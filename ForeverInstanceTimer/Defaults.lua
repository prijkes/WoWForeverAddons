-- AceDB defaults. Rule defaults are the user's answers.
local _, ns = ...

local function rgba(r, g, b, a) return { r = r, g = g, b = b, a = a } end

ns.DEFAULTS = {
    profile = {
        -- Display tab
        showTimer = true,
        locked = true,
        rightClickMenu = true,
        pos = { x = 0, y = -80 }, -- UIParent units, offset of the frame's TOP from the screen's top-center
        scale = 1,
        alpha = 1,
        strata = "MEDIUM",
        hideInCombat = false,
        showWhileAway = true,
        -- Appearance: text & layout
        showName = true,
        namePos = "ABOVE",  -- ABOVE | BELOW | LEFT | RIGHT
        align = "CENTER",   -- LEFT | CENTER | RIGHT
        spacing = 2,
        timeStyle = "auto", -- auto | hours | padded | words
        showTenths = false,
        -- Appearance: fonts
        nameFont = { face = "Friz Quadrata TT", size = 12, outline = "NONE", mono = false, shadow = true },
        timeFont = { face = "Friz Quadrata TT", size = 22, outline = "OUTLINE", mono = false, shadow = false },
        -- Appearance: colors
        colors = {
            name = rgba(1, 0.82, 0, 1),
            running = rgba(1, 1, 1, 1),
            away = rgba(0.6, 0.75, 1, 1),
            final = rgba(0.25, 1, 0.25, 1),
        },
        -- Appearance: background & border
        bg = { show = true, texture = "Solid", color = rgba(0, 0, 0, 0.55) },
        border = { show = true, texture = "Blizzard Tooltip", size = 14, color = rgba(0.8, 0.8, 0.8, 0.9) },
        padding = 8,
        -- Rules tab
        types = { party = true, raid = true, pvp = true },
        awayMode = "count", -- count | pause
        giveUp = "ghost",   -- ghost | grace | never
        graceMinutes = 15,
        offline = "count",  -- count | pause | reset
        chat = true,
        freezeSeconds = 10,
    },
    global = {
        debug = false,
    },
}
