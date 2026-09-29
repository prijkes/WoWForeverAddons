-- Glue: WoW API reads, events, 10 Hz ticker, freeze, chat output and slash commands.
local ADDON_NAME, ns = ...

local LSM = LibStub("LibSharedMedia-3.0")
local TimeFormat = ns.TimeFormat

local PREFIX = "|cff33ff99Forever Instance Timer|r: "
local TICK = 0.1

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "ADDON_RESTRICTION_STATE_CHANGED",
}
local WATCHER_EVENTS = {
    PLAYER_ENTERING_WORLD = true, LOADING_SCREEN_ENABLED = true, LOADING_SCREEN_DISABLED = true,
    ZONE_CHANGED_NEW_AREA = true, PLAYER_DEAD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true,
}

local issecret = issecretvalue or function() return false end

local core = CreateFrame("Frame")
local db, charDB, clock, watcher, tracker
local freeze -- { name, seconds, untilTime } while a finished run is shown
local optionsReady = false -- false if the options panel failed to initialize on this client

local function Print(msg) print(PREFIX .. msg) end

local function Debug(msg)
    if db and db.global.debug then print("|cff33ff99FIT debug|r: " .. msg) end
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- Raw game-state read for ZoneWatcher. Unreadable or secret values are left out, so a
-- secret value is never tested in a boolean context.
local function ReadGameState()
    local raw = { ok = false }
    local ok, inInstance = Call(IsInInstance)
    if not ok or issecret(inInstance) then return raw end
    raw.ok = true
    raw.inInstance = inInstance and true or false
    if raw.inInstance then
        local ok2, name, instanceType, _, _, _, _, _, instanceID = Call(GetInstanceInfo)
        if ok2 and not issecret(name) and not issecret(instanceType) and not issecret(instanceID) then
            raw.instanceName, raw.instanceType, raw.instanceID = name, instanceType, instanceID
        end
    end
    local okD, dog = Call(UnitIsDeadOrGhost, "player")
    if okD and not issecret(dog) then raw.dogReadable, raw.dog = true, dog and true or false end
    local okG, ghost = Call(UnitIsGhost, "player")
    if okG and not issecret(ghost) then raw.ghostReadable, raw.ghost = true, ghost and true or false end
    local okX, deadOnly = Call(UnitIsDead, "player")
    if okX and not issecret(deadOnly) then raw.deadReadable, raw.deadOnly = true, deadOnly and true or false end
    return raw
end

local function GetRules()
    local p = db.profile
    return { types = p.types, awayMode = p.awayMode, giveUp = p.giveUp,
             graceMinutes = p.graceMinutes, offline = p.offline }
end

local function FormatTime(seconds)
    local p = db.profile
    return TimeFormat.Format(seconds, p.timeStyle, p.showTenths)
end

local function BuildView(now)
    local state = tracker:GetState()
    if state ~= "idle" then
        return { mode = state == "inside" and "running" or "away", name = tracker:GetInstanceName(),
                 seconds = tracker:GetDisplayElapsed(now) }
    end
    if freeze then
        if now < freeze.untilTime then
            return { mode = "frozen", name = freeze.name, seconds = freeze.seconds }
        end
        freeze = nil
    end
    return { mode = "hidden" }
end

local function Render(now)
    ns.Display:Render(BuildView(now or clock:Now()))
end

local function OnRunStart(info)
    freeze = nil
    Debug("run started: " .. tostring(info.name))
end

local function OnRunFinish(info)
    Debug(("run finished (%s%s): %s %s"):format(info.reason, info.silent and ", silent" or "",
        tostring(info.name), FormatTime(info.seconds)))
    if info.silent then return end
    local p = db.profile
    if p.chat then
        Print(("%s - %s"):format(info.name or "?", FormatTime(info.seconds)))
    end
    if not info.replaced and (p.freezeSeconds or 0) > 0 then
        freeze = { name = info.name, seconds = info.seconds, untilTime = clock:Now() + p.freezeSeconds }
    end
end

local lastRunLog
local function OnRunChange()
    if not (db and db.global.debug) then return end
    local run = tracker:GetRun()
    local line = ("state=%s pending=%s revive=%s pause=%s"):format(run.state,
        run.pending and run.pending.kind or "-", run.revivedAt and "pending" or "-",
        run.pauseSince and "open" or "-")
    if line ~= lastRunLog then
        lastRunLog = line
        Debug(line)
    end
