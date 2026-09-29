-- Headless smoke test: loads the whole addon (libraries included) in TOC order against stubs
-- of the WoW API, validates the options tables, drives every option, and replays a session.
-- Usage (addon root):  luajit tests/smoke.lua
-- If a LIBRARY fails to load because a WoW global is missing, add a stub in STUBS below.
-- Never edit library code.
local ADDON = "ForeverInstanceTimer"
-- FIT_SMOKE_BREAK_SETTINGS=1 simulates a client whose Settings API breaks the options panel:
-- the timer itself must keep working.
local BREAK_SETTINGS = os.getenv("FIT_SMOKE_BREAK_SETTINGS") ~= nil
local rawprint = print -- the stubbed print below captures the addon's chat output
local failures = {}
local function fail(msg) failures[#failures + 1] = msg; rawprint("FAIL " .. msg) end
local function check(cond, msg) if not cond then fail(msg) end end

-------------------------------------------------------------------------------- clock & game
local now = 1000.0
local game = { inInstance = false, name = nil, itype = "none", id = nil, dead = false, ghost = false,
               secret = false, throw = false, restrictedTypes = {} }
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local chat, openedCategory = {}, nil

-------------------------------------------------------------------------------- frames
-- Stub state lives in "_"-prefixed fields, read with rawget. Real frames keep their state in
-- C, so libraries freely store their own Lua fields on frames (e.g. Blizzard's legacy options
-- `frame.parent = categoryID`); prefixed names keep the two from colliding.
local Frame, eventFrames, allFrames = {}, {}, {}
local function noopMethod() end
-- Real widget-API methods our own files call that the stub treats as no-ops. Any other
-- unstubbed method called from our files is reported: it is a typo or a missing stub.
local KNOWN_OWN_METHODS = {}
for _, m in ipairs({ "SetClampedToScreen", "SetMovable", "RegisterForDrag",
                     "SetJustifyV", "SetJustifyH", "SetAllPoints", "SetColorTexture", "SetShadowOffset",
                     "SetShadowColor", "SetTextColor", "SetBackdropColor", "SetBackdropBorderColor",
                     "ClearAllPoints", "SetPoint", "StopMovingOrSizing", "SetOwner", "AddLine" }) do
    KNOWN_OWN_METHODS[m] = true
end
local OWN_SOURCES = {} -- filled below; shared with the global-read guard
local unknownMethods = {}
local frameMeta = { __index = function(_, k)
    local v = Frame[k]
    if v ~= nil then return v end
    -- Any other widget API method (CamelCase, like the real API) is a no-op. Unknown data
    -- fields stay nil, as on real frames (libraries do `frame.x = frame.x or {}`).
    if type(k) == "string" and k:find("^%u") then
        local info = debug.getinfo(2, "S")
        if info and OWN_SOURCES[info.source] and not KNOWN_OWN_METHODS[k] then
            unknownMethods[info.source .. ": " .. k] = true
        end
        return noopMethod
    end
    return nil
end }

local function NewFrame(kind, name, parent)
    local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true, _scripts = {},
        _hooks = {}, _w = 100, _h = 20, _scale = 1 }, frameMeta)
    allFrames[#allFrames + 1] = f
    if name then rawset(_G, name, f) end
    return f
end

local function S(f) return rawget(f, "_scripts") end
function Frame:CreateFontString(name) return NewFrame("FontString", name, self) end
function Frame:CreateTexture(name) return NewFrame("Texture", name, self) end
function Frame:SetScript(e, fn) S(self)[e] = fn end
function Frame:GetScript(e) return S(self)[e] end
function Frame:HookScript(e, fn)
    rawget(self, "_hooks")[e] = fn
    local prev = S(self)[e]
    S(self)[e] = prev and function(...) prev(...); fn(...) end or fn
end
function Frame:Show()
    if not rawget(self, "_shown") then
        rawset(self, "_shown", true)
        local s = S(self).OnShow
        if s then s(self) end
    end
end
function Frame:Hide()
    if rawget(self, "_shown") then
        rawset(self, "_shown", false)
        local s = S(self).OnHide
        if s then s(self) end
    end
end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return rawget(self, "_shown") end
function Frame:IsVisible()
    local f = self
    while f do
        if not rawget(f, "_shown") then return false end
        f = rawget(f, "_parent")
    end
    return true
end
function Frame:SetText(t) rawset(self, "_text", t) end
function Frame:GetText() return rawget(self, "_text") end
function Frame:SetFont(path, size, flags) rawset(self, "_font", { path, size, flags }); return true end
function Frame:GetFont() local f = rawget(self, "_font") or {}; return f[1], f[2], f[3] end
function Frame:GetStringWidth() return #tostring(rawget(self, "_text") or "") * 7 end
function Frame:GetTextWidth() return #tostring(rawget(self, "_text") or "") * 7 end -- Button API
function Frame:GetStringHeight() local f = rawget(self, "_font"); return f and f[2] or 12 end
function Frame:SetSize(w, h) rawset(self, "_w", w); rawset(self, "_h", h) end
function Frame:SetWidth(w) rawset(self, "_w", w) end
function Frame:SetHeight(h) rawset(self, "_h", h) end
function Frame:GetWidth() return rawget(self, "_w") end
function Frame:GetHeight() return rawget(self, "_h") end
function Frame:GetSize() return rawget(self, "_w"), rawget(self, "_h") end
function Frame:SetScale(s) rawset(self, "_scale", s) end
function Frame:GetScale() return rawget(self, "_scale") end
function Frame:GetEffectiveScale() return rawget(self, "_scale") end
function Frame:GetCenter() return 960, 540 end
function Frame:GetTop() return 1000 end
function Frame:GetLeft() return 900 end
function Frame:GetRight() return 1020 end
function Frame:GetBottom() return 980 end
function Frame:GetParent() return rawget(self, "_parent") end
function Frame:SetParent(p) rawset(self, "_parent", p) end
function Frame:GetName() return rawget(self, "_name") end
function Frame:GetObjectType() return rawget(self, "_kind") end
function Frame:IsObjectType(t) return rawget(self, "_kind") == t end
function Frame:GetFrameLevel() return 1 end
function Frame:SetFrameStrata(s) rawset(self, "_strata", s) end
function Frame:GetFrameStrata() return rawget(self, "_strata") or "MEDIUM" end
function Frame:SetAlpha(a) rawset(self, "_alpha", a) end
function Frame:GetAlpha() return rawget(self, "_alpha") or 1 end
function Frame:SetBackdrop(b) rawset(self, "_backdrop", b) end
function Frame:GetNumPoints() return 0 end
function Frame:IsOwned() return false end
function Frame:SetWordWrap(v) rawset(self, "_wordWrap", v) end
function Frame:StartMoving() rawset(self, "_userPlaced", true) end -- as in game: moving marks it user-placed
function Frame:SetUserPlaced(v) rawset(self, "_userPlaced", v) end
function Frame:EnableMouse(v) rawset(self, "_click", v); rawset(self, "_motion", v) end
function Frame:SetMouseClickEnabled(v) rawset(self, "_click", v) end
function Frame:SetMouseMotionEnabled(v) rawset(self, "_motion", v) end
-- Like the game: blocked during combat or a restriction of a type the addons wait for, 0-4 (the
-- test fails); Chat (5) doesn't block it. A switch makes it reject button names above Button5 with an error.
function Frame:SetPassThroughButtons(...)
    if game.combat then fail("SetPassThroughButtons called during combat") end
    for t = 0, 4 do
        if game.restrictedTypes[t] then fail("SetPassThroughButtons called during restriction type " .. t) end
    end
    local names = { ... }
    if game.rejectLongButtons then
        for _, n in ipairs(names) do
            local k = tonumber(n:match("^Button(%d+)$"))
            if k and k > 5 then error("invalid mouse button " .. n) end
        end
    end
    rawset(self, "_pass", table.concat(names, ","))
end
-- Child regions that library code grabs and then uses (e.g. button:GetNormalTexture():SetTexCoord()).
local function child(self, key, kind)
    local c = rawget(self, key)
    if not c then
        c = NewFrame(kind, nil, self)
        rawset(self, key, c)
    end
    return c
end
for _, m in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture",
                     "GetCheckedTexture", "GetThumbTexture", "GetStatusBarTexture" }) do
    Frame[m] = function(self) return child(self, "_" .. m, "Texture") end
