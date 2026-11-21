-- LibHiddenValues.lua: the entry point. LibStub("LibHiddenValues-1.0"): threshold events for values the client hides
-- (unit health and power percent), as plain numbers. Consumers declare what they want (Watch); the library owns the
-- hidden bars, the client events, the priming and the capability state. This file: the registry, the handles, the
-- capability answers and the kill switch. Bars.lua: the bar pool, curves, priming, the firing and the decode.
-- Feed.lua: the driver, the client events, the statistics. Kinds/*.lua: one file per family of kinds.
--
-- Upgrades: the newest minor on the client runs; every file after this one returns unless this copy won LibStub
-- (lib.loading). All state lives on lib, as plain data; scripts are one-line dispatchers through lib, so a newer minor
-- replaces behaviour by replacing functions. Nothing is built before PLAYER_LOGIN. The addon name and the private
-- table from `...` are never used (an embedded copy would receive its host's).
local MAJOR, MINOR = "LibHiddenValues-1.0", 7
local lib, oldMinor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return
end
lib.loading, lib.oldMinor = true, oldMinor

-- Quality codes (the major's contract).
lib.UNKNOWN, lib.COARSE, lib.BAND, lib.EXACT = 0, 1, 2, 3

-- Error codes: Watch and every call that refuses input return nil, code. Codes are plain strings, never English
-- text; lib:GetMessage(code) gives the words.
lib.ERR = {
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
    POOL_LIMIT = "pool-limit",
    PRECISION_INVALID = "precision-invalid",
    SPELL_INVALID = "spell-invalid",
    SPELL_OR_COOLDOWN = "spell-or-cooldown",
    COOLDOWN_INVALID = "cooldown-invalid",
    WHAT_INVALID = "what-invalid",
    MAX_INVALID = "max-invalid",
}

-- Messages for error codes, handle states and capability reasons, per locale; enUS only for now.
lib.MESSAGES = {
    enUS = {
        ["owner-invalid"] = "The owner must be a string (your addon's name).",
        ["spec-invalid"] = "The spec must be a table.",
        ["sink-invalid"] = "The sink must be a function or nil.",
        ["kind-invalid"] = "Unknown kind.",
        ["unit-invalid"] = "The unit must be a unit token.",
        ["edges-invalid"] = "The edges must be a list of numbers (whole numbers for aura stacks).",
        ["edges-out-of-range"] = "An edge is out of range: percent above 0.05 and at most 100; aura stacks from 1 "
            .. "to max; aura seconds above 0.01.",
        ["edges-required"] = "The spec needs edges, a step, points or a precision (aura stacks: edges or max; "
            .. "aura seconds: edges).",
        ["step-invalid"] = "The step must be a positive number.",
        ["power-required"] = "A power watch needs its power type (an Enum.PowerType number).",
        ["power-invalid"] = "The power type must be an Enum.PowerType number.",
        ["points-invalid"] = "The points must be a list of whole numbers of 1 or more, on a points handle.",
        ["edge-limit"] = "Too many point thresholds: over the cap per value or in total (nothing was granted).",
        ["pool-limit"] = "Not enough bars left in the pool (nothing was granted).",
        ["precision-invalid"] = 'The precision must be "point" or nil.',
        ["spell-invalid"] = "The spell must be a spell ID (a whole number above 0).",
        ["spell-or-cooldown"] = "An aura watch names exactly one of spell or cooldown.",
        ["cooldown-invalid"] = "The cooldown must be a Cooldown Manager cooldownID (a whole number above 0).",
        ["what-invalid"] = 'The aura\'s what must be "up", "stacks" or "left".',
        ["max-invalid"] = "The max must be a whole number of stacks, 1 or more.",
        ["max-unknown"] = "The maximum is not known (never read as a plain number).",
        live = "Live: a band is known.",
        priming = "Priming: the band is not known yet.",
        pending = "Pending: the self-test has not passed yet.",
        gone = "Gone: the unit is not there or is dead (an aura: its Cooldown Manager item cannot be read).",
        paused = "Paused by its owner.",
        suspended = "Suspended: no bar was free for it, or the client refused the curves it needs.",
        unavailable = "Unavailable.",
        released = "Released.",
        ready = "Ready.",
        api = "The client lacks an API this needs.",
        selftest = "The self-test failed.",
        error = "Switched off after an error.",
        off = "Switched off for this session.",
        unproven = "Not proven on this client yet.",
        ["unknown-kind"] = "Unknown kind.",
        ["bad-spec"] = "The spec is not valid (Watch returns its error code).",
        ["cdm-off"] = "The Cooldown Manager is off or missing: switch it on in Options.",
        ["not-in-cdm"] = "No Cooldown Manager entry names this spell (or has this cooldownID).",
        ["cdm-not-tracked"] = "Not shown in the Cooldown Manager: place it in Tracked Buffs, or Tracked Bars.",
        ["cdm-icon-only"] = "Shown as an icon, which has no timer: move it to Tracked Bars.",
        ["cdm-cooldown-only"] = "Shown only as a cooldown (Essential or Utility), which has no stack count or "
            .. "timer: place the aura in Tracked Buffs or Tracked Bars.",
    },
}

-- The message for an error code, a state or a reason in locale (default: the client's), nil when the library has no
-- text for that locale or code yet: map the code yourself then.
function lib:GetMessage(code, locale)
    local t = lib.MESSAGES[locale or (GetLocale and GetLocale()) or "enUS"]
    return t and code ~= nil and t[code] or nil
end

-- Every kind name of the major's contract; only those with a file in Kinds/ are built (lib.kinds). The aura kind reads
-- the client's Cooldown Manager (Cdm.lua): the client's aura container only takes widgets owned by its forbidden aura
-- button.
lib.KINDS =
    { "health", "power", "cooldown", "charges", "cast", "totem", "loc", "bool", "aura", "threat", "absorb", "meter" }
lib.KNOWN = {}
for i = 1, #lib.KINDS do
    lib.KNOWN[lib.KINDS[i]] = true
end

lib.reg = lib.reg or {} -- every handle not released
lib.sources = lib.sources or {} -- one per canonical key; never removed (a key's table is reused when watched again)
lib.srcByKey = lib.srcByKey or {}
lib.kinds = lib.kinds or {}
lib.capCb = lib.capCb or {}
lib.capSeen = lib.capSeen or {}
lib.errored = lib.errored or {}
lib.stWaiters = lib.stWaiters or {}
lib.H = lib.H or {}
lib.handleMeta = lib.handleMeta or { __index = lib.H }
lib.NOPOINTS = lib.NOPOINTS or {} -- shared and never written: the points of a handle that has none
-- An older minor's handles and sources (a newer copy loaded over it) get this minor's fields.
for i = 1, #lib.reg do
    local h = lib.reg[i]
    h.points = h.points or lib.NOPOINTS
    h.barless = h.barless or (h.kind == "aura" and h.what == "up") or nil
end
for i = 1, #lib.sources do
    local s = lib.sources[i]
    s.core, s.pbar, s.pref, s.bad = s.core or {}, s.pbar or {}, s.pref or {}, s.bad or 0
end
lib.apiMissing = not (
    C_CurveUtil
    and C_CurveUtil.CreateCurve
    and Enum
    and Enum.LuaCurveType
    and Enum.LuaCurveType.Step
    and issecretvalue
    and CreateFrame
    and UIParent
    and GetTime
    and debugprofilestop
)

function lib:GetVersion()
    return MAJOR, MINOR
end

-- Passes an error to the client's handler (never a secret: a plain stand-in replaces it).
function lib.report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(issecretvalue and issecretvalue(err) and "LibHiddenValues: an error with a secret message" or err)
    end
end

-- Capability ------------------------------------------------------------------------------------------------------

-- state "ready" | "pending" | "unavailable", reason (nil when not unavailable). barless: a watch that rests on no bar
-- (an aura's presence): the bar self-test, pending or failed, does not gate it; every other reason does.
function lib.capOf(kind, barless)
    if not lib.KNOWN[kind] then
        return "unavailable", "unknown-kind"
    end
    local k = lib.kinds[kind]
    if not k then
        return "unavailable", "unproven"
    end
    if lib.apiMissing or _G[k.api] == nil then
        return "unavailable", "api"
    end
    if lib.disabled then
        return "unavailable", "off"
    end
    if lib.errored[kind] then
        return "unavailable", "error"
    end
    local why = k.why and k.why()
    if why then
        return "unavailable", why
    end
    if barless then
        return "ready"
    end
    if lib.stVerdict == false then
        return "unavailable", "selftest"
    end
    if lib.stVerdict == nil then
        return "pending"
    end
    return "ready"
end

-- unit: a unit token, or a whole spec (the aura kind answers for its spell and what: placement reasons).
function lib:IsAvailable(kind, unit)
    local spec
    if type(unit) == "table" then
        spec, unit = unit, unit.unit
    end
    local k = lib.kinds[kind]
    local state, reason = lib.capOf(kind, spec and k and k.barless and k.barless(spec))
    if state ~= "unavailable" and unit ~= nil and not lib.kinds[kind].units[unit] then
        return false, "unavailable", "unproven"
    end
    if state == "ready" and spec and lib.kinds[kind].status then
        state, reason = lib.kinds[kind].status(spec)
    end
    return state == "ready", state, reason
end

-- Every kind of the major in contract order, each { kind =, state =, reason = } as IsAvailable gives them (a fresh
-- array: a cold path).
function lib:GetKinds()
    local out = {}
    for i = 1, #lib.KINDS do
        local kind = lib.KINDS[i]
        local state, reason = lib.capOf(kind)
        out[i] = { kind = kind, state = state, reason = reason }
    end
    return out
end

function lib:OnCapability(owner, fn)
    lib.capCb[owner] = fn
end

-- After anything that can change a kind's capability: tell the callbacks what changed, then re-sync every source.
function lib.capChanged()
    for kind in pairs(lib.kinds) do
        local state, reason = lib.capOf(kind)
        local key = state .. ":" .. (reason or "")
        if lib.capSeen[kind] ~= key then
            lib.capSeen[kind] = key
            for _, fn in pairs(lib.capCb) do
                local ok, err = pcall(fn, kind, state, reason)
                if not ok then
                    lib.report(err)
                end
            end
        end
    end
    for i = 1, #lib.sources do
        lib.sync(lib.sources[i])
    end
end

-- The kill switch for this session. On again: pending until a fresh self-test passes. Already on: nothing (a failed
-- verdict stands; lib:SelfTest() runs again).
function lib:SetEnabled(on)
    if on then
        if not lib.disabled then
            return
        end
        lib.disabled, lib.stVerdict, lib.stLines = nil, nil, nil
        lib.capChanged()
        lib:SelfTest()
    elseif not lib.disabled then
        lib.disabled = true
        lib.capChanged()
    end
end

-- Watch -------------------------------------------------------------------------------------------------------------

function lib:Watch(owner, spec, sink)
    local E = lib.ERR
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
    if not lib.KNOWN[kind] then
        return nil, E.KIND_INVALID
    end
    local h = setmetatable({ owner = owner, kind = kind, sink = sink, q = lib.UNKNOWN }, lib.handleMeta)
    local k = lib.kinds[kind]
    if k then
        local err = k.validate(spec, h)
        if err then
            return nil, err
        end
    else
        h.unproven = "unproven"
    end
    h.points = h.points or lib.NOPOINTS -- a kind without points (and an unproven handle) has none
    -- a step is admitted too: beside a ring of step above 1 it adds the position set (8 bars)
    if not h.unproven and (#h.points > 0 or h.prec or h.step) then
        local err = lib.admit(h)
        if err then
            return nil, err
        end
    end
    lib.reg[#lib.reg + 1] = h
    if not h.unproven then
        lib.attach(h)
    end
    return h
end

function lib.keyOf(h)
    return h.key or h.kind .. "|" .. h.unit .. "|" .. tostring(h.power) .. "|" .. tostring(h.predicted)
end

-- References (or with d = -1 drops) a handle's points on its source.
local function refPoints(s, pts, d)
    for i = 1, #pts do
        local p = pts[i]
        s.pref[p] = (s.pref[p] or 0) + d
    end
end

-- Joins the handle to the source of its canonical key (created on first use) and references its edges and points.
function lib.attach(h)
    local key = lib.keyOf(h)
    local s = lib.srcByKey[key]
    if not s then
        s = { kind = h.kind, unit = h.unit, power = h.power, predicted = h.predicted, handles = {} }
        s.bar, s.ref, s.core, s.pbar, s.pref, s.bad = {}, {}, {}, {}, {}, 0
        s.spell, s.what, s.cdw = h.spell, h.what, h.cdw
        lib.srcByKey[key] = s
        lib.sources[#lib.sources + 1] = s
    end
    for i = 1, #h.edges do
        local e = h.edges[i]
        s.ref[e] = (s.ref[e] or 0) + 1
    end
    refPoints(s, h.points, 1)
    s.handles[#s.handles + 1] = h
    h.src = s
    lib.sync(s)
end

local function remove(list, x)
    for i = #list, 1, -1 do
        if list[i] == x then
            table.remove(list, i)
            return
        end
    end
end

function lib:ReleaseAll(owner)
    for i = #lib.reg, 1, -1 do
        local h = lib.reg[i]
        if h and h.owner == owner then
            h:Release()
        end
    end
end

-- Handles -----------------------------------------------------------------------------------------------------------

-- "live" | "priming" | "pending" | "gone" | "paused" | "suspended" | "unavailable" | "released", reason.
function lib.stateOf(h)
    if h.released then
        return "released"
    end
    if h.unproven then
        return "unavailable", h.unproven
    end
    local state, reason = lib.capOf(h.kind, h.barless)
    if state ~= "ready" then
        return state, reason
    end
    local s = h.src
    if s.cap then -- the source's own answer (the aura kind: its Cooldown Manager placement)
        return s.cap, s.why
    end
    if h.pts and not s.max then
        return "unavailable", "max-unknown"
    end
    if h.paused then
        return "paused"
    end
    if s.gone then
        return "gone"
    end
    if not lib.served(s, h) then
        return "suspended" -- the bar cap was reached, or the client refused its curves
    end
    return lib.priming(s, h) and "priming" or "live"
end

local H = lib.H

function H:Get()
    return self.lo, self.hi, self.t, self.q
end

-- "live" means a band is known: bars live but the first band not yet decoded (next frame) still read "priming".
-- Not in lib.stateOf: decode needs the bar-level "live" to compute that first band.
function H:State()
    local state, reason = lib.stateOf(self)
    if state == "live" and self.lo == nil then
        return "priming"
    end
    return state, reason
end

-- step, min, max granted: a step of any size is granted as 1 (the 1% cell), nil for edges only. A points handle
-- answers in points: 0 to the plain max (nil while unknown), its step the 1% cell in points. The top is 100 for
-- percents; for an aura, 1 (up), max (stacks; math.huge without one) or math.huge (seconds).
function H:Domain()
    if self.pts then
        local s = self.src
        local M = s and s.max
        if self.prec then
            return s and s.mode == "ring" and s.ring and s.ring.g or 1, 0, M
        end
        return self.step and M and M / 100 or nil, 0, M
    end
    return self.step, 0, self.top or 100
end

-- Swaps the handle's point thresholds in one step: true, or nil, code (the old set stays).
function H:SetPoints(points)
    local list = not self.released and self.pts and lib.pointList(points)
    if not list then
        return nil, lib.ERR.POINTS_INVALID
    end
    local s = self.src
    if s then
        local err = lib.admit(self, list)
        if err then
            return nil, err
        end
        refPoints(s, self.points, -1)
        refPoints(s, list, 1)
    end
    self.points = list
    self.single = #self.edges + #list == 1 and not self.step and not self.prec -- rests on one bar or not, anew
    if s then
        lib.sync(s)
    end
    return true
end

-- The plain value when the client gives it right now: not read in this stage.
function H:Exact()
    if self.lo == nil then
        return nil
    end
    return lib.exact(self)
end

-- Worst-case seconds from a change to its callback: a one-edge handle on an edges-only source is called in the frame of
-- the push, a handle on several edges one frame later, any handle on a position or precision source in SETTLE + 3
-- frames counted from the frame the change's first firing arrives (the push's own when the client fires at once): that
-- frame, at most SETTLE + 1 decodes without a call while firings land (bad frames, and the holds of a precision source,
-- whose every change waits for the next decode to agree; the desync rule caps them), then a call with the value or,
-- after a desync, unknown (measured 7 in the fake by a chain of split changes, and the first change's firings all late
-- stay within it: precision_spec). A precision change with every firing in one frame is called 2 frames after it. An
-- aura handle (the Cooldown Manager's own delay aside): `up` one frame later; stacks once the bar settled (SETTLE frames after the client's first push, plus
-- one); seconds refreshed as they fall through an edge prime the bar again first (HOLD + SETTLE, plus the fall's frame,
-- the push and a secret firing a frame late). Measured in the fake (aura_timing_spec): 2, 4 and 10 (11 a frame late).
function H:Latency()
    local mode = self.src and self.src.mode
    local n = mode and lib.SETTLE + 3 or self.single and 1 or 2
    if self.kind == "aura" then
        n = self.what == "up" and 2 or self.what == "stacks" and lib.SETTLE + 1 or lib.HOLD + lib.SETTLE + 3
    end
    return lib.frameSec * n
end

function H:SetSink(fn)
    if fn == nil or type(fn) == "function" then
        self.sink = fn
    end
end

function H:SetPaused(paused)
    self.paused = paused and true or nil
    if self.src and not self.released then
        lib.sync(self.src)
    end
end

-- shortcut: a bar whose last reference goes is freed at once (the design's 5 s grace is not built); add the grace if
-- consumers re-register often enough to churn bars.
function H:Release()
    if self.released then
        return
    end
    self.released = true
    self.lo, self.hi, self.q = nil, nil, lib.UNKNOWN
    remove(lib.reg, self)
    local s = self.src
    if s then
        for i = 1, #self.edges do
            local e = self.edges[i]
            s.ref[e] = s.ref[e] - 1
        end
        refPoints(s, self.points, -1)
        remove(s.handles, self)
        lib.sync(s)
    end
end
