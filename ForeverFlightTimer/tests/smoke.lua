-- Headless smoke test for Forever Flight Timer. From the addon root:  luajit tests/smoke.lua
--   FFT_SMOKE_BREAK_SETTINGS=1       simulate a broken Settings API: the timer must keep working
--   FFT_SMOKE_FLIGHTMAP_PRELOADED=1  Blizzard_FlightMap is already loaded when the addon starts
-- It ends by starting tests/smoke_resume.lua three times: a /reload, a relog, and a pick while
-- resuming, each a new UI session in a fresh process (as in the game).
-- If a LIBRARY fails for a missing WoW global, add a stub (never edit library code).
package.path = "tests/lib/?.lua;" .. package.path
local W = require("wowstub")
local X = require("taxiworld")
local check = W.check
local PRELOADED = os.getenv("FFT_SMOKE_FLIGHTMAP_PRELOADED") ~= nil
local MODE = W.BREAK_SETTINGS and "broken" or (PRELOADED and "preloaded" or "normal")
local taxi, slash, routes = X.taxi, X.slash, X.routes

if PRELOADED then X.defineFlightMap() end
X.install()
local ns = {}
X.load(ns)
check(ns.TimeFormat and ns.ArrivalClock and ns.RealmClock and ns.RouteStore and ns.FlightTracker and ns.DEFAULTS
      and ns.Display and ns.Options, "all modules loaded into the namespace")

-------------------------------------------------------------------------------- helpers
local timer
local function texts() return timer.nameText:GetText(), timer.timeText:GetText(), timer.arrivalText:GetText() end
local function timeText() return (select(2, texts())) end
local function expect(label, got, pattern)
    check(type(got) == "string" and got:find(pattern) ~= nil, ("%s: got %q"):format(label, tostring(got)))
end
local function barIs(colorKey, value)
    local c, want = rawget(timer.bar, "_barColor") or {}, X.profile().colors[colorKey]
    local sameColor = math.abs((c[1] or -1) - want.r) < 1e-6 and math.abs((c[2] or -1) - want.g) < 1e-6
        and math.abs((c[3] or -1) - want.b) < 1e-6
    return sameColor and math.abs(timer.bar:GetValue() - value) < 0.01
end
local function state()
    W.clearChat(); slash("status")
    for _, m in ipairs(W.chat) do
        local s = m:match("tracker: (%a+);")
        if s then return s end
    end
end

-------------------------------------------------------------------------------- session
W.fireEvent("ADDON_LOADED", "ForeverFlightTimer")
check(type(ForeverFlightTimerCharDB) == "table", "per-character saved table created")
check(SlashCmdList.FOREVERFLIGHTTIMER ~= nil, "slash command registered")
if W.BREAK_SETTINGS then
    check(W.chatHas("options panel is unavailable"), "a broken Settings API is reported in chat")
end
if not PRELOADED then
    X.defineFlightMap()
    W.fireEvent("ADDON_LOADED", "Blizzard_FlightMap")
end

W.fireEvent("PLAYER_ENTERING_WORLD", true, false)
W.tick(0.5)
W.fireEvent("LOADING_SCREEN_DISABLED")
W.tick(1)
timer = _G.ForeverFlightTimerFrame
check(timer and not timer:IsShown(), "no timer on the ground")

-- 1. First flight on a route: learning, then learned. Flights last 52.2 s: the takeoff tick + 52.
X.openMap()
TaxiNodeOnButtonEnter(X.button(2))
check(W.linesHave("Flight time: not flown yet"), "classic tooltip marks an unknown route")
TakeTaxiNode(2)
X.closeMap()
W.tick(1)
X.takeoff()
check(timer:IsShown(), "timer shown while flying")
W.tick(10.5)
local name, time, arrival = texts()
check(name == "Ratchet", "learning: the destination, got " .. tostring(name))
expect("learning: elapsed time", time, "^0:10 %(learning%)$")
check(arrival == "", "learning: no arrival clock")
check(barIs("learning", 1), "learning: a full bar in the learning colour")
W.clearChat(); slash("status")
check(W.chatHas("(learning) - Ratchet"), "status shows learning")
W.tick(41.5)
W.clearChat(); X.land()
check(W.chatHas("Forever Flight Timer|r: Crossroads -> Ratchet: 0:52 (new route learned)"), "landing line for a new route")
check(routes()["25>80"] ~= nil, "route learned under its path key")
check(not timer:IsShown(), "timer hidden after landing (no freeze by default)")

-- 2. The same route: countdown, bar, every clock choice, arrival placement, count-up, overtime.
X.openMap()
TaxiNodeOnButtonEnter(X.button(2))
check(W.linesHave("Flight time: 0:52"), "classic tooltip shows the learned time")
TakeTaxiNode(2)
X.closeMap()
X.takeoff()
W.tick(10.3) -- elapsed 10.5, 41.7 left; the next 3 ticks stay within "0:41"
name, time, arrival = texts()
expect("countdown, clock CVars unreadable (local time, 24 h)", time, "^0:41 %(20:%d%d%)$")
check(arrival == "", "countdown: the arrival clock goes after the time by default")
check(barIs("countdown", 41.7 / 52.2), "countdown: the bar drains in the countdown colour")
W.clearChat(); slash("status")
check(W.chatHas("0:41 left - Ratchet"), "status shows the countdown")
X.cvars.timeMgrUseLocalTime, X.cvars.timeMgrUseMilitaryTime = false, false -- the client's defaults
W.tick(0.1)
expect("countdown, the client's default clock (realm time, 12 h)", timeText(), "^0:41 %(3:%d%d AM%)$")
local p = X.profile()
p.clockSource, p.clockFormat = "local", "12"
W.tick(0.1)
expect("clock override: local, 12 h", timeText(), "^0:41 %(8:%d%d PM%)$")
p.clockSource, p.clockFormat = "realm", "24"
W.tick(0.1) -- elapsed 10.8, 41.4 left
expect("clock override: realm, 24 h", timeText(), "^0:41 %(03:%d%d%)$")
p.arrivalPos = "below"
ns.Display:ApplySettings()
name, time, arrival = texts()
check(time == "0:41" and arrival:find("^lands at 03:%d%d$") ~= nil,
      ("arrival clock below the bar: %q / %q"):format(tostring(time), tostring(arrival)))
