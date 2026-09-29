-- Glue: flight-map sessions, hooks, readings, loading state, tooltips, chat, slash commands.
local ADDON_NAME, ns = ...

local LSM = LibStub("LibSharedMedia-3.0")
local TimeFormat, ArrivalClock = ns.TimeFormat, ns.ArrivalClock

local PREFIX = "|cff33ff99Forever Flight Timer|r: "
local TICK = 0.1
local SESSION_GRACE = 0.5 -- a session closed this recently may still resolve a pick
local PEW_FAILSAFE, LSE_FAILSAFE = 10, 60
local DEBUG_AFTER_LANDING = 10 -- s after a landing that control events are still logged
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "TAXIMAP_OPENED",
    "TAXIMAP_CLOSED", "UI_ERROR_MESSAGE", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_LOGOUT",
    "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED",
}
local TAXI_ERRORS = {
    "ERR_TAXIINCOMBAT", "ERR_TAXINOPATH", "ERR_TAXINOPATHS", "ERR_TAXINOSUCHPATH", "ERR_TAXINOTELIGIBLE",
    "ERR_TAXINOTENOUGHMONEY", "ERR_TAXINOTSTANDING", "ERR_TAXINOTVISITED", "ERR_TAXINOVENDORNEARBY",
    "ERR_TAXIPLAYERALREADYMOUNTED", "ERR_TAXIPLAYERBUSY", "ERR_TAXIPLAYERMOVING", "ERR_TAXIPLAYERSHAPESHIFTED",
    "ERR_TAXISAMENODE", "ERR_TAXITOOFARAWAY", "ERR_TAXIUNSPECIFIEDSERVERERROR",
}
local REASON_TEXT = {
    learned = " (new route learned)",
    early = " (not recorded: early landing)",
    interrupted = " (not recorded: flight interrupted)",
    short = " (not recorded: under 5 s)",
    relog = " (not recorded: relogged during the flight)",
    ambiguous = " (not recorded: two destinations picked)",
}

local issecret = issecretvalue or function() return false end

local core = CreateFrame("Frame")
local db, charDB, store, tracker, realmClock
local optionsReady = false
local loading, pewAt, lseAt, loadDone = true, nil, nil, false -- addons load during a loading screen
local seq, lastCloseSeq = 0, 0
local lastCloseEventAt -- GetTime() of the last TAXIMAP_CLOSED, including ones no session of ours saw
local session -- { open, list, system, openedAt, closedAt }
local frozen  -- { view, untilTime } after a landing
local pickGeo -- { key, mapID, x, y } of the picked destination, for the debug distance check
local lastReading, readingProblem, falseSince, lastLandAt
local flightMapHooked = false
local taxiErrorText = {}
local Handlers = {}

local function Print(msg) print(PREFIX .. msg) end

local function Debugging() return db and db.global.debug end

local function Debug(msg)
    if Debugging() then print("|cff33ff99FFT debug|r: " .. msg) end
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function FormatTime(seconds)
    local p = db.profile
    return TimeFormat.Format(seconds, p.timeStyle, p.showTenths)
end

local function ShortName(name) return ns.Display.ShortName(name, db.profile.fullNames) end

local function FlightPathState(name, fallback)
    local e = Enum and Enum.FlightPathState
    return (e and e[name]) or fallback
end

-- TAXIMAP_OPENED's system picks the UI (Blizzard_Game EventImplementation): Taxi -> TaxiFrame.
local function MapUIName(system)
    local taxi = Enum and Enum.UIMapSystem and Enum.UIMapSystem.Taxi or 1
    return system == taxi and "TaxiFrame" or "FlightMapFrame"
end

