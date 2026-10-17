-- Game/State/Families/TargetHealth.lua
-- Target health (docs/superpowers/specs/2026-10-16-target-health-design.md): the current target's health as a
-- fraction 0..1, from the client's usability answer for an ability declaring `healthGate = g` (usable only at or
-- below g of the target's health). Usable bounds the health at or below g; a NOT under every guard of design §5
-- bounds it above g; a flip from such a NOT to usable pins it at g. M, the damage per full health, is learned at that
-- flip on a target never held before (full at the swap): M = the WOUND damage since the swap / (1 - g).
-- Between answers each WOUND moves the health down by amount / M (floor 0.02 while alive), written as a `modelled`
-- sample only from an anchor (R5): a target never held before (full), a combat end (an evade heals it full), or a pin.
-- No time to die: the user dropped it (2026-10-16); AplWarnings.lua warns when a priority reads one.
-- Not built until the in-game checkpoint (design §7) answers: a short answer (c = 1) as a health signal (line 4), and
-- a plain UnitHealthMax("target") read as M (line 2; its hook is marked below).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs

--- A live target's health never reads below this fraction (Targets.lua's UpdateTTDs drops an enemy at or below 1%).
I.TARGET_HEALTH_FLOOR = 0.02

-- What a gated ability's last answer said: nothing about health, above its gate (a guarded NOT), at or below it.
local UNKNOWN, ABOVE, BELOW = -1, 0, 1

-- By gated ability k (n of them): its ability index, gate, guard aura (the player aura index of its `buff` or `nobuff`:
-- 0 none, -1 named but untracked, which allows no NOT bound), whether that aura must be up (`buff`), its last answer,
-- and the damage taken at its last guarded NOT. The current target: its memory slot (0 none), dead, attackable
-- (TargetSwap c), fresh (TargetSwap b: never held before, so full at the swap), anchored (the health is known from a
-- full start or a pin since the last restart), the health interval, the WOUND damage since the swap, M (the damage per
-- full health; 0 unknown).
local H = {
    n = 0,
    ab = {},
    gate = {},
    aura = {},
    up = {},
    prev = {},
    notDmg = {},
    maxBy = {}, -- M by target memory slot: a swap back keeps it
    slot = 0,
    dead = false,
    attackable = false,
    fresh = false,
    anchored = false,
    est0 = 1,
    lo0 = 0,
    hi0 = 1,
    dmg = 0,
    M = 0,
}
I.th = H
local rec

-- The player aura index of an ability's `buff`/`nobuff` key (Resources.lua's swingAura): 0 none, -1 untracked.
local function auraIndex(def, key)
    if key == nil then
        return 0
    end
    for i = 1, #def.auras do
        if def.auras[i].key == key then
            return i
        end
    end
    return -1
end

-- Back to the default: 1.0 in [0, 1], no damage seen, no answer standing, no anchor; only the default sample counts
-- (basis "default"). Allocates nothing.
local function restart(t)
    H.est0, H.lo0, H.hi0, H.dmg, H.anchored = 1, 0, 1, 0, false
    for k = 1, H.n do
        H.prev[k] = UNKNOWN
    end
    local last = rec.last
    last.observed.t, last.pinned.t, last.modelled.t = 0, 0, 0
    I.Sample(rec, "default", 1, t, 0)
end

I.OnBuild(function(def, now)
    rec = I.NewBelief("health target")
    H.n = 0
    for a = 1, #def.abilities do
        local obj = def.abilities[a]
        local g = rawget(obj, "healthGate")
        if type(g) == "number" and g > 0 and g < 1 then
            local buff, nobuff = rawget(obj, "buff"), rawget(obj, "nobuff")
            local k = H.n + 1
            H.n, H.ab[k], H.gate[k], H.up[k], H.notDmg[k] = k, a, g, buff ~= nil, 0
            if buff ~= nil and nobuff ~= nil then
                H.aura[k] = -1 -- shortcut: both named allows no NOT bound; resolve both when an ability needs it
            else
                H.aura[k] = auraIndex(def, buff ~= nil and buff or nobuff)
            end
        end
    end
    for s = 1, I.TARGET_CAP do
        H.maxBy[s] = 0
    end
    H.slot, H.dead, H.attackable, H.fresh, H.M = 0, false, false, false, 0
    restart(now)
end)

