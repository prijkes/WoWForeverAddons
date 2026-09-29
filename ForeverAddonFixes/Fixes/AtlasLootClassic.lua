-- AtlasLoot's vendor price scan reads the target's GUID on MERCHANT_SHOW and splits it to get the
-- vendor's NPC ID. When the game hides the vendor's identity, that GUID is a secret and the split
-- throws "attempt to perform string conversion on a secret string value". This skips the scan for
-- that visit, as AtlasLoot already does without a target. Its event handler calls
-- AtlasLoot.Data.VendorPrice.ScanShownVendor() through the table, so wrapping it covers every path.
local _, ns = ...

local original, wrapper
local fix

local function Scanner()
    local atlasLoot = _G.AtlasLoot
    local data = type(atlasLoot) == "table" and atlasLoot.Data
    local vendorPrice = type(data) == "table" and data.VendorPrice
    if type(vendorPrice) == "table" then return vendorPrice end
end

fix = ns.RegisterFix({
    id = "AtlasLootClassic.hiddenVendor",
    addon = "AtlasLootClassic",
    title = "AtlasLoot: skip scans of hidden vendors",
    skipText = "AtlasLoot skipped a vendor scan (the vendor is hidden)",
    description = "When the game hides a vendor's identity from addons, AtlasLoot's vendor price scan tries to read it anyway "
        .. "and throws a Lua error. This makes AtlasLoot skip the scan for that visit, as it already does when you have no target. "
        .. "It only misses the special-currency prices it would have learned from that one visit.",
    testedVersions = { "Forever 1.60.1" }, -- what releases 1.0.7 and 1.1.1 both report
    versionNote = "its releases share one version string",

    needed = function() return issecretvalue ~= nil or canaccessvalue ~= nil end,

    install = function()
        local vendorPrice = Scanner()
        if not vendorPrice or type(vendorPrice.ScanShownVendor) ~= "function" then
            return false, "AtlasLoot's vendor scanner wasn't found (AtlasLoot has changed, or part of it failed to load)"
        end
        local Readable, state = ns.Readable, fix.state
        original = vendorPrice.ScanShownVendor
        wrapper = function(...)
            if state.enabled then
                -- The same unit AtlasLoot reads, in the same call. If reading it errors, AtlasLoot's
                -- own read would error too, so that counts as a skip.
                local ok, guid = pcall(UnitGUID, "target")
                if not ok or (guid and not Readable(guid)) then -- a truth test is safe on a secret
                    fix:CountSkip()
                    return -- AtlasLoot's own early returns return nothing too
                end
            end
            return original(...)
        end
        vendorPrice.ScanShownVendor = wrapper
        return true
    end,

    -- Restores AtlasLoot's function, unless another addon has wrapped it after us.
    uninstall = function()
        local vendorPrice = Scanner()
        if vendorPrice and wrapper and vendorPrice.ScanShownVendor == wrapper then
            vendorPrice.ScanShownVendor = original
            return true
        end
        return false
    end,
})
