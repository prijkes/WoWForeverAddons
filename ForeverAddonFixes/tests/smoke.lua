-- Smoke test against GearQuest's real Core.lua and Log.lua (cases 1-8).
-- From the addon root:  luajit tests/smoke.lua
-- Another GearQuest copy:  AFIX_GQ_PATH=<GearQuestForever folder> luajit tests/smoke.lua
package.path = "tests/lib/?.lua;" .. package.path
local E = require("env")

local GQ = os.getenv("AFIX_GQ_PATH") or "../GearQuestForever"
local ID = "GearQuestForever.hiddenChatText"
local FIX_VAR = "ForeverAddonFixes_fix_GearQuestForever_hiddenChatText"
local LOOT = "You receive loot: |cff9d9d9d|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r."
local SKILL = "Your skill in Defense has increased to 45."

local checks, problems = 0, 0
local function check(ok, what)
    checks = checks + 1
    if not ok then problems = problems + 1; print("PROBLEM: " .. what) end
end

local function TocVersion(dir)
    local f = io.open(dir .. "/GearQuestForever.toc", "r")
    if not f then return nil end
    for line in f:lines() do
        local v = line:match("^## Version:%s*(.-)%s*$")
        if v then f:close(); return v end
    end
    f:close()
end

local VERSION = TocVersion(GQ)
if not VERSION then
    print("SKIP: no GearQuestForever at " .. GQ)
    os.exit(0)
end
print(("GearQuest %s at %s"):format(VERSION, GQ))

-- A world with GearQuest's real files, loaded as the client does: files, then saved variables,
-- then ADDON_LOADED. opts: withFix, oursFirst, settings, saved, version.
local function World(opts)
    opts = opts or {}
    local w = E.new({ settings = opts.settings })
    local function LoadGearQuest()
        w:loadFiles("GearQuestForever", {}, { "Core.lua", "Log.lua" }, GQ)
        w.env.GearQuestForeverDB, w.env.GearQuestForeverCharDB = {}, {}
        w:loadTarget("GearQuestForever", opts.version or VERSION)
    end
    if opts.oursFirst then
        w:loadOurs({ saved = opts.saved })
        w.statusBeforeGearQuest = w.ns.StatusText(w.ns.fixes[1])
        w:loadFiles("GearQuestForever", {}, { "Core.lua", "Log.lua" }, GQ)
        w.env.GearQuestForeverDB, w.env.GearQuestForeverCharDB = {}, {}
        w:loadTarget("GearQuestForever", opts.version or VERSION, opts.lateLoadedFlag)
    else
        LoadGearQuest()
        w.gqOriginal = w.env.GearQuest.Log.HandleCraftChatMessage
        if opts.withFix then w:loadOurs({ saved = opts.saved }) end
    end
    w.env.GearQuest.Log:EnsureTrackerEvents()
    local tracker = w.env.GearQuest.Log.trackerFrame
    function w:chat(event, msg) return pcall(tracker.scripts.OnEvent, tracker, event, msg) end
    function w:fix() return self.ns and self.ns.fixes[1] end
    return w
end

local function RaisesSecret(w, event)
    local ok, err = w:chat(event or "CHAT_MSG_SKILL", w:secret())
    return not ok and tostring(err):find("secret", 1, true) ~= nil, err
end

-- 1. Red: without our addon, GearQuest's real handler throws on a hidden message.
do
    local w = World()
    local red, err = RaisesSecret(w)
    check(red, "case 1: expected GearQuest's secret error without the fix, got " .. tostring(err))
end

-- 2. Green: with our addon, hidden skill and loot lines are skipped.
do
    local w = World({ withFix = true })
    local fix = w:fix()
    check(w:chat("CHAT_MSG_SKILL", w:secret()), "case 2: a hidden skill line still raised an error")
    check(fix.state.skipped == 1, "case 2: skipped should be 1, is " .. fix.state.skipped)
    check(w:chat("CHAT_MSG_LOOT", w:secret()), "case 2: a hidden loot line still raised an error")
    check(fix.state.skipped == 2, "case 2: skipped should be 2, is " .. fix.state.skipped)
    collectgarbage(); collectgarbage()
    check(next(w.secrets) == nil, "case 2: a skipped message is still referenced somewhere")
    check(w.ns.StatusText(fix):find("^active %(GearQuestForever " .. VERSION:gsub("%p", "%%%0") .. "%), skipped 2") ~= nil,
        "case 2: status " .. w.ns.StatusText(fix))
end

