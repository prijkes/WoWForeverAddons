-- Compiles every .lua file given on the command line, and lints the addon's own files for
-- syntax LuaJIT accepts but WoW's Lua 5.1 rejects.
-- Usage (addon root):  luajit tests/lint51.lua $(find . -name "*.lua" | sort)
local OWN = {
    ["TimeFormat.lua"] = true, ["Clock.lua"] = true, ["ZoneWatcher.lua"] = true,
    ["RunTracker.lua"] = true, ["Defaults.lua"] = true, ["Display.lua"] = true,
    ["Options.lua"] = true, ["Core.lua"] = true,
}
local BANNED = {
    { "%f[%w_]goto%f[^%w_]", "goto (Lua 5.2+)" },
    { "::[%a_][%w_]*::", "label (Lua 5.2+)" },
    { "\\u{", "\\u{...} escape (Lua 5.3+)" },
    { "\\z", "\\z escape (Lua 5.2+)" },
    { "\\x%x%x", "\\x escape (Lua 5.2+)" },
}

-- Globals that do not exist on the WoW Forever client (Midnight / 12.1 FrameXML). Any file
-- that reads one would error at runtime. Detected from bytecode (GGET), so comments and
-- strings never trigger it.
local REMOVED_GLOBALS = {
    SetDesaturation = "removed in WoW 12.1; use texture:SetDesaturated() (Ace3 r1403 fixed AceGUI's CheckBox)",
}

local function globalReads(path)
    local names = {}
    local p = io.popen('luajit -bl "' .. path .. '" 2>&1')
    if not p then return names end
    for line in p:lines() do
        local name = line:match('GGET%s+%d+%s+%d+%s+; "([^"]+)"')
        if name then names[name] = true end
    end
    p:close()
    return names
end

local problems, checked = 0, 0
for _, path in ipairs(arg) do
    checked = checked + 1
    local chunk, err = loadfile(path)
    if not chunk then
        problems = problems + 1
        print("COMPILE " .. tostring(err))
    end
    for name in pairs(globalReads(path)) do
        if REMOVED_GLOBALS[name] then
            problems = problems + 1
            print(("REMOVED %s reads global %s: %s"):format(path, name, REMOVED_GLOBALS[name]))
        end
    end
    local dir, base = path:match("^(.-)[/\\]?([^/\\]+)$")
    if OWN[base] and (dir == "." or dir == "") then
        local n = 0
        for line in io.lines(path) do
            n = n + 1
            for _, rule in ipairs(BANNED) do
                if line:find(rule[1]) then
                    problems = problems + 1
                    print(("LUA51 %s:%d: %s"):format(path, n, rule[2]))
                end
            end
        end
    end
end
print(("%d files checked, %d problems"):format(checked, problems))
os.exit(problems == 0 and 0 or 1)
