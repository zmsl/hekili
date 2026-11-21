-- Bars.lua: the bar pool, the curves, priming, the firing and the decode (named edges and position).
--
-- The mechanism (measured, BandProbe run 2026-11-20): a read with a Step curve returns a hidden 1 (below the edge) or
-- 2 (at or above it); pushed into a StatusBar ranged 0-2 it fills half or all of it; a frame anchored to the fill
-- texture gets OnSizeChanged when the fill changes, after the frame's scripts. That firing is plain. Its arguments
-- are secret and never read: each bar keeps one plain boolean the firing flips (a toggle), so a bar needs a known
-- start: priming holds it at the plain low level for HOLD frames, clears the boolean, then feeds the live value (it
-- fires if and only if the value is at or above the edge) and counts its firings for SETTLE more frames before the
-- handle goes live: a secret push's firing can trail it by a frame (LHVProbe 2026-11-20), and a decode before it
-- arrived reported the lowest band, then the real one with dir 1.
--
-- A source runs one of three modes, chosen by its handles: edges only (one bar per edge); position (a listener asked
-- for a step: the Gray code of the 1% cell n = 0..100 on 7 bars plus a parity bar, design 3.3, proven by BandProbe2;
-- an edge on the 1% grid then needs no bar); point precision (Kinds/Percent.lua's ring, stage 3 task D; at a point
-- step above 1 a step listener keeps a position set beside it, cut on whole points, owner L1624). A position
-- decode checks the code, the parity and every edge bar against the cell: one bad frame holds the last band (a split:
-- one change's firings landed in two frames), two in a row are a desync and the source primes again (design 3.3).
-- The encoding stays internal: a handle reads its band through decode.
local lib = LibStub and LibStub("LibHiddenValues-1.0", true)
if not (lib and lib.loading) then
    return
end

local HOLD = 4 -- frames at the low level before the live value (the run saw every plain push fire in its own frame)
-- frames the live push's firing may trail it: the self-test's limit for plain pushes (3), plus the frame a secret one
-- was seen to add (BandProbe v1 counted 4 frames after the push: "IN window 4")
local SETTLE = 4
local LOW = 1 -- the curve's "below" output; "at or above" is 2
local EPS = 0.0005 -- a guard point this far below each step (curve x scale 0-1), whichever way the client snaps
local CAP = 256 -- bars are never destroyed (frames cannot be): a hard ceiling on the pool
local NGRAY = 7 -- Gray bits of the 1% cell (101 values)
lib.HOLD, lib.SETTLE, lib.LOW, lib.POOL, lib.CAP = HOLD, SETTLE, LOW, 32, CAP
-- Points per Step curve the client accepts (BandProbe2 0.3.0: 256 accepted, 512 refused); a guarded step costs 2.
lib.MAXPTS = 256
-- Point thresholds that need a bar: at most per source and in total (owner L1613; tunable after a perf run).
lib.POINTS_PER_SOURCE, lib.POINTS_TOTAL = 8, 64
local MINSP = 0.00001 -- the smallest step spacing proven on the 0-1 scale (BandProbe2 0.3.0 D2)

-- Point precision (BandProbe2 0.3.0's mana arm, C50): the value in quanta q (g points each) is cell c = q div N on a
-- Gray code (cell bits + a parity bar) and ring position q mod N on N fine bars, where boundary q toggles bars q mod N
-- and (q + N/2) mod N. Any two ring states differ in >= 2 bars, so one lost or extra firing is never read as another
-- value: it decodes as no state at all.
local N, HALF = 50, 25
local RS, RK = {}, {} -- ring state per position (bar j: RS[p][j]), position per state key
do
    local s = {}
    for j = 0, N - 1 do
        s[j] = 0
    end
    for p = 0, N - 1 do
        if p > 0 then
            local a, c = p % N, (p + HALF) % N
            s[a], s[c] = 1 - s[a], 1 - s[c]
        end
        local row, key = {}, 0
        for j = 0, N - 1 do
            row[j] = s[j]
            key = key + s[j] * 2 ^ j
        end
        RS[p], RK[key] = row, p
    end
end
lib.RING_N, lib.RK = N, RK
-- The largest ring: 127 steps of N/2 quanta (3175) is 64 cells, 6 cell bits, plus the parity bar.
lib.RING_MAXBARS = N + 6 + 1
lib.rings = lib.rings or {} -- per plain max: { g, mq, ncell, NB, curves } or false (refused)

-- Gray code tables over 0..127, built without a bit library.
local POW2 = { [0] = 1 }
for k = 1, 60 do
    POW2[k] = POW2[k - 1] * 2
end
local function gray(n)
    local g, a, b, k = 0, n, math.floor(n / 2), 0
    while a > 0 or b > 0 do
        if a % 2 ~= b % 2 then
            g = g + POW2[k]
        end
        a, b, k = math.floor(a / 2), math.floor(b / 2), k + 1
    end
    return g
end
local GRAY, GINV = {}, {}
for n = 0, 127 do
    GRAY[n] = gray(n)
    GINV[GRAY[n]] = n
end
lib.POW2, lib.GRAY, lib.GINV = POW2, GRAY, GINV

-- Bars made (frames are never destroyed), the cap, point bars in use, and the two point caps (total, per source).
function lib:GetPool()
    local used = 0
    for k = 1, #lib.sources do
        for _ in pairs(lib.sources[k].pbar) do
            used = used + 1
        end
    end
    return #lib.barFrame, CAP, used, lib.POINTS_TOTAL, lib.POINTS_PER_SOURCE
end

lib.barFrame = lib.barFrame or {}
lib.barClip = lib.barClip or {}
lib.barSrc = lib.barSrc or {} -- the source a bar serves (lib.ST: the self-test), nil when free
lib.barState = lib.barState or {} -- plain: the value is at or above the bar's step
lib.barCurve = lib.barCurve or {} -- the curve a bar is fed through
-- frames of priming left: > SETTLE + 1 hold low, SETTLE + 1 feed live next, 1..SETTLE settling (fed live, firings
-- counted), 0 live
lib.barPrime = lib.barPrime or {}
lib.free = lib.free or {}
lib.curves = lib.curves or {} -- one per edge, shared by every source
lib.ptCurves = lib.ptCurves or {} -- [max][point]
lib.ST = lib.ST or {}
lib.desyncs = lib.desyncs or 0
lib.splits = lib.splits or 0
lib.nFire = lib.nFire or 0
lib.frameNo = lib.frameNo or 0

-- One dispatcher for every bar's anchored child: the firing's arguments are secret and are not passed on.
lib.onSize = lib.onSize
    or function(self)
        local ok, err = pcall(lib.fire, self.i)
        if not ok then
            lib.fail(err)
        end
    end

-- The Step curve of an edge in percent: 1 below, 2 at or above (the guard point holds 1 up to EPS below the step).
function lib.curveFor(e)
    local c = lib.curves[e]
    if not c then
        c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, LOW)
        c:AddPoint(e / 100 - EPS, LOW)
        c:AddPoint(e / 100, 2)
        lib.curves[e] = c
    end
    return c
end

-- An older minor's edge bars (minor 2 kept no per-bar curve: it fed lib.curves[e]) get their curve; aura bars have
-- none.
for k = 1, #lib.sources do
    local s = lib.sources[k]
    if s.kind ~= "aura" then
        for e, i in pairs(s.bar) do
            lib.barCurve[i] = lib.barCurve[i] or lib.curveFor(e)
        end
    end
end

-- The Step curve of a point threshold p at the plain max M: 1 below p, 2 at or above. The step sits half a point below
-- p (a last-bit error in the client's percent cannot move a whole point across it), its guard a quarter point lower
-- (BandProbe2 0.3.0's construction). One per (M, p), shared.
function lib.pointCurve(p, M)
    local byMax = lib.ptCurves[M]
    if not byMax then
        lib.trim(lib.ptCurves)
        byMax = {}
        lib.ptCurves[M] = byMax
    end
    local c = byMax[p]
    if not c then
        local x, eps = (p - 0.5) / M, math.max(0.25 / M, MINSP)
        c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, LOW)
        if x - eps > 0 then
            c:AddPoint(x - eps, LOW)
        end
        c:AddPoint(x, 2)
        byMax[p] = c
    end
    return c
end

-- A two-level Step curve over the integers 0..top: LOW + bit(n), the step into n at xOf(n), a guard point eps below
-- it. Only n = first, first + stride, ... are read (default every n): the caller vouches that bit is constant between
-- them. Raises when the client refuses a point (callers use pcall). A cold path: build time only.
function lib.levelCurve(bit, top, xOf, eps, first, stride)
    local c = C_CurveUtil.CreateCurve()
    c:SetType(Enum.LuaCurveType.Step)
    local prev = bit(0)
    c:AddPoint(0, LOW + prev)
    for n = first or 1, top, stride or 1 do
        local b = bit(n)
        if b ~= prev then
            local x = xOf(n)
            c:AddPoint(x - eps, LOW + prev)
            c:AddPoint(x, LOW + b)
            prev = b
        end
    end
    return c
end

-- A position set's curves (Gray bits 0-6, then the parity bar), the step into cell n at xOf(n); false when the client
-- refused one.
local function grayList(xOf, eps)
    local ok, list = pcall(function()
        local t = {}
        for k = 0, NGRAY - 1 do
            t[k + 1] = lib.levelCurve(function(n)
                return math.floor(GRAY[n] / POW2[k]) % 2
            end, 100, xOf, eps)
        end
        t[NGRAY + 1] = lib.levelCurve(function(n)
            return n % 2
        end, 100, xOf, eps)
        return t
    end)
    return ok and list or false
end

-- The position set's curves on the percent scale, built once.
function lib.grayCurves()
    if lib.gcurve == nil then
        lib.gcurve = grayList(function(n)
            return n / 100
        end, EPS)
    end
    return lib.gcurve
end

-- Creates one pooled bar (a 20 x 2 StatusBar under the alpha-0 root, its clipped child anchored to the fill).
function lib.newBar()
    local i = #lib.barFrame + 1
    if i > CAP then
        return nil
    end
    local bar = CreateFrame("StatusBar", nil, lib.root)
    bar:SetSize(20, 2)
    bar:SetPoint("TOPLEFT", lib.root, "TOPLEFT", 0, 0)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 2)
    bar:SetValue(LOW)
    bar:SetClipsChildren(true)
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetPoint("TOPLEFT", bar, "TOPLEFT")
    clip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
    clip.i = i
    clip:SetScript("OnSizeChanged", lib.onSize)
    lib.barFrame[i], lib.barClip[i], lib.barState[i], lib.barPrime[i] = bar, clip, false, 0
    lib.free[#lib.free + 1] = i
    return i
end

-- A free bar for owner fed through curve, priming; nil at the cap (growth in combat is tried under pcall: it may be
-- refused).
function lib.allocBar(owner, curve)
    local free = lib.free
    if #free == 0 then
        local ok = pcall(lib.newBar)
        if not ok or #free == 0 then
            return nil
        end
    end
    local i = free[#free]
    free[#free] = nil
    lib.barSrc[i], lib.barCurve[i], lib.barState[i], lib.barPrime[i] = owner, curve, false, HOLD + SETTLE + 1
    return i
end

function lib.freeBar(i)
    lib.barSrc[i], lib.barCurve[i], lib.barPrime[i] = nil, nil, 0
    lib.free[#lib.free + 1] = i
end

-- Every bar of the source primes; its handles go unknown until they are live again.
function lib.reprime(s)
    local prime, P = lib.barPrime, HOLD + SETTLE + 1
    for k = 1, #s.core do
        prime[s.core[k]] = P
    end
    for _, i in pairs(s.bar) do
        prime[i] = P
    end
    for _, i in pairs(s.pbar) do
        prime[i] = P
    end
    s.bad, s.ok, s.qv, s.pend, s.run = 0, false, nil, nil, 0 -- no s.qv: the first decode after the prime is held too
    s.dirty = true
    lib.wake()
end

-- Whether a percent edge needs a bar of its own in a mode at the max M with the ring's point step g (position covers
-- the 1% grid; the ring covers every cut at step 1 and a cut on its quantum grid above it: a cut inside the value's
-- quantum keeps its bar, review I2; a cut that is not a whole multiple of the step is kept too, the safe side).
local function needEdge(mode, e, M, g)
    if mode == "ring" then
        return g ~= nil and g > 1 and (e * M) % (100 * g) ~= 0
    end
    return mode == nil or (mode == "gray" and e % 1 ~= 0)
end

-- Whether a point threshold needs a bar of its own in a mode at the max M (position covers p when p / M is on the 1%
-- grid: p * 100 a multiple of M, plain integers; the ring covers p at step 1 and on its quantum grid, as for edges).
local function needPoint(mode, M, p, g)
    if mode == "ring" then
        return g ~= nil and g > 1 and p % g ~= 0
    end
    return mode == nil or (mode == "gray" and not (M and (p * 100) % M == 0))
end

-- Every bar the handle rests on is there (false: the cap was reached or the client refused the curves its mode needs,
-- the handle is suspended).
local function served(s, h)
    local mode, M = s.mode, s.max
    if mode and not s.core[1] then
        return false
    end
    if (h.prec and mode ~= ((M and M > 100) and "ring" or "gray")) or (h.step and not mode) then
        return false -- lib.sync fell back to a mode without its curves
    end
    local g = s.ring and s.ring.g
    for k = 1, #h.edges do
        local e = h.edges[k]
        if not s.bar[e] and needEdge(mode, e, M, g) then
            return false
        end
    end
    local pts = h.points
    for k = 1, #pts do
        local p = pts[k]
        if not s.pbar[p] and needPoint(mode, M, p, g) then
            return false
        end
    end
    return true
end
lib.served = served

-- A bar is still priming for the handle.
function lib.priming(s, h)
    local prime = lib.barPrime
    if s.mode and prime[s.core[1]] > 0 then
        return true
    end
    for k = 1, #h.edges do
        local i = s.bar[h.edges[k]]
        if i and prime[i] > 0 then
            return true
        end
    end
    local pts = h.points
    for k = 1, #pts do
        local i = s.pbar[pts[k]]
        if i and prime[i] > 0 then
            return true
        end
    end
    return false
end

-- The mode a set of handles asks for: "gray" while any asks for a step, else nil (edges only).
-- The mode a set of handles asks for at the max M: "ring" while any asks for point precision and the max is over 100,
-- "gray" while any asks for a step (or point precision at a max of 100 or less: the 1% cell is one point then), else
-- nil (edges only).
function lib.modeFor(step, prec, M)
    if prec and M and M > 100 then
        return "ring"
    end
    return (step or prec) and "gray" or nil
end

-- The source's mode, and whether any handle asks for a step.
function lib.modeOf(s)
    local step, prec = false, false
    for j = 1, #s.handles do
        local h = s.handles[j]
        step, prec = step or h.step ~= nil, prec or h.prec == true
    end
    return lib.modeFor(step, prec, s.max), step
end

-- Keeps a per-max cache under 4 entries before one is added: drops the maxes no source cuts with now (a max that comes
-- back, a buff toggled, rebuilds only once it fell out).
local function trim(cache)
    local n = 0
    for _ in pairs(cache) do
        n = n + 1
    end
    if n < 4 then
        return
    end
    for M in pairs(cache) do
        local used = false
        for k = 1, #lib.sources do
            used = used or lib.sources[k].max == M
        end
        if not used then
            cache[M] = nil
        end
    end
end
lib.trim = trim

-- The ring for the max M: the point step g grows until every curve fits lib.MAXPTS points (a fine bar steps every N/2
-- quanta; a guarded step costs 2 points). false when the client refused a curve. Each curve reads only the quanta
-- where its bar can change (fine bar j: q = j mod N/2; cell bits and parity: multiples of N), about 25 times less
-- work than every quantum; full (a test's reference, not cached) reads every quantum.
function lib.ringFor(M, full)
    if not full and lib.rings[M] ~= nil then
        return lib.rings[M]
    end
    local g, mq, ncell
    g = 1
    while true do
        mq = math.floor(M / g)
        ncell = math.floor(mq / N) + 1
        local steps = math.max(math.ceil(mq / HALF), ncell - 1)
        if 1 + 2 * steps <= lib.MAXPTS then
            break
        end
        g = g + 1
    end
    local NB = 1
    while POW2[NB] < ncell do
        NB = NB + 1
    end
    local ok, curves = pcall(function()
        local t, eps = {}, math.max(0.25 / M, MINSP)
        local function xOf(q) -- half a point below the quantum's first point, as for a point bar
            return (q * g - 0.5) / M
        end
        local cellFirst, cellStride = full and 1 or N, full and 1 or N
        for j = 0, N - 1 do
            local first = full and 1 or (j % HALF == 0 and HALF or j % HALF)
            t[j + 1] = lib.levelCurve(function(q)
                return RS[q % N][j]
            end, mq, xOf, eps, first, full and 1 or HALF)
        end
        for k = 0, NB - 1 do
            t[N + k + 1] = lib.levelCurve(function(q)
                return math.floor(GRAY[math.floor(q / N)] / POW2[k]) % 2
            end, mq, xOf, eps, cellFirst, cellStride)
        end
        t[N + NB + 1] = lib.levelCurve(function(q)
            return math.floor(q / N) % 2
        end, mq, xOf, eps, cellFirst, cellStride)
        return t
    end)
    local r = ok and { g = g, mq = mq, ncell = ncell, NB = NB, curves = curves } or false
    if not full then
        trim(lib.rings)
        lib.rings[M] = r
    end
    return r
end

-- The first whole point of the 1% cell n at the max M (M + 1 past the top cell).
local function cellPoint(n, M)
    return n > 100 and M + 1 or math.floor((n * M + 99) / 100)
end

-- The position set beside a ring at the max M (owner L1624: a step watch reads one 1% cell where a quantum spans two):
-- the step into cell n half a point below its first whole point, its guard a quarter point lower, as the ring's and
-- the point bars' steps, so a whole-point value reads its own cell under any snapping. Per max, like the rings; false
-- when the client refused a curve.
lib.pgray = lib.pgray or {}
function lib.grayFor(M)
    local c = lib.pgray[M]
    if c == nil then
        c = grayList(function(n)
            return (cellPoint(n, M) - 0.5) / M
        end, math.max(0.25 / M, MINSP))
        trim(lib.pgray)
        lib.pgray[M] = c
    end
    return c
end

-- The player's plain max of the source's power type: a secret one (or a say-so that it is secret) keeps the last
-- plain value; 0 or none is nil (never a divisor). The check is (unit, powerType?) -> bool on Forever (API reference);
-- a raise from it counts as "secret".
function lib.maxOf(unit, power, last)
    if power == nil then
        return nil
    end
    local should = C_Secrets and C_Secrets.ShouldUnitPowerMaxBeSecret
    if should then
        local ok, sec = pcall(should, unit, power)
        if not ok or issecretvalue(sec) or sec then
            return last
        end
    end
    local m = UnitPowerMax and UnitPowerMax(unit, power)
    if issecretvalue(m) or type(m) ~= "number" or not (m > 0) then
        return last
    end
    return m
end

-- Bars a set of handles needs on a source, how many of them are point bars, and its distinct points (what the caps
-- count: as edges mode would place them, so a mode that answers some points without bars cannot later lift the source
-- over the caps when it ends). While precision is asked every edge and point counts toward the pool (the step can grow
-- with the max after admission, and a threshold then needs its bar). A cold path: admission. add joins the set; swapH
-- counts with swapList as its points.
function lib.need(s, add, swapH, swapList)
    local M = s.kind == "power" and lib.maxOf(s.unit, s.power, s.max) or nil
    local step, prec, edges, points = false, false, {}, {}
    local function take(h)
        step, prec = step or h.step ~= nil, prec or h.prec == true
        for k = 1, #h.edges do
            edges[h.edges[k]] = true
        end
        local pl = h == swapH and swapList or h.points
        for k = 1, #pl do
            points[pl[k]] = true
        end
    end
    for j = 1, #s.handles do
        take(s.handles[j])
    end
    if add then
        take(add)
    end
    local mode = lib.modeFor(step, prec, M)
    local bars, pb, all, g = mode == "gray" and NGRAY + 1 or 0, 0, 0, nil
    if mode == "ring" then
        local r = lib.ringFor(M)
        bars, g = r and #r.curves or 0, r and r.g
        if step then -- the position set beside the ring: counted at step 1 too (the step can grow with the max)
            bars = bars + NGRAY + 1
        end
    elseif prec and not M then -- no plain max yet (before login): the largest ring, and the position set beside it
        bars = lib.RING_MAXBARS + (step and NGRAY + 1 or 0)
    end
    for e in pairs(edges) do
        if prec or needEdge(mode, e, M, g) then
            bars = bars + 1
        end
    end
    for p in pairs(points) do
        all = all + 1
        if prec or needPoint(mode, M, p, g) then
            pb = pb + 1
        end
    end
    return bars + pb, pb, all
end

-- nil when the handle (with newPoints, when given, as its points) fits the caps, else the error code: EDGE_LIMIT over
-- the point caps, POOL_LIMIT over the pool. Nothing is granted here.
function lib.admit(h, newPoints)
    local s = lib.srcByKey[lib.keyOf(h)]
    local cur = s or { kind = h.kind, unit = h.unit, power = h.power, handles = {} }
    local bars, pb, _
    if newPoints then
        bars, _, pb = lib.need(cur, nil, h, newPoints)
    else
        bars, _, pb = lib.need(cur, h)
    end
    if pb > lib.POINTS_PER_SOURCE then
        return lib.ERR.EDGE_LIMIT
    end
    for k = 1, #lib.sources do
        local o = lib.sources[k]
        if o ~= s then
            local b, _, p = lib.need(o)
            bars, pb = bars + b, pb + p
        end
    end
    if pb > lib.POINTS_TOTAL then
        return lib.ERR.EDGE_LIMIT
    end
    if bars > CAP then
        return lib.ERR.POOL_LIMIT
    end
end

local function freeCore(s)
    for k = #s.core, 1, -1 do
        lib.freeBar(s.core[k])
        s.core[k] = nil
    end
end

-- The core set of the mode (all or nothing): false when a bar or a curve could not be had. A ring's position set
-- (s.gray) follows its bars in s.core.
local function allocCore(s)
    local curves, beside
    if s.mode == "ring" then
        curves, beside = s.ring and s.ring.curves, s.gray
    else
        curves = lib.grayCurves()
    end
    if not curves then
        return false
    end
    local n = #curves
    for k = 1, n + (beside and #beside or 0) do
        local i = lib.allocBar(s, curves[k] or beside[k - n])
        if not i then
            freeCore(s)
            return false
        end
        s.core[k] = i
    end
    return true
end

-- Brings a source in line with the capability, its references, its unit and its handles: picks the mode, allocates
-- the bars it needs when the kind is ready (only a new bar primes), frees the rest, and feeds it while any handle is
-- neither paused nor suspended and its unit is there.
function lib.sync(s)
    local ready = lib.realised and lib.capOf(s.kind) == "ready"
    if ready and s.kind == "power" then
        s.max = lib.maxOf(s.unit, s.power, s.max)
    end
    local M = s.max
    if s.pM ~= M then -- the cuts move: every point bar is placed again (and primes)
        for p, i in pairs(s.pbar) do
            lib.freeBar(i)
            s.pbar[p] = nil
        end
        s.pM = M
    end
    local mode, step
    if ready then
        mode, step = lib.modeOf(s)
    end
    local ring = mode == "ring" and lib.ringFor(M) or nil
    if mode == "ring" and not ring then -- the client refused a ring curve at this max: no point precision here; the
        mode = step and "gray" or nil -- other watches keep their bars, a precision handle is suspended (served)
    end
    if mode == "gray" and not lib.grayCurves() then -- refused too: edges only, a step handle is suspended
        mode = nil
    end
    local g = ring and ring.g
    -- a step beside a ring of step above 1 keeps the position set (owner L1624); at step 1 the ring gives one cell
    local gray = ring and g > 1 and step and lib.grayFor(M) or nil
    if mode ~= s.mode or ring ~= s.ring or gray ~= s.gray then -- a new mode, the ring of a new max, the set beside
        freeCore(s) -- the whole core primes again: shortcut, a step joining or leaving re-primes the ring too
        s.mode, s.ring, s.gray, s.bad, s.ok, s.qv, s.pend, s.run = mode, ring, gray, 0, false, nil, nil, 0
    end
    local want = false
    if ready then
        s.gone = not lib.present(s.unit) or (s.kind == "health" and lib.dead(s.unit))
        if mode and not s.core[1] then
            allocCore(s)
        end
        for e, n in pairs(s.ref) do
            if n > 0 and not s.bar[e] and needEdge(mode, e, M, g) then
                s.bar[e] = lib.allocBar(s, lib.curveFor(e))
            end
        end
        if M then
            for p, n in pairs(s.pref) do
                if n > 0 and not s.pbar[p] and needPoint(mode, M, p, g) then
                    s.pbar[p] = lib.allocBar(s, lib.pointCurve(p, M))
                end
            end
        end
        if not s.gone then
            for j = 1, #s.handles do
                local h = s.handles[j]
                if not h.paused and served(s, h) then
                    want = true
                    break
                end
            end
        end
    end
    for e, i in pairs(s.bar) do
        if not ready or s.ref[e] == 0 or not needEdge(mode, e, M, g) then
            lib.freeBar(i)
            s.bar[e] = nil
        end
    end
    for p, i in pairs(s.pbar) do
        if not ready or s.pref[p] == 0 or not needPoint(mode, M, p, g) then
            lib.freeBar(i)
            s.pbar[p] = nil
        end
    end
    if want and not s.active then
        lib.reprime(s)
    end
    s.active = want
    s.dirty = true
    lib.wake()
end

-- A bar's anchored child fired: its fill changed. Ignored while the bar holds low; counted while it settles (a
-- settling handle is not called: it is still priming). Once live, a handle on this bar alone (edges mode) is called
-- now (the frame of the firing); every other handle is decoded at the start of the next frame.
function lib.fire(i)
    local s = lib.barSrc[i]
    if s == nil then
        return
    end
    if s == lib.ST then
        return lib.stFire(i)
    end
    if lib.barPrime[i] > SETTLE then
        return
    end
    lib.barState[i] = not lib.barState[i]
    lib.nFire = lib.nFire + 1
    s.dirty, s.seen, s.seenFrame, s.firedAt = true, GetTime(), lib.frameNo, lib.frameNo
    if s.mode then
        return
    end
    local hs = s.handles
    for j = #hs, 1, -1 do
        local h = hs[j]
        if h and h.single and (s.bar[h.edges[1]] == i or s.pbar[h.points[1]] == i) then
            lib.decode(h)
        end
    end
end

-- The 1% cell of a position set at core[off + 1 .. off + 8]; nil and an error word when its code or parity is off.
local function grayCell(st, core, off)
    local code = 0
    for k = 1, NGRAY do
        if st[core[off + k]] then
            code = code + POW2[k - 1]
        end
    end
    local n = GINV[code]
    if n == nil or n > 100 then
        return nil, "code"
    end
    if st[core[off + NGRAY + 1]] ~= (n % 2 == 1) then
        return nil, "parity"
    end
    return n
end

-- The position set's cell from its bars (nil, n); an error word when the code, the parity or an edge bar disagrees.
local function grayDecode(s)
    local st = lib.barState
    local n, bad = grayCell(st, s.core, 0)
    if not n then
        return bad
    end
    local prime = lib.barPrime -- a bar still priming says nothing yet (its own handles read "priming")
    for e, i in pairs(s.bar) do
        if prime[i] == 0 then
            if st[i] then
                if n + 1 <= e then
                    return "edge"
                end
            elseif n >= e then
                return "edge"
            end
        end
    end
    local M = s.max
    if M then
        for p, i in pairs(s.pbar) do -- at or above p: the cell must reach p; below: it must start under p
            if prime[i] == 0 then
                if st[i] then
                    if (n + 1) * M <= p * 100 then
                        return "edge"
                    end
                elseif n * M >= p * 100 then
                    return "edge"
                end
            end
        end
    end
    return nil, n
end

-- The ring's quantum from its bars; an error word when the ring state, the cell code, its parity or the range is off.
local function ringDecode(s)
    local r, st, core = s.ring, lib.barState, s.core
    local key = 0
    for j = 1, N do
        if st[core[j]] then
            key = key + POW2[j - 1]
        end
    end
    local p = RK[key]
    if not p then
        return "ring"
    end
    local NB, code = r.NB, 0
    for k = 1, NB do
        if st[core[N + k]] then
            code = code + POW2[k - 1]
        end
    end
    local c = GINV[code]
    if c == nil or c >= r.ncell then
        return "code"
    end
    if st[core[N + NB + 1]] ~= (c % 2 == 1) then
        return "parity"
    end
    local q = c * N + p
    if q > r.mq then
        return "range"
    end
    -- the kept bars (step above 1, review I2) against the quantum's points A..B; a bar still priming says nothing
    local g, M, prime = r.g, s.max, lib.barPrime
    local A = q * g
    local B = math.min(A + g - 1, M)
    for e, i in pairs(s.bar) do
        if prime[i] == 0 then
            if st[i] then
                if 100 * B < e * M then
                    return "edge"
                end
            elseif 100 * A >= e * M then
                return "edge"
            end
        end
    end
    for pt, i in pairs(s.pbar) do
        if prime[i] == 0 then
            if st[i] then
                if B < pt then
                    return "edge"
                end
            elseif A >= pt then
                return "edge"
            end
        end
    end
    if s.gray then -- the position set beside: its cell's whole points must meet the quantum's (owner L1624)
        local n, bad = grayCell(st, core, N + NB + 1)
        if not n then
            return bad
        end
        if cellPoint(n, M) > B or cellPoint(n + 1, M) <= A then
            return "cross"
        end
        s.gn = n
    end
    return nil, q
end

-- Decodes the source's core set (position) before its handles. false: hold the handles' bands this frame (s.qv keeps
-- the last accepted value: the ring's quantum, or the Gray 1% cell). A decode other than s.qv is held until confirmed:
-- the next frame's decode gives the same value (owner, fix round 2 for the ring, fix round 3 for Gray: "it's
-- consistency"); a prime clears s.qv, so its first decode is held too (re-review 2 I-R2a). Half of a change whose bars
-- land over two frames is a valid state the client never held (a 2-3 point regen change across a cell read 50 off; a
-- spend whose cell bits landed in part read another cell, 516 for 116; a spend whose cell bars all came late read as a
-- small change, 272 for 122; a Gray jump 100 -> 85 with bit 0 and the parity late read 84); when a push's firings land
-- within two frames, the next frame's decode holds the rest of them, so a half-landed state does not repeat. A desync
-- (the source primes again) is a bad frame after a bad one with no firing in between, SETTLE bad frames in a row, or
-- more than SETTLE + 1 frames without a call (bad frames and holds; h:Latency()): a lost firing leaves the bars invalid
-- once the firings stop, while two changes on adjacent frames, each split over two frames, are invalid two frames in a
-- row with firings still landing (the owner's run of 2026-11-21: 4 desyncs in 2.5 min at ~10 changes/s). A value that
-- changes on every frame is never confirmed: the source desyncs every SETTLE + 2 frames until it slows.
function lib.decodeSource(s)
    local mode = s.mode
    if not mode then
        return true
    end
    local first = s.core[1]
    if not first or lib.barPrime[first] > 0 then
        s.ok = false
        return true
    end
    local bad, q
    if mode == "gray" then
        bad, q = grayDecode(s) -- q: the 1% cell
    else
        bad, q = ringDecode(s) -- q: the ring's quantum
    end
    local run = (s.run or 0) + 1 -- frames without a call, this one counted (an older minor's source has no s.run)
    if bad then
        s.bad, s.pend, s.run = s.bad + 1, nil, run
        if s.bad >= SETTLE or run > SETTLE + 1 or (s.bad >= 2 and (s.firedAt or -1) < lib.frameNo - 1) then
            lib.desyncs = lib.desyncs + 1
            lib.reprime(s)
            return true
        end
        s.dirty = true -- decode again next frame
        return false
    end
    if q and q ~= s.qv and q ~= s.pend then -- a change (or the first decode after a prime), not confirmed yet
        if run > SETTLE + 1 then
            lib.desyncs = lib.desyncs + 1
            lib.reprime(s)
            return true
        end
        if s.pend or s.bad > 0 then -- the decode moved while firings landed
            lib.splits = lib.splits + 1
        end
        s.pend, s.bad, s.run, s.dirty = q, 0, run, true -- decode again next frame, with or without a new firing
        return false
    end
    if q then
        s.qv, s.pend = q, nil
    end
    if s.bad > 0 then
        lib.splits = lib.splits + 1
        s.bad = 0
    end
    s.ok, s.run = true, 0
    return true
end

-- The handle's band from the source, in percent, or in points for a points handle (h.pts; the max is known then):
-- the cell for a step handle, then its own edges and points, each from its bar or the cell. false when the bars
-- contradict each other (edges mode: a firing was lost).
local function band(h)
    local s, st = h.src, lib.barState
    local n = s.mode == "gray" and s.qv or nil
    local M, pts = s.max, h.pts
    local A, B -- point precision: the value is in A..B (whole points)
    if s.mode == "ring" then
        local g = s.ring.g
        A = s.qv * g
        B = math.min(A + g - 1, M)
    end
    local top = pts and M or 100
    local lo, hi = 0, top
    if h.prec and (n or A) then
        if A then
            lo, hi = A, B < M and B + 1 or M
        else -- a max of 100 or less: the cell holds one whole point
            lo = math.floor((n * M + 99) / 100)
            hi = lo < M and lo + 1 or M
        end
    elseif h.step and (n or A) then
        local n1, n2 = n, n
        if A and s.gray then -- the position set beside the ring: one cell
            n1, n2 = s.gn, s.gn
        elseif A then -- the 1% cells the exact value spans (one at step 1)
            n1, n2 = math.floor(100 * A / M), math.floor(100 * B / M)
        end
        if pts then
            lo, hi = n1 * M / 100, n2 < 100 and (n2 + 1) * M / 100 or M
        else
            lo, hi = n1, n2 < 100 and n2 + 1 or 100
        end
    end
    local edges = h.edges
    for k = 1, #edges do
        local e = edges[k]
        local i, up = s.bar[e], nil
        if i then
            up = st[i]
        elseif n then
            up = n >= e
        elseif A then
            if 100 * A >= e * M then
                up = true
            elseif 100 * B < e * M then
                up = false
            end
        end
        local c = pts and e * M / 100 or e
        if up then
            if c > lo then
                lo = c
            end
        elseif up == false and c < hi then
            hi = c
        end
    end
    local pl = h.points
    for k = 1, #pl do
        local p = pl[k]
        local i, up = s.pbar[p], nil
        if i then
            up = st[i]
        elseif n then
            if n * M >= p * 100 then
                up = true
            elseif (n + 1) * M <= p * 100 or p > M then
                up = false
            end
        elseif A then
            if A >= p then
                up = true
            elseif B < p then
                up = false
            end
        end
        if up then
            if p > lo then
                lo = p
            end
        elseif up == false and p < hi then
            hi = p
        end
    end
    if lo > hi or (lo == hi and hi < top) then
        return false
    end
    return lo, hi
end

-- The exact value in points and its step for a point-precision handle, nil when the source does not know it.
function lib.exact(h)
    local s = h.src
    if not (s and s.ok and s.qv and h.prec) then -- no s.qv: a gray source from an older minor (s.n then)
        return nil
    end
    if s.mode == "ring" then
        local g = s.ring.g
        return s.qv * g, g
    end
    local M = s.max
    if s.mode == "gray" and M and M <= 100 then
        return math.floor((s.qv * M + 99) / 100), 1
    end
end

-- The handle's band and its sink when the band changed; at most one call per handle per frame (a second change in
-- the same frame waits for the next frame's decode: the source stays dirty).
function lib.decode(h)
    local lo, hi
    if lib.stateOf(h) == "live" and (not h.src.mode or h.src.ok) then
        lo, hi = band(h)
        if lo == false then -- at or above an edge but below a lower one: a firing was lost or split
            lib.desyncs = lib.desyncs + 1
            lib.reprime(h.src)
            return
        end
    end
    if lo == h.lo and hi == h.hi then
        return
    end
    local frame = lib.frameNo
    if h.stamp == frame then
        return
    end
    local dir = 0
    if lo and h.lo then
        dir = (lo > h.lo or hi > h.hi) and 1 or -1
    end
    -- t: the frame the change was seen (a firing or the end of priming, this frame or the last; two frames back on a
    -- position or precision source, whose change is called once the next decode agrees), else now
    local src = h.src
    local sf = src and src.seenFrame
    local t = (lo and sf and sf >= frame - (src.mode and 2 or 1)) and src.seen or GetTime()
    local q = lo and lib.BAND or lib.UNKNOWN
    if lo and h.prec and select(2, lib.exact(h)) == 1 then
        q = lib.EXACT
    end
    h.lo, h.hi, h.t, h.q, h.stamp = lo, hi, t, q, frame
    local fn = h.sink
    if fn then
        local ok, err = pcall(fn, h, lo, hi, dir, t, q)
        if not ok and not h.sinkErr then
            h.sinkErr = true
            lib.report(err)
        end
    end
end
