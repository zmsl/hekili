-- Virtual/State/VirtualState.lua
-- VirtualState carries the game state forward from plain observations on WoW Forever and answers the reads that are
-- secret in combat (docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md). This file: the public table
-- `ns.VirtualState`, the module's internal table, the observation enum, the Belief record and the debug rings.
-- Ported from Taco Dog Forever: src/TacoDogForever/Engine/Enum.lua (Enum.Obs, Enum.ReadOf, Enum.TargetCastOf, same
-- integers) and src/TacoDogForever/Model/Belief.lua (the est/lo/hi/conf record and its constants).

local _, ns = ...

local VS = { Count = {} }
ns.VirtualState = VS

-- The module's internals, shared by the VirtualState files only. Not a public surface.
local I = {}
ns.VirtualStateInternal = I

--- Observation kinds (spec §2): TDF's Enum.Obs, same integers. The kinds Phase 1 does not log keep their integers.
VS.Obs = {
    Usable = 1, -- a: ability index; b: 1 usable / 0 not; c: 1 not usable for lack of its resource
    CastStart = 2, -- a: ability index; b: the cast's end
    CastSuccess = 3, -- a: ability index
    CastStop = 4, -- a: ability index (failed or interrupted)
    Read = 5, -- a: resource slot or aura index (c: ReadOf); b: the exact value (amount; aura time remaining)
    Cooldown = 6, -- a: ability index; b: 1 ready / 0 not (the plain isActive flag); c: 1 the GCD flag edge
    PowerTick = 7, -- a: resource slot
    TargetSwap = 8, -- a: memory slot (0 none); b: 1 a slot newly taken; c: 1 attackable (plain UnitCanAttack)
    CombatStart = 9,
    CombatEnd = 10,
    Group = 11, -- reserved
    TargetGone = 12,
    Known = 13, -- reserved
    Queued = 14, -- a: ability index; b: 1 queued for the next swing / 0 not
    Swing = 15, -- a: hand (1 main, 2 off); b: swing duration or speed; c: 1 swung (PLAYER_SWING), 0 a read, 2 base speed
    Haste = 16, -- b: melee multiplier (a plain read); c: 1 melee, 2 spell (b: spell haste percent)
    Moving = 17, -- b: 1 moving / 0 not
    Talent = 18, -- a: talent index; b: its rank
    Enemies = 19, -- b: live attackable plates
    Encounter = 20, -- reserved
    TargetInfo = 21, -- reserved
    PlayerInfo = 22, -- reserved
    GameError = 23, -- reserved
    ChannelStart = 24, -- a: ability index; b: the channel's end
    ChannelStop = 25, -- a: ability index
    ChannelUpdate = 26, -- a: ability index; b: the channel's new end
    CastDelay = 27, -- a: ability index; b: the cast's new end
    PackEvent = 28, -- reserved
    Pet = 29, -- reserved
    Totem = 30, -- a: slot 1-4; b: expiry (0 empty); c: 1 an out-of-combat read, 0 an update with no read
    Gear = 31, -- reserved
    ItemCooldown = 32, -- reserved
    Range = 33, -- a: plate index; b: count in range of the range spell
    TargetCast = 34, -- a: TargetCastOf; b: castBarID; c: interruptible 1 / 0 / -1 unknown
    TargetDamage = 35, -- b: a WOUND amount the target took (UNIT_COMBAT, plain); VirtualState's own, past TDF's range
}

--- What a `Read` observation read (its `c`): TDF's Enum.ReadOf integers (5 and 7-9 reserved), plus Health = 10, a
--- VirtualState kind past TDF's range.
I.ReadOf = { Resource = 1, Aura = 2, TargetAura = 3, Max = 4, Regen = 6, Health = 10 }

--- What a `TargetCast` observation reports (its `a`): TDF's Enum.TargetCastOf integers.
I.TargetCastOf = { Start = 1, ChannelStart = 2, End = 3, Interrupted = 4, Kickable = 5 }

-- Constants (spec §6), TDF's values (src/TacoDogForever/Model/Belief.lua:39-72; Belief/Resources.lua:26;
-- Belief/Swing.lua:46).
I.PIN_GAP = 1
I.ALPHA = 0.3
I.REGEN_SPREAD = 0.1
I.REGEN_SPREAD_MIN = 0.02
I.REGEN_RATIO = 2
I.EPS = 0.01
I.CD_PROBE = 0.5
I.SNAP_HOLD = 1
I.AURA_HALF_LIFE = 10
I.CAST_GRACE = 0.5
I.TARGET_CAP = 16
I.FALSE_START = 1
I.READ_HOLD = 2
I.SWING_DECAY = 10
I.SWING_TOL = 0.15
I.RING = 8 -- debug ring slots per origin (spec §2)

I.ORIGINS = { "observed", "pinned", "modelled", "default" }

