local _, ns = ...
-- Engine/Output.lua: the engine's output and its publish/subscribe (restructure plan, Task 3).
-- Per display, Core builds into `scratch` between ns.Output.Begin and ns.Output.Publish; Publish runs the annotators,
-- swaps `scratch` and `recs`, bumps `version` and calls the subscribers. Between the two only `scratch` is written, so
-- a reader (or a yield) only ever sees `recs` as the last complete set. Everything is preallocated here: no table or
-- closure is created by Begin, Publish, Subscribe or Unsubscribe.

local Engine = Hekili.Engine

local SLOTS = 12 -- recommendation records per display: at most 10 buttons, and 2 more records for the on-GCD plan (Core)
local SUBS = 8 -- subscriber slots per display: OUTSIDE of them for Engine.Subscribe, the rest Hekili's own (Output.Subscribe)
local OUTSIDE = 4 -- so an outside caller never takes the slot of the display, the integrations or the action bar glow
local ANNOTATORS = 4
local ALTS = 2 -- alternatives per record: the picks at the low and the high bound of the gating resource
local READY = ns.READY -- steady icons: a record due within this is shown as ready (the harness's press threshold)

local function records()
    local t = {}
    for i = 1, SLOTS do
        t[i] = { resources = {}, floors = {}, belief = {}, cost = 0, busy = 0, alts = { n = 0 } } -- cost, busy: Core writes them on every published record; floors: the believed floor per pool (the gate veil), resources the estimate (the tooltip)
        -- focus (nil or the entry's `focus=N` tier, 1 highest) is a scalar Core also writes on every record, so Begin clears it
        -- alts[1..n]: { actionName, actionID, texture, action, list, bound = "lo"|"hi" }, filled for a needs.alts subscriber
        for j = 1, ALTS do
            t[i].alts[j] = {}
        end
    end
    return t
end

-- `SLOTS` copies of `v`: the per-slot state of steady icons, sized once.
local function filled(v)
    local t = {}
    for i = 1, SLOTS do
        t[i] = v
    end
    return t
end

-- `false` fills the slots past `n`, so the array part is sized once (SUBS) and (un)subscribing never grows it.
local function slots()
    return { false, false, false, false, false, false, false, false, n = 0 }
end

local function display()
    return {
        version = 0,
        count = 0,
        recs = records(),
        scratch = records(),
        subs = slots(),
        passive = slots(),
        own = slots(), -- per subscriber slot: Hekili's own (Output.Subscribe), not an outside caller's
        outside = 0, -- outside callers' slots in use
        alts = slots(), -- per subscriber slot: it declared needs.alts
        wanted = 0,
        needAlts = 0, -- subscribers that declared needs.alts (passive or not): Core then fills recs[1..2].alts
        publishing = false,
        payload = nil, -- the copy for other addons, set by Integrations/Recommendations.lua (WeakAuras or a listener)
        -- steady icons (Output.steady): per slot the raw (unheld) name last publish, its countdown streak, and whether recs[i] is
        -- held; `acts` the Output.Acted count this display last published at
        rawName = filled(false),
        streak = filled(0),
        held = filled(false),
        -- per slot the icon a hold kept shown, the publish its held change came through (else false)
        kept = filled(false),
        acts = 0,
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
        own = slots(),
        outside = 0,
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

-- Steady icons: always on for players (owner 2026-11-07, no setting); `Output.hold` the updates to hold (1). Only the
-- headless harness turns them off or holds longer, per instance (tests/Game/harness/loop.lua's measurement arms).
Output.steady = true
Output.hold = 1
Output.interval = ns.UPDATE_INTERVAL -- seconds between updates in combat (the driver's combatRate)
-- Published for the displays and the harness, which read the engine through Hekili.Engine.
Engine.READY, Engine.UPDATE_INTERVAL = READY, ns.UPDATE_INTERVAL
local acts = 0

--- Our own cast started or succeeded, our channel ended or a swing queue changed: the next publish of every display
--- shows its new icons at once (Engine/Sim/Events.lua's cast and CURRENT_SPELL_CAST_CHANGED handlers).
function Output.Acted()
    acts = acts + 1
end

-- Holds, per slot, a shown countdown icon that the new set would replace with another countdown icon: the shown
-- record moves into the new set and the new one into the old. `streak[i]` counts the consecutive publishes the raw
-- set had the same countdown icon in slot i (0 after a ready icon or a different one); the swap is held while the
-- streak before this publish is below Output.hold, so an icon the engine keeps shows at most `hold` publishes late
-- (the N+1th publish it is the raw choice). Hold 1 is the original one-publish hold. Never held: a ready icon on
-- either side, a slot the last set lacked, and every slot after Output.Acted. So a ready icon, a ready one going
-- back to waiting, and anything after our own cast show at once. A swap is not started when the new icon is due
-- within the hold window (READY + hold * Output.interval, the driver's combat update rate): it turns ready before
-- the hold could end, the ready exemption would cut the hold short, and a 2-update raw change would show as a
-- 1-update blip. That swap is the next press, not flicker. The exception (L1328): the publish after a held change
-- came through, a change back to the icon the hold kept shown is held even inside the window (only the ready exemption
-- applies), else a raw a,b,b,a would show b for one update. At the shipped hold 1 an icon inside the window turns
-- ready by the next update, which shows it at once, so no press waits.
local function steady(o, built, count)
    local recs, rawName, held, streak, kept = o.recs, o.rawName, o.held, o.streak, o.kept
    local acted, last, hold = o.acts ~= acts, o.count, Output.hold
    local window = READY + hold * Output.interval
    for i = 1, SLOTS do
        local name, t, keep, run, back = false, 0, false, 0, false
        if i <= count then
            local new, old = built[i], recs[i]
            name, t = new.actionName or false, new.time or 0
            if t > READY then
                run = rawName[i] == name and streak[i] + 1 or 1
            end
            keep = not acted
                and i <= last
                and t > (name and name == kept[i] and READY or window)
                and (old.time or 0) > READY
                and old.actionName ~= name
                and run <= hold
            if keep then
                built[i], recs[i] = old, new
            elseif held[i] and run > 1 then
                back = old.actionName or false -- the held change came through: a return to `old` is held next publish
            end
        end
        held[i], rawName[i], streak[i], kept[i] = keep, name, run, back
    end
end

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
    local subs, passive, own, alts = o.subs, o.passive, o.own, o.alts
    local n, j = subs.n, 0
    for i = 1, n do
        if subs[i] then
            j = j + 1
            subs[j], passive[j], own[j] = subs[i], passive[i], own[i]
            if alts then
                alts[j] = alts[i]
            end
        end
    end
    for i = j + 1, n do
        subs[i], passive[i], own[i] = false, false, false
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
        if Output.steady then
            steady(o, built, count)
        end
        o.acts = acts
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

-- Engine.Subscribe and Output.Subscribe: `own` true for Hekili's own subscribers, which outside callers never crowd out.
local function subscribe(name, fn, passive, needs, own)
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
    if not own and o.outside == OUTSIDE then
        return false
    end
    -- A publish cut short by a subscriber error leaves its blanked slots (and `publishing`) behind: drop them first.
    if subs.n == SUBS then
        compact(o)
    end
    if subs.n == SUBS then
        return false
    end
    local n = subs.n + 1
    subs[n], o.passive[n], o.own[n], subs.n = fn, passive, own, n
    if not own then
        o.outside = o.outside + 1
    end
    if not passive then
        o.wanted = o.wanted + 1
    end
    setAlts(o, n, alts)
    return true
end

--- Subscribes `fn(name, version, output)` to `name`'s publishes; a `passive` subscriber listens without asking the
--- engine to compute the display. `needs` (optional): `needs.alts` asks Core to fill recs[1..2].alts (the picks at
--- the gating resource's belief bounds). Subscribing an already subscribed fn only updates its passive flag and needs.
--- Returns false when the caller's slots are full: an outside caller has 4 per display.
function Engine.Subscribe(name, fn, passive, needs)
    return subscribe(name, fn, passive, needs, false)
end

--- Engine.Subscribe for Hekili's own subscribers (the displays, the integrations, the action bar glow): their slots
--- are kept apart from the outside callers', so an outside caller never takes one.
function Output.Subscribe(name, fn, passive, needs)
    return subscribe(name, fn, passive, needs, true)
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
            if not o.own[i] then
                o.outside = o.outside - 1
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
    if n == ANNOTATORS then
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
