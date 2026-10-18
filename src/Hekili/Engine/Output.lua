local _, ns = ...
-- Engine/Output.lua: the engine's output and its publish/subscribe (restructure plan, Task 3).
-- Per display, Core builds into `scratch` between ns.Output.Begin and ns.Output.Publish; Publish runs the annotators,
-- swaps `scratch` and `recs`, bumps `version` and calls the subscribers. Between the two only `scratch` is written, so
-- a reader (or a yield) only ever sees `recs` as the last complete set. Everything is preallocated here: no table or
-- closure is created by Begin, Publish, Subscribe or Unsubscribe.

local Engine = Hekili.Engine

local SLOTS = 10 -- recommendation records per display: a display has at most 10 buttons
local SUBS = 4 -- subscriber slots per display, and annotator slots
local ALTS = 2 -- alternatives per record: the picks at the low and the high bound of the gating resource

local function records()
    local t = {}
    for i = 1, SLOTS do
        t[i] = { resources = {}, belief = {}, cost = 0, busy = 0, alts = { n = 0 } } -- cost, busy: Core writes them on every published record
        -- alts[1..n]: { actionName, actionID, texture, action, list, bound = "lo"|"hi" }, filled for a needs.alts subscriber
        for j = 1, ALTS do
            t[i].alts[j] = {}
        end
    end
    return t
end

-- `false` fills the slots past `n`, so the array part is sized once and (un)subscribing never grows it.
local function slots()
    return { false, false, false, false, n = 0 }
end

local function display()
    return {
        version = 0,
        count = 0,
        recs = records(),
        scratch = records(),
        subs = slots(),
        passive = slots(),
        alts = slots(), -- per subscriber slot: it declared needs.alts
        wanted = 0,
        needAlts = 0, -- subscribers that declared needs.alts (passive or not): Core then fills recs[1..2].alts
        publishing = false,
        payload = nil, -- the WeakAuras event copy, set by Integrations/WeakAuras.lua only when WeakAuras is loaded
    }
end

--- Per display name the published output; `status` is the engine's own record (combat, targets, spec, pack).
local Displays = {
    Interrupts = display(),
    Defensives = display(),
    Cooldowns = display(),
    Primary = display(),
    AOE = display(),
    status = {
        version = 0,
        count = 1, -- status is itself the one record it publishes (Publish("status", 1)); always 1
        subs = slots(),
        passive = slots(),
        wanted = 0,
        publishing = false,
        combat = false,
        combatStart = 0, -- the combat start time (state.combat), 0 out of combat
        numTargets = 0,
        specID = nil,
        specKey = nil,
        specName = nil,
        packName = nil,
    },
}

-- Hekili.Engine.Output is the display table only; ns.Output (engine-private) holds the functions below and reads the
-- displays through __index, so ns.Output.Primary still works while Begin/Publish stay off the public port.
Engine.Output = Displays
local Output = setmetatable({}, { __index = Displays })
ns.Output = Output

local annotators = slots()

--- Clears `name`'s scratch set (every non-table field of every record, and each record's belief) and returns it.
function Output.Begin(name)
    local scratch = Displays[name].scratch
    for i = 1, SLOTS do
        local rec = scratch[i]
        for k, v in pairs(rec) do
            if type(v) ~= "table" then
                rec[k] = nil
            end
        end
        local belief = rec.belief
        for k in pairs(belief) do
            belief[k] = nil
        end
        rec.alts.n = 0
    end
    return scratch
end

-- Drops the blanked (false) subscriber slots, keeping the others' order.
local function compact(o)
    local subs, passive, alts = o.subs, o.passive, o.alts
    local n, j = subs.n, 0
    for i = 1, n do
        if subs[i] then
            j = j + 1
            subs[j], passive[j] = subs[i], passive[i]
            if alts then
                alts[j] = alts[i]
            end
        end
    end
    for i = j + 1, n do
        subs[i], passive[i] = false, false
        if alts then
            alts[i] = false
        end
    end
    subs.n = j
end

--- Publishes `count` records of `name`'s scratch set: the annotators run over them, scratch and recs swap, the version
--- bumps, then each subscriber gets (name, version, output). No yield inside.
function Output.Publish(name, count)
    local o = Displays[name]
    local built = o.scratch
    if built then
        for a = 1, annotators.n do
            local fn = annotators[a]
            for i = 1, count do
                fn(name, built[i], i)
            end
        end
        o.scratch, o.recs, o.count = o.recs, built, count
    end
    o.version = o.version + 1
    local subs, version = o.subs, o.version
    -- A subscriber may unsubscribe (itself or another) mid-loop: Unsubscribe then only blanks its slot, and the
    -- slots are compacted after the loop, so no later subscriber is skipped.
    o.publishing = true
    for i = 1, subs.n do
        local fn = subs[i]
        if fn then
            fn(name, version, o)
        end
    end
    o.publishing = false
    compact(o)
end

--- True when `name` has a non-passive subscriber, i.e. someone wants it computed.
function Output.Wanted(name)
    return Displays[name].wanted > 0
end

-- Sets subscriber slot i's needs.alts flag, keeping the display's count.
local function setAlts(o, i, alts)
    if o.alts and o.alts[i] ~= alts then
        o.alts[i] = alts
        o.needAlts = o.needAlts + (alts and 1 or -1)
    end
end

--- Subscribes `fn(name, version, output)` to `name`'s publishes; a `passive` subscriber listens without asking the
--- engine to compute the display. `needs` (optional): `needs.alts` asks Core to fill recs[1..2].alts (the picks at
--- the gating resource's belief bounds). Subscribing an already subscribed fn only updates its passive flag and needs.
--- Returns false when the slots are full.
function Engine.Subscribe(name, fn, passive, needs)
    local o = Displays[name]
    local subs = o.subs
    passive = passive and true or false
    local alts = needs and needs.alts and true or false
    for i = 1, subs.n do
        if subs[i] == fn then
            if o.passive[i] ~= passive then
                o.passive[i] = passive
                o.wanted = o.wanted + (passive and -1 or 1)
            end
            setAlts(o, i, alts)
            return true
        end
    end
    -- A publish cut short by a subscriber error leaves its blanked slots (and `publishing`) behind: drop them first.
    if subs.n == SUBS then
        compact(o)
    end
    if subs.n == SUBS then
        return false
    end
    local n = subs.n + 1
    subs[n], o.passive[n], subs.n = fn, passive, n
    if not passive then
        o.wanted = o.wanted + 1
    end
    setAlts(o, n, alts)
    return true
end

--- Removes `fn` from `name`'s subscribers, keeping the others' order.
function Engine.Unsubscribe(name, fn)
    local o = Displays[name]
    local subs = o.subs
    for i = 1, subs.n do
        if subs[i] == fn then
            if not o.passive[i] then
                o.wanted = o.wanted - 1
            end
            setAlts(o, i, false)
            subs[i] = false
            if not o.publishing then
                compact(o)
            end
            return
        end
    end
end

--- Registers `fn(name, rec, i)`, run over each published record before the swap (the belief annotator's hook).
function Output.Annotate(fn)
    local n = annotators.n
    for i = 1, n do
        if annotators[i] == fn then
            return true
        end
    end
    if n == SUBS then
        return false
    end
    annotators[n + 1], annotators.n = fn, n + 1
    return true
end

function Output.Unannotate(fn)
    local n = annotators.n
    for i = 1, n do
        if annotators[i] == fn then
            for j = i, n - 1 do
                annotators[j] = annotators[j + 1]
            end
            annotators[n], annotators.n = false, n - 1
            return
        end
    end
end
