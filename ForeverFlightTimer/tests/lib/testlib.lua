-- Minimal test framework for the offline suite (LuaJIT / Lua 5.1).
local T = { passed = 0, failed = 0, failures = {}, current = "" }

function T.suite(name)
    T.current = name
    print("== " .. name)
end

function T.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = T.current .. " :: " .. name .. "\n    " .. tostring(err)
        print("  FAIL " .. name .. "\n    " .. tostring(err))
    end
end

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function T.near(actual, expected, eps, msg)
    eps = eps or 1e-6
    if type(actual) ~= "number" or math.abs(actual - expected) > eps then
        error((msg and (msg .. ": ") or "") .. "expected ~" .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function T.truthy(v, msg)
    if not v then error((msg or "expected truthy") .. ", got " .. fmt(v), 2) end
end

function T.falsy(v, msg)
    if v then error((msg or "expected falsy") .. ", got " .. fmt(v), 2) end
end

function T.report()
    print(string.format("\n%d passed, %d failed", T.passed, T.failed))
    for _, f in ipairs(T.failures) do print("FAILED: " .. f) end
    return T.failed == 0
end

return T
