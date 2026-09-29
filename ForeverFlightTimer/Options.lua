-- Options panel: Esc > Options > AddOns > Forever Flight Timer (+ Profiles sub-page).
local _, ns = ...

local Options = {}
ns.Options = Options

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

local APP, APP_PROFILES = "ForeverFlightTimer", "ForeverFlightTimer_Profiles"
local TITLE = "Forever Flight Timer"

local STRATA = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" }
local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }
local TIME_STYLES = { auto = "Auto (4:05, 1:02:45)", hours = "Always hours (0:04:05)",
                      padded = "Zero-padded (00:04:05)", words = "Words (4m 05s)" }
local TIME_STYLE_ORDER = { "auto", "hours", "padded", "words" }
local OUTLINES = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" }
local OUTLINE_ORDER = { "NONE", "OUTLINE", "THICKOUTLINE" }
local FILL = { drain = "Drain (empties as you fly)", fill = "Fill (fills as you fly)" }
local FILL_ORDER = { "drain", "fill" }
local ARRIVAL_POS = { after = "After the time", below = "Below the bar" }
local ARRIVAL_POS_ORDER = { "after", "below" }
local CLOCK_SOURCE = { game = "Game clock setting", ["local"] = "Local time", realm = "Realm time" }
local CLOCK_SOURCE_ORDER = { "game", "local", "realm" }
local CLOCK_FORMAT = { game = "Game clock setting", ["24"] = "24-hour", ["12"] = "12-hour (AM/PM)" }
local CLOCK_FORMAT_ORDER = { "game", "24", "12" }

local db, actions, getStatus

local function P() return db.profile end

local function GetPath(path)
    local t = P()
    for i = 1, #path do t = t[path[i]] end
    return t
end

