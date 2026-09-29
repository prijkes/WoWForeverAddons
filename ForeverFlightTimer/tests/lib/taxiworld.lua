-- The Forever taxi world both smoke scripts run in: flight-map APIs, clocks and CVars, stubbed with
-- globals this client has, plus helpers that act like the player.
local W = require("wowstub")

local X = {
    taxi = {
        live = false,          -- the flight map is open (the server answers taxi queries)
        onTaxi = false,        -- UnitOnTaxi("player")
        closeOnTake = false,   -- TakeTaxiNode closes the map before our post-hook runs
        noCurrentInMap = false, -- C_TaxiMap lists the nodes but none as Current
        secretOnTaxi = false,  -- UnitOnTaxi returns a secret value
        badRoutes = {},        -- slots whose hop count can't be read
        classicAfterClose = false, -- the classic functions still answer after the map closes
        muteOnTake = false,    -- the taxi functions go silent inside TakeTaxiNode (until mute is reset)
        mute = false,
        hideSlotInMap = nil,   -- a slot C_TaxiMap leaves out
        secretNodeName = nil,  -- a slot whose name is secret in both APIs
        classicNames = {},     -- slot -> a different TaxiNodeName
        badHops = {},          -- slots whose hop destinations can't be read
        numNodesFails = false, -- NumTaxiNodes errors
    },
    cvars = {},   -- GetCVarBool answers; nil = unreadable (the addon then uses local time, 24 h)
    SECRET = {},  -- the one value issecretvalue() reports as secret
}

X.NODES = {
    { nodeID = 25, name = "Crossroads, The Barrens", state = 0, x = 0.5, y = 0.5 },
    { nodeID = 80, name = "Ratchet, The Barrens", state = 1, x = 0.6, y = 0.6 },
    { nodeID = 23, name = "Orgrimmar, Durotar", state = 1, x = 0.6, y = 0.3 },
    { nodeID = 77, name = "Camp Taurajo, The Barrens", state = 1, x = 0.45, y = 0.7 },
    { nodeID = 99, name = "Far Away, Somewhere", state = 2, x = 0.1, y = 0.1 },
}
local PATHS = { [2] = { 2 }, [3] = { 4, 3 }, [4] = { 4 } } -- slot 3 flies via Camp Taurajo
local TYPES = { [0] = "CURRENT", [1] = "REACHABLE", [2] = "DISTANT" } -- TaxiNodeGetType, as TaxiFrame.lua reads it
local TAXI_ERRORS = {
    "ERR_TAXIINCOMBAT", "ERR_TAXINOPATH", "ERR_TAXINOPATHS", "ERR_TAXINOSUCHPATH", "ERR_TAXINOTELIGIBLE",
    "ERR_TAXINOTENOUGHMONEY", "ERR_TAXINOTSTANDING", "ERR_TAXINOTVISITED", "ERR_TAXINOVENDORNEARBY",
    "ERR_TAXIPLAYERALREADYMOUNTED", "ERR_TAXIPLAYERBUSY", "ERR_TAXIPLAYERMOVING", "ERR_TAXIPLAYERSHAPESHIFTED",
    "ERR_TAXISAMENODE", "ERR_TAXITOOFARAWAY", "ERR_TAXIUNSPECIFIEDSERVERERROR",
}

-- Clocks, as offsets from W.now = 1000 (a run's start): the realm clock reads 03:07:12 then, and
-- the local clock 20:15:00. The local clock is UTC here, so arrival times are deterministic.
local START = 1000
local REALM_AT_START = 3 * 3600 + 7 * 60 + 12
local LOCAL_AT_START = 20 * 3600 + 15 * 60

local S = W.STUBS
S.issecretvalue = function(v) return v == X.SECRET end
S.GetGameTime = function()
    local s = (REALM_AT_START + (W.now - START)) % 86400
    return math.floor(s / 3600), math.floor(s % 3600 / 60)
end
S.time = function() return LOCAL_AT_START + math.floor(W.now - START) end
S.date = function(fmt, t)
    if fmt == "*t" then return os.date("!*t", t) end
    return os.date(fmt, t)
end
S.GetCVarBool = function(name) return X.cvars[name] end
S.Enum = { FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 }, UIMapSystem = { Taxi = 1 },
           AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 } }
local function mapAnswers() return X.taxi.live and not X.taxi.mute end
local function classicAnswers() return (X.taxi.live or X.taxi.classicAfterClose) and not X.taxi.mute end
S.GetTaxiMapID = function() return mapAnswers() and 1463 or nil end
S.C_TaxiMap = {
    GetAllTaxiNodes = function()
        if not mapAnswers() then return {} end
        local out = {}
        for i, n in ipairs(X.NODES) do
            if i ~= X.taxi.hideSlotInMap then
                local state = n.state
                if X.taxi.noCurrentInMap and state == 0 then state = 2 end
                out[#out + 1] = { nodeID = n.nodeID, state = state, slotIndex = i,
                                  name = X.taxi.secretNodeName == i and X.SECRET or n.name,
                                  position = { GetXY = function() return n.x, n.y end } }
            end
        end
        return out
    end,
}
S.NumTaxiNodes = function()
    if X.taxi.numNodesFails then error("simulated NumTaxiNodes failure") end
    return classicAnswers() and #X.NODES or 0
end
S.TaxiNodeName = function(slot)
    if X.taxi.secretNodeName == slot then return X.SECRET end
    return X.taxi.classicNames[slot] or (X.NODES[slot] and X.NODES[slot].name)
end
S.TaxiNodeGetType = function(slot) return X.NODES[slot] and TYPES[X.NODES[slot].state] end
S.GetNumRoutes = function(slot)
    if X.taxi.badRoutes[slot] then return nil end
    return PATHS[slot] and #PATHS[slot] or 0
