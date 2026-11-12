-- Game/State/Families/Enemies.lua
-- Enemies (spec §6.9): the target's range. The belief keeps no plate count: Hekili's enemy scan counts plates through
-- the UnitHealth policy (spec §7.4).
-- The target's range (gap 13, wowsims unitDistance): the bracket in yards [lo, hi] is LibRangeCheck-3.0's (range plan
-- R2: Sources/Target.lua's poll 14 reads it through the facade's RangeLib); the last bracket stays believed through
-- polls with no plain answer (a secret, raising or silent library) for under 1.5 s, then the poll's age-out makes it
-- unknown (batch review I1), as a target swap does.
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

-- Unknown until the next plain answer.
local function forget()
    range.est, range.lo, range.hi, range.conf = 0, 0, HUGE, 0
    range.last.observed.t = 0
    I.Basis(range)
end

-- TargetRange (a: lo, b: hi yards) at t: est the bracket's middle; with no upper bound, up to FAR yards (or lo).
-- a = -1: the poll's age-out, no plain answer for a while.
local FAR = 40 -- yards: past every range answered, the farthest spell ranges (the engine's maxR then)
I.On(Obs.TargetRange, function(o, t)
    if o.a < 0 then
        forget()
        return
    end
    range.lo, range.hi = o.a, o.b
    range.est, range.conf = (o.a + (o.b < HUGE and o.b or math.max(o.a, FAR))) / 2, 1
    I.Sample(range, "observed", range.est, t, Obs.TargetRange)
end)

-- A new target (or none): its distance is unknown until the next poll answers.
I.On(Obs.TargetSwap, forget)

--- The target's distance in yards: { est, lo, hi (math.huge: no bound), basis } (basis "unknown": no plain range
--- answer for this target yet, or none for 1.5 s; I.UNKNOWN before the first build). Allocates nothing.
function VS.TargetRange()
    return range or I.UNKNOWN
end
