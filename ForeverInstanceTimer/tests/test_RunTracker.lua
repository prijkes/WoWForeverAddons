local T = ...
local ns = require("loader").load({}, "RunTracker.lua")
local RT = ns.RunTracker

local function rules(over)
    local r = { types = { party = true, raid = true, pvp = true }, awayMode = "count",
                giveUp = "ghost", graceMinutes = 15, offline = "count" }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
end

local function make(over, store)
    local env = { rules = rules(over), store = store or {}, starts = {}, finishes = {} }
    env.rt = RT.New(env.store, function() return env.rules end, {
        onStart = function(i) env.starts[#env.starts + 1] = i end,
        onFinish = function(i) env.finishes[#env.finishes + 1] = i end,
    })
    return env
end

local function In(t, id, extra)
    local r = { at = t, inInstance = true, instanceID = id or 36, instanceName = "Inst" .. (id or 36),
                instanceType = "party", dead = false }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

local function Out(t, extra)
    local r = { at = t, inInstance = false, instanceType = "none", dead = false }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

local function obs(env, r) env.rt:Observe(r, r.at) end

-- Arrive in instance `id` at time t; confirmed by a reading 1 s later. Run start = t.
local function enter(env, t, id)
    obs(env, In(t, id, { arrivedAt = t }))
    obs(env, In(t + 1, id))
end

-- From INSIDE: release and land outside as a ghost; the leaving loading screen starts at t.
local function dieOut(env, t)
    obs(env, Out(t + 10, { dead = true, leftAt = t, arrivedAt = t + 5 }))
end

T.test("a start needs a confirming reading >= 1 s later and starts at arrivedAt", function()
    local env = make()
    obs(env, In(10, 36, { arrivedAt = 9 }))
    T.eq(env.rt:GetState(), "idle")
    obs(env, In(10.5, 36))
    T.eq(env.rt:GetState(), "idle", "under 1 s never confirms")
    obs(env, In(11, 36))
    T.eq(env.rt:GetState(), "inside")
    T.eq(env.rt:GetElapsed(19), 10)
    T.eq(#env.starts, 1)
    T.eq(env.rt:GetInstanceName(), "Inst36")
end)

T.test("a pending start is dropped when the next reading disagrees", function()
    local env = make()
    obs(env, In(10, 36))
    obs(env, Out(11))
    T.eq(env.rt:GetState(), "idle")
    T.eq(env.rt:GetRun().pending, nil)
end)

T.test("disabled instance types never start a run", function()
    local env = make({ types = { party = true, raid = false, pvp = true } })
    obs(env, In(10, 409, { instanceType = "raid" }))
    obs(env, In(11, 409, { instanceType = "raid" }))
    T.eq(env.rt:GetState(), "idle")
end)

T.test("leaving alive finishes at leftAt once confirmed; display holds meanwhile", function()
    local env = make()
    enter(env, 100)
    obs(env, Out(200, { leftAt = 190, arrivedAt = 195 }))
    T.eq(env.rt:GetState(), "inside", "pending finish")
    T.eq(env.rt:GetDisplayElapsed(200.5), 90)
    obs(env, Out(200.4))
    T.eq(#env.finishes, 0, "under 1 s never confirms")
    obs(env, Out(201))
    T.eq(env.rt:GetState(), "idle")
    T.eq(env.finishes[1].seconds, 90)
    T.eq(env.finishes[1].reason, "left")
    T.eq(env.finishes[1].silent, false)
    T.eq(env.finishes[1].replaced, false)
    T.eq(env.finishes[1].name, "Inst36")
end)

T.test("a same-instance reading drops a pending finish", function()
    local env = make()
    enter(env, 100)
    obs(env, Out(200, { leftAt = 190 }))
    obs(env, In(200.5, 36))
    obs(env, Out(202))
    obs(env, In(202.5, 36))
    T.eq(env.rt:GetState(), "inside")
    T.eq(#env.finishes, 0)
end)

T.test("leaving dead goes AWAY immediately at leftAt and keeps counting", function()
    local env = make()
    enter(env, 100)
    dieOut(env, 190)
    T.eq(env.rt:GetState(), "away")
    T.eq(env.rt:GetRun().awaySince, 190)
    T.eq(env.rt:GetElapsed(300), 200)
end)

T.test("a dead confirming reading turns a pending finish into AWAY", function()
    local env = make()
    enter(env, 100)
    obs(env, Out(200, { leftAt = 190 }))
    obs(env, Out(201, { dead = true }))
    T.eq(env.rt:GetState(), "away")
    T.eq(env.rt:GetRun().awaySince, 190)
    T.eq(#env.finishes, 0)
end)

T.test("ghost run-back and re-entry resumes the run", function()
    local env = make()
    enter(env, 100)
    dieOut(env, 190)
    obs(env, Out(260, { dead = true }))
    obs(env, In(300, 36, { dead = true, leftAt = 295, arrivedAt = 298 }))
    T.eq(env.rt:GetState(), "inside")
    T.eq(env.rt:GetElapsed(310), 210)
    T.eq(#env.finishes, 0)
end)

T.test("a revive at the portal (before the loading screen) does not end the run", function()
    local env = make()
    enter(env, 100)
    dieOut(env, 190)
    obs(env, Out(290)) -- alive outside: revive pending
    T.eq(env.rt:GetRun().revivedAt, 290)
    obs(env, In(298, 36, { leftAt = 291, arrivedAt = 298 }))
    T.eq(env.rt:GetState(), "inside")
    T.eq(env.rt:GetRun().revivedAt, nil)
    T.eq(#env.finishes, 0)
end)

T.test("spirit healer: alive outside for >= 3 s ends the run at the revive moment", function()
    local env = make()
    enter(env, 100)
    dieOut(env, 190)
    obs(env, Out(400))
    T.eq(env.rt:GetDisplayElapsed(402), 300, "display holds at the revive moment")
    obs(env, Out(401))
    T.eq(env.rt:GetState(), "away")
    obs(env, Out(403))
    T.eq(env.rt:GetState(), "idle")
    T.eq(env.finishes[1].seconds, 300)
    T.eq(env.finishes[1].reason, "revived")
end)

T.test("dead again clears a pending revive", function()
    local env = make()
    enter(env, 100)
    dieOut(env, 190)
    obs(env, Out(400))
    obs(env, Out(401, { dead = true }))
    T.eq(env.rt:GetRun().revivedAt, nil)
    obs(env, Out(405))
    T.eq(env.rt:GetRun().revivedAt, 405)
    T.eq(#env.finishes, 0)
end)

T.test("grace rule finishes at awaySince + grace, even after a long gap", function()
    local env = make({ giveUp = "grace", graceMinutes = 15 })
    enter(env, 100)
    dieOut(env, 190)
    obs(env, Out(1000))
    T.eq(env.rt:GetState(), "away", "being alive does not matter for grace")
    obs(env, Out(50000))
    T.eq(env.rt:GetState(), "idle")
    T.eq(env.finishes[1].seconds, 990)
    T.eq(env.finishes[1].reason, "grace")
end)

T.test("never rule waits indefinitely", function()
    local env = make({ giveUp = "never" })
    enter(env, 100)
    dieOut(env, 190)
    obs(env, Out(100000))
    obs(env, Out(100010))
    T.eq(env.rt:GetState(), "away")
end)

T.test("pause-while-away freezes the timer from leftAt to arrivedAt", function()
    local env = make({ awayMode = "pause" })
    enter(env, 100)
    dieOut(env, 190)
    T.eq(env.rt:GetElapsed(500), 90)
    obs(env, In(600, 36, { dead = true, leftAt = 590, arrivedAt = 598 }))
    T.eq(env.rt:GetElapsed(700), 192)
end)

T.test("a revive finish in pause mode keeps the frozen time", function()
    local env = make({ awayMode = "pause" })
    enter(env, 100)
    dieOut(env, 190)
    obs(env, Out(400))
    obs(env, Out(403))
    T.eq(env.finishes[1].seconds, 90)
end)

T.test("direct switch: old run finishes (replaced) at leftAt, new starts at arrivedAt", function()
    local env = make()
    enter(env, 100, 36)
    obs(env, In(200, 48, { leftAt = 190, arrivedAt = 195 }))
    T.eq(env.rt:GetDisplayElapsed(200), 90)
    obs(env, In(201, 48))
    T.eq(env.finishes[1].seconds, 90)
    T.eq(env.finishes[1].reason, "switched")
    T.eq(env.finishes[1].replaced, true)
    T.eq(env.rt:GetState(), "inside")
    T.eq(env.rt:GetRun().key, 48)
    T.eq(env.rt:GetElapsed(205), 10)
end)

T.test("switch from AWAY finishes the old run including the corpse run", function()
    local env = make()
    enter(env, 100, 36)
    dieOut(env, 190)
    obs(env, In(500, 48, { dead = true, leftAt = 495, arrivedAt = 499 }))
    obs(env, In(501, 48))
    T.eq(env.finishes[1].seconds, 395)
    T.eq(env.rt:GetRun().key, 48)
    T.eq(env.rt:GetRun().start, 499)
end)

T.test("dying and resurrecting inside changes nothing", function()
    local env = make()
    enter(env, 100)
    obs(env, In(150, 36, { dead = true }))
    obs(env, In(160, 36))
    T.eq(env.rt:GetState(), "inside")
    T.eq(env.rt:GetElapsed(200), 100)
    T.eq(#env.finishes, 0)
end)

T.test("multi-wing dungeon: the same map ID resumes the run", function()
    local env = make()
    enter(env, 100, 189)
    dieOut(env, 190)
    obs(env, In(300, 189, { dead = true, arrivedAt = 299 }))
    T.eq(env.rt:GetState(), "inside")
    T.eq(#env.finishes, 0)
end)

T.test("disabling a type does not end a run in progress", function()
    local env = make()
    enter(env, 100)
    env.rules.types.party = false
    obs(env, In(200, 36))
    T.eq(env.rt:GetState(), "inside")
end)

-- Lifecycle: login, logout, rule changes, reset, validation ----------------------------------

T.test("logout stores lastSeen", function()
    local env = make()
    env.rt:OnLogout(500)
    T.eq(env.store.lastSeen, 500)
end)

T.test("offline keep-counting: offline time counts", function()
    local env = make()
    enter(env, 100)
    env.rt:OnLogout(200)
    env.rt:OnLogin(5000)
    T.eq(env.rt:GetElapsed(5000), 4900)
end)

T.test("offline pause: offline time is excluded", function()
    local env = make({ offline = "pause" })
    enter(env, 100)
    env.rt:OnLogout(200)
    env.rt:OnLogin(5000)
    T.eq(env.rt:GetElapsed(5000), 100)
end)

T.test("offline pause with an open away-pause is not double counted", function()
    local env = make({ offline = "pause", awayMode = "pause" })
    enter(env, 100)
    dieOut(env, 190)
    env.rt:OnLogout(300)
    env.rt:OnLogin(5000)
    T.eq(env.rt:GetElapsed(5000), 90)
end)

T.test("keep-counting with an open away-pause excludes offline time", function()
    local env = make({ awayMode = "pause" })
    enter(env, 100)
    dieOut(env, 190)
    env.rt:OnLogout(300)
    env.rt:OnLogin(5000)
    T.eq(env.rt:GetElapsed(5000), 90)
end)

T.test("offline reset clears the run silently, even a pending one", function()
    local env = make({ offline = "reset" })
    enter(env, 100)
    obs(env, Out(200, { leftAt = 190 }))
    env.rt:OnLogout(200.5)
    env.rt:OnLogin(300)
    T.eq(env.rt:GetState(), "idle")
    T.eq(env.rt:GetRun().pending, nil)
    T.eq(#env.finishes, 0)
end)

T.test("the offline policy is applied before pause reconciliation", function()
    local env = make()
    enter(env, 100)
    dieOut(env, 190) -- away, counting (no pause)
    env.rt:OnLogout(300)
    env.rules.offline = "pause" -- both changed on another character
    env.rules.awayMode = "pause"
    env.rt:OnLogin(1000)
    T.eq(env.rt:GetElapsed(1000), 200)
    T.eq(env.rt:GetElapsed(2000), 200)
end)

T.test("a finish started by the first reading after login is silent", function()
    local env = make()
    enter(env, 100)
    env.rt:OnLogout(200)
    env.rt:OnLogin(5000)
    obs(env, Out(5000, { arrivedAt = 5000 }))
    obs(env, Out(5001))
    T.eq(env.finishes[1].silent, true)
end)

T.test("only the first valid reading after login is silent", function()
    local env = make()
    enter(env, 100)
    env.rt:OnLogin(5000)
    obs(env, In(5000, 36))
    obs(env, Out(6000, { leftAt = 5990 }))
    obs(env, Out(6001))
    T.eq(env.finishes[1].silent, false)
end)

T.test("a revive started by the first reading after login finishes silently", function()
    local env = make()
    enter(env, 100)
    dieOut(env, 190)
    env.rt:OnLogout(300)
    env.rt:OnLogin(1000)
    obs(env, Out(1000))
    obs(env, Out(1003))
    T.eq(env.finishes[1].silent, true)
end)

T.test("a pending transition survives a reload and confirms loudly", function()
    local env = make()
    enter(env, 100)
    obs(env, Out(200, { leftAt = 190 }))
    local env2 = make(nil, env.store) -- /reload: new tracker, same saved table
    obs(env2, Out(201))
    T.eq(env2.finishes[1].seconds, 90)
    T.eq(env2.finishes[1].silent, false)
end)

T.test("away-mode changes open and close a pause at that moment", function()
    local env = make()
    enter(env, 100)
    dieOut(env, 190)
    env.rules.awayMode = "pause"
    env.rt:OnRulesChanged(300)
    T.eq(env.rt:GetElapsed(400), 200)
    env.rules.awayMode = "count"
    env.rt:OnRulesChanged(500)
    T.eq(env.rt:GetElapsed(600), 300)
end)

T.test("switching the give-up rule away from ghost clears a pending revive", function()
    local env = make()
    enter(env, 100)
    dieOut(env, 190)
    obs(env, Out(400))
    env.rules.giveUp = "never"
    env.rt:OnRulesChanged(401)
    T.eq(env.rt:GetRun().revivedAt, nil)
    obs(env, Out(410))
    T.eq(env.rt:GetState(), "away")
end)

T.test("manual reset inside restarts the run from now, silently", function()
    local env = make()
    enter(env, 100)
    env.rt:Reset(500, In(499, 36))
    T.eq(env.rt:GetState(), "inside")
    T.eq(env.rt:GetElapsed(510), 10)
    T.eq(#env.finishes, 0)
end)

T.test("manual reset without a fresh reading goes idle", function()
    local env = make()
    enter(env, 100)
    env.rt:Reset(500, nil)
    T.eq(env.rt:GetState(), "idle")
end)

T.test("manual reset clears a pending transition", function()
    local env = make()
    enter(env, 100)
    obs(env, Out(200, { leftAt = 190 }))
    env.rt:Reset(200.5, nil)
    obs(env, Out(201))
    T.eq(env.rt:GetState(), "idle")
    T.eq(#env.finishes, 0)
end)

T.test("validation keeps good data and discards malformed data", function()
    local good = { run = { state = "inside", key = 36, name = "X", start = 1, paused = 0 }, lastSeen = 5 }
    T.falsy(make(nil, good).rt.validationFailed)
    T.eq(good.run.state, "inside")

    local fresh = {}
    T.falsy(make(nil, fresh).rt.validationFailed)
    T.eq(fresh.run.state, "idle")

    local cases = {
        { run = { state = "bogus" } },
        { run = "text" },
        { run = { state = "inside", key = "x", name = "X", start = 1 } },
        { run = { state = "away", key = 36, name = "X", start = 1 } }, -- no awaySince
        { run = { state = "inside", key = 36, name = "X", start = 1, pending = { kind = "finish" } } },
        { run = { state = "idle", pending = { kind = "finish", at = 1, firstSeen = 1 } } },
        { run = { state = "inside", key = 36, name = "X", start = 1, -- a start only exists while idle
                  pending = { kind = "start", key = 48, name = "Y", at = 1, firstSeen = 1, arrivedAt = 1 } } },
    }
    for i, store in ipairs(cases) do
        T.truthy(make(nil, store).rt.validationFailed, "case " .. i)
        T.eq(store.run.state, "idle", "case " .. i)
    end

    local badSeen = { lastSeen = "x" }
    make(nil, badSeen)
    T.eq(badSeen.lastSeen, nil)
end)