p.arrivalPos, p.showTime = "after", false
ns.Display:ApplySettings()
expect("time hidden: the arrival clock on its own", timeText(), "^03:%d%d$")
p.showTime, p.countUp, p.barFill = true, true, "fill"
ns.Display:ApplySettings()
expect("count up on a known route", timeText(), "^0:10 %(03:%d%d%)$")
check(barIs("countdown", 1 - 41.4 / 52.2), "fill: the bar fills as you fly")
W.tick(45) -- elapsed 55.8: 3.6 s over
expect("overtime while counting up: it just carries on", timeText(), "^0:55$")
check(barIs("overtime", 1), "overtime: a full bar in the overtime colour")
p.countUp = false
ns.Display:ApplySettings()
expect("overtime", timeText(), "^%+0:03$")
W.clearChat(); X.land()
check(W.chatHas("Crossroads -> Ratchet: 0:55 (expected 0:52)"), "landing line mentions the expected time")
X.aceDB():ResetProfile()

-- 3. A multi-hop path is keyed by its hops.
X.flyTo(3, 80)
check(routes()["25>77>23"] ~= nil, "multi-hop path key lists every hop")

-- 4. Unreachable and failed picks.
X.openMap(); TakeTaxiNode(5); X.closeMap(); X.takeoff(); W.tick(10)
name = texts()
check(name == "Flight" and barIs("learning", 1), "an untracked flight is labelled Flight, in the learning colour")
W.clearChat(); X.land()
check(W.chatHas("flight: 0:10 (not recorded: unknown route)"), "unreachable click ignored -> untracked flight")
X.openMap(); TakeTaxiNode(2)
W.fireEvent("UI_ERROR_MESSAGE", 1, "ERR_TAXINOTENOUGHMONEY (text)")
check(state() == "idle", "a taxi error (by its token) cancels the pending pick")
X.closeMap()
X.openMap(); TakeTaxiNode(2)
W.fireEvent("UI_ERROR_MESSAGE", 2, "ERR_TAXIPLAYERMOVING (text)") -- no token for this error type
check(state() == "idle", "a taxi error matched by its message text cancels the pending pick")
X.closeMap()
X.openMap(); TakeTaxiNode(2)
W.fireEvent("UI_ERROR_MESSAGE", 3, "You are too far away.")
check(state() == "pending", "other errors leave the pick alone")
X.closeMap()
W.tick(20.5)
check(state() == "idle", "a pick without a takeoff expires after 20 s")

-- 5. The click closes the map before our post-hook: the just-closed session resolves the pick.
X.openMap()
taxi.closeOnTake = true
TakeTaxiNode(4)
taxi.closeOnTake = false
X.takeoff(); W.tick(30); X.land()
check(routes()["25>77"] ~= nil, "a pick whose click closed the map still resolves")
-- Such a pick that never takes off is cancelled by the next map session, as it is from an earlier frame.
X.openMap(); taxi.closeOnTake = true; TakeTaxiNode(4); taxi.closeOnTake = false
W.tick(2)
X.openMap(); TakeTaxiNode(2); X.closeMap(); X.takeoff(); W.tick(52)
W.clearChat(); X.land()
check(W.chatHas("Crossroads -> Ratchet: 0:52") and not W.chatHas("two destinations"),
      "a new map session cancels a pick left from an earlier frame")

-- 6. An auto-taxi pick made in the same TAXIMAP_OPENED dispatch, before our handler, survives it.
taxi.live = true
TakeTaxiNode(2)
W.fireEvent("TAXIMAP_OPENED", 1)
X.closeMap(); X.takeoff(); W.tick(52)
W.clearChat(); X.land()
check(W.chatHas("Crossroads -> Ratchet: 0:52"), "an auto-taxi pick is not cancelled by the new session")

-- 7. A pick that can't be resolved cancels an earlier one: the flight can't be matched to it.
X.openMap(); TakeTaxiNode(2); TakeTaxiNode(9); X.closeMap(); X.takeoff(); W.tick(10)
W.clearChat(); X.land()
check(W.chatHas("flight: 0:10 (not recorded: unknown route)"), "an unresolvable pick cancels the earlier pick")

-- 8. A summon and a loading screen mid-flight are not recorded.
X.openMap(); TakeTaxiNode(2); X.closeMap(); X.takeoff(); W.tick(10)
C_SummonInfo.ConfirmSummon()
W.clearChat(); X.land()
check(W.chatHas("(not recorded: flight interrupted)"), "summon mid-flight is not recorded")
X.openMap(); TakeTaxiNode(2); X.closeMap(); X.takeoff(); W.tick(10)
W.fireEvent("LOADING_SCREEN_ENABLED")
taxi.onTaxi = false
W.tick(0.5)
W.fireEvent("PLAYER_ENTERING_WORLD", false, false)
W.clearChat()
W.fireEvent("LOADING_SCREEN_DISABLED")
W.tick(0.5)
check(W.chatHas("(not recorded: flight interrupted)"), "a loading screen mid-flight is not recorded")

-- 9. An untracked flight with a loading screen prints the untracked line (never nil names).
X.takeoff()
W.fireEvent("LOADING_SCREEN_ENABLED")
W.fireEvent("LOADING_SCREEN_DISABLED")
W.tick(5)
W.clearChat(); X.land()
check(W.chatHas("flight: ") and W.chatHas("(not recorded: unknown route)") and not W.chatHas("nil"),
      "untracked flight line has no nil names")

-- 10. An early landing is not recorded.
X.openMap(); TakeTaxiNode(2); X.closeMap(); X.takeoff(); W.tick(10)
TaxiRequestEarlyLanding()
W.clearChat(); X.land()
check(W.chatHas("(not recorded: early landing)"), "early landing is not recorded")

-- 11. The loading failsafes: LOADING_SCREEN_DISABLED never comes.
W.fireEvent("LOADING_SCREEN_ENABLED")
W.fireEvent("PLAYER_ENTERING_WORLD", false, false)
taxi.onTaxi = true
W.tick(9.5)
check(not timer:IsShown(), "no readings while the loading flag is up")
W.tick(1)
check(timer:IsShown(), "the failsafe clears the loading flag 10 s after PLAYER_ENTERING_WORLD")
X.land()
W.fireEvent("LOADING_SCREEN_ENABLED") -- and no PLAYER_ENTERING_WORLD either
taxi.onTaxi = true
W.tick(59.5)
check(not timer:IsShown(), "still loading 59.5 s after LOADING_SCREEN_ENABLED")
W.tick(1)
check(timer:IsShown(), "the failsafe clears the loading flag 60 s after LOADING_SCREEN_ENABLED")
X.land()

-- 12. The final time stays on screen after landing when asked to.
X.profile().freezeSeconds = 3
X.flyTo(2, 52)
name, time = texts()
check(timer:IsShown() and name == "Ratchet" and time == "0:52", "the final time is frozen after landing")
W.tick(3)
check(not timer:IsShown(), "the frozen time goes away after 3 s")
X.profile().freezeSeconds = 0

