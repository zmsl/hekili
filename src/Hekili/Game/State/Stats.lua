-- Game/State/Stats.lua
-- The belief layer's running statistics, written once (owner ruling 2026-10-22, the belief-layer audit): an
-- exponential moving average with a mean-absolute-deviation spread and a floor (Resources' regen calibration and hit
-- rate, Attackers' learned period, the flight lag of Events/Tickets.lua), and a sign-step running median with a
-- clamped spread (Melee's swing landing lag). Pure arithmetic: no table, no client read.

local _, ns = ...
local I = ns.VirtualStateInternal

local Stats = {}
I.Stats = Stats
Stats.SPR_LO, Stats.SPR_HI, Stats.SPR_ALPHA = 0.02, 0.4, 0.05
local abs = math.abs

--- x clamped to [lo, hi]. Allocates nothing.
function Stats.Clamp(x, lo, hi)
    return x < lo and lo or (x > hi and hi or x)
end

--- One sample into an EMA: the new estimate, the new deviation (an EMA of |sample - the new estimate|) and the spread
--- (that deviation, never below `floor`). Allocates nothing.
function Stats.Ema(est, dev, sample, alpha, floor)
    local e = est + alpha * (sample - est)
    local d = dev + alpha * (abs(sample - e) - dev)
    return e, d, d > floor and d or floor
end

--- One sample d into a sign-step running median `med` (a step of `step` toward d, then clamped to [lo, hi]) and its
--- spread (mean absolute deviation to SD, 1.2533 x |d - med| against the stepped median, an EMA of SPR_ALPHA, clamped
--- to [SPR_LO, SPR_HI]). Allocates nothing.
function Stats.Median(med, spr, d, step, lo, hi)
    med = med + step * (d > med and 1 or -1)
    spr = Stats.Clamp(spr + Stats.SPR_ALPHA * (1.2533 * abs(d - med) - spr), Stats.SPR_LO, Stats.SPR_HI)
    return Stats.Clamp(med, lo, hi), spr
end
