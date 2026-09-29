-- Pure run state machine. No WoW APIs: readings, time and rules are passed in.
local _, ns = ...

local RunTracker = {}
RunTracker.__index = RunTracker
ns.RunTracker = RunTracker

local CONFIRM_DELAY = 1 -- a confirming reading must be at least this much later
local REVIVE_DELAY = 3  -- a revive outside must hold this long before the run ends

local STATES = { idle = true, inside = true, away = true }
local KINDS = { start = true, finish = true, switch = true }

local function isNum(v) return type(v) == "number" and v == v end

local function idleRun() return { state = "idle" } end

local function elapsedAt(run, t)
    if run.state == "idle" or not run.start then return 0 end
    local e = t - run.start - (run.paused or 0)
    if run.pauseSince then
        local open = t - run.pauseSince
        if open > 0 then e = e - open end
    end
    return e > 0 and e or 0
end

local function trackable(reading, rules)
    return reading.inInstance and rules.types ~= nil and rules.types[reading.instanceType] == true
end

-- Returns false when saved data was malformed and had to be discarded.
function RunTracker.Validate(store)
    if not isNum(store.lastSeen) then store.lastSeen = nil end
    local run = store.run
    if run == nil then
        store.run = idleRun()
        return true
    end
    local ok = type(run) == "table" and STATES[run.state] ~= nil
    if ok and run.state ~= "idle" then
        ok = isNum(run.key) and run.key > 0 and type(run.name) == "string" and isNum(run.start)
            and (run.paused == nil or isNum(run.paused))
            and (run.pauseSince == nil or isNum(run.pauseSince))
            and (run.state ~= "away" or isNum(run.awaySince))
            and (run.revivedAt == nil or isNum(run.revivedAt))
    end
    if ok and run.pending ~= nil then
        local p = run.pending
        ok = type(p) == "table" and KINDS[p.kind] ~= nil and isNum(p.at) and isNum(p.firstSeen)
        if ok and p.kind ~= "finish" then
            ok = isNum(p.key) and p.key > 0 and type(p.name) == "string" and isNum(p.arrivedAt)
        end
        if ok and p.kind ~= "start" and run.state == "idle" then ok = false end -- nothing to finish
        if ok and p.kind == "start" and run.state ~= "idle" then ok = false end -- would replace the run
    end
    if not ok then
        store.run = idleRun()
        return false
    end
    if run.state ~= "idle" then run.paused = run.paused or 0 end
    return true
end

function RunTracker.New(store, getRules, callbacks)
    local self = setmetatable({ store = store, getRules = getRules, cb = callbacks or {} }, RunTracker)
    self.silentNext = false
    self.validationFailed = not RunTracker.Validate(store)
    return self
end

function RunTracker:Changed()
    if self.cb.onChange then self.cb.onChange() end
end

function RunTracker:StartRun(key, name, itype, at)
    self.store.run = { state = "inside", key = key, name = name, itype = itype, start = at, paused = 0 }
    if self.cb.onStart then self.cb.onStart({ name = name, at = at }) end
end

function RunTracker:FinishRun(at, reason, silent, replaced)
    local run = self.store.run
    local info = { name = run.name, seconds = elapsedAt(run, at), reason = reason,
                   silent = silent and true or false, replaced = replaced and true or false }
    self.store.run = idleRun()
    if self.cb.onFinish then self.cb.onFinish(info) end
    return info
end

function RunTracker:GoAway(at, rules)
    local run = self.store.run
    run.state = "away"
    run.awaySince = at
    run.revivedAt, run.reviveSilent = nil, nil
    if rules.awayMode == "pause" and not run.pauseSince then run.pauseSince = at end
end

function RunTracker:ComeBack(at)
    local run = self.store.run
    run.state = "inside"
    if run.pauseSince then
        local d = at - run.pauseSince
        if d > 0 then run.paused = (run.paused or 0) + d end
        run.pauseSince = nil
    end
    run.awaySince, run.revivedAt, run.reviveSilent = nil, nil, nil
end

function RunTracker:SetPending(kind, reading, t, silent)
    local p = { kind = kind, firstSeen = t, silent = silent and true or false }
    if kind ~= "finish" then
        p.key, p.name, p.itype = reading.instanceID, reading.instanceName, reading.instanceType
        p.arrivedAt = reading.arrivedAt or t
    end
    if kind == "start" then
        p.at = p.arrivedAt
    else
        p.at = reading.leftAt or t
    end
    self.store.run.pending = p
end

