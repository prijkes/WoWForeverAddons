-- The options panel: a native Settings category with one checkbox per fix and two
-- general checkboxes. Registrations return their results through one shared Blizzard delegate,
-- which may still hold another call's objects after a failure, so every object is checked right
-- after the call that returns it, before it is used.
local _, ns = ...

local CATEGORY_NAME = "Forever Addon Fixes"

local function VariableName(id)
    return "ForeverAddonFixes_fix_" .. (id:gsub("[^%w]", "_"))
end

local function FixTooltip(fix)
    return ("%s\n\nAddon: %s. Tested with %s%s.\nType /afix status to see whether it's active and how many times it skipped."):format(
        fix.description or "", fix.addon, ns.JoinList(fix.testedVersions or {}),
        fix.versionNote and (" (" .. fix.versionNote .. ")") or "")
end

-- Returns { categoryID, settings = { [fix id | "notices" | "debug"] = setting } }; errors on failure.
function ns.BuildOptions(db)
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
        and Settings.CreateCheckbox and Settings.RegisterAddOnCategory and Settings.VarType) then
        error("the game's Settings API is missing", 0)
    end

    local category = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
    if type(category) ~= "table" or type(category.GetName) ~= "function" or category:GetName() ~= CATEGORY_NAME
        or type(category.GetID) ~= "function" or category:GetID() == nil then
        error("the settings category wasn't created", 0)
    end

    local settings = {}
    local function AddCheckbox(key, variable, variableKey, variableTbl, label, default, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl,
            Settings.VarType.Boolean, label, default)
        if type(setting) ~= "table" or type(setting.GetVariable) ~= "function" or setting:GetVariable() ~= variable then
            error(("the setting %s wasn't created"):format(variable), 0)
        end
        local initializer = Settings.CreateCheckbox(category, setting, tooltip)
        if type(initializer) ~= "table" or type(initializer.GetSetting) ~= "function" or initializer:GetSetting() ~= setting then
            error(("the checkbox for %s wasn't created"):format(variable), 0)
        end
        if onChange then setting:SetValueChangedCallback(onChange) end -- only after the checks
        settings[key] = setting
    end

    for _, fix in ipairs(ns.fixes) do
        local id = fix.id
        AddCheckbox(id, VariableName(id), "enabled", db.fixes[id], fix.title, true, FixTooltip(fix),
            function(_, value) ns.OnFixSwitched(id, value) end)
    end
    AddCheckbox("notices", "ForeverAddonFixes_notices", "notices", db, "Chat notices", true,
        "A chat line when a fix can't be put in place, or when its addon has a version the fix wasn't tested with.")
    AddCheckbox("debug", "ForeverAddonFixes_debug", "debug", db, "Debug: report skips", false,
        "A chat line every time a fix skips something. What was hidden is never shown.")

    Settings.RegisterAddOnCategory(category) -- last, so a failed build leaves no half-built panel
    return { categoryID = category:GetID(), settings = settings }
end
