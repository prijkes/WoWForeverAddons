local T = ...
local ns = require("loader").load({}, "RealmClock.lua")

local function src(h, m, t)
    local s = { h = h, m = m, t = t }
    s.gameTime = function() return s.h, s.m end
    s.getTime = function() return s.t end
    return s
end

T.test("assumes 30 s into the minute until a change is seen", function()
    local s = src(14, 32, 100)
    local c = ns.RealmClock.New(s.gameTime, s.getTime)
    T.near(c:Now(), 14 * 3600 + 32 * 60 + 30)
    s.t = 110
    T.near(c:Now(), 14 * 3600 + 32 * 60 + 40)
end)

T.test("anchors on a promptly observed minute change", function()
    local s = src(14, 32, 100)
    local c = ns.RealmClock.New(s.gameTime, s.getTime)
    s.t = 100.1
    c:Now()
    s.t, s.m = 100.2, 33 -- seen 0.1 s after the previous look
    T.near(c:Now(), 14 * 3600 + 33 * 60)
    s.t = 145.2
    T.near(c:Now(), 14 * 3600 + 33 * 60 + 45)
end)

T.test("a late observation stays approximate until a prompt one", function()
    local s = src(14, 32, 100)
    local c = ns.RealmClock.New(s.gameTime, s.getTime)
    s.t, s.m = 105, 34 -- 5 s without looking (e.g. a loading screen)
    T.near(c:Now(), 14 * 3600 + 34 * 60 + 30)
    s.t, s.m = 105.1, 35
    T.near(c:Now(), 14 * 3600 + 35 * 60)
end)

T.test("wraps at midnight", function()
    local s = src(23, 59, 100)
    local c = ns.RealmClock.New(s.gameTime, s.getTime)
    s.t = 100.1
    c:Now()
    s.t, s.h, s.m = 100.2, 0, 0
    T.near(c:Now(), 0)
    s.t = 100.2 + 86400 + 5
    T.near(c:Now(), 5)
end)
