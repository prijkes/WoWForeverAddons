local T = ...
local ns = require("loader").load({}, "ZoneWatcher.lua")
local ZW = ns.ZoneWatcher

local OUTSIDE = { ok = true, inInstance = false, dogReadable = true, dog = false }
local function inside(id, dead)
    return { ok = true, inInstance = true, instanceID = id, instanceName = "The Deadmines",
             instanceType = "party", dogReadable = true, dog = dead or false }
end

local function make(raw, savedDead)
    local env = { raw = raw, readings = {} }
    env.w = ZW.New(function() return env.raw end,
                   function(r) env.readings[#env.readings + 1] = r end, savedDead)
    return env
end

local function login(env, t) -- PEW at t, loading screen ends at t + 0.5
    env.w:OnEvent("PLAYER_ENTERING_WORLD", t, true, false)
    env.w:OnEvent("LOADING_SCREEN_DISABLED", t + 0.5)
end

local function ticks(env, from, to) -- tenths, inclusive
    for i = from, to do env.w:Tick(i / 10) end
end

T.test("no readings while loading at load time", function()
    local env = make(OUTSIDE)
    ticks(env, 0, 50)
    T.eq(#env.readings, 0)
    T.truthy(env.w:IsLoading())
end)

T.test("login: reading at LOADING_SCREEN_DISABLED with arrivedAt, no leftAt", function()
    local env = make(OUTSIDE)
    login(env, 1)
    T.eq(#env.readings, 1)
    T.eq(env.readings[1].arrivedAt, 1.5)
    T.eq(env.readings[1].leftAt, nil)
    T.eq(env.readings[1].instanceType, "none")
    T.falsy(env.w:IsLoading())
end)

T.test("LOADING_SCREEN_DISABLED before PLAYER_ENTERING_WORLD: first reading waits for PEW", function()
    local env = make(OUTSIDE)
    env.w:OnEvent("LOADING_SCREEN_DISABLED", 5.2)
    ticks(env, 53, 59)
    T.eq(#env.readings, 0)
    env.w:OnEvent("PLAYER_ENTERING_WORLD", 6, true, false)
    env.w:Tick(6.1)
    T.eq(#env.readings, 1)
    T.eq(env.readings[1].arrivedAt, 5.2)
end)

T.test("polls once per second after the PEW-deferred read", function()
    local env = make(OUTSIDE)
    login(env, 0)          -- reading at 0.5
    ticks(env, 6, 50)      -- deferred read at 1.0, then polls at 2,3,4,5
    T.eq(#env.readings, 6)
end)

T.test("PEW failsafe: clears loading 10 s after PEW when LSD never comes", function()
    local env = make(OUTSIDE)
    env.w:OnEvent("PLAYER_ENTERING_WORLD", 0, true, false)
    ticks(env, 1, 99)
    T.eq(#env.readings, 0)
    env.w:Tick(10)
    T.eq(#env.readings, 1)
    T.eq(env.readings[1].arrivedAt, 10)
    T.falsy(env.w:IsLoading())
end)

T.test("LSE failsafe: clears loading 60 s after LSE with no PEW", function()
    local env = make(OUTSIDE)
    login(env, 0)
    env.w:OnEvent("LOADING_SCREEN_ENABLED", 100)
    local n = #env.readings
    env.w:Tick(159.9)
    T.eq(#env.readings, n)
    env.w:Tick(160)
    T.eq(#env.readings, n + 1)
    T.eq(env.readings[n + 1].leftAt, 100)
    T.eq(env.readings[n + 1].arrivedAt, 160)
end)

T.test("boundary hints only on the first valid reading after a loading screen", function()
    local env = make(OUTSIDE)
    login(env, 0)
    env.w:OnEvent("LOADING_SCREEN_ENABLED", 10)
    env.raw = inside(36)
    env.w:OnEvent("LOADING_SCREEN_DISABLED", 14)
    local r = env.readings[#env.readings]
    T.eq(r.leftAt, 10)
    T.eq(r.arrivedAt, 14)
    T.eq(r.instanceID, 36)
    env.w:Tick(15)
    r = env.readings[#env.readings]
    T.eq(r.leftAt, nil)
    T.eq(r.arrivedAt, nil)
end)

T.test("invalid reads are skipped and the hints wait for the first valid one", function()
    local env = make(OUTSIDE)
    login(env, 0)
    env.w:OnEvent("LOADING_SCREEN_ENABLED", 10)
    env.raw = { ok = true, inInstance = true, instanceType = "party", dogReadable = true, dog = false }
    env.w:OnEvent("LOADING_SCREEN_DISABLED", 14)
    local n = #env.readings
    env.w:Tick(15)
    env.raw = { ok = true, inInstance = true, instanceID = 0, instanceName = "X", instanceType = "party", dogReadable = true, dog = false }
    env.w:Tick(16)
    env.raw = { ok = false }
    env.w:Tick(17)
    env.raw = { ok = true, dogReadable = true, dog = false } -- inInstance missing
    env.w:Tick(18)
    T.eq(#env.readings, n)
    env.raw = inside(36)
    env.w:Tick(19)
    T.eq(#env.readings, n + 1)
    T.eq(env.readings[n + 1].leftAt, 10)
    T.eq(env.readings[n + 1].arrivedAt, 14)
end)

T.test("LOADING_SCREEN_ENABLED discards the last reading", function()
    local env = make(OUTSIDE)
    login(env, 0)
    T.truthy(env.w:GetLastReading())
    env.w:OnEvent("LOADING_SCREEN_ENABLED", 3)
    T.eq(env.w:GetLastReading(), nil)
end)

T.test("events during a loading screen update the dead flag but produce no reading", function()
    local env = make({ ok = true, inInstance = false, dogReadable = false })
    login(env, 0)
    env.w:OnEvent("LOADING_SCREEN_ENABLED", 10)
    local n = #env.readings
    env.w:OnEvent("PLAYER_DEAD", 11)
    T.eq(#env.readings, n)
    T.truthy(env.w:GetDeadFlag())
end)

T.test("dead fallback follows events when UnitIsDeadOrGhost is unreadable", function()
    local env = make({ ok = true, inInstance = false, dogReadable = false })
    login(env, 0)
    T.falsy(env.readings[1].dead)
    T.truthy(env.w:IsUsingDeadFallback())
    env.w:OnEvent("PLAYER_DEAD", 2)
    T.truthy(env.readings[#env.readings].dead)
    env.raw = { ok = true, inInstance = false, dogReadable = false, ghostReadable = true, ghost = true }
    env.w:OnEvent("PLAYER_ALIVE", 3) -- released: now a ghost, still "dead"
    T.truthy(env.readings[#env.readings].dead)
    env.raw = { ok = true, inInstance = false, dogReadable = false }
    env.w:OnEvent("PLAYER_UNGHOST", 4)
    T.falsy(env.readings[#env.readings].dead)
end)

T.test("PLAYER_ALIVE with unreadable UnitIsGhost leaves the flag unchanged", function()
    local env = make({ ok = true, inInstance = false, dogReadable = false })
    login(env, 0)
    env.w:OnEvent("PLAYER_DEAD", 1)
    env.w:OnEvent("PLAYER_ALIVE", 2)
    T.truthy(env.readings[#env.readings].dead)
end)

T.test("fallback is seeded from the saved flag when nothing is readable", function()
    local env = make({ ok = true, inInstance = false, dogReadable = false }, true)
    login(env, 0)
    T.truthy(env.readings[1].dead)
end)

T.test("readable UnitIsGhost/UnitIsDead override the saved flag", function()
    local env = make({ ok = true, inInstance = false, dogReadable = false,
                       ghostReadable = true, ghost = false, deadReadable = true, deadOnly = false }, true)
    login(env, 0)
    T.falsy(env.readings[1].dead)
end)

T.test("readable UnitIsDeadOrGhost always wins and updates the flag", function()
    local env = make(inside(36, true), false)
    login(env, 0)
    T.truthy(env.readings[1].dead)
    T.truthy(env.w:GetDeadFlag())
    T.falsy(env.w:IsUsingDeadFallback())
end)
