-- The options panel against a recording Settings API that copies the real behaviour.
local T = ...
local E = require("env")

local ID = "GearQuestForever.hiddenChatText"
local FIX_VAR = "ForeverAddonFixes_fix_GearQuestForever_hiddenChatText"

local function Boot(opts)
    opts = opts or {}
    local w = E.new({ settings = opts.settings })
    w.env.GearQuest = { Log = { HandleCraftChatMessage = function() end } }
    w.loaded.GearQuestForever = true
    w.versions.GearQuestForever = "0.2.11-beta"
    local ns = w:loadOurs({ saved = opts.saved })
    return w, ns, ns.fixes[1]
end

T.test("the category, four settings and four checkboxes, registered last", function()
    local w, ns = Boot()
    local S = w.S
    T.eq(#S.categories, 1)
    local c = S.categories[1]
    T.eq(c:GetName(), "Forever Addon Fixes")
    T.eq(ns.GetPanel().ok, true)
    T.eq(ns.GetPanel().categoryID, c:GetID())
    T.eq(#S.registered, 1)
    T.eq(S.registered[1], c)
    T.eq(S.log[#S.log], "RegisterAddOnCategory", "the category is registered last")
    local db = ns.GetDB()
    local AL_ID = "AtlasLootClassic.hiddenVendor"
    local expect = {
        { FIX_VAR, "enabled", db.fixes[ID], true, "GearQuest: skip hidden chat text" },
        { "ForeverAddonFixes_fix_AtlasLootClassic_hiddenVendor", "enabled", db.fixes[AL_ID], true, "AtlasLoot: skip scans of hidden vendors" },
        { "ForeverAddonFixes_notices", "notices", db, true, "Chat notices" },
        { "ForeverAddonFixes_debug", "debug", db, false, "Debug: report skips" },
    }
    T.eq(#c.settings, 4)
    T.truthy(c.initializers[2].tooltip:find("Tested with Forever 1.60.1 (its releases share one version string).", 1, true))
    for i, e in ipairs(expect) do
        local s = c.settings[i]
        T.eq(s.variable, e[1]); T.eq(s.key, e[2]); T.eq(s.tbl, e[3]); T.eq(s.default, e[4]); T.eq(s.name, e[5])
        T.eq(c.initializers[i]:GetSetting(), s)
    end
    local tip = c.initializers[1].tooltip
    T.truthy(tip:find("GearQuest tries to read it", 1, true))
    T.truthy(tip:find("Tested with 0.2.6-beta and 0.2.11-beta", 1, true))
    T.truthy(tip:find("/afix status", 1, true))
    T.eq(#w.prints, 0, "nothing printed when the panel builds")
end)

T.test("the checkbox switches the fix; settings stay in step with the saved table", function()
    local w, ns, fix = Boot()
    local s = w.S.registry[FIX_VAR]
    s:SetValue(false)
    T.eq(ns.GetDB().fixes[ID].enabled, false)
    T.eq(ns.FixState(fix), "off")
    s:SetValue(true)
    T.eq(ns.FixState(fix), "active")
    w.S.registry.ForeverAddonFixes_debug:SetValue(true)
    T.eq(ns.GetDB().debug, true)
    T.eq(#w.S.callbackErrors, 0, "no callback raised an error")
end)

T.test("Defaults (These Settings) brings back fix on, notices on, debug off", function()
    local w, ns, fix = Boot({ saved = { fixes = { [ID] = { enabled = false } }, notices = false, debug = true } })
    T.eq(ns.FixState(fix), "off")
    w.S.ResetToDefaults(w.S.categories[1])
    local db = ns.GetDB()
    T.eq(db.fixes[ID].enabled, true); T.eq(db.notices, true); T.eq(db.debug, false)
    T.eq(ns.FixState(fix), "active")
end)

T.test("saved values survive registration (the default is written only when nil)", function()
    local _, ns = Boot({ saved = { debug = true, notices = false } })
    T.eq(ns.GetDB().debug, true)
    T.eq(ns.GetDB().notices, false)
end)

T.test("building twice fails on the duplicate name, like the real API", function()
    local _, ns = Boot()
    local ok, err = pcall(ns.BuildOptions, ns.GetDB())
    T.falsy(ok)
    T.truthy(tostring(err):find("was previously registered", 1, true))
end)

T.test("a broken panel and a failing print together still let the fix activate", function()
    local w = E.new({ settings = false })
    w.env.GearQuest = { Log = { HandleCraftChatMessage = function() end } }
    w.loaded.GearQuestForever, w.versions.GearQuestForever = true, "0.2.11-beta"
    w.env.print = function() error("no chat right now") end
    local ok, err = pcall(w.loadOurs, w)
    T.truthy(ok, tostring(err))
    T.eq(w.ns.FixState(w.ns.fixes[1]), "active")
end)

-- A broken panel: a (no API), b (early and late throw), c (wrong objects).
local BROKEN = {
    { settings = false, why = "the game's Settings API is missing" },
    { settings = "throw", why = "Settings exploded" },
    { settings = "latethrow", why = "late Settings failure" },
    { settings = "wrongcategory", why = "the settings category wasn't created" },
    { settings = "wrongsetting", why = "the setting " .. FIX_VAR .. " wasn't created" },
    { settings = "wronginitializer", why = "the checkbox for " .. FIX_VAR .. " wasn't created" },
    { settings = "noid", why = "the settings category wasn't created" },
}

for _, case in ipairs(BROKEN) do
    T.test("broken panel (" .. tostring(case.settings) .. "): load line, no category, switching still works", function()
        local w, ns, fix = Boot({ settings = case.settings })
        T.eq(ns.GetPanel().ok, false)
        T.eq(w:printsMatching("the options panel couldn't be built %(.*" .. case.why:gsub("%p", "%%%0") .. ".*%); use /afix status and /afix on|off%."), 1)
        if w.S then
            T.eq(#w.S.registered, 0, "no category registered")
            T.eq(w.S.callbacks.SomeOtherAddon_option, nil, "another addon's setting never gets our callback")
        end
        w:slash("off 1")
        T.eq(ns.FixState(fix), "off")
        T.eq(ns.GetDB().fixes[ID].enabled, false)
        w:slash("on 1")
        T.eq(ns.FixState(fix), "active")
        w:slash("debug on")
        T.eq(ns.GetDB().debug, true)
        w:clearPrints()
        w:slash("")
        T.truthy(w.prints[1]:find("the options panel is unavailable", 1, true))
    end)
end
