local _, ns = ...
-- Engine/Output.lua: the engine's output and its publish/subscribe (restructure plan, Task 3).
-- Per display, Core builds into `scratch` between ns.Output.Begin and ns.Output.Publish; Publish runs the annotators,
-- swaps `scratch` and `recs`, bumps `version` and calls the subscribers. Between the two only `scratch` is written, so
-- a reader (or a yield) only ever sees `recs` as the last complete set. Everything is preallocated here: no table or
-- closure is created by Begin, Publish, Subscribe or Unsubscribe.

local Engine = Hekili.Engine

local SLOTS = 10 -- recommendation records per display: a display has at most 10 buttons
local SUBS = 4 -- subscriber slots per display, and annotator slots

local function records()
    local t = {}
    for i = 1, SLOTS do
        t[i] = { resources = {}, belief = {} }
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
        wanted = 0,
        payload = nil, -- the WeakAuras event copy, set by Core only when WeakAuras is loaded
    }
end

--- Per display name the published output; `status` is the engine's own record (combat, targets, spec, pack).
local Output = {
    Interrupts = display(),
    Defensives = display(),
    Cooldowns = display(),
    Primary = display(),
    AOE = display(),
    status = {
        version = 0,
        count = 0,
        subs = slots(),
        passive = slots(),
        wanted = 0,
        combat = false,
        numTargets = 0,
        specID = nil,
        specKey = nil,
        packName = nil,
    },
}

Engine.Output = Output
ns.Output = Output

local annotators = slots()

--- Clears `name`'s scratch set (every non-table field of every record, and each record's belief) and returns it.
function Output.Begin(name)
    local scratch = Output[name].scratch
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
    end
    return scratch
end

--- Publishes `count` records of `name`'s scratch set: the annotators run over them, scratch and recs swap, the version
--- bumps, then each subscriber gets (name, version, output). No yield inside.
function Output.Publish(name, count)
    local o = Output[name]
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
    for i = 1, subs.n do
        subs[i](name, version, o)
    end
end

--- True when `name` has a non-passive subscriber, i.e. someone wants it computed.
function Output.Wanted(name)
    return Output[name].wanted > 0
end

--- Subscribes `fn(name, version, output)` to `name`'s publishes; a `passive` subscriber listens without asking the
--- engine to compute the display. Subscribing an already subscribed fn does nothing. Returns false when the slots are full.
function Engine.Subscribe(name, fn, passive)
    local o = Output[name]
    local subs = o.subs
    for i = 1, subs.n do
        if subs[i] == fn then
            return true
        end
    end
    if subs.n == SUBS then
        return false
    end
    local n = subs.n + 1
    subs[n], o.passive[n], subs.n = fn, passive and true or false, n
    if not passive then
        o.wanted = o.wanted + 1
    end
    return true
end

--- Removes `fn` from `name`'s subscribers, keeping the others' order.
function Engine.Unsubscribe(name, fn)
    local o = Output[name]
    local subs, passive = o.subs, o.passive
    local n = subs.n
    for i = 1, n do
        if subs[i] == fn then
            if not passive[i] then
                o.wanted = o.wanted - 1
            end
            for j = i, n - 1 do
                subs[j], passive[j] = subs[j + 1], passive[j + 1]
            end
            subs[n], passive[n], subs.n = false, false, n - 1
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