end
S.TaxiGetNodeSlot = function(slot, hop)
    if X.taxi.badHops[slot] then return nil end
    return PATHS[slot] and PATHS[slot][hop]
end
S.TakeTaxiNode = function()
    if X.taxi.closeOnTake then X.closeMap() end -- the click closes the map before our post-hook
    if X.taxi.muteOnTake then X.taxi.mute = true end
end
S.TaxiRequestEarlyLanding = function() end
S.UnitOnTaxi = function()
    if X.taxi.secretOnTaxi then return X.SECRET end
    return X.taxi.onTaxi
end
S.C_SummonInfo = { ConfirmSummon = function() end }
S.TaxiNodeOnButtonEnter = function(button) -- Blizzard's classic tooltip builder
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(TaxiNodeName(button:GetID()))
    GameTooltip:Show()
end
S.GetGameMessageInfo = function(errorType) if errorType == 1 then return "ERR_TAXINOTENOUGHMONEY" end end
for _, name in ipairs(TAXI_ERRORS) do S[name] = name .. " (text)" end
S.C_Map = { -- the player is always at Ratchet
    GetPlayerMapPosition = function() return { GetXY = function() return X.NODES[2].x, X.NODES[2].y end } end,
}
local loadedAddOns = {}
S.C_AddOns = { IsAddOnLoaded = function(name) return loadedAddOns[name] or false end }
S.TaxiFrame = W.NewFrame("Frame", "TaxiFrame") -- Blizzard_UIPanels_Game is always loaded
S.TaxiFrame:Hide()
W.TEMPLATE_MIXINS.FlightMap_FlightPointPinTemplate = "FlightMap_FlightPointPinMixin"

-- Blizzard_FlightMap is load-on-demand.
function X.defineFlightMap()
    W.NewFrame("Frame", "FlightMapFrame"):Hide()
    rawset(_G, "FlightMap_FlightPointPinMixin", {
        OnMouseEnter = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_PRESERVE")
            GameTooltip:AddLine(self.taxiNodeData.name)
            GameTooltip:Show()
        end,
    })
    loadedAddOns.Blizzard_FlightMap = true
end

function X.install()
    W.install({
        own = { "TimeFormat", "ArrivalClock", "RealmClock", "RouteStore", "FlightTracker", "Defaults", "Display",
                "Options", "Core" },
        expectedNil = { "ForeverFlightTimerCharDB", "FlightMapFrame", "MenuUtil" }, -- MenuUtil: removed by one test
        allowedWrites = { "ForeverFlightTimerCharDB", "SLASH_FOREVERFLIGHTTIMER1", "SLASH_FOREVERFLIGHTTIMER2" },
        knownMethods = { "SetClampedToScreen", "SetMovable", "RegisterForDrag", "SetJustifyH",
                         "SetAllPoints", "SetColorTexture", "SetShadowOffset", "SetShadowColor", "SetTextColor",
                         "SetBackdropColor", "SetBackdropBorderColor", "ClearAllPoints", "SetPoint",
                         "StopMovingOrSizing", "SetOwner", "AddLine", "SetMinMaxValues", "SetStatusBarTexture" },
    })
end

function X.load(ns) W.loadToc("ForeverFlightTimer", ns) end

-------------------------------------------------------------------------------- the player
function X.slash(cmd) SlashCmdList.FOREVERFLIGHTTIMER(cmd) end
function X.routes() return ForeverFlightTimerDB.global.routes end

-- System 1 (Enum.UIMapSystem.Taxi) opens the classic TaxiFrame; others the modern FlightMapFrame.
function X.openMap(system)
    system = system or 1
    X.taxi.live = true
    if system == 1 then TaxiFrame:Show() else FlightMapFrame:Show() end
    W.fireEvent("TAXIMAP_OPENED", system)
end

function X.closeMap()
    if X.taxi.live then
        X.taxi.live = false
        TaxiFrame:Hide()
        if rawget(_G, "FlightMapFrame") then FlightMapFrame:Hide() end
        W.fireEvent("TAXIMAP_CLOSED")
    end
end

function X.takeoff() X.taxi.onTaxi = true; W.fireEvent("PLAYER_CONTROL_LOST"); W.tick(0.2) end
function X.land() X.taxi.onTaxi = false; W.fireEvent("PLAYER_CONTROL_GAINED"); W.tick(0.5) end
function X.button(slot) local b = W.NewFrame("Button"); b:SetID(slot); return b end

-- A whole flight lasting seconds + 0.2 (the takeoff tick).
function X.flyTo(slot, seconds)
    X.openMap(); TakeTaxiNode(slot); X.closeMap(); X.takeoff(); W.tick(seconds); X.land()
end

function X.aceDB()
    for db in pairs(LibStub("AceDB-3.0").db_registry) do
        if db.sv == ForeverFlightTimerDB then return db end
    end
end
function X.profile() return X.aceDB().profile end

-------------------------------------------------------------------------------- sessions
-- Saved variables and GetTime() carry over to the next UI session, as they do in the game.
local function serialize(v)
    local t = type(v)
    if t == "string" then return ("%q"):format(v) end
    if t == "number" then return ("%.17g"):format(v) end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then return "nil" end
    local parts = {}
    for k, x in pairs(v) do
        if type(x) ~= "function" then parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(x) end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function X.saveSession(path)
    local f = assert(io.open(path, "w"))
    f:write("return " .. serialize({ db = ForeverFlightTimerDB, char = ForeverFlightTimerCharDB, now = W.now }))
    f:close()
end

function X.restoreSession(path)
    local s = dofile(path)
    rawset(_G, "ForeverFlightTimerDB", s.db)
    rawset(_G, "ForeverFlightTimerCharDB", s.char)
    return s
end

return X
