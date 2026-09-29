local T = ...
local ns = require("loader").load({}, "Clock.lua")

local function source(server, t)
    local src = { server = server, t = t }
    src.getServerTime = function() return src.server end
    src.getTime = function() return src.t end
    return src
end

T.test("rough anchor before the first server-second change", function()
    local src = source(1000, 50.3)
    local c = ns.Clock.New(src.getServerTime, src.getTime)
    T.near(c:Now(), 1000)
    src.t = 50.9
    T.near(c:Now(), 1000.6)
end)

T.test("anchors precisely when the server second ticks over", function()
    local src = source(1000, 50.3)
    local c = ns.Clock.New(src.getServerTime, src.getTime)
    src.t = 50.9
    c:Now()                         -- looking at 10 Hz...
    src.t, src.server = 51.0, 1001  -- ...so the new second is seen 0.1 s after the last look
    T.near(c:Now(), 1001.0)
    src.t, src.server = 52.5, 1002
    T.near(c:Now(), 1002.5)
    src.t = 53.25 -- once anchored, only GetTime matters
    T.near(c:Now(), 1003.25)
end)

T.test("a late observation (after a loading screen) does not lock in an imprecise anchor", function()
    -- True server time is t + 989.8, so server seconds tick over at t = 10.2, 11.2, 12.2, ...
    local src = { t = 10.0 }
    src.getTime = function() return src.t end
    src.getServerTime = function() return math.floor(src.t + 989.8 + 1e-9) end
    local c = ns.Clock.New(src.getServerTime, src.getTime)
    c:Now()
    src.t = 13.7 -- no calls during a 3.7 s loading screen; the boundary at 13.2 was missed
    c:Now()
    for t = 13.8, 14.25, 0.1 do src.t = t; c:Now() end -- 10 Hz again: sees the 14.2 boundary promptly
    src.t = 20.0
    T.near(c:Now(), 1009.8, 0.11, "anchored on the promptly observed boundary")
end)

T.test("a reload (new clock) agrees with the old clock once anchored", function()
    local src = source(1000, 10.0)
    local a = ns.Clock.New(src.getServerTime, src.getTime)
    src.t = 10.45
    a:Now()
    src.t, src.server = 10.5, 1001
    a:Now() -- a anchors at 1001 @ 10.5 (seen 0.05 s after the previous look)
    src.t, src.server = 20.2, 1010
    local b = ns.Clock.New(src.getServerTime, src.getTime)
    src.t = 20.45
    b:Now()
    src.t, src.server = 20.5, 1011
    b:Now() -- b anchors at 1011 @ 20.5
    src.t = 21.0
    T.near(a:Now(), 1011.5)
    T.near(b:Now(), 1011.5)
end)
