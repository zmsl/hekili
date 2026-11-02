-- Game/State/Families/Enemies.lua
-- Enemies (spec §6.9): the target's range. The belief keeps no plate count: Hekili's enemy scan counts plates through
-- the UnitHealth policy (spec §7.4).
-- The target's range (gap 13, wowsims unitDistance): Sources/Target.lua's poll 14 brackets the distance in yards
-- [lo, hi] from the tracked abilities' own ranges (plain C_Spell.IsSpellInRange); the last bracket stays believed
-- through polls with no plain answer (a secret or nil read), a target swap forgets it (unknown).
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Targets.lua (Applier Enemies :184).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs

local range
local HUGE = math.huge

I.OnBuild(function()
    range = I.NewBelief("target range")
    range.hi = HUGE
end)

-- TargetRange (a: lo, b: hi yards) at t: est the bracket's middle; with no upper bound, up to FAR yards (or lo).
local FAR = 40 -- yards: past every range answered, the farthest spell ranges (the engine's maxR then)
I.On(Obs.TargetRange, function(o, t)
    range.lo, range.hi = o.a, o.b
    range.est, range.conf = (o.a + (o.b < HUGE and o.b or math.max(o.a, FAR))) / 2, 1
    I.Sample(range, "observed", range.est, t, Obs.TargetRange)
end)

-- A new target (or none): its distance is unknown until the next poll answers.
I.On(Obs.TargetSwap, function()
    range.est, range.lo, range.hi, range.conf = 0, 0, HUGE, 0
    range.last.observed.t = 0
    I.Basis(range)
end)

--- The target's distance in yards: { est, lo, hi (math.huge: no bound), basis } (basis "unknown": no plain range
--- answer for this target yet; I.UNKNOWN before the first build). Allocates nothing.
function VS.TargetRange()
    return range or I.UNKNOWN
end
