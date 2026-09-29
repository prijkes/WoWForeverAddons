-- Pure time formatting (no WoW APIs). Styles: auto | hours | padded | words.
local _, ns = ...

local TimeFormat = {}
ns.TimeFormat = TimeFormat

local floor, format = math.floor, string.format

function TimeFormat.Format(seconds, style, showTenths)
    seconds = tonumber(seconds) or 0
    if seconds ~= seconds or seconds < 0 then seconds = 0 end
    -- The epsilon absorbs binary fractions like 12.7 * 10 = 126.99999999999999.
    local totalTenths = floor(seconds * 10 + 1e-6)
    local whole = floor(totalTenths / 10)
    local tenths = totalTenths % 10
    local h = floor(whole / 3600)
    local m = floor(whole % 3600 / 60)
    local s = whole % 60
    local suffix = showTenths and ("." .. tenths) or ""

    if style == "hours" then
        return format("%d:%02d:%02d", h, m, s) .. suffix
    elseif style == "padded" then
        return format("%02d:%02d:%02d", h, m, s) .. suffix
    elseif style == "words" then
        local text
        if h > 0 then
            text = format("%dh %02dm %02d", h, m, s)
        elseif m > 0 then
            text = format("%dm %02d", m, s)
        else
            text = format("%d", s)
        end
        return text .. suffix .. "s"
    end
    if h > 0 then
        return format("%d:%02d:%02d", h, m, s) .. suffix
    end
    return format("%d:%02d", m, s) .. suffix
end
