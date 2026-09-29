-- Options panel: Esc > Options > AddOns > Forever Instance Timer (+ Profiles sub-page).
local _, ns = ...

local Options = {}
ns.Options = Options

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

local APP, APP_PROFILES = "ForeverInstanceTimer", "ForeverInstanceTimer_Profiles"
local TITLE = "Forever Instance Timer"

local STRATA = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" }
local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }
local NAME_POS = { ABOVE = "Above the time", BELOW = "Below the time", LEFT = "Left of the time", RIGHT = "Right of the time" }
local NAME_POS_ORDER = { "ABOVE", "BELOW", "LEFT", "RIGHT" }
local ALIGN = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
local ALIGN_ORDER = { "LEFT", "CENTER", "RIGHT" }
local TIME_STYLES = {
    auto = "Auto (4:05, 1:02:45)",
    hours = "Always hours (0:04:05)",
    padded = "Zero-padded (00:04:05)",
    words = "Words (4m 05s)",
}
local TIME_STYLE_ORDER = { "auto", "hours", "padded", "words" }
local OUTLINES = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" }
local OUTLINE_ORDER = { "NONE", "OUTLINE", "THICKOUTLINE" }
local AWAY = { count = "Keep counting", pause = "Pause" }
local AWAY_ORDER = { "count", "pause" }
local GIVE_UP = { ghost = "Only while a ghost", grace = "Grace period", never = "Wait indefinitely" }
local GIVE_UP_ORDER = { "ghost", "grace", "never" }
local OFFLINE = { count = "Keep counting", pause = "Pause while offline", reset = "Reset" }
local OFFLINE_ORDER = { "count", "pause", "reset" }

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

-- Adds get/set bound to a profile path. kind: "display" or "rules".
local function Bind(opt, path, kind)
    opt.get = function() return GetPath(path) end
    opt.set = function(_, value)
        SetPath(path, value)
        actions.settingsChanged(kind or "display")
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
            actions.settingsChanged("display")
        end,
    }
end

local MEDIA_WIDGETS = { font = "LSM30_Font", background = "LSM30_Background", border = "LSM30_Border" }

-- Font/texture picker: SharedMedia preview widget when it registered, plain dropdown otherwise.
local function MediaSelect(order, name, kind, path)
    local opt = Bind({ type = "select", order = order, name = name }, path, "display")
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

