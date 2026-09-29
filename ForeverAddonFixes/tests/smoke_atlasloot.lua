-- Smoke test against AtlasLoot's real Data/VendorPrice.lua (cases 1-6).
-- From the addon root:  luajit tests/smoke_atlasloot.lua
-- Another AtlasLoot copy:  AFIX_AL_PATH=<AtlasLootClassic folder> luajit tests/smoke_atlasloot.lua
package.path = "tests/lib/?.lua;" .. package.path
local E = require("env")

local AL = os.getenv("AFIX_AL_PATH") or "../AtlasLootClassic"
local ID = "AtlasLootClassic.hiddenVendor"
local CREATURE = "Creature-0-4461-0-12-5120-00001ABCDE"  -- NPC 5120
local PLAYER = "Player-4461-0ABCDEF1"
local ITEM = 1001                                        -- sold for 5 Burning Blossoms (item 23247)

local checks, problems = 0, 0
local function check(ok, what)
    checks = checks + 1
    if not ok then problems = problems + 1; print("PROBLEM: " .. what) end
end

-- The Forever toc when it exists (the one the Forever client most likely loads), else the generic one.
local function TocVersion(dir)
    local f = io.open(dir .. "/AtlasLootClassic_Forever.toc", "r") or io.open(dir .. "/AtlasLootClassic.toc", "r")
    if not f then return nil end
    for line in f:lines() do
        local v = line:match("^## Version:%s*(.-)%s*$")
        if v then f:close(); return v end
    end
    f:close()
end

local VERSION = TocVersion(AL)
if not VERSION or not io.open(AL .. "/Data/VendorPrice.lua", "r") then
    print("SKIP: no AtlasLootClassic with Data/VendorPrice.lua at " .. AL)
    os.exit(0)
end
print(("AtlasLoot %s at %s"):format(VERSION, AL))

-- A world with AtlasLoot's real VendorPrice.lua. AtlasLoot captures UnitGUID, the merchant
-- functions and GetItemInfoInstant as locals when the file loads, so the stubs read world state
-- (w.target, w.merchant) that tests change later. opts: withFix, oursFirst, lateLoadedFlag.
local function World(opts)
    opts = opts or {}
    local w = E.new()
    w.target = nil
    w.merchant = { { itemID = ITEM, costs = { { texture = 136999, value = 5, link = "item:23247", name = "Burning Blossom" } } } }
    local env = w.env
    env.UnitGUID = function(unit) if unit == "target" then return w.target end end
    env.GetMerchantNumItems = function() return #w.merchant end
    env.GetMerchantItemID = function(i) return w.merchant[i] and w.merchant[i].itemID end
    env.GetMerchantItemCostInfo = function(i) return #w.merchant[i].costs end
    env.GetMerchantItemCostItem = function(i, c)
        local cost = w.merchant[i].costs[c]
        return cost.texture, cost.value, cost.link, cost.name
    end
    env.C_Item = { GetItemInfoInstant = function(link) return tonumber(tostring(link):match("item:(%d+)")) end }
    env.C_CurrencyInfo = { GetCoinTextureString = function(v) return tostring(v) end, GetCurrencyInfo = function() return nil end }
    local atlasLoot = {
        Data = {}, Locales = setmetatable({}, { __index = function(_, k) return k end }),
        BC_VERSION_NUM = 2, WRATH_VERSION_NUM = 3,
        dbGlobal = { VendorPrice = {} },
        Addons = { GetAddon = function() return nil end },
    }
    function atlasLoot:GameVersion_GE() return false end
    -- Behaves like AtlasLoot's helper of that name, which VendorPrice.lua calls when it loads: it
    -- returns a merged price table, and a table where assigning a game version's prices adds them
    -- to the merged one.
    function atlasLoot:GetGameVersionDataTable()
        local merged = {}
        local byVersion = setmetatable({}, { __newindex = function(_, _, prices)
            for itemID, price in pairs(prices) do merged[itemID] = price end
        end })
        return merged, byVersion
    end
    env.AtlasLoot = atlasLoot
    local function LoadAtlasLoot()
        w:loadFiles("AtlasLootClassic", {}, { "Data/VendorPrice.lua" }, AL)
        w:loadTarget("AtlasLootClassic", VERSION, opts.lateLoadedFlag)
    end
    if opts.oursFirst then
        w:loadOurs()
        w.statusBefore = w.ns.StatusText(w.ns.fixes[2])
        LoadAtlasLoot()
    else
        LoadAtlasLoot()
        w.alOriginal = atlasLoot.Data.VendorPrice.ScanShownVendor
        if opts.withFix then w:loadOurs() end
    end
    function w:merchantShow() return pcall(self.fire, self, "MERCHANT_SHOW") end
    function w:fix() return self.ns and self.ns.fixes[2] end
    function w:prices() return atlasLoot.dbGlobal.VendorPrice end
    return w
