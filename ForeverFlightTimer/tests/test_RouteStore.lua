local T = ...
local ns = require("loader").load({}, "RouteStore.lua")
local RS = ns.RouteStore

T.test("expected is the median of 1, 2 and 3 samples", function()
    local s = RS.New({})
    T.eq(s:Expected("a>b"), nil)
    s:Record("a>b", "A", "B", 1, 50)
    T.eq(s:Expected("a>b"), 50)
    s:Record("a>b", "A", "B", 1, 60)
    T.eq(s:Expected("a>b"), 55)
    s:Record("a>b", "A", "B", 1, 52)
    T.eq(s:Expected("a>b"), 52)
end)

T.test("only the last 3 samples count", function()
    local tbl = {}
    local s = RS.New(tbl)
    for _, d in ipairs({ 50, 60, 55, 100 }) do s:Record("a>b", "A", "B", 1, d) end
    T.eq(#tbl["a>b"].samples, 3)
    T.eq(s:Expected("a>b"), 60)
    T.eq(tbl["a>b"].flights, 4)
end)

T.test("newRoute only for the first recording; names refresh", function()
    local tbl = {}
    local s = RS.New(tbl)
    T.eq(s:Record("a>b", "A", "B", 1, 50), true)
    T.eq(s:Record("a>b", "A2", "B2", 2, 51), false)
    T.eq(tbl["a>b"].fromName, "A2")
    T.eq(tbl["a>b"].toName, "B2")
    T.eq(tbl["a>b"].hops, 2)
end)

T.test("validation drops malformed entries and trims long sample lists", function()
    local tbl = {
        good = { fromName = "A", toName = "B", samples = { 1, 2, 3, 4, 5 }, flights = 5 },
        noSamples = { fromName = "A", toName = "B", samples = {} },
        badSample = { fromName = "A", toName = "B", samples = { "x" } },
        noName = { toName = "B", samples = { 10 } },
        notTable = "text",
    }
    tbl[42] = { fromName = "A", toName = "B", samples = { 10 } }
    local s = RS.New(tbl)
    T.eq(s.dropped, 5)
    T.eq(s:Count(), 1)
    T.eq(#tbl.good.samples, 3)
    T.eq(s:Expected("good"), 4)
end)

T.test("forget clears the same table", function()
    local tbl = {}
    local s = RS.New(tbl)
    s:Record("a>b", "A", "B", 1, 50)
    s:Forget()
    T.eq(s:Count(), 0)
    T.eq(next(tbl), nil)
end)

T.test("list is sorted and carries expected times", function()
    local s = RS.New({})
    s:Record("x>z", "Xavi", "Zed", 1, 30)
    s:Record("a>c", "Alpha", "Charlie", 2, 70)
    s:Record("a>b", "Alpha", "Bravo", 1, 40)
    local list = s:List()
    T.eq(#list, 3)
    T.eq(list[1].toName, "Bravo")
    T.eq(list[2].toName, "Charlie")
    T.eq(list[2].hops, 2)
    T.eq(list[2].expected, 70)
    T.eq(list[3].fromName, "Xavi")
    T.eq(list[3].flights, 1)
end)
