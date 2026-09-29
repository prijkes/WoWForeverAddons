-- GearQuestForever reads chat text that the game hides from addons in dungeons, raids and boss
-- fights, and throws "attempt to index local 'msg' (a secret string value ...)". This makes it
-- skip those messages. Its tracker calls GearQuest.Log:HandleCraftChatMessage(msg)
-- through the table on every message, so wrapping that method covers the only parsing path.
local _, ns = ...

local original, wrapper
local fix

fix = ns.RegisterFix({
    id = "GearQuestForever.hiddenChatText",
    addon = "GearQuestForever",
    title = "GearQuest: skip hidden chat text",
    skipText = "GearQuest skipped a hidden chat message",
    description = "In dungeons, raids and boss fights the game hides some chat text from addons. "
        .. "GearQuest tries to read it and throws a Lua error. This makes GearQuest skip those messages. "
        .. "It loses nothing: GearQuest only needs loot and craft lines, which it can't read while they're hidden anyway.",
    testedVersions = { "0.2.6-beta", "0.2.11-beta" },

    needed = function() return issecretvalue ~= nil or canaccessvalue ~= nil end,

    install = function()
        local gq = _G.GearQuest
        local log = type(gq) == "table" and gq.Log
        if type(log) ~= "table" or type(log.HandleCraftChatMessage) ~= "function" then
            return false, "GearQuest's chat handler wasn't found (GearQuest has changed, or part of it failed to load)"
        end
        local Readable, state = ns.Readable, fix.state
        original = log.HandleCraftChatMessage
        wrapper = function(self, msg, ...)
            -- A truth test is safe on a secret: GearQuest's own 'if not msg' runs first.
            if msg and state.enabled and not Readable(msg) then
                fix:CountSkip()
                return -- the original returns nothing either
            end
            return original(self, msg, ...)
        end
        log.HandleCraftChatMessage = wrapper
        return true
    end,

    -- Restores GearQuest's method, unless another addon has wrapped it after us.
    uninstall = function()
        local gq = _G.GearQuest
        local log = type(gq) == "table" and gq.Log
        if type(log) == "table" and wrapper and log.HandleCraftChatMessage == wrapper then
            log.HandleCraftChatMessage = original
            return true
        end
        return false
    end,
})
