-- tests/Game/harness/fake_lhv.lua (LibHiddenValues integration design 5.4 item 2, lane B0): an observer-driven fake of
-- LibHiddenValues-1.0's handle contract for the loops, on the harness clock. The real library on its FakeClient would
-- add the fake client's own cost to the loops' CPU ratio, so the loops run this instead; the contract specs run the real
-- one (tests/Forever/bands_contract_spec.lua), and tests/Game/harness/fake_lhv_spec.lua holds both to the same shapes.
--
-- The observer drives it: `lib:Push(kind, unit, power, value, max, t)` is a firing (the world's true value at t, plain,
-- in its own units; value nil: no unit, the handle is gone), `lib:Prime(unit, t)` a change of the unit (a new target).
-- A handle answers from the pushes, read lazily in Get and State on the clock `o.now()`. What it models, each rule
-- citing its run as observer.lua's do (frames of `frame` seconds):
--   hold:    a change is reported 2 frames after its last firing: every change of a step source waits for the next
--            frame's decode to agree (LibHiddenValues README, "Confirmation"; minor 7, `t` the change's last firing);
--   latency: while firings keep landing, a change is reported at most 7 frames after its first one, with the latest
--            value (README, h:Latency(): seven frames worst case);
--   prime:   unknown for 10 frames after a watch starts, resumes or its unit changes (README, "Testing your addon":
--            priming 10 frames at least: hold 4, push, settle 4, decode);
--   cells:   a step watch is the 1% cell [lo, lo + 1) (hi inclusive at 100), cut further by its edges or points; a
--            points handle answers in points, its cell (max / 100) wide (README, `step`, `points`);
--   caps:    8 distinct points per source and 64 in total, over either the request is refused with edge-limit and
--            nothing granted (README, `points`; GetPool).
-- shortcut: every handle times as a step source (Hekili's watches are step = 1, design decision 13): an edges-only
-- handle's 1-2 frame timing is not modelled, upgrade if a consumer watches edges only. Sinks are kept, never called
-- (the belief polls in Drain, decision 15). A point-precision spec is not read (Hekili never asks for one, decision
-- 6). No aura kind (unproven here), no bar pool: GetStats counts
-- watches only. The unmeasured knobs (bandLead, spendFirst) come with the lanes that need them.
local M = {}

M.DEFAULTS = { frame = 1 / 60, hold = 2, latency = 7, prime = 10, pointCap = 8, pointTotal = 64 }

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
            -- v, m: the reported value and max (v nil: unknown); pv, pm: the pending change, first at pf, last at pl
            s = { key = key, v = nil, m = nil, t = nil, pend = false, pv = nil, pm = nil, pf = 0, pl = 0, gone = false }
            lib.sources[key] = s
        end
        return s
    end

    -- The pending change becomes the reported value once it held `hold` frames, or `latency` frames after its first.
    local function settle(s, t)
        if s.pend and (t >= s.pl + R.hold * R.frame or t >= s.pf + R.latency * R.frame) then
            s.pend, s.v, s.m, s.t = false, s.pv, s.pm, s.pl
        end
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
        h.primeUntil = now() + R.prime * R.frame
        lib.handles[#lib.handles + 1] = h
        return h
    end

    -- The observer's firing: the true value (plain, its own units; nil: no unit) of a source at t.
    function lib:Push(kind, unit, power, value, max, t)
        local s = source(kind, unit, kind == "power" and power or nil)
        settle(s, t)
        if value == nil then
            s.pend, s.v, s.m, s.t, s.gone = false, nil, nil, t, true
            return
        end
        s.gone = false
        if s.v == nil and not s.pend then -- the first value: a prime decodes it, no confirmation
            s.v, s.m, s.t = value, max, t
            return
        end
        if not s.pend then
            if value == s.v and max == s.m then
                return
            end
            s.pend, s.pf = true, t
        end
        s.pv, s.pm, s.pl = value, max, t
    end

    -- The unit changed (a new target): every handle on it primes again.
    function lib:Prime(unit, t)
        for _, h in ipairs(lib.handles) do
            if h.unit == unit and not h.released then
                h.primeUntil = t + R.prime * R.frame
            end
        end
    end

    -- The capability (the bandDrop arm, a failed self-test): "ready", or "pending" / "unavailable" with a reason.
    function lib:SetAvailable(state, reason)
        cap, capWhy = state, reason
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
        if t < self.primeUntil or s.v == nil then
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
            if cell >= 100 then
                cell = cell - 1 -- hi inclusive at the top
            end
            local glo, ghi = cell, cell + 1
            if self.points then
                glo, ghi = cell * m / 100, (cell + 1) * m / 100
            end
            lo, hi = lo > glo and lo or glo, hi < ghi and hi or ghi
        end
        return lo, hi, s.t, M.BAND
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
            self.primeUntil = now() + R.prime * R.frame -- a resumed watch primes again
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
