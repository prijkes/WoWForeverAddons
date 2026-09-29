-- Core: Readable, saved settings, state precedence, notices, the switch path and the slash command.
local T = ...
local E = require("env")

local CORE_ONLY = { "Core.lua", "Options.lua" }

-- A fix around env.Target.Handle, built like the GearQuest one; opts tune its behaviour.
local function TestFix(opts)
    opts = opts or {}
    local original, wrapper
    local fix
    fix = {
        id = opts.id or "Test.fix", addon = opts.addon or "TestTarget", title = opts.title or "Test fix",
        skipText = "Test skipped a message", description = "A test fix.",
        testedVersions = opts.tested or { "1.0" },
        needed = opts.needed,
        install = function(f)
            fix.installs = (fix.installs or 0) + 1
            if opts.installError then error("install exploded") end
            if opts.installFails then return false, "the target has changed" end
            local target = f.env.Target
            original = target.Handle
            wrapper = function(self, msg, ...)
                if msg and fix.state.enabled and not f.ns.Readable(msg) then fix:CountSkip(); return end
                return original(self, msg, ...)
            end
            target.Handle = wrapper
            return true
        end,
        uninstall = function(f)
            fix.uninstalls = (fix.uninstalls or 0) + 1
            if opts.uninstallError then error("uninstall exploded") end
            if f.env.Target.Handle == wrapper then f.env.Target.Handle = original; return true end
            return false
        end,
    }
    if opts.noUninstall then fix.uninstall = nil end
    return fix
end

-- Boots a world with test fixes. opts: fixes (list), saved, settings, loaded (target loaded at
-- start, default true), version, files.
local function Boot(opts)
    opts = opts or {}
    local w = E.new({ settings = opts.settings })
    w.env.Target = { calls = 0, Handle = function(self, msg, ...) self.calls = self.calls + 1; self.last = { msg, ... } return "result", 2 end }
    w.env.Target.original = w.env.Target.Handle
    if opts.loaded ~= false then w.loaded.TestTarget = true; w.versions.TestTarget = opts.version or "1.0" end
    local fixes = opts.fixes or { TestFix() }
    w:loadOurs({ files = opts.files or CORE_ONLY, saved = opts.saved, beforeLoad = function(ns)
        for _, fix in ipairs(fixes) do fix.env, fix.ns = w.env, ns; ns.RegisterFix(fix) end
    end })
    return w, w.ns, fixes[1]
end

T.test("Readable: plain text yes, a secret no", function()
    local w, ns = Boot()
    T.truthy(ns.Readable("Your skill in Defense has increased to 45."))
    T.falsy(ns.Readable(w:secret()))
end)

T.test("Readable: a throwing check counts as not readable", function()
    local w, ns = Boot()
    w.env.issecretvalue = function() error("no secrets for you") end
    T.falsy(ns.Readable("plain"))
    w.env.issecretvalue = function() error() end -- an error whose value is nil
    T.falsy(ns.Readable("plain"))
    w.env.issecretvalue = function() return false end
    w.env.canaccessvalue = function() error("nope") end
    T.falsy(ns.Readable("plain"))
end)

T.test("Readable: either check flagging the value is enough", function()
    local w, ns = Boot()
    w.env.issecretvalue = function() return false end
    w.env.canaccessvalue = function() return false end
    T.falsy(ns.Readable("plain"))
end)

T.test("Readable: the canaccessvalue-only branch, and no checks at all", function()
    local w, ns = Boot()
    local secret = w:secret()
    w.env.issecretvalue = nil
    T.falsy(ns.Readable(secret))
    T.truthy(ns.Readable("plain"))
    w.env.canaccessvalue = nil
    T.truthy(ns.Readable("plain"))
end)

