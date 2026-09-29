-- AceDB defaults. Learned routes are account-wide, outside the profiles.
local _, ns = ...

local function rgba(r, g, b, a) return { r = r, g = g, b = b, a = a } end

ns.DEFAULTS = {
    profile = {
        -- Display tab
        showTimer = true,
        locked = true,
        rightClickMenu = true,
        pos = { x = 0, y = -120 }, -- UIParent units, frame TOP relative to the screen's top-center
        width = 240,
        height = 20,
        scale = 1,
        alpha = 1,
        strata = "MEDIUM",
        freezeSeconds = 0,
        -- Appearance: bar
        showBar = true,
        barTexture = "Blizzard",
        barFill = "drain", -- drain | fill
        colors = {
            countdown = rgba(0.2, 0.6, 1, 1),
            learning = rgba(0.55, 0.55, 0.55, 1),
            overtime = rgba(1, 0.45, 0.1, 1),
            barBg = rgba(0, 0, 0, 0.5),
            name = rgba(1, 1, 1, 1),
            time = rgba(1, 1, 1, 1),
            arrival = rgba(0.8, 0.8, 0.8, 1),
        },
        -- Appearance: text
        showDest = true,
        showOrigin = false,
        fullNames = false,
        showTime = true,
        countUp = false,
        timeStyle = "auto",
        showTenths = false,
        showArrival = true,
        arrivalPos = "after",  -- after | below
        clockSource = "game",  -- game | local | realm
        clockFormat = "game",  -- game | 24 | 12
        font = { face = "Friz Quadrata TT", size = 12, outline = "OUTLINE", mono = false, shadow = false },
        -- Appearance: frame
        bg = { show = false, texture = "Solid", color = rgba(0, 0, 0, 0.55) },
        border = { show = false, texture = "Blizzard Tooltip", size = 14, color = rgba(0.8, 0.8, 0.8, 0.9) },
        padding = 0,
        -- Behaviour tab
        tooltips = true,
        chat = true,
    },
    global = {
        debug = false,
        routes = {},
    },
}
