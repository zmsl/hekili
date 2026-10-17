local _, ns = ...
-- Engine/WeakAuras.lua: the HEKILI_RECOMMENDATION_UPDATE event for WeakAuras, as a passive subscriber to the engine's
-- output (restructure plan, Task 4; it was a block in Core's Update). Passive: WeakAuras alone never makes the engine
-- compute a hidden display, as stock.

local Engine = Hekili.Engine

local NAMES = { "Interrupts", "Defensives", "Cooldowns", "Primary", "AOE" }

-- Per display, the payload's record tables, held strongly here: the stock payload is weak ("kv"), and these are
-- allocated once, not again after a collection.
local held = {}

local function OnPublish(name, version, out)
    local payload, tables = out.payload, held[name]
    if not payload then
        tables = {}
        for i = 1, #out.recs do
            tables[i] = {}
        end
        held[name] = tables
        payload = { tables[1] }
        setmetatable(payload, { __index = payload[1], __mode = "kv" })
        out.payload = payload
    end

    local recs = out.recs
    for i = 1, #recs do
        if i <= out.count then
            local p = tables[i]
            wipe(p)
            for k, v in pairs(recs[i]) do
                p[k] = v
            end
            payload[i] = p
        else
            payload[i] = nil
        end
    end

    -- nil holds a retired argument slot
    WeakAuras.ScanEvents("HEKILI_RECOMMENDATION_UPDATE", name, recs[1].actionID, recs[1].indicator, nil, payload)
end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if WeakAuras and WeakAuras.ScanEvents then
        for i = 1, #NAMES do
            Engine.Subscribe(NAMES[i], OnPublish, true)
        end
    end
end)