T.test("RegisterFix rejects a fix without an id, addon, title or install", function()
    local _, ns = Boot()
    local install = function() return true end
    T.falsy(pcall(ns.RegisterFix, { addon = "A", title = "T", install = install }), "no id")
    T.falsy(pcall(ns.RegisterFix, { id = "x1", title = "T", install = install }), "no addon")
    T.falsy(pcall(ns.RegisterFix, { id = "x2", addon = "A", install = install }), "no title")
    T.falsy(pcall(ns.RegisterFix, { id = "x3", addon = "A", title = "T" }), "no install")
    T.falsy(pcall(ns.RegisterFix, { id = "Test.fix", addon = "A", title = "T", install = install }), "duplicate id")
    T.truthy(pcall(ns.RegisterFix, { id = "x4", addon = "A", title = "T", install = install }), "complete")
end)

T.test("InitDB: defaults for a first run, stored in the saved-variables global", function()
    local w, ns = Boot()
    local db = ns.GetDB()
    T.eq(w.env.ForeverAddonFixesDB, db)
    T.eq(db.fixes["Test.fix"].enabled, true)
    T.eq(db.notices, true)
    T.eq(db.debug, false)
    T.eq(type(db.noticedVersions["Test.fix"]), "table")
end)

T.test("InitDB: wrong types are repaired, unknown keys kept", function()
    local saved = { fixes = { ["Test.fix"] = true, Other = { enabled = false, x = 1 } }, notices = 1, debug = "yes",
        noticedVersions = { ["Test.fix"] = "1.2" }, extra = "kept" }
    local _, ns = Boot({ saved = saved })
    local db = ns.GetDB()
    T.eq(db, saved, "the saved table itself is repaired")
    T.eq(type(db.fixes["Test.fix"]), "table")
    T.eq(db.fixes["Test.fix"].enabled, true)
    T.eq(db.notices, true)
    T.eq(db.debug, false)
    T.eq(type(db.noticedVersions["Test.fix"]), "table")
    T.eq(db.extra, "kept")
    T.eq(db.fixes.Other.x, 1)
    local _, ns2 = Boot({ saved = { fixes = "broken", noticedVersions = 5 } })
    T.eq(ns2.GetDB().fixes["Test.fix"].enabled, true)
    T.eq(type(ns2.GetDB().noticedVersions), "table")
    local _, ns3 = Boot({ saved = "not a table" })
    T.eq(ns3.GetDB().notices, true)
end)

T.test("saved 'off' is honoured at load: nothing installed", function()
    local _, ns, fix = Boot({ saved = { fixes = { ["Test.fix"] = { enabled = false } } } })
    T.eq(fix.installs, nil)
    T.eq(ns.StatusText(fix), "off")
end)

T.test("state precedence: not needed beats off", function()
    local _, ns, fix = Boot({ fixes = { TestFix({ needed = function() return false end }) },
        saved = { fixes = { ["Test.fix"] = { enabled = false } } } })
    T.eq(ns.StatusText(fix), "not needed on this client")
    T.eq(fix.installs, nil, "a fix that isn't needed is never installed")
end)

T.test("a target that is still loading counts as not loaded (IsAddOnLoaded's second value)", function()
    local w, ns, fix = Boot({ loaded = false })
    w.loading.TestTarget = true
    w:fire("ADDON_LOADED", "SomethingElse")
    T.eq(ns.StatusText(fix), "waiting: TestTarget not loaded")
    T.eq(fix.installs, nil)
end)

T.test("the target's own ADDON_LOADED is proof enough, even if IsAddOnLoaded still says no", function()
    local w, ns, fix = Boot({ loaded = false })
    w:loadTarget("TestTarget", "1.0", true)
    T.eq(fix.installs, 1)
    T.eq(ns.StatusText(fix), "active (TestTarget 1.0), skipped 0 this session")
end)

T.test("state precedence: off beats waiting", function()
    local _, ns, fix = Boot({ loaded = false, saved = { fixes = { ["Test.fix"] = { enabled = false } } } })
    T.eq(ns.StatusText(fix), "off")
end)

