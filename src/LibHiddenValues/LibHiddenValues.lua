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
    local why = k.why and k.why()
    if why then
        return "unavailable", why
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
    local state, reason = lib.capOf(kind)
    local spec
    if type(unit) == "table" then
        spec, unit = unit, unit.unit
    end
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

local function badSpec(msg)
    return nil, "bad-spec: " .. msg
end

function lib:Watch(owner, spec, sink)
    if type(owner) ~= "string" then
        return badSpec("owner must be a string")
    end
    if type(spec) ~= "table" then
        return badSpec("spec must be a table")
    end
    if sink ~= nil and type(sink) ~= "function" then
        return badSpec("sink must be a function or nil")
    end
    local kind = spec.kind
    if not lib.KNOWN[kind] then
        return badSpec("unknown kind " .. tostring(kind))
    end
    local h = setmetatable({ owner = owner, kind = kind, sink = sink, q = lib.UNKNOWN }, lib.handleMeta)
    local k = lib.kinds[kind]
    if k then
        local err = k.validate(spec, h)
        if err then
            return badSpec(err)
        end
    else
        h.unproven = "unproven"
    end
    lib.reg[#lib.reg + 1] = h
    if not h.unproven then
        lib.attach(h)
    end
    return h
end

-- Joins the handle to the source of its canonical key (created on first use) and references its edges.
function lib.attach(h)
    local key = h.key or (h.kind .. "|" .. h.unit .. "|" .. tostring(h.power) .. "|" .. tostring(h.predicted))
    local s = lib.srcByKey[key]
    if not s then
        s = { kind = h.kind, unit = h.unit, power = h.power, predicted = h.predicted, bar = {}, ref = {}, handles = {} }
        s.spell, s.what = h.spell, h.what
        lib.srcByKey[key] = s
        lib.sources[#lib.sources + 1] = s
    end
    for i = 1, #h.edges do
        local e = h.edges[i]
        s.ref[e] = (s.ref[e] or 0) + 1
    end
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
    if s.cap then -- the source's own answer (the aura kind: its Cooldown Manager placement)
        return s.cap, s.why
    end
    if h.paused then
        return "paused"
    end
    if s.gone then
        return "gone"
    end
    local prime, priming = lib.barPrime, false
    for k = 1, #h.edges do
        local i = s.bar[h.edges[k]]
        if not i then
            return "suspended" -- the bar cap was reached
        end
        priming = priming or prime[i] > 0
    end
    return priming and "priming" or "live"
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

-- step, min, max granted. Position (step) is a later stage: only the edges are served, so the step is nil. The top is
-- 100 for percents; for an aura, 1 (up), max (stacks; math.huge without one) or math.huge (seconds).
function H:Domain()
    return nil, 0, self.top or 100
end

-- The plain value when the client gives it right now: not read in this stage.
function H:Exact()
    return nil
end

-- Worst-case seconds from a change to its callback: a one-edge handle is called in the frame of the push, a handle on
-- several edges one frame later; an aura handle one frame later always (plus the Cooldown Manager's own delay).
function H:Latency()
    return lib.frameSec * ((self.kind ~= "aura" and self.edges and #self.edges == 1) and 1 or 2)
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
        remove(s.handles, self)
        lib.sync(s)
    end
end