local function Note(list, msg) list.notes[#list.notes + 1] = msg end

-- C_TaxiMap nodes: node-ID keys and map positions.
local function ReadMapNodes(list)
    local okMap, mapID = Call(GetTaxiMapID)
    if not okMap then return Note(list, "GetTaxiMapID is missing or failed") end
    if issecret(mapID) then return Note(list, "GetTaxiMapID returned a secret value") end
    if not mapID then return Note(list, "GetTaxiMapID returned nothing") end
    list.mapID = mapID
    local ok, nodes = Call(C_TaxiMap and C_TaxiMap.GetAllTaxiNodes, mapID)
    if not ok or type(nodes) ~= "table" or issecret(nodes) then
        return Note(list, "C_TaxiMap.GetAllTaxiNodes is missing or failed")
    end
    local current, reachable = FlightPathState("Current", 0), FlightPathState("Reachable", 1)
    local secret = 0
    for _, n in ipairs(nodes) do
        if type(n) == "table" then
            if issecret(n.slotIndex) or issecret(n.name) or issecret(n.nodeID) or issecret(n.state) then
                secret = secret + 1
            elseif type(n.slotIndex) == "number" and type(n.name) == "string" then
                local key = (type(n.nodeID) == "number" and n.nodeID > 0) and tostring(n.nodeID) or ("n:" .. n.name)
                local state = (n.state == current and "CURRENT") or (n.state == reachable and "REACHABLE") or "OTHER"
                local x, y
                if type(n.position) == "table" and n.position.GetXY then
                    local okXY, px, py = pcall(n.position.GetXY, n.position)
                    if okXY and type(px) == "number" and type(py) == "number" and not issecret(px) and not issecret(py) then
                        x, y = px, py
                    end
                end
                list.nodes[n.slotIndex] = { key = key, name = n.name, state = state, x = x, y = y }
                if state == "CURRENT" then list.origin = n.slotIndex end
            end
        end
    end
    if secret > 0 then Note(list, ("%d C_TaxiMap nodes had secret fields"):format(secret)) end
end

-- The classic taxi functions, with name keys.
local function ReadClassicNodes(list)
    local okN, count = Call(NumTaxiNodes)
    if not okN or issecret(count) or type(count) ~= "number" then
        return Note(list, "NumTaxiNodes is missing, failed or secret")
    end
    local secret = 0
    for slot = 1, count do
        local okName, name = Call(TaxiNodeName, slot)
        local okType, kind = Call(TaxiNodeGetType, slot)
        if (okName and issecret(name)) or (okType and issecret(kind)) then
            secret = secret + 1
        elseif okName and type(name) == "string" then
            local state = (okType and kind == "CURRENT" and "CURRENT")
                or (okType and kind == "REACHABLE" and "REACHABLE") or "OTHER"
            list.nodes[slot] = { key = "n:" .. name, name = name, state = state }
            if state == "CURRENT" then list.origin = slot end
        end
    end
    if secret > 0 then Note(list, ("%d classic taxi nodes had secret values"):format(secret)) end
end

-- The flight map's nodes: slot -> {key, name, state, x, y}, the origin slot, and a path key plus
-- hop count for every reachable slot. C_TaxiMap first; the classic functions when
-- that list is unusable or has no Current node. list.notes says what failed, for debug mode.
local function BuildNodeList()
    local list = { nodes = {}, paths = {}, hops = {}, fallback = {}, notes = {} }
    ReadMapNodes(list)
    if list.origin then
        list.source = "C_TaxiMap"
    else
        if next(list.nodes) then Note(list, "the C_TaxiMap list has no Current node") end
        list.nodes = {}
        ReadClassicNodes(list)
        list.source = "the classic functions"
        if not list.origin then
            Note(list, "no Current node")
            return list
        end
    end
    local originKey = list.nodes[list.origin].key
    for slot, node in pairs(list.nodes) do
        if node.state == "REACHABLE" then
            local parts, why = { originKey }, nil
            local okR, hops = Call(GetNumRoutes, slot)
            if not okR or issecret(hops) or type(hops) ~= "number" or hops < 1 then
                why = "hops unreadable"
            else
                for hop = 1, hops do
                    local okS, dest = Call(TaxiGetNodeSlot, slot, hop, false)
                    if not okS or dest == nil or issecret(dest) then
                        why = ("hop %d unreadable"):format(hop)
                        break
                    end
                    if not list.nodes[dest] then
                        why = ("hop %d goes through slot %s, which is not in the list"):format(hop, tostring(dest))
                        break
                    end
                    parts[#parts + 1] = list.nodes[dest].key
                end
            end
            if why then
                list.paths[slot], list.fallback[slot] = originKey .. ">" .. node.key, why -- from>to
            else
                list.paths[slot], list.hops[slot] = table.concat(parts, ">"), hops
            end
        end
    end
    return list
end

local function NodeCount(list)
    local n = 0
    for _ in pairs(list.nodes) do n = n + 1 end
    return n
end

local function OriginName(list) return list.origin and list.nodes[list.origin].name or "none" end

local function NotesText(list) return #list.notes > 0 and table.concat(list.notes, "; ") or "no details" end

local function PathText(list, slot)
    return list.paths[slot] .. (list.fallback[slot] and (" (fallback key: " .. list.fallback[slot] .. ")") or "")
end

-- A map session a pick may use: still open, or closed no more than SESSION_GRACE ago.
local function UsableSession(now)
    local s = session
    if s and (s.open or (s.closedAt and now - s.closedAt <= SESSION_GRACE)) then return s end
end

-- TakeTaxiNode post-hook. A usable session for the same flight master resolves the pick:
-- its keys are the ones the tooltips show. The live read tells which flight master it is, and stands
-- in when there is no usable session (an auto-taxi pick before our TAXIMAP_OPENED handler).
local function OnTakeTaxiNode(slot)
    seq = seq + 1
    local pickSeq, now = seq, GetTime()
    local live, usable = BuildNodeList(), UsableSession(now)
    local liveHas = live.origin and live.nodes[slot]
    if live.origin and not liveHas then
        Note(live, ("slot %s is not in the list from %s"):format(tostring(slot), live.source))
    end
    local sessionHas = usable and usable.list.origin and usable.list.nodes[slot]
    -- Names are compared only within one API: C_TaxiMap and TaxiNodeName may spell them differently.
    local comparable = usable and live.source == usable.list.source
    local sameMaster = sessionHas and (not live.origin or not comparable or OriginName(live) == OriginName(usable.list))
    local outOfDate = sameMaster and comparable and liveHas and live.nodes[slot].name ~= sessionHas.name
    local list, how
    if sameMaster and not outOfDate then
        list = usable.list
        how = usable.open and "open map session" or ("map session closed %.2f s before"):format(now - usable.closedAt)
        if not liveHas then
            how = how .. "; the live read failed: " .. NotesText(live)
        elseif live.paths[slot] == list.paths[slot] then
            how = how .. "; the live read agrees"
        elseif live.paths[slot] then
            how = ("%s; the live read gave %s from %s"):format(how, PathText(live, slot), live.source)
        else
            how = ("%s; the live read has the node as %s"):format(how, live.nodes[slot].state)
        end
    elseif liveHas then
        list = live
        how = (not usable and "live read; no map session")
            or (outOfDate and ("live read; the map session is out of date: slot %s is %s there"):format(
                tostring(slot), sessionHas.name))
            or (sessionHas and "live read; the map session is for another flight master")
            or "live read; the map session lacks this slot"
    end
    if not list then
        -- A map closing in this very frame proves there was one: e.g. an auto-taxi pick inside the
        -- TAXIMAP_OPENED dispatch, before our handler, whose click closed the map again.
        local closedNow = lastCloseEventAt == now
        if not usable and not next(live.nodes) and not closedNow then
            Debug(("TakeTaxiNode(%s) at %.2f with no flight map open: ignored"):format(tostring(slot), now))
            return
        end
        local state = tracker:GetState()
        Debug(("pick of slot %s at %.2f could not be resolved (%s%s%s)%s; the flight will be untracked"):format(
            tostring(slot), now, NotesText(live),
            usable and (sessionHas and "; the map session is for another flight master" or "; the map session lacks it") or "",
            (closedNow and not usable) and "; a flight map closed in this frame" or "",
            (state == "pending" and "; the earlier pick is cancelled")
                or (state == "resuming" and "; the saved flight is dropped") or ""))
        tracker:UnresolvedPick()
        return
    end
    local node = list.nodes[slot]
    if node.state ~= "REACHABLE" then
        Debug(("pick of slot %s at %.2f ignored: the node is %s (%s)"):format(tostring(slot), now, node.state, how))
        return
    end
    local route = { key = list.paths[slot], fromName = list.nodes[list.origin].name, toName = node.name,
                    hops = list.hops[slot] }
    pickGeo = { key = route.key, mapID = list.mapID, x = node.x, y = node.y }
    Debug(("pick of slot %s at %.2f: %s -> %s, path %s (%s)"):format(tostring(slot), now, route.fromName,
        route.toName, PathText(list, slot), how))
    tracker:Pick(route, now, pickSeq)
end

-- UnitOnTaxi("player") through pcall: true/false, or nil plus why it is unknown.
local function ReadOnTaxi()
    local ok, v = Call(UnitOnTaxi, "player")
    if not ok then return nil, "UnitOnTaxi is missing or failed" end
    if issecret(v) then return nil, "secret value" end
    return v and true or false
end

local function TakeReading(now)
    if not loadDone or loading then return end
    local v, problem = ReadOnTaxi()
    if problem ~= readingProblem then
        readingProblem = problem
        if problem then Debug(("on-taxi reading at %.2f is unknown: %s"):format(now, problem)) end
    end
    if v ~= nil and v ~= lastReading then
        if v and falseSince and tracker:GetState() == "flying" then
            Debug(("taxi flag was false for %.2f s"):format(now - falseSince))
        end
        falseSince = (not v) and now or nil
        Debug(("on-taxi reading at %.2f: %s"):format(now, tostring(v)))
        lastReading = v
    end
    tracker:Reading(v, now)
end

local function AddTooltipLine(slot)
    if not db.profile.tooltips then return end
    local list = (session and session.open) and session.list or BuildNodeList()
    local node = list and list.origin and list.nodes[slot]
    if not node or node.state ~= "REACHABLE" then return end
    local expected = store:Expected(list.paths[slot])
    if expected then
        GameTooltip:AddLine("Flight time: " .. FormatTime(expected), 1, 1, 1)
    else
        GameTooltip:AddLine("Flight time: not flown yet", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function HookFlightMap()
    if flightMapHooked then return end
    if type(FlightMap_FlightPointPinMixin) ~= "table"
        or type(FlightMap_FlightPointPinMixin.OnMouseEnter) ~= "function" then
        Debug("FlightMap_FlightPointPinMixin is missing: no flight-map tooltips")
        return
    end
    flightMapHooked = true
    hooksecurefunc(FlightMap_FlightPointPinMixin, "OnMouseEnter", function(pin)
        local d = pin.taxiNodeData
        if type(d) == "table" and d.slotIndex then AddTooltipLine(d.slotIndex) end
    end)
end

local function ReadCVarBool(name)
    local ok, v = Call(GetCVarBool, name)
    if ok and v ~= nil and not issecret(v) then return v and true or false end
    return nil
end

-- Arrival clock string; follows the game clock settings unless overridden.
local function ArrivalString(remaining)
    local p = db.profile
    local useLocal = p.clockSource == "local"
        or (p.clockSource == "game" and ReadCVarBool("timeMgrUseLocalTime") ~= false)
    local use24
    if p.clockFormat == "24" then
        use24 = true
    elseif p.clockFormat == "12" then
        use24 = false
    else
        local v = ReadCVarBool("timeMgrUseMilitaryTime")
        use24 = v == nil or v
    end
    if useLocal then return ArrivalClock.Local(time() + remaining, use24, date) end
    return ArrivalClock.Realm(realmClock:Now() + remaining, use24)
end

local function Render(now)
    local view = tracker:GetView(now)
    if view.mode == "hidden" and frozen then
        if now < frozen.untilTime then view = frozen.view else frozen = nil end
    end
    local arrival = (view.mode == "countdown" and db.profile.showArrival) and ArrivalString(view.remaining) or nil
    ns.Display:Render(view, arrival)
end

-- Debug only: how far from the picked destination the flight ended.
local function LandingPositionText(route)
    if not (pickGeo and pickGeo.key == route.key) then return "unavailable (no pick of this route this session)" end
    if not (pickGeo.mapID and pickGeo.x) then return "unavailable (the flight map gave no destination position)" end
    local ok, pos = Call(C_Map and C_Map.GetPlayerMapPosition, pickGeo.mapID, "player")
    if not ok then return "unavailable (C_Map.GetPlayerMapPosition is missing or failed)" end
    if issecret(pos) then return "unavailable (C_Map.GetPlayerMapPosition returned a secret value)" end
    if type(pos) ~= "table" or not pos.GetXY then
        return ("unavailable (no player position on map %s)"):format(tostring(pickGeo.mapID))
    end
    local okXY, x, y = pcall(pos.GetXY, pos)
    if not okXY or type(x) ~= "number" or type(y) ~= "number" or issecret(x) or issecret(y) then
        return "unavailable (unreadable player position)"
    end
    return ("%.3f map units from the destination"):format(math.sqrt((x - pickGeo.x) ^ 2 + (y - pickGeo.y) ^ 2))
end

local function OnLand(info)
    local p = db.profile
    lastLandAt = GetTime()
    if p.chat then
        if not info.route then
            Print(("flight: %s (not recorded: unknown route)"):format(FormatTime(info.duration)))
        else
            local suffix = REASON_TEXT[info.reason] or ""
            if info.reason == "updated" and info.expectedBefore then
                suffix = (" (expected %s)"):format(FormatTime(info.expectedBefore))
            end
            Print(("%s -> %s: %s%s"):format(ShortName(info.fromName), ShortName(info.toName),
                FormatTime(info.duration), suffix))
        end
    end
    if (p.freezeSeconds or 0) > 0 then
        frozen = { view = { mode = "frozen", fromName = info.fromName, toName = info.toName, duration = info.duration },
                   untilTime = lastLandAt + p.freezeSeconds }
    end
    if Debugging() and info.route then Debug("landing position: " .. LandingPositionText(info.route)) end
    Debug(("landed at %.2f: %s, %.1f s"):format(lastLandAt, tostring(info.reason), info.duration))
end

local function StatusText()
    local v = tracker:GetView(GetTime())
    if v.mode == "hidden" then return ("Not flying - %d routes learned"):format(store:Count()) end
    local name = v.toName and ShortName(v.toName) or "unknown route"
    if v.mode == "countdown" then return ("Flying: %s left - %s"):format(FormatTime(v.remaining), name) end
    if v.mode == "overtime" then return ("Flying: +%s - %s"):format(FormatTime(v.over), name) end
    if v.mode == "learning" then return ("Flying: %s (learning) - %s"):format(FormatTime(v.elapsed), name) end
    return ("Flying: %s - %s"):format(FormatTime(v.elapsed), name)
end

local function SetLocked(locked, fromPanel)
    db.profile.locked = locked and true or false
    ns.Display:UpdateLock()
    if not fromPanel then
        if optionsReady then ns.Options:Refresh() end
        Print(locked and "position locked." or "unlocked: drag the timer to move it, then /ftimer lock.")
    end
end

local function ResetPosition()
    local d = ns.DEFAULTS.profile.pos
    db.profile.pos.x, db.profile.pos.y = d.x, d.y
    ns.Display:ApplyPosition()
    if optionsReady then ns.Options:Refresh() end
end

local function SettingsChanged() ns.Display:ApplySettings() end

local function ForgetRoutes()
    store:Forget()
    Print("all learned flight times forgotten.")
    if optionsReady then ns.Options:Refresh() end
end

-- Every setting in the active profile back to its default. The
-- OnProfileReset callback re-applies them. Learned routes, debug mode and a flight in progress are
-- kept. The button route needs no refresh: its confirmation popup re-opens the page itself.
local function ResetDefaults(source)
    db:ResetProfile()
    if source ~= "button" and optionsReady then ns.Options:Refresh() end
    Print(("all settings in the profile \"%s\" reset to their defaults%s (learned flight times are kept)."):format(
        db:GetCurrentProfile(), source == "game" and " by the game's Defaults button" or ""))
end

local function PrintStatus()
    Print(StatusText())
    local reading = readingProblem and ("unknown (" .. readingProblem .. ")") or tostring(lastReading)
    Print(("tracker: %s; loading screen: %s; last reading: %s"):format(tracker:GetState(), tostring(loading), reading))
    if session then
        local l = session.list
        Print(("last flight map: %s, %s (system %s), map %s, %d nodes from %s, origin %s"):format(
            session.open and "open" or "closed", MapUIName(session.system), tostring(session.system),
            tostring(l.mapID), NodeCount(l), l.source, OriginName(l)))
    else
        Print("no flight map opened this session")
    end
    Print(("tooltips: classic %s, flight map %s; debug %s"):format(
        type(TaxiNodeOnButtonEnter) == "function" and "hooked" or "unavailable",
        flightMapHooked and "hooked" or "not loaded", Debugging() and "on" or "off"))
    Print(ns.Display:MouseStatus())
end

local function PrintRoutes()
    local list = store:List()
    if #list == 0 then
        Print("no routes learned yet.")
        return
    end
    for _, r in ipairs(list) do
        local flights = r.flights or 0
        local hops = r.hops and ("%d hop%s"):format(r.hops, r.hops == 1 and "" or "s") or "hops unknown"
        Print(("%s -> %s (%s): %s, %d flight%s%s"):format(ShortName(r.fromName), ShortName(r.toName), hops,
            FormatTime(r.expected), flights, flights == 1 and "" or "s", Debugging() and (", path " .. r.key) or ""))
    end
end

local function OpenOptions()
    if optionsReady then
        ns.Options:Open()
    else
        Print("the options panel is unavailable on this client (see the message at login). /ftimer help lists the commands.")
    end
end

-- The timer's right-click menu.
local function ContextMenu(_, root)
    root:CreateTitle("Forever Flight Timer")
    root:CreateButton("Options", function() OpenOptions() end)
    root:CreateCheckbox("Lock position", function() return db.profile.locked end,
        function() SetLocked(not db.profile.locked) end)
    root:CreateButton("Reset position", function()
        ResetPosition()
        Print("position reset.")
    end)
end

local function HandleSlash(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd, rest = (cmd or ""):lower(), (rest or ""):lower()
    if cmd == "" then
        OpenOptions()
    elseif cmd == "lock" then
        SetLocked(true)
    elseif cmd == "unlock" then
        SetLocked(false)
    elseif cmd == "resetpos" then
        ResetPosition()
        Print("position reset.")
    elseif cmd == "defaults" then
        if rest == "confirm" then
            ResetDefaults("slash")
        else
            Print("type /ftimer defaults confirm to reset all settings in the current profile to their defaults (learned flight times are kept).")
        end
    elseif cmd == "status" then
        PrintStatus()
    elseif cmd == "routes" then
        PrintRoutes()
    elseif cmd == "forget" then
        if rest == "all" then
            ForgetRoutes()
        else
            Print(("type /ftimer forget all to erase all %d learned routes."):format(store:Count()))
        end
    elseif cmd == "debug" then
        db.global.debug = not db.global.debug
        Print("debug " .. (db.global.debug and "on" or "off") .. ".")
    else
        Print("/ftimer (options), lock, unlock, resetpos, defaults, status, routes, forget, debug, help")
    end
end

-- Which taxi UI is really showing; checked a frame after TAXIMAP_OPENED.
local function ShownMapUI()
    local shown = {}
    for _, name in ipairs({ "TaxiFrame", "FlightMapFrame" }) do
        local f = _G[name]
        local ok, isShown = Call(type(f) == "table" and f.IsShown, f)
        if ok and isShown then shown[#shown + 1] = name end
    end
    return #shown > 0 and table.concat(shown, " and ") or "neither TaxiFrame nor FlightMapFrame"
end

-- Unverified in game: do C_TaxiMap's slot indexes match the classic functions TakeTaxiNode goes by?
local function DebugSlotCheck(l)
    if l.source ~= "C_TaxiMap" then return end
    local checked, differ = 0, 0
    for slot, n in pairs(l.nodes) do
        local okName, name = Call(TaxiNodeName, slot)
        local okType, kind = Call(TaxiNodeGetType, slot)
        name = okName and not issecret(name) and name or nil
        kind = okType and not issecret(kind) and kind or nil
        checked = checked + 1
        if name ~= n.name or (n.state ~= "OTHER" and kind ~= n.state) then
            differ = differ + 1
            if differ <= 5 then
                Debug(("  slot %s differs: C_TaxiMap %s (%s), TaxiNodeName %s, TaxiNodeGetType %s"):format(
                    tostring(slot), n.name, n.state, tostring(name), tostring(kind)))
            end
        end
    end
    if differ == 0 then
        Debug(("  slot check: TaxiNodeName and TaxiNodeGetType agree on all %d slots"):format(checked))
    else
        Debug(("  slot check: %d of %d slots differ"):format(differ, checked))
    end
    -- The classic TaxiFrame makes a button for every slot up to NumTaxiNodes().
    local okN, count = Call(NumTaxiNodes)
    if not okN or issecret(count) or type(count) ~= "number" then
        Debug("  slot check: NumTaxiNodes is unreadable, so missing slots can't be listed")
        return
    end
    local missing = {}
    for slot = 1, count do
        if not l.nodes[slot] then missing[#missing + 1] = tostring(slot) end
    end
    if #missing > 0 then
        Debug(("  slot check: slots %s of NumTaxiNodes' %d are not in the C_TaxiMap list"):format(
            table.concat(missing, ", "), count))
    end
end

local function DebugMapOpened(s)
    local l = s.list
    Debug(("flight map opened at %.2f: system %s (%s expected), map %s, %d nodes from %s, origin %s"):format(
        s.openedAt, tostring(s.system), MapUIName(s.system), tostring(l.mapID), NodeCount(l), l.source, OriginName(l)))
    for _, note in ipairs(l.notes) do Debug("  note: " .. note) end
    local slots, others = {}, 0
    for slot, node in pairs(l.nodes) do
        if node.state == "OTHER" then others = others + 1 else slots[#slots + 1] = slot end
    end
    table.sort(slots)
    for _, slot in ipairs(slots) do
        local n = l.nodes[slot]
        Debug(("  slot %s: %s [%s] %s%s"):format(tostring(slot), n.name, n.key, n.state,
            l.paths[slot] and (", path " .. PathText(l, slot)) or ""))
    end
    Debug(("  %d other nodes (not reachable)"):format(others))
    DebugSlotCheck(l)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() Debug("flight map UI shown: " .. ShownMapUI()) end)
    end
end

Handlers.LOADING_SCREEN_ENABLED = function()
    local now = GetTime()
    loading, lseAt, pewAt = true, now, nil
    Debug(("loading screen started at %.2f"):format(now))
    tracker:LoadingStarted()
end

Handlers.LOADING_SCREEN_DISABLED = function()
    local now = GetTime()
    Debug(("loading screen ended at %.2f"):format(now))
    if loading then
        loading = false
        tracker:LoadingEnded()
    end
    TakeReading(now)
end

Handlers.PLAYER_ENTERING_WORLD = function(isInitialLogin, isReloadingUi)
    local now = GetTime()
    pewAt = now
    Debug(("PLAYER_ENTERING_WORLD at %.2f (initial login %s, reload %s)"):format(now, tostring(isInitialLogin),
        tostring(isReloadingUi)))
    if not loadDone then -- the load path runs once per UI session
        loadDone = true
        tracker:OnLoad(now, isReloadingUi and true or false)
        Debug("load path: " .. (isReloadingUi and "reload" or (isInitialLogin and "login" or "other")))
    end
end

Handlers.TAXIMAP_OPENED = function(system)
    seq = seq + 1
    local now = GetTime()
    session = { open = true, list = BuildNodeList(), system = system, openedAt = now }
    if not next(session.list.nodes) then -- e.g. an auto-taxi pick closed the map before our handler
        session.open, session.closedAt = false, now
    end
    local wasState = tracker:GetState()
    tracker:CancelStale(lastCloseSeq, now)
    tracker:EndResume() -- a flight map proves the player is on the ground
    if Debugging() then
        DebugMapOpened(session)
        if not session.open then Debug("  no nodes: the map had closed again, or wasn't ready") end
        if wasState == "pending" and tracker:GetState() ~= "pending" then
            Debug("an earlier pick was cancelled by this map session")
        elseif wasState == "resuming" then
            Debug("the saved flight is over: a flight map opened")
        end
    end
end

Handlers.TAXIMAP_CLOSED = function()
    local now = GetTime()
    lastCloseEventAt = now
    if session and session.open then -- only close a session we opened
        seq = seq + 1
        session.open, session.closedAt = false, now
        lastCloseSeq = seq
        Debug(("flight map closed at %.2f"):format(now))
    else
        Debug(("flight map closed at %.2f (no open map session)"):format(now))
    end
end

Handlers.UI_ERROR_MESSAGE = function(errorType, message)
    if tracker:GetState() ~= "pending" then return end
    local how
    if not issecret(errorType) then
        local ok, token = Call(GetGameMessageInfo, errorType)
        if ok and type(token) == "string" and not issecret(token) and token:find("^ERR_TAXI") then how = token end
    end
    if not how and not issecret(message) and type(message) == "string" and taxiErrorText[message] then
        how = "matched the message text"
    end
    if how then
        Debug(("taxi error at %.2f (%s): %s"):format(GetTime(), how, issecret(message) and "secret message" or tostring(message)))
        tracker:CancelPending()
    end
end

-- Logged while a flight is picked or under way, and briefly after landing.
local function ControlEvent(name)
    return function(unit)
        local now = GetTime()
        if Debugging() and (tracker:GetState() ~= "idle" or (lastLandAt and now - lastLandAt <= DEBUG_AFTER_LANDING)) then
            Debug(("%s%s at %.2f"):format(name, unit and (" " .. tostring(unit)) or "", now))
        end
        TakeReading(now)
    end
end
Handlers.PLAYER_CONTROL_LOST = ControlEvent("PLAYER_CONTROL_LOST")
Handlers.PLAYER_CONTROL_GAINED = ControlEvent("PLAYER_CONTROL_GAINED")
Handlers.UNIT_FLAGS = ControlEvent("UNIT_FLAGS")

-- Pass-through changes wait for combat and addon restrictions to end.
Handlers.PLAYER_REGEN_ENABLED = function() ns.Display:ApplyMouse() end
Handlers.ADDON_RESTRICTION_STATE_CHANGED = function() ns.Display:ScheduleMouseUpdate() end

Handlers.PLAYER_LOGOUT = function()
    tracker:OnUnload(GetTime())
end

local function InstallHooks()
    if type(TakeTaxiNode) == "function" then
        hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode)
    else
        Debug("TakeTaxiNode is missing: every flight will be untracked")
    end
    if type(TaxiRequestEarlyLanding) == "function" then
        hooksecurefunc("TaxiRequestEarlyLanding", function()
            Debug(("early landing requested at %.2f"):format(GetTime()))
            tracker:EarlyLanding()
        end)
    end
    if C_SummonInfo and type(C_SummonInfo.ConfirmSummon) == "function" then
        hooksecurefunc(C_SummonInfo, "ConfirmSummon", function()
            Debug(("summon accepted at %.2f"):format(GetTime()))
            tracker:Interrupt()
        end)
    end
    if type(TaxiNodeOnButtonEnter) == "function" then
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
            local ok, slot = pcall(button.GetID, button)
            if ok then AddTooltipLine(slot) end
        end)
    else
        Debug("TaxiNodeOnButtonEnter is missing: no classic tooltips")
    end
    local ok, loaded = Call(C_AddOns and C_AddOns.IsAddOnLoaded, "Blizzard_FlightMap")
    if ok and loaded then HookFlightMap() end
end

local function Initialize()
    db = LibStub("AceDB-3.0"):New("ForeverFlightTimerDB", ns.DEFAULTS, true)
    if type(ForeverFlightTimerCharDB) ~= "table" then ForeverFlightTimerCharDB = {} end
    charDB = ForeverFlightTimerCharDB
    store = ns.RouteStore.New(db.global.routes)
    tracker = ns.FlightTracker.New(store, charDB, { onLand = OnLand })
    realmClock = ns.RealmClock.New(GetGameTime, GetTime)
    if store.dropped > 0 then Debug(("dropped %d malformed saved routes"):format(store.dropped)) end
    if tracker.droppedSave then Debug("dropped a malformed saved flight") end
    for _, name in ipairs(TAXI_ERRORS) do
        local text = _G[name]
        if type(text) == "string" then taxiErrorText[text] = true end
    end

    ns.Display:SetSampleArrival(ArrivalString) -- the preview's arrival follows the clock settings
    ns.Display:SetContextMenu(ContextMenu)
    ns.Display:SetDebug(Debug, Debugging)
    ns.Display:Init(db)
    db.RegisterCallback(core, "OnProfileChanged", SettingsChanged)
    db.RegisterCallback(core, "OnProfileCopied", SettingsChanged)
    db.RegisterCallback(core, "OnProfileReset", SettingsChanged)
    LSM.RegisterCallback(core, "LibSharedMedia_Registered", SettingsChanged)

    for _, event in ipairs(EVENTS) do
        if not pcall(core.RegisterEvent, core, event) then Debug("event not available: " .. event) end
    end
    if not pcall(core.RegisterUnitEvent, core, "UNIT_FLAGS", "player") then Debug("UNIT_FLAGS not available") end
    InstallHooks()

    SLASH_FOREVERFLIGHTTIMER1 = "/ftimer"
    SLASH_FOREVERFLIGHTTIMER2 = "/flighttimer"
    SlashCmdList.FOREVERFLIGHTTIMER = HandleSlash

    local acc = 0
    core:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < TICK then return end
        acc = 0
        local now = GetTime()
        if loading and ((pewAt and now - pewAt >= PEW_FAILSAFE) or (lseAt and not pewAt and now - lseAt >= LSE_FAILSAFE)) then
            loading = false
            tracker:LoadingEnded()
            Debug(("loading flag cleared by the failsafe at %.2f"):format(now))
        end
        realmClock:Now() -- keeps watching for the realm minute change
        TakeReading(now)
        Render(now)
    end)

    -- Last, and isolated: the panel depends on the Settings UI and Ace3 (see FIT's history).
    local ok, err = pcall(ns.Options.Init, ns.Options, db, StatusText, {
        resetPosition = ResetPosition,
        setLocked = SetLocked,
        setPreview = function(on) ns.Display:SetPreview(on) end,
        settingsChanged = SettingsChanged,
        forgetRoutes = ForgetRoutes,
        resetDefaults = ResetDefaults,
        routeCount = function() return store:Count() end,
    })
    optionsReady = ok
    if not ok then
        Print("the options panel is unavailable on this client: " .. tostring(err) .. " -- the timer itself still works.")
    end
end

core:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            Initialize()
        elseif name == "Blizzard_FlightMap" and db then
            HookFlightMap()
        end
        return -- ADDON_LOADED stays registered: Blizzard_FlightMap is load-on-demand
    end
    local handler = Handlers[event]
    if handler then handler(...) end
end)
core:RegisterEvent("ADDON_LOADED")
