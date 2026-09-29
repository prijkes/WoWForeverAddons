-- The flight bar. Renders the view Core hands it; owns no timing logic.
local _, ns = ...

local Display = {}
ns.Display = Display

local LSM = LibStub("LibSharedMedia-3.0")
local TimeFormat = ns.TimeFormat

local PREVIEW_STRATA = "FULLSCREEN_DIALOG" -- above the Settings window
local SAMPLE = { mode = "countdown", fromName = "Crossroads, The Barrens", toName = "Ratchet, The Barrens",
                 elapsed = 20, remaining = 32, expected = 52 }
local SAMPLE_ARRIVAL = "14:32" -- used until Core supplies the clock (SetSampleArrival)

local db, frame, bar, barBg, textLayer, nameText, timeText, arrivalText, highlight
local lastView, lastArrival = { mode = "hidden" }, nil
local preview, unlocked = false, false
local sampleArrival -- function(remaining) -> arrival string, so the preview follows the clock settings

local function Profile() return db.profile end

-- "Crossroads, The Barrens" -> "Crossroads", unless full names are wanted.
function Display.ShortName(name, full)
    if type(name) ~= "string" then return nil end
    if full then return name end
    return name:match("^([^,]+)") or name
end

-- A saved media name that isn't registered (yet) falls back to the default for drawing only.
local function Fetch(kind, name)
    return LSM:Fetch(kind, name, true) or LSM:Fetch(kind, LSM:GetDefault(kind))
end

local function FontFlags(f)
    local flags = f.outline ~= "NONE" and f.outline or ""
    if f.mono then flags = (flags ~= "" and (flags .. ",") or "") .. "MONOCHROME" end
    return flags
end

local function ApplyFont(fs, f)
    local path = Fetch("font", f.face) or STANDARD_TEXT_FONT
    if not fs:SetFont(path, f.size, FontFlags(f)) then
        fs:SetFont(STANDARD_TEXT_FONT, f.size, FontFlags(f))
    end
    if f.shadow then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function ApplyBackdrop(p)
    local bgFile = p.bg.show and Fetch("background", p.bg.texture) or nil
    local edgeFile = p.border.show and Fetch("border", p.border.texture) or nil
    if bgFile == "" then bgFile = nil end
    if edgeFile == "" then edgeFile = nil end
    if not bgFile and not edgeFile then
        frame:SetBackdrop(nil)
        return
    end
    local inset = edgeFile and math.floor(p.border.size / 4) or 0
    frame:SetBackdrop({
        bgFile = bgFile,
        edgeFile = edgeFile,
        edgeSize = edgeFile and p.border.size or nil,
        tile = false,
        insets = { left = inset, right = inset, top = inset, bottom = inset },
    })
    if bgFile then
        local c = p.bg.color
        frame:SetBackdropColor(c.r, c.g, c.b, c.a)
    end
    if edgeFile then
        local c = p.border.color
        frame:SetBackdropBorderColor(c.r, c.g, c.b, c.a)
    end
end

local function Layout()
    local p = Profile()
    local pad = p.padding
    local below = p.showArrival and p.arrivalPos == "below"
    local extra = below and (p.font.size + 4) or 0
    frame:SetSize(p.width + 2 * pad, p.height + extra + 2 * pad)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    bar:SetSize(p.width, p.height)
    timeText:ClearAllPoints()
    timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    nameText:ClearAllPoints()
    nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    nameText:SetPoint("RIGHT", timeText, "LEFT", -6, 0)
    arrivalText:ClearAllPoints()
    arrivalText:SetPoint("TOP", bar, "BOTTOM", 0, -2)
end

local function IsVisible(view)
    if preview or unlocked then return true end
    if view.mode == "hidden" then return false end
    return Profile().showTimer
end

local function Fmt(seconds)
    local p = Profile()
    return TimeFormat.Format(seconds, p.timeStyle, p.showTenths)
end

local function SavePosition()
    local p = Profile()
    local s = frame:GetScale()
    local cx, top = frame:GetCenter(), frame:GetTop()
    local ucx, utop = UIParent:GetCenter(), UIParent:GetTop()
    if not (cx and top and ucx and utop) then return end
    p.pos.x = math.floor(cx * s - ucx + 0.5)
    p.pos.y = math.floor(top * s - utop + 0.5)
    Display:ApplyPosition()
    if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
end

-- Right-click menu and mouse handling. Core supplies the menu generator
-- and its debug function. The pass-through buttons change only outside combat and the client's
-- addon restrictions, because SetPassThroughButtons has restrictions.
local PASS_ALL = { "LeftButton", "MiddleButton" }
for n = 4, 31 do PASS_ALL[#PASS_ALL + 1] = "Button" .. n end
local PASS_SHORT = { "LeftButton", "MiddleButton", "Button4", "Button5" }
local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }
local contextMenu, debugNote, debugOn
local passList, passSet, passBroken, catchUpPending = PASS_ALL, false, false, false
local noted = {}

