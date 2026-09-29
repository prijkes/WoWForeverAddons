-- Loads addon files the way WoW does: each chunk receives (addonName, namespace).
local L = {}

function L.load(ns, ...)
    for i = 1, select("#", ...) do
        local chunk = assert(loadfile((select(i, ...))))
        chunk("ForeverFlightTimer", ns)
    end
    return ns
end

return L
