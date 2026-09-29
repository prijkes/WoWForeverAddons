-- Pure flight state machine. No WoW APIs: readings, time and picks come
-- from Core.
local _, ns = ...

local FlightTracker = {}
FlightTracker.__index = FlightTracker
ns.FlightTracker = FlightTracker

local TAKEOFF_WINDOW = 20 -- s from a pick to the first true reading
local RESUME_WINDOW = 10  -- s from the first permitted reading after a load
local LAND_CONFIRM = 0.1  -- a false reading must hold this long to count as a landing
local EPSILON = 1e-6      -- 140.1 - 140 is 0.0999999999999943 in binary floating point
local MIN_RECORD = 5      -- shorter flights are not recorded

local function isNum(v) return type(v) == "number" and v == v end

local function validRoute(r)
    return type(r) == "table" and type(r.key) == "string" and type(r.fromName) == "string"
        and type(r.toName) == "string" and (r.hops == nil or isNum(r.hops))
end

local function validSave(f)
    return type(f) == "table" and (f.route == nil or validRoute(f.route)) and isNum(f.takeoff)
        and isNum(f.elapsed) and f.elapsed >= 0 and (f.expected == nil or isNum(f.expected))
        and type(f.recordable) == "boolean" and (f.reason == nil or type(f.reason) == "string")
end

function FlightTracker.New(store, charSave, callbacks)
    local self = setmetatable({ store = store, save = charSave, cb = callbacks or {} }, FlightTracker)
    self.state = "idle"
    self.loaded = false
    if charSave.flight ~= nil and not validSave(charSave.flight) then
        charSave.flight = nil
        self.droppedSave = true
    end
    return self
end

function FlightTracker:Changed()
    if self.cb.onChange then self.cb.onChange() end
end

function FlightTracker:GetState() return self.state end

function FlightTracker:StartFlying(now, route, expected, recordable, reason, takeoff)
    self.flight = { route = route, takeoff = takeoff or now, expected = expected,
                    recordable = recordable, reason = reason, suspended = false }
    self.state = "flying"
    self.pick, self.resume = nil, nil
    if self.cb.onTakeoff then self.cb.onTakeoff(self.flight) end
    self:Changed()
end

function FlightTracker:Pick(route, now, seq)
    if self.state == "flying" then return end
    if self.state == "resuming" then -- a pick proves the player is on the ground
        self.save.flight, self.resume, self.state = nil, nil, "idle"
    end
    if self.state == "pending" then
        local p = self.pick
        if p.route.key ~= route.key then p.ambiguous = true end
        p.route, p.pickedAt, p.seq = route, now, seq
    else
        self.pick = { route = route, pickedAt = now, seq = seq, ambiguous = false }
        self.state = "pending"
    end
    self:Changed()
end

function FlightTracker:CancelPending()
    if self.state == "pending" then
        self.pick, self.state = nil, "idle"
        self:Changed()
    end
end

