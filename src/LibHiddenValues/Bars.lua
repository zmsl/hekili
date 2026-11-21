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
-- an edge on the 1% grid then needs no bar); point precision (Kinds/Percent.lua's ring, stage 3 task D). A position
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

-- The Step curve of a point threshold p at the plain max M: 1 below p, 2 at or above. The step sits half a point below
-- p (a last-bit error in the client's percent cannot move a whole point across it), its guard a quarter point lower
-- (BandProbe2 0.3.0's construction). One per (M, p), shared.
function lib.pointCurve(p, M)
    local byMax = lib.ptCurves[M]
    if not byMax then
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
-- it. Raises when the client refuses a point (callers use pcall). A cold path: build time only.
function lib.levelCurve(bit, top, xOf, eps)
    local c = C_CurveUtil.CreateCurve()
    c:SetType(Enum.LuaCurveType.Step)
    local prev = bit(0)
    c:AddPoint(0, LOW + prev)
    for n = 1, top do
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

-- The position set's curves (Gray bits 0-6, then the parity bar), built once; false when the client refused them.
function lib.grayCurves()
    if lib.gcurve == nil then
        local ok, list = pcall(function()
            local t = {}
            local function xOf(n)
                return n / 100
            end
            for k = 0, NGRAY - 1 do
                t[k + 1] = lib.levelCurve(function(n)
                    return math.floor(GRAY[n] / POW2[k]) % 2
                end, 100, xOf, EPS)
            end
            t[NGRAY + 1] = lib.levelCurve(function(n)
                return n % 2
            end, 100, xOf, EPS)
            return t
        end)
        lib.gcurve = ok and list or false
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
    s.bad, s.ok = 0, false
    s.dirty = true
    lib.wake()
end

-- Whether a percent edge needs a bar of its own in a mode (position covers the 1% grid).
local function needEdge(mode, e)
    return mode == nil or (mode == "gray" and e % 1 ~= 0)
end

-- Whether a point threshold needs a bar of its own in a mode at the max M (position covers p when p / M is on the 1%
-- grid: p * 100 a multiple of M, plain integers).
local function needPoint(mode, M, p)
    return mode == nil or (mode == "gray" and not (M and (p * 100) % M == 0))
end

-- Every bar the handle rests on is there (false: the cap was reached, the handle is suspended).
local function served(s, h)
    local mode = s.mode
    if mode and not s.core[1] then
        return false
    end
    for k = 1, #h.edges do
        local e = h.edges[k]
        if not s.bar[e] and needEdge(mode, e) then
            return false
        end
    end
    local pts = h.points
    for k = 1, #pts do
        local p = pts[k]
        if not s.pbar[p] and needPoint(mode, s.max, p) then
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
function lib.modeFor(step)
    return step and "gray" or nil
end

function lib.modeOf(s)
    local step = false
    for j = 1, #s.handles do
        step = step or s.handles[j].step ~= nil
    end
    return lib.modeFor(step)
end

-- The player's plain max of the source's power type: a secret one (or a say-so that it is secret) keeps the last
-- plain value; 0 or none is nil (never a divisor).
function lib.maxOf(unit, power, last)
    if power == nil then
        return nil
    end
    local should = C_Secrets and C_Secrets.ShouldUnitPowerMaxBeSecret
    if should then
        local sec = should(unit, power)
        if issecretvalue(sec) or sec then
            return last
        end
    end
    local m = UnitPowerMax and UnitPowerMax(unit, power)
    if issecretvalue(m) or type(m) ~= "number" or not (m > 0) then
        return last
    end
    return m
end

-- Bars a set of handles needs on a source, and how many of them are point bars (a cold path: admission). add joins
-- the set; swapH counts with swapList as its points.
function lib.need(s, add, swapH, swapList)
    local M = s.kind == "power" and lib.maxOf(s.unit, s.power, s.max) or nil
    local step, edges, points = false, {}, {}
    local function take(h)
        step = step or h.step ~= nil
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
    local mode = lib.modeFor(step)
    local bars, pb = mode == "gray" and 8 or 0, 0
    for e in pairs(edges) do
        if needEdge(mode, e) then
            bars = bars + 1
        end
    end
    for p in pairs(points) do
        if needPoint(mode, M, p) then
            pb = pb + 1
        end
    end
    return bars + pb, pb
end

-- nil when the handle (with newPoints, when given, as its points) fits the caps, else the error code: EDGE_LIMIT over
-- the point caps, POOL_LIMIT over the pool. Nothing is granted here.
function lib.admit(h, newPoints)
    local s = lib.srcByKey[lib.keyOf(h)]
    local cur = s or { kind = h.kind, unit = h.unit, power = h.power, handles = {} }
    local bars, pb
    if newPoints then
        bars, pb = lib.need(cur, nil, h, newPoints)
    else
        bars, pb = lib.need(cur, h)
    end
    if pb > lib.POINTS_PER_SOURCE then
        return lib.ERR.EDGE_LIMIT
    end
    for k = 1, #lib.sources do
        local o = lib.sources[k]
        if o ~= s then
            local b, p = lib.need(o)
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

-- The core set of the mode (all or nothing): false when a bar or a curve could not be had.
local function allocCore(s)
    local curves = lib.grayCurves()
    if not curves then
        return false
    end
    for k = 1, #curves do
        local i = lib.allocBar(s, curves[k])
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
    local mode = ready and lib.modeOf(s) or nil
    if mode ~= s.mode then
        freeCore(s)
        s.mode, s.bad, s.ok = mode, 0, false
    end
    local want = false
    if ready then
        s.gone = not lib.present(s.unit) or (s.kind == "health" and lib.dead(s.unit))
        if mode and not s.core[1] then
            allocCore(s)
        end
        for e, n in pairs(s.ref) do
            if n > 0 and not s.bar[e] and needEdge(mode, e) then
                s.bar[e] = lib.allocBar(s, lib.curveFor(e))
            end
        end
        if M then
            for p, n in pairs(s.pref) do
                if n > 0 and not s.pbar[p] and needPoint(mode, M, p) then
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
        if not ready or s.ref[e] == 0 or not needEdge(mode, e) then
            lib.freeBar(i)
            s.bar[e] = nil
        end
    end
    for p, i in pairs(s.pbar) do
        if not ready or s.pref[p] == 0 or not needPoint(mode, M, p) then
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
    s.dirty, s.seen, s.seenFrame = true, GetTime(), lib.frameNo
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

-- The position set's cell from its bars; an error word when the code, the parity or an edge bar disagrees.
local function grayDecode(s)
    local st, core = lib.barState, s.core
    local code = 0
    for k = 1, NGRAY do
        if st[core[k]] then
            code = code + POW2[k - 1]
        end
    end
    local n = GINV[code]
    if n == nil or n > 100 then
        return "code"
    end
    if st[core[NGRAY + 1]] ~= (n % 2 == 1) then
        return "parity"
    end
    for e, i in pairs(s.bar) do
        if st[i] then
            if n + 1 <= e then
                return "edge"
            end
        elseif n >= e then
            return "edge"
        end
    end
    local M = s.max
    if M then
        for p, i in pairs(s.pbar) do -- at or above p: the cell must reach p; below: it must start under p
            if st[i] then
                if (n + 1) * M <= p * 100 then
                    return "edge"
                end
            elseif n * M >= p * 100 then
                return "edge"
            end
        end
    end
    s.n = n
end

-- Decodes the source's core set (position) before its handles. false: hold the handles' bands this frame (a split);
-- two bad frames in a row are a desync and the source primes again.
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
    if grayDecode(s) then
        s.bad = s.bad + 1
        if s.bad >= 2 then
            lib.desyncs = lib.desyncs + 1
            lib.reprime(s)
            return true
        end
        s.dirty = true -- decode again next frame
        return false
    end
    if s.bad > 0 then
        lib.splits = lib.splits + 1
        s.bad = 0
    end
    s.ok = true
    return true
end

-- The handle's band from the source, in percent, or in points for a points handle (h.pts; the max is known then):
-- the cell for a step handle, then its own edges and points, each from its bar or the cell. false when the bars
-- contradict each other (edges mode: a firing was lost).
local function band(h)
    local s, st = h.src, lib.barState
    local n = s.mode == "gray" and s.n or nil
    local M, pts = s.max, h.pts
    local top = pts and M or 100
    local lo, hi = 0, top
    if h.step and n then
        if pts then
            lo, hi = n * M / 100, n < 100 and (n + 1) * M / 100 or M
        else
            lo, hi = n, n < 100 and n + 1 or 100
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
    -- t: the frame the change was seen (a firing or the end of priming, this frame or the last), else now
    local sf = h.src and h.src.seenFrame
    local t = (lo and sf and sf >= frame - 1) and h.src.seen or GetTime()
    local q = lo and lib.BAND or lib.UNKNOWN
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
