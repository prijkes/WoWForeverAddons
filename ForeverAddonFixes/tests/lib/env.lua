-- A stub WoW environment for the offline tests. Every E.new() builds a fresh global table, so
-- tests (and GearQuest's own globals) never leak into each other. Addon files load through
-- setfenv with the (addonName, namespace) varargs the client passes.
local E = {}

-- The addon's files in load order, read from the toc (run from the addon folder), so the tests
-- always load exactly what the client does and a new fix file can't be left out.
local function TocFiles()
    local files = {}
    for line in io.lines("ForeverAddonFixes.toc") do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:find("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    assert(#files > 0, "no files listed in ForeverAddonFixes.toc")
    return files
end
E.ADDON_FILES = TocFiles()

-- An emulated secret string. Anything but passing it around or a truth test errors, as with a
-- real secret in addon code. Unlike a real secret, type() says "table", so the addon must never
-- branch on type(msg).
local SECRET_MT = {}
local function SecretError(what) return function() error("attempt to " .. what .. " a secret string value", 2) end end
SECRET_MT.__index = SecretError("index")
SECRET_MT.__newindex = SecretError("index")
SECRET_MT.__tostring = SecretError("convert")
SECRET_MT.__concat = SecretError("concatenate")
SECRET_MT.__len = SecretError("get the length of")
SECRET_MT.__call = SecretError("call")
SECRET_MT.__lt = SecretError("compare")
SECRET_MT.__le = SecretError("compare")

local W = {}
W.__index = W

-- A recording Settings API that copies the real behaviour: the change callback
-- fires even on an unchanged SetValue, the default is written only when the value is nil,
-- duplicate variable names throw, and a callback error doesn't stop the others: the real client
-- reports it and carries on, so the stub records it in S.callbackErrors for the tests to check.
-- mode: nil | "throw" | "latethrow" | "wrongcategory" | "wrongsetting" | "wronginitializer" | "noid"
function E.newSettings(mode)
    local S = { VarType = { Boolean = "boolean" }, registry = {}, callbacks = {}, log = {},
        categories = {}, registered = {}, opened = nil, settingCount = 0, setCalls = {}, callbackErrors = {} }
    local nextID = 1000

    local function NewCategory(name)
        nextID = nextID + 1
        local c = { name = name, ID = nextID, settings = {}, initializers = {} }
        function c:GetName() return self.name end
        function c:GetID() return self.ID end
        return c
    end

    local function NewSetting(category, variable, key, tbl, name, default)
        local s = { variable = variable, key = key, tbl = tbl, name = name, default = default, category = category }
        function s:GetVariable() return self.variable end
        function s:GetValue() return self.tbl[self.key] end
        function s:SetValue(value)
            S.setCalls[self.variable] = (S.setCalls[self.variable] or 0) + 1
            self.tbl[self.key] = value
            for _, cb in ipairs(S.callbacks[self.variable] or {}) do
                local ok, err = pcall(cb, self, value)
                if not ok then S.callbackErrors[#S.callbackErrors + 1] = err end
            end
        end
        function s:SetValueChangedCallback(cb)
            S.callbacks[self.variable] = S.callbacks[self.variable] or {}
            table.insert(S.callbacks[self.variable], cb)
        end
        return s
    end

    -- Another addon's objects, which a failed registration may hand back.
    S.otherCategory = NewCategory("Some Other Addon")
    S.otherSetting = NewSetting(S.otherCategory, "SomeOtherAddon_option", "option", {}, "Other", true)

    function S.RegisterVerticalLayoutCategory(name)
        S.log[#S.log + 1] = "RegisterVerticalLayoutCategory"
        if mode == "throw" then error("Settings exploded") end
        if mode == "wrongcategory" then return S.otherCategory end
        local c = NewCategory(name)
        if mode == "noid" then c.ID = nil end
        S.categories[#S.categories + 1] = c
        return c
    end

    function S.RegisterAddOnSetting(category, variable, key, tbl, varType, name, default)
        S.log[#S.log + 1] = "RegisterAddOnSetting " .. tostring(variable)
        if S.registry[variable] then error(("Setting variable '%s' was previously registered."):format(variable)) end
        assert(type(tbl) == "table", "'variableTbl' argument must be a table.")
        assert(varType == "boolean", "unexpected variable type")
        S.settingCount = S.settingCount + 1
        if mode == "latethrow" and S.settingCount == 2 then error("late Settings failure") end
        if mode == "wrongsetting" then return S.otherSetting end
        if tbl[key] == nil then tbl[key] = default end
        local s = NewSetting(category, variable, key, tbl, name, default)
        S.registry[variable] = s
        category.settings[#category.settings + 1] = s
        return s
    end

    function S.CreateCheckbox(category, setting, tooltip)
        S.log[#S.log + 1] = "CreateCheckbox " .. tostring(setting and setting.variable)
        local init = { setting = mode == "wronginitializer" and S.otherSetting or setting, tooltip = tooltip }
        function init:GetSetting() return self.setting end
        category.initializers[#category.initializers + 1] = init
        return init
    end

    function S.RegisterAddOnCategory(category)
        S.log[#S.log + 1] = "RegisterAddOnCategory"
        S.registered[#S.registered + 1] = category
    end

    function S.OpenToCategory(id) S.opened = id end

    -- The panel's Defaults button, "These Settings".
    function S.ResetToDefaults(category)
        for _, s in ipairs(category.settings) do s:SetValue(s.default) end
    end

    return S
end

-- opts.settings: false for no Settings API, or a mode for E.newSettings.
function E.new(opts)
    opts = opts or {}
    local env = {}
    for k, v in pairs(_G) do env[k] = v end -- the Lua standard library...
    -- ...minus what the WoW client doesn't give addons (its own Lua code uses none of these)
    for _, name in ipairs({ "arg", "io", "os", "debug", "jit", "package", "require", "loadfile", "dofile", "module" }) do
        env[name] = nil
    end
    env._G = env
    local w = setmetatable({ env = env, prints = {}, frames = {}, loaded = {}, loading = {}, versions = {},
        combat = false, timers = {}, secrets = setmetatable({}, { __mode = "k" }) }, W)

    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        w.prints[#w.prints + 1] = table.concat(parts, " ")
    end
    env.CreateFrame = function()
        local f = { scripts = {}, events = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterEvent(e) self.events[e] = nil end
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:GetScript(k) return self.scripts[k] end
        w.frames[#w.frames + 1] = f
        return f
    end
    env.C_AddOns = {
        IsAddOnLoaded = function(name) -- loadedOrLoading, loaded
            local l = w.loaded[name] == true
            return l or w.loading[name] == true, l
        end,
        GetAddOnMetadata = function(name, field) if field == "Version" then return w.versions[name] end end,
    }
    env.InCombatLockdown = function() return w.combat end
    -- The docs mark the argument non-nilable; the stub is strict about it.
    env.issecretvalue = function(v)
        if v == nil then error("bad argument #1 to 'issecretvalue' (value expected)", 2) end
        return w.secrets[v] == true
    end
    env.canaccessvalue = function(v)
        if v == nil then error("bad argument #1 to 'canaccessvalue' (value expected)", 2) end
        return w.secrets[v] ~= true
    end
    env.SlashCmdList = {}
    env.C_Timer = { After = function(delay, fn) w.timers[#w.timers + 1] = { delay = delay, fn = fn } end }
    env.time = function() return 1790000000 end -- fixed: GearQuest stores it with crafted items
    env.strtrim = function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
    env.format = string.format -- the client's global alias
    -- The client's strsplit; like the real one, it can't convert a secret to a string. Unlike the
    -- real one, it treats the delimiter as one substring rather than a set of separator characters
    -- (the same for the single "-" the tests need).
    env.strsplit = function(delimiter, s, pieces)
        if w.secrets[s] then error("attempt to perform string conversion on a secret string value", 2) end
        s = tostring(s)
        local out, start = {}, 1
        while true do
            local i = s:find(delimiter, start, true)
            if not i or (pieces and #out == pieces - 1) then out[#out + 1] = s:sub(start); break end
            out[#out + 1] = s:sub(start, i - 1)
            start = i + #delimiter
        end
        return unpack(out)
    end
    env.UnitGUID = function() return "Player-1-0000ABCD" end
    env.GetItemInfo = function() return nil end
    if opts.settings ~= false then
        w.S = E.newSettings(opts.settings)
        env.Settings = w.S
    end
    return w
end

function W:secret()
    local s = setmetatable({}, SECRET_MT)
    self.secrets[s] = true
    return s
end

function W:loadFiles(addonName, ns, files, dir)
    for _, file in ipairs(files) do
        local path = dir and (dir .. "/" .. file) or file
        local chunk = assert(loadfile(path))
        setfenv(chunk, self.env)
        chunk(addonName, ns)
    end
    return ns
end

function W:fire(event, ...)
    for _, f in ipairs(self.frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- Loads our files (opts.files, default all), runs opts.beforeLoad(ns) to register test fixes,
-- then assigns the saved variables and fires our ADDON_LOADED, in the client's order.
function W:loadOurs(opts)
    opts = opts or {}
    local ns = {}
    self:loadFiles("ForeverAddonFixes", ns, opts.files or E.ADDON_FILES, opts.dir)
    if opts.beforeLoad then opts.beforeLoad(ns, self) end
    self.env.ForeverAddonFixesDB = opts.saved
    self.loaded.ForeverAddonFixes = true
    self:fire("ADDON_LOADED", "ForeverAddonFixes")
    self.ns = ns
    return ns
end

-- Marks an addon loaded (with an optional version) and fires its ADDON_LOADED. With late = true,
-- IsAddOnLoaded reports it as only "loading" during its own ADDON_LOADED and loaded afterwards,
-- a timing that can't be ruled out offline.
function W:loadTarget(name, version, late)
    self.versions[name] = version
    if late then self.loading[name] = true else self.loaded[name] = true end
    self:fire("ADDON_LOADED", name)
    self.loading[name] = nil
    self.loaded[name] = true
end

function W:slash(input) return self.env.SlashCmdList.FOREVERADDONFIXES(input) end

function W:clearPrints() self.prints = {} end

function W:printsMatching(pattern)
    local n = 0
    for _, line in ipairs(self.prints) do if line:find(pattern) then n = n + 1 end end
    return n
end

function W:lastPrint() return self.prints[#self.prints] end

function E.deepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[E.deepCopy(k)] = E.deepCopy(v) end
    return c
end

-- A list of differences between two values ("" paths), comparing tables structurally.
function E.deepDiff(a, b, path, diffs)
    path, diffs = path or "root", diffs or {}
    if type(a) ~= type(b) then
        diffs[#diffs + 1] = path .. ": " .. type(a) .. " vs " .. type(b)
    elseif type(a) == "table" then
        local keys = {}
        for k in pairs(a) do keys[k] = true end
        for k in pairs(b) do keys[k] = true end
        for k in pairs(keys) do E.deepDiff(a[k], b[k], path .. "." .. tostring(k), diffs) end
    elseif a ~= b then
        diffs[#diffs + 1] = path .. ": " .. tostring(a) .. " vs " .. tostring(b)
    end
    return diffs
end

-- True when a value is reachable from a table (used to prove a secret is never stored).
function E.holds(t, needle, seen)
    seen = seen or {}
    if t == needle then return true end
    if type(t) ~= "table" or seen[t] then return false end
    seen[t] = true
    for k, v in pairs(t) do
        if rawequal(k, needle) or rawequal(v, needle) then return true end
        if E.holds(k, needle, seen) or E.holds(v, needle, seen) then return true end
    end
    return false
end

return E