local function SetPath(path, value)
    local t = P()
    for i = 1, #path - 1 do t = t[path[i]] end
    t[path[#path]] = value
end

local function Bind(opt, path)
    opt.get = function() return GetPath(path) end
    opt.set = function(_, value)
        SetPath(path, value)
        actions.settingsChanged()
    end
    return opt
end

local function Color(order, name, path)
    return {
        type = "color", order = order, name = name, hasAlpha = true,
        get = function()
            local c = GetPath(path)
            return c.r, c.g, c.b, c.a
        end,
        set = function(_, r, g, b, a)
            local c = GetPath(path)
            c.r, c.g, c.b, c.a = r, g, b, a
            actions.settingsChanged()
        end,
    }
end

local MEDIA_WIDGETS = { font = "LSM30_Font", background = "LSM30_Background", border = "LSM30_Border",
                        statusbar = "LSM30_Statusbar" }

-- Media picker: SharedMedia preview widget when it registered, plain dropdown otherwise.
local function MediaSelect(order, name, kind, path)
    local opt = Bind({ type = "select", order = order, name = name }, path)
    local widget = MEDIA_WIDGETS[kind]
    if AceGUI:GetWidgetVersion(widget) and AceGUIWidgetLSMlists and AceGUIWidgetLSMlists[kind] then
        opt.dialogControl = widget
        opt.values = AceGUIWidgetLSMlists[kind]
    else
        opt.values = function()
            local list = {}
            for _, n in ipairs(LSM:List(kind)) do list[n] = n end
            return list
        end
    end
    return opt
end

local function Toggle(order, name, path, extra)
    local opt = Bind({ type = "toggle", order = order, name = name }, path)
    for k, v in pairs(extra or {}) do opt[k] = v end
    return opt
end

local function Select(order, name, path, values, sorting, extra)
    local opt = Bind({ type = "select", order = order, name = name, values = values, sorting = sorting }, path)
    for k, v in pairs(extra or {}) do opt[k] = v end
    return opt
end

local function Range(order, name, path, min, max, step, extra)
    local opt = Bind({ type = "range", order = order, name = name, min = min, max = max, step = step }, path)
    for k, v in pairs(extra or {}) do opt[k] = v end
    return opt
end

local function BuildOptions()
    local halfWidth = math.floor((UIParent:GetWidth() or 1920) / 2)
    local height = math.floor(UIParent:GetHeight() or 1080)
    return {
        type = "group", name = TITLE, childGroups = "tab",
        args = {
            display = {
                type = "group", order = 1, name = "Display",
                args = {
                    showTimer = Toggle(1, "Show on-screen timer", { "showTimer" },
                        { width = "full", desc = "Turn this off to only get the chat message when you land." }),
                    locked = {
                        type = "toggle", order = 2, name = "Lock position",
                        desc = "Unlock to drag the timer with the left mouse button.",
                        get = function() return P().locked end,
                        set = function(_, value) actions.setLocked(value, true) end,
                    },
                    rightClickMenu = Toggle(2.5, "Right-click menu", { "rightClickMenu" },
                        { desc = "Right-click the timer for a menu: Options, Lock position and Reset position. Other clicks still go through to the game world. Turn this off to make the locked timer completely click-through." }),
                    resetPos = { type = "execute", order = 3, name = "Reset position",
                        func = function() actions.resetPosition() end },
                    resetDefaults = {
                        type = "execute", order = 3.5, name = "Reset defaults",
                        desc = "Puts every setting on every tab back to its default, including the position. Learned flight times are kept. Same as /ftimer defaults confirm.",
                        confirm = true,
                        confirmText = "Reset all Forever Flight Timer settings in the current profile to their defaults? Learned flight times are kept. This cannot be undone.",
                        func = function() actions.resetDefaults("button") end,
                    },
                    posX = Range(4, "Position X", { "pos", "x" }, -4000, 4000, 1,
                        { softMin = -halfWidth, softMax = halfWidth, bigStep = 5,
                          desc = "Horizontal offset from the top-center of the screen." }),
                    posY = Range(5, "Position Y", { "pos", "y" }, -4000, 0, 1,
                        { softMin = -height, softMax = 0, bigStep = 5, desc = "Vertical offset from the top of the screen." }),
                    width = Range(6, "Bar width", { "width" }, 80, 600, 1),
                    height = Range(7, "Bar height", { "height" }, 8, 60, 1),
                    scale = Range(8, "Scale", { "scale" }, 0.5, 3, 0.05),
                    alpha = Range(9, "Opacity", { "alpha" }, 0.1, 1, 0.05, { isPercent = true }),
                    strata = Select(10, "Frame strata", { "strata" }, STRATA, STRATA_ORDER),
                    freezeSeconds = Range(11, "Keep final time on screen after landing (s)", { "freezeSeconds" },
                        0, 30, 1, { desc = "0 turns it off." }),
                },
            },
            appearance = {
                type = "group", order = 2, name = "Appearance",
                args = {
                    barGroup = {
                        type = "group", inline = true, order = 1, name = "Bar",
                        args = {
                            showBar = Toggle(1, "Show bar", { "showBar" }),
                            barTexture = MediaSelect(2, "Bar texture", "statusbar", { "barTexture" }),
                            barFill = Select(3, "Bar fill", { "barFill" }, FILL, FILL_ORDER),
                            countdown = Color(4, "Counting down", { "colors", "countdown" }),
                            learning = Color(5, "Learning / unknown route", { "colors", "learning" }),
                            overtime = Color(6, "Overtime", { "colors", "overtime" }),
                            barBg = Color(7, "Bar background", { "colors", "barBg" }),
                        },
                    },
                    textGroup = {
                        type = "group", inline = true, order = 2, name = "Text",
                        args = {
                            showDest = Toggle(1, "Show destination", { "showDest" }),
                            showOrigin = Toggle(2, "Show origin too", { "showOrigin" }),
                            fullNames = Toggle(3, "Full names (with zone)", { "fullNames" }),
                            showTime = Toggle(4, "Show time", { "showTime" }),
                            countUp = Toggle(5, "Count up on known routes", { "countUp" },
                                { desc = "Show the time flown instead of the time left. It keeps counting up if the flight runs over." }),
                            timeStyle = Select(6, "Time format", { "timeStyle" }, TIME_STYLES, TIME_STYLE_ORDER),
                            showTenths = Toggle(7, "Show tenths of a second", { "showTenths" }),
                            showArrival = Toggle(8, "Show arrival clock", { "showArrival" }),
                            arrivalPos = Select(9, "Arrival clock position", { "arrivalPos" }, ARRIVAL_POS, ARRIVAL_POS_ORDER,
                                { desc = "With \"Show time\" off, \"After the time\" shows the arrival clock on its own." }),
                            clockSource = Select(10, "Clock", { "clockSource" }, CLOCK_SOURCE, CLOCK_SOURCE_ORDER),
                            clockFormat = Select(11, "Clock format", { "clockFormat" }, CLOCK_FORMAT, CLOCK_FORMAT_ORDER),
                        },
                    },
                    fontGroup = {
                        type = "group", inline = true, order = 3, name = "Font",
                        args = {
                            face = MediaSelect(1, "Font", "font", { "font", "face" }),
                            size = Range(2, "Size", { "font", "size" }, 6, 40, 1),
                            outline = Select(3, "Outline", { "font", "outline" }, OUTLINES, OUTLINE_ORDER),
                            mono = Toggle(4, "Monochrome", { "font", "mono" }),
                            shadow = Toggle(5, "Shadow", { "font", "shadow" }),
                        },
                    },
                    textColors = {
                        type = "group", inline = true, order = 4, name = "Text colours",
                        args = {
                            name = Color(1, "Name", { "colors", "name" }),
                            time = Color(2, "Time", { "colors", "time" }),
                            arrival = Color(3, "Arrival clock", { "colors", "arrival" }),
                        },
                    },
                    frameGroup = {
                        type = "group", inline = true, order = 5, name = "Frame background & border",
                        args = {
                            bgShow = Toggle(1, "Show background", { "bg", "show" }),
                            bgTexture = MediaSelect(2, "Background texture", "background", { "bg", "texture" }),
                            bgColor = Color(3, "Background colour", { "bg", "color" }),
                            borderShow = Toggle(4, "Show border", { "border", "show" }),
                            borderTexture = MediaSelect(5, "Border texture", "border", { "border", "texture" }),
                            borderSize = Range(6, "Border thickness", { "border", "size" }, 1, 32, 1),
                            borderColor = Color(7, "Border colour", { "border", "color" }),
                            padding = Range(8, "Padding", { "padding" }, 0, 30, 1),
                        },
                    },
                },
            },
            behaviour = {
                type = "group", order = 3, name = "Behaviour",
                args = {
                    tooltips = Toggle(1, "Show flight times in flight-map tooltips", { "tooltips" }, { width = "full" }),
                    chat = Toggle(2, "Chat message when you land", { "chat" }, { width = "full" }),
                    routes = {
                        type = "group", inline = true, order = 3, name = "Learned routes",
                        args = {
                            count = {
                                type = "description", order = 1,
                                name = function()
                                    return ("%d routes learned. Type /ftimer routes to list them."):format(actions.routeCount())
                                end,
                            },
                            forget = {
                                type = "execute", order = 2, name = "Forget all learned times",
                                confirm = true, confirmText = "Forget every learned flight time? This cannot be undone.",
                                func = function() actions.forgetRoutes() end,
                            },
                        },
                    },
                },
            },
        },
    }
end

-- Live status line in the page's title row, outside AceConfig's widget tree (no rebuilds).
local function CreateStatusLine(page)
    local holder = CreateFrame("Frame", nil, page)
    holder:SetPoint("TOPLEFT", page, "TOPLEFT", 250, -15)
    holder:SetPoint("TOPRIGHT", page, "TOPRIGHT", -16, -15)
    holder:SetHeight(20)
    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetAllPoints()
    text:SetJustifyH("RIGHT")
    text:SetWordWrap(false)
    local acc = 1
    holder:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.5 then return end
        acc = 0
        text:SetText(getStatus())
    end)
    return text
end

function Options:Init(database, statusProvider, actionTable)
    db, getStatus, actions = database, statusProvider, actionTable
    AceConfig:RegisterOptionsTable(APP, BuildOptions)
    self.frame, self.categoryID = AceConfigDialog:AddToBlizOptions(APP, TITLE)
    -- The Settings window's Defaults → All Settings calls every page's OnDefault, which Ace3's page
    -- turns into the "default" callback. The game has already confirmed.
    self.frame.obj:SetCallback("default", function() actions.resetDefaults("game") end)
    AceConfig:RegisterOptionsTable(APP_PROFILES, AceDBOptions:GetOptionsTable(db))
    self.profilesFrame = AceConfigDialog:AddToBlizOptions(APP_PROFILES, "Profiles", TITLE)
    local function UpdatePreview()
        actions.setPreview(self.frame:IsVisible() or self.profilesFrame:IsVisible())
    end
    for _, page in ipairs({ self.frame, self.profilesFrame }) do
        page:HookScript("OnShow", UpdatePreview) -- HookScript: the pages' own scripts fill them
        page:HookScript("OnHide", UpdatePreview)
    end
    self.statusText = CreateStatusLine(self.frame)
end

function Options:Open()
    if InCombatLockdown() then
        print("|cff33ff99Forever Flight Timer|r: options can't be opened during combat.")
        return
    end
    Settings.OpenToCategory(self.categoryID)
end

-- Rebuilds the visible page. Only call after user actions taken outside the panel.
function Options:Refresh()
    AceConfigRegistry:NotifyChange(APP)
end
