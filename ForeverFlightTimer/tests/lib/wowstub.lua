-- Headless WoW harness for smoke tests.
-- * Frame and API stubs. Only globals that exist on the Forever client are stubbed.
-- * Event dispatch, and a clock that only moves in tick(): like GetTime in game, it is
--   constant within one event dispatch.
-- * Guards: unknown global reads/writes and unstubbed methods called from the addon's own files.
-- * Errors routed to geterrorhandler are reported. AceGUI and AceConfigDialog run widget code
--   through xpcall, which is how FIT's first in-game bug hid from its earlier smoke test.
-- * TOC loading, and a routine that renders and uses a real AceConfig options panel.
local W = { failures = {}, chat = {}, now = 1000.0, tooltipLines = {}, timers = {}, restrictedTypes = {} }
local rawprint = print
W.rawprint = rawprint
W.BREAK_SETTINGS = os.getenv("FFT_SMOKE_BREAK_SETTINGS") ~= nil

function W.fail(msg) W.failures[#W.failures + 1] = msg; rawprint("FAIL " .. msg) end
function W.check(cond, msg) if not cond then W.fail(msg) end end
function W.clearChat() W.chat = {} end

function W.chatHas(s)
    for _, m in ipairs(W.chat) do if m:find(s, 1, true) then return true end end
    return false
end

function W.linesHave(s)
    for _, m in ipairs(W.tooltipLines) do if m:find(s, 1, true) then return true end end
    return false
end

-------------------------------------------------------------------------------- frames
-- Stub state lives in "_"-prefixed fields, read with rawget: libraries store their own Lua
-- fields on frames (e.g. Blizzard's legacy options `frame.parent = categoryID`).
local Frame, eventFrames, allFrames = {}, {}, {}
local function noopMethod() end
local KNOWN_OWN_METHODS, OWN_SOURCES = {}, {}
local unknownMethods, unknownReads = {}, {}

local frameMeta = { __index = function(_, k)
    local v = Frame[k]
    if v ~= nil then return v end
    -- Any other widget-API method (CamelCase, like the real API) is a no-op; unknown data
    -- fields stay nil, as on real frames. Unstubbed methods called from our code are reported.
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
W.NewFrame = NewFrame

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
function Frame:GetTextWidth() return #tostring(rawget(self, "_text") or "") * 7 end
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
function Frame:SetFrameLevel(l) rawset(self, "_level", l) end
function Frame:GetFrameLevel() return rawget(self, "_level") or 1 end
function Frame:SetFrameStrata(s) rawset(self, "_strata", s) end
function Frame:GetFrameStrata() return rawget(self, "_strata") or "MEDIUM" end
function Frame:SetAlpha(a) rawset(self, "_alpha", a) end
function Frame:GetAlpha() return rawget(self, "_alpha") or 1 end
function Frame:SetBackdrop(b) rawset(self, "_backdrop", b) end
function Frame:SetValue(v) rawset(self, "_value", v) end
function Frame:GetValue() return rawget(self, "_value") or 0 end
function Frame:SetStatusBarColor(r, g, b, a) rawset(self, "_barColor", { r, g, b, a }) end
function Frame:SetID(id) rawset(self, "_id", id) end
function Frame:GetID() return rawget(self, "_id") or 0 end
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
    if W.combat then W.fail("SetPassThroughButtons called during combat") end
    for t = 0, 4 do
        if W.restrictedTypes[t] then W.fail("SetPassThroughButtons called during restriction type " .. t) end
    end
    local names = { ... }
    if W.rejectLongButtons then
        for _, n in ipairs(names) do
            local k = tonumber(n:match("^Button(%d+)$"))
            if k and k > 5 then error("invalid mouse button " .. n) end
        end
    end
    rawset(self, "_pass", table.concat(names, ","))
end
function Frame:AddMessage(msg) W.chat[#W.chat + 1] = msg end
function Frame:RegisterEvent(e)
    eventFrames[e] = eventFrames[e] or {}
    eventFrames[e][self] = true
end
function Frame:RegisterUnitEvent(e) self:RegisterEvent(e) end
function Frame:UnregisterEvent(e) if eventFrames[e] then eventFrames[e][self] = nil end end
function Frame:IsEventRegistered(e) return eventFrames[e] and eventFrames[e][self] or false end
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

function W.setShownQuiet(f, v) rawset(f, "_shown", v) end -- no OnShow/OnHide
function W.hooks(f) return rawget(f, "_hooks") end

-- A right-click as the engine delivers it: only to a frame that takes clicks and doesn't pass
-- the right button through. Returns whether a menu opened.
function W.rightClick(f)
    W.lastMenu = nil
    if rawget(f, "_click") and not (rawget(f, "_pass") or ""):find("RightButton", 1, true) then
        f:GetScript("OnMouseUp")(f, "RightButton")
    end
    return W.lastMenu ~= nil
end

function W.fireRestriction(restrictionType, state)
    W.restrictionDispatch = true
    W.fireEvent("ADDON_RESTRICTION_STATE_CHANGED", restrictionType, state)
    W.restrictionDispatch = false
end

function W.fireEvent(e, ...)
    local list = {}
    for f in pairs(eventFrames[e] or {}) do list[#list + 1] = f end
    for _, f in ipairs(list) do
        local s = S(f).OnEvent
        if s then s(f, e, ...) end
    end
end

local function runTimers()
    local due = {}
    for i = #W.timers, 1, -1 do
        if W.timers[i].at <= W.now then
            due[#due + 1] = W.timers[i].fn
            table.remove(W.timers, i)
        end
    end
    for i = #due, 1, -1 do due[i]() end
end

function W.tick(seconds)
    for _ = 1, math.floor(seconds / 0.1 + 0.5) do
        W.now = W.now + 0.1
        runTimers()
        for i = 1, #allFrames do
            local f = allFrames[i]
            local s = S(f).OnUpdate
            if s and f:IsVisible() then s(f, 0.1) end
        end
    end
end

-------------------------------------------------------------------------------- stubs
local function noop() end
-- Templates that apply a mixin at creation (mixin="…" in XML) and bind OnEnter once.
W.TEMPLATE_MIXINS = {}
local TEMPLATE_CHILDREN = { "HighlightTexture", "Left", "Middle", "Right", "LeftDisabled",
                            "MiddleDisabled", "RightDisabled", "Text", "Button" }

local tooltip = NewFrame("GameTooltip", "GameTooltip")
rawset(tooltip, "SetOwner", function() W.tooltipLines = {} end)
rawset(tooltip, "SetText", function(_, text) W.tooltipLines = { tostring(text) } end)
rawset(tooltip, "AddLine", function(_, text) W.tooltipLines[#W.tooltipLines + 1] = tostring(text) end)

local categories, nextID = {}, 100
W.STUBS = {
    CreateFrame = function(kind, name, parent, template)
        local f = NewFrame(kind, name, parent)
        if name and template then
            for _, suffix in ipairs(TEMPLATE_CHILDREN) do NewFrame("Texture", name .. suffix, f) end
        end
        local mixinName = template and W.TEMPLATE_MIXINS[template]
        local mixin = mixinName and rawget(_G, mixinName)
        if type(mixin) == "table" then
            for k, v in pairs(mixin) do rawset(f, k, v) end -- copied once, at creation
            f:SetScript("OnEnter", function(self) self:OnMouseEnter() end)
        end
        return f
    end,
    GameTooltip = tooltip,
    ColorPickerFrame = (function()
        local f = NewFrame("Frame")
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
    InCombatLockdown = function() return W.combat == true end,
    C_RestrictedActions = { -- RA:55-67: false for every type while ADDON_RESTRICTION_STATE_CHANGED dispatches
        IsAddOnRestrictionActive = function(t)
            if W.restrictionDispatch then return false end
            return W.restrictedTypes[t] == true
        end,
    },
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
            W.lastMenu = { owner = owner, entries = root.entries }
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
    geterrorhandler = function() return function(e) W.fail("error handler: " .. tostring(e)); return e end end,
    debugstack = function() return "" end,
    issecretvalue = function() return false end,
    C_Timer = {
        After = function(delay, fn) W.timers[#W.timers + 1] = { at = W.now + (delay or 0), fn = fn } end,
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
    GetTime = function() return W.now end,
    GetServerTime = function() return math.floor(W.now) end,
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        W.chat[#W.chat + 1] = table.concat(parts, " ")
    end,
    Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            if W.BREAK_SETTINGS then error("simulated Settings API change") end
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
        OpenToCategory = function(id) W.openedCategory = id end,
    },
}

-------------------------------------------------------------------------------- install & load
function W.install(opts)
    for k, v in pairs(W.STUBS) do rawset(_G, k, v) end
    rawset(_G, "UIParent", NewFrame("Frame", "UIParent"))
    UIParent:SetSize(1920, 1080)
    table.wipe = W.STUBS.wipe       -- WoW adds wipe to the table library
    string.split = W.STUBS.strsplit -- ...and strsplit to the string library
    for _, f in ipairs(opts.own or {}) do OWN_SOURCES["@" .. f .. ".lua"] = true end
    for _, m in ipairs(opts.knownMethods or {}) do KNOWN_OWN_METHODS[m] = true end
    local expectedNil, allowed = {}, {}
    for _, k in ipairs(opts.expectedNil or {}) do expectedNil[k] = true end
    for _, k in ipairs(opts.allowedWrites or {}) do allowed[k] = true end
    setmetatable(_G, {
        __index = function(_, k)
            local info = debug.getinfo(2, "S")
            if info and OWN_SOURCES[info.source] and not expectedNil[k] then
                unknownReads[info.source .. ": " .. tostring(k)] = true
            end
            return nil
        end,
        __newindex = function(t, k, v)
            local info = debug.getinfo(2, "S")
            if info and OWN_SOURCES[info.source] and not allowed[k] then
                W.fail("global write '" .. tostring(k) .. "' from " .. info.source)
            end
            rawset(t, k, v)
        end,
    })
end

function W.loadToc(addon, ns)
    local function loadLua(path)
        local chunk, err = loadfile(path)
        if not chunk then W.fail("compile: " .. tostring(err)); return end
        local ok, e = pcall(chunk, addon, ns)
        if not ok then W.fail("load " .. path .. ": " .. tostring(e)) end
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
    for line in io.lines(addon .. ".toc") do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and not line:find("^#") then
            local p = line:gsub("\\", "/")
            if p:find("%.xml$") then loadXml(p) else loadLua(p) end
        end
    end
end

-------------------------------------------------------------------------------- options panel
-- Validates the options tables; checks preview and the status line; drives every option's
-- get/set; then renders every tab and the Profiles page with real AceGUI widgets and uses each
-- control the way a player would.
function W.exercisePanel(o)
    local check = W.check
    local ACR = LibStub("AceConfigRegistry-3.0")
    local ACD = LibStub("AceConfigDialog-3.0")
    local AceGUI = LibStub("AceGUI-3.0")
    for _, app in ipairs({ o.app, o.profilesApp }) do
        local ok, err = pcall(ACR.GetOptionsTable, ACR, app, "dialog", "AceConfigDialog-3.0")
        check(ok, "options table " .. app .. " validates: " .. tostring(err))
    end

    local page = o.options.frame
    W.setShownQuiet(page, true)
    W.hooks(page).OnShow(page)
    check(o.timer:IsShown() and o.timer:GetFrameStrata() == "FULLSCREEN_DIALOG",
        "preview shows the timer above the settings window")
    local holder = o.options.statusText:GetParent()
    holder:GetScript("OnUpdate")(holder, 1)
    W.statusLine = tostring(o.options.statusText:GetText())
    check(rawget(o.options.statusText, "_wordWrap") == false, "status line never wraps")
    -- Hide the page again before the walk: a visible page makes AceConfigDialog render real
    -- widgets on the tick after a NotifyChange. Keep the preview on directly instead.
    W.setShownQuiet(page, false)
    o.display:SetPreview(true)

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
                        opt.set(info, not orig[1]); W.tick(0.2); opt.set(info, orig[1])
                    elseif opt.type == "select" then
                        local values = type(opt.values) == "function" and opt.values(info) or opt.values
                        for k in pairs(values) do opt.set(info, k); W.tick(0.2) end
                        opt.set(info, orig[1])
                    elseif opt.type == "range" then
                        opt.set(info, opt.softMin or opt.min); W.tick(0.2)
                        opt.set(info, opt.softMax or opt.max); W.tick(0.2)
                        opt.set(info, orig[1])
                    elseif opt.type == "color" then
                        opt.set(info, 0.1, 0.2, 0.3, 0.4); W.tick(0.2); opt.set(info, unpack(orig))
                    end
                end)
                check(ok, here .. ": " .. tostring(err))
            end
        end
    end
    walk(ACR:GetOptionsTable(o.app, "dialog", "AceConfigDialog-3.0"), "options")
    W.hooks(page).OnHide(page)
    check(o.timer:GetFrameStrata() == "MEDIUM", "preview ends when the settings page hides")

    local created, origCreate = {}, AceGUI.Create
    AceGUI.Create = function(self, widgetType, ...)
        created[widgetType] = (created[widgetType] or 0) + 1
        return origCreate(self, widgetType, ...)
    end
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
            script(w.button, "OnClick")(w.button)
            script(w.button, "OnClick")(w.button)
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
    -- Most changes make AceConfigDialog rebuild the page at once: every widget goes back to
    -- AceGUI's pools and comes out again in a different order. So widget objects can't be held
    -- across a use, but index paths can (the rebuilt page has the same layout): walk by path and
    -- resolve each widget from the page's root.
    local function useAll(label, root)
        local function at(path)
            local w = root
            for _, i in ipairs(path) do
                w = w.children and w.children[i]
                if not w then return nil end
            end
            return w
        end
        local function walk(path)
            local i = 1
            while true do
                local here = { unpack(path) }
                here[#here + 1] = i
                local w = at(here)
                if not w then return end
                local ok, err = pcall(useWidget, w)
                check(ok, "use " .. label .. " " .. tostring(w.type) .. ": " .. tostring(err))
                W.tick(0.2)
                local after = at(here)
                if after and after.children then walk(here) end
                i = i + 1
            end
        end
        walk({})
    end
    local function render(label, fn)
        local ok, err = pcall(function() fn(); W.tick(0.5) end)
        check(ok, "render " .. label .. ": " .. tostring(err))
    end
    render("main page", function() page:Show() end)
    useAll("first tab", page.obj)
    for _, tab in ipairs(o.tabs) do
        render(tab .. " tab", function() ACD:SelectGroup(o.app, tab) end)
        useAll(tab .. " tab", page.obj)
    end
    render("refresh while open (NotifyChange)", function() o.options:Refresh() end)
    render("hide main page", function() page:Hide() end)
    local profiles = o.options.profilesFrame
    render("Profiles page", function() profiles:Show() end)
    useAll("Profiles page", profiles.obj)
    render("hide Profiles page", function() profiles:Hide() end)
    AceGUI.Create = origCreate
    for _, t in ipairs(o.expectUsed or {}) do check(used[t], "interacted with a " .. t .. " widget") end
    for _, t in ipairs(o.expectCreated or {}) do check((created[t] or 0) > 0, "render built at least one " .. t .. " widget") end
end

function W.report(label)
    for entry in pairs(unknownReads) do W.fail("unknown global read: " .. entry) end
    for entry in pairs(unknownMethods) do W.fail("unstubbed method called from our code: " .. entry) end
    rawprint(("\n%s%s: %d problem(s)"):format(label, W.BREAK_SETTINGS and " (broken Settings API)" or "", #W.failures))
    os.exit(#W.failures == 0 and 0 or 1)
end

return W