-- A new map session cancels a pick left over from before it: one made before the last
-- TAXIMAP_CLOSED, or in an earlier frame. GetTime() is constant within a frame, so a pick made
-- during this TAXIMAP_OPENED dispatch (another addon's auto-taxi) survives.
function FlightTracker:CancelStale(closeSeq, now)
    if self.state == "pending" and ((self.pick.seq or 0) < closeSeq or self.pick.pickedAt < now) then
        self:CancelPending()
    end
end

-- A flight map opened: the player is on the ground at a flight master, so a saved
-- flight that is still resuming is over.
function FlightTracker:EndResume()
    if self.state == "resuming" then
        self.save.flight, self.resume, self.state = nil, nil, "idle"
        self:Changed()
    end
end

-- TakeTaxiNode ran with a flight map but the pick couldn't be resolved: the player is
-- on the ground at a flight master, and the flight that follows can't be matched to a route.
function FlightTracker:UnresolvedPick()
    if self.state == "pending" then
        self:CancelPending()
    else
        self:EndResume()
    end
end

function FlightTracker:Land(landAt)
    local f = self.flight
    local duration = landAt - f.takeoff
    if duration < 0 then duration = 0 end
    local reason = f.reason
    if not f.route then
        reason = "untracked"
    elseif f.recordable then
        if duration >= MIN_RECORD then
            local newRoute = self.store:Record(f.route.key, f.route.fromName, f.route.toName, f.route.hops, duration)
            reason = newRoute and "learned" or "updated"
        else
            reason = "short"
        end
    end
    self.flight, self.state, self.save.flight = nil, "idle", nil
    if self.cb.onLand then
        self.cb.onLand({ route = f.route, fromName = f.route and f.route.fromName,
                         toName = f.route and f.route.toName, duration = duration,
                         expectedBefore = f.expected, reason = reason })
    end
    self:Changed()
end

function FlightTracker:Reading(onTaxi, now)
    if not self.loaded or onTaxi == nil then return end
    local state = self.state
    if state == "idle" then
        if onTaxi then self:StartFlying(now, nil, nil, false, "untracked") end
    elseif state == "pending" then
        local p = self.pick
        if onTaxi then
            self:StartFlying(now, p.route, self.store:Expected(p.route.key), not p.ambiguous,
                p.ambiguous and "ambiguous" or nil)
        elseif now - p.pickedAt > TAKEOFF_WINDOW then
            self.pick, self.state = nil, "idle"
            self:Changed()
        end
    elseif state == "resuming" then
        local r = self.resume
        r.firstReading = r.firstReading or now
        if onTaxi then
            local s = self.save.flight
            local expected = s.route and self.store:Expected(s.route.key) or nil
            if r.isReload then
                local takeoff = s.takeoff
                if takeoff > now then takeoff = now - s.elapsed end -- clock reset: keep the elapsed time
                self:StartFlying(now, s.route, expected, s.recordable, s.reason, takeoff)
            else
                self:StartFlying(now, s.route, expected, false, "relog", now - s.elapsed)
            end
        elseif now - r.firstReading > RESUME_WINDOW then
            self.save.flight, self.resume, self.state = nil, nil, "idle"
            self:Changed()
        end
    elseif state == "flying" then
        local f = self.flight
        if f.suspended then return end
        if onTaxi then
            f.landAt = nil
        elseif not f.landAt then
            f.landAt = now
        elseif now - f.landAt >= LAND_CONFIRM - EPSILON then
            self:Land(f.landAt)
        end
    end
end

local function NotRecorded(self, reason)
    if self.state == "flying" then
        self.flight.recordable, self.flight.reason = false, reason
        self:Changed()
    end
end

function FlightTracker:EarlyLanding() NotRecorded(self, "early") end
function FlightTracker:Interrupt() NotRecorded(self, "interrupted") end

function FlightTracker:LoadingStarted()
    if self.state == "flying" then
        NotRecorded(self, "interrupted")
        self.flight.suspended, self.flight.landAt = true, nil
    end
end

function FlightTracker:LoadingEnded()
    if self.state == "flying" then self.flight.suspended = false end
end

-- The first PLAYER_ENTERING_WORLD of a UI session.
function FlightTracker:OnLoad(now, isReload)
    if self.loaded then return end
    self.loaded = true
    if self.save.flight then
        self.state = "resuming"
        self.resume = { isReload = isReload and true or false }
        self:Changed()
    end
end

-- PLAYER_LOGOUT: fires on logout, disconnect and /reload.
function FlightTracker:OnUnload(now)
    if self.state == "flying" then
        local f = self.flight
        self.save.flight = { route = f.route, takeoff = f.takeoff, elapsed = now - f.takeoff,
                             expected = f.expected, recordable = f.recordable, reason = f.reason }
    elseif self.state ~= "resuming" then
        self.save.flight = nil
    end
end

function FlightTracker:GetView(now)
    if self.state ~= "flying" then return { mode = "hidden" } end
    local f = self.flight
    local elapsed = (f.landAt or now) - f.takeoff -- hold at a landing candidate
    if elapsed < 0 then elapsed = 0 end
    local v = { elapsed = elapsed, expected = f.expected, route = f.route,
                fromName = f.route and f.route.fromName, toName = f.route and f.route.toName }
    if not f.route then
        v.mode = "untracked"
    elseif not f.expected then
        v.mode = "learning"
    elseif elapsed <= f.expected then
        v.mode, v.remaining = "countdown", f.expected - elapsed
    else
        v.mode, v.over = "overtime", elapsed - f.expected
    end
    return v
end
