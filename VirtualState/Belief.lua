-- VirtualState/Belief.lua
-- The fold (spec §8): applies the log's observations in order on the belief clock, with the lag clamp, then settles
-- (cooldown flags, record sync). Families register appliers per observation kind, advance hooks (carry their clock
-- values forward) and settle hooks. Also the tracked-set build (spec §3.6).
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief.lua (Update :720, the clock start :723-728, the lag
-- clamp :733-736, constrain :652, sync :687); the Writer/FinalWriter/Serial parts are not ported.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local At, Shift = I.ObsLog.At, I.ObsLog.Shift
local Obs = VS.Obs

local APPLY, ADVANCE, SETTLE = {}, {}, {}

--- Registers `fn(o, t, lag)` for observations of `kind` (families, at load). `o` is the reused log record.
function I.On(kind, fn)
    local list = APPLY[kind]
    if not list then
        list = {}
        APPLY[kind] = list
    end
    list[#list + 1] = fn
end

--- Registers `fn(from, to)`, run whenever the belief clock moves forward. Load time only.
function I.OnAdvance(fn)
    ADVANCE[#ADVANCE + 1] = fn
end

--- Registers `fn(now)`, run once at the end of each fold (the standing flags and the record sync). Load time only.
function I.OnSettle(fn)
    SETTLE[#SETTLE + 1] = fn
end

I.clock, I.started = 0, false

-- Moves the belief clock to t (never backward).
local function advance(t)
    local c = I.clock
    if t > c then
        for k = 1, #ADVANCE do
            ADVANCE[k](c, t)
        end
        I.clock = t
    end
end
I.Advance = advance

--- Folds the log in order (spec §5.2 step 2): everything stamped at or before `upto`; an own cast's effects are
--- written by its appliers (Families/Now.lua). An observation older than the clock is applied at the clock with
--- `lag`. Allocates nothing.
---@param upto number
function I.Fold(upto)
    local log = I.log
    if not I.started then
        -- The clock starts at the first thing heard, not at 0 (TDF Belief.lua:723-728).
        local first = log.n > 0 and At(log, 1).t or upto
        I.clock = first < upto and first or upto
        I.started = true
    end
    while log.n > 0 do
        local o = At(log, 1)
        if o.t > upto then
            break
        end
        Shift(log)
        local t, lag = o.t, 0
        if t < I.clock then
            t, lag = I.clock, I.clock - o.t
        end
        advance(t)
        local kind = o.kind
        local list = APPLY[kind]
        if list then
            for k = 1, #list do
                list[k](o, t, lag)
            end
        end
    end
    return nil
end

--- Ends a fold: the clock to `now`, then every settle hook. Allocates nothing.
function I.Settle(now)
    advance(now)
    for k = 1, #SETTLE do
        SETTLE[k](now)
    end
end

--- The time a projection uses (spec §2 "No backward projection"): 0 for a `now` before the clock.
function I.Dt(now)
    local dt = now - I.clock
    return dt > 0 and dt or 0
end

--- Rebuilds the tracked set from `def` (spec §3.6): every family allocates its arrays and records. `def` holds
--- `abilities` (Hekili ability tables), `resources`, `auras`, `talents` and `units` (see Adapter.lua). Allocates;
--- SpecChanged only.
function I.Build(def, now)
    I.ClearRecords()
    I.ObsLog.Clear(I.log) -- held observations name the old set's indices
    if I.Sources then
        I.Sources.stN = 0 -- and so do staged ones
    end
    I.started = false
    I.clock = now
    for k = 1, #I.BUILD do
        I.BUILD[k](def, now)
    end
    I.built = true
end
