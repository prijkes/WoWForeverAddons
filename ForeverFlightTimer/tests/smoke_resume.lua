-- The UI session after tests/smoke.lua's logout mid-flight, in a fresh process with the saved
-- variables. smoke.lua runs it:  luajit tests/smoke_resume.lua <kind> <file>
--   reload    /reload: GetTime() runs on, the takeoff is kept, and the flight is still recorded
--   relog     a login 5 min later: the offline time is left out, and the flight isn't recorded
--   pick      /reload after the player got off: opening a flight map ends the saved flight
--   autotaxi  the same, but another addon picks inside the TAXIMAP_OPENED dispatch, before our
--             handler, and the click closes the map again: the next flight must not be taken
--             for the saved one
-- The saved flight: 25>80 (52.2 s, learned once), logged out 20.2 s after takeoff.
package.path = "tests/lib/?.lua;" .. package.path
local W = require("wowstub")
local X = require("taxiworld")
local check = W.check
local kind, file = arg[1], arg[2]
local stillFlying = kind == "reload" or kind == "relog"

if os.getenv("FFT_SMOKE_FLIGHTMAP_PRELOADED") then X.defineFlightMap() end
X.install()
local saved = X.restoreSession(file)
local flight = ForeverFlightTimerCharDB.flight
check(type(flight) == "table" and flight.route and flight.route.key == "25>80", "the saved flight was restored")
ForeverFlightTimerDB.global.debug = kind ~= "relog"
local ns = {}
X.load(ns)
W.now = saved.now + (kind == "relog" and 300 or 2)
X.taxi.onTaxi = stillFlying

W.fireEvent("ADDON_LOADED", "ForeverFlightTimer")
W.fireEvent("PLAYER_ENTERING_WORLD", kind == "relog", kind ~= "relog")
W.tick(0.5)
local timer = _G.ForeverFlightTimerFrame
check(not timer:IsShown(), "nothing is shown during the loading screen")
if kind == "reload" then
    TakeTaxiNode(2) -- a stray call with no flight map (another addon, a macro): ignored
    check(ForeverFlightTimerCharDB.flight ~= nil, "a stray TakeTaxiNode doesn't drop the saved flight")
end
W.fireEvent("LOADING_SCREEN_DISABLED")
W.tick(0.2)
local shown = timer.timeText:GetText()

if kind == "reload" then
    -- 22.9 s flown (20.2 + 2 + 0.5 + 0.2), so 29.3 s of 52.2 left
    check(timer:IsShown() and shown:find("^0:29 ") ~= nil, "the countdown carries on from the original takeoff: " .. tostring(shown))
    W.tick(29.3)
    W.clearChat(); X.land()
    check(W.chatHas("Crossroads -> Ratchet: 0:52 (expected 0:52)"), "a /reload mid-flight is still recorded")
    check(W.chatHas("landing position: unavailable (no pick of this route this session)"),
          "debug: a resumed flight has no picked destination to measure against")
    check(X.routes()["25>80"].flights == 2, "the resumed flight was counted")
elseif kind == "relog" then
    -- 20.2 s flown before logging out, 0.2 s since: 31.8 s left
    check(timer:IsShown() and shown:find("^0:31 ") ~= nil, "the countdown resumes without the offline time: " .. tostring(shown))
    W.tick(31.8)
    W.clearChat(); X.land()
    check(W.chatHas("Crossroads -> Ratchet: 0:52 (not recorded: relogged during the flight)"), "a relog mid-flight isn't recorded")
    check(X.routes()["25>80"].flights == 1, "the relogged flight was not counted")
elseif kind == "pick" then
    check(not timer:IsShown() and ForeverFlightTimerCharDB.flight ~= nil, "resuming: waiting for the taxi flag")
    W.clearChat()
    X.openMap()
    check(ForeverFlightTimerCharDB.flight == nil, "a flight map proves the player is on the ground: the saved flight goes")
    check(W.chatHas("the saved flight is over: a flight map opened"), "debug: says why the saved flight went")
    TakeTaxiNode(3)
    X.closeMap(); X.takeoff(); W.tick(80)
    W.clearChat(); X.land()
    check(W.chatHas("Crossroads -> Orgrimmar: 1:20 (new route learned)"), "the new flight is tracked")
else
    check(ForeverFlightTimerCharDB.flight ~= nil, "resuming: waiting for the taxi flag")
    X.taxi.live, X.taxi.closeOnTake = true, true -- the server opened the map; another addon picks first
    W.clearChat()
    TakeTaxiNode(3)
    X.taxi.closeOnTake = false
    check(W.chatHas("could not be resolved") and W.chatHas("a flight map closed in this frame")
          and W.chatHas("the saved flight is dropped"), "debug: the auto-taxi pick is unresolved and ends the saved flight")
    check(ForeverFlightTimerCharDB.flight == nil, "the saved flight is gone")
    check(W.chatHas("(no open map session)"), "debug: a map close no session of ours saw")
    W.clearChat()
    W.fireEvent("TAXIMAP_OPENED", 1) -- our handler runs after the other addon's
    check(W.chatHas("no nodes: the map had closed again"), "debug: the map had already closed again at our handler")
    X.takeoff(); W.tick(80)
    W.clearChat(); X.land()
    check(W.chatHas("flight: 1:20 (not recorded: unknown route)"), "the next flight is untracked, not taken for the saved one")
    check(X.routes()["25>80"].flights == 1, "the saved route's time is untouched")
end
check(ForeverFlightTimerCharDB.flight == nil, "no saved flight is left")
W.report("smoke, next session (" .. tostring(kind) .. ")")
