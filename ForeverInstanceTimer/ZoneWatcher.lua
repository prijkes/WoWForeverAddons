-- Pure zone watcher: turns events and raw game-state reads into validated readings.
-- No WoW APIs: the raw reader and the time are passed in.
local _, ns = ...

local ZoneWatcher = {}
ZoneWatcher.__index = ZoneWatcher
ns.ZoneWatcher = ZoneWatcher

local POLL_INTERVAL = 1   -- seconds between polls while no loading screen is active
local PEW_READ_DELAY = 1  -- deferred reading after PLAYER_ENTERING_WORLD
local PEW_FAILSAFE = 10   -- clear a stuck loading flag this long after PLAYER_ENTERING_WORLD
local LSE_FAILSAFE = 60   -- ...or this long after LOADING_SCREEN_ENABLED when no PEW followed

function ZoneWatcher.New(read, onReading, savedDeadFlag)
    local self = setmetatable({}, ZoneWatcher)
    self.read = read
    self.onReading = onReading
    self.loading = true       -- addons load during a loading screen
    self.hintPending = true   -- the next valid reading carries boundary hints
    self.seenPEW = false      -- no readings before the first PLAYER_ENTERING_WORLD
    self.deadFlag = savedDeadFlag and true or false
    self.usingFallback = false
    return self
end

-- Best dead-or-ghost value from the raw read, or nil when nothing is readable.
local function deriveDead(raw)
    if raw.dogReadable then return raw.dog and true or false end
    if (raw.ghostReadable and raw.ghost) or (raw.deadReadable and raw.deadOnly) then return true end
    if raw.ghostReadable and raw.deadReadable then return false end
    return nil
end

function ZoneWatcher:OnEvent(event, now, ...)
    if event == "LOADING_SCREEN_ENABLED" then
        self.loading = true
        self.loadStart, self.loadEnd = now, nil
        self.lseAt, self.pewAt = now, nil
        self.hintPending = true
        self.lastReading = nil
    elseif event == "LOADING_SCREEN_DISABLED" then
        if self.loading then
            self.loading = false
            self.loadEnd = now
        end
        self:ReadNow(now)
    elseif event == "PLAYER_ENTERING_WORLD" then
        self.seenPEW = true
        self.pewAt = now
        self.pewReadAt = now + PEW_READ_DELAY
    else
        if event == "PLAYER_DEAD" then
            self.deadFlag = true
        elseif event == "PLAYER_UNGHOST" then
            self.deadFlag = false
        elseif event == "PLAYER_ALIVE" then
            -- Also fires on release (you become a ghost), so only trust UnitIsGhost.
            local raw = self.read()
            if type(raw) == "table" and raw.ghostReadable then
                self.deadFlag = raw.ghost and true or false
            end
        end
        self:ReadNow(now) -- ZONE_CHANGED_NEW_AREA and the death events
    end
end

function ZoneWatcher:Tick(now)
    if self.loading then
        local pewExpired = self.pewAt and now - self.pewAt >= PEW_FAILSAFE
        local lseExpired = self.lseAt and not self.pewAt and now - self.lseAt >= LSE_FAILSAFE
        if pewExpired or lseExpired then
            self.loading = false
            self.loadEnd = nil -- cleared by a failsafe: arrivedAt becomes the reading time
            self:ReadNow(now)
        end
        return
    end
    if self.pewReadAt and now >= self.pewReadAt then
        self.pewReadAt = nil
        self:ReadNow(now)
    elseif not self.lastPoll or now - self.lastPoll >= POLL_INTERVAL then
        self:ReadNow(now)
    end
end

function ZoneWatcher:ReadNow(now)
    if self.loading or not self.seenPEW then return nil end
    self.lastPoll = now
    local raw = self.read()
    if type(raw) ~= "table" or not raw.ok or type(raw.inInstance) ~= "boolean" then return nil end

    local reading = { at = now, inInstance = raw.inInstance }
    if raw.inInstance then
        if type(raw.instanceID) ~= "number" or raw.instanceID <= 0
            or type(raw.instanceType) ~= "string" or type(raw.instanceName) ~= "string" then
            return nil
        end
        reading.instanceID = raw.instanceID
        reading.instanceType = raw.instanceType
        reading.instanceName = raw.instanceName
    else
        reading.instanceType = "none"
    end

    local derived = deriveDead(raw)
    if derived ~= nil then self.deadFlag = derived end
    self.usingFallback = not raw.dogReadable
    reading.dead = self.deadFlag

    if self.hintPending then
        reading.leftAt = self.loadStart
        reading.arrivedAt = self.loadEnd or now
        self.hintPending = false
        self.loadStart, self.loadEnd = nil, nil
    end

    self.lastReading = reading
    if self.onReading then self.onReading(reading, now) end
    return reading
end

function ZoneWatcher:IsLoading() return self.loading end
function ZoneWatcher:IsUsingDeadFallback() return self.usingFallback end
function ZoneWatcher:GetLastReading() return self.lastReading end
function ZoneWatcher:GetDeadFlag() return self.deadFlag end
