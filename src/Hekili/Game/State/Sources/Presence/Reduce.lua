-- Game/State/Sources/Presence/Reduce.lua
-- The fact reducer (cdm-default spec §2.3, decision 94): one thing's evidence counters in, one reduced state and an
-- agree flag out. Pure and total: numbers only, no tables, no state, no game calls. The seen rule (§2.2a, decision 115)
-- is folded into liveness by the leaf; disagreement transitions are counted by the router (§2.4). Counts are tested
-- `> 0` as the spec's rows say, so a negative count (a leaf un-count imbalance) fails safe to UNKNOWN, never DOWN.
-- The presence-bit-on-items idea is from TellMeWhen (Cybeloras), GPL-3.0; ideas only, no code copied.

local _, ns = ...
local I = ns.VirtualStateInternal

local UP, DOWN, UNKNOWN = I.UP, I.DOWN, I.UNDECIDED

---@return integer state I.UP, I.DOWN or I.UNDECIDED
---@return boolean agree false when live slots answer both UP and NONE
function I.ReduceFact(nLive, nUp, nNone, nStale, tUp, tNone)
    local up, none = nUp > 0, nNone > 0
    if nLive <= 0 or not (up or none) then
        return UNKNOWN, true
    end
    if not none then
        return UP, true
    end
    if not up then
        if nStale == 0 then
            return DOWN, true
        end
        return UNKNOWN, true
    end
    if tUp >= tNone then
        return UP, false
    end
    return UNKNOWN, false
end
