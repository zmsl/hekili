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
local FLIGHT, TICKS, CHANNEL = X.FLIGHT, X.TICKS, X.CHANNEL
K.SPELL_BAND_LO, K.SPELL_BAND_HI, K.BAND_N = 0.6, 1.6, 3
K.TICK_BAND_LO, K.TICK_BAND_HI = 0.5, 2

-- Seconds after its anchor before which a flight to ticket i's GUID cannot land, from the target's plain range
-- bracket (poll 14) when the GUID is the current target: the bracket's distance less CLOSE x (anchor - bracket),
-- flown at v + CLOSE (a mob running in meets the projectile), less TOL, never below 0. The bracket's upper bound is
-- never used (a closing mob makes it stale on the wrong side).
local function rangeLow(i, v)
    if T.guid[i] ~= I.Units.Bound(1) then
        return 0
    end
    local r = ns.VirtualState.TargetRange()
    -- a bracket logged after the success can sit above the true lag (the mob closed meanwhile): unused
    if not (r.lo and r.lo > 0 and r.last) or r.last.observed.t > T.at[i] then
        return 0
    end
    local lo = (r.lo - T.CLOSE * (T.at[i] - r.last.observed.t)) / (v + T.CLOSE) - T.TOL
    return lo > 0 and lo or 0
end

--- (spec §3.3.1) A flight's band for ticket i at pass p (speed v, hard window H from anchor a0): with no (GUID, v)
--- record, only the whole hard window at pass 3 (E its middle; Overdue, decision 33); with one, the narrow band
--- lagE +- b at pass 1 and the widened band at pass 2 (from the bound a mob running in at CLOSE since the record's
--- last anchor allows, less b, up to lagE + CLOSE / 2 / v per second of it), clipped to the hard window, and
--- nothing at pass 3. While a foreign row of the ticket's school reached its unit within T.CROWD s (T.Crowded), the
--- widened band's lower edge is lagE less CLOSE / v per second of it (at least b) instead of the bound.
function K.Flight(i, p, t, v, H, a0)
    local lo0, hiH = a0 + rangeLow(i, v), a0 + H
    local r = T.LagOf(T.guid[i], v)
    if r == 0 then
        if p < 3 then
            return nil
        end
        return lo0, hiH, a0 + H / 2
    elseif p == 3 then
        return nil
    end
    local e = a0 + T.lagE[r]
    local b = 2 * T.lagSpr[r] > T.TOL and 2 * T.lagSpr[r] or T.TOL
    local lo, h = e - b, e + b
    if p == 2 then
        -- a lag measures the distance at its ticket's anchor: the closing time runs anchor to anchor (lagT - lagE is
        -- the record's last paid anchor); landing to row would miss the lag the mob already removed
        local d = a0 - (T.lagT[r] - T.lagE[r])
        if T.Crowded(T.uid[i], T.school[i], t) then -- the crowd gate: another source of this school on the unit
            local down = T.CLOSE / v * d
            lo = e - (down > b and down or b)
        else -- the distance left at this anchor, flown at v + CLOSE: a mob running in meets the projectile
            local bound = (T.lagE[r] * v - T.CLOSE * d) / (v + T.CLOSE)
            lo = a0 + (bound > 0 and bound or 0) - b
        end
        local up = T.CLOSE / 2 / v * d
        h = e + (up > b and up or b)
    end
    return lo > lo0 and lo or lo0, h < hiH and h or hiH, e
end

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
    if not (s == ANY or (s > 0 and s == sch)) then
        return false
    end
    if k == TICKS then -- owner ruling 2026-10-22: no band before the first paid tick, then [0.5x, 2x] of the last one
        local m = T.tickAmt[i]
        if m <= 0 then
            return true, false
        end
        local v = flag == "CRITICAL" and amount / 2 or amount
        if v < K.TICK_BAND_LO * m or v > K.TICK_BAND_HI * m then
            return false, true -- refused by the band (T.Pick counts T.bandRejected once per row)
        end
        return true, false -- a tick's band filters but never ranks: a banded direct ticket takes the row first (K21)
    end
    local a = T.ab[i]
    if a > 0 and k ~= CHANNEL and T.bandN[a] >= K.BAND_N then
        local B = I.Bands
        local v = B.Normalise(amount, flag, "ours")
        if not B.Fits(T.bandLo, T.bandHi, T.bandN, a, v, K.SPELL_BAND_LO, K.SPELL_BAND_HI, K.BAND_N) then
            return false, true -- a learned band refused it (T.Pick counts T.bandRejected once per row)
        end
        return true, true -- a learned band accepted it: ranked first (T.Pick)
    end
    return true, false
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
    if k == TICKS then
        if isAvoid then -- only an alone ticket's application, before its first tick (decision 35)
            if T.link[i] == -1 or T.done[i] > 0 then
                return nil
            elseif T.speed[i] > 0 then
                return K.Flight(i, p, t, T.speed[i], T.H[i], a0)
            elseif p == 1 then -- its own frame, as FRAME's: Rows absorbs an avoid past it in an UNMAPPED window
                return a0, a0 + SAME_FRAME, a0
            end
            return a0, a0 + L.LandWindow(1), a0
        end
        local e = T.anchor[i] + (T.done[i] + 1) * T.period[i]
        local half = T.TICK_BAND + T.wide[i] -- the schedule is the only discriminator: every pass alike
        return e - half, e + half, e
    elseif k == CHANNEL then
        local e = a0 + (T.done[i] + 1) * T.period[i]
        local half = p == 1 and T.TOL or 2 * T.TOL
        return e - half, e + half, e
    end
    if k == FLIGHT then
        return K.Flight(i, p, t, T.speed[i], T.H[i], a0)
    end
end
