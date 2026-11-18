local _, ns = ...
-- Integrations/Recommendations.lua: each recommendation update for other addons. One passive subscriber per display,
-- in Hekili's own engine slots, copies the published records into a payload and hands it to the WeakAuras event
-- HEKILI_RECOMMENDATION_UPDATE (when WeakAuras was loaded as the player entered the world) and to the listeners of Hekili:RegisterRecommendationListener.
-- Passive: neither ever makes the engine compute a hidden display, as stock.

local NAMES = { "Interrupts", "Defensives", "Cooldowns", "Primary", "AOE" }
local MAX = 16 -- listener slots

-- The listeners, `false` past `n` (sized once for 16; inside a callback a register after an unregister may append
-- past 16 until the compaction). One unregistered mid-call is blanked and the list compacted after the loop, so no
-- later listener is skipped.
local listeners = { n = 0 }
for i = 1, MAX do
    listeners[i] = false
end
local calling = false
-- listener -> true once its first error went to the error handler; weak, and cleared on unregister
local reported = setmetatable({}, { __mode = "k" })
local wa = false -- WeakAuras was loaded when the player entered the world, as stock
local subscribed = false

-- Per display, the payload's record tables, held strongly here: the stock payload is weak ("kv"), and these are
-- allocated once, not again after a collection.
local held = {}

local function compact()
    local n, j = listeners.n, 0
    for i = 1, n do
        if listeners[i] then
            j = j + 1
            listeners[j] = listeners[i]
        end
    end
    for i = j + 1, n do
        listeners[i] = false
    end
    listeners.n = j
end

local function OnPublish(name, version, out)
    if not wa and listeners.n == 0 then
        return
    end

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
            -- blank past count (stock copied numRecs records, the extras blank); at 0, payload's __index reads blank
            local p = tables[i]
            wipe(p)
            payload[i] = p
        end
    end

    -- Also fires on Core's rule-off Publish(name, 0), unlike stock (which left the aura on a stale recommendation).
    -- nil holds a retired argument slot
    if wa then
        WeakAuras.ScanEvents("HEKILI_RECOMMENDATION_UPDATE", name, recs[1].actionID, recs[1].indicator, nil, payload)
    end

    calling = true
    for i = 1, listeners.n do
        local fn = listeners[i]
        if fn then
            local ok, err = pcall(fn, name, payload)
            if not ok and not reported[fn] then
                reported[fn] = true -- the first error only: a listener raising on every update would flood the handler
                geterrorhandler()(err)
            end
        end
    end
    calling = false
    compact()
end

-- Subscribed once, on the first need (WeakAuras at PLAYER_ENTERING_WORLD, or the first listener), in Hekili's own slots.
local function subscribe()
    if subscribed then
        return
    end
    subscribed = true
    for i = 1, #NAMES do
        ns.Output.Subscribe(NAMES[i], OnPublish, true)
    end
end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if WeakAuras and WeakAuras.ScanEvents then
        wa = true
        subscribe()
    end
end)

--- Registers `fn(display, payload)`, called after every update of the five displays (Interrupts, Defensives,
--- Cooldowns, Primary, AOE) with the display's name and the HEKILI_RECOMMENDATION_UPDATE event's payload. Called
--- inside pcall: a listener's first error goes to the error handler, later ones are dropped, and it stays registered.
--- Returns true when registered (also when it already was), false when the 16 slots are full.
---@param fn fun(display: string, payload: table)
---@return boolean
function Hekili:RegisterRecommendationListener(fn)
    assert(type(fn) == "function", "RegisterRecommendationListener: fn must be a function")
    local n, live = listeners.n, 0
    for i = 1, n do
        local l = listeners[i]
        if l == fn then
            return true
        elseif l then
            live = live + 1
        end
    end
    if live == MAX then
        return false
    end
    -- Appended even past MAX inside a callback (a blank there is compacted after the loop), so it is first called on
    -- the next publish.
    listeners[n + 1], listeners.n = fn, n + 1
    subscribe()
    return true
end

--- Removes a listener added by RegisterRecommendationListener; an unknown `fn` is ignored. Safe inside a listener.
function Hekili:UnregisterRecommendationListener(fn)
    for i = 1, listeners.n do
        if listeners[i] == fn then
            listeners[i] = false
            reported[fn] = nil
            if not calling then
                compact()
            end
            return
        end
    end
end