end
function Frame:GetFontString() return child(self, "_fontString", "FontString") end
function Frame:AddMessage(msg) chat[#chat + 1] = msg end
function Frame:RegisterEvent(e)
    eventFrames[e] = eventFrames[e] or {}
    eventFrames[e][self] = true
end
function Frame:UnregisterEvent(e) if eventFrames[e] then eventFrames[e][self] = nil end end
function Frame:IsEventRegistered(e) return eventFrames[e] and eventFrames[e][self] or false end

-- Test helpers for stub state.
local function setShownQuiet(f, v) rawset(f, "_shown", v) end -- no OnShow/OnHide
local function hooks(f) return rawget(f, "_hooks") end

local function fireEvent(e, ...)
    local list = {}
    for f in pairs(eventFrames[e] or {}) do list[#list + 1] = f end
    for _, f in ipairs(list) do
        local s = S(f).OnEvent
        if s then s(f, e, ...) end
    end
end

-- Right-click menu: the last menu opened, tooltip lines, and clicks and
-- restriction events delivered the way the engine delivers them.
local lastMenu
local tooltipLines = {}
local function linesHave(s)
    for _, m in ipairs(tooltipLines) do if m:find(s, 1, true) then return true end end
    return false
end
local tooltip = NewFrame("GameTooltip")
rawset(tooltip, "SetOwner", function() tooltipLines = {} end)
rawset(tooltip, "SetText", function(_, text) tooltipLines = { tostring(text) } end)
rawset(tooltip, "AddLine", function(_, text) tooltipLines[#tooltipLines + 1] = tostring(text) end)
local function rightClick(f)
    lastMenu = nil
    if rawget(f, "_click") and not (rawget(f, "_pass") or ""):find("RightButton", 1, true) then
        f:GetScript("OnMouseUp")(f, "RightButton")
    end
    return lastMenu ~= nil
end
local function fireRestriction(restrictionType, state)
    game.restrictionDispatch = true
    fireEvent("ADDON_RESTRICTION_STATE_CHANGED", restrictionType, state)
    game.restrictionDispatch = false
end

-- C_Timer.After callbacks run on tick(), so deferred library code (e.g. AceGUI's Slider
-- font workaround) is exercised too.
local timers = {}
local function runTimers()
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= now then
            due[#due + 1] = timers[i].fn
            table.remove(timers, i)
        end
    end
    for i = #due, 1, -1 do due[i]() end
end

local function tick(seconds)
    for _ = 1, math.floor(seconds / 0.1 + 0.5) do
        now = now + 0.1
        runTimers()
        for i = 1, #allFrames do
            local f = allFrames[i]
            local s = S(f).OnUpdate
            if s and f:IsVisible() then s(f, 0.1) end
        end
    end
end

-------------------------------------------------------------------------------- STUBS
local function noop() end
local UIParentStub = NewFrame("Frame", "UIParent")
UIParentStub:SetSize(1920, 1080)

-- Blizzard button/tab templates create named child regions ("$parentHighlightTexture",
-- "$parentLeft", ...) that library code looks up through _G.
local TEMPLATE_CHILDREN = { "HighlightTexture", "Left", "Middle", "Right", "LeftDisabled",
                            "MiddleDisabled", "RightDisabled", "Text", "Button" }

local STUBS = {
    CreateFrame = function(kind, name, parent, template)
        local f = NewFrame(kind, name, parent)
        if name and template then
            for _, suffix in ipairs(TEMPLATE_CHILDREN) do NewFrame("Texture", name .. suffix, f) end
        end
        return f
    end,
    GameTooltip = tooltip,
    ColorPickerFrame = (function()
        local f = NewFrame("Frame")
        -- 10.2.5+ colour picker API (what AceGUI's ColorPicker uses on this client)
        f.SetupColorPickerAndShow = function(self, info) rawset(self, "_info", info) end
        f.GetColorRGB = function() return 0.1, 0.2, 0.3 end
        f.GetColorAlpha = function() return 0.4 end
        return f
    end)(),
    WorldFrame = NewFrame("Frame"),
    DEFAULT_CHAT_FRAME = NewFrame("Frame"),
    GameFontNormal = NewFrame("Font"), GameFontHighlight = NewFrame("Font"),
    GameFontHighlightSmall = NewFrame("Font"), GameFontNormalSmall = NewFrame("Font"),
    GameFontNormalLarge = NewFrame("Font"), GameFontDisable = NewFrame("Font"),
    ChatFontNormal = NewFrame("Font"),
    STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
    NORMAL_FONT_COLOR_CODE = "|cffffd200", FONT_COLOR_CODE_CLOSE = "|r",
    UNKNOWN = "Unknown", OKAY = "Okay", CANCEL = "Cancel", ACCEPT = "Accept", CLOSE = "Close",
    YES = "Yes", NO = "No", DEFAULT = "Default",
    UISpecialFrames = {}, SOUNDKIT = {}, SlashCmdList = {}, hash_SlashCmdList = {},
    WOW_PROJECT_ID = 1, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CLASSIC = 2,
    GetBuildInfo = function() return "1.60.1", "70009", "Sep 2026", 16001 end,
    GetLocale = function() return "enUS" end,
    GetCurrentRegion = function() return 1 end,
    GetCurrentRegionName = function() return "US" end,
    UnitName = function() return "Tester" end,
    GetRealmName = function() return "Realm" end,
    UnitClass = function() return "Warrior", "WARRIOR", 1 end,
    UnitRace = function() return "Human", "Human", 1 end,
    UnitFactionGroup = function() return "Alliance", "Alliance" end,
    IsLoggedIn = function() return false end,
    InCombatLockdown = function() return game.combat == true end,
    C_RestrictedActions = { -- RA:55-67: false for every type while ADDON_RESTRICTION_STATE_CHANGED dispatches
        IsAddOnRestrictionActive = function(t)
            if game.restrictionDispatch then return false end
            return game.restrictedTypes[t] == true
        end,
    },
    Enum = { AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 } },
    MenuUtil = {
        CreateContextMenu = function(owner, generator)
            local root = { entries = {} }
            local function add(e) root.entries[#root.entries + 1] = e end
            function root:CreateTitle(text) add({ kind = "title", text = text }) end
            function root:CreateButton(text, callback) add({ kind = "button", text = text, callback = callback }) end
            function root:CreateCheckbox(text, isSelected, onSelect)
                add({ kind = "checkbox", text = text, isSelected = isSelected, onSelect = onSelect })
            end
            function root:CreateDivider() add({ kind = "divider" }) end
            generator(owner, root)
            lastMenu = { owner = owner, entries = root.entries }
            return root
        end,
    },
    PlaySound = noop, PlaySoundFile = noop,
    GetCursorPosition = function() return 0, 0 end,
    IsShiftKeyDown = function() return false end,
    IsControlKeyDown = function() return false end,
    IsAltKeyDown = function() return false end,
    hooksecurefunc = function(t, name, fn)
        if type(t) == "string" then t, name, fn = _G, t, name end
        local orig = t[name]
        t[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
    end,
    securecallfunction = function(f, ...) return f(...) end,
    securecall = function(f, ...) if type(f) == "string" then f = _G[f] end return f(...) end,
    -- Like the game's error frame: errors that libraries route to the error handler (AceGUI and
    -- AceConfigDialog run widget code through xpcall + geterrorhandler) are reported, not lost.
    geterrorhandler = function() return function(e) fail("error handler: " .. tostring(e)); return e end end,
    debugstack = function() return "" end,
    issecretvalue = function(v) return v == SECRET end,
    C_Timer = {
        After = function(delay, fn) timers[#timers + 1] = { at = now + (delay or 0), fn = fn } end,
        NewTicker = function() return { Cancel = noop, IsCancelled = function() return false end } end,
    },
    C_SettingsUtil = { OpenSettingsPanel = noop },
    C_UIFileAsset = { IsKnownFile = function() return true end }, -- LibSharedMedia 12.x
    Mixin = function(o, ...)
        for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end
        return o
    end,
    BackdropTemplateMixin = {},
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    tinsert = table.insert, tremove = table.remove, format = string.format,
    strmatch = string.match, strfind = string.find, gsub = string.gsub, strsub = string.sub,
    strlower = string.lower, strupper = string.upper, strlen = string.len, strrep = string.rep,
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
    strsplit = function(sep, s)
        local out = {}
        for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
        return unpack(out)
    end,
    strjoin = function(sep, ...) return table.concat({ ... }, sep) end,
    floor = math.floor, ceil = math.ceil, max = math.max, min = math.min, abs = math.abs,
    date = os.date, time = os.time,
    -- the addon's game-state APIs
    GetTime = function() return now end,
    GetServerTime = function() return math.floor(now) end,
    IsInInstance = function()
        if game.throw then error("simulated API failure") end
        return game.inInstance, game.itype
    end,
    GetInstanceInfo = function()
        if not game.inInstance then return "Elwynn Forest", "none", 0, "", 0, 0, false, 0 end
        return game.name, game.itype, 1, "Normal", 5, 0, false, game.id
    end,
    UnitIsDeadOrGhost = function() if game.secret then return SECRET end return game.dead or game.ghost end,
    UnitIsGhost = function() if game.secret then return SECRET end return game.ghost end,
    UnitIsDead = function() if game.secret then return SECRET end return game.dead and not game.ghost end,
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        chat[#chat + 1] = table.concat(parts, " ")
    end,
}
local categories, nextID = {}, 100
STUBS.Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        if BREAK_SETTINGS then error("simulated Settings API change") end
        nextID = nextID + 1
        categories[nextID] = { ID = nextID, name = name, frame = frame }
        return categories[nextID]
    end,
    RegisterCanvasLayoutSubcategory = function(parent, frame, name)
        nextID = nextID + 1
        categories[nextID] = { ID = nextID, name = name, frame = frame, parent = parent }
        return categories[nextID]
    end,
    RegisterAddOnCategory = noop,
    GetCategory = function(id) return categories[id] end,
    OpenToCategory = function(id) openedCategory = id end,
}
for k, v in pairs(STUBS) do rawset(_G, k, v) end
table.wipe = STUBS.wipe       -- WoW adds wipe to the table library too
string.split = STUBS.strsplit -- ...and strsplit to the string library ("\001"):split(s)
rawset(_G, "UIParent", UIParentStub)

-------------------------------------------------------------------------------- global guard
local OWN = OWN_SOURCES
for _, f in ipairs({ "TimeFormat", "Clock", "ZoneWatcher", "RunTracker", "Defaults", "Display", "Options", "Core" }) do
    OWN["@" .. f .. ".lua"] = true
end
local EXPECTED_NIL = { ForeverInstanceTimerCharDB = true, MenuUtil = true } -- MenuUtil: removed by one test
local ALLOWED_WRITES = { ForeverInstanceTimerCharDB = true, SLASH_FOREVERINSTANCETIMER1 = true,
                         SLASH_FOREVERINSTANCETIMER2 = true }
local unknownReads = {}
setmetatable(_G, {
    __index = function(_, k)
        local info = debug.getinfo(2, "S")
        if info and OWN[info.source] and not EXPECTED_NIL[k] then
            unknownReads[info.source .. ": " .. tostring(k)] = true
        end
        return nil
    end,
    __newindex = function(t, k, v)
        local info = debug.getinfo(2, "S")
        if info and OWN[info.source] and not ALLOWED_WRITES[k] then
            fail("global write '" .. tostring(k) .. "' from " .. info.source)
        end
        rawset(t, k, v)
    end,
})

-------------------------------------------------------------------------------- load addon
local ns = {}
local function loadLua(path)
    local chunk, err = loadfile(path)
    if not chunk then fail("compile: " .. tostring(err)); return end
    local ok, e = pcall(chunk, ADDON, ns)
    if not ok then fail("load " .. path .. ": " .. tostring(e)) end
end

local function loadXml(path)
    local f = assert(io.open(path, "r"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")
    f:close()
    local dir = path:match("^(.*)/[^/]*$") or "."
    for tag, file in xml:gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
        local sub = dir .. "/" .. file:gsub("\\", "/")
        if tag == "Script" then loadLua(sub) elseif tag == "Include" then loadXml(sub) end
    end
end

for line in io.lines(ADDON .. ".toc") do
    line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
    if line ~= "" and not line:find("^#") then
        local p = line:gsub("\\", "/")
        if p:find("%.xml$") then loadXml(p) else loadLua(p) end
    end
end
check(ns.TimeFormat and ns.Clock and ns.ZoneWatcher and ns.RunTracker and ns.DEFAULTS
      and ns.Display and ns.Options, "all modules loaded into the namespace")

-------------------------------------------------------------------------------- session
local function run() return ForeverInstanceTimerCharDB and ForeverInstanceTimerCharDB.run or {} end
local function chatHas(s)
    for _, m in ipairs(chat) do if m:find(s, 1, true) then return true end end
    return false
end
local function zone(state)
    fireEvent("LOADING_SCREEN_ENABLED")
    tick(0.5)
    for k, v in pairs(state) do game[k] = v end
    fireEvent("PLAYER_ENTERING_WORLD", false, false)
    fireEvent("ZONE_CHANGED_NEW_AREA")
    tick(0.3)
    fireEvent("LOADING_SCREEN_DISABLED")
end
local DM = { inInstance = true, name = "The Deadmines", itype = "party", id = 36 }
local MC = { inInstance = true, name = "Molten Core", itype = "raid", id = 409 }
local WSG = { inInstance = true, name = "Warsong Gulch", itype = "pvp", id = 489 }
local OUT = { inInstance = false, name = false, itype = "none", id = false }

fireEvent("ADDON_LOADED", ADDON)
check(type(ForeverInstanceTimerCharDB) == "table", "per-character saved table created")
check(SlashCmdList.FOREVERINSTANCETIMER ~= nil, "slash command registered")

local ACR = LibStub("AceConfigRegistry-3.0")
if BREAK_SETTINGS then
    check(chatHas("options panel is unavailable"), "a broken Settings API is reported in chat")
else
    for _, app in ipairs({ "ForeverInstanceTimer", "ForeverInstanceTimer_Profiles" }) do
        local ok, err = pcall(ACR.GetOptionsTable, ACR, app, "dialog", "AceConfigDialog-3.0")
        check(ok, "options table " .. app .. " validates: " .. tostring(err))
    end
end

-- Change a setting the way the options panel does: through the option's own setter.
-- A colour's setter takes r, g, b, a.
local function setOption(path, ...)
    local opt = ACR:GetOptionsTable("ForeverInstanceTimer", "dialog", "AceConfigDialog-3.0")
    for _, key in ipairs(path) do opt = opt.args[key] end
    opt.set({}, ...)
end
local function aceDB()
    for db in pairs(LibStub("AceDB-3.0").db_registry) do
        if db.sv == ForeverInstanceTimerDB then return db end
    end
end

fireEvent("PLAYER_ENTERING_WORLD", true, false)
tick(0.5)
fireEvent("LOADING_SCREEN_DISABLED")
tick(2)
check(run().state == "idle", "idle after logging in outside")

local timer = _G.ForeverInstanceTimerFrame
zone(DM); tick(3)
check(run().state == "inside", "entering a dungeon starts a run")
check(timer and timer:IsShown(), "timer shown inside")

setOption({ "display", "hideInCombat" }, true)
fireEvent("PLAYER_REGEN_DISABLED"); tick(0.2)
check(not timer:IsShown(), "hide-in-combat hides the timer during combat")
fireEvent("PLAYER_REGEN_ENABLED"); tick(0.2)
check(timer:IsShown(), "the timer comes back after combat")
setOption({ "display", "hideInCombat" }, false)

game.dead = true; fireEvent("PLAYER_DEAD"); tick(1)
game.ghost = true
zone(OUT); tick(3)
check(run().state == "away", "releasing keeps the run (away)")
check(timer:IsShown(), "timer shown during the corpse run")
setOption({ "display", "showWhileAway" }, false); tick(0.2)
check(not timer:IsShown(), "show-while-away off hides the corpse-run timer")
setOption({ "display", "showWhileAway" }, true); tick(0.2)
zone(DM); tick(1)
game.dead, game.ghost = false, false; fireEvent("PLAYER_UNGHOST"); tick(2)
check(run().state == "inside", "ghost re-entry resumes the run")

SlashCmdList.FOREVERINSTANCETIMER("unlock")
local okDrag, errDrag = pcall(function()
    timer:GetScript("OnEnter")(timer)
    timer:GetScript("OnDragStart")(timer)
    timer:GetScript("OnDragStop")(timer)
    timer:GetScript("OnLeave")(timer)
end)
check(okDrag, "drag and tooltip scripts: " .. tostring(errDrag))
check(rawget(timer, "_userPlaced") == false, "a dragged frame is not left user-placed (the profile owns its position)")
local savedPos = ForeverInstanceTimerDB.profiles and ForeverInstanceTimerDB.profiles.Default
                 and ForeverInstanceTimerDB.profiles.Default.pos
check(savedPos and type(savedPos.x) == "number" and type(savedPos.y) == "number", "dragging saves the position")
SlashCmdList.FOREVERINSTANCETIMER("lock")
SlashCmdList.FOREVERINSTANCETIMER("resetpos")

chat = {}
zone(OUT); tick(3)
check(run().state == "idle", "leaving alive ends the run")
check(chatHas("Forever Instance Timer|r: The Deadmines - "), "final time printed to chat")
check(timer:IsShown(), "final time frozen on screen")
tick(11)
check(not timer:IsShown(), "frozen time hides after 10 s")

zone(DM); tick(3)
game.dead = true; fireEvent("PLAYER_DEAD"); game.ghost = true
zone(OUT); tick(2)
game.dead, game.ghost = false, false; fireEvent("PLAYER_UNGHOST"); tick(5)
check(run().state == "idle", "spirit-healer revive outside ends the run")

zone(MC); tick(3)
check(run().state == "inside" and run().key == 409, "raids start the timer")
zone(WSG); tick(3)
check(run().state == "inside" and run().key == 489, "direct switch to a battleground starts a new run")
game.dead = true; fireEvent("PLAYER_DEAD"); tick(1)
game.dead = false; fireEvent("PLAYER_UNGHOST"); tick(1)
check(run().state == "inside", "dying in a battleground changes nothing")
zone(OUT); tick(3)

-- Secret death state (a Midnight restriction): the event-tracked flag keeps the run.
game.secret = true
zone(DM); tick(3)
check(run().state == "inside", "secret death state: entering still starts a run")
fireEvent("PLAYER_DEAD"); tick(1)
zone(OUT); tick(3)
check(run().state == "away", "secret death state: releasing keeps the run via the event-tracked flag")
zone(DM); tick(1)
fireEvent("PLAYER_UNGHOST"); tick(2)
check(run().state == "inside", "secret death state: ghost re-entry resumes the run")
chat = {}
SlashCmdList.FOREVERINSTANCETIMER("status")
check(chatHas("deadFallback=true"), "/itimer status reports the dead fallback")
game.secret = false

-- A failing game API: readings are skipped, nothing raises, the run is untouched.
game.throw = true
local stateBefore = run().state
local okThrow, errThrow = pcall(tick, 3)
check(okThrow, "a failing IsInInstance does not raise: " .. tostring(errThrow))
check(run().state == stateBefore, "a failing IsInInstance leaves the run untouched")
game.throw = false
zone(OUT); tick(3)

-------------------------------------------------------------------------------- slash commands
for _, cmd in ipairs({ "status", "debug", "status", "debug", "unlock", "lock", "resetpos", "reset", "help" }) do
    local ok, err = pcall(SlashCmdList.FOREVERINSTANCETIMER, cmd)
    check(ok, "/itimer " .. cmd .. ": " .. tostring(err))
end
chat = {}
local okOpen, errOpen = pcall(SlashCmdList.FOREVERINSTANCETIMER, "")
check(okOpen, "/itimer: " .. tostring(errOpen))
if BREAK_SETTINGS then
    check(chatHas("options panel is unavailable"), "/itimer explains that the panel is unavailable")
else
    check(openedCategory == ns.Options.categoryID and openedCategory ~= nil, "/itimer opens the settings category")
end

if not BREAK_SETTINGS then
-------------------------------------------------------------------------------- options panel
local page = ns.Options.frame
setShownQuiet(page, true)
hooks(page).OnShow(page)
check(timer:IsShown() and timer:GetFrameStrata() == "FULLSCREEN_DIALOG", "preview shows the timer above the settings window")

local holder = ns.Options.statusText:GetParent()
holder:GetScript("OnUpdate")(holder, 1)
zone(DM); tick(3)
holder:GetScript("OnUpdate")(holder, 1)
local statusLine = tostring(ns.Options.statusText:GetText())
check(statusLine:find("^Current run: %d+:%d%d %- The Deadmines") ~= nil,
      "status line puts the time first, so a long name is what gets cut: " .. statusLine)
check(rawget(ns.Options.statusText, "_wordWrap") == false, "status line never wraps")
zone(OUT); tick(3)

-- Hide the page again before the walk. While a page is visible, AceConfigDialog renders real
-- AceGUI widgets on the tick after a NotifyChange, and these stubs don't support that
-- (AceConfigDialog-3.0.lua:1789-1795). Keep the preview on directly instead.
setShownQuiet(page, false)
ns.Display:SetPreview(true)

local function walk(group, path)
    for key, opt in pairs(group.args or {}) do
        local here = path .. "." .. key
        if opt.type == "group" then
            walk(opt, here)
        elseif opt.type == "execute" then
            local ok, err = pcall(opt.func, {})
            check(ok, here .. ": " .. tostring(err))
        elseif type(opt.get) == "function" and type(opt.set) == "function" then
            local ok, err = pcall(function()
                local info = {}
                local orig = { opt.get(info) }
                if opt.type == "toggle" then
                    opt.set(info, not orig[1]); tick(0.2); opt.set(info, orig[1])
                elseif opt.type == "select" then
                    local values = type(opt.values) == "function" and opt.values(info) or opt.values
                    for k in pairs(values) do opt.set(info, k); tick(0.2) end
                    opt.set(info, orig[1])
                elseif opt.type == "range" then
                    opt.set(info, opt.softMin or opt.min); tick(0.2)
                    opt.set(info, opt.softMax or opt.max); tick(0.2)
                    opt.set(info, orig[1])
                elseif opt.type == "color" then
                    opt.set(info, 0.1, 0.2, 0.3, 0.4); tick(0.2); opt.set(info, unpack(orig))
                end
            end)
            check(ok, here .. ": " .. tostring(err))
        end
    end
end
local options = ACR:GetOptionsTable("ForeverInstanceTimer", "dialog", "AceConfigDialog-3.0")
walk(options, "options")

hooks(page).OnHide(page)
check(timer:GetFrameStrata() == "MEDIUM", "preview ends when the settings page hides")

-------------------------------------------------------------------------------- render the real panel
-- Showing a page makes AceConfigDialog build real AceGUI widgets (CheckBox, Slider, Dropdown,
-- ColorPicker, Button, LSM30_* pickers) exactly as the Settings window does in game. Only
-- globals that exist on the client are stubbed, so a library calling a removed global
-- (e.g. SetDesaturation, removed in 12.1) fails here instead of in game.
local ACD = LibStub("AceConfigDialog-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local created, origCreate = {}, AceGUI.Create
AceGUI.Create = function(self, widgetType, ...) -- count what actually gets built
    created[widgetType] = (created[widgetType] or 0) + 1
    return origCreate(self, widgetType, ...)
end
local function render(label, fn)
    local ok, err = pcall(function() fn(); tick(0.5) end)
    check(ok, "render " .. label .. ": " .. tostring(err))
end
-- Use every live control on a page the way a player would. Scripts are the ones AceGUI and
-- SharedMediaWidgets register (OnMouseUp, OnClick, OnValueChanged, OnEnterPressed).
local used = {}
local function script(frame, name) return frame and frame:GetScript(name) end
local function useWidget(w)
    local t = w.type
    if t == "CheckBox" then
        script(w.frame, "OnMouseUp")(w.frame)
    elseif t == "Slider" then
        script(w.slider, "OnValueChanged")(w.slider, w.value or 1)
        script(w.slider, "OnMouseUp")(w.slider)
    elseif t == "Dropdown" then
        script(w.button, "OnClick")(w.button) -- open the list
        script(w.button, "OnClick")(w.button) -- close it
    elseif t:find("^LSM30_") then
        local b = w.frame.dropButton
        script(b, "OnClick")(b)
        script(b, "OnClick")(b)
    elseif t == "Button" then
        script(w.frame, "OnClick")(w.frame)
    elseif t == "ColorPicker" then
        script(w.frame, "OnClick")(w.frame)
        local info = rawget(ColorPickerFrame, "_info")
        if info then info.swatchFunc(); info.opacityFunc(); info.cancelFunc({ r = 1, g = 1, b = 1, a = 1 }) end
    elseif t == "EditBox" then
        w.editbox:SetText("SmokeProfile")
        script(w.editbox, "OnEnterPressed")(w.editbox)
    else
        return
    end
    used[t] = true
end
local function useAll(label, container)
    for _, w in ipairs(container.children or {}) do
        local ok, err = pcall(useWidget, w)
        check(ok, "use " .. label .. " " .. tostring(w.type) .. ": " .. tostring(err))
        if w.children then useAll(label, w) end
        tick(0.2)
    end
end

render("main page (Display tab)", function() page:Show() end)
useAll("Display tab", page.obj)
render("Appearance tab", function() ACD:SelectGroup("ForeverInstanceTimer", "appearance") end)
useAll("Appearance tab", page.obj)
render("Rules tab", function() ACD:SelectGroup("ForeverInstanceTimer", "rules") end)
useAll("Rules tab", page.obj)
render("Display tab again", function() ACD:SelectGroup("ForeverInstanceTimer", "display") end)
render("refresh while open (NotifyChange)", function() ns.Options:Refresh() end)
render("hide main page", function() page:Hide() end)
local profiles = ns.Options.profilesFrame
render("Profiles page", function() profiles:Show() end)
useAll("Profiles page", profiles.obj)
render("hide Profiles page", function() profiles:Hide() end)
for _, t in ipairs({ "CheckBox", "Slider", "Dropdown", "Button", "ColorPicker", "EditBox",
                     "LSM30_Font", "LSM30_Background", "LSM30_Border" }) do
    check(used[t], "interacted with a " .. t .. " widget")
end
AceGUI.Create = origCreate
for _, widgetType in ipairs({ "TabGroup", "InlineGroup", "CheckBox", "Slider", "Dropdown", "ColorPicker",
                              "Button", "Label", "EditBox", "LSM30_Font", "LSM30_Background", "LSM30_Border" }) do
    check((created[widgetType] or 0) > 0, "render built at least one " .. widgetType .. " widget")
end

end

-------------------------------------------------------------------------------- reset defaults
-- Reset defaults. Steps 1-4 test the slash route; step 5 repeats them for the button and
-- the game's Defaults; step 8 checks the two rule exceptions.
do
    local slash = SlashCmdList.FOREVERINSTANCETIMER
    local ACD = LibStub("AceConfigDialog-3.0")
    local HINT = "type /itimer defaults confirm to reset all settings in the current profile, including the run rules, to their defaults (a run in progress follows the default rules from then on, so a corpse run can end)."
    local DESC = "Puts every setting on every tab back to its default, including the position and the run rules. A run in progress follows the default rules from then on, so a corpse run can end. Same as /itimer defaults confirm."
    local CONFIRM = "Reset all Forever Instance Timer settings in the current profile, including the run rules, to their defaults? A run in progress follows the default rules from then on, so a corpse run can end. This cannot be undone."
    local HELP = "/itimer (options), lock, unlock, reset, resetpos, defaults, status, debug, help"
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
    -- Changes on every tab, through the options' own setters.
    local function changeSettings()
        setOption({ "display", "posX" }, 150)
        setOption({ "display", "scale" }, 2)
        setOption({ "display", "alpha" }, 0.5)
        setOption({ "display", "strata" }, "HIGH")
        setOption({ "appearance", "colors", "running" }, 1, 0, 0, 1)
        setOption({ "appearance", "timeFont", "size" }, 30)
        setOption({ "appearance", "layout", "showName" }, false)
        setOption({ "rules", "death", "awayMode" }, "pause")
        setOption({ "rules", "types", "pvp" }, false)
        setOption({ "display", "rightClickMenu" }, false)
        slash("unlock")
        check(timer:GetScale() == 2 and rawget(timer, "_motion") == true, "reset: the changes reached the frame")
    end
    -- Checked right after a reset, before any tick.
    local function checkReset(route)
        local out = {}
        diff(aceDB().profile, ns.DEFAULTS.profile, "profile", out)
        check(#out == 0, route .. ": every setting is back to its default: " .. table.concat(out, ", "))
        check(timer:GetScale() == 1 and rawget(timer, "_motion") == false and rawget(timer, "_click") == true
              and rawget(timer, "_pass") == PASS_ALL, route .. ": the frame was re-applied (scale 1, locked, the menu back on)")
        check(chatHas('all settings in the profile "Default" reset to their defaults'
                      .. (route == "game" and " by the game's Defaults button" or "") .. "."), route .. ": the chat line")
        if not BREAK_SETTINGS then
            local requested = ACD.frame.apps.ForeverInstanceTimer == true
            check(requested == (route ~= "button"),
                  route .. (route == "button" and ": no panel refresh (the popup re-opens the page)" or ": a panel refresh"))
        end
        check(ForeverInstanceTimerDB.global.debug == true and ForeverInstanceTimerDB.profiles.Other.scale == 1.5,
              route .. ": debug and the other profile are kept")
    end

    aceDB():SetProfile("Default") -- the panel walk left "SmokeProfile" active
    -- 1. A run in progress; debug on, once.
    zone(DM); tick(3)
    check(run().state == "inside", "reset: a run is in progress")
    slash("debug")
    -- 2. Settings changed on every tab, and in a second profile.
    changeSettings()
    aceDB():SetProfile("Other")
    setOption({ "display", "scale" }, 1.5)
    aceDB():SetProfile("Default")
    -- 3. Without "confirm", nothing changes.
    chat = {}; slash("defaults")
    check(chatHas(HINT), "/itimer defaults prints the hint")
    chat = {}; slash("defaults confirm now")
    check(chatHas(HINT) and aceDB().profile.scale == 2, "/itimer defaults confirm now only explains")
    -- 4. The slash route.
    tick(0.1); chat = {}
    slash("  Defaults  CONFIRM ") -- the rest of the line is trimmed and lowercased
    checkReset("slash")
    tick(1)
    check(run().state == "inside" and timer:IsShown(), "slash: the run keeps going")
    -- 5. The button, the game's Defaults, and the Profiles page (which must not listen).
    if not BREAK_SETTINGS then
        changeSettings(); tick(0.1); chat = {}
        local opt = ACR:GetOptionsTable("ForeverInstanceTimer", "dialog", "AceConfigDialog-3.0").args.display.args.resetDefaults
        check(opt and opt.type == "execute" and opt.order == 3.5 and opt.name == "Reset defaults" and opt.desc == DESC
              and opt.confirm == true and opt.confirmText == CONFIRM, "the Display tab's Reset defaults button")
        opt.func()
        checkReset("button")
        changeSettings(); tick(0.1); chat = {}
        ns.Options.frame:OnDefault()
        checkReset("game")
        setOption({ "display", "scale" }, 2)
        chat = {}
        ns.Options.profilesFrame:OnDefault()
        check(aceDB().profile.scale == 2 and not chatHas("reset to their defaults"), "the Profiles page's OnDefault doesn't reset")
        aceDB():ResetProfile()
    end
    -- The chat line names the active profile, and only that profile is reset.
    aceDB():SetProfile("Other")
    chat = {}; slash("defaults confirm")
    check(chatHas('all settings in the profile "Other" reset to their defaults') and aceDB().profile.scale == 1,
          "a reset names and resets the active profile")
    aceDB():SetProfile("Default")
    -- 7. The help line.
    chat = {}; slash("help")
    check(chatHas(HELP), "/itimer help lists defaults")
    -- 8(a). A corpse run, alive outside, waiting indefinitely: the default rule (ghost) ends it.
    setOption({ "rules", "death", "giveUp" }, "never")
    game.dead = true; fireEvent("PLAYER_DEAD"); tick(1)
    game.ghost = true
    zone(OUT); tick(3)
    game.dead, game.ghost = false, false; fireEvent("PLAYER_UNGHOST"); tick(5)
    check(run().state == "away", "8(a): alive outside, waiting indefinitely: still away")
    chat = {}
    slash("defaults confirm"); tick(5)
    check(run().state == "idle" and chatHas("The Deadmines - ") and chatHas("run finished (revived)"),
          "8(a): after a reset, the corpse run ends as revived")
    -- 8(b). Standing in a battleground with battlegrounds off: the reset starts timing now.
    setOption({ "rules", "types", "pvp" }, false)
    zone(WSG); tick(5)
    check(run().state == "idle", "8(b): battlegrounds off: no run")
    slash("defaults confirm"); tick(3)
    chat = {}; slash("status")
    local seconds
    for _, m in ipairs(chat) do
        local mm, ss = m:match("Current run: (%d+):(%d%d) %- Warsong Gulch")
        if mm then seconds = tonumber(mm) * 60 + tonumber(ss) end
    end
    check(run().state == "inside" and run().key == 489 and seconds and seconds <= 3,
          "8(b): the reset starts a run, timed from the reset: " .. tostring(seconds))
    zone(OUT); tick(3)
    slash("debug")
end

-------------------------------------------------------------------------------- right-click menu
-- Right-click menu. In a run inside The Deadmines, so the timer is on screen.
do
    local slash = SlashCmdList.FOREVERINSTANCETIMER
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
        for _, e in ipairs(lastMenu and lastMenu.entries or {}) do out[#out + 1] = e.kind .. ":" .. tostring(e.text) end
        return table.concat(out, "|")
    end
    local function entry(text)
        for _, e in ipairs(lastMenu.entries) do if e.text == text then return e end end
    end
    local function count(s)
        local n = 0
        for _, line in ipairs(chat) do if line:find(s, 1, true) then n = n + 1 end end
        return n
    end
    local function menuStatus()
        chat = {}; slash("status")
        for _, line in ipairs(chat) do
            local s = line:match("(right%-click menu: .*)$")
            if s then return s end
        end
    end
    local UNSUPPORTED = "pass-through buttons are not supported on this client: the locked timer stays click-through, the menu works when unlocked"
    local SHORT = "pass-through fell back to buttons 1-5"
    local SHORT_LIST = "LeftButton,MiddleButton,Button4,Button5"
    zone(DM); tick(3)
    check(run().state == "inside", "menu: a run is in progress")
    -- The setting.
    if not BREAK_SETTINGS then
        local opt = ACR:GetOptionsTable("ForeverInstanceTimer", "dialog", "AceConfigDialog-3.0").args.display.args.rightClickMenu
        check(opt and opt.type == "toggle" and opt.order == 2.5 and opt.name == "Right-click menu"
              and opt.desc == "Right-click the timer for a menu: Options, Lock position, Reset position and Reset current run. Other clicks still go through to the game world. Turn this off to make the locked timer completely click-through.",
              "the Display tab's Right-click menu setting")
    end
    -- 1. Locked, default; the status line says so.
    lockedState("default")
    check(menuStatus() == "right-click menu: on; pass-through: all but the right button", "status: locked with the menu")
    -- 2. Right-click opens the menu; other buttons don't; unlocked too.
    check(rightClick(timer) and lastMenu.owner == timer, "right-click opens a menu owned by the timer")
    check(entries() == "title:Forever Instance Timer|button:Options|checkbox:Lock position|button:Reset position|button:Reset current run",
          "menu entries: " .. entries())
    check(entry("Lock position").isSelected() == true, "Lock position is ticked while locked")
    lastMenu = nil
    timer:GetScript("OnMouseUp")(timer, "LeftButton")
    timer:GetScript("OnMouseUp")(timer, "MiddleButton")
    check(lastMenu == nil, "left and middle clicks open nothing")
    slash("unlock")
    check(rightClick(timer), "an unlocked timer's right-click opens the menu too")
    slash("lock")
    -- 3. Each entry.
    rightClick(timer)
    if not BREAK_SETTINGS then
        openedCategory = nil
        entry("Options").callback()
        check(openedCategory ~= nil and openedCategory == ns.Options.categoryID, "Options opens the settings")
        game.combat = true; chat = {}
        entry("Options").callback()
        check(chatHas("options can't be opened during combat."), "Options is refused in combat")
        game.combat = false
    else
        chat = {}; entry("Options").callback()
        check(chatHas("options panel is unavailable"), "Options explains a broken panel")
    end
    chat = {}
    entry("Lock position").onSelect()
    local c, m, p = mouse()
    check(aceDB().profile.locked == false and m == true and p == "" and chatHas("unlocked:"), "Lock position unlocks")
    check(entry("Lock position").isSelected() == false, "Lock position is unticked while unlocked")
    entry("Lock position").onSelect()
    lockedState("Lock position locks again")
    setOption({ "display", "posX" }, 77)
    chat = {}; entry("Reset position").callback()
    check(aceDB().profile.pos.x == ns.DEFAULTS.profile.pos.x and chatHas("position reset."), "Reset position")
    local before = run().start
    tick(2)
    chat = {}; entry("Reset current run").callback()
    check(chatHas("timer reset.") and run().start and run().start > before, "Reset current run restarts the run")
    -- 4. The setting off; 8. the tooltip both ways.
    setOption({ "display", "rightClickMenu" }, false)
    c, m, p = mouse()
    check(c == false and m == false and p == "", "setting off: the locked timer is fully click-through")
    check(menuStatus() == "right-click menu: off", "status: the setting off")
    check(not rightClick(timer), "setting off: right-click opens nothing")
    slash("unlock")
    check(rawget(timer, "_motion") == true and not rightClick(timer), "setting off, unlocked: right-click opens nothing")
    timer:GetScript("OnEnter")(timer)
    check(linesHave("Drag to move. Type /itimer lock to lock it."), "tooltip without the menu")
    setOption({ "display", "rightClickMenu" }, true)
    timer:GetScript("OnEnter")(timer)
    check(linesHave("Drag to move. Right-click for the menu. Type /itimer lock to lock it."), "tooltip with the menu")
    slash("lock")
    lockedState("setting back on")
    -- 5. Combat: pass-through changes wait for PLAYER_REGEN_ENABLED.
    game.combat = true; fireEvent("PLAYER_REGEN_DISABLED")
    slash("unlock")
    c, m, p = mouse()
    check(m == true and p == ALL, "unlock in combat: the mouse is taken, the pass-through waits")
    check(menuStatus() == "right-click menu: on; pass-through: all but the right button, waiting for combat or a restriction to end",
          "status: the clear waits for combat to end")
    game.combat = false; fireEvent("PLAYER_REGEN_ENABLED")
    check(rawget(timer, "_pass") == "", "after combat: the pass-through is cleared")
    check(menuStatus() == "right-click menu: on; pass-through: none (unlocked)", "status: unlocked")
    game.combat = true; fireEvent("PLAYER_REGEN_DISABLED")
    slash("lock")
    check(rawget(timer, "_click") == false, "lock in combat: fully click-through until combat ends")
    check(menuStatus() == "right-click menu: on; pass-through: none, waiting for combat or a restriction to end",
          "status: the set waits for combat to end")
    game.combat = false; fireEvent("PLAYER_REGEN_ENABLED")
    lockedState("after combat")
    -- 6. A restriction: changes wait, and the catch-up runs a frame after the event. Each type the
    -- addons wait for (0-4) on its own; the stub fails any pass-through call made under one.
    for t = 0, 4 do
        local label = "restriction type " .. t
        setOption({ "display", "rightClickMenu" }, false)
        check(rawget(timer, "_pass") == "", label .. ": the test starts without the pass-through")
        game.restrictedTypes[t] = true
        setOption({ "display", "rightClickMenu" }, true)
        check(rawget(timer, "_click") == false and rawget(timer, "_pass") == "", label .. ": fully click-through, no call")
        fireRestriction(5, 2) -- Chat becoming active: another type
        check(rawget(timer, "_pass") == "", label .. ": no call inside the event's dispatch")
        tick(0.1)
        check(rawget(timer, "_pass") == "", label .. ": still pending while the restriction lasts")
        game.restrictedTypes[t] = nil
        fireRestriction(t, 0)
        check(rawget(timer, "_pass") == "", label .. ": nothing changes during the dispatch")
        tick(0.1)
        lockedState(label .. ": a frame after it ended")
    end
    -- A Chat restriction doesn't hold the change back.
    setOption({ "display", "rightClickMenu" }, false)
    game.restrictedTypes[5] = true
    setOption({ "display", "rightClickMenu" }, true)
    lockedState("under a Chat restriction")
    game.restrictedTypes[5] = nil
    -- One catch-up per frame, however many events fire in it.
    local after, scheduled = C_Timer.After, 0
    local function counting(delay, fn) scheduled = scheduled + 1; return after(delay, fn) end
    C_Timer.After = counting
    fireRestriction(1, 2); fireRestriction(2, 2); fireRestriction(1, 0)
    C_Timer.After = after
    check(scheduled == 1, "three events in one frame schedule one catch-up")
    tick(0.1)
    C_Timer.After = counting
    fireRestriction(1, 2)
    C_Timer.After = after
    check(scheduled == 2, "an event in a later frame schedules another")
    tick(0.1)
    lockedState("after the catch-ups")
    -- The menu turned off while its clear waits: the status line still shows the wait.
    game.restrictedTypes[1] = true
    setOption({ "display", "rightClickMenu" }, false)
    check(menuStatus() == "right-click menu: off; pass-through: all but the right button, waiting for combat or a restriction to end",
          "status: the menu off, its clear waiting")
    game.restrictedTypes[1] = nil
    fireRestriction(1, 0); tick(0.1)
    check(rawget(timer, "_pass") == "" and menuStatus() == "right-click menu: off", "the clear catches up; status: off")
    setOption({ "display", "rightClickMenu" }, true)
    lockedState("the menu back on")
    -- 6b. MenuUtil missing: no menu anywhere, and the locked timer is fully click-through.
    local menuUtil = MenuUtil
    rawset(_G, "MenuUtil", nil)
    ns.Display:ApplyMouse()
    c, m, p = mouse()
    check(c == false and m == false and p == "" and not rightClick(timer), "no MenuUtil: fully click-through, no menu")
    check(menuStatus() == "right-click menu: unavailable on this client", "status: no MenuUtil")
    slash("unlock")
    check(rawget(timer, "_motion") == true and not rightClick(timer), "no MenuUtil, unlocked: right-click opens nothing")
    timer:GetScript("OnEnter")(timer)
    check(linesHave("Drag to move. Type /itimer lock to lock it."), "no MenuUtil: the tooltip without the menu")
    slash("lock")
    rawset(_G, "MenuUtil", menuUtil)
    ns.Display:ApplyMouse()
    lockedState("MenuUtil back")
    -- 7. Pass-through unsupported. Debug is off at first: the note waits until debug is on.
    rawset(timer, "SetPassThroughButtons", false)
    chat = {}
    slash("unlock"); slash("lock")
    fireRestriction(1, 0); tick(0.1)
    check(rawget(timer, "_click") == false and not rightClick(timer), "unsupported: the locked timer stays click-through, no menu")
    check(count(UNSUPPORTED) == 0, "unsupported: no note while debug is off")
    check(menuStatus() == "right-click menu: on; pass-through: unsupported, so the menu works only when unlocked",
          "status: unsupported")
    slash("debug")
    slash("unlock")
    check(rightClick(timer), "unsupported: the unlocked timer's menu still works")
    slash("lock")
    check(count(UNSUPPORTED) == 1, "unsupported: noted once, after debug is turned on")
    rawset(timer, "SetPassThroughButtons", nil)
    ns.Display:ApplyMouse()
    lockedState("pass-through supported again")
    -- 7b. The short-list fallback (last: the short list stays for the session). Debug off at first.
    slash("debug")
    game.rejectLongButtons = true
    chat = {}
    slash("unlock"); slash("lock")
    check(rawget(timer, "_pass") == SHORT_LIST, "the short-list fallback")
    check(count(SHORT) == 0, "short list: no note while debug is off")
    check(menuStatus() == "right-click menu: on; pass-through: buttons 1-5 but the right one", "status: the short list")
    slash("debug")
    slash("unlock"); slash("lock")
    check(rawget(timer, "_pass") == SHORT_LIST and count(SHORT) == 1, "later sets use the short list; noted once debug is on")
    slash("unlock"); slash("lock")
    check(count(SHORT) == 1, "the note isn't repeated")
    game.rejectLongButtons = false
    slash("unlock"); slash("lock")
    check(rawget(timer, "_pass") == SHORT_LIST, "the short list stays for the session")
    slash("debug")
    zone(OUT); tick(3)
end

-------------------------------------------------------------------------------- logout & report
fireEvent("PLAYER_LOGOUT")
check(type(ForeverInstanceTimerCharDB.lastSeen) == "number", "lastSeen saved at logout")

for entry in pairs(unknownReads) do fail("unknown global read: " .. entry) end
for entry in pairs(unknownMethods) do fail("unstubbed method called from our code: " .. entry) end
rawprint(("\nsmoke%s: %d problem(s)"):format(BREAK_SETTINGS and " (broken Settings API)" or "", #failures))
os.exit(#failures == 0 and 0 or 1)