-- 3. Pass-through, as a differential test: readable lines change GearQuest's data exactly as without us.
do
    local a, b = World(), World({ withFix = true })
    for _, w in ipairs({ a, b }) do
        check(w:chat("CHAT_MSG_LOOT", LOOT), "case 3: readable loot line errored")
        check(w:chat("CHAT_MSG_SKILL", SKILL), "case 3: readable skill line errored")
    end
    for _, name in ipairs({ "GearQuestForeverDB", "GearQuestForeverCharDB" }) do
        local diffs = E.deepDiff(a.env[name], b.env[name], name)
        check(#diffs == 0, "case 3: " .. name .. " differs: " .. table.concat(diffs, "; "))
    end
    check(#a.timers == #b.timers, ("case 3: timers %d vs %d"):format(#a.timers, #b.timers))
    for i = 1, math.min(#a.timers, #b.timers) do
        check(a.timers[i].delay == b.timers[i].delay, "case 3: timer delay differs")
    end
    check(b:fix().state.skipped == 0, "case 3: a readable line was counted as skipped")
    check(E.holds(a.env.GearQuestForeverDB, 2589) or E.holds(a.env.GearQuestForeverCharDB, 2589),
        "case 3: GearQuest didn't record the looted item, so the comparison proves nothing")
end

-- 4. Off brings the error back and restores GearQuest's own method; on fixes it again, one wrapper.
do
    local w = World({ withFix = true })
    local log = w.env.GearQuest.Log
    w:slash("off 1")
    check(log.HandleCraftChatMessage == w.gqOriginal, "case 4: off didn't restore GearQuest's method")
    check((RaisesSecret(w)), "case 4: off should bring the error back")
    w:slash("on 1")
    check(w:chat("CHAT_MSG_SKILL", w:secret()), "case 4: on should fix it again")
    w:slash("off 1")
    check(log.HandleCraftChatMessage == w.gqOriginal, "case 4: more than one wrapper after on")
end

-- 5. Load order: our addon first, GearQuest later; also when IsAddOnLoaded only says "loaded"
-- after GearQuest's own ADDON_LOADED (that timing is unverified).
for _, late in ipairs({ false, true }) do
    local w = World({ oursFirst = true, lateLoadedFlag = late })
    local label = "case 5" .. (late and " (late flag)" or "") .. ": "
    check(w.statusBeforeGearQuest == "waiting: GearQuestForever not loaded", label .. "before: " .. tostring(w.statusBeforeGearQuest))
    check(w.ns.FixState(w:fix()) == "active", label .. "not active after GearQuest loaded")
    check(w:chat("CHAT_MSG_SKILL", w:secret()), label .. "a hidden line still raised an error")
end

-- 6. The panel: registered last, and its checkbox switches the real fix.
do
    local w = World({ withFix = true })
    check(w.ns.GetPanel().ok and #w.S.registered == 1 and w.S.log[#w.S.log] == "RegisterAddOnCategory", "case 6: panel not built as specified")
    local s = w.S.registry[FIX_VAR]
    s:SetValue(false)
    check((RaisesSecret(w)), "case 6: unticking should bring the error back")
    s:SetValue(true)
    check(w:chat("CHAT_MSG_SKILL", w:secret()), "case 6: ticking should fix it again")
    w.S.registry.ForeverAddonFixes_debug:SetValue(true)
    w.S.ResetToDefaults(w.S.categories[1])
    check(w.ns.GetDB().debug == false and w.ns.GetDB().fixes[ID].enabled == true, "case 6: Defaults")
    check(#w.S.callbackErrors == 0, "case 6: a panel callback raised an error: " .. tostring(w.S.callbackErrors[1]))
end

-- 7. A broken panel in all variants: a load line, and the slash command still switches the fix.
for _, mode in ipairs({ false, "throw", "latethrow", "wrongcategory", "wrongsetting", "wronginitializer", "noid" }) do
    local w = World({ withFix = true, settings = mode })
    local label = "case 7 (" .. tostring(mode) .. "): "
    check(not w.ns.GetPanel().ok, label .. "panel reported ok")
    check(w:printsMatching("the options panel couldn't be built") == 1, label .. "no load line")
    if w.S then check(#w.S.registered == 0, label .. "a category was registered") end
    w:slash("off 1")
    check((RaisesSecret(w)), label .. "off didn't bring the error back")
    w:slash("on 1")
    check(w:chat("CHAT_MSG_SKILL", w:secret()), label .. "on didn't fix it")
end

-- 8. An untested GearQuest version: flagged in the status, one notice, not repeated next session.
do
    local w = World({ withFix = true, version = "0.2.99-beta" })
    check(w.ns.StatusText(w:fix()):find("untested with this version", 1, true) ~= nil, "case 8: status not flagged")
    check(w:printsMatching("GearQuestForever is now 0%.2%.99%-beta;") == 1, "case 8: expected one notice")
    local w2 = World({ withFix = true, version = "0.2.99-beta", saved = E.deepCopy(w.ns.GetDB()) })
    check(w2:printsMatching("is now") == 0, "case 8: the notice repeated in the next session")
    check(w2:chat("CHAT_MSG_SKILL", w2:secret()), "case 8: the fix isn't active on an untested version")
end

print(("%d checks, %d problems"):format(checks, problems))
os.exit(problems == 0 and 0 or 1)
