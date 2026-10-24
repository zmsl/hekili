-- Game/Events/Melee.lua
-- The MELEE kind (unit-registry spec §3.3, §3.4; moved unchanged from Events/Rows.lua): a white (school 1) outcome is
-- scored against our open swing tickets, LR = q(amount class) x f(landing lag) / lambda(the learned background rate of
-- that class), and credited to the best swing when LR >= THETA (avoids) or theta[k] (wounds), else it is background.
-- The landing-lag density per reference (main from its swing; off from its own swing or its main reference), learned
-- from clean credits; the amount classes from UnitDamage; the background rates over the quiet time. Also the frame
-- constants every spell kind shares. Pure: reads VS.Stat only.
-- Measured: docs/research/2026-10-16-swing-outcome-pairing.md (P), docs/research/2026-10-16-group-pairing-captures.md
-- (G, G5).

local _, ns = ...
local I = ns.VirtualStateInternal
local VS = ns.VirtualState
local L = I.Log
local T, X = I.Tickets, I.Expect

local M = {}
I.Melee = M

-- Per hand (1 main, 2 off), the support of a swing's landing lag (ms), capped at the hand's swing period: measured
-- maximum lags 1287 / 1686 ms plus a margin (P log 2).
L.PAIR_WINDOW_MS = { 1500, 2000 }
-- Seconds a cast waits for its own wound, and within which an on-next-swing strike's success and its swing are one
-- event pair (the same frame, log 1).
M.CAST_WINDOW, M.STRIKE_WINDOW = 0.2, 0.2
-- Seconds within which a cast's own wound comes (its frame); also the foreign strike frame after a WOUND 0
-- (G 177249/177250).
M.SAME_FRAME = 0.05
local CAST_WINDOW = M.CAST_WINDOW
-- The window our cast's own avoid may follow its success in: a main-hand landing lag's window (the learned median
-- plus three spreads). Hand h's; also how long a swing's rage stays pending (VS.SwingPending).
function L.LandWindow(h)
    return L.med[h] + 3 * L.spr[h]
end
-- GAP AX (docs/dev/gaps.md): the landing window holds for a refused avoid only while L.bg[7] stays below this.
-- UNMEASURED: a chosen constant (GAP AX residue in docs/dev/gaps.md).
L.FOREIGN_AVOIDS = 0.05