-- 13. Chat and tooltip toggles, and tooltips only on reachable destinations.
p = X.profile()
p.chat, p.tooltips = false, false
X.openMap()
TaxiNodeOnButtonEnter(X.button(2))
check(not W.linesHave("Flight time"), "tooltips off: no flight time line")
TakeTaxiNode(2); X.closeMap(); X.takeoff(); W.tick(52)
W.clearChat(); X.land()
check(not W.chatHas("Ratchet"), "chat off: no landing line")
p.chat, p.tooltips = true, true
X.openMap()
TaxiNodeOnButtonEnter(X.button(1))
check(not W.linesHave("Flight time"), "no tooltip line on the current node")
TaxiNodeOnButtonEnter(X.button(5))
check(not W.linesHave("Flight time"), "no tooltip line on an unreachable node")
X.closeMap()

-- 14. Flight-map pin tooltips (hooked when Blizzard_FlightMap loaded, or at once if it already was).
X.openMap()
local pin = CreateFrame("Button", nil, nil, "FlightMap_FlightPointPinTemplate")
pin.taxiNodeData = { slotIndex = 2, name = "Ratchet, The Barrens", state = 1, nodeID = 80 }
pin:GetScript("OnEnter")(pin)
check(W.linesHave("Flight time: 0:52"), "flight-map pin tooltip shows the learned time")
X.closeMap()

-- 15. The debug log shows what the in-game checklist needs.
slash("debug")
W.clearChat()
X.openMap()
W.tick(0.1) -- the shown-UI check runs a frame later
check(W.chatHas("flight map opened at") and W.chatHas("system 1 (TaxiFrame expected)"), "debug: map open and its UI")
check(W.chatHas("slot 2: Ratchet, The Barrens [80] REACHABLE, path 25>80"), "debug: slot, key and path")
check(W.chatHas("slot 3: Orgrimmar, Durotar [23] REACHABLE, path 25>77>23"), "debug: a multi-hop path")
check(W.chatHas("1 other nodes (not reachable)"), "debug: other nodes are counted")
check(W.chatHas("slot check: TaxiNodeName and TaxiNodeGetType agree on all 5 slots")
      and not W.chatHas("not in the C_TaxiMap list"), "debug: slot check")
check(W.chatHas("flight map UI shown: TaxiFrame"), "debug: the UI that is really shown")
W.clearChat()
TakeTaxiNode(2)
check(W.chatHas("pick of slot 2 at") and W.chatHas("path 25>80 (open map session; the live read agrees)"),
      "debug: a pick from the open session, and what the live read said")
W.clearChat()
X.closeMap()
check(W.chatHas("flight map closed at"), "debug: map close, with its time")
W.clearChat()
X.takeoff()
check(W.chatHas("PLAYER_CONTROL_LOST at") and W.chatHas("on-taxi reading at"), "debug: takeoff events and readings, with times")
W.tick(52)
W.clearChat(); X.land()
check(W.chatHas("landing position: 0.000 map units from the destination"), "debug: the landing position")
check(W.chatHas("landed at") and W.chatHas("PLAYER_CONTROL_GAINED at"), "debug: landing events, with times")
W.tick(2)
W.clearChat(); W.fireEvent("UNIT_FLAGS", "player")
check(W.chatHas("UNIT_FLAGS player at"), "debug: control events are logged for 10 s after landing")
W.tick(10)
W.clearChat(); W.fireEvent("UNIT_FLAGS", "player")
check(not W.chatHas("UNIT_FLAGS"), "debug: control events are not logged while idle")

-- The click closes the map before our post-hook, and the live read fails: the closed session resolves it.
X.openMap(); taxi.closeOnTake = true
W.clearChat()
TakeTaxiNode(2)
taxi.closeOnTake = false
check(W.chatHas("path 25>80 (map session closed 0.00 s before; the live read failed: GetTaxiMapID returned nothing; no Current node)"),
      "debug: a pick resolved from the just-closed session")
X.takeoff(); W.tick(52); X.land()
-- The same, but the classic functions still answer after the close: the pick keeps the session's
-- node-ID key, so it matches the tooltips.
taxi.classicAfterClose = true
X.openMap(); taxi.closeOnTake = true
W.clearChat()
TakeTaxiNode(2)
taxi.closeOnTake = false
check(W.chatHas("path 25>80 (map session closed 0.00 s before; the live read gave n:Crossroads, The Barrens>n:Ratchet, The Barrens from the classic functions)"),
      "debug: a live read from the classic functions doesn't change the pick's key")
X.takeoff(); W.tick(52)
W.clearChat(); X.land()
check(W.chatHas("Crossroads -> Ratchet: 0:52 (expected 0:52)") and routes()["n:Crossroads, The Barrens>n:Ratchet, The Barrens"] == nil,
      "that flight is recorded under the node-ID key")
taxi.classicAfterClose = false
-- ...and even when the classic functions spell the names differently (unverified in game):
-- names are only compared within one API, so the session still wins.
taxi.classicAfterClose, taxi.classicNames[1], taxi.classicNames[2] = true, "Crossroads", "Ratchet"
X.openMap(); taxi.closeOnTake = true
W.clearChat()
TakeTaxiNode(2)
taxi.closeOnTake = false
check(W.chatHas("path 25>80 (map session closed 0.00 s before; the live read gave n:Crossroads>n:Ratchet from the classic functions)"),
      "a live read from the classic functions with other names doesn't change the pick's key")
W.fireEvent("UI_ERROR_MESSAGE", 1, "ERR_TAXINOTENOUGHMONEY (text)")
taxi.classicAfterClose, taxi.classicNames[1], taxi.classicNames[2] = false, nil, nil
-- The taxi functions are silent inside TakeTaxiNode while the map is open: the open session resolves it.
taxi.muteOnTake = true
X.openMap()
W.clearChat()
TakeTaxiNode(2)
taxi.muteOnTake, taxi.mute = false, false
check(W.chatHas("path 25>80 (open map session; the live read failed: GetTaxiMapID returned nothing; no Current node)"),
      "debug: the open session resolves a pick when the taxi functions are silent in the hook")
