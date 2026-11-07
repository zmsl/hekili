-- Game/State/Sources/Presence/Reduce.lua
-- The fact reducer (cdm-default spec §2.3, decision 94): one thing's evidence counters in, one reduced state and an
-- agree flag out. Pure and total: numbers only, no tables, no state, no game calls. nNone counts trusted NONEs only
-- (item trust is folded into liveness by the leaf, §2.2a); disagreement transitions are counted by the router (§2.4).
-- The presence-bit-on-items idea is from TellMeWhen (Cybeloras), GPL-3.0; ideas only, no code copied.

local _, ns = ...
local I = ns.VirtualStateInternal

local UP, DOWN, UNKNOWN = I.UP, I.DOWN, I.UNDECIDED

---@return integer state I.UP, I.DOWN or I.UNDECIDED
---@return boolean agree false when live slots answer both UP and NONE
function I.ReduceFact(nLive, nUp, nNone, nStale, tUp, tNone)
    if nLive == 0 or (nUp == 0 and nNone == 0) then
        return UNKNOWN, true
    end
    if nNone == 0 then
        return UP, true
    end
    if nUp == 0 then
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