T.test("waiting until the target loads, then active", function()
    local w, ns, fix = Boot({ loaded = false })
    T.eq(ns.StatusText(fix), "waiting: TestTarget not loaded")
    T.eq(fix.installs, nil)
    w:loadTarget("TestTarget", "1.0")
    T.eq(ns.StatusText(fix), "active (TestTarget 1.0), skipped 0 this session")
    T.eq(fix.installs, 1)
end)

T.test("not applied: install returns a reason, once-per-session notice", function()
    local w, ns, fix = Boot({ fixes = { TestFix({ installFails = true }) } })
    T.eq(ns.StatusText(fix), "not applied: the target has changed")
    T.eq(w:printsMatching('"Test fix" is not in place: the target has changed%. The fix may no longer be needed%.'), 1)
    ns.SetFixEnabled("Test.fix", false)
    ns.SetFixEnabled("Test.fix", true)
    T.eq(fix.installs, 2, "switching on retries")
    T.eq(w:printsMatching("is not in place"), 1, "the notice appears once per session")
end)

T.test("not applied: an install error is caught", function()
    local w, ns, fix = Boot({ fixes = { TestFix({ installError = true }) } })
    T.truthy(ns.StatusText(fix):find("^not applied: error: .*install exploded"))
    T.eq(w:printsMatching("is not in place"), 1)
end)

T.test("not applied: no notice with notices off", function()
    local w, ns, fix = Boot({ fixes = { TestFix({ installFails = true }) }, saved = { notices = false } })
    T.eq(ns.FixState(fix), "notapplied")
    T.eq(w:printsMatching("is not in place"), 0)
end)

T.test("active: version, skip count, untested and unknown versions", function()
    local w, ns, fix = Boot()
    w.env.Target:Handle(w:secret())
    w.env.Target:Handle(w:secret())
    T.eq(ns.StatusText(fix), "active (TestTarget 1.0), skipped 2 this session")
    w.versions.TestTarget = "2.0"
    T.eq(ns.StatusText(fix), "active (TestTarget 2.0), skipped 2 this session, untested with this version")
    w.versions.TestTarget = ""
    T.eq(ns.StatusText(fix), "active (TestTarget unknown), skipped 2 this session, untested with this version")
    w.versions.TestTarget = nil
    T.eq(ns.StatusText(fix), "active (TestTarget unknown), skipped 2 this session, untested with this version")
end)

T.test("off restores the original; on installs exactly one wrapper again", function()
    local w, ns, fix = Boot()
    local original = w.env.Target.original
    T.truthy(w.env.Target.Handle ~= original, "installed at load")
    ns.SetFixEnabled("Test.fix", false)
    T.eq(w.env.Target.Handle, original, "restored")
    T.eq(fix.uninstalls, 1)
    T.eq(ns.StatusText(fix), "off")
    ns.SetFixEnabled("Test.fix", true)
    T.eq(fix.installs, 2)
    T.truthy(w.env.Target.Handle ~= original, "wrapped again")
    ns.SetFixEnabled("Test.fix", false)
    T.eq(w.env.Target.Handle, original, "one wrapper: a single uninstall restores the original")
end)

T.test("off with another wrapper on top passes through; on adds no second wrapper", function()
    local w, ns, fix = Boot()
    local ours = w.env.Target.Handle
    local outer = function(self, msg, ...) return ours(self, msg, ...) end
    w.env.Target.Handle = outer
    ns.SetFixEnabled("Test.fix", false)
    T.eq(ns.StatusText(fix), "off (passing through until /reload)")
    local secret = w:secret()
    w.env.Target:Handle(secret)
    T.eq(w.env.Target.calls, 1, "passed through to the original")
    T.truthy(rawequal(w.env.Target.last[1], secret))
    ns.SetFixEnabled("Test.fix", true)
    T.eq(fix.installs, 1, "no second install")
    T.eq(w.env.Target.Handle, outer)
    w.env.Target:Handle(w:secret())
    T.eq(w.env.Target.calls, 1, "skipped again")
    T.eq(fix.state.skipped, 1)
end)

