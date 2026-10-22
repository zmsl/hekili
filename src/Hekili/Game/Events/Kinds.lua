-- Game/Events/Kinds.lua
-- Each engine kind's matching rule, once (unit-registry spec §3.3, §3.4): which rows an open ticket accepts (an avoid
-- pays any kind that owes a row; a WOUND only a kind of its school, or ANY; a school of 0 only an avoid) and its band
-- per pass (1 narrow, 2 widened, 3 hard) with its expected closure E. MELEE's rule is Events/Melee.lua's; NONE and
-- UNMAPPED accept no row. Packs write no matching code: they declare data (Families/Expect.lua). Pure.

local _, ns = ...
local I = ns.VirtualStateInternal
local L = I.Log
local T, M, X = I.Tickets, I.Melee, I.Expect

local K = {}
I.Kinds = K
-- Fix 31 G4, now the UNMAPPED kind's window: an avoid or crit within it of a success the kit does not map, past another
-- ticket's own frame, is nobody's. UNMEASURED: a chosen bound (the Affliction log's thrown explosive, 1.43 s).
L.UNMAPPED_WINDOW = 2
local SAME_FRAME, CAST_WINDOW = M.SAME_FRAME, M.CAST_WINDOW
local REFUSED = { DODGE = true, PARRY = true, MISS = true }
local FRAME, STRIKE, MELEE, UNMAPPED, NONE, ANY = X.FRAME, X.STRIKE, X.MELEE, X.UNMAPPED, X.NONE, X.ANY

--- Whether open ticket i accepts a row of `act` (an avoid when `isAvoid`) and school `sch` (spec §3.4 step 2), and
--- whether a learned amount band accepted it (Tasks 7 and 8 add the bands; T.Pick ranks banded candidates first).
function K.Accepts(i, act, flag, amount, sch, isAvoid)
    local k = T.kind[i]
    if T.owed[i] <= 0 or k == MELEE or k == UNMAPPED or k == NONE then
        return false
    elseif isAvoid then
        return true
    end
    local s = T.school[i]
    return s == ANY or (s > 0 and s == sch)
end

--- Ticket i's band at pass p for a row at t: lo, hi (absolute) and its expected closure E; nil when it has none.
function K.Band(i, p, t, isAvoid, act, sch)
    local k, a0 = T.kind[i], T.at[i]
    if k == FRAME or k == STRIKE then
        if p == 1 then
            return a0, a0 + SAME_FRAME, a0
        elseif isAvoid then
            -- GAP AX: the landing window for a refused avoid while others rarely avoid, else the cast's own window
            if REFUSED[act] and L.bg[7] < L.FOREIGN_AVOIDS then
                return a0, a0 + T.w[i], a0
            end
            return a0, a0 + CAST_WINDOW, a0
        elseif T.school[i] == ANY and sch ~= 1 then
            return nil -- a default type takes a non-white wound only in its frame (Rows.lua:458, :497 before)
        end
        return a0, a0 + CAST_WINDOW, a0
    end
end