W.clearChat()
W.fireEvent("UI_ERROR_MESSAGE", 1, "ERR_TAXINOTENOUGHMONEY (text)")
check(W.chatHas("taxi error at") and W.chatHas("(ERR_TAXINOTENOUGHMONEY)"), "debug: a taxi error matched by its token")
X.closeMap()
-- An auto-taxi pick before our TAXIMAP_OPENED handler: no usable session, so the live read resolves it.
W.tick(1)
taxi.live = true
W.clearChat()
TakeTaxiNode(2)
check(W.chatHas("path 25>80 (live read; no map session)"), "debug: a pick resolved by the live read alone")
W.fireEvent("TAXIMAP_OPENED", 1)
X.closeMap()
W.clearChat()
W.fireEvent("UI_ERROR_MESSAGE", 2, "ERR_TAXIPLAYERMOVING (text)")
check(W.chatHas("taxi error at") and W.chatHas("(matched the message text)"), "debug: a taxi error matched by its text")
-- A session still open from another flight master (its close never came) doesn't resolve a pick here.
X.openMap()
X.NODES[1].state, X.NODES[2].state = 1, 0 -- now at Ratchet
W.clearChat()
TakeTaxiNode(1)
check(W.chatHas("path 80>25") and W.chatHas("(live read; the map session is for another flight master)"),
      "debug: a session for another flight master is not used")
W.fireEvent("TAXIMAP_OPENED", 1)
W.fireEvent("UI_ERROR_MESSAGE", 1, "ERR_TAXINOTENOUGHMONEY (text)")
X.closeMap()
X.NODES[1].state, X.NODES[2].state = 0, 1
-- A stray TakeTaxiNode with no flight map is ignored, and doesn't cancel a pending pick.
W.tick(1)
W.clearChat()
TakeTaxiNode(2)
check(W.chatHas("TakeTaxiNode(2) at") and W.chatHas("with no flight map open: ignored"), "debug: TakeTaxiNode without a flight map")
X.openMap(); TakeTaxiNode(2); X.closeMap()
W.tick(1)
TakeTaxiNode(3)
check(state() == "pending", "a stray TakeTaxiNode without a flight map leaves the pick alone")
X.takeoff(); W.tick(52)
W.clearChat(); X.land()
check(W.chatHas("Crossroads -> Ratchet: 0:52"), "...and the flight is tracked")
-- A fallback key when the hops can't be read.
taxi.badRoutes[3] = true
W.clearChat(); X.openMap()
check(W.chatHas("slot 3: Orgrimmar, Durotar [23] REACHABLE, path 25>23 (fallback key: hops unreadable)"),
      "debug: a fallback key is flagged")
TakeTaxiNode(3); X.closeMap(); X.takeoff(); W.tick(20); X.land()
taxi.badRoutes[3] = nil
W.clearChat(); slash("routes")
check(W.chatHas("Crossroads -> Orgrimmar (hops unknown): 0:20, 1 flight, path 25>23"),
      "routes: a fallback key has unknown hops (and debug mode shows the path)")
-- A slot the C_TaxiMap list leaves out.
taxi.hideSlotInMap = 4
W.clearChat(); X.openMap()
check(W.chatHas("slot check: slots 4 of NumTaxiNodes' 5 are not in the C_TaxiMap list"), "debug: slots missing from C_TaxiMap")
check(W.chatHas("path 25>23 (fallback key: hop 1 goes through slot 4, which is not in the list)"), "debug: a hop through a missing slot")
W.clearChat()
TakeTaxiNode(4)
check(W.chatHas("could not be resolved (slot 4 is not in the list from C_TaxiMap; the map session lacks it)"),
      "debug: why a pick of a missing slot can't be resolved")
X.closeMap()
taxi.hideSlotInMap = nil
-- Slots whose classic name differs, and secret node fields.
taxi.classicNames[3] = "Orgrimmar"
W.clearChat(); X.openMap()
check(W.chatHas("slot 3 differs: C_TaxiMap Orgrimmar, Durotar (REACHABLE), TaxiNodeName Orgrimmar, TaxiNodeGetType REACHABLE")
      and W.chatHas("slot check: 1 of 5 slots differ"), "debug: the slot check lists differing slots")
X.closeMap()
taxi.classicNames[3] = nil
taxi.secretNodeName = 5
W.clearChat(); X.openMap()
check(W.chatHas("note: 1 C_TaxiMap nodes had secret fields"), "debug: secret C_TaxiMap fields are noted")
X.closeMap()
taxi.noCurrentInMap = true -- the classic functions take over
W.clearChat(); X.openMap()
check(W.chatHas("note: the C_TaxiMap list has no Current node") and W.chatHas("nodes from the classic functions")
      and W.chatHas("note: 1 classic taxi nodes had secret values"),
      "debug: the classic functions stand in for a C_TaxiMap list without a Current node; secret values are noted")
TakeTaxiNode(2)
check(W.chatHas("path n:Crossroads, The Barrens>n:Ratchet, The Barrens (open map session; the live read agrees)"),
      "the classic fallback resolves picks")
X.closeMap(); X.takeoff(); W.tick(52)
W.clearChat(); X.land()
check(W.chatHas("landing position: unavailable (the flight map gave no destination position)"),
      "debug: the classic functions give no positions, so the landing can't be measured")
taxi.noCurrentInMap, taxi.secretNodeName = false, nil
-- The modern flight map.
W.clearChat(); X.openMap(2); W.tick(0.1)
check(W.chatHas("system 2 (FlightMapFrame expected)") and W.chatHas("flight map UI shown: FlightMapFrame"), "debug: the modern flight map")
X.closeMap()
-- Loading events and the failsafe.
W.clearChat()
W.fireEvent("LOADING_SCREEN_ENABLED"); W.fireEvent("PLAYER_ENTERING_WORLD", false, false); W.fireEvent("LOADING_SCREEN_DISABLED")
check(W.chatHas("loading screen started at") and W.chatHas("PLAYER_ENTERING_WORLD at")
      and W.chatHas("(initial login false, reload false)") and W.chatHas("loading screen ended at"), "debug: loading events, with times")
W.fireEvent("LOADING_SCREEN_ENABLED"); W.fireEvent("PLAYER_ENTERING_WORLD", false, false)
W.clearChat(); W.tick(10.5)
check(W.chatHas("loading flag cleared by the failsafe at"), "debug: the failsafe")
-- Ignored picks, early landings and summons.
X.openMap()
W.clearChat()
TakeTaxiNode(5)
check(W.chatHas("pick of slot 5 at") and W.chatHas("ignored: the node is OTHER (open map session; the live read agrees)"),
      "debug: a pick of an unreachable node is ignored")