-- Every guard of design §5 on reading a NOT as "above the gate" (the caller has checked a live target): the ability
-- known, its cost believed affordable, its guard aura as it needs, the target attackable. Range is not part of
-- IsSpellUsable; a gated ability has no cooldown. Allocates nothing.
local function guarded(k, a, t)
    if I.ab.known[a] == false or not H.attackable then
        return false
    end
    local r = I.ab.slot[a]
    if r > 0 and I.res.lo0[r] < I.CostOf(a) then
        return false
    end
    local j = H.aura[k]
    if j < 0 then
        return false
    elseif j == 0 then
        return true
    end
    local up = I.auras.exp0[1][j] > t -- unit 1 is always "player" (Adapter.lua's def.units)
    return up == H.up[k]
end

I.On(Obs.Usable, function(o, t, lag)
    local a, k = o.a, 0
    for i = 1, H.n do
        if H.ab[i] == a then
            k = i
        end
    end
    if k == 0 or H.slot == 0 or H.dead then
        return
    end
    local g = H.gate[k]
    if o.b == 1 then
        local was = H.prev[k]
        H.prev[k] = BELOW
        if was == ABOVE and lag <= I.PIN_EXACT then
            -- A flip: the health crossed g since the last guarded NOT, by at most the damage taken since then.
            local slack = H.M > 0 and (H.dmg - H.notDmg[k]) / H.M or 0 -- nonzero: M > 0 checked
            H.lo0, H.hi0 = g - slack > 0 and g - slack or 0, g
            H.est0 = (H.lo0 + H.hi0) / 2
            -- Hook (design §2.3b, deferred to §7 line 2): a plain UnitHealthMax("target") read would set M here,
            -- observed, winning over a learned one (as Resources.lua's maxRead). Until then M is learned or unknown.
            if H.fresh and H.dmg > 0 and H.M == 0 then
                H.M = H.dmg / (1 - g) -- nonzero: g < 1 (checked at the build)
            end
            H.anchored = true
            I.Sample(rec, "pinned", H.est0, t, Obs.Usable)
        else
            if H.hi0 > g then
                H.hi0 = g
            end
            if H.lo0 > g then
                H.lo0 = g -- the newest bound wins
            end
            if H.est0 > g then
                H.est0, H.anchored = g, true
                I.Sample(rec, "pinned", g, t, Obs.Usable)
            end
        end
    elseif o.c == 1 then
        -- shortcut: a short answer says nothing about health until design §7 line 4 shows short means at or below
        -- the gate; then it joins the usable branch above.
        H.prev[k] = UNKNOWN
    elseif lag <= I.PIN_EXACT and guarded(k, a, t) then
        local top = g + I.EPS
        H.prev[k], H.notDmg[k] = ABOVE, H.dmg
        if H.lo0 < top then
            H.lo0 = top
        end
        if H.hi0 < top then
            H.hi0 = 1 -- the newest bound wins: it healed (an evade) since the bound below
        end
        if H.est0 < top then
            H.est0 = top
            I.Sample(rec, "pinned", top, t, Obs.Usable)
        end
    else
        H.prev[k] = UNKNOWN
    end
end)

-- A swap (a: the new slot, 0 none; b: 1 never held before; c: 1 attackable) keeps the old slot's M and starts the new
-- target over at the default with its own. Families/Auras.lua has already moved I.curSlot; H.slot is the old one here.
I.On(Obs.TargetSwap, function(o, t)
    if H.slot > 0 then
        H.maxBy[H.slot] = H.M
    end
    H.slot, H.dead = o.a, false
    H.M = o.a > 0 and H.maxBy[o.a] or 0
    H.fresh, H.attackable = o.b == 1, o.c == 1
    restart(t)
    H.anchored = H.fresh -- a swap back has no anchor until a pin (R5)
end)

-- WOUND damage the target took (UNIT_COMBAT, plain; everyone's hits): counted from the swap (M's numerator); with M
-- known, the health moves down by amount / M, a live target never below the floor, sampled only from an anchor (R5).
I.On(Obs.TargetDamage, function(o, t)
    if H.slot == 0 or H.dead then
        return
    end
    H.dmg = H.dmg + o.b
    if H.M > 0 then
        local d, floor = o.b / H.M, I.TARGET_HEALTH_FLOOR -- nonzero: M > 0 checked
        H.est0 = H.est0 - d > floor and H.est0 - d or floor
        H.lo0 = H.lo0 - d > floor and H.lo0 - d or floor
        H.hi0 = H.hi0 - d > floor and H.hi0 - d or floor
        if H.anchored then
            I.Sample(rec, "modelled", H.est0, t, Obs.TargetDamage)
        end
    end
end)

-- A death (poll 4) or a slot taken for another GUID: the slot forgets M; the current target reads 0, observed, until
-- the next swap.
I.On(Obs.TargetGone, function(o, t)
    local s = o.a
    if s <= 0 then
        return
    end
    H.maxBy[s] = 0
    if s == H.slot then
        H.dead, H.M = true, 0
        H.est0, H.lo0, H.hi0 = 0, 0, 0
        I.Sample(rec, "observed", 0, t, Obs.TargetGone)
    end
end)

-- Combat end: an evade heals, so a live target starts over full: an anchor, though M is no longer learnable.
I.On(Obs.CombatEnd, function(o, t)
    if not H.dead then
        H.fresh = false
        restart(t)
        H.anchored = true
    end
end)

--- (design §3) The current target's health fraction: the interval as folded, conf 1 - its width (0 at the default).
--- VS.Health("target") answers it (Families/Player.lua). Allocates nothing.
function I.TargetHealth(now)
    rec.est, rec.lo, rec.hi = H.est0, H.lo0, H.hi0
    rec.conf = 1 - (H.hi0 - H.lo0)
    return rec
end

I.OnSnapshot(function(out, now)
    I.TargetHealth(now)
    out[#out + 1] = string.format(
        "target health slot=%d gates=%d M=%.0f dmg=%.0f fresh=%s anchored=%s attackable=%s dead=%s",
        H.slot,
        H.n,
        H.M,
        H.dmg,
        tostring(H.fresh),
        tostring(H.anchored),
        tostring(H.attackable),
        tostring(H.dead)
    )
end)
