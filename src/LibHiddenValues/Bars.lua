-- Bars.lua: the bar pool, the curves, priming, the firing and the decode (named edges).
--
-- The mechanism (measured, BandProbe run 2026-11-20): a read with a Step curve returns a hidden 1 (below the edge) or
-- 2 (at or above it); pushed into a StatusBar ranged 0-2 it fills half or all of it; a frame anchored to the fill
-- texture gets OnSizeChanged when the fill changes, after the frame's scripts. That firing is plain. Its arguments
-- are secret and never read: each bar keeps one plain boolean the firing flips (a toggle), so a bar needs a known
-- start: priming holds it at the plain low level for HOLD frames, clears the boolean, then feeds the live value (it
-- fires if and only if the value is at or above the edge) and counts its firings for SETTLE more frames before the
-- handle goes live: a secret push's firing can trail it by a frame (LHVProbe 2026-11-20), and a decode before it
-- arrived reported the lowest band, then the real one with dir 1.
-- The encoding stays internal: a handle reads its band through decode, so a position encoding can join the edges
-- without changing the surface.
local lib = LibStub and LibStub("LibHiddenValues-1.0", true)
if not (lib and lib.loading) then
    return
end

local HOLD = 4 -- frames at the low level before the live value (the run saw every firing in its own frame)
-- frames the live push's firing may trail it: the self-test's limit for plain pushes (3), plus the frame a secret one
-- was seen to add (BandProbe v1 counted 4 frames after the push: "IN window 4")
local SETTLE = 4
local LOW = 1 -- the curve's "below" output; "at or above" is 2
local EPS = 0.0005 -- a guard point this far below each step (curve x scale 0-1), whichever way the client snaps
local CAP = 256 -- bars are never destroyed (frames cannot be): a hard ceiling on the pool
lib.HOLD, lib.SETTLE, lib.LOW, lib.POOL = HOLD, SETTLE, LOW, 32

-- Bars made (frames are never destroyed) and the cap.
function lib:GetPool()
    return #lib.barFrame, CAP
end

lib.barFrame = lib.barFrame or {}
lib.barClip = lib.barClip or {}
lib.barSrc = lib.barSrc or {} -- the source a bar serves (lib.ST: the self-test), nil when free
lib.barState = lib.barState or {} -- plain: the value is at or above the bar's edge
-- frames of priming left: > SETTLE + 1 hold low, SETTLE + 1 feed live next, 1..SETTLE settling (fed live, firings
-- counted), 0 live
lib.barPrime = lib.barPrime or {}
lib.free = lib.free or {}
lib.curves = lib.curves or {} -- one per edge, shared by every source
lib.ST = lib.ST or {}
lib.desyncs = lib.desyncs or 0
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

-- A free bar for owner's edge e, priming; nil at the cap (growth in combat is tried under pcall: it may be refused).
function lib.allocBar(owner, e)
    local free = lib.free
    if #free == 0 then
        local ok = pcall(lib.newBar)
        if not ok or #free == 0 then
            return nil
        end
    end
    local i = free[#free]
    free[#free] = nil
    lib.curveFor(e)
    lib.barSrc[i], lib.barState[i], lib.barPrime[i] = owner, false, HOLD + SETTLE + 1
    return i
end

function lib.freeBar(i)
    lib.barSrc[i], lib.barPrime[i] = nil, 0
    lib.free[#lib.free + 1] = i
end

-- Every bar of the source primes; its handles go unknown until they are live again.
function lib.reprime(s)
    for _, i in pairs(s.bar) do
        lib.barPrime[i] = HOLD + SETTLE + 1
    end
    s.dirty = true
    lib.wake()
end

-- Every edge of the handle has a bar on its source (false: the cap was reached, the handle is suspended).
local function served(s, h)
    for k = 1, #h.edges do
        if not s.bar[h.edges[k]] then
            return false
        end
    end
    return true
end

-- Brings a source in line with the capability, its references, its unit and its handles: allocates a bar for each
-- referenced edge when the kind is ready (only a new bar primes), frees the rest, and feeds it while any handle is
-- neither paused nor suspended and its unit is there.
function lib.sync(s)
    local ready = lib.realised and lib.capOf(s.kind) == "ready"
    local want = false
    if ready then
        s.gone = not lib.present(s.unit) or (s.kind == "health" and lib.dead(s.unit))
        for e, n in pairs(s.ref) do
            if n > 0 and not s.bar[e] then
                s.bar[e] = lib.allocBar(s, e)
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
        if not ready or s.ref[e] == 0 then
            lib.freeBar(i)
            s.bar[e] = nil
        end
    end
    if want and not s.active then
        lib.reprime(s)
    end
    s.active = want
    s.dirty = true
    lib.wake()
end

-- A bar's anchored child fired: its fill changed. Ignored while the bar holds low; counted while it settles. A handle on this bar alone is called
-- now (the frame of the push); handles on several bars are decoded at the start of the next frame.
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
    local hs = s.handles
    for j = #hs, 1, -1 do
        local h = hs[j]
        if h and #h.edges == 1 and s.bar[h.edges[1]] == i then
            lib.decode(h)
        end
    end
end

-- The handle's band from its own edges, and its sink when the band changed; at most one call per handle per frame (a
-- second change in the same frame waits for the next frame's decode: the source stays dirty).
function lib.decode(h)
    local lo, hi
    if lib.stateOf(h) == "live" then
        local s, st = h.src, lib.barState
        local below = false
        lo, hi = 0, 100
        for k = 1, #h.edges do
            local e = h.edges[k]
            if st[s.bar[e]] then
                if below then -- at or above an edge but below a lower one: a firing was lost or split
                    lib.desyncs = lib.desyncs + 1
                    lib.reprime(s)
                    return
                end
                lo = e
            elseif not below then
                below, hi = true, e
            end
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