end

local lastReadingLog
local function OnReading(reading, now)
    if db.global.debug then
        local line = ("reading: in=%s type=%s id=%s name=%s dead=%s"):format(tostring(reading.inInstance),
            tostring(reading.instanceType), tostring(reading.instanceID), tostring(reading.instanceName),
            tostring(reading.dead))
        if line ~= lastReadingLog or reading.arrivedAt then
            lastReadingLog = line
            Debug(line .. (reading.arrivedAt and " (after loading screen)" or ""))
        end
    end
    tracker:Observe(reading, now)
end

-- Time first, so a long instance name is what gets cut off in the options title row.
local function StatusText()
    local state = tracker:GetState()
    if state == "idle" then return "Current run: none" end
    return ("Current run: %s - %s%s"):format(FormatTime(tracker:GetDisplayElapsed(clock:Now())),
        tracker:GetInstanceName() or "?", state == "away" and " (corpse run)" or "")
end

local function ResetRun()
    freeze = nil
    tracker:Reset(clock:Now(), watcher:GetLastReading())
    Render()
    Print("timer reset.")
end

local function SetLocked(locked, fromPanel)
    db.profile.locked = locked and true or false
    ns.Display:UpdateLock()
    if not fromPanel then
        if optionsReady then ns.Options:Refresh() end
        Print(locked and "position locked." or "unlocked: drag the timer to move it, then /itimer lock.")
    end
end

local function ResetPosition()
    local d = ns.DEFAULTS.profile.pos
    db.profile.pos.x, db.profile.pos.y = d.x, d.y
    ns.Display:ApplyPosition()
    if optionsReady then ns.Options:Refresh() end
end

local function SettingsChanged(kind)
    if kind == "rules" then tracker:OnRulesChanged(clock:Now()) end
    ns.Display:ApplySettings()
end

local function OnProfileUpdated()
    tracker:OnRulesChanged(clock:Now())
    ns.Display:ApplySettings()
end

-- Every setting in the active profile back to its default, run rules included.
-- OnProfileReset → OnProfileUpdated re-applies them; a run in progress follows the default
-- rules from then on. The button route needs no refresh: its confirmation popup re-opens the page.
local function ResetDefaults(source)
    db:ResetProfile()
    if source ~= "button" and optionsReady then ns.Options:Refresh() end
    Print(("all settings in the profile \"%s\" reset to their defaults%s."):format(db:GetCurrentProfile(),
        source == "game" and " by the game's Defaults button" or ""))
end

local function PrintStatus()
    Print(StatusText())
    local run = tracker:GetRun()
    Print(("state=%s pending=%s revive=%s pause=%s paused=%.1fs"):format(run.state,
        run.pending and run.pending.kind or "none", run.revivedAt and "pending" or "none",
        run.pauseSince and "open" or "none", run.paused or 0))
    local r = watcher:GetLastReading()
    if r then
        Print(("last reading: in=%s type=%s id=%s name=%s dead=%s"):format(tostring(r.inInstance),
            tostring(r.instanceType), tostring(r.instanceID), tostring(r.instanceName), tostring(r.dead)))
    else
        Print("last reading: none since the last loading screen")
    end
    Print(("loading=%s deadFallback=%s"):format(tostring(watcher:IsLoading()), tostring(watcher:IsUsingDeadFallback())))
    local p = db.profile
    Print(("rules: away=%s stopWaiting=%s grace=%dm offline=%s"):format(p.awayMode, p.giveUp,
        p.graceMinutes, p.offline))
    Print(ns.Display:MouseStatus())
end

local function OpenOptions()
    if optionsReady then
        ns.Options:Open()
    else
        Print("the options panel is unavailable on this client (see the message at login). /itimer help lists the commands.")
    end
end

