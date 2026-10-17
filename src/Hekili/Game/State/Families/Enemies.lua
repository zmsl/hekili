-- Game/State/Families/Enemies.lua
-- Enemies (spec §6.9): the nameplate walk's count of live, attackable plates (`observed`, default 1 without plates)
-- and the range poll's counts. In Phase 1 no Hekili code reads VirtualState.Count: Hekili's enemy scan still counts
-- plates through the UnitHealth policy (spec §7.4).
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Targets.lua (Applier Enemies :184).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs

local rec
-- By ability index: plates in range of that ability's spell at the last range poll.
I.inRange = {}

I.OnBuild(function(def, now)
    rec = I.NewBelief("enemies")
    rec.est, rec.lo, rec.hi = 1, 1, 1
    I.Sample(rec, "default", 1, now, 0)
    for a = 1, #def.abilities do
        I.inRange[a] = 0
    end
end)

I.On(Obs.Enemies, function(o, t)
    local n = o.b > 0 and o.b or 1
    if rec.est ~= n or rec.last.observed.t == 0 then
        I.Sample(rec, o.b > 0 and "observed" or "default", n, t, Obs.Enemies)
    end
    rec.est, rec.lo, rec.hi = n, n, n
end)

I.On(Obs.Range, function(o)
    I.inRange[o.a] = o.b
end)

--- (spec §3.3) Belief count of enemies: the nameplate walk, default 1.
function VS.Count.Enemies(now)
    I.AgeConf(rec, now)
    return rec
end

--- (spec §3.3) Tracked enemies in range of the spell (the range poll covers the tracked attacks); 0 for any other.
function VS.Count.InRange(spellID, now)
    local a = I.ab.bySpell[spellID]
    return a and I.inRange[a] or 0
end
