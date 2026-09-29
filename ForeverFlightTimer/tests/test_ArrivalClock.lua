local T = ...
local ns = require("loader").load({}, "ArrivalClock.lua")
local A = ns.ArrivalClock
local utc = function(_, t) return os.date("!*t", t) end

T.test("local time in 24 h and 12 h", function()
    local t = 14 * 3600 + 32 * 60 + 50 -- 14:32:50 UTC
    T.eq(A.Local(t, true, utc), "14:32")
    T.eq(A.Local(t, false, utc), "2:32 PM")
end)

T.test("12 h edge hours and 24 h zero padding", function()
    T.eq(A.Local(0, false, utc), "12:00 AM")
    T.eq(A.Local(12 * 3600 + 5 * 60, false, utc), "12:05 PM")
    T.eq(A.Local(9 * 3600 + 5 * 60, true, utc), "09:05")
end)

T.test("minutes are floored, not rounded", function()
    T.eq(A.Local(14 * 3600 + 32 * 60 + 59.9, true, utc), "14:32")
end)

T.test("realm time wraps past midnight", function()
    T.eq(A.Realm(23 * 3600 + 59 * 60 + 30, true), "23:59")
    T.eq(A.Realm(86400 + 65, true), "00:01")
    T.eq(A.Realm(86400 + 13 * 3600, false), "1:00 PM")
end)
