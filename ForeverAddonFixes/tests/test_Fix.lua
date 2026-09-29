-- The GearQuest fix against a fake GearQuest table; smoke.lua runs it against the real one.
local T = ...
local E = require("env")

local ID = "GearQuestForever.hiddenChatText"

-- A fake GearQuest whose HandleCraftChatMessage records its calls and returns values.
local function Boot(opts)
    opts = opts or {}
    local w = E.new()
    local log = { calls = {} }
    function log.HandleCraftChatMessage(self, msg, ...)
        log.calls[#log.calls + 1] = { self = self, msg = msg, n = select("#", ...), ... }
        return "first", "second"
    end
    log.original = log.HandleCraftChatMessage
    if opts.gearquest ~= false then w.env.GearQuest = opts.gearquest or { Log = log } end
    if opts.loaded ~= false then w.loaded.GearQuestForever = true; w.versions.GearQuestForever = opts.version or "0.2.11-beta" end
    local ns = w:loadOurs({ saved = opts.saved })
    return w, ns, ns.fixes[1], log
end

T.test("registered with its id, target and tested versions", function()
    local _, ns, fix = Boot()
    T.eq(#ns.fixes, 2, "GearQuest first, then AtlasLoot, in toc order")
    T.eq(ns.fixes[2].id, "AtlasLootClassic.hiddenVendor")
    T.eq(fix.id, ID)
    T.eq(fix.addon, "GearQuestForever")
    T.eq(fix.title, "GearQuest: skip hidden chat text")
    T.eq(ns.JoinList(fix.testedVersions), "0.2.6-beta and 0.2.11-beta")
    T.eq(ns.StatusText(fix), "active (GearQuestForever 0.2.11-beta), skipped 0 this session")
end)

T.test("a readable message reaches GearQuest exactly once, with all arguments and results", function()
    local w, _, fix, log = Boot()
    local a, b = w.env.GearQuest.Log:HandleCraftChatMessage("You receive loot: [Linen Cloth].", "extra", nil, 3)
    T.eq(#log.calls, 1)
    T.eq(log.calls[1].self, log)
    T.eq(log.calls[1].msg, "You receive loot: [Linen Cloth].")
    T.eq(log.calls[1].n, 3, "trailing arguments, nils included")
    T.eq(log.calls[1][1], "extra")
    T.eq(log.calls[1][3], 3)
    T.eq(a, "first"); T.eq(b, "second")
    T.eq(fix.state.skipped, 0)
end)

T.test("a hidden message is skipped: GearQuest never sees it, the count goes up", function()
    local w, ns, fix, log = Boot()
    local secret = w:secret()
    local r = { w.env.GearQuest.Log:HandleCraftChatMessage(secret) }
    T.eq(#log.calls, 0)
    T.eq(#r, 0, "returns nothing, like the original's early returns")
    T.eq(fix.state.skipped, 1)
    T.eq(#w.prints, 0, "no line with debug off")
    T.falsy(E.holds(ns.GetDB(), secret))
    T.falsy(E.holds(fix, secret))
end)

T.test("a skipped message is not kept anywhere (garbage-collection check)", function()
    local w, _, fix = Boot({ saved = { debug = true } })
    w.env.GearQuest.Log:HandleCraftChatMessage(w:secret())
    w.env.GearQuest.Log:HandleCraftChatMessage(w:secret())
    T.eq(fix.state.skipped, 2)
    collectgarbage(); collectgarbage()
    T.eq(next(w.secrets), nil, "a skipped secret is still referenced somewhere")
end)

T.test("a nil message goes straight through, uncounted", function()
    local w, _, fix, log = Boot()
    w.env.GearQuest.Log:HandleCraftChatMessage(nil)
    T.eq(#log.calls, 1)
    T.eq(log.calls[1].msg, nil)
    T.eq(fix.state.skipped, 0)
end)

T.test("switched off, even a hidden message goes to GearQuest", function()
    local w, ns, _, log = Boot()
    ns.SetFixEnabled(ID, false)
    T.eq(w.env.GearQuest.Log.HandleCraftChatMessage, log.original, "restored exactly")
    local secret = w:secret()
    local ok = pcall(w.env.GearQuest.Log.HandleCraftChatMessage, w.env.GearQuest.Log, secret)
    T.truthy(ok, "the fake doesn't index the message")
    T.truthy(rawequal(log.calls[1].msg, secret))
end)

T.test("off with another wrapper on top: pass-through, and on again reuses our wrapper", function()
    local w, ns, fix, log = Boot()
    local ours = w.env.GearQuest.Log.HandleCraftChatMessage
    local outer = function(self, msg, ...) return ours(self, msg, ...) end
    w.env.GearQuest.Log.HandleCraftChatMessage = outer
    ns.SetFixEnabled(ID, false)
    T.eq(w.env.GearQuest.Log.HandleCraftChatMessage, outer)
    T.eq(ns.StatusText(fix), "off (passing through until /reload)")
    w.env.GearQuest.Log:HandleCraftChatMessage(w:secret())
    T.eq(#log.calls, 1)
    ns.SetFixEnabled(ID, true)
    w.env.GearQuest.Log:HandleCraftChatMessage(w:secret())
    T.eq(#log.calls, 1, "skipped again, by the same wrapper")
    T.eq(fix.state.skipped, 1)
end)

T.test("install reports a changed GearQuest", function()
    for _, gq in ipairs({ false, 5, { Log = "nope" }, { Log = {} }, { Log = { HandleCraftChatMessage = "x" } } }) do
        local w, ns, fix = Boot({ gearquest = gq })
        T.eq(ns.StatusText(fix), "not applied: GearQuest's chat handler wasn't found (GearQuest has changed, or part of it failed to load)")
        T.eq(w:printsMatching('"GearQuest: skip hidden chat text" is not in place'), 1)
    end
end)

T.test("needed: with either secret check, not with neither", function()
    local w, _, fix = Boot()
    T.truthy(fix.needed())
    w.env.issecretvalue = nil
    T.truthy(fix.needed())
    w.env.canaccessvalue = nil
    T.falsy(fix.needed())
    w.env.issecretvalue = function() return false end
    T.truthy(fix.needed())
end)

T.test("a client without secret checks: not needed, GearQuest untouched", function()
    local w = E.new()
    w.env.issecretvalue, w.env.canaccessvalue = nil, nil
    local log = { HandleCraftChatMessage = function() end }
    local original = log.HandleCraftChatMessage
    w.env.GearQuest = { Log = log }
    w.loaded.GearQuestForever = true
    local ns = w:loadOurs()
    T.eq(ns.StatusText(ns.fixes[1]), "not needed on this client")
    T.eq(log.HandleCraftChatMessage, original)
end)

T.test("debug on: one line per skip with the count, never the message", function()
    local w, _, fix = Boot({ saved = { debug = true } })
    w.env.GearQuest.Log:HandleCraftChatMessage(w:secret())
    w.env.GearQuest.Log:HandleCraftChatMessage(w:secret())
    T.eq(w.prints[1], "|cff33ff99Forever Addon Fixes|r: GearQuest skipped a hidden chat message (1 this session)")
    T.eq(w.prints[2], "|cff33ff99Forever Addon Fixes|r: GearQuest skipped a hidden chat message (2 this session)")
    w.env.print = function() error("no chat during lockdown") end
    T.truthy(pcall(w.env.GearQuest.Log.HandleCraftChatMessage, w.env.GearQuest.Log, w:secret()))
    T.eq(fix.state.skipped, 3)
end)

T.test("GearQuest loading after us: waiting, then active", function()
    local w, ns, fix = Boot({ loaded = false })
    T.eq(ns.StatusText(fix), "waiting: GearQuestForever not loaded")
    w:loadTarget("GearQuestForever", "0.2.11-beta")
    T.eq(ns.FixState(fix), "active")
end)
