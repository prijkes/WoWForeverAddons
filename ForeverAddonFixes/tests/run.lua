-- Offline unit-test runner. From the addon root:  luajit tests/run.lua [filter]
package.path = "tests/lib/?.lua;" .. package.path
local T = require("testlib")

local SUITES = {
    "tests/test_Core.lua",
    "tests/test_Fix.lua",
    "tests/test_FixAtlasLoot.lua",
    "tests/test_Options.lua",
}

local filter = arg and arg[1]
for _, path in ipairs(SUITES) do
    if not filter or path:find(filter, 1, true) then
        local f = io.open(path, "r")
        if f then
            f:close()
            T.suite(path)
            local chunk, err = loadfile(path)
            if chunk then
                local ok, suiteErr = pcall(chunk, T)
                if not ok then -- a suite that errors outside T.test counts as one failure
                    T.failed = T.failed + 1
                    T.failures[#T.failures + 1] = path .. " :: suite error\n    " .. tostring(suiteErr)
                end
            else
                T.failed = T.failed + 1
                T.failures[#T.failures + 1] = path .. " :: load error\n    " .. tostring(err)
            end
        else
            T.failed = T.failed + 1
            T.failures[#T.failures + 1] = path .. " :: missing"
        end
    end
end

os.exit(T.report() and 0 or 1)