end

local function RaisesSecret(w)
    w.target = w:secret()
    local ok, err = w:merchantShow()
    w.target = nil
    return not ok and tostring(err):find("secret", 1, true) ~= nil, err
end

-- 1. Red: without our addon, AtlasLoot's real scan throws on a hidden vendor.
do
    local w = World()
    local red, err = RaisesSecret(w)
    check(red, "case 1: expected AtlasLoot's secret error without the fix, got " .. tostring(err))
    check(tostring(err):find("VendorPrice.lua:988", 1, true) ~= nil, "case 1: the error should come from VendorPrice.lua:988: " .. tostring(err))
end

-- 2. Green: with our addon, the hidden vendor is skipped.
do
    local w = World({ withFix = true })
    w.target = w:secret()
    check(w:merchantShow(), "case 2: a hidden vendor still raised an error")
    w.target = nil
    check(w:fix().state.skipped == 1, "case 2: skipped should be 1, is " .. w:fix().state.skipped)
    check(next(w:prices()) == nil, "case 2: a skipped visit recorded prices")
    collectgarbage(); collectgarbage()
    check(next(w.secrets) == nil, "case 2: a skipped GUID is still referenced somewhere")
end

-- 3. Differential pass-through, in two fresh environments (AtlasLoot scans each vendor once per session).
do
    local a, b = World(), World({ withFix = true })
    for _, w in ipairs({ a, b }) do
        w.target = CREATURE
        check(w:merchantShow(), "case 3: a readable vendor raised an error")
    end
    local diffs = E.deepDiff(a:prices(), b:prices(), "VendorPrice")
    check(#diffs == 0, "case 3: prices differ: " .. table.concat(diffs, "; "))
    check(a:prices()[ITEM] == "burningblossom:5", "case 3: AtlasLoot didn't record the price, so the comparison proves nothing: " .. tostring(a:prices()[ITEM]))
    check(b:fix().state.skipped == 0, "case 3: a readable vendor was counted as skipped")
end

-- 3b. A skip doesn't lock the vendor: a later readable visit still records prices.
do
    local w = World({ withFix = true })
    w.target = w:secret()
    check(w:merchantShow(), "case 3b: the hidden visit raised an error")
    w.target = CREATURE
    check(w:merchantShow(), "case 3b: the readable visit raised an error")
    check(w:prices()[ITEM] == "burningblossom:5", "case 3b: the readable visit after a skip recorded nothing")
    check(w:fix().state.skipped == 1, "case 3b: skipped should be 1")
end

-- 3c. A readable player target: AtlasLoot finds no NPC ID; nothing recorded, nothing skipped.
do
    local w = World({ withFix = true })
    w.target = PLAYER
    check(w:merchantShow(), "case 3c: a player target raised an error")
    check(next(w:prices()) == nil, "case 3c: a player target recorded prices")
    check(w:fix().state.skipped == 0, "case 3c: a player target was counted as skipped")
end

-- 4. Off restores AtlasLoot's own function and brings the error back; on fixes it, one wrapper.
do
    local w = World({ withFix = true })
    local vendorPrice = w.env.AtlasLoot.Data.VendorPrice
    w:slash("off 2")
    check(vendorPrice.ScanShownVendor == w.alOriginal, "case 4: off didn't restore AtlasLoot's function")
    check((RaisesSecret(w)), "case 4: off should bring the error back")
    w:slash("on 2")
    w.target = w:secret()
    check(w:merchantShow(), "case 4: on should fix it again")
    w.target = nil
    w:slash("off 2")
    check(vendorPrice.ScanShownVendor == w.alOriginal, "case 4: more than one wrapper after on")
end

-- 5. No target: AtlasLoot's own early return; nothing recorded or counted.
do
    local w = World({ withFix = true })
    w.target = nil
    check(w:merchantShow(), "case 5: no target raised an error")
    check(next(w:prices()) == nil and w:fix().state.skipped == 0, "case 5: no target recorded or counted something")
end

-- 6. Load order: our addon first, AtlasLoot later, also with the late loaded flag.
for _, late in ipairs({ false, true }) do
    local w = World({ oursFirst = true, lateLoadedFlag = late })
    local label = "case 6" .. (late and " (late flag)" or "") .. ": "
    check(w.statusBefore == "waiting: AtlasLootClassic not loaded", label .. "before: " .. tostring(w.statusBefore))
    check(w.ns.FixState(w:fix()) == "active", label .. "not active after AtlasLoot loaded")
    w.target = w:secret()
    check(w:merchantShow(), label .. "a hidden vendor still raised an error")
end

print(("%d checks, %d problems"):format(checks, problems))
os.exit(problems == 0 and 0 or 1)