TakeTaxiNode(2); X.closeMap(); X.takeoff(); W.tick(5)
W.clearChat()
TaxiRequestEarlyLanding(); C_SummonInfo.ConfirmSummon()
check(W.chatHas("early landing requested at") and W.chatHas("summon accepted at"), "debug: early landing and summons, with times")
X.land()
-- The 0.5 s grace: a session closed 0.4 s ago resolves a pick; one closed 0.6 s ago doesn't.
X.openMap(); X.closeMap(); W.tick(0.4)
W.clearChat(); TakeTaxiNode(2)
check(W.chatHas("path 25>80 (map session closed 0.40 s before; the live read failed:"), "a session closed 0.4 s ago resolves a pick")
W.fireEvent("UI_ERROR_MESSAGE", 1, "ERR_TAXINOTENOUGHMONEY (text)")
X.openMap(); X.closeMap(); W.tick(0.6)
W.clearChat(); TakeTaxiNode(2)
check(W.chatHas("with no flight map open: ignored"), "a session closed 0.6 s ago doesn't")
-- An auto-taxi pick with the map open but no session yet, of a slot the list lacks: unresolved, so
-- the earlier pick goes.
X.openMap(); TakeTaxiNode(2); X.closeMap(); W.tick(1)
taxi.live = true
W.clearChat(); TakeTaxiNode(9)
check(W.chatHas("could not be resolved (slot 9 is not in the list from C_TaxiMap)") and W.chatHas("the earlier pick is cancelled"),
      "an unresolvable pick with the map open cancels the earlier pick")
check(state() == "idle", "...so the tracker is idle")
W.fireEvent("TAXIMAP_OPENED", 1); X.closeMap()
-- A session that lacks the slot, and one that is out of date, don't resolve the pick.
taxi.hideSlotInMap = 4
X.openMap()
taxi.hideSlotInMap = nil
W.clearChat(); TakeTaxiNode(4)
check(W.chatHas("path 25>77 (live read; the map session lacks this slot)"), "debug: a slot the session lacks comes from the live read")
W.fireEvent("UI_ERROR_MESSAGE", 1, "ERR_TAXINOTENOUGHMONEY (text)")
X.closeMap()
X.openMap()
X.NODES[2], X.NODES[3] = X.NODES[3], X.NODES[2] -- the list changed under an open session
W.clearChat(); TakeTaxiNode(2)
check(W.chatHas("Orgrimmar, Durotar, path 25>23 (live read; the map session is out of date: slot 2 is Ratchet, The Barrens there)"),
      "debug: an out-of-date session is not used")
W.fireEvent("UI_ERROR_MESSAGE", 1, "ERR_TAXINOTENOUGHMONEY (text)")
X.closeMap()
X.NODES[2], X.NODES[3] = X.NODES[3], X.NODES[2]
-- The live read has the node in another state than the session: the session still resolves it.
X.openMap()
X.NODES[2].state = 2
W.clearChat(); TakeTaxiNode(2)
check(W.chatHas("path 25>80 (open map session; the live read has the node as OTHER)"), "debug: the live read's other node state is reported")
W.fireEvent("UI_ERROR_MESSAGE", 1, "ERR_TAXINOTENOUGHMONEY (text)")
X.closeMap()
X.NODES[2].state = 1
-- A pick of another route during a flight doesn't count as that flight's destination for the landing.
X.openMap(); TakeTaxiNode(2); X.closeMap(); X.takeoff(); W.tick(10)
X.openMap(); TakeTaxiNode(3); X.closeMap()
W.tick(42)
W.clearChat(); X.land()
check(W.chatHas("landing position: unavailable (no pick of this route this session)"), "debug: the landing is only measured against its own pick")
-- A pick left from an earlier frame is cancelled by the next map session.
X.openMap(); TakeTaxiNode(2); X.closeMap(); W.tick(1)
W.clearChat(); X.openMap()
check(W.chatHas("an earlier pick was cancelled by this map session"), "debug: a stale pick cancelled by a new session")
X.closeMap()
-- An unreadable hop, and NumTaxiNodes unreadable.
taxi.badHops[3] = true
W.clearChat(); X.openMap()
check(W.chatHas("path 25>23 (fallback key: hop 1 unreadable)"), "debug: an unreadable hop")
X.closeMap()
taxi.badHops[3] = nil
taxi.numNodesFails = true
W.clearChat(); X.openMap()
check(W.chatHas("NumTaxiNodes is unreadable, so missing slots can't be listed"), "debug: NumTaxiNodes unreadable")
X.closeMap()
taxi.numNodesFails = false
-- Unknown readings.
taxi.secretOnTaxi = true
W.clearChat(); W.tick(0.2)
check(W.chatHas("is unknown: secret value"), "debug: a secret reading is reported")
W.clearChat(); slash("status")
check(W.chatHas("last reading: unknown (secret value)"), "status says why the reading is unknown")
taxi.secretOnTaxi = false
W.tick(0.2)
W.clearChat(); X.openMap(); X.closeMap(); slash("status")
check(W.chatHas("last flight map: closed, TaxiFrame (system 1), map 1463, 5 nodes from C_TaxiMap"), "status names the map UI and node source")
slash("debug")

-- 16. Slash commands.
for _, cmd in ipairs({ "status", "routes", "forget", "debug", "status", "debug", "unlock", "lock", "resetpos", "help" }) do
    local ok, err = pcall(slash, cmd)
    check(ok, "/ftimer " .. cmd .. ": " .. tostring(err))
end
W.clearChat()
local ok, err = pcall(slash, "")
check(ok, "/ftimer: " .. tostring(err))
if W.BREAK_SETTINGS then
    check(W.chatHas("options panel is unavailable"), "/ftimer explains that the panel is unavailable")
else
    check(W.openedCategory ~= nil and W.openedCategory == ns.Options.categoryID, "/ftimer opens the settings category")
end

-- 17. The preview's arrival clock follows the clock settings; then the whole options panel.
ns.Display:SetPreview(true)
check(timer:IsShown(), "preview shows the timer")
expect("preview sample", timeText(), "^0:32 %(3:%d%d AM%)$")
ns.Display:SetPreview(false)
if not W.BREAK_SETTINGS then
    W.exercisePanel({
        app = "ForeverFlightTimer", profilesApp = "ForeverFlightTimer_Profiles",
        options = ns.Options, display = ns.Display, timer = timer,
        tabs = { "appearance", "behaviour", "display" },
        expectUsed = { "CheckBox", "Slider", "Dropdown", "Button", "ColorPicker", "EditBox",
                       "LSM30_Font", "LSM30_Background", "LSM30_Border", "LSM30_Statusbar" },
        expectCreated = { "TabGroup", "InlineGroup", "CheckBox", "Slider", "Dropdown", "ColorPicker", "Button",
                          "Label", "EditBox", "LSM30_Font", "LSM30_Background", "LSM30_Border", "LSM30_Statusbar" },
    })
    check(W.statusLine:find("^Not flying %- %d+ routes learned") ~= nil, "status line: " .. tostring(W.statusLine))
    X.aceDB():SetProfile("Default") -- the panel walk made and switched to a new profile
