-- Forever Addon Fixes: fixes Lua errors that other addons throw on WoW Forever, without editing
-- their files.
local ADDON_NAME, ns = ...

local PREFIX = "|cff33ff99Forever Addon Fixes|r: "
local function Print(msg) print(PREFIX .. msg) end
ns.Print = Print

local fixes, byId = {}, {}
ns.fixes = fixes
local db -- ForeverAddonFixesDB, once our saved variables are loaded
local panel = { ok = false, settings = {} } -- the options panel's setting objects, when it was built

function ns.GetDB() return db end
function ns.GetPanel() return panel end

-- True when addon code may read the value. Skips when either check flags it, and an
-- error from a check counts as "not readable".
local function Readable(value)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return false end
    end
    if canaccessvalue then
        local ok, access = pcall(canaccessvalue, value)
        if not ok or not access then return false end
    end
    return true
end
ns.Readable = Readable

-- "a", "a and b", "a, b and c"
local function JoinList(list)
    if #list <= 1 then return list[1] or "no versions" end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end
ns.JoinList = JoinList

-- Counts one skipped message. It never errors and never sees the message itself.
local function CountSkip(fix)
    fix.state.skipped = fix.state.skipped + 1
    if db and db.debug then
        pcall(Print, ("%s (%d this session)"):format(fix.skipText or fix.title, fix.state.skipped))
    end
end

