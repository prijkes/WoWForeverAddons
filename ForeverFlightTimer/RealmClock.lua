-- Pure: realm time of day with sub-minute precision. GetGameTime() only reports hours and
-- minutes, so the clock pins a promptly observed minute change to GetTime(), like FIT's Clock.
-- Until then it assumes 30 s into the current minute.
local _, ns = ...

local RealmClock = {}
RealmClock.__index = RealmClock
ns.RealmClock = RealmClock

local PROMPT = 0.25 -- a minute change pins the anchor only if the previous look was this recent
local GUESS = 30    -- assumed seconds into the minute while the phase is unknown

local function MinuteOfDay(getGameTime)
    local h, m = getGameTime()
    return (h or 0) * 60 + (m or 0)
end

function RealmClock.New(getGameTime, getTime)
    local self = setmetatable({ getGameTime = getGameTime, getTime = getTime }, RealmClock)
    local t = getTime()
    self.minute = MinuteOfDay(getGameTime)
    self.base = t - GUESS
    self.lastLook = t
    self.precise = false
    return self
end

-- Seconds since realm midnight, 0 <= s < 86400.
function RealmClock:Now()
    local t = self.getTime()
    if not self.precise then
        local minute = MinuteOfDay(self.getGameTime)
        if minute ~= self.minute then
            self.minute = minute
            if t - self.lastLook <= PROMPT then
                self.base, self.precise = t, true
            else
                self.base = t - GUESS
            end
        end
        self.lastLook = t
    end
    return (self.minute * 60 + (t - self.base)) % 86400
end