-- A note is printed once per session, and counts as printed only in debug mode.
local function Note(key, msg)
    if debugNote and not noted[key] and (not debugOn or debugOn()) then
        noted[key] = true
        debugNote(msg)
    end
end

local function MenuAvailable()
    return Profile().rightClickMenu and contextMenu ~= nil and type(MenuUtil) == "table"
        and type(MenuUtil.CreateContextMenu) == "function"
end

local function PassThroughSupported()
    return not passBroken and type(frame.SetPassThroughButtons) == "function"
end

local function PassThroughAllowed()
    if InCombatLockdown() then return false end
    local ra, types = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
    if type(ra) == "table" and type(ra.IsAddOnRestrictionActive) == "function" and type(types) == "table" then
        for _, name in ipairs(RESTRICTIONS) do
            if types[name] ~= nil then
                local ok, active = pcall(ra.IsAddOnRestrictionActive, types[name])
                if ok and active then return false end
            end
        end
    end
    return true
end

local function SetPassThrough(on)
    local ok
    if on then
        ok = pcall(frame.SetPassThroughButtons, frame, unpack(passList))
        if not ok and passList == PASS_ALL then
            passList = PASS_SHORT
            ok = pcall(frame.SetPassThroughButtons, frame, unpack(passList))
        end
    else
        ok = pcall(frame.SetPassThroughButtons, frame)
    end
    if ok then passSet = on else passBroken = true end
end

function Display:SetContextMenu(generator) contextMenu = generator end
function Display:SetDebug(fn, isOn) debugNote, debugOn = fn, isOn end

-- The frame's mouse state: unlocked takes the mouse; locked with the menu catches
-- right-clicks only; otherwise fully click-through.
function Display:ApplyMouse()
    if not frame then return end
    local supported = PassThroughSupported()
    local want = supported and not unlocked and MenuAvailable() or false
    if supported and want ~= passSet and PassThroughAllowed() then SetPassThrough(want) end
    -- Checked on every call, so a note missed while debug was off shows once debug is on.
    if passList == PASS_SHORT then Note("short", "pass-through fell back to buttons 1-5") end
    if not PassThroughSupported() then
        Note("unsupported", "pass-through buttons are not supported on this client: the locked timer stays click-through, the menu works when unlocked")
    end
    if unlocked then
        frame:EnableMouse(true)
    elseif MenuAvailable() and passSet and PassThroughSupported() then
        frame:SetMouseClickEnabled(true)
        frame:SetMouseMotionEnabled(false)
    else
        frame:EnableMouse(false)
    end
end

-- One line for /… status: the menu, and the buttons passing through now.
function Display:MouseStatus()
    if not frame then return "right-click menu: not set up" end
    local menu = not Profile().rightClickMenu and "off"
        or not MenuAvailable() and "unavailable on this client" or "on"
    local supported = PassThroughSupported()
    local waiting = supported and (not unlocked and MenuAvailable() or false) ~= passSet
    -- With the menu off, only a clear that still waits is worth showing.
    if menu ~= "on" and not waiting then return "right-click menu: " .. menu end
    if not supported then
        return "right-click menu: on; pass-through: unsupported, so the menu works only when unlocked"
    end
    local now = not passSet and "none"
        or passList == PASS_SHORT and "buttons 1-5 but the right one" or "all but the right button"
    return ("right-click menu: %s; pass-through: %s%s"):format(menu, now,
        waiting and ", waiting for combat or a restriction to end" or unlocked and " (unlocked)" or "")
end

-- ADDON_RESTRICTION_STATE_CHANGED: the restriction check reads false while that event dispatches,
-- so catch up on the next frame, once.
function Display:ScheduleMouseUpdate()
    if catchUpPending then return end
    catchUpPending = true
    C_Timer.After(0, function()
        catchUpPending = false
        Display:ApplyMouse()
    end)
end

