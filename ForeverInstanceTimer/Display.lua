-- The on-screen timer frame. Renders the `view` Core hands it; owns no timing logic.
local _, ns = ...

local Display = {}
ns.Display = Display

local LSM = LibStub("LibSharedMedia-3.0")
local TimeFormat = ns.TimeFormat

local SAMPLE_NAME, SAMPLE_SECONDS = "The Deadmines", 754 -- shown as 12:34 in preview/drag mode
local PREVIEW_STRATA = "FULLSCREEN_DIALOG"                -- above the Settings window

local db, frame, nameText, timeText, measureName, measureTime, highlight
local lastView = { mode = "hidden" }
local preview, unlocked, inCombat = false, false, false
local widestDigit = "0"
local curTime, curName, curTemplate -- what is currently laid out

local function Profile() return db.profile end

-- A saved media name that isn't registered (yet) falls back to the default for drawing
-- only; the saved name is never overwritten.
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

local function FindWidestDigit()
    local best, bestWidth = "0", -1
    for d = 0, 9 do
        measureTime:SetText(tostring(d))
        local w = measureTime:GetStringWidth()
        if w > bestWidth then best, bestWidth = tostring(d), w end
    end
    return best
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

-- Sizes and anchors both texts. The time is measured as a template with every digit
-- replaced by the widest digit, so the box doesn't jitter while the time ticks.
local function Layout()
    local p = Profile()
    local pad, gap = p.padding, p.spacing
    measureTime:SetText(curTemplate or "")
    local tw = math.ceil(measureTime:GetStringWidth())
    local th = math.ceil(measureTime:GetStringHeight())
    local showName = curName ~= nil and curName ~= ""
    local nw, nh = 0, 0
    if showName then
        measureName:SetText(curName)
        nw = math.ceil(measureName:GetStringWidth())
        nh = math.ceil(measureName:GetStringHeight())
    end

    nameText:ClearAllPoints()
    timeText:ClearAllPoints()
    local w, h
    if not showName then
        w, h = tw, th
        timeText:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
        timeText:SetSize(w, h)
    elseif p.namePos == "LEFT" or p.namePos == "RIGHT" then
        w, h = nw + gap + tw, math.max(nh, th)
        local first, firstW, second, secondW = nameText, nw, timeText, tw
        if p.namePos == "RIGHT" then first, firstW, second, secondW = timeText, tw, nameText, nw end
        first:SetPoint("LEFT", frame, "LEFT", pad, 0)
        first:SetSize(firstW, h)
        second:SetPoint("LEFT", first, "RIGHT", gap, 0)
        second:SetSize(secondW, h)
    else -- ABOVE / BELOW
        w, h = math.max(nw, tw), nh + gap + th
        local top, topH, bottom, bottomH = nameText, nh, timeText, th
        if p.namePos == "BELOW" then top, topH, bottom, bottomH = timeText, th, nameText, nh end
        top:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
        top:SetSize(w, topH)
        bottom:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -gap)
        bottom:SetSize(w, bottomH)
    end
    frame:SetSize(w + 2 * pad, h + 2 * pad)
end

local function IsVisible(view)
    if preview or unlocked then return true end
    if view.mode == "hidden" then return false end
    local p = Profile()
    if not p.showTimer then return false end
    if p.hideInCombat and inCombat then return false end
    if view.mode == "away" and not p.showWhileAway then return false end
    return true
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
    frame = CreateFrame("Frame", "ForeverInstanceTimerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(120, 50)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouse(false)
    frame:Hide()

    nameText = frame:CreateFontString(nil, "OVERLAY")
    timeText = frame:CreateFontString(nil, "OVERLAY")
    measureName = frame:CreateFontString(nil, "BACKGROUND")
    measureTime = frame:CreateFontString(nil, "BACKGROUND")
    for _, fs in ipairs({ nameText, timeText, measureName, measureTime }) do
        fs:SetWordWrap(false)
        fs:SetJustifyV("MIDDLE")
    end
    measureName:SetAlpha(0)
    measureTime:SetAlpha(0)

    highlight = frame:CreateTexture(nil, "OVERLAY")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.2, 0.6, 1, 0.25)
    highlight:Hide()

    frame:SetScript("OnDragStart", function(self)
        if unlocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- StartMoving marks the frame user-placed, which makes the client keep its own
        -- per-character copy of the position; the (shared) profile owns it instead.
        self:SetUserPlaced(false)
        SavePosition()
    end)
    frame:SetScript("OnEnter", function(self)
        if not unlocked then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Forever Instance Timer")
        GameTooltip:AddLine(MenuAvailable() and "Drag to move. Right-click for the menu. Type /itimer lock to lock it."
                            or "Drag to move. Type /itimer lock to lock it.", 1, 1, 1, true)
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
    ApplyFont(nameText, p.nameFont)
    ApplyFont(measureName, p.nameFont)
    ApplyFont(timeText, p.timeFont)
    ApplyFont(measureTime, p.timeFont)
    local c = p.colors.name
    nameText:SetTextColor(c.r, c.g, c.b, c.a)
    nameText:SetJustifyH(p.align)
    timeText:SetJustifyH(p.align)
    widestDigit = FindWidestDigit()
    ApplyBackdrop(p)
    frame:SetScale(p.scale)
    frame:SetAlpha(p.alpha)
    frame:SetFrameStrata(preview and PREVIEW_STRATA or p.strata)
    self:ApplyPosition()
    curTime, curName, curTemplate = nil, nil, nil -- force a fresh layout
    self:UpdateLock()                              -- re-renders
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
    self:Render(lastView)
end

function Display:SetPreview(on)
    preview = on and true or false
    if not frame then return end
    frame:SetFrameStrata(preview and PREVIEW_STRATA or Profile().strata)
    self:Render(lastView)
end

function Display:SetInCombat(on)
    inCombat = on and true or false
    self:Render(lastView)
end

function Display:Render(view)
    lastView = view or lastView
    if not frame then return end
    if not IsVisible(lastView) then
        frame:Hide()
        return
    end
    local p = Profile()
    local mode, name, seconds = lastView.mode, lastView.name, lastView.seconds
    if mode == "hidden" then -- preview or drag mode with nothing real to show
        mode, name, seconds = "sample", SAMPLE_NAME, SAMPLE_SECONDS
    end

    local text = TimeFormat.Format(seconds, p.timeStyle, p.showTenths)
    local shownName = p.showName and (name or "") or ""
    local template = (text:gsub("%d", widestDigit))
    if text ~= curTime then
        curTime = text
        timeText:SetText(text)
    end
    if shownName ~= curName or template ~= curTemplate then
        curName, curTemplate = shownName, template
        nameText:SetText(shownName)
        Layout()
    end

    local c = p.colors.running
    if mode == "away" then
        c = p.colors.away
    elseif mode == "frozen" then
        c = p.colors.final
    end
    timeText:SetTextColor(c.r, c.g, c.b, c.a)
    frame:Show()
end
