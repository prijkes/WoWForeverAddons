-- End-to-end event timelines: ZoneWatcher feeding RunTracker, with a 10 Hz tick like Core.
local T = ...
local ns = require("loader").load({}, "ZoneWatcher.lua", "RunTracker.lua")

local function raw(inInstance, deadOrGhost, ghost, readable)
    if readable == nil then readable = true end
    return {
        ok = true, inInstance = inInstance,
        instanceID = inInstance and 36 or nil, instanceName = inInstance and "The Deadmines" or nil,
        instanceType = inInstance and "party" or nil,
        dogReadable = readable, dog = deadOrGhost or false,
        ghostReadable = readable, ghost = ghost or false,
        deadReadable = readable, deadOnly = (deadOrGhost and not ghost) or false,
    }
end
local OUT, OUT_GHOST = raw(false), raw(false, true, true)
local IN, IN_DEAD = raw(true), raw(true, true, false)

local function make()
    local env = { finishes = {}, store = {} }
    env.rules = { types = { party = true, raid = true, pvp = true }, awayMode = "count",
                  giveUp = "ghost", graceMinutes = 15, offline = "count" }
    env.rt = ns.RunTracker.New(env.store, function() return env.rules end,
        { onFinish = function(i) env.finishes[#env.finishes + 1] = i end })
    env.w = ns.ZoneWatcher.New(function() return env.raw end,
        function(r, now) env.rt:Observe(r, now) end, false)
    return env
end

local function run(env, from, to) -- 10 Hz ticks from `from` to `to`
    for i = math.floor(from * 10 + 0.5), math.floor(to * 10 + 0.5) do env.w:Tick(i / 10) end
end

local function zone(env, t, newRaw, seconds) -- a loading screen from t to t + seconds
    env.w:OnEvent("LOADING_SCREEN_ENABLED", t)
    env.raw = newRaw
    env.w:OnEvent("PLAYER_ENTERING_WORLD", t + seconds - 0.1, false, false)
    env.w:OnEvent("LOADING_SCREEN_DISABLED", t + seconds)
end

local function loginAndEnter(env) -- log in outside, then arrive in the dungeon at t = 13
    env.raw = OUT
    env.rt:OnLogin(0)
    env.w:OnEvent("PLAYER_ENTERING_WORLD", 0, true, false)
    env.w:OnEvent("LOADING_SCREEN_DISABLED", 0.5)
    run(env, 0.6, 9)
    zone(env, 10, IN, 3)
    run(env, 13.1, 20)
end

T.test("enter and walk out alive: the run lasts from arrival to departure", function()
    local env = make()
    loginAndEnter(env)
    T.eq(env.rt:GetState(), "inside")
    zone(env, 100, OUT, 4)
    run(env, 104.1, 107)
    T.eq(env.rt:GetState(), "idle")
    T.eq(env.finishes[1].reason, "left")
    T.near(env.finishes[1].seconds, 87, 1e-6)
end)

T.test("revived at the portal (PLAYER_ALIVE before LOADING_SCREEN_ENABLED): the run continues", function()
    local env = make()
    loginAndEnter(env)
    env.raw = IN_DEAD
    env.w:OnEvent("PLAYER_DEAD", 50)
    run(env, 50.1, 59)
    zone(env, 60, OUT_GHOST, 4) -- release: ghost at the graveyard
    run(env, 64.1, 119)
    T.eq(env.rt:GetState(), "away")
    env.raw = OUT -- resurrected at the portal, just before the teleport
    env.w:OnEvent("PLAYER_UNGHOST", 120)
    env.w:OnEvent("PLAYER_ALIVE", 120.05)
    zone(env, 120.3, IN, 3)
    run(env, 123.4, 130)
    T.eq(env.rt:GetState(), "inside")
    T.eq(#env.finishes, 0)
    T.near(env.rt:GetElapsed(130), 117, 1e-6)
end)

T.test("spirit healer outside: the run ends 3 s later, timed at the revive", function()
    local env = make()
    loginAndEnter(env)
    zone(env, 60, OUT_GHOST, 4)
    run(env, 64.1, 89)
    env.raw = OUT
    env.w:OnEvent("PLAYER_UNGHOST", 90)
    run(env, 90.1, 95)
    T.eq(env.rt:GetState(), "idle")
    T.eq(env.finishes[1].reason, "revived")
    T.near(env.finishes[1].seconds, 77, 1e-6)
end)

T.test("secret UnitIsDeadOrGhost: the event-tracked flag keeps the run through a corpse run", function()
    local env = make()
    env.raw = raw(false, false, false, false)
    env.rt:OnLogin(0)
    env.w:OnEvent("PLAYER_ENTERING_WORLD", 0, true, false)
    env.w:OnEvent("LOADING_SCREEN_DISABLED", 0.5)
    run(env, 0.6, 9)
    zone(env, 10, raw(true, false, false, false), 3)
    run(env, 13.1, 20)
    T.eq(env.rt:GetState(), "inside")
    env.w:OnEvent("PLAYER_DEAD", 50)
    zone(env, 60, raw(false, false, false, false), 4) -- released; death state unreadable
    run(env, 64.1, 100)
    T.eq(env.rt:GetState(), "away")
    zone(env, 100, raw(true, false, false, false), 3)
    env.w:OnEvent("PLAYER_UNGHOST", 103.2)
    run(env, 103.1, 110)
    T.eq(env.rt:GetState(), "inside")
    T.eq(#env.finishes, 0)
    T.truthy(env.w:IsUsingDeadFallback())
end)
