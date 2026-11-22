-- tests/Game/harness/fake_lhv.lua (LibHiddenValues integration design 5.4 item 2, lane B0): an observer-driven fake of
-- LibHiddenValues-1.0's handle contract for the loops, on the harness clock. The real library on its FakeClient would
-- add the fake client's own cost to the loops' CPU ratio, so the loops run this instead; the contract specs run the real
-- one (tests/Forever/bands_contract_spec.lua), and tests/Game/harness/fake_lhv_spec.lua holds both to the same shapes.
--
-- The observer drives it: `lib:Push(kind, unit, power, value, max, t)` is a firing (the world's true value at t, plain,
-- in its own units; value nil: no unit, the handle is gone), `lib:Prime(unit, t)` a change of the unit (a new target).
-- A handle answers from the pushes, read lazily in Get and State on the clock `o.now()`. What it models, each rule
-- citing its run as observer.lua's do (frames of `frame` seconds; the timing rows of fake_lhv_spec's shared block run
-- on the real library too, so it pins them):
--   fires:   a push fires only when it crosses a cut of a watch on the source (its 1% cell, an edge, a point); one that
--            does not updates the value silently (README, `step`: the bars fire on a cell change);
--   points:  on a step source an edge or a point crossed inside its cell is one bar's firing, reported a frame later,
--            and waits with a cell change while one is pending (`t` then the last firing of the two); each handle's `t`
--            is its own band's change (shared rows "points and a step", L1664 items 2-3);
--   setpts:  SetPoints with a point that needs a new bar (off the step's grid, on no other watch) primes that handle
--            9 frames, `t` the prime's end; another change of its band is a change of that frame (shared row);
--   hold:    a change is reported 2 frames after its last firing: every change of a step source waits for the next
--            frame's decode to agree (LibHiddenValues README, "Confirmation"; minor 7, `t` the change's last firing);
--            a firing back to the reported cut ends the change (an alternating value keeps the held band);
--   desync:  a change still unreported 6 frames after its first firing is never confirmed: the source reads unknown,
--            its prime decodes again, and the value is reported 10 frames after the desync at the earliest, held 2
--            frames after its last firing as any change (`t`: that firing, or the prime's end, 2 frames before the
--            earliest report, if later); still moving 6 frames after that decode, it desyncs again
--            (README, "Confirmation": "A value that moves one way on every frame is never confirmed");
--   latency: h:Latency() answers 7 frames (README, h:Latency(): seven frames worst case); not a reporting rule;
--   prime:   unknown for 10 frames after a watch starts, resumes or its unit changes, live on the 11th, `t` then the
--            prime's end (2 frames back) unless the value fired since (README, "Testing your addon": priming 10
--            frames at least: hold 4, push, settle 4, decode; shared rows "primes: ...", ledger L1664 item 1); a
--            points handle (one point or more) for 9 frames after its max moves (README, `points`: its point bars are
--            placed again on UNIT_MAXPOWER), `t` then that prime's end, a frame back;
--   cells:   a step watch is the 1% cell [lo, lo + 1), full its own closed cell [100, 100] (Bars.lua `band`; ledger
--            L1669), cut further by its edges or points; a points handle answers in points, its cell (max / 100) wide,
--            [max, max] at full (README, `step`, `points`); the library's 0.05% guard below each edge is not modelled;
--   caps:    8 distinct points per source and 64 in total, over either the request is refused with edge-limit and
--            nothing granted (README, `points`; GetPool).
-- shortcut: every handle times as a step source (Hekili's watches are step = 1, design decision 13): an edges-only
-- handle's 1-2 frame timing is not modelled, upgrade if a consumer watches edges only. shortcut: lib:Prime ends a
-- pending change or desync at once with the latest value (the real library primes the whole source again), each
-- handle then priming its 10 frames (a retarget's liveness and `t` are pinned by the shared rows; a desync running
-- across a retarget is not); upgrade if a consumer's gate turns on that case. Sinks are kept, never called
-- (the belief polls in Drain, decision 15). A point-precision spec is not read (Hekili never asks for one, decision
-- 6). No aura kind (unproven here), no bar pool: GetStats counts
-- watches only. GetVersion answers minor 7; GetSelfTest reads the capability (pending nil, a "selftest" loss false,
-- else true) and SelfTest calls back at once. `o.history`: every push kept per source, lib:TruthAt(kind, unit, power,
-- t) the last at or before t (the bands arms' containment, loop.bandCheck). The bands-drop arm's capability loss is
-- lib:SetAvailable; the unmeasured knobs (bandLead, spendFirst) are the observer's (observer.lua).
local M = {}

M.DEFAULTS = {
    frame = 1 / 60,
    hold = 2,
    desync = 6,
    reprime = 10,
    latency = 7,
    prime = 10,
    rebar = 9,
    pointCap = 8,
    pointTotal = 64,
}

M.UNKNOWN, M.BAND = 0, 2
M.ERR = {
    OWNER_INVALID = "owner-invalid",
    SPEC_INVALID = "spec-invalid",
    SINK_INVALID = "sink-invalid",
    KIND_INVALID = "kind-invalid",
    UNIT_INVALID = "unit-invalid",
    EDGES_INVALID = "edges-invalid",
    EDGES_OUT_OF_RANGE = "edges-out-of-range",
    EDGES_REQUIRED = "edges-required",
    STEP_INVALID = "step-invalid",
    POWER_REQUIRED = "power-required",
    POWER_INVALID = "power-invalid",
    POINTS_INVALID = "points-invalid",
    EDGE_LIMIT = "edge-limit",
}
-- The kinds of the major (README, GetKinds) and the units and powers proven for the two this fake models.
local KNOWN = { health = true, power = true, aura = true, cooldown = true, meter = true }
local UNITS = { health = { player = true, target = true }, power = { player = true } }
local PROVEN_POWER = { [0] = true, [1] = true, [3] = true } -- Mana, Rage, Energy
local GUARD = 0.05

local floor, sort = math.floor, table.sort

-- A sorted list of distinct whole points >= 1, or nil.
local function pointList(pts)
    if type(pts) ~= "table" then
        return nil
    end
    local list, seen = {}, {}
    for i = 1, #pts do
        local p = pts[i]
        if type(p) ~= "number" or not (p >= 1 and p < math.huge) or p % 1 ~= 0 then
            return nil
        end
        if not seen[p] then
            seen[p], list[#list + 1] = true, p
        end
    end
    sort(list)
    return list
end

-- The cuts of `pts` around v inside its 1% cell of max m.
local function pointCut(pts, v, m)
    local cell = floor(v * 100 / m)
    local lo, hi = cell * m / 100, (cell + 1) * m / 100
    for i = 1, #pts do
        local p = pts[i]
        if p <= v and p > lo then
            lo = p
        elseif p > v and p < hi then
            hi = p
        end
    end
    return lo, hi
end

function M.new(o)
    o = o or {}
    local R = {}
    for k, v in pairs(M.DEFAULTS) do
        R[k] = o[k] == nil and v or o[k]
    end
    local now = assert(o.now, "fake_lhv.new: o.now (the harness clock)")
    local lib = { UNKNOWN = M.UNKNOWN, BAND = M.BAND, ERR = M.ERR, rules = R, handles = {}, sources = {} }
    local cap, capWhy = "ready", nil
    local H = {}
    H.__index = H

    local function source(kind, unit, power)
        local key = kind .. "|" .. unit .. "|" .. tostring(power)
        local s = lib.sources[key]
        if not s then
            -- v, m: the reported value and max (v nil: unknown); pv, pm: the pending change, first at pf, its last cell
            -- firing at pl (cell: it holds one), its last firing of any bar at pa, not reported before `ready` (after a
            -- desync); mx: the last pushed max
            s = {
                key = key,
                v = nil,
                m = nil,
                t = nil,
                pend = false,
                pv = nil,
                pm = nil,
                pf = 0,
                pl = 0,
                pa = 0,
                cell = false,
                ready = 0,
                mx = nil,
                gone = false,
            }
            lib.sources[key] = s
        end
        return s
    end

    local EPS = R.frame / 1000 -- the deadlines fall on frame boundaries: a rounding ulp must not move one a frame

    -- h primes from t: unknown `prime` frames, live on the next; its first band stamped no earlier than the prime's end.
    local function prime(h, t)
        h.primeUntil = t + (R.prime + 1) * R.frame
        h.tFloor = h.primeUntil - R.hold * R.frame
        h.t = h.tFloor
    end

    -- New point bars of h from `t` (a max change, SetPoints): unknown `rebar` frames, stamped a frame before its end.
    local function rebar(h, untilT)
        if h.primeUntil < untilT then
            h.primeUntil, h.tFloor = untilT, untilT - R.frame
        end
    end

    -- What fires on h between two values (each in its own units, of its max): nil, CUT (an edge or a point) or CELL.
    local CUT, CELL = 1, 2
    local function fires(h, v1, m1, v2, m2)
        local x1, x2 = v1 * 100 / m1, v2 * 100 / m2
        if h.step and floor(x1) ~= floor(x2) then
            return CELL
        end
        local cuts, a, b = h.edges, x1, x2
        if h.points then
            cuts, a, b = h.points, v1, v2
        end
        for j = 1, #cuts do
            if (a >= cuts[j]) ~= (b >= cuts[j]) then
                return CUT
            end
        end
        return nil
    end

    -- The source reports v at `stamp`: each handle whose band that moves takes the stamp.
    local function report(s, v, m, stamp)
        local hs = lib.handles
        for i = 1, #hs do
            local h = hs[i]
            if h.src == s and (s.v == nil or (h.points and h.step and m ~= s.m) or fires(h, s.v, s.m, v, m)) then
                h.t = stamp
            end
        end
        s.v, s.m, s.t = v, m, stamp
    end

    -- Applies what happened by t with no firing since the last push, in order: the pending change is reported once it
    -- held `hold` frames (not before `ready`), or the source desyncs `desync` frames after its first firing (the report
    -- wins a tie); after a desync the prime's decode starts the change again (`reprime` frames to its earliest report).
    local function settle(s, t)
        while s.pend do
            local due = s.cell and s.pl + R.hold * R.frame or s.pa + R.frame -- a point inside the cell: one bar
            local cut = s.pf + R.desync * R.frame
            if due < s.ready then
                due = s.ready
            end
            if due <= cut + EPS then
                if t + EPS < due then
                    return
                end
                -- t: the last firing, or the prime's end when the change was a desync's and fired before it
                s.pend, s.ready = false, 0
                report(s, s.pv, s.pm, s.pa > s.pf and s.pa or s.pf)
            else
                if t + EPS < cut then
                    return
                end
                s.v, s.cell, s.ready = nil, true, cut + R.reprime * R.frame
                s.pf = s.ready - R.hold * R.frame
            end
        end
    end

    -- What fires on s between two values: nil, CUT or CELL (with no step watch every firing times as a cell's: the
    -- edges-only shortcut above).
    local function crosses(s, v1, m1, v2, m2)
        local hs, k, stepped = lib.handles, nil, false
        for i = 1, #hs do
            local h = hs[i]
            if h.src == s then
                local f = fires(h, v1, m1, v2, m2)
                if f == CELL then
                    return CELL
                end
                k, stepped = k or f, stepped or h.step ~= nil
            end
        end
        return k and (stepped and k or CELL)
    end

    -- Whether h's new list needs a bar the source does not run: a point off the step's grid that no watch holds.
    local function newBar(h, list)
        local s, stepped, held = h.src, false, {}
        for _, x in ipairs(lib.handles) do
            if x.src == s then
                stepped = stepped or x.step ~= nil
                for j = 1, x.points and #x.points or 0 do
                    held[x.points[j]] = true
                end
            end
        end
        for i = 1, #list do
            local p = list[i]
            if not held[p] and not (stepped and s.mx and p * 100 % s.mx == 0) then
                return true
            end
        end
        return false
    end

    -- nil, or the error code over the caps with `list` in place of h's points: distinct points per source (identical
    -- points share a bar), summed over the sources. Allocates (a Watch or SetPoints, out of combat).
    local function admit(h, list)
        local sets, total, mine = {}, 0, 0
        local function add(s, p)
            local set = sets[s]
            if not set then
                set = {}
                sets[s] = set
            end
            if not set[p] then
                set[p], total = true, total + 1
                if s == h.src then
                    mine = mine + 1
                end
            end
        end
        for _, x in ipairs(lib.handles) do
            for i = 1, x ~= h and x.points and x.src and #x.points or 0 do
                add(x.src, x.points[i])
            end
        end
        for i = 1, #list do
            add(h.src, list[i])
        end
        if mine > R.pointCap or total > R.pointTotal then
            return M.ERR.EDGE_LIMIT
        end
        return nil
    end

    function lib:Watch(owner, spec, sink)
        local E = M.ERR
        if type(owner) ~= "string" then
            return nil, E.OWNER_INVALID
        end
        if type(spec) ~= "table" then
            return nil, E.SPEC_INVALID
        end
        if sink ~= nil and type(sink) ~= "function" then
            return nil, E.SINK_INVALID
        end
        local kind = spec.kind
        if not KNOWN[kind] then
            return nil, E.KIND_INVALID
        end
        local h = setmetatable({ owner = owner, kind = kind, sink = sink }, H)
        if not UNITS[kind] then
            h.unproven = "unproven"
            lib.handles[#lib.handles + 1] = h
            return h
        end
        -- the real library's order of checks (Kinds/Percent.lua validate), so a bad spec gets the same code
        local unit, edges, step, pts = spec.unit, spec.edges, spec.step, spec.points
        if type(unit) ~= "string" or not unit:match("^%a%w*$") then
            return nil, E.UNIT_INVALID
        end
        if edges ~= nil and type(edges) ~= "table" then
            return nil, E.EDGES_INVALID
        end
        if step ~= nil and (type(step) ~= "number" or not (step > 0)) then
            return nil, E.STEP_INVALID
        end
        if pts ~= nil and type(pts) ~= "table" then
            return nil, E.POINTS_INVALID
        end
        if (edges == nil or #edges == 0) and step == nil and (pts == nil or #pts == 0) then
            return nil, E.EDGES_REQUIRED
        end
        if spec.power ~= nil and type(spec.power) ~= "number" then
            return nil, E.POWER_INVALID
        end
        if kind == "power" and spec.power == nil then
            return nil, E.POWER_REQUIRED
        end
        local cuts = {}
        for i = 1, edges and #edges or 0 do
            local e = edges[i]
            if type(e) ~= "number" then
                return nil, E.EDGES_INVALID
            end
            if not (e > GUARD and e <= 100) then
                return nil, E.EDGES_OUT_OF_RANGE
            end
            cuts[i] = e
        end
        sort(cuts)
        local list = pts and pointList(pts)
        if pts and not list then
            return nil, E.POINTS_INVALID
        end
        h.unit, h.power, h.edges, h.step = unit, kind == "power" and spec.power or nil, cuts, step and 1 or nil
        h.points = list -- nil: a percent handle (a points handle's percent edges are not modelled)
        if
            not UNITS[kind][unit]
            or (list and kind ~= "power")
            or (kind == "power" and not PROVEN_POWER[spec.power])
        then
            h.unproven = "unproven"
        else
            h.src = source(kind, unit, h.power)
            if list then
                local err = admit(h, list)
                if err then
                    return nil, err
                end
            end
        end
        prime(h, now())
        lib.handles[#lib.handles + 1] = h
        return h
    end

    -- The observer's firing: the true value (plain, its own units; nil: no unit) of a source at t.
    function lib:Push(kind, unit, power, value, max, t)
        local s = source(kind, unit, kind == "power" and power or nil)
        if o.history then -- the truth the harness checks a band against (lib:TruthAt); allocates
            local hist = s.hist or { n = 0, t = {}, v = {}, m = {} }
            s.hist = hist
            hist.n = hist.n + 1
            hist.t[hist.n], hist.v[hist.n], hist.m[hist.n] = t, value or false, max
        end
        settle(s, t)
        if value == nil then
            s.pend, s.v, s.m, s.t, s.gone = false, nil, nil, t, true
            return
        end
        s.gone = false
        if s.mx and max ~= s.mx then -- the point bars are placed again: each points handle primes
            for _, h in ipairs(lib.handles) do
                if h.src == s and h.points and #h.points > 0 then
                    rebar(h, t + R.rebar * R.frame)
                end
            end
        end
        s.mx = max
        if s.v == nil and not s.pend then -- the first value: a prime decodes it, no confirmation
            s.v, s.m, s.t = value, max, t
            return
        end
        if s.v ~= nil and not crosses(s, s.v, s.m, value, max) then -- no change, or back to the reported cut
            s.pend, s.ready, s.v, s.m = false, 0, value, max
            return
        end
        local kind
        if s.pend then
            kind = crosses(s, s.pv, s.pm, value, max)
            if not kind then -- inside the pending cut: nothing fires
                s.pv, s.pm = value, max
                return
            end
        else
            kind = crosses(s, s.v, s.m, value, max)
            s.pend, s.cell, s.pf, s.ready = true, false, t, 0
        end
        if kind == CELL then
            s.cell, s.pl = true, t
        end
        s.pv, s.pm, s.pa = value, max, t
    end

    -- The unit changed (a new target): every handle on it primes again; its sources take the latest value.
    function lib:Prime(unit, t)
        for _, s in pairs(lib.sources) do
            if s.pend and s.key:match("^%a+|" .. unit .. "|") then
                s.pend, s.ready = false, 0
                report(s, s.pv, s.pm, s.pa)
            end
        end
        for _, h in ipairs(lib.handles) do
            if h.unit == unit and not h.released then
                prime(h, t)
            end
        end
    end

    -- The capability (the bandDrop arm, a failed self-test): "ready", or "pending" / "unavailable" with a reason.
    function lib:SetAvailable(state, reason)
        cap, capWhy = state, reason
    end

    -- (o.history) The pushed truth of a source at t: the last push at or before t, value and max (nil: none; false:
    -- no unit).
    function lib:TruthAt(kind, unit, power, t)
        local s = lib.sources[kind .. "|" .. unit .. "|" .. tostring(kind == "power" and power or nil)]
        local hist = s and s.hist
        for i = hist and hist.n or 0, 1, -1 do
            if hist.t[i] <= t then
                return hist.v[i], hist.m[i]
            end
        end
        return nil
    end

    -- The major and the minor this fake follows (README, Diagnostics).
    function lib:GetVersion()
        return "LibHiddenValues-1.0", 7
    end

    -- The self-test as the capability says it: nil pending, false a failed self-test, else true; never running. No bar
    -- model to test: SelfTest calls fn at once with that verdict.
    local LINES = {}
    function lib:GetSelfTest()
        if cap == "pending" then
            return nil, nil, false
        end
        return capWhy ~= "selftest", LINES, false
    end

    function lib:SelfTest(fn)
        if fn then
            fn((lib:GetSelfTest()), LINES)
        end
    end

    function lib:IsAvailable(kind, unit)
        if not UNITS[kind] then
            return false, "unavailable", KNOWN[kind] and "unproven" or "unknown-kind"
        end
        if cap == "ready" and unit ~= nil and not UNITS[kind][unit] then
            return false, "unavailable", "unproven"
        end
        return cap == "ready", cap, capWhy
    end

    function lib:ReleaseAll(owner)
        for i = #lib.handles, 1, -1 do
            local h = lib.handles[i]
            if h and h.owner == owner then
                h:Release()
            end
        end
    end

    -- bars, usFrame, usPeak, pushesPerSec, firesPerSec, desyncs, level, splits: no bar model, the watches count as bars.
    function lib:GetStats()
        return #lib.handles, 0, 0, 0, 0, 0, 0, 0
    end

    function H:State()
        if self.released then
            return "released"
        end
        if self.unproven then
            return "unavailable", self.unproven
        end
        if cap ~= "ready" then
            return cap, capWhy
        end
        if self.paused then
            return "paused"
        end
        local s, t = self.src, now()
        settle(s, t)
        if s.gone then
            return "gone"
        end
        if t + EPS < self.primeUntil or s.v == nil then
            return "priming"
        end
        return "live"
    end

    -- lo, hi, t, q; nil, nil, nil, UNKNOWN unless live, or the band at the pause while paused (as the real library's
    -- handle keeps its last band: only State says paused). Allocates nothing.
    function H:Get()
        if self.paused and not self.released and self.plo then
            return self.plo, self.phi, self.pt, M.BAND
        end
        if self:State() ~= "live" then
            return nil, nil, nil, M.UNKNOWN
        end
        local s = self.src
        local v, m = s.v, s.m
        local top = self.points and m or 100
        local x = self.points and v or v * 100 / m -- multiply first: whole values give exact cells
        local lo, hi = 0, top
        local cuts = self.points or self.edges
        for i = 1, #cuts do
            local c = cuts[i]
            if c <= x and c > lo and c < top then
                lo = c
            elseif c > x and c < hi then
                hi = c
            end
        end
        if self.step then
            local cell = floor(v * 100 / m)
            local glo, ghi = cell, cell < 100 and cell + 1 or 100 -- full: the closed cell [100, 100] (ledger L1669)
            if self.points then
                glo, ghi = glo * m / 100, ghi * m / 100
            end
            lo, hi = lo > glo and lo or glo, hi < ghi and hi or ghi
        end
        local t, at = self.t or s.t, now()
        if self.tFloor and self.tFloor > t then -- a band first known at a prime: stamped at its end
            t = self.tFloor
        end
        if t > at then -- SetPoints' change: seen in the next frame
            t = at
        end
        return lo, hi, t, M.BAND
    end

    function H:Latency()
        return R.latency * R.frame
    end

    function H:SetPoints(list)
        local pts = not self.released and self.points and pointList(list)
        if not pts then
            return nil, M.ERR.POINTS_INVALID
        end
        local err = self.src and admit(self, pts)
        if err then
            return nil, err
        end
        local s = self.src
        if s then
            local t = now()
            if newBar(self, pts) then
                rebar(self, t + (R.rebar + 1) * R.frame)
            elseif s.v ~= nil then -- a band the new set cuts elsewhere is a change of the next frame
                local lo0, hi0 = pointCut(self.points, s.v, s.m)
                local lo1, hi1 = pointCut(pts, s.v, s.m)
                if lo0 ~= lo1 or hi0 ~= hi1 then
                    self.t = t + R.frame
                end
            end
        end
        self.points = pts
        return true
    end

    function H:SetSink(fn)
        if fn == nil or type(fn) == "function" then
            self.sink = fn
        end
    end

    function H:SetPaused(paused)
        if self.paused and not paused then
            prime(self, now()) -- a resumed watch primes again
            self.plo, self.phi, self.pt = nil, nil, nil
        elseif paused and not self.paused then
            self.plo, self.phi, self.pt = self:Get()
        end
        self.paused = paused and true or nil
    end

    function H:Release()
        if self.released then
            return
        end
        self.released = true
        for i = #lib.handles, 1, -1 do
            if lib.handles[i] == self then
                table.remove(lib.handles, i)
                break
            end
        end
    end

    return lib
end

return M