T.test("uninstalling a fix that isn't installed does nothing", function()
    local _, ns, fix = Boot({ loaded = false })
    ns.SetFixEnabled("Test.fix", false)
    T.eq(fix.uninstalls, nil)
    T.eq(ns.StatusText(fix), "off")
end)

T.test("a throwing uninstall is caught and leaves a pass-through (panel and no panel)", function()
    for _, withPanel in ipairs({ true, false }) do
        local opts = { fixes = { TestFix({ uninstallError = true }) } }
        if not withPanel then opts.settings = false end
        local w, ns, fix = Boot(opts)
        T.truthy(pcall(ns.SetFixEnabled, "Test.fix", false), withPanel and "panel" or "no panel")
        T.eq(ns.StatusText(fix), "off (passing through until /reload)")
        w.env.Target:Handle(w:secret())
        T.eq(w.env.Target.calls, 1)
        T.truthy(pcall(w.slash, w, "on 1"), "the slash command survives too")
    end
end)

T.test("a fix without uninstall stays as a pass-through", function()
    local _, ns, fix = Boot({ fixes = { TestFix({ noUninstall = true }) } })
    ns.SetFixEnabled("Test.fix", false)
    T.eq(ns.StatusText(fix), "off (passing through until /reload)")
end)

T.test("one SetFixEnabled call gives exactly one OnFixSwitched call (panel and fallback)", function()
    for _, withPanel in ipairs({ true, false }) do
        local opts = {}
        if not withPanel then opts.settings = false end
        local w, ns = Boot(opts)
        T.eq(ns.GetPanel().ok, withPanel)
        local n, orig = 0, ns.OnFixSwitched
        ns.OnFixSwitched = function(...) n = n + 1; return orig(...) end
        ns.SetFixEnabled("Test.fix", false)
        T.eq(n, 1, withPanel and "panel" or "fallback")
        if withPanel then T.eq(w.S.setCalls.ForeverAddonFixes_fix_Test_fix, 1, "switched through the panel's setting") end
        ns.SetFixEnabled("Test.fix", false)
        T.eq(n, 2, "an unchanged value still gives exactly one call")
    end
end)

