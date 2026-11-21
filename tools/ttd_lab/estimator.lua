-- Time to die for one health stream seen as 1% bands (the band lo..hi, hi = lo + 1, the top cell 99-100 holding full
-- health). Pure Lua 5.1: no game API, no units, no allocation after New. The caller feeds Restart on a unit change,
-- Band on every band callback, and asks Get(now [, ownDps]) -> est, lo, hi, state; est nil means unknown.
-- Fit: seconds per percent `b` from an exponentially time-weighted least squares of time on percent over the recent
-- crossings (half-life 6 s, 30 s window); with too little spread for a fit, the stream's cumulative slope from an
-- anchor (the first band: 100% for a mob first seen full, the band's middle otherwise); a slope carries over a swap,
-- heal or stall for 8 s; a stall (no crossing for max(4 s, 5 x the mean gap)) holds the countdown; the published death
-- time moves only past a deadband, so the countdown is smooth. Defaults: the TTD lab's winner (tools/ttd_lab/README.md).
local max, min, abs = math.max, math.min, math.abs

local E = {}
E.__index = E

E.DEFAULTS = {
    halfLife = 6, -- seconds: weight 1/2 per halfLife of age
    window = 30, -- seconds: crossings older than this leave the fit
    ring = 32, -- crossings kept
    shrink = 0, -- K: pseudo-weight of the cumulative slope (the fit's weight is its summed weights)
    clampLo = 0.2, -- the blended slope stays within [clampLo, clampHi] x the cumulative slope
    clampHi = 5,
    minSpan = 2, -- percent the crossings must span before the fit answers on a mob first seen below full
    fitSpan = 3, -- percent and ...
    fitTime = 1.5, -- ... seconds the weighted window must span to fit at all (else the cumulative slope)
    anchorFull = true, -- a mob first seen full: a pseudo point (first band time, 100) starts the stream
    anchorBelow = true, -- a mob first seen below full: a pseudo point (first band time, the band's middle) starts it
    prior = true, -- carry the last slope over a restart, heal or stall
    priorTime = 8, -- seconds the carried slope is mixed in
    priorWeight = 1,
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
    self.bPrev = nil
    self:Restart()
    return self
end

local function clear(self)
    self.n, self.head = 0, 0
    self.t0, self.p0 = nil, nil
end

--- A unit change: everything but the carried slope goes.
function E:Restart()
    clear(self)
    if self.lastB then
        self.bPrev = self.lastB
    end
    self.known, self.fresh, self.anchored, self.carryFrom, self.resumed = false, false, false, nil, false
    self.tAnchor, self.pMin, self.tLast, self.pLast = nil, nil, nil, nil
    self.tPub, self.setAt, self.lastB = nil, nil, nil
end

-- The slope to carry into a reset: the latest answered one, else the one carried in.
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

--- A band callback: health in [lo, hi) at `t` (hi == 100: the top cell, full health possible).
function E:Band(t, lo, hi)
    if not self.known then
        self.known, self.tAnchor, self.pMin = true, t, hi
        self.fresh = self.anchorFull and hi >= 100
        self.anchored = self.fresh or (self.anchorBelow and hi < 100)
        if self.bPrev then
            self.carryFrom = t
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
        self.head = self.head % self.ring + 1
        self.rt[self.head], self.rp[self.head] = t, hi
        self.n = min(self.n + 1, self.ring)
        self.pMin, self.tLast, self.pLast = hi, t, hi
    elseif hi - pMin >= self.healReset then -- a heal: start over from here
        carry(self, t)
        self.pMin, self.tLast, self.pLast = hi, nil, nil
    end
end

-- The weighted fit of time on percent with half-life h: b (seconds per percent, > 0) and the weight sum, or nil.
local function fit(self, now, h)
    local sw, sp, st, spp, spt = 0, 0, 0, 0, 0
    local pHi, pLo, tHi, tLo = -1, 1000, -1e9, 1e9
    local pRef, tRef = self.pLast, self.tLast
    for i = 1, self.n do
        local j = at(self, i)
        local t = self.rt[j]
        local age = now - t
        if age <= self.window then
            local p = self.rp[j]
            local w = 0.5 ^ (age / h)
            local dp, dt = p - pRef, t - tRef
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
    local bcum
    if self.t0 and self.p0 > self.pLast and self.tLast > self.t0 then
        bcum = (self.tLast - self.t0) / (self.p0 - self.pLast)
    end
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
            b, w, state = bcum, 0, "seed"
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

-- The death time for slope b, censored by the quiet time since the last crossing.
local function death(self, now, b)
    local tLast, pLast = self.tLast, self.pLast
    if not tLast then -- no crossing yet (a carried answer): health just under the band's top, from now
        tLast, pLast = now, self.pMin - 0.5
    end
    if self.censor > 0 then
        b = max(b, (now - tLast) / self.censor)
    end
    local T = tLast + (pLast - self.deathPct) * b
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
    self.lastB = b
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

return E
