-- Pure clock: server time with sub-second precision. Time sources are injected.
local _, ns = ...

local Clock = {}
Clock.__index = Clock
ns.Clock = Clock

-- A server-second change only pins the anchor when the previous look was this recent.
-- Nothing runs during a loading screen, so the first change seen afterwards can be up to
-- a second late; the clock then re-anchors roughly and waits for a promptly seen boundary.
local PROMPT = 0.25

function Clock.New(getServerTime, getTime)
    local self = setmetatable({ getServerTime = getServerTime, getTime = getTime }, Clock)
    self.baseServer = getServerTime()
    self.baseTime = getTime()
    self.lastLook = self.baseTime
    self.precise = false
    return self
end

function Clock:Now()
    local t = self.getTime()
    if not self.precise then
        local server = self.getServerTime()
        if server ~= self.baseServer then
            self.baseServer, self.baseTime = server, t
            self.precise = t - self.lastLook <= PROMPT
        end
        self.lastLook = t
    end
    return self.baseServer + (t - self.baseTime)
end
