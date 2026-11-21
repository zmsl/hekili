-- tools/ttd_lab/baselines.lua: the other estimators, written from their published descriptions (see the research
-- note, section 1-2), on the same band stream. Each sees samples (t, health %) built from the bands: a fall gives the
-- percent just crossed (hi), a rise the band's floor (lo), the first band its middle (100 when the top cell).
-- Every one answers an absolute death time T and reports max(0, T - now), or nil (unknown, which covers the
-- constant defaults some of them show instead).
local B = {}

local function class()
    local c = {}
    c.__index = c
    function c.new(params)
        local self = setmetatable({ p = params or {} }, c)
        self:restart(0)
        return self
    end
    function c:restart()
        self._lo = nil
        self:reset()
    end
    function c:band(t, lo, hi)
        local prev = self._lo
        self._lo = lo
        if prev == nil then
            self:sample(t, hi >= 100 and 100 or lo + 0.5, 0)
        elseif lo < prev then
            self:sample(t, hi, -1)
        elseif lo > prev then
            self:sample(t, lo, 1)
        end
    end
    function c:get(now)
        local T = self:death(now)
        if T then
            return math.max(0, T - now)
        end
    end
    return c
end

-- Root of the least-squares line of y on x from sums (x centred by the caller): the x where y = 0, or nil.
local function root(n, sx, sy, sxy, sxx)
    local den = n * sxx - sx * sx
    if n <= 0 or den <= 1e-12 then
        return nil
    end
    local slope = (n * sxy - sx * sy) / den
    if slope >= 0 then
        return nil
    end
    local a = (sy - slope * sx) / n
    return -a / slope
end

-- Initial Midpoints: the first sample and a centroid halved toward each new sample; the line through both.
B.Midpoints = class()
function B.Midpoints:reset()
    self.x0 = nil
end
function B.Midpoints:sample(t, y)
    if not self.x0 or y >= 100 then
        self.x0, self.y0, self.mx, self.my = t, y, t, y
    else
        self.mx, self.my = (self.mx + t) / 2, (self.my + y) / 2
    end
    self.tl, self.yl = t, y
end
function B.Midpoints:death()
    if self.x0 and self.mx > self.x0 and self.my < self.y0 then
        return self.tl + self.yl * (self.mx - self.x0) / (self.y0 - self.my)
    end
end

-- Least Squares over every sample since the first (or since full); Weighted: all sums halved before each sample.
local function lsClass(decay)
    local c = class()
    function c:reset()
        self.x0, self.n, self.sx, self.sy, self.sxy, self.sxx = nil, 0, 0, 0, 0, 0
    end
    function c:sample(t, y)
        if not self.x0 or y >= 100 then
            self:reset()
            self.x0 = t
        end
        local x = t - self.x0
        self.n, self.sx, self.sy = self.n * decay + 1, self.sx * decay + x, self.sy * decay + y
        self.sxy, self.sxx = self.sxy * decay + x * y, self.sxx * decay + x * x
    end
    function c:death()
        if self.x0 and self.n > 1.01 then
            local r = root(self.n, self.sx, self.sy, self.sxy, self.sxx)
            return r and self.x0 + r
        end
    end
    return c
end
B.LeastSquares = lsClass(1)
B.WeightedLS = lsClass(0.5)

-- HeroLib-style: percent-on-time least squares over the samples of the last 10.4 s (at most 100), more than 3 of them;
-- a rise above the newest sample drops the history.
B.HeroLib = class()
function B.HeroLib:reset()
    self.t, self.y = {}, {}
end
function B.HeroLib:sample(t, y)
    local n = #self.t
    if n > 0 and y > self.y[n] then
        self:reset()
    end
    table.insert(self.t, t)
    table.insert(self.y, y)
    if #self.t > 100 then
        table.remove(self.t, 1)
        table.remove(self.y, 1)
    end
end
function B.HeroLib:death(now)
    local win = self.p.window or 10.4
    while self.t[1] and self.t[1] < now - win do
        table.remove(self.t, 1)
        table.remove(self.y, 1)
    end
    local n = #self.t
    if n <= (self.p.min or 3) then
        return nil
    end
    local x0, sx, sy, sxy, sxx = self.t[1], 0, 0, 0, 0
    for i = 1, n do
        local x, y = self.t[i] - x0, self.y[i]
        sx, sy, sxy, sxx = sx + x, sy + y, sxy + x * y, sxx + x * x
    end
    local r = root(n, sx, sy, sxy, sxx)
    return r and x0 + r
end

-- Hekili-retail-style: the mean of the last 10 instantaneous rates (drop / time since the previous sample); a rise
-- updates no rate; 3 rates needed.
B.Hekili = class()
function B.Hekili:reset()
    self.rates, self.tl = {}, nil
end
function B.Hekili:sample(t, y)
    if self.tl and y < self.yl and t > self.tl then
        table.insert(self.rates, (self.yl - y) / (t - self.tl))
        if #self.rates > 10 then
            table.remove(self.rates, 1)
        end
    end
    self.tl, self.yl = t, y
end
function B.Hekili:death()
    local n = #self.rates
    if n < 3 then
        return nil
    end
    local s = 0
    for i = 1, n do
        s = s + self.rates[i]
    end
    return self.tl + self.yl / (s / n)
end

-- SimC-style cumulative average: drop since the first sample over the time since it; needs 1 s and a drop.
B.Cumulative = class()
function B.Cumulative:reset()
    self.t0 = nil
end
function B.Cumulative:sample(t, y)
    if not self.t0 then
        self.t0, self.y0 = t, y
    end
    self.tl, self.yl = t, y
end
function B.Cumulative:death()
    if self.t0 and self.tl - self.t0 >= 1 and self.y0 > self.yl then
        return self.tl + self.yl * (self.tl - self.t0) / (self.y0 - self.yl)
    end
end

-- The old plan (design 2.7): a ring of the last 8 falls; the rate from its oldest to its newest point; fewer than 3
-- points, a swap or any rise answers unknown (the ring clears).
B.Ring8 = class()
function B.Ring8:reset()
    self.t, self.y = {}, {}
end
function B.Ring8:sample(t, y, dir)
    if dir == 1 then
        self:reset()
    elseif dir == -1 then
        table.insert(self.t, t)
        table.insert(self.y, y)
        if #self.t > 8 then
            table.remove(self.t, 1)
            table.remove(self.y, 1)
        end
    end
end
function B.Ring8:death()
    local n = #self.t
    if n < 3 or self.t[n] <= self.t[1] then
        return nil
    end
    return self.t[n] + self.y[n] * (self.t[n] - self.t[1]) / (self.y[1] - self.y[n])
end

-- The deadband the recommended estimator publishes through, around any of the above (an ablation).
B.Hyst = {}
B.Hyst.__index = B.Hyst
function B.Hyst.new(inner)
    return setmetatable({ inner = inner }, B.Hyst)
end
function B.Hyst:restart(t)
    self.pub = nil
    self.inner:restart(t)
end
function B.Hyst:band(t, lo, hi)
    self.inner:band(t, lo, hi)
end
function B.Hyst:get(now, dps)
    local est = self.inner:get(now, dps)
    if not est then
        return nil
    end
    local T = now + est
    local d = math.abs(T - (self.pub or -1e9))
    if not self.pub or d > math.max(1, 0.12 * est) or (now - self.setAt >= 3 and d > 0.04 * est) then
        self.pub, self.setAt = T, now
    end
    return math.max(0, self.pub - now)
end

return B