-- Parry haste (parry-haste spec decision 57; wowsims's attack.go applyParryHaste, taken as Forever's rule by the
-- owner's ruling of 2026-10-23): a unit that parries pulls its main-hand swing, due in r s of duration d, by
-- min(PULL x d, r - FLOOR x d) when r > FLOOR x d. A game rule: no pack field. PHS1 confirms it on launch day.
L.PARRY_PULL, L.PARRY_FLOOR = 0.4, 0.2

--- The pull (seconds) of a parrier's main-hand swing due in `r` s with duration `d`; 0 when none. Allocates nothing.
function L.ParryPull(r, d)
    local least = L.PARRY_FLOOR * d
    if d <= 0 or r <= least then
        return 0
    end
    local cap = L.PARRY_PULL * d
    return r - least < cap and r - least or cap
end

-- The score (harness design §1.2-§1.4, decision D1; PROTOTYPE values, the harness's gates hold them).
L.THETA = 5
L.Q = { 0.90, 0.08, 0.02 }
L.Q_AVOID = 0.22
L.EPS = { 0.12, 0.10 }
L.LAMBDA0, L.T0, L.TAU = 0.01, 5, 10
-- The landing lag per reference (1 main; 2 off from its own swing; 3 off from the latest main swing), seeds
-- (MEASURED: P log 2, G5) learned online from clean credits.
L.med, L.spr = { 0.474, 0.703, 1.686 }, { 0.060, 0.020, 0.020 }
-- The background: per class (1-3 main exact, loose, above; 4-6 off; 7 avoid; 8 white, any amount) and the quiet time.
L.bg, L.quiet = { 0, 0, 0, 0, 0, 0, 0, 0 }, 0
local lastT = 0
L.credited, L.background, L.avoidsBack = { 0, 0, 0 }, 0, 0
L.avoids, L.avoidX, L.avoidT = 0, 0, 0
-- The usability oracle (harness design §2, decision D8).
L.ORACLE_MIN = 0.1
L.THETA_MIN, L.THETA_MAX = 2, 16
L.theta = {}
for k = 1, 16 do
    L.theta[k] = L.THETA
end
L.oracle = { judged = 0, confirmed = 0, retracted = 0, soft = 0, vetoed = 0 }
L.vetoX, L.vetoAt = 0, 0

-- The avoids a swing can have (school 1).
M.AVOIDS = { DODGE = true, PARRY = true, MISS = true, BLOCK = true, DEFLECT = true, EVADE = true }
local AVOIDS = M.AVOIDS

--- Whether an action of ours is pending at t for the background: a swing, or a spell within CAST_WINDOW of its
--- anchor (past it a spell waits only for an avoid, which the background's wound rates do not see).
function M.pending(t)
    for i = 1, T.CAP do
        local k = T.kind[i]
        if T.state[i] >= T.OPEN and k ~= X.UNMAPPED and (k == X.MELEE or t - T.at[i] <= CAST_WINDOW) then
            return true
        end
    end
    return false
end

--- The background's clock: in combat the counts and the quiet time decay by exp(-dt / TAU), and the quiet time grows
--- while nothing of ours is pending. Allocates nothing.
function M.advance(t)
    if t <= lastT then
        return
    end
    if I.inCombat then
        local dt = t - lastT
        local k = math.exp(-dt / L.TAU)
        local bg = L.bg
        for c = 1, 8 do
            bg[c] = bg[c] * k
        end
        L.quiet = L.quiet * k + (M.pending(t) and 0 or dt)
    end
    lastT = t
end

--- The background rate of class c (nonzero: T0 > 0).
function M.lambda(c)
    return (L.bg[c] + L.LAMBDA0 * L.T0) / (L.quiet + L.T0)
end

--- The amount class of a wound for hand h (1 exact, 2 loose, 3 above, 0 none), on half a crit (Rows.lua's rule).
function M.classOf(h, amount, flag)
    local minMain, maxMain, minOff, maxOff = VS.Stat("UnitDamage")
    local lo, hi = minMain, maxMain
    if h == 2 then
        lo, hi = minOff, maxOff
    end
    -- a glancing or partly blocked hit opens the loose band down to 0 (G's glancing 1-5 are another player's)
    local looseLo = (flag == "GLANCING" or flag == "BLOCK_REDUCED") and 0 or 0.6 * lo
    return I.Bands.Class(I.Bands.Normalise(amount, flag, "ours"), lo, hi, looseLo)
end

local function normal(d, m, s)
    local z = (d - m) / s -- nonzero: spr clamped at 0.02 s
    return math.exp(-0.5 * z * z) / (s * 2.5066283)
end

--- The landing-lag density of swing ticket i for an outcome at t (0 outside its window) and the reference that scored.
function M.density(i, t)
    local d, win = t - T.at[i], T.w[i]
    if d < 0 or d > win then
        return 0, 0
    end
    local med, spr = L.med, L.spr
    if T.x[i] == 1 then
        return (1 - L.EPS[1]) * normal(d, med[1], spr[1]) + L.EPS[1] / win, 1 -- nonzero: win > 0
    end
    local f, r = normal(d, med[2], spr[2]), 2
    if T.ref[i] > 0 then
        local m = normal(t - T.ref[i], med[3], spr[3])
        if m > f then
            f, r = m, 3
        end
    end
    return (1 - L.EPS[2]) * f + L.EPS[2] / win, r -- nonzero: win > 0
end

--- A clean credit moves its reference's median and spread (a running median; mean absolute deviation to SD).
function M.learn(r, d)
    L.med[r], L.spr[r] = I.Stats.Median(L.med[r], L.spr[r], d, 0.005, 0, L.PAIR_WINDOW_MS[r == 1 and 1 or 2] / 1000)
end

--- The theta index of hand h's amount class `cls` (1-3, 4 unknown) at lag d from reference `r`: core band or tail.
function M.thetaIndex(h, cls, r, d)
    local band = math.abs(d - L.med[r]) <= 2 * L.spr[r] and 1 or 2
    return (h - 1) * 8 + (cls - 1) * 2 + band
end

--- The best open swing ticket on `g` (nil: any) for an outcome at t: its index, LR, reference, lag, the runner-up's LR
--- and its theta index. Allocates nothing.
function M.score(t, g, amount, flag, avoid, unknown)
    local best, bestLR, r0, lag, second, idx = nil, 0, 0, 0, 0, 1
    for i = 1, T.CAP do
        if
            T.state[i] ~= 0
            and T.state[i] ~= T.TENT -- credited provisionally: replaced only by M.Replaceable (decision 48)
            and T.kind[i] == X.MELEE
            and (g == nil or T.guid[i] == g)
            and not (avoid and T.avoid[i] ~= "")
            and not (not avoid and T.told[i] == 2) -- the provider said AVOID: no wound is its (providers decision 70)
        then
            local f, r = M.density(i, t)
            local q, c, cls = L.Q_AVOID, 7, 4
            if not avoid then
                if unknown then
                    q, c = 1, 8
                else
                    cls = M.classOf(T.x[i], amount, flag)
                    q, c = cls > 0 and L.Q[cls] or 0, (T.x[i] - 1) * 3 + cls
                end
            end
            local lri = f > 0 and q > 0 and q * f / M.lambda(c) or 0
            if lri > T.lr[i] or T.avoid[i] == "" then -- a wound takes a provisionally avoided swing only by beating it
                if lri > bestLR then
                    local d = r == 3 and t - T.ref[i] or t - T.at[i]
                    best, bestLR, r0, lag, second = i, lri, r, t - T.at[i], bestLR
                    idx = M.thetaIndex(T.x[i], cls, r, d)
                elseif lri > second then
                    second = lri
                end
            end
        end
    end
    return best, bestLR, r0, lag, second, idx
end

--- (attribution-recovery decision 48) The oldest TENT swing ticket on `g` (credited outside its core band) whose
--- core band holds a white row at t: a wound in an amount class of its hand (or unknown), or an avoid. Nil when none.
--- Allocates nothing.
function M.Replaceable(t, g, amount, flag, avoid, unknown)
    local best = nil
    if T.nTent == 0 then
        return nil
    end
    for i = 1, T.CAP do
        if T.state[i] == T.TENT and T.kind[i] == X.MELEE and T.guid[i] == g and t <= T.fin[i] then
            local h, rf = T.x[i], T.ref[i]
            if
                (
                    math.abs(t - T.at[i] - L.med[h]) <= 2 * L.spr[h]
                    or (rf > 0 and math.abs(t - rf - L.med[3]) <= 2 * L.spr[3])
                )
                and (avoid or unknown or M.classOf(h, amount, flag) > 0)
                and (best == nil or T.at[i] < T.at[best])
            then
                best = i
            end
        end
    end
    return best
end

--- An outcome nobody of ours claimed: counted, and while in combat with nothing of ours pending it teaches the
--- background rate of each white class it qualifies for (§1.3, §1.4).
function M.background(act, amount, flag, white, avoid, unknown)
    L.background = L.background + 1
    if M.pending(lastT) or not I.inCombat or not white then
        return
    end
    local bg = L.bg
    if avoid then
        if AVOIDS[act] then
            bg[7] = bg[7] + 1
        end
        return
    end
    bg[8] = bg[8] + 1
    if not unknown then
        for h = 1, 2 do
            local cls = M.classOf(h, amount, flag)
            if cls > 0 then
                bg[(h - 1) * 3 + cls] = bg[(h - 1) * 3 + cls] + 1
            end
        end
    end
end
