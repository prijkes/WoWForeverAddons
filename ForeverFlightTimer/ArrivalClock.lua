-- Pure: formats an arrival clock time. No WoW APIs; the date function is injected.
local _, ns = ...

local ArrivalClock = {}
ns.ArrivalClock = ArrivalClock

local floor, format = math.floor, string.format

local function HourMinute(hour, minute, use24h)
    if use24h then return format("%02d:%02d", hour, minute) end
    local suffix = hour < 12 and "AM" or "PM"
    local h12 = hour % 12
    if h12 == 0 then h12 = 12 end
    return format("%d:%02d %s", h12, minute, suffix)
end

-- Local time. epoch = time() + seconds remaining; dateFn behaves like date("*t", t).
function ArrivalClock.Local(epoch, use24h, dateFn)
    local t = dateFn("*t", floor(epoch))
    return HourMinute(t.hour, t.min, use24h)
end

-- Realm time. secondsOfDay may run past midnight; it wraps.
function ArrivalClock.Realm(secondsOfDay, use24h)
    local s = floor(secondsOfDay) % 86400
    return HourMinute(floor(s / 3600), floor(s % 3600 / 60), use24h)
end