-- def: id, addon, title, description, skipText, testedVersions, versionNote, needed(), install(fix), uninstall(fix)
function ns.RegisterFix(def)
    assert(type(def) == "table" and type(def.id) == "string" and not byId[def.id], "a fix needs a unique id")
    assert(type(def.addon) == "string" and type(def.title) == "string" and type(def.install) == "function",
        "a fix needs an addon, a title and install()")
    def.state = { enabled = true, installed = false, skipped = 0 }
    def.CountSkip = CountSkip
    fixes[#fixes + 1] = def
    byId[def.id] = def
    return def
end

local function Needed(fix) return not fix.needed or fix.needed() end

-- The target's own ADDON_LOADED counts as proof it is loaded: whether IsAddOnLoaded's second
-- value is already true while that event is dispatched is unverified.
local function TargetLoaded(fix)
    if fix.state.targetSeen then return true end
    local _, loaded = C_AddOns.IsAddOnLoaded(fix.addon) -- the second value, as Blizzard's EventUtil uses
    return loaded and true or false
end

-- The target's version, or nil when it has none (shown as "unknown").
local function TargetVersion(fix)
    local version = C_AddOns.GetAddOnMetadata(fix.addon, "Version")
    if type(version) == "string" and version ~= "" then return version end
    return nil
end

local function IsTested(fix, version)
    for _, tested in ipairs(fix.testedVersions or {}) do
        if version and tested == version then return true end
    end
    return false
end

-- The fix's state, in precedence order: the first match wins.
function ns.FixState(fix)
    if not Needed(fix) then return "notneeded" end
    if not fix.state.enabled then return "off" end
    if not TargetLoaded(fix) then return "waiting" end
    if not fix.state.installed then return "notapplied" end
    return "active"
end

function ns.StatusText(fix)
    local state = ns.FixState(fix)
    if state == "notneeded" then return "not needed on this client" end
    if state == "off" then return fix.state.installed and "off (passing through until /reload)" or "off" end
    if state == "waiting" then return "waiting: " .. fix.addon .. " not loaded" end
    if state == "notapplied" then return "not applied: " .. (fix.state.failReason or "not tried yet") end
    local version = TargetVersion(fix)
    local text = ("active (%s %s%s), skipped %d this session"):format(fix.addon, version or "unknown",
        fix.versionNote and ("; " .. fix.versionNote) or "", fix.state.skipped)
    if not IsTested(fix, version) then text = text .. ", untested with this version" end
    return text
end

-- The untested-version notice: a missing version is "unknown", each version is
-- announced once ever, and it is recorded only when the line was actually printed.
local function CheckVersionNotice(fix)
    local version = TargetVersion(fix)
    if IsTested(fix, version) then return end
    local key = version or "unknown"
    local seen = db.noticedVersions[fix.id]
    if seen[key] or not db.notices then return end
    if pcall(Print, ('%s is now %s; "%s" was tested with %s. It is still active. To check whether it\'s still needed, see "Is a fix still needed?" in the Forever Addon Fixes README.'):format(
        fix.addon, key, fix.title, JoinList(fix.testedVersions or {}))) then
        seen[key] = true
    end
end

-- The version check runs only when a fix becomes active, not on a repeated "on".
local function NoteActivation(fix)
    local active = ns.FixState(fix) == "active"
    if active and not fix.state.wasActive then CheckVersionNotice(fix) end
    fix.state.wasActive = active
end

local function TryInstall(fix)
    if fix.state.installed then return true end -- idempotent; also covers a pass-through "off"
    local ok, done, reason = pcall(fix.install, fix)
    if ok and done then
        fix.state.installed, fix.state.failReason = true, nil
        return true
    end
    fix.state.failReason = ok and (reason or "the fix couldn't be put in place") or ("error: " .. tostring(done))
    if db.notices and not fix.state.failureNoticed then -- once per fix per session, once printed
        fix.state.failureNoticed = pcall(Print, ('"%s" is not in place: %s. The fix may no longer be needed.'):format(
            fix.title, fix.state.failReason))
    end
    return false
end

-- Restores the target when the fix can; otherwise its wrapper stays and passes everything through.
local function TryUninstall(fix)
    if not fix.state.installed or not fix.uninstall then return end
    local ok, restored = pcall(fix.uninstall, fix)
    if ok and restored then fix.state.installed = false end
end

local function ActivateIfReady(fix)
    if fix.state.enabled and Needed(fix) and TargetLoaded(fix) then TryInstall(fix) end
    NoteActivation(fix)
end

-- The effects of a fix's switch, from the panel setting's callback or directly without a panel.
-- It must never call SetFixEnabled or SetValue: the callback also fires on unchanged values.
function ns.OnFixSwitched(id, value)
    local fix = byId[id]
    if not fix then return end
    fix.state.enabled = value and true or false
    if fix.state.enabled then ActivateIfReady(fix) else TryUninstall(fix); NoteActivation(fix) end
end

-- The one switch path: through the panel's setting when it exists, so the panel stays
-- in step; otherwise, or if that fails, write the saved setting and apply it directly.
function ns.SetFixEnabled(id, value)
    local fix = byId[id]
    if not fix or not db then return false end
    value = value and true or false
    local setting = panel.ok and panel.settings[id]
    if not (setting and pcall(setting.SetValue, setting, value)) then
        db.fixes[id].enabled = value
        ns.OnFixSwitched(id, value)
    end
    return true
end

function ns.SetOption(key, value)
    if not db or (key ~= "notices" and key ~= "debug") then return false end
    value = value and true or false
    local setting = panel.ok and panel.settings[key]
    if not (setting and pcall(setting.SetValue, setting, value)) then db[key] = value end
    return true
end

-- Fills defaults and repairs wrong types; unknown keys are kept.
function ns.InitDB(saved)
    if type(saved) ~= "table" then saved = {} end
    if type(saved.fixes) ~= "table" then saved.fixes = {} end
    if type(saved.noticedVersions) ~= "table" then saved.noticedVersions = {} end
    for _, fix in ipairs(fixes) do
        if type(saved.fixes[fix.id]) ~= "table" then saved.fixes[fix.id] = {} end
        if type(saved.fixes[fix.id].enabled) ~= "boolean" then saved.fixes[fix.id].enabled = true end
        if type(saved.noticedVersions[fix.id]) ~= "table" then saved.noticedVersions[fix.id] = {} end
    end
    if type(saved.notices) ~= "boolean" then saved.notices = true end
    if type(saved.debug) ~= "boolean" then saved.debug = false end
    return saved
end

local function BuildPanel()
    if not ns.BuildOptions then return end
    local ok, result = pcall(ns.BuildOptions, db)
    if ok then
        panel = { ok = true, categoryID = result.categoryID, settings = result.settings }
    else
        panel = { ok = false, settings = {} }
        pcall(Print, ("the options panel couldn't be built (%s); use /afix status and /afix on|off."):format(tostring(result)))
    end
end

local function StatusLine(i, fix) return ("%d. %s: %s"):format(i, fix.title, ns.StatusText(fix)) end

local function PrintStatus()
    if #fixes == 0 then Print("no fixes are registered.") end
    for i, fix in ipairs(fixes) do Print(StatusLine(i, fix)) end
    Print(("notices %s, debug %s"):format(db.notices and "on" or "off", db.debug and "on" or "off"))
end

local function FindFix(arg)
    local n = tonumber(arg)
    if n then return fixes[n], n end
    for i, fix in ipairs(fixes) do
        if fix.id:lower() == arg then return fix, i end
    end
end

local function OpenOptions()
    if not panel.ok then
        Print("the options panel is unavailable (see the message at login); /afix status and /afix on|off <number> still work.")
        return
    end
    if InCombatLockdown() then
        Print("options can't be opened during combat.")
        return
    end
    local ok, err = pcall(Settings.OpenToCategory, panel.categoryID)
    if not ok then Print("couldn't open the options panel: " .. tostring(err)) end
end

local HELP = {
    "/afix or /afix options - open the options panel",
    "/afix status - each fix and whether it's active",
    "/afix on|off <number> - switch a fix on or off (numbers from /afix status; the fix's id works too)",
    "/afix notices on|off - chat notices about fixes",
    "/afix debug on|off - a chat line every time a fix skips something",
}

function ns.HandleSlash(input)
    if not db then return end
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" or cmd == "options" then
        OpenOptions()
    elseif cmd == "status" then
        PrintStatus()
    elseif cmd == "on" or cmd == "off" then
        local fix, i = FindFix(arg)
        if not fix then
            Print(arg == "" and "which fix? /afix status lists them, for example /afix off 1."
                or ("no fix %s; /afix status lists them."):format(arg))
            return
        end
        ns.SetFixEnabled(fix.id, cmd == "on")
        Print(StatusLine(i, fix)) -- re-read: errors inside the panel's callback are swallowed by the game
    elseif (cmd == "notices" or cmd == "debug") and (arg == "on" or arg == "off") then
        ns.SetOption(cmd, arg == "on")
        Print(("%s %s"):format(cmd, db[cmd] and "on" or "off"))
    else
        for _, line in ipairs(HELP) do Print(line) end
    end
end

SLASH_FOREVERADDONFIXES1 = "/afix"
SLASH_FOREVERADDONFIXES2 = "/addonfixes"
SlashCmdList.FOREVERADDONFIXES = function(input) ns.HandleSlash(input) end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
    for _, fix in ipairs(fixes) do
        if fix.addon == name then fix.state.targetSeen = true end
    end
    if name == ADDON_NAME then
        db = ns.InitDB(ForeverAddonFixesDB)
        ForeverAddonFixesDB = db
        for _, fix in ipairs(fixes) do fix.state.enabled = db.fixes[fix.id].enabled end
        BuildPanel()
        for _, fix in ipairs(fixes) do ActivateIfReady(fix) end
    elseif db then
        for _, fix in ipairs(fixes) do
            if fix.addon == name then ActivateIfReady(fix) end
        end
    end
end)
