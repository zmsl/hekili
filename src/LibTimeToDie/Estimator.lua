-- Estimator.lua: the estimator of one health stream, lifted as is from the TTD lab (branch ttd-lab b00ce4af2,
-- tools/ttd_lab/estimator.lua; the paths its comments name are on that branch). Only this header and the footer are
-- the library's: the lines between the two markers are the lab's file byte for byte, its last line (return E) moved
-- into the footer. Loaded alone (no LibStub: the busted specs) it returns the module.
local lib = LibStub and LibStub("LibTimeToDie-1.0", true)
if lib and not lib.loading then
    return
end
-- lifted body begins
-- Time to die for one health stream seen as 1% bands (the band lo..hi, hi = lo + 1, the top cell 99-100 holding full
-- health). Pure Lua 5.1: no game API, no units, no allocation after New. The caller feeds Restart on a unit change,
-- Band on every band callback, and asks Get(now) -> est, lo, hi, state; est nil means unknown.
-- Fit: seconds per percent `b` from an exponentially time-weighted least squares of time on percent over the recent
-- crossings (half-life 6 s, 30 s window); with too little spread for a fit, the stream's cumulative slope from an
-- anchor (the first band: 100% for a mob first seen full, the band's middle otherwise); a slope carries over a swap,
-- heal or stall for 8 s; a stall (no crossing for max(4 s, 5 x the mean gap)) holds the countdown; the published death
-- time moves only past a deadband, so the countdown is smooth. Defaults: the TTD lab's winner (tools/ttd_lab/README.md).
-- Rate changes (TTD lab run 2): a change detector (two-sided CUSUM of the crossings against the fit, on by default)
-- restarts the fit at the change; optional caller hints: Hint("rate", factor, startT, endT) for a known damage
-- multiplier over a time window (time is warped so the fit sees one base rate) and Hint("execute", factor, pct) for
-- a speed-up below a health percent (percent is warped; by default the factor is learned from the streams that cross
-- it). Slopes are kept in base-rate units, so a carried slope survives a hint's end.
local max, min, abs, sqrt = math.max, math.min, math.abs, math.sqrt

local E = {}
E.__index = E

local NEVER = 1e9 -- an open-ended hint's end

E.DEFAULTS = {
    halfLife = 6, -- seconds: weight 1/2 per halfLife of age
    window = 30, -- seconds: crossings older than this leave the fit
    ring = 32, -- crossings kept
    shrink = 0, -- K: pseudo-weight of the cumulative slope (the fit's weight is its summed weights)
    clampLo = 0.2, -- the blended slope stays within [clampLo, clampHi] x the cumulative slope
    clampHi = 5,
    minSpan = 2, -- percent the crossings must span before an unanchored stream (after a heal or stall) answers
    fitSpan = 3, -- percent and ...
    fitTime = 1.5, -- ... seconds the weighted window must span to fit at all (else the cumulative slope)
    anchorFull = true, -- a mob first seen full: a pseudo point (first band time, 100) starts the stream
    anchorBelow = true, -- a mob first seen below full: a pseudo point (first band time, the band's middle) starts it
    prior = true, -- carry the last slope over a restart, heal or stall
    priorTime = 8, -- seconds the carried slope is mixed in
    priorWeight = 1,
    seedWeight = 0, -- the weight of the stream's own anchor slope against a carried one (0: the carried slope rules)
    priorAge = 10, -- seconds: a carried slope whose last answer is older than this at the next first band is dropped
    priorEmpty = true, -- answer from the carried slope before the first crossing (mob below full)
    healReset = 3, -- a rise of this many percent over the lowest crossing restarts the fit
    stallGap = 4, -- a gap over max(stallGap, stallMult x mean gap) is a stall: the fit restarts at the next crossing
    stallMult = 5,
    holdStall = true, -- during a stall the death time moves later with the clock (the countdown holds)
    censor = 0, -- the slope is at least (time since the last crossing) / censor; 0 turns it off
    hystAbs = 1, -- republish the death time when it moves more than max(hystAbs, hystRel x remaining) ...
    hystRel = 0.12,
    hystLate = 3, -- ... or more than hystLateRel x remaining after hystLate seconds; hystAbs = 0 turns it off
    hystLateRel = 0.04,
    floor = 0.25, -- the estimate stays above floor x b while the mob lives
    deathPct = 0, -- the percent the stream ends at (a phase exit)
    spread = true, -- lo/hi from a fast and a slow half-life (two more fits per Get)
    fastHalfLife = 3,
    slowHalfLife = 12,
    -- The change detector: each crossing's lateness in percent (time taken / slope - percent crossed), standardised by
    -- its own running variance, feeds a two-sided CUSUM; past `detect` the fit restarts at the crossing where that
    -- side last sat at zero, and a hint the change contradicts is dropped. 0 turns it off.
    detect = 6,
    detectK = 0.25, -- allowance per crossing (standard units)
    detectMin = 4, -- crossings after a (re)start that only learn the variance
    detectClip = 3, -- one crossing moves a side by at most this many standard units
    detectAlpha = 0.1, -- the variance's running weight
    -- A declared execute (Hint "execute"); without one these do nothing.
    execAhead = true, -- the projection bends at the threshold before the band reaches it (false: from the crossing)
    execLearn = 0.5, -- weight of each stream's measured speed-up in the declared factor (0: the factor stays)
    learnSpan = 5, -- percent below the threshold a stream must fall before it measures
    learnLo = 0.5, -- a measured speed-up is clamped to [learnLo, learnHi]
    learnHi = 4,
}

function E.New(params)
    local self = setmetatable({}, E)
    for k, v in pairs(E.DEFAULTS) do
        self[k] = v
    end
    for k, v in pairs(params or {}) do
        assert(E.DEFAULTS[k] ~= nil, "unknown parameter " .. tostring(k))
        self[k] = v
    end
    self.rt, self.rp = {}, {}
    for i = 1, self.ring do
        self.rt[i], self.rp[i] = 0, 0
    end
    -- state fields are false, never nil, when empty: a nil field re-set after a collection can rehash the table
    self.bPrev, self.lastAt = false, false
    self.hf, self.hs, self.he = 1, 0, NEVER -- rate hint: factor over [hs, he)
    self.drops = 0 -- hints dropped because the data contradicted them (a diagnostic)
    self.xf, self.xp = 1, 0 -- execute declaration: factor below xp percent
    self:Restart()
    return self
end

local function clear(self)
    self.n, self.head = 0, 0
    self.t0, self.p0 = false, false
    self.gUp, self.gDn, self.dCnt, self.dVar = 0, 0, 0, 1
    self.upT, self.upP, self.dnT, self.dnP = 0, 0, 0, 0
end

--- A unit change: everything but the carried slope and the hints goes.
function E:Restart()
    clear(self)
    if self.lastB then
        self.bPrev = self.lastB
    end
    self.known, self.fresh, self.anchored, self.carryFrom, self.resumed = false, false, false, false, false
    self.tAnchor, self.pMin, self.tLast, self.pLast = false, false, false, false
    self.tPub, self.setAt, self.lastB = false, false, false
    if self.xCand and self.execLearn > 0 then -- the last stream measured its speed-up below the threshold
        self.xf = self.xf + self.execLearn * (self.xCand - self.xf)
    end
    self.xOn, self.xOff, self.xA, self.xT0, self.xP0, self.xCand = false, false, false, -NEVER, 0, false
end

--- A caller hint. "rate": damage on this stream runs `factor` times its base rate from startT to endT (nil: open
--- ended); factor nil or 1 clears it. A new rate hint replaces the last one. "execute": below `pct` percent the
--- damage runs `factor` times faster (a pack's declared execute range); pct nil clears it. With `execLearn` the factor
--- is only the start: each stream that falls `learnSpan` percent below the threshold moves it toward the speed-up it
--- measured (slope above / slope below). Hints survive Restart.
--- shortcut: one rate hint at a time (a second replaces the first, also for crossings it covered); upgrade to a short
--- list if overlapping multipliers ever matter.
function E:Hint(kind, factor, a, b)
    if kind == "rate" then
        if not factor or factor <= 0 or factor == 1 or not a or (b and b <= a) then
            self.hf = 1
        else
            self.hf, self.hs, self.he = factor, a, b or NEVER
        end
    elseif kind == "execute" then
        if not factor or factor <= 0 or not a or a <= 0 then
            self.xf, self.xp = 1, 0
        else
            self.xf, self.xp = factor, a
        end
    end
end

--- The execute factor in use, with the current stream's measurement folded in as Restart would (execLearn).
function E:ExecuteFactor()
    if self.xCand and self.execLearn > 0 then
        return self.xf + self.execLearn * (self.xCand - self.xf)
    end
    return self.xf
end

-- Warped time: the base-rate seconds a rate hint makes of real time t.
local function tau(self, t)
    local f = self.hf
    if f == 1 or t <= self.hs then
        return t
    end
    return t + (f - 1) * (min(t, self.he) - self.hs)
end

-- The real time of warped time T (tau's inverse).
local function untau(self, T)
    local f, hs = self.hf, self.hs
    if f == 1 or T <= hs then
        return T
    end
    local tauEnd = hs + f * (self.he - hs)
    if T <= tauEnd then
        return hs + (T - hs) / f
    end
    return self.he + (T - tauEnd)
end

-- Warped percent: base-rate work left above 0 at health p under a declared execute.
local function work(self, p)
    if self.xp <= 0 or self.xf == 1 or self.xOff or not (self.xOn or self.execAhead) then
        return p
    end
    return p - (1 - 1 / self.xf) * min(p, self.xp)
end

-- The slope a carried value can apply to: the latest answered one, else the one carried in.
local function carry(self, t)
    self.bPrev = self.lastB or self.bPrev
    self.carryFrom, self.resumed = t, true
    self.fresh, self.anchored = false, false
    clear(self)
end

local function at(self, i) -- the i-th kept crossing, 1 oldest
    return (self.head - self.n + i - 1) % self.ring + 1
end

-- Seconds since the last crossing beyond the stall threshold, max(stallGap, stallMult x mean gap); 0: no stall.
local function stalledFor(self, now)
    if not self.tLast or self.n < 2 then
        return 0
    end
    local mean = (self.tLast - self.rt[at(self, 1)]) / (self.n - 1)
    return max(0, now - self.tLast - max(self.stallGap, self.stallMult * mean))
end

-- The cumulative slope from the anchor (or the last cut) to the last crossing, or nil.
local function cumSlope(self)
    if not self.t0 or not self.tLast then
        return nil
    end
    local dw, dt = work(self, self.p0) - work(self, self.pLast), tau(self, self.tLast) - tau(self, self.t0)
    if dw > 0 and dt > 0 then
        return dt / dw
    end
end

-- The weighted fit of time on percent with half-life h: b (seconds per percent, > 0) and the weight sum, or nil.
local function fit(self, now, h)
    local sw, sp, st, spp, spt = 0, 0, 0, 0, 0
    local pHi, pLo, tHi, tLo = -1, 1000, -1e9, 1e9
    local wRef, tRef = work(self, self.pLast), tau(self, self.tLast)
    for i = 1, self.n do
        local j = at(self, i)
        local t = self.rt[j]
        local age = now - t
        if age <= self.window then
            local p = self.rp[j]
            local w = 0.5 ^ (age / h)
            local dp, dt = work(self, p) - wRef, tau(self, t) - tRef
            sw, sp, st = sw + w, sp + w * dp, st + w * dt
            spp, spt = spp + w * dp * dp, spt + w * dp * dt
            pHi, pLo, tHi, tLo = max(pHi, p), min(pLo, p), max(tHi, t), min(tLo, t)
        end
    end
    if sw <= 0 or pHi - pLo < self.fitSpan or tHi - tLo < self.fitTime then
        return nil, sw
    end
    local mp, mt = sp / sw, st / sw
    local var = spp / sw - mp * mp
    if var <= 0 then
        return nil, sw
    end
    local b = -(spt / sw - mp * mt) / var
    if b <= 0 then
        return nil, sw
    end
    return b, sw
end

-- A detected change: the fit restarts at (t0, p0), a crossing already kept. A hint goes when the change contradicts
-- it from its start: the change point lies within max(2 s, 2 mean gaps) of the hint's start (rate) or of the
-- threshold crossing (execute). A later change (an opener ending under a lust) leaves it.
local function cut(self, t, t0, p0, slower)
    local tol = self.n > 1 and 2 * (self.tLast - self.rt[at(self, 1)]) / (self.n - 1) or 0
    tol = max(2, tol)
    while self.n > 0 and self.rt[at(self, 1)] < t0 do
        self.n = self.n - 1
    end
    self.t0, self.p0, self.anchored, self.carryFrom = t0, p0, true, false
    local hf = self.hf
    if hf ~= 1 and t >= self.hs and t < self.he and (hf > 1) == slower and abs(t0 - self.hs) <= tol then
        self.hf, self.drops = 1, self.drops + 1
    end
    if slower and self.xOn and self.xf > 1 and abs(t0 - self.xT0) <= tol then
        self.xOff, self.drops = true, self.drops + 1
    end
    self.gUp, self.gDn, self.dCnt = 0, 0, 0
    self.upT, self.upP, self.dnT, self.dnP = t0, p0, t0, p0
end

-- The change detector on a crossing to hi at t, before it is kept.
local function detect(self, t, hi)
    if self.detect <= 0 or self.n < 1 then
        return
    end
    local b = fit(self, t, self.halfLife) or cumSlope(self)
    local dw = work(self, self.pLast) - work(self, hi)
    if not b or dw <= 0 then
        return
    end
    local e = (tau(self, t) - tau(self, self.tLast)) / b - dw -- percent late (+) or early (-)
    local c = self.dCnt + 1
    self.dCnt = c
    if c > self.detectMin then
        local z = e / sqrt(self.dVar * dw)
        z = max(-self.detectClip, min(self.detectClip, z))
        self.gUp = max(0, self.gUp - z - self.detectK)
        self.gDn = max(0, self.gDn + z - self.detectK)
    end
    self.dVar = max(0.01, self.dVar + max(self.detectAlpha, 1 / c) * (e * e / dw - self.dVar))
    if self.gUp > self.detect then
        cut(self, t, self.upT, self.upP, false)
    elseif self.gDn > self.detect then
        cut(self, t, self.dnT, self.dnP, true)
    end
    -- the change point of each side: the last crossing it sat at zero (the new rate began after it)
    if self.gUp <= 0 then
        self.upT, self.upP = t, hi
    end
    if self.gDn <= 0 then
        self.dnT, self.dnP = t, hi
    end
end

--- A band callback: health in [lo, hi) at `t` (hi == 100: the top cell, full health possible).
function E:Band(t, lo, hi)
    if not self.known then
        self.known, self.tAnchor, self.pMin = true, t, hi
        self.fresh = self.anchorFull and hi >= 100
        self.anchored = self.fresh or (self.anchorBelow and hi < 100)
        self.xOn = self.xp > 0 and hi <= self.xp
        if self.bPrev and self.lastAt and t - self.lastAt <= self.priorAge then
            self.carryFrom = t
        else -- a new pull, not a swap: the old slope says nothing
            self.bPrev = false
        end
        return
    end
    local pMin = self.pMin
    if hi < pMin then -- a crossing: health just fell below hi
        if stalledFor(self, t) > 0 then
            carry(self, t)
        end
        if self.n == 0 and not self.t0 then
            if self.fresh then
                self.t0, self.p0 = self.tAnchor, 100
            elseif self.anchored then
                self.t0, self.p0 = self.tAnchor, pMin - 0.5 -- the first band's middle
            else
                self.t0, self.p0 = t, hi
            end
        end
        if self.xp > 0 and hi <= self.xp then
            if not self.xOn then -- the threshold: keep the slope above it to measure the speed-up against
                local bA = self.n > 0 and (fit(self, t, self.halfLife) or cumSlope(self))
                self.xOn, self.xA, self.xT0, self.xP0 = true, bA or false, t, hi
            elseif self.xA and self.xP0 - hi >= self.learnSpan then
                local dt = tau(self, t) - tau(self, self.xT0)
                if dt > 0 then
                    self.xCand = min(self.learnHi, max(self.learnLo, self.xA * (self.xP0 - hi) / dt))
                end
            end
        end
        detect(self, t, hi)
        self.head = self.head % self.ring + 1
        self.rt[self.head], self.rp[self.head] = t, hi
        self.n = min(self.n + 1, self.ring)
        self.pMin, self.tLast, self.pLast = hi, t, hi
    elseif hi - pMin >= self.healReset then -- a heal: start over from here
        carry(self, t)
        self.pMin, self.tLast, self.pLast = hi, false, false
    end
end

-- The slope `b` at `now` for half-life h and the state it came from, or nil.
local function slope(self, now, h)
    local carried = self.prior and self.bPrev and self.carryFrom and now - self.carryFrom < self.priorTime
    local n = self.n
    if n == 0 then
        if carried and (self.priorEmpty or self.resumed) then -- a swap, or the same mob after a heal or stall
            return self.bPrev, "prior"
        end
        return nil
    end
    local bcum = cumSlope(self)
    local b, w, state
    if not self.anchored and self.rp[at(self, 1)] - self.pLast < self.minSpan then
        b, w, state = nil, 0, "prior"
    else
        local bfit
        bfit, w = fit(self, now, h)
        if bfit and bcum then
            b = (w * bfit + self.shrink * bcum) / (w + self.shrink)
            b = min(max(b, self.clampLo * bcum), self.clampHi * bcum)
            state = "fit"
        elseif bcum then
            b, w, state = bcum, self.seedWeight, "seed"
        else
            b, w, state = bfit, w, "fit"
        end
    end
    if carried and w < 2 then
        if b then
            local k = w + self.shrink
            b = (k * b + self.priorWeight * self.bPrev) / (k + self.priorWeight)
        else
            b = self.bPrev
        end
    elseif not b then
        return nil
    end
    return b, state
end

-- The death time for slope b (warped seconds per warped percent), censored by the quiet time since the last crossing.
local function death(self, now, b)
    local tLast, pLast = self.tLast, self.pLast
    if not tLast then -- no crossing yet (a carried answer): health just under the band's top, from now
        tLast, pLast = now, self.pMin - 0.5
    end
    if self.censor > 0 then
        b = max(b, (now - tLast) / self.censor)
    end
    local T = untau(self, tau(self, tLast) + (work(self, pLast) - work(self, self.deathPct)) * b)
    if self.holdStall then -- a stall stops the countdown
        T = T + stalledFor(self, now)
    end
    return T
end

--- est, lo, hi (seconds from now) and the state ("fit", "seed", "prior", "stalled", "unknown").
function E:Get(now)
    if not self.known then
        return nil, nil, nil, "unknown"
    end
    local b, state = slope(self, now, self.halfLife)
    if not b then
        return nil, nil, nil, "unknown"
    end
    self.lastB, self.lastAt = b, now
    local T = death(self, now, b)
    local rem = T - now
    local pub = self.tPub
    if
        not pub
        or self.hystAbs <= 0
        or abs(T - pub) > max(self.hystAbs, self.hystRel * rem)
        or (now - self.setAt >= self.hystLate and abs(T - pub) > self.hystLateRel * rem)
    then
        self.tPub, self.setAt, pub = T, now, T
    end
    local lowest = self.floor * b
    local est = max(pub - now, lowest)
    if stalledFor(self, now) > 0 then
        state = "stalled"
    end
    if not self.spread then
        return est, est, est, state
    end
    if state ~= "fit" and state ~= "stalled" then -- little data: a wide band
        return est, est * 0.5, est * 3, state
    end
    local bf = slope(self, now, self.fastHalfLife) or b
    local bs = slope(self, now, self.slowHalfLife) or b
    local ef = max(death(self, now, bf) - now, lowest)
    local es = max(death(self, now, bs) - now, lowest)
    return est, min(est, ef, es), max(est, ef, es), state
end

-- lifted body ends
if lib then
    lib.Estimator = E
    lib.loading = nil -- the last file of the TOC
end
return E
