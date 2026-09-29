-- The AtlasLoot fix against a fake AtlasLoot; smoke_atlasloot.lua runs it against the real file.
local T = ...
local E = require("env")

local ID = "AtlasLootClassic.hiddenVendor"

-- A fake AtlasLoot whose ScanShownVendor records its calls; w.target is what UnitGUID("target") returns.
local function Boot(opts)
    opts = opts or {}
    local w = E.new()
    local vp = { calls = {} }
    function vp.ScanShownVendor(...)
        vp.calls[#vp.calls + 1] = { n = select("#", ...), ... }
        return "first", "second"
    end
    vp.original = vp.ScanShownVendor
    w.env.UnitGUID = function(unit)
        if w.guidError then error("UnitGUID failed") end
        if unit == "target" then return w.target end
    end
    if opts.atlasloot ~= false then w.env.AtlasLoot = opts.atlasloot or { Data = { VendorPrice = vp } } end
    if opts.loaded ~= false then w.loaded.AtlasLootClassic = true; w.versions.AtlasLootClassic = opts.version or "Forever 1.60.1" end
    local ns = w:loadOurs({ saved = opts.saved })
    return w, ns, ns.fixes[2], vp
end

local CREATURE = "Creature-0-4461-0-12-5120-00001ABCDE"

T.test("registered second, with its id, target, tested version and version note", function()
    local _, ns, fix = Boot()
    T.eq(fix.id, ID)
    T.eq(fix.addon, "AtlasLootClassic")
    T.eq(fix.title, "AtlasLoot: skip scans of hidden vendors")
    T.eq(ns.StatusText(fix), "active (AtlasLootClassic Forever 1.60.1; its releases share one version string), skipped 0 this session")
end)

T.test("both fixes in /afix status, in toc order", function()
    local w = Boot()
    w:clearPrints()
    w:slash("status")
    T.truthy(w.prints[1]:find("1%. GearQuest: skip hidden chat text: waiting: GearQuestForever not loaded"))
    T.truthy(w.prints[2]:find("2%. AtlasLoot: skip scans of hidden vendors: active"))
end)

T.test("a readable target reaches AtlasLoot exactly once, with all arguments and results", function()
    local w, _, fix, vp = Boot()
    w.target = CREATURE
    local a, b = w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor("x", nil, 3)
    T.eq(#vp.calls, 1)
    T.eq(vp.calls[1].n, 3)
    T.eq(vp.calls[1][1], "x"); T.eq(vp.calls[1][3], 3)
    T.eq(a, "first"); T.eq(b, "second")
    T.eq(fix.state.skipped, 0)
end)

T.test("a hidden vendor is skipped: AtlasLoot never scans, the count goes up", function()
    local w, _, fix, vp = Boot()
    w.target = w:secret()
    local r = { w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor() }
    T.eq(#vp.calls, 0)
    T.eq(#r, 0, "returns nothing, like AtlasLoot's own early returns")
    T.eq(fix.state.skipped, 1)
    T.eq(#w.prints, 0, "no line with debug off")
end)

T.test("no target goes straight to AtlasLoot, which returns early on its own", function()
    local w, _, fix, vp = Boot()
    w.target = nil
    w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor()
    T.eq(#vp.calls, 1)
    T.eq(fix.state.skipped, 0)
end)

T.test("an erroring UnitGUID counts as a skip (AtlasLoot's own read would error too)", function()
    local w, _, fix, vp = Boot()
    w.guidError = true
    T.truthy(pcall(w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor))
    T.eq(#vp.calls, 0)
    T.eq(fix.state.skipped, 1)
end)

T.test("switched off: AtlasLoot's own function is back, and even a hidden vendor reaches it", function()
    local w, ns, _, vp = Boot()
    w:slash("off 2")
    T.eq(w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor, vp.original, "restored exactly")
    w.target = w:secret()
    w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor()
    T.eq(#vp.calls, 1)
    T.eq(ns.StatusText(ns.fixes[2]), "off")
end)

T.test("off with another wrapper on top: pass-through, and on again reuses our wrapper", function()
    local w, ns, fix, vp = Boot()
    local ours = w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor
    local outer = function(...) return ours(...) end
    w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor = outer
    ns.SetFixEnabled(ID, false)
    T.eq(w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor, outer)
    T.eq(ns.StatusText(fix), "off (passing through until /reload)")
    w.target = w:secret()
    outer()
    T.eq(#vp.calls, 1)
    ns.SetFixEnabled(ID, true)
    outer()
    T.eq(#vp.calls, 1, "skipped again, by the same wrapper")
    T.eq(fix.state.skipped, 1)
end)

T.test("install reports a changed AtlasLoot", function()
    for _, al in ipairs({ false, 5, { Data = 5 }, { Data = {} }, { Data = { VendorPrice = 5 } }, { Data = { VendorPrice = {} } },
        { Data = { VendorPrice = { ScanShownVendor = "x" } } } }) do
        local w, ns, fix = Boot({ atlasloot = al })
        T.eq(ns.StatusText(fix), "not applied: AtlasLoot's vendor scanner wasn't found (AtlasLoot has changed, or part of it failed to load)")
        T.eq(w:printsMatching('"AtlasLoot: skip scans of hidden vendors" is not in place'), 1)
    end
end)

T.test("debug on: one line per skip with the count, never the GUID", function()
    local w, _, fix = Boot({ saved = { debug = true } })
    w.target = w:secret()
    w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor()
    T.eq(w.prints[1], "|cff33ff99Forever Addon Fixes|r: AtlasLoot skipped a vendor scan (the vendor is hidden) (1 this session)")
    w.env.print = function() error("no chat right now") end
    T.truthy(pcall(w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor))
    T.eq(fix.state.skipped, 2)
end)

T.test("a skipped GUID is not kept anywhere (garbage-collection check)", function()
    local w, _, fix = Boot({ saved = { debug = true } })
    w.target = w:secret()
    w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor()
    w.target = w:secret()
    w.env.AtlasLoot.Data.VendorPrice.ScanShownVendor()
    w.target = nil
    T.eq(fix.state.skipped, 2)
    collectgarbage(); collectgarbage()
    T.eq(next(w.secrets), nil, "a skipped GUID is still referenced somewhere")
end)

T.test("needed: with either secret check, not with neither", function()
    local w, _, fix = Boot()
    T.truthy(fix.needed())
    w.env.issecretvalue = nil
    T.truthy(fix.needed())
    w.env.canaccessvalue = nil
    T.falsy(fix.needed())
end)

T.test("AtlasLoot loading after us: waiting, then active (also with the late loaded flag)", function()
    for _, late in ipairs({ false, true }) do
        local w, ns, fix = Boot({ loaded = false })
        T.eq(ns.StatusText(fix), "waiting: AtlasLootClassic not loaded")
        w:loadTarget("AtlasLootClassic", "Forever 1.60.1", late)
        T.eq(ns.FixState(fix), "active")
    end
end)
