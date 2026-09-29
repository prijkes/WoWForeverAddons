-- Pure: learned flight times, keyed by path. No WoW APIs.
local _, ns = ...

local RouteStore = {}
RouteStore.__index = RouteStore
ns.RouteStore = RouteStore

local MAX_SAMPLES = 3

local function isNum(v) return type(v) == "number" and v == v end

local function median(samples)
    local n = #samples
    if n == 0 then return nil end
    local c = {}
    for i = 1, n do c[i] = samples[i] end
    table.sort(c)
    if n % 2 == 1 then return c[(n + 1) / 2] end
    return (c[n / 2] + c[n / 2 + 1]) / 2
end

local function validSamples(s)
    if type(s) ~= "table" or #s < 1 then return false end
    for i = 1, #s do
        if not isNum(s[i]) or s[i] <= 0 then return false end
    end
    return true
end

-- Removes malformed entries in place; returns how many were dropped.
function RouteStore.Validate(tbl)
    local dropped = 0
    for key, r in pairs(tbl) do
        local ok = type(key) == "string" and type(r) == "table" and validSamples(r.samples)
            and type(r.fromName) == "string" and type(r.toName) == "string"
        if ok then
            while #r.samples > MAX_SAMPLES do table.remove(r.samples, 1) end
            if not isNum(r.flights) then r.flights = #r.samples end
            if r.hops ~= nil and not isNum(r.hops) then r.hops = nil end
        else
            tbl[key] = nil -- clearing fields during traversal is allowed
            dropped = dropped + 1
        end
    end
    return dropped
end

function RouteStore.New(tbl)
    local self = setmetatable({ routes = tbl }, RouteStore)
    self.dropped = RouteStore.Validate(tbl)
    return self
end

function RouteStore:Expected(key)
    local r = key and self.routes[key]
    return r and median(r.samples) or nil
end

function RouteStore:Record(key, fromName, toName, hops, duration)
    local r = self.routes[key]
    local newRoute = r == nil
    if newRoute then
        r = { samples = {}, flights = 0 }
        self.routes[key] = r
    end
    r.fromName, r.toName, r.hops = fromName, toName, hops
    r.samples[#r.samples + 1] = duration
    while #r.samples > MAX_SAMPLES do table.remove(r.samples, 1) end
    r.flights = (r.flights or 0) + 1
    return newRoute
end

function RouteStore:Forget()
    for key in pairs(self.routes) do self.routes[key] = nil end
end

function RouteStore:Count()
    local n = 0
    for _ in pairs(self.routes) do n = n + 1 end
    return n
end

function RouteStore:List()
    local list = {}
    for key, r in pairs(self.routes) do
        list[#list + 1] = { key = key, fromName = r.fromName, toName = r.toName, hops = r.hops,
                            expected = median(r.samples), flights = r.flights }
    end
    table.sort(list, function(a, b)
        if a.fromName ~= b.fromName then return a.fromName < b.fromName end
        if a.toName ~= b.toName then return a.toName < b.toName end
        return a.key < b.key
    end)
    return list
end