function Display:Init(database)
    db = database
    frame = CreateFrame("Frame", "ForeverFlightTimerFrame", UIParent, "BackdropTemplate")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouse(false)
    frame:Hide()

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetMinMaxValues(0, 1)
    barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()

    -- Texts live on their own layer above the bar, so hiding the bar keeps them visible.
    textLayer = CreateFrame("Frame", nil, frame)
    textLayer:SetAllPoints()
    textLayer:SetFrameLevel(bar:GetFrameLevel() + 2)
    nameText = textLayer:CreateFontString(nil, "OVERLAY")
    timeText = textLayer:CreateFontString(nil, "OVERLAY")
    arrivalText = textLayer:CreateFontString(nil, "OVERLAY")
    for _, fs in ipairs({ nameText, timeText, arrivalText }) do fs:SetWordWrap(false) end
    nameText:SetJustifyH("LEFT")
    timeText:SetJustifyH("RIGHT")
    arrivalText:SetJustifyH("CENTER")
    -- Named regions, like XML parentKeys: for skins and for the smoke test.
    frame.bar, frame.nameText, frame.timeText, frame.arrivalText = bar, nameText, timeText, arrivalText

    highlight = textLayer:CreateTexture(nil, "OVERLAY")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.2, 0.6, 1, 0.25)
    highlight:Hide()

    frame:SetScript("OnDragStart", function(self)
        if unlocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false) -- the (shared) profile owns the position, not the client
        SavePosition()
    end)
    frame:SetScript("OnEnter", function(self)
        if not unlocked then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Forever Flight Timer")
        GameTooltip:AddLine(MenuAvailable() and "Drag to move. Right-click for the menu. Type /ftimer lock to lock it."
                            or "Drag to move. Type /ftimer lock to lock it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and MenuAvailable() then
            MenuUtil.CreateContextMenu(self, contextMenu)
        end
    end)

    self:ApplySettings()
end

function Display:ApplySettings()
    if not frame then return end
    local p = Profile()
    for _, fs in ipairs({ nameText, timeText, arrivalText }) do ApplyFont(fs, p.font) end
    local c = p.colors
    nameText:SetTextColor(c.name.r, c.name.g, c.name.b, c.name.a)
    timeText:SetTextColor(c.time.r, c.time.g, c.time.b, c.time.a)
    arrivalText:SetTextColor(c.arrival.r, c.arrival.g, c.arrival.b, c.arrival.a)
    bar:SetStatusBarTexture(Fetch("statusbar", p.barTexture) or "Interface\\TargetingFrame\\UI-StatusBar")
    barBg:SetColorTexture(c.barBg.r, c.barBg.g, c.barBg.b, c.barBg.a)
    bar:SetAlpha(p.showBar and 1 or 0)
    ApplyBackdrop(p)
    frame:SetScale(p.scale)
    frame:SetAlpha(p.alpha)
    frame:SetFrameStrata(preview and PREVIEW_STRATA or p.strata)
    Layout()
    self:ApplyPosition()
    self:UpdateLock() -- re-renders
end

function Display:ApplyPosition()
    if not frame then return end
    local p = Profile()
    local s = frame:GetScale()
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", p.pos.x / s, p.pos.y / s)
end

function Display:UpdateLock()
    if not frame then return end
    unlocked = not Profile().locked
    self:ApplyMouse()
    if unlocked then
        highlight:Show()
    else
        highlight:Hide()
        if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
    end
    self:Render(lastView, lastArrival)
end

function Display:SetSampleArrival(fn)
    sampleArrival = fn
end

function Display:SetPreview(on)
    preview = on and true or false
    if not frame then return end
    frame:SetFrameStrata(preview and PREVIEW_STRATA or Profile().strata)
    self:Render(lastView, lastArrival)
end

function Display:Render(view, arrival)
    lastView, lastArrival = view or lastView, arrival
    if not frame then return end
    local v = lastView
    if not IsVisible(v) then
        frame:Hide()
        return
    end
    local p = Profile()
    if v.mode == "hidden" then -- preview or drag mode with no real flight: sample data
        v = SAMPLE
        arrival = sampleArrival and sampleArrival(SAMPLE.remaining) or SAMPLE_ARRIVAL
    end

    local name
    if not v.toName then
        name = "Flight"
    elseif p.showDest then
        local to = Display.ShortName(v.toName, p.fullNames)
        if p.showOrigin and v.fromName then
            name = Display.ShortName(v.fromName, p.fullNames) .. " -> " .. to
        else
            name = to
        end
    end
    nameText:SetText(name or "")

    local t
    if v.mode == "countdown" then
        t = Fmt(p.countUp and v.elapsed or v.remaining)
    elseif v.mode == "overtime" then
        t = p.countUp and Fmt(v.elapsed) or ("+" .. Fmt(v.over)) -- counting up just carries on
    elseif v.mode == "frozen" then
        t = Fmt(v.duration)
    else
        t = Fmt(v.elapsed)
        if v.mode == "learning" then t = t .. " (learning)" end
    end
    if not p.showTime then t = nil end
    local withArrival = p.showArrival and v.mode == "countdown" and arrival ~= nil
    local below = withArrival and p.arrivalPos == "below"
    if withArrival and not below then
        t = t and (t .. " (" .. arrival .. ")") or arrival -- on its own when the time is hidden
    end
    timeText:SetText(t or "")
    arrivalText:SetText(below and ("lands at " .. arrival) or "")

    local c, value = p.colors.countdown, 1
    if v.mode == "countdown" then
        local frac = (v.expected and v.expected > 0) and v.remaining / v.expected or 0
        value = p.barFill == "fill" and (1 - frac) or frac
    elseif v.mode == "overtime" then
        c = p.colors.overtime
    elseif v.mode == "learning" or v.mode == "untracked" then
        c = p.colors.learning
    end
    bar:SetValue(value)
    bar:SetStatusBarColor(c.r, c.g, c.b, c.a)
    frame:Show()
end