T.test("repeated on through the panel installs once (idempotent)", function()
    local w, ns, fix = Boot()
    local setting = ns.GetPanel().settings["Test.fix"]
    setting:SetValue(true)
    setting:SetValue(true)
    T.eq(fix.installs, 1)
    T.eq(#w.S.callbacks["ForeverAddonFixes_fix_Test_fix"], 1)
end)

T.test("fallback: a SetValue that throws still switches", function()
    local _, ns, fix = Boot()
    ns.GetPanel().settings["Test.fix"].SetValue = function() error("panel broke") end
    ns.SetFixEnabled("Test.fix", false)
    T.eq(ns.GetDB().fixes["Test.fix"].enabled, false)
    T.eq(ns.StatusText(fix), "off")
end)

T.test("version notice: none for a tested version", function()
    local w = Boot()
    T.eq(w:printsMatching("was tested with"), 0)
end)

T.test("version notice: once per version, remembered across sessions, A -> B -> A", function()
    local w, ns = Boot({ version = "2.0" })
    T.eq(w:printsMatching('^|cff33ff99Forever Addon Fixes|r: TestTarget is now 2%.0; "Test fix" was tested with 1%.0%. It is still active%.'), 1)
    ns.SetFixEnabled("Test.fix", false)
    ns.SetFixEnabled("Test.fix", true)
    T.eq(w:printsMatching("is now 2%.0"), 1, "not again in the same session")
    local saved = E.deepCopy(ns.GetDB())
    local w2, ns2 = Boot({ version = "2.0", saved = saved })
    T.eq(w2:printsMatching("is now"), 0, "not again next session")
    local w3, ns3 = Boot({ version = "3.0", saved = E.deepCopy(ns2.GetDB()) })
    T.eq(w3:printsMatching("is now 3%.0"), 1)
    local w4 = Boot({ version = "2.0", saved = E.deepCopy(ns3.GetDB()) })
    T.eq(w4:printsMatching("is now"), 0, "going back to 2.0 doesn't announce it again")
end)

T.test("version notice: with notices off it isn't recorded, so it shows once they're on", function()
    local w, ns = Boot({ version = "2.0", saved = { notices = false } })
    T.eq(w:printsMatching("is now"), 0)
    T.eq(ns.GetDB().noticedVersions["Test.fix"]["2.0"], nil)
    local saved = E.deepCopy(ns.GetDB())
    saved.notices = true
    local w2 = Boot({ version = "2.0", saved = saved })
    T.eq(w2:printsMatching("is now 2%.0"), 1)
end)

T.test("version notice: only when the fix becomes active, not on a repeated on or Defaults", function()
    local w, ns = Boot({ version = "2.0", saved = { notices = false } })
    T.eq(w:printsMatching("is now"), 0)
    w:slash("notices on")
    w:slash("on 1")
    w.S.ResetToDefaults(w.S.categories[1])
    T.eq(w:printsMatching("is now"), 0, "the fix was already active")
    w:slash("off 1")
    w:slash("on 1")
    T.eq(w:printsMatching("is now 2%.0"), 1, "becoming active again checks")
    T.eq(#w.S.callbackErrors, 0)
end)

T.test("version notice: a failing print records nothing and doesn't break loading", function()
    local w = E.new()
    w.env.Target = { Handle = function() end }
    w.loaded.TestTarget, w.versions.TestTarget = true, "2.0"
    local second = TestFix({ id = "Test.second", addon = "TestTarget", title = "Second" })
    w.env.print = function() error("no chat right now") end
    local ns = w:loadOurs({ files = CORE_ONLY, beforeLoad = function(ns)
        for _, fix in ipairs({ TestFix(), second }) do fix.env, fix.ns = w.env, ns; ns.RegisterFix(fix) end
    end })
    T.eq(ns.FixState(second), "active", "a later fix still activates")
    T.eq(ns.GetDB().noticedVersions["Test.fix"]["2.0"], nil, "not recorded as announced")
end)

T.test("not-applied notice: a failing print isn't counted as shown", function()
    local w = E.new()
    w.loaded.TestTarget = true
    w.env.print = function() error("no chat right now") end
    local fix = TestFix({ installFails = true })
    local ns = w:loadOurs({ files = CORE_ONLY, beforeLoad = function(ns) fix.env, fix.ns = w.env, ns; ns.RegisterFix(fix) end })
    w.env.print = function(...) w.prints[#w.prints + 1] = table.concat({ ... }, " ") end
    ns.SetFixEnabled("Test.fix", false)
    ns.SetFixEnabled("Test.fix", true)
    T.eq(w:printsMatching("is not in place"), 1, "shown once printing works")
end)

T.test("version notice: a missing version is 'unknown', once", function()
    local w, ns = Boot({ version = "" })
    T.eq(w:printsMatching("TestTarget is now unknown;"), 1)
    local w2 = Boot({ version = "", saved = E.deepCopy(ns.GetDB()) })
    T.eq(w2:printsMatching("is now"), 0)
end)

T.test("version notice: never while off, waiting or not applied; shown on switch-on", function()
    local w, ns = Boot({ version = "2.0", saved = { fixes = { ["Test.fix"] = { enabled = false } } } })
    T.eq(w:printsMatching("is now"), 0, "off")
    ns.SetFixEnabled("Test.fix", true)
    T.eq(w:printsMatching("is now 2%.0"), 1, "becoming active announces it")
    local w2 = Boot({ loaded = false })
    w2.versions.TestTarget = "2.0"
    T.eq(w2:printsMatching("is now"), 0, "waiting")
    w2:loadTarget("TestTarget", "2.0")
    T.eq(w2:printsMatching("is now 2%.0"), 1, "the target loading announces it")
    local w3 = Boot({ version = "2.0", fixes = { TestFix({ installFails = true }) } })
    T.eq(w3:printsMatching("is now"), 0, "not applied")
end)

T.test("slash: bare /afix and /afix options open the panel, not in combat", function()
    local w, ns = Boot()
    w:slash("")
    T.eq(w.S.opened, ns.GetPanel().categoryID)
    w.S.opened = nil
    w:slash("  OPTIONS ")
    T.eq(w.S.opened, ns.GetPanel().categoryID)
    w.S.opened = nil
    w.combat = true
    w:slash("")
    T.eq(w.S.opened, nil)
    T.eq(w:printsMatching("options can't be opened during combat"), 1)
end)

T.test("slash: a panel that fails to open says so", function()
    local w = Boot()
    w.S.OpenToCategory = function() error("the panel is busy") end
    T.truthy(pcall(w.slash, w, ""))
    T.truthy(w:lastPrint():find("couldn't open the options panel: .*the panel is busy"))
end)

T.test("slash: status lists each fix and the settings", function()
    local w = Boot()
    w:clearPrints()
    w:slash("status")
    T.eq(w.prints[1], "|cff33ff99Forever Addon Fixes|r: 1. Test fix: active (TestTarget 1.0), skipped 0 this session")
    T.eq(w.prints[2], "|cff33ff99Forever Addon Fixes|r: notices on, debug off")
end)

T.test("slash: on/off by number and by id, then the fix's status", function()
    local w, ns, fix = Boot()
    w:slash("off 1")
    T.eq(ns.FixState(fix), "off")
    T.eq(w:lastPrint(), "|cff33ff99Forever Addon Fixes|r: 1. Test fix: off")
    w:slash("on TEST.FIX")
    T.eq(ns.FixState(fix), "active")
    T.eq(ns.GetDB().fixes["Test.fix"].enabled, true)
end)

T.test("slash: an unknown or missing fix says so instead of the help", function()
    local w = Boot()
    w:slash("off 9")
    T.eq(w:lastPrint(), "|cff33ff99Forever Addon Fixes|r: no fix 9; /afix status lists them.")
    w:slash("on")
    T.truthy(w:lastPrint():find("which fix%?"))
end)

T.test("slash: notices and debug", function()
    local w, ns = Boot()
    w:slash("notices off")
    T.eq(ns.GetDB().notices, false)
    T.eq(w:lastPrint(), "|cff33ff99Forever Addon Fixes|r: notices off")
    w:slash("debug on")
    T.eq(ns.GetDB().debug, true)
    T.eq(ns.GetPanel().settings.debug:GetValue(), true, "the panel's setting is in step")
    T.eq(w.S.setCalls.ForeverAddonFixes_debug, 1, "switched through the panel's setting")
    T.eq(w.S.setCalls.ForeverAddonFixes_notices, 1)
end)

T.test("slash: unknown input and bad values print the help", function()
    local w = Boot()
    w:clearPrints()
    w:slash("debug maybe")
    T.truthy(#w.prints >= 5)
    T.truthy(w.prints[1]:find("/afix or /afix options %- open the options panel"))
    T.truthy(w.prints[3]:find("the fix's id works too", 1, true))
    w:clearPrints()
    w:slash("bogus")
    T.truthy(w.prints[2]:find("/afix status"))
end)

T.test("debug line: counted, never the message, and a failing print can't break the call", function()
    local w, ns, fix = Boot({ saved = { debug = true } })
    local secret = w:secret()
    w:clearPrints()
    w.env.Target:Handle(secret)
    T.eq(w:lastPrint(), "|cff33ff99Forever Addon Fixes|r: Test skipped a message (1 this session)")
    w.env.print = function() error("print is broken") end
    T.truthy(pcall(w.env.Target.Handle, w.env.Target, w:secret()))
    T.eq(fix.state.skipped, 2)
    T.falsy(E.holds(ns.GetDB(), secret), "the message is never stored")
    T.falsy(E.holds(fix.state, secret))
end)
