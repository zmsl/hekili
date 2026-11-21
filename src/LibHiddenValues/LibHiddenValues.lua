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
local MAJOR, MINOR = "LibHiddenValues-1.0", 2
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
}

-- Messages for error codes, handle states and capability reasons, per locale; enUS only for now.
lib.MESSAGES = {
    enUS = {
        ["owner-invalid"] = "The owner must be a string (your addon's name).",
        ["spec-invalid"] = "The spec must be a table.",
        ["sink-invalid"] = "The sink must be a function or nil.",
        ["kind-invalid"] = "Unknown kind.",
        ["unit-invalid"] = "The unit must be a unit token.",
        ["edges-invalid"] = "The edges must be a list of numbers.",
        ["edges-out-of-range"] = "Every edge must be above 0.05 and at most 100 (percent).",
        ["edges-required"] = "The spec needs edges, a step, points or a precision.",
        ["step-invalid"] = "The step must be a positive number.",
        ["power-required"] = "A power watch needs its power type (an Enum.PowerType number).",
        ["power-invalid"] = "The power type must be an Enum.PowerType number.",
        ["points-invalid"] = "The points must be a list of whole numbers of 1 or more, on a points handle.",
        ["edge-limit"] = "Too many point thresholds: over the cap per value or in total (nothing was granted).",
        ["pool-limit"] = "Not enough bars left in the pool (nothing was granted).",
        ["max-unknown"] = "The maximum is not known (never read as a plain number).",
        live = "Live: a band is known.",
        priming = "Priming: the band is not known yet.",
        pending = "Pending: the self-test has not passed yet.",
        gone = "Gone: the unit is not there or is dead.",
        paused = "Paused by its owner.",
        suspended = "Suspended: no bar was free for it.",
        unavailable = "Unavailable.",
        released = "Released.",
        ready = "Ready.",
        api = "The client lacks an API this needs.",
        selftest = "The self-test failed.",
        error = "Switched off after an error.",
        off = "Switched off for this session.",
        unproven = "Not proven on this client yet.",
        ["unknown-kind"] = "Unknown kind.",
    },
}

-- The message for an error code, a state or a reason in locale (default: the client's), nil when the library has no
-- text for that locale or code yet: map the code yourself then.
function lib:GetMessage(code, locale)
    local t = lib.MESSAGES[locale or (GetLocale and GetLocale()) or "enUS"]
    return t and code ~= nil and t[code] or nil
end

-- Every kind name of the major's contract; only those with a file in Kinds/ are built (lib.kinds). The aura kind stays
-- unproven for good: the client's aura container only takes widgets owned by its forbidden aura button.
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

-- state "ready" | "pending" | "unavailable", reason (nil when not unavailable).
function lib.capOf(kind)
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
    if lib.stVerdict == false then
        return "unavailable", "selftest"
    end
    if lib.stVerdict == nil then
        return "pending"
    end
    return "ready"
end

function lib:IsAvailable(kind, unit)
    local state, reason = lib.capOf(kind)
    if state ~= "unavailable" and unit ~= nil and not lib.kinds[kind].units[unit] then
        return false, "unavailable", "unproven"
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
    if not h.unproven and #h.points > 0 then
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
    return h.kind .. "|" .. h.unit .. "|" .. tostring(h.power) .. "|" .. tostring(h.predicted)
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
    local state, reason = lib.capOf(h.kind)
    if state ~= "ready" then
        return state, reason
    end
    local s = h.src
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
        return "suspended" -- the bar cap was reached
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
-- answers in points: 0 to the plain max (nil while unknown), its step the 1% cell in points.
function H:Domain()
    if self.pts then
        local M = self.src and self.src.max
        return self.step and M and M / 100 or nil, 0, M
    end
    return self.step, 0, 100
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
    if s then
        lib.sync(s)
    end
    return true
end

-- The plain value when the client gives it right now: not read in this stage.
function H:Exact()
    return nil
end

-- Worst-case seconds from a change to its callback: a one-edge handle on an edges-only source is called in the frame of
-- the push, any other handle (several edges, a position) one frame later.
function H:Latency()
    return lib.frameSec * ((self.single and not (self.src and self.src.mode)) and 1 or 2)
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