-- The timer's right-click menu.
local function ContextMenu(_, root)
    root:CreateTitle("Forever Instance Timer")
    root:CreateButton("Options", function() OpenOptions() end)
    root:CreateCheckbox("Lock position", function() return db.profile.locked end,
        function() SetLocked(not db.profile.locked) end)
    root:CreateButton("Reset position", function()
        ResetPosition()
        Print("position reset.")
    end)
    root:CreateButton("Reset current run", function() ResetRun() end)
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
    elseif cmd == "reset" then
        ResetRun()
    elseif cmd == "resetpos" then
        ResetPosition()
        Print("position reset.")
    elseif cmd == "defaults" then
        if rest == "confirm" then
            ResetDefaults("slash")
        else
            Print("type /itimer defaults confirm to reset all settings in the current profile, including the run rules, to their defaults (a run in progress follows the default rules from then on, so a corpse run can end).")
        end
    elseif cmd == "status" then
        PrintStatus()
    elseif cmd == "debug" then
        db.global.debug = not db.global.debug
        Print("debug " .. (db.global.debug and "on" or "off") .. ".")
    else
        Print("/itimer (options), lock, unlock, reset, resetpos, defaults, status, debug, help")
    end
end

local actions = {
    resetRun = ResetRun,
    resetPosition = ResetPosition,
    resetDefaults = ResetDefaults,
    setLocked = SetLocked,
    setPreview = function(on) ns.Display:SetPreview(on) end,
    settingsChanged = SettingsChanged,
}

local function Initialize()
    core:UnregisterEvent("ADDON_LOADED")
    db = LibStub("AceDB-3.0"):New("ForeverInstanceTimerDB", ns.DEFAULTS, true)
    if type(ForeverInstanceTimerCharDB) ~= "table" then ForeverInstanceTimerCharDB = {} end
    charDB = ForeverInstanceTimerCharDB

    clock = ns.Clock.New(GetServerTime or time, GetTime)
    tracker = ns.RunTracker.New(charDB, GetRules,
        { onStart = OnRunStart, onFinish = OnRunFinish, onChange = OnRunChange })
    if tracker.validationFailed then Debug("discarded malformed saved run data.") end
    watcher = ns.ZoneWatcher.New(ReadGameState, OnReading, charDB.deadFlag)

    ns.Display:SetContextMenu(ContextMenu)
    ns.Display:SetDebug(Debug, function() return db and db.global.debug end)
    ns.Display:Init(db)

    db.RegisterCallback(core, "OnProfileChanged", OnProfileUpdated)
    db.RegisterCallback(core, "OnProfileCopied", OnProfileUpdated)
    db.RegisterCallback(core, "OnProfileReset", OnProfileUpdated)
    LSM.RegisterCallback(core, "LibSharedMedia_Registered", function() ns.Display:ApplySettings() end)

    for _, event in ipairs(EVENTS) do
        if not pcall(core.RegisterEvent, core, event) then
            Debug("event not available on this client: " .. event)
        end
    end

    SLASH_FOREVERINSTANCETIMER1 = "/itimer"
    SLASH_FOREVERINSTANCETIMER2 = "/instancetimer"
    SlashCmdList.FOREVERINSTANCETIMER = HandleSlash

    local acc = 0
    core:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < TICK then return end
        acc = 0
        local now = clock:Now()
        watcher:Tick(now)
        Render(now)
    end)

    -- Last, and isolated: the panel depends on the Settings UI and Ace3, which a client update
    -- can break. The timer, events and slash commands above keep working if it fails.
    local ok, err = pcall(ns.Options.Init, ns.Options, db, StatusText, actions)
    optionsReady = ok
    if not ok then
        Print("the options panel is unavailable on this client: " .. tostring(err)
            .. " -- the timer itself still works.")
    end
end

core:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then Initialize() end
        return
    end
    local now = clock:Now()
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin = ...
        if isInitialLogin then tracker:OnLogin(now) end
        ns.Display:SetInCombat(InCombatLockdown())
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.Display:SetInCombat(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.Display:SetInCombat(false)
        ns.Display:ApplyMouse() -- pass-through changes wait for combat to end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        ns.Display:ScheduleMouseUpdate()
        return
    elseif event == "PLAYER_LOGOUT" then
        tracker:OnLogout(now)
        charDB.deadFlag = watcher:GetDeadFlag()
        return
    end
    if WATCHER_EVENTS[event] then watcher:OnEvent(event, now, ...) end
end)
core:RegisterEvent("ADDON_LOADED")
