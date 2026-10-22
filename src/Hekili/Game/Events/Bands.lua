-- Game/Events/Bands.lua
-- Amount bands, written once (owner ruling 2026-10-22, the belief-layer audit): a hit's amount normalised to its
-- unmodified size, and band records kept in the caller's arrays (lo, hi, n by index) with their learning, their fit
-- and a fixed range's grades. Callers: Melee's white amount classes (a fixed UnitDamage range), Attackers' bands per
-- attacker, the ticket pool's cast bands. Pure: no table, no client read.

local _, ns = ...
local I = ns.VirtualStateInternal

local B = {}
I.Bands = B

--- A hit's amount as its unmodified size, or nil: a crit halved; `policy` "theirs" (hits on us) also divides a
--- crushing blow by 1.5 and drops a partly blocked hit (its blocked part is not given); "ours" keeps both as given.
function B.Normalise(amount, flag, policy)
    if type(amount) ~= "number" then
        return nil
    elseif flag == "CRITICAL" then
        return amount / 2
    elseif policy == "theirs" and flag == "CRUSHING" then
        return amount / 1.5
    elseif policy == "theirs" and flag == "BLOCK_REDUCED" then
        return nil
    end
    return amount
end

--- Band k learns v: the first value sets both ends; a new low or high takes it; otherwise each end creeps toward v by
--- `creep` (0: plain min and max). Allocates nothing.
function B.Learn(lo, hi, n, k, v, creep)
    if n[k] == 0 then
        lo[k], hi[k] = v, v
    else
        lo[k] = v < lo[k] and v or lo[k] + creep * (v - lo[k])
        hi[k] = v > hi[k] and v or hi[k] + creep * (v - hi[k])
    end
    n[k] = n[k] + 1
end

--- Whether band k, taught at least minN values, holds v within [kLo x lo, kHi x hi].
function B.Fits(lo, hi, n, k, v, kLo, kHi, minN)
    return v ~= nil and n[k] >= minN and v >= kLo * lo[k] and v <= kHi * hi[k]
end

--- v's grade against a fixed range [lo, hi]: 1 inside, 2 loose [looseLo, 1.1 hi], 3 above (1.1 hi, 2 hi], 0 none.
function B.Class(v, lo, hi, looseLo)
    if hi <= 0 or v < looseLo or v > 2 * hi then
        return 0
    elseif v >= lo and v <= hi then
        return 1
    end
    return v <= 1.1 * hi and 2 or 3
end
