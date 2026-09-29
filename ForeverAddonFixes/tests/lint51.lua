-- Compiles every .lua file given on the command line, and lints the addon's own files for
-- syntax LuaJIT accepts but WoW's Lua 5.1 rejects, and for globals the client no longer has.
-- Usage (addon root):  luajit tests/lint51.lua $(find . -name "*.lua" | sort)
-- Our own files: every .lua outside tests/, so a new Fixes/<Addon>.lua is covered automatically.
local function IsOwn(rel) return not rel:find("^tests/") end
local BANNED = {
    { "%f[%w_]goto%f[^%w_]", "goto (Lua 5.2+)" },
    { "::[%a_][%w_]*::", "label (Lua 5.2+)" },
    { "\\u{", "\\u{...} escape (Lua 5.3+)" },
    { "\\z", "\\z escape (Lua 5.2+)" },
    { "\\x%x%x", "\\x escape (Lua 5.2+)" },
}

-- Globals that do not exist on the WoW Forever client (Midnight / 12.1 FrameXML). Detected from
-- bytecode (GGET), so comments and strings never trigger it.
local REMOVED_GLOBALS = {
    SetDesaturation = "removed in WoW 12.1; use texture:SetDesaturated()",
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

local problems, checked, own = 0, 0, 0
for _, path in ipairs(arg) do
    checked = checked + 1
    local chunk, err = loadfile(path)
    if not chunk then
        problems = problems + 1
        print("COMPILE " .. tostring(err))
    end
    local rel = path:gsub("\\", "/"):gsub("^%./", "")
    if IsOwn(rel) then
        own = own + 1
        for name in pairs(globalReads(path)) do
            if REMOVED_GLOBALS[name] then
                problems = problems + 1
                print(("REMOVED %s reads global %s: %s"):format(path, name, REMOVED_GLOBALS[name]))
            end
        end
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
if own == 0 then
    problems = problems + 1
    print("no own files seen: pass every .lua file")
end
print(("%d files checked (%d own), %d problems"):format(checked, own, problems))
os.exit(problems == 0 and 0 or 1)