function RunTracker:Observe(reading, now)
    local rules = self.getRules()
    local t = reading.at or now
    local silent = self.silentNext
    self.silentNext = false
    local run = self.store.run

    -- 1. A pending confirmed transition: confirm it, keep waiting, or drop it.
    local p = run.pending
    if p then
        local agrees
        if p.kind == "finish" then
            agrees = not (reading.inInstance and reading.instanceID == run.key)
        else
            agrees = reading.inInstance and reading.instanceID == p.key
        end
        if agrees then
            if t - p.firstSeen < CONFIRM_DELAY then return end
            run.pending = nil
            if p.kind == "start" then
                self:StartRun(p.key, p.name, p.itype, p.arrivedAt)
            elseif p.kind == "switch" then
                self:FinishRun(p.at, "switched", p.silent, true)
                self:StartRun(p.key, p.name, p.itype, p.arrivedAt)
            elseif reading.dead then
                self:GoAway(p.at, rules) -- died after all: never reset on a death
            else
                self:FinishRun(p.at, "left", p.silent, false)
            end
            self:Changed()
            return
        end
        run.pending = nil -- disagrees: drop it, then handle this reading normally
        self:Changed()
    end

    -- 2. Normal transitions.
    if run.state == "idle" then
        if trackable(reading, rules) then
            self:SetPending("start", reading, t, silent)
            self:Changed()
        end
        return
    end

    local same = reading.inInstance and reading.instanceID == run.key
    if run.state == "inside" then
        if same then return end
        if trackable(reading, rules) then
            self:SetPending("switch", reading, t, silent)
        elseif reading.dead then
            self:GoAway(reading.leftAt or t, rules)
        else
            self:SetPending("finish", reading, t, silent)
        end
        self:Changed()
        return
    end

    -- run.state == "away"
    if same then
        self:ComeBack(reading.arrivedAt or t)
        self:Changed()
        return
    end
    if trackable(reading, rules) then
        self:SetPending("switch", reading, t, silent)
        self:Changed()
        return
    end
    if rules.giveUp == "ghost" then
        if reading.dead then
            if run.revivedAt then
                run.revivedAt, run.reviveSilent = nil, nil
                self:Changed()
            end
        elseif not run.revivedAt then
            run.revivedAt, run.reviveSilent = t, silent
            self:Changed()
        elseif t - run.revivedAt >= REVIVE_DELAY then
            self:FinishRun(run.revivedAt, "revived", run.reviveSilent, false)
            self:Changed()
        end
    elseif rules.giveUp == "grace" then
        local deadline = run.awaySince + (rules.graceMinutes or 15) * 60
        if t >= deadline then
            self:FinishRun(deadline, "grace", silent, false)
            self:Changed()
        end
    end
end

function RunTracker:GetState() return self.store.run.state end
function RunTracker:GetInstanceName() return self.store.run.name end
function RunTracker:GetRun() return self.store.run end
function RunTracker:GetElapsed(now) return elapsedAt(self.store.run, now) end

-- What the display shows: holds at a pending finish/switch or revive moment, so the
-- timer doesn't visibly jump back when the final time freezes.
function RunTracker:GetDisplayElapsed(now)
    local run = self.store.run
    local t = now
    local p = run.pending
    if p and p.kind ~= "start" and p.at < t then t = p.at end
    if run.state == "away" and run.revivedAt and run.revivedAt < t then t = run.revivedAt end
    return elapsedAt(run, t)
end

-- Initial login only (not /reload). Order matters: offline policy first, then rules.
function RunTracker:OnLogin(now)
    local store, rules = self.store, self.getRules()
    local run = store.run
    self.silentNext = true
    if rules.offline == "reset" then
        store.run = idleRun()
    elseif rules.offline == "pause" and run.state ~= "idle" and not run.pauseSince
        and isNum(store.lastSeen) and now > store.lastSeen then
        run.paused = (run.paused or 0) + (now - store.lastSeen)
    end
    self:OnRulesChanged(now)
end

function RunTracker:OnLogout(now)
    self.store.lastSeen = now
end

function RunTracker:OnRulesChanged(now)
    local run, rules = self.store.run, self.getRules()
    if run.state == "away" then
        if rules.awayMode == "pause" then
            if not run.pauseSince then run.pauseSince = now end
        elseif run.pauseSince then
            local d = now - run.pauseSince
            if d > 0 then run.paused = (run.paused or 0) + d end
            run.pauseSince = nil
        end
        if rules.giveUp ~= "ghost" then run.revivedAt, run.reviveSilent = nil, nil end
    elseif run.pauseSince then -- a pause can only be open while away
        local d = now - run.pauseSince
        if d > 0 then run.paused = (run.paused or 0) + d end
        run.pauseSince = nil
    end
    self:Changed()
end

-- Manual reset: silent restart. `reading` must be one taken after the most
-- recent loading screen (ZoneWatcher:GetLastReading() guarantees that) or nil.
function RunTracker:Reset(now, reading)
    self.store.run = idleRun()
    if reading and trackable(reading, self.getRules()) then
        self:StartRun(reading.instanceID, reading.instanceName, reading.instanceType, now)
    end
    self:Changed()
end
