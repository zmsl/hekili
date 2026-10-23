-- Game/State/Belief.lua
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

-- The provider contracts (providers spec §1): answers (UNDECIDED: no answer, the consumer's own path), and the
-- registries each provider file fills at load. I.UNKNOWN is the unknown entity record (VirtualState.lua), not an answer.
I.UNDECIDED, I.HIT, I.AVOID, I.OURS, I.FOREIGN, I.UP, I.DOWN = 0, 1, 2, 1, 2, 1, 2
I.OUTCOMES, I.PRESENCE = {}, {}
I.outcomes, I.presence, I.presenceViewer = nil, nil, nil
local wantO, wantP, wantV -- a swap asked for in combat (VS.SetProviders): applied at combat end

-- Activates the named providers (spec §3.1): unknown names are "default"; only a changed choice is swapped, except
-- that a build (`def`) re-activates the presence provider (its map names the new set's auras).
local function provide(oName, pName, viewer, now, def)
    local O = I.OUTCOMES[oName or "default"] or I.OUTCOMES.default
    local P = I.PRESENCE[pName or "default"] or I.PRESENCE.default
    if O ~= I.outcomes then
        if I.outcomes then
            I.outcomes.Deactivate(now)
        end
        I.outcomes = O
        O.Activate(I.api, now)
    end
    if P ~= I.presence or viewer ~= I.presenceViewer or def then
        if I.presence then
            I.presence.Deactivate(now)
        end
        I.presence, I.presenceViewer = P, viewer
        P.Activate(I.api, now, def or I.def, { viewer = viewer == true })
        if I.OnPresence then
            I.OnPresence(P) -- Sources/Auras.lua: the provider's edges go there
        end
    end
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
    I.def = def
    for k = 1, #I.BUILD do
        I.BUILD[k](def, now)
    end
    local pv = def.providers or {}
    provide(pv.outcomes, pv.presence, pv.viewer, now, def)
    I.built = true
end

--- (spec §3.1) Swaps the providers without a rebuild: out of combat at once, in combat at PLAYER_REGEN_ENABLED.
function VS.SetProviders(outcomes, presence, viewer)
    if I.inCombat then
        wantO, wantP, wantV = outcomes or "default", presence or "default", viewer
        return
    end
    provide(outcomes, presence, viewer, I.clock)
end

--- Applies a swap asked for in combat. Rows calls it at PLAYER_REGEN_ENABLED, after T.EndCombat.
function I.ApplyProviders(now)
    if wantO then
        local o, p, v = wantO, wantP, wantV
        wantO, wantP, wantV = nil, nil, nil
        provide(o, p, v, now)
    end
end

--- (spec §3.4) The active presence provider's scope ("self", "any") for aura `key` on `unit`, nil when uncovered.
function VS.PresenceScope(unit, key)
    local P, U = I.presence, I.auras
    local u, j = U and U.index[unit], U and U.byKey[key]
    if P and u and j and P.Presence(j, u) ~= I.UNDECIDED then
        return P.scope
    end
    return nil
end