local function FontGroup(order, name, key)
    return {
        type = "group", inline = true, order = order, name = name,
        args = {
            face = MediaSelect(1, "Font", "font", { key, "face" }),
            size = Bind({ type = "range", order = 2, name = "Size", min = 6, max = 72, step = 1 }, { key, "size" }),
            outline = Bind({ type = "select", order = 3, name = "Outline", values = OUTLINES, sorting = OUTLINE_ORDER }, { key, "outline" }),
            mono = Bind({ type = "toggle", order = 4, name = "Monochrome" }, { key, "mono" }),
            shadow = Bind({ type = "toggle", order = 5, name = "Shadow" }, { key, "shadow" }),
        },
    }
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
                    showTimer = Bind({ type = "toggle", order = 1, width = "full", name = "Show on-screen timer",
                        desc = "Turn this off to only get the chat message when a run ends." }, { "showTimer" }),
                    locked = {
                        type = "toggle", order = 2, name = "Lock position",
                        desc = "Unlock to drag the timer with the left mouse button.",
                        get = function() return P().locked end,
                        set = function(_, value) actions.setLocked(value, true) end,
                    },
                    rightClickMenu = Bind({ type = "toggle", order = 2.5, name = "Right-click menu",
                        desc = "Right-click the timer for a menu: Options, Lock position, Reset position and Reset current run. Other clicks still go through to the game world. Turn this off to make the locked timer completely click-through." },
                        { "rightClickMenu" }),
                    resetPos = { type = "execute", order = 3, name = "Reset position",
                        func = function() actions.resetPosition() end },
                    resetDefaults = {
                        type = "execute", order = 3.5, name = "Reset defaults",
                        desc = "Puts every setting on every tab back to its default, including the position and the run rules. A run in progress follows the default rules from then on, so a corpse run can end. Same as /itimer defaults confirm.",
                        confirm = true,
                        confirmText = "Reset all Forever Instance Timer settings in the current profile, including the run rules, to their defaults? A run in progress follows the default rules from then on, so a corpse run can end. This cannot be undone.",
                        func = function() actions.resetDefaults("button") end,
                    },
                    posX = Bind({ type = "range", order = 4, name = "Position X",
                        desc = "Horizontal offset from the top-center of the screen.",
                        min = -4000, max = 4000, softMin = -halfWidth, softMax = halfWidth, step = 1, bigStep = 5 },
                        { "pos", "x" }),
                    posY = Bind({ type = "range", order = 5, name = "Position Y",
                        desc = "Vertical offset from the top of the screen.",
                        min = -4000, max = 0, softMin = -height, softMax = 0, step = 1, bigStep = 5 },
                        { "pos", "y" }),
                    scale = Bind({ type = "range", order = 6, name = "Scale", min = 0.5, max = 3, step = 0.05 }, { "scale" }),
                    alpha = Bind({ type = "range", order = 7, name = "Opacity", min = 0.1, max = 1, step = 0.05,
                        isPercent = true }, { "alpha" }),
                    strata = Bind({ type = "select", order = 8, name = "Frame strata", values = STRATA,
                        sorting = STRATA_ORDER }, { "strata" }),
                    hideInCombat = Bind({ type = "toggle", order = 9, name = "Hide in combat" }, { "hideInCombat" }),
                    showWhileAway = Bind({ type = "toggle", order = 10, name = "Show while away (corpse run)" },
                        { "showWhileAway" }),
                },
            },
            appearance = {
                type = "group", order = 2, name = "Appearance",
                args = {
                    layout = {
                        type = "group", inline = true, order = 1, name = "Text & layout",
                        args = {
                            showName = Bind({ type = "toggle", order = 1, name = "Show instance name" }, { "showName" }),
                            namePos = Bind({ type = "select", order = 2, name = "Name position", values = NAME_POS,
                                sorting = NAME_POS_ORDER }, { "namePos" }),
                            align = Bind({ type = "select", order = 3, name = "Alignment",
                                desc = "Used when the name is above or below the time.",
                                values = ALIGN, sorting = ALIGN_ORDER }, { "align" }),
                            spacing = Bind({ type = "range", order = 4, name = "Spacing", min = 0, max = 20, step = 1 },
                                { "spacing" }),
                            timeStyle = Bind({ type = "select", order = 5, name = "Time format", values = TIME_STYLES,
                                sorting = TIME_STYLE_ORDER }, { "timeStyle" }),
                            showTenths = Bind({ type = "toggle", order = 6, name = "Show tenths of a second" },
                                { "showTenths" }),
                        },
                    },
                    timeFont = FontGroup(2, "Time font", "timeFont"),
                    nameFont = FontGroup(3, "Name font", "nameFont"),
                    colors = {
                        type = "group", inline = true, order = 4, name = "Colors",
                        args = {
                            name = Color(1, "Name", { "colors", "name" }),
                            running = Color(2, "Time while running", { "colors", "running" }),
                            away = Color(3, "Time while away (corpse run)", { "colors", "away" }),
                            final = Color(4, "Final time", { "colors", "final" }),
                        },
                    },
                    box = {
                        type = "group", inline = true, order = 5, name = "Background & border",
                        args = {
                            bgShow = Bind({ type = "toggle", order = 1, name = "Show background" }, { "bg", "show" }),
                            bgTexture = MediaSelect(2, "Background texture", "background", { "bg", "texture" }),
                            bgColor = Color(3, "Background color", { "bg", "color" }),
                            borderShow = Bind({ type = "toggle", order = 4, name = "Show border" }, { "border", "show" }),
                            borderTexture = MediaSelect(5, "Border texture", "border", { "border", "texture" }),
                            borderSize = Bind({ type = "range", order = 6, name = "Border thickness", min = 1, max = 32,
                                step = 1 }, { "border", "size" }),
                            borderColor = Color(7, "Border color", { "border", "color" }),
                            padding = Bind({ type = "range", order = 8, name = "Padding", min = 0, max = 30, step = 1 },
                                { "padding" }),
                        },
                    },
                },
            },
            rules = {
                type = "group", order = 3, name = "Rules",
                args = {
                    types = {
                        type = "group", inline = true, order = 1, name = "Start the timer in",
                        args = {
                            party = Bind({ type = "toggle", order = 1, name = "Dungeons" }, { "types", "party" }, "rules"),
                            raid = Bind({ type = "toggle", order = 2, name = "Raids" }, { "types", "raid" }, "rules"),
                            pvp = Bind({ type = "toggle", order = 3, name = "Battlegrounds" }, { "types", "pvp" }, "rules"),
                        },
                    },
                    death = {
                        type = "group", inline = true, order = 2, name = "Deaths and corpse runs",
                        args = {
                            awayMode = Bind({ type = "select", order = 1, name = "While away after dying",
                                values = AWAY, sorting = AWAY_ORDER }, { "awayMode" }, "rules"),
                            giveUp = Bind({ type = "select", order = 2, name = "Stop waiting after a death",
                                desc = "What ends a run when you died and did not come back in.",
                                values = GIVE_UP, sorting = GIVE_UP_ORDER }, { "giveUp" }, "rules"),
                            graceMinutes = Bind({ type = "range", order = 3, name = "Grace period (minutes)",
                                min = 1, max = 120, step = 1,
                                disabled = function() return P().giveUp ~= "grace" end }, { "graceMinutes" }, "rules"),
                            offline = Bind({ type = "select", order = 4, name = "Logout / disconnect",
                                values = OFFLINE, sorting = OFFLINE_ORDER }, { "offline" }, "rules"),
                        },
                    },
                    leaving = {
                        type = "group", inline = true, order = 3, name = "When a run ends",
                        args = {
                            chat = Bind({ type = "toggle", order = 1, name = "Print final time to chat" }, { "chat" }),
                            freezeSeconds = Bind({ type = "range", order = 2, name = "Keep final time on screen (s)",
                                desc = "0 turns it off.", min = 0, max = 60, step = 1 }, { "freezeSeconds" }),
                        },
                    },
                    resetRun = { type = "execute", order = 4, name = "Reset current run",
                        desc = "Same as /itimer reset.", func = function() actions.resetRun() end },
                },
            },
        },
    }
end

-- Live status line, right-aligned in the page's title row. It lives outside AceConfig's
-- widget tree, so it can update every half second without rebuilding the page.
local function CreateStatusLine(page)
    local holder = CreateFrame("Frame", nil, page)
    -- From just past the title to the right edge, so it uses all the free width.
    holder:SetPoint("TOPLEFT", page, "TOPLEFT", 260, -15)
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

    -- Preview while either page is visible. HookScript, because the pages' own
    -- OnShow/OnHide scripts are what fill and clear them.
    local function UpdatePreview()
        actions.setPreview(self.frame:IsVisible() or self.profilesFrame:IsVisible())
    end
    for _, page in ipairs({ self.frame, self.profilesFrame }) do
        page:HookScript("OnShow", UpdatePreview)
        page:HookScript("OnHide", UpdatePreview)
    end
    self.statusText = CreateStatusLine(self.frame)
end

function Options:Open()
    if InCombatLockdown() then
        print("|cff33ff99Forever Instance Timer|r: options can't be opened during combat.")
        return
    end
    Settings.OpenToCategory(self.categoryID)
end

-- Rebuilds the visible page. Only call after user actions made outside the panel.
function Options:Refresh()
    AceConfigRegistry:NotifyChange(APP)
end