end
X.aceDB():ResetProfile()

-- 17b. Reset defaults. Steps 1-4 test the slash route; step 5 repeats
-- them for the button and the game's Defaults.
do
    local ACD = LibStub("AceConfigDialog-3.0")
    local HINT = "type /ftimer defaults confirm to reset all settings in the current profile to their defaults (learned flight times are kept)."
    local DESC = "Puts every setting on every tab back to its default, including the position. Learned flight times are kept. Same as /ftimer defaults confirm."
    local CONFIRM = "Reset all Forever Flight Timer settings in the current profile to their defaults? Learned flight times are kept. This cannot be undone."
    local HELP = "/ftimer (options), lock, unlock, resetpos, defaults, status, routes, forget, debug, help"
    local PASS_ALL = { "LeftButton", "MiddleButton" }
    for n = 4, 31 do PASS_ALL[#PASS_ALL + 1] = "Button" .. n end
    PASS_ALL = table.concat(PASS_ALL, ",")
    local function diff(value, default, path, out)
        if type(default) == "table" then
            if type(value) ~= "table" then out[#out + 1] = path; return end
            for k, v in pairs(default) do diff(value[k], v, path .. "." .. tostring(k), out) end
            for k in pairs(value) do
                if default[k] == nil then out[#out + 1] = path .. "." .. tostring(k) .. " (extra)" end
            end
        elseif value ~= default then
            out[#out + 1] = path
        end
    end
    -- Changes on every tab, applied the way the panel applies them.
    local function changeSettings()
        local p = X.profile()
        p.pos.x, p.pos.y, p.scale, p.alpha, p.strata = 150, -300, 2, 0.5, "HIGH"
        p.colors.countdown.r, p.colors.countdown.g = 1, 0
        p.font.size, p.showOrigin, p.chat, p.rightClickMenu = 20, true, false, false
        ns.Display:ApplySettings()
        slash("unlock")
        check(timer:GetScale() == 2 and rawget(timer, "_motion") == true, "reset: the changes reached the frame")
    end
    -- Checked right after a reset, before any tick.
    local function checkReset(route)
        local out = {}
        diff(X.profile(), ns.DEFAULTS.profile, "profile", out)
        check(#out == 0, route .. ": every setting is back to its default: " .. table.concat(out, ", "))
        check(timer:GetScale() == 1 and rawget(timer, "_motion") == false and rawget(timer, "_click") == true
              and rawget(timer, "_pass") == PASS_ALL, route .. ": the frame was re-applied (scale 1, locked, the menu back on)")
        check(W.chatHas('all settings in the profile "Default" reset to their defaults'
                        .. (route == "game" and " by the game's Defaults button" or "") .. " (learned flight times are kept)."),
              route .. ": the chat line")
        if not W.BREAK_SETTINGS then
            local requested = ACD.frame.apps.ForeverFlightTimer == true
            check(requested == (route ~= "button"),
                  route .. (route == "button" and ": no panel refresh (the popup re-opens the page)" or ": a panel refresh"))
        end
        check(routes()["25>80"] ~= nil and ForeverFlightTimerDB.global.debug == true
              and ForeverFlightTimerDB.profiles.Other.width == 333, route .. ": routes, debug and the other profile are kept")
    end

    -- 1. A flight in progress on a learned route; debug on, once.
    X.flyTo(2, 52)
    X.openMap(); TakeTaxiNode(2); X.closeMap()
    local takeoffAt = W.now
    X.takeoff()
    slash("debug")
    -- 2. Settings changed on every tab, and in a second profile.
    changeSettings()
    X.aceDB():SetProfile("Other")
    X.profile().width = 333
    X.aceDB():SetProfile("Default")
    -- 3. Without "confirm", nothing changes.
    W.clearChat(); slash("defaults")
    check(W.chatHas(HINT), "/ftimer defaults prints the hint")
    W.clearChat(); slash("defaults confirm now")
    check(W.chatHas(HINT) and X.profile().scale == 2, "/ftimer defaults confirm now only explains")
    -- 4. The slash route.
    W.tick(0.1); W.clearChat()
    slash("  Defaults  CONFIRM ") -- the rest of the line is trimmed and lowercased
    checkReset("slash")
    W.tick(1)
    check(timer:IsShown() and state() == "flying", "slash: the flight keeps going")
    -- 5. The button, the game's Defaults, and the Profiles page (which must not listen).
    if not W.BREAK_SETTINGS then
        changeSettings(); W.tick(0.1); W.clearChat()
        local opt = LibStub("AceConfigRegistry-3.0"):GetOptionsTable("ForeverFlightTimer", "dialog", "AceConfigDialog-3.0")
            .args.display.args.resetDefaults
        check(opt and opt.type == "execute" and opt.order == 3.5 and opt.name == "Reset defaults" and opt.desc == DESC
              and opt.confirm == true and opt.confirmText == CONFIRM, "the Display tab's Reset defaults button")
        opt.func()
        checkReset("button")
        changeSettings(); W.tick(0.1); W.clearChat()
        ns.Options.frame:OnDefault()
        checkReset("game")
        X.profile().scale = 2
        W.clearChat()
        ns.Options.profilesFrame:OnDefault()
        check(X.profile().scale == 2 and not W.chatHas("reset to their defaults"), "the Profiles page's OnDefault doesn't reset")
        X.aceDB():ResetProfile()
    end
    -- The chat line names the active profile, and only that profile is reset.
    X.aceDB():SetProfile("Other")
    W.clearChat(); slash("defaults confirm")
    check(W.chatHas('all settings in the profile "Other" reset to their defaults') and X.profile().width == 240,
          "a reset names and resets the active profile")
    X.aceDB():SetProfile("Default")
    -- 7. The help line.
    W.clearChat(); slash("help")
    check(W.chatHas(HELP), "/ftimer help lists defaults")
    slash("debug")
    -- The flight is still recorded normally after the resets.
    W.tick(52.2 - (W.now - takeoffAt))
    W.clearChat(); X.land()
    check(W.chatHas("Crossroads -> Ratchet: 0:52 (expected 0:52)"), "the flight in progress is still recorded after a reset")
end

-- 17c. Right-click menu. On a flight, so the bar is on screen.
do
    local ALL = { "LeftButton", "MiddleButton" }
    for n = 4, 31 do ALL[#ALL + 1] = "Button" .. n end
    ALL = table.concat(ALL, ",")
    local function mouse() return rawget(timer, "_click"), rawget(timer, "_motion"), rawget(timer, "_pass") end
    local function lockedState(label)
        local c, m, p = mouse()
        check(c == true and m == false and p == ALL, label .. ": locked with the menu (clicks on, hover off, all but the right button pass)")
    end
    local function entries()
        local out = {}
        for _, e in ipairs(W.lastMenu and W.lastMenu.entries or {}) do out[#out + 1] = e.kind .. ":" .. tostring(e.text) end
        return table.concat(out, "|")
    end
    local function entry(text)
        for _, e in ipairs(W.lastMenu.entries) do if e.text == text then return e end end
    end
    local function count(s)
        local n = 0
        for _, line in ipairs(W.chat) do if line:find(s, 1, true) then n = n + 1 end end
        return n
    end
    local function menuStatus()
        W.clearChat(); slash("status")
        for _, line in ipairs(W.chat) do
            local s = line:match("(right%-click menu: .*)$")
            if s then return s end
        end
    end
    local UNSUPPORTED = "pass-through buttons are not supported on this client: the locked timer stays click-through, the menu works when unlocked"
    local SHORT = "pass-through fell back to buttons 1-5"
    local SHORT_LIST = "LeftButton,MiddleButton,Button4,Button5"
    X.openMap(); TakeTaxiNode(2); X.closeMap(); X.takeoff()
    -- The setting.
    if not W.BREAK_SETTINGS then
        local opt = LibStub("AceConfigRegistry-3.0"):GetOptionsTable("ForeverFlightTimer", "dialog", "AceConfigDialog-3.0")
            .args.display.args.rightClickMenu
        check(opt and opt.type == "toggle" and opt.order == 2.5 and opt.name == "Right-click menu"
              and opt.desc == "Right-click the timer for a menu: Options, Lock position and Reset position. Other clicks still go through to the game world. Turn this off to make the locked timer completely click-through.",
              "the Display tab's Right-click menu setting")
    end
    -- 1. Locked, default; the status line says so.
    lockedState("default")
    check(menuStatus() == "right-click menu: on; pass-through: all but the right button", "status: locked with the menu")
    -- 2. Right-click opens the menu; other buttons don't; unlocked too.
    check(W.rightClick(timer) and W.lastMenu.owner == timer, "right-click opens a menu owned by the timer")
    check(entries() == "title:Forever Flight Timer|button:Options|checkbox:Lock position|button:Reset position",
          "menu entries: " .. entries())
    check(entry("Lock position").isSelected() == true, "Lock position is ticked while locked")
    W.lastMenu = nil
    timer:GetScript("OnMouseUp")(timer, "LeftButton")
    timer:GetScript("OnMouseUp")(timer, "MiddleButton")
    check(W.lastMenu == nil, "left and middle clicks open nothing")
    slash("unlock")
    check(W.rightClick(timer), "an unlocked timer's right-click opens the menu too")
    slash("lock")
    -- 3. Each entry.
    W.rightClick(timer)
    if not W.BREAK_SETTINGS then
        W.openedCategory = nil
        entry("Options").callback()
        check(W.openedCategory ~= nil and W.openedCategory == ns.Options.categoryID, "Options opens the settings")
        W.combat = true; W.clearChat()
        entry("Options").callback()
        check(W.chatHas("options can't be opened during combat."), "Options is refused in combat")
        W.combat = false
    else
        W.clearChat(); entry("Options").callback()
        check(W.chatHas("options panel is unavailable"), "Options explains a broken panel")
    end
    W.clearChat()
    entry("Lock position").onSelect()
    local c, m, p = mouse()
    check(X.profile().locked == false and m == true and p == "" and W.chatHas("unlocked:"), "Lock position unlocks")
    check(entry("Lock position").isSelected() == false, "Lock position is unticked while unlocked")
    entry("Lock position").onSelect()
    lockedState("Lock position locks again")
    X.profile().pos.x = 77; ns.Display:ApplyPosition()
    W.clearChat(); entry("Reset position").callback()
    check(X.profile().pos.x == ns.DEFAULTS.profile.pos.x and W.chatHas("position reset."), "Reset position")
    -- 4. The setting off; 8. the tooltip both ways.
    X.profile().rightClickMenu = false; ns.Display:ApplySettings()
    c, m, p = mouse()
    check(c == false and m == false and p == "", "setting off: the locked timer is fully click-through")
    check(menuStatus() == "right-click menu: off", "status: the setting off")
    check(not W.rightClick(timer), "setting off: right-click opens nothing")
    slash("unlock")
    check(rawget(timer, "_motion") == true and not W.rightClick(timer), "setting off, unlocked: right-click opens nothing")
    timer:GetScript("OnEnter")(timer)
    check(W.linesHave("Drag to move. Type /ftimer lock to lock it."), "tooltip without the menu")
    X.profile().rightClickMenu = true; ns.Display:ApplySettings()
    timer:GetScript("OnEnter")(timer)
    check(W.linesHave("Drag to move. Right-click for the menu. Type /ftimer lock to lock it."), "tooltip with the menu")
    slash("lock")
    lockedState("setting back on")
    -- 5. Combat: pass-through changes wait for PLAYER_REGEN_ENABLED.
    W.combat = true
    slash("unlock")
    c, m, p = mouse()
    check(m == true and p == ALL, "unlock in combat: the mouse is taken, the pass-through waits")
    check(menuStatus() == "right-click menu: on; pass-through: all but the right button, waiting for combat or a restriction to end",
          "status: the clear waits for combat to end")
    W.combat = false; W.fireEvent("PLAYER_REGEN_ENABLED")
    check(rawget(timer, "_pass") == "", "after combat: the pass-through is cleared")
    check(menuStatus() == "right-click menu: on; pass-through: none (unlocked)", "status: unlocked")
    W.combat = true
    slash("lock")
    check(rawget(timer, "_click") == false, "lock in combat: fully click-through until combat ends")
    check(menuStatus() == "right-click menu: on; pass-through: none, waiting for combat or a restriction to end",
          "status: the set waits for combat to end")
    W.combat = false; W.fireEvent("PLAYER_REGEN_ENABLED")
    lockedState("after combat")
    -- 6. A restriction: changes wait, and the catch-up runs a frame after the event. Each type the
    -- addons wait for (0-4) on its own; the stub fails any pass-through call made under one.
    for t = 0, 4 do
        local label = "restriction type " .. t
        X.profile().rightClickMenu = false; ns.Display:ApplySettings()
        check(rawget(timer, "_pass") == "", label .. ": the test starts without the pass-through")
        W.restrictedTypes[t] = true
        X.profile().rightClickMenu = true; ns.Display:ApplySettings()
        check(rawget(timer, "_click") == false and rawget(timer, "_pass") == "", label .. ": fully click-through, no call")
        W.fireRestriction(5, 2) -- Chat becoming active: another type
        check(rawget(timer, "_pass") == "", label .. ": no call inside the event's dispatch")
        W.tick(0.1)
        check(rawget(timer, "_pass") == "", label .. ": still pending while the restriction lasts")
        W.restrictedTypes[t] = nil
        W.fireRestriction(t, 0)
        check(rawget(timer, "_pass") == "", label .. ": nothing changes during the dispatch")
        W.tick(0.1)
        lockedState(label .. ": a frame after it ended")
    end
    -- A Chat restriction doesn't hold the change back.
    X.profile().rightClickMenu = false; ns.Display:ApplySettings()
    W.restrictedTypes[5] = true
    X.profile().rightClickMenu = true; ns.Display:ApplySettings()
    lockedState("under a Chat restriction")
    W.restrictedTypes[5] = nil
    -- One catch-up per frame, however many events fire in it.
    local after, scheduled = C_Timer.After, 0
    local function counting(delay, fn) scheduled = scheduled + 1; return after(delay, fn) end
    C_Timer.After = counting
    W.fireRestriction(1, 2); W.fireRestriction(2, 2); W.fireRestriction(1, 0)
    C_Timer.After = after
    check(scheduled == 1, "three events in one frame schedule one catch-up")
    W.tick(0.1)
    C_Timer.After = counting
    W.fireRestriction(1, 2)
    C_Timer.After = after
    check(scheduled == 2, "an event in a later frame schedules another")
    W.tick(0.1)
    lockedState("after the catch-ups")
    -- The menu turned off while its clear waits: the status line still shows the wait.
    W.restrictedTypes[1] = true
    X.profile().rightClickMenu = false; ns.Display:ApplySettings()
    check(menuStatus() == "right-click menu: off; pass-through: all but the right button, waiting for combat or a restriction to end",
          "status: the menu off, its clear waiting")
    W.restrictedTypes[1] = nil
    W.fireRestriction(1, 0); W.tick(0.1)
    check(rawget(timer, "_pass") == "" and menuStatus() == "right-click menu: off", "the clear catches up; status: off")
    X.profile().rightClickMenu = true; ns.Display:ApplySettings()
    lockedState("the menu back on")
    -- 6b. MenuUtil missing: no menu anywhere, and the locked timer is fully click-through.
    local menuUtil = MenuUtil
    rawset(_G, "MenuUtil", nil)
    ns.Display:ApplyMouse()
    c, m, p = mouse()
    check(c == false and m == false and p == "" and not W.rightClick(timer), "no MenuUtil: fully click-through, no menu")
    check(menuStatus() == "right-click menu: unavailable on this client", "status: no MenuUtil")
    slash("unlock")
    check(rawget(timer, "_motion") == true and not W.rightClick(timer), "no MenuUtil, unlocked: right-click opens nothing")
    timer:GetScript("OnEnter")(timer)
    check(W.linesHave("Drag to move. Type /ftimer lock to lock it."), "no MenuUtil: the tooltip without the menu")
    slash("lock")
    rawset(_G, "MenuUtil", menuUtil)
    ns.Display:ApplyMouse()
    lockedState("MenuUtil back")
    -- 7. Pass-through unsupported. Debug is off at first: the note waits until debug is on.
    rawset(timer, "SetPassThroughButtons", false)
    W.clearChat()
    slash("unlock"); slash("lock")
    W.fireRestriction(1, 0); W.tick(0.1)
    check(rawget(timer, "_click") == false and not W.rightClick(timer), "unsupported: the locked timer stays click-through, no menu")
    check(count(UNSUPPORTED) == 0, "unsupported: no note while debug is off")
    check(menuStatus() == "right-click menu: on; pass-through: unsupported, so the menu works only when unlocked",
          "status: unsupported")
    slash("debug")
    slash("unlock")
    check(W.rightClick(timer), "unsupported: the unlocked timer's menu still works")
    slash("lock")
    check(count(UNSUPPORTED) == 1, "unsupported: noted once, after debug is turned on")
    rawset(timer, "SetPassThroughButtons", nil)
    ns.Display:ApplyMouse()
    lockedState("pass-through supported again")
    -- 7b. The short-list fallback (last: the short list stays for the session). Debug off at first.
    slash("debug")
    W.rejectLongButtons = true
    W.clearChat()
    slash("unlock"); slash("lock")
    check(rawget(timer, "_pass") == SHORT_LIST, "the short-list fallback")
    check(count(SHORT) == 0, "short list: no note while debug is off")
    check(menuStatus() == "right-click menu: on; pass-through: buttons 1-5 but the right one", "status: the short list")
    slash("debug")
    slash("unlock"); slash("lock")
    check(rawget(timer, "_pass") == SHORT_LIST and count(SHORT) == 1, "later sets use the short list; noted once debug is on")
    slash("unlock"); slash("lock")
    check(count(SHORT) == 1, "the note isn't repeated")
    W.rejectLongButtons = false
    slash("unlock"); slash("lock")
    check(rawget(timer, "_pass") == SHORT_LIST, "the short list stays for the session")
    slash("debug")
    W.tick(52); X.land()
end

-- 18. Forget all (after learning a route: the panel walk already pressed its Forget button).
X.flyTo(2, 52)
check(next(routes()) ~= nil, "a route is learned again")
slash("forget all")
check(next(routes()) == nil, "forget all clears the learned routes")

-- 19. Logout mid-flight saves the flight. PLAYER_LOGOUT ends a UI session (AceDB strips the profile
-- defaults on it), so the next sessions run in fresh processes with the saved variables.
X.flyTo(2, 52) -- known again, so the resumed flights count down
X.openMap(); TakeTaxiNode(2); X.closeMap(); X.takeoff(); W.tick(20)
W.fireEvent("PLAYER_LOGOUT")
local saved = ForeverFlightTimerCharDB.flight
check(type(saved) == "table" and saved.route and saved.route.key == "25>80", "logout mid-flight saves the flight")
-- The session file goes to the temp folder, so an interrupted run leaves nothing in the addon.
local file = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. "/fft_smoke_session_" .. MODE .. ".lua"
X.saveSession(file)
for _, kind in ipairs({ "reload", "relog", "pick", "autotaxi" }) do
    local cmd = ('"%s" tests/smoke_resume.lua %s "%s"'):format(arg[-1] or "luajit", kind, file)
    if package.config:sub(1, 1) == "\\" then cmd = '"' .. cmd .. '"' end -- cmd.exe drops one outer pair of quotes
    local r1, _, r3 = os.execute(cmd)
    check(r1 == 0 or (r1 == true and (r3 == nil or r3 == 0)), "next session (" .. kind .. ") passed")
end
os.remove(file)
W.report("smoke")