-- Every record, with its label, in creation order (Snapshot and SetDebug walk them).
I.records, I.labels = {}, {}

local function sample()
    return { v = 0, t = 0, event = 0 }
end

--- A preallocated Belief record (spec §2). Allocates; build time only. `label` names it in Snapshot().
---@param label string
---@return table
function I.NewBelief(label)
    local rec = {
        est = 0,
        lo = 0,
        hi = 0,
        conf = 0,
        basis = "unknown",
        last = { observed = sample(), pinned = sample(), modelled = sample(), default = sample() },
    }
    local n = #I.records + 1
    I.records[n], I.labels[n] = rec, label
    if I.debug then
        I.AddRing(rec)
    end
    return rec
end

--- Forgets every record (SpecChanged rebuilds them). Build time only.
function I.ClearRecords()
    I.records, I.labels = {}, {}
end

--- Writes one sample into `rec.last[origin]` (and its debug ring when debug is on), then re-derives the basis.
--- Allocates nothing.
function I.Sample(rec, origin, v, t, event)
    local s = rec.last[origin]
    s.v, s.t, s.event = v, t, event
    local ring = rec.ring
    if ring then
        local r = ring[origin]
        r.head = r.head % I.RING + 1
        local e = r[r.head]
        e.v, e.t, e.event = v, t, event
    end
    I.Basis(rec)
end

--- The basis (spec §2): the newest of observed, pinned and modelled by t (ties in that order), else default when
--- one is in force, else "unknown". Allocates nothing.
function I.Basis(rec)
    local last = rec.last
    local o, p, m = last.observed.t, last.pinned.t, last.modelled.t
    if o == 0 and p == 0 and m == 0 then
        rec.basis = last.default.t > 0 and "default" or "unknown"
    elseif o >= p and o >= m then
        rec.basis = "observed"
    elseif p >= m then
        rec.basis = "pinned"
    else
        rec.basis = "modelled"
    end
end

--- Gives a record its debug rings: per origin, RING preallocated samples and a head index.
function I.AddRing(rec)
    local ring = {}
    for k = 1, #I.ORIGINS do
        local r = { head = 0 }
        for i = 1, I.RING do
            r[i] = sample()
        end
        ring[I.ORIGINS[k]] = r
    end
    rec.ring = ring
end

--- Creates (on) or drops (off) the debug rings of every record (spec §2, §3.5). Allocates when turned on.
---@param on boolean
function VS.SetDebug(on)
    I.debug = on and true or false
    for i = 1, #I.records do
        I.records[i].ring = nil
        if on then
            I.AddRing(I.records[i])
        end
    end
end

-- The static record an accessor returns for an entity nothing tracks: unknown, conf 0.
I.UNKNOWN = {
    est = 0,
    lo = 0,
    hi = 0,
    conf = 0,
    basis = "unknown",
    last = { observed = sample(), pinned = sample(), modelled = sample(), default = sample() },
}

-- Build hooks (families allocate their arrays and records) and the snapshot writers, in registration order.
I.BUILD, I.SNAPSHOT = {}, {}

--- Registers `fn(def, now)`, run by I.Build for every family. Load time only.
function I.OnBuild(fn)
    I.BUILD[#I.BUILD + 1] = fn
end

--- Registers `fn(out)`, which appends Snapshot() lines to `out`. Load time only.
function I.OnSnapshot(fn)
    I.SNAPSHOT[#I.SNAPSHOT + 1] = fn
end

-- What VirtualState.Tracked(kind) lists, by kind: arrays the families fill at build time.
I.TRACKED = {}

--- Fills the caller's array `out` with the tracked IDs of `kind` ("ability", "aura", "resource", "unit") and returns
--- the count. Allocates nothing.
---@param kind string
---@param out table
---@return integer
function VS.Tracked(kind, out)
    local list = I.TRACKED[kind]
    local n = list and #list or 0
    for i = 1, n do
        out[i] = list[i]
    end
    for i = n + 1, #out do
        out[i] = nil
    end
    return n
end

-- The pack exception (spec §3.6): IDs a class pack adds, merged at the next build.
I.extra = { abilities = {}, auras = {}, units = {}, talents = {} }

--- Adds IDs core does not already track: `abilities` (spell IDs: cooldown flags and usability only), `auras` (spell
--- IDs, tracked on every aura unit), `units` (unit tokens walked for auras), `talents` (alias spell ID = the talent's
--- registered spell ID). They join the tracked set at the next SpecChanged. Allocates; load time only.
---@param t table
function VS.Track(t)
    for kind, list in pairs(t) do
        local into = I.extra[kind]
        if into then
            for k, v in pairs(list) do
                if type(k) == "number" and kind ~= "talents" then
                    into[#into + 1] = v
                else
                    into[k] = v
                end
            end
        end
    end
end
