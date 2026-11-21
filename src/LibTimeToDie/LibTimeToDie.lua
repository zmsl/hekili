-- LibTimeToDie.lua: the entry point. LibStub("LibTimeToDie-1.0"): seconds until a unit's health reaches 0, with a
-- range (lo, hi), from LibHiddenValues' 1% health bands. Consumers name what to track (unit tokens); the library opens
-- one LibHiddenValues health watch per token (step 1, shared by every track of it, released with the last) and feeds
-- its bands to one estimator per owner of that token (Estimator.lua, the TTD lab's winner, lifted as is): each owner's
-- estimate sees the shared crossings and that owner's hints only. A target change starts a fresh stream (the estimator
-- carries the last rate); a re-prime of the same unit keeps the history; gone (no unit, plainly dead) clears the stream
-- and keeps the handle. Hints (HintRate, HintBelow) are numbers only and reach hostile units only.
--
-- Upgrades: the newest minor on the client runs; Estimator.lua returns unless this copy won LibStub (lib.loading).
-- State lives on lib as plain data; scripts are one-line dispatchers through lib. The addon name and the private table
-- from `...` are never used (an embedded copy would receive its host's).
local MAJOR, MINOR = "LibTimeToDie-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return
end
lib.loading = true

local LHV_MAJOR = "LibHiddenValues-1.0"
local NEVER = 1e9 -- the estimator's end of an open-ended rate hint
local IDLE = math.huge -- a stream's next driver read when only a band, a read, a hint or a capability change wakes it
lib.LHV_MIN = 5 -- the oldest LibHiddenValues minor this library runs on (below it: unavailable, lhv-old)
lib.POLL = 0.1 -- seconds between the driver's reads of a stream
lib.RETRY = 1 -- seconds between the driver's tries to open a stream's watch (no LibHiddenValues, too old, refused)
lib.NONE = lib.NONE or {} -- shared and never written

-- Error codes: every call that refuses input returns nil, code. Codes are plain strings; lib:GetMessage gives words.
lib.ERR = {
    OWNER_INVALID = "owner-invalid",
    UNIT_INVALID = "unit-invalid",
    SINK_INVALID = "sink-invalid",
    FACTOR_INVALID = "factor-invalid",
    TIME_INVALID = "time-invalid",
    PCT_INVALID = "pct-invalid",
}

-- Messages for error codes, states and reasons, per locale; enUS only for now. LibHiddenValues' reasons (passed
-- through by unavailable) use its own messages.
lib.MESSAGES = {
    enUS = {
        ["owner-invalid"] = "The owner must be a string (your addon's name).",
        ["unit-invalid"] = "The unit must be a unit token.",
        ["sink-invalid"] = "The sink must be a function or nil.",
        ["factor-invalid"] = "The factor must be a number above 0.",
        ["time-invalid"] = "The start must be a GetTime() number, and the end (when given) a later one.",
        ["pct-invalid"] = "The health percent must be a number above 0 and at most 100.",
        live = "Live: an estimate is known.",
        priming = "Priming: the health is not read yet.",
        gone = "Gone: the unit is not there or is dead.",
        unknown = "Unknown: the health is read, but has not fallen enough to estimate yet.",
        unavailable = "Unavailable.",
        paused = "Paused by its owner.",
        released = "Released.",
        ["lhv-missing"] = "LibHiddenValues is not loaded.",
        ["lhv-old"] = "The LibHiddenValues loaded is older than this library needs.",
        fit = "Estimated from the recent fall of the health.",
        seed = "Estimated from the fall since the unit was first seen (little data yet).",
        prior = "Estimated from the rate carried over from before a change of unit, a heal or a stall.",
        stalled = "The health stopped falling: the estimate holds.",
        pending = "Waiting for LibHiddenValues' self-test.",
        suspended = "LibHiddenValues had no bar free for it.",
    },
}

-- The message for a code, a state or a reason in locale (default: the client's), nil when there is none for that
-- locale. A reason LibHiddenValues gave is answered by its GetMessage.
function lib:GetMessage(code, locale)
    locale = locale or (GetLocale and GetLocale()) or "enUS"
    local t = lib.MESSAGES[locale]
    local msg = t and code ~= nil and t[code] or nil
    if msg == nil and t then
        local lhv = LibStub(LHV_MAJOR, true)
        msg = lhv and lhv:GetMessage(code, locale)
    end
    return msg
end

function lib:GetVersion()
    return MAJOR, MINOR
end

-- Passes an error to the client's handler.
function lib.report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(err)
    end
end

lib.streams = lib.streams or {} -- one per tracked token, in creation order
lib.byToken = lib.byToken or {}
lib.byLhv = lib.byLhv or {} -- LibHiddenValues handle -> stream
lib.reg = lib.reg or {} -- every track not released
lib.rateF, lib.rateS, lib.rateE = lib.rateF or {}, lib.rateS or {}, lib.rateE or {} -- per owner; end false: open
lib.belowP, lib.belowF = lib.belowP or {}, lib.belowF or {} -- per owner; factor false: learned
lib.H = lib.H or {}
lib.handleMeta = lib.handleMeta or { __index = lib.H }
lib.spec = lib.spec or { kind = "health", unit = false, step = 1 } -- the watch spec (LibHiddenValues copies it)

-- Dispatchers: LibHiddenValues and the frame keep these references; a newer minor replaces what they call.
lib.lhvDispatch = lib.lhvDispatch or function(...)
    return lib.lhvSink(...)
end
lib.capDispatch = lib.capDispatch or function(...)
    return lib.onCapability(...)
end
lib.onUpdate = lib.onUpdate
    or function()
        local ok, err = pcall(lib.drive)
        if not ok then
            lib.report(err)
        end
    end
lib.onEvent = lib.onEvent
    or function(_, event)
        local ok, err = pcall(lib.event, event)
        if not ok then
            lib.report(err)
        end
    end

if CreateFrame and not lib.frame then
    lib.frame = CreateFrame("Frame") -- shows nothing: the client events and the driver (OnUpdate)
end
if lib.frame then
    lib.frame:SetScript("OnEvent", lib.onEvent)
    lib.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    lib.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

-- Streams -------------------------------------------------------------------------------------------------------------
-- A stream (s) is one token: its LibHiddenValues watch, its tracks, whether it is hostile. Each owner tracking the token
-- has a record (o) on it: its estimator and its answer; an owner's several tracks of one token share the record.

-- Hints are for damage dealt, so they reach hostile units only: never the player, never a friendly target. A secret
-- answer counts as hostile (under the dungeon restrictions a target in combat is nearly always an enemy); the secret
-- only goes to issecretvalue.
function lib.hostile(token)
    if token == "player" then
        return false
    end
    local v = UnitCanAttack("player", token)
    return (issecretvalue and issecretvalue(v)) or v == true
end

-- Whether the unit is there. A secret answer counts as there (as LibHiddenValues' lib.present); the value is never
-- tested as a boolean (a boolean test on a secret raises on this client).
function lib.present(token)
    local v = UnitExists(token)
    return (issecretvalue and issecretvalue(v)) or v == true
end

local function pushRate(s, o)
    local owner = o.owner
    local f = s.hostile and lib.rateF[owner]
    if f then
        o.e:Hint("rate", f, lib.rateS[owner], lib.rateE[owner] or nil)
    else
        o.e:Hint("rate", nil)
    end
end

local function pushBelow(s, o)
    local owner = o.owner
    local p = s.hostile and lib.belowP[owner]
    o.e:Hint("execute", p and (lib.belowF[owner] or 1), p or nil) -- a nil percent clears; learned: from 1
end

-- Opens the LibHiddenValues watch of a stream: nil, or a code it refused with. Without the library (or with one older
-- than LHV_MIN), or refused, the stream reads unavailable (lhv-missing, lhv-old, the code) and tries again at most every
-- RETRY seconds, on a read or the driver's (a refused Watch allocates: never every frame).
local function attach(s)
    s.retryAt = GetTime() + lib.RETRY
    local lhv, minor = LibStub(LHV_MAJOR, true)
    if not lhv then
        s.why = "lhv-missing"
        return nil
    end
    if minor < lib.LHV_MIN then
        s.why = "lhv-old"
        return nil
    end
    lhv:OnCapability(MAJOR, lib.capDispatch)
    lib.spec.unit = s.token
    local lh, code = lhv:Watch(MAJOR, lib.spec, lib.lhvDispatch)
    if not lh then
        s.why = code
        return code
    end
    s.lh, s.why = lh, nil
    lib.byLhv[lh] = s
    lib.syncPause(s)
end

-- The watch is paused while every track of its token is.
function lib.syncPause(s)
    local all = #s.tracks > 0
    for i = 1, #s.tracks do
        if not s.tracks[i].paused then
            all = false
            break
        end
    end
    if s.lh then
        s.lh:SetPaused(all)
    end
end

-- A band, a hint or a capability change arrived: the next read computes again, the driver reads it next frame.
function lib.touch(s)
    s.at, s.due = false, false
    lib.wake()
end

local function open(token)
    local s = { token = token, tracks = {}, sinks = 0, owners = {}, byOwner = {}, at = false, due = false, retryAt = 0 }
    s.state, s.why, s.hostile = "priming", nil, lib.hostile(token)
    local code = attach(s)
    if code then
        return nil, code
    end
    lib.byToken[token] = s
    lib.streams[#lib.streams + 1] = s
    lib.wake()
    return s
end

-- An owner's record on a stream. On a watch that already has a band it starts from that band (now), as a new watch
-- would; the history before it is not replayed.
local function addOwner(s, owner)
    local o = { owner = owner, e = lib.Estimator.New(), refs = 0, state = "priming", pub = false }
    pushRate(s, o)
    pushBelow(s, o)
    if s.lh then
        local lo, hi = s.lh:Get()
        if lo then
            o.e:Band(GetTime(), lo, hi)
        end
    end
    s.owners[#s.owners + 1] = o
    s.byOwner[owner] = o
    lib.touch(s)
    return o
end

local function remove(list, x)
    for i = #list, 1, -1 do
        if list[i] == x then
            table.remove(list, i)
            return
        end
    end
end

local function close(s)
    if s.lh then
        lib.byLhv[s.lh] = nil
        s.lh:Release()
        s.lh = nil
    end
    lib.byToken[s.token] = nil
    remove(lib.streams, s)
end

-- A band (or unknown) from LibHiddenValues, to every owner's estimator. Unknown keeps the history (a re-prime of the
-- same unit) unless the unit is gone: the stream is cleared then. A target change is told by the client's event.
function lib.lhvSink(lh, lo, hi, _, t)
    local s = lib.byLhv[lh]
    if not s then
        return
    end
    lib.touch(s)
    local owners = s.owners
    if lo == nil then
        if lh:State() == "gone" then
            for i = 1, #owners do
                owners[i].e:Restart()
            end
        end
        return
    end
    for i = 1, #owners do
        owners[i].e:Band(t, lo, hi)
    end
end

-- LibHiddenValues' capability changed (its callbacks run before it re-syncs its watches): every stream is read again.
function lib.onCapability(kind)
    if kind == "health" then
        for i = 1, #lib.streams do
            lib.touch(lib.streams[i])
        end
    end
end

-- Brings a stream's answers up to `now` (once per frame; a band or a hint since then reads it again).
function lib.evaluate(s, now)
    if s.at == now then
        return
    end
    s.at = now
    if not s.lh and now >= (s.retryAt or 0) then
        attach(s)
    end
    local lh, state, why, ls, lr = s.lh, nil, nil, nil, nil
    if not lh then
        state, why = "unavailable", s.why
    else
        ls, lr = lh:State()
        if ls == "live" or ls == "priming" then -- priming: a re-prime of the same unit keeps answering
            state = ls
        elseif ls == "pending" then
            state, why = "priming", "pending"
        elseif ls == "gone" or ls == "paused" then
            state = ls
        else -- unavailable (its reason), suspended
            state, why = "unavailable", lr or ls
        end
    end
    s.state = state
    local owners = s.owners
    for i = 1, #owners do
        local o = owners[i]
        local est, lo, hi, ostate, owhy = nil, nil, nil, state, why
        if ls == "live" or ls == "priming" then
            local es
            est, lo, hi, es = o.e:Get(now)
            if est then
                ostate, owhy = "live", es
            elseif ls == "live" then
                ostate = "unknown"
            end
        end
        o.est, o.lo, o.hi, o.state, o.why = est, lo, hi, ostate, owhy
        o.pub = est and o.e.tPub or false
    end
end

-- The driver: every stream is read every POLL seconds and in the frame after a band or a hint (the estimator keeps its
-- carried rate and its deadband from these reads; the TTD lab polled every 0.1-0.25 s); then a track's sink is called
-- when its owner's published death time or its state changed. A stream LibHiddenValues reports unavailable is not read
-- again until a band, a read, a hint or a capability change; one without a watch tries every RETRY seconds. The driver
-- unsets itself when no stream wants a read.
function lib.drive()
    local now = GetTime()
    local streams = lib.streams
    local busy = false
    for i = #streams, 1, -1 do
        local s = streams[i]
        if s and (not s.due or now >= s.due) then
            lib.evaluate(s, now)
            if not s.lh then
                s.due = now + lib.RETRY
            elseif s.state == "unavailable" then
                s.due = IDLE
            else
                s.due = now + lib.POLL
            end
            local tracks = s.sinks > 0 and s.tracks or lib.NONE
            for j = #tracks, 1, -1 do
                local h = tracks[j]
                local fn = h and h.sink
                if fn then
                    local o = h.o
                    local paused = h.paused
                    local state = paused and "paused" or o.state
                    local pub = not paused and o.pub
                    if state ~= h.fState or pub ~= h.fPub then
                        h.fState, h.fPub = state, pub
                        local ok, err
                        if paused then
                            ok, err = pcall(fn, h, nil, nil, nil, state)
                        else
                            ok, err = pcall(fn, h, o.est, o.lo, o.hi, state)
                        end
                        if not ok and not h.sinkErr then
                            h.sinkErr = true
                            lib.report(err)
                        end
                    end
                end
            end
        end
        if s and s.due ~= IDLE then
            busy = true
        end
    end
    if not busy then
        lib.frame:SetScript("OnUpdate", nil)
    end
end

function lib.wake()
    local f = lib.frame
    if f and f:GetScript("OnUpdate") == nil then
        f:SetScript("OnUpdate", lib.onUpdate)
    end
end

-- Hints on (hostile) or off (friendly) for an owner's record after a flip. A learned threshold factor is kept across a
-- friendly spell while the owner's threshold stays the same.
-- shortcut: the flip back re-pushes the owner's rate hint, reviving one the estimator had dropped as contradicted;
-- keep a per-record dropped flag if that ever matters.
local function flip(s, o)
    local e, owner = o.e, o.owner
    if not s.hostile then
        o.xf, o.xp, o.xg = e.xf, lib.belowP[owner], lib.belowF[owner]
    end
    pushRate(s, o)
    pushBelow(s, o)
    if s.hostile and o.xp and o.xp == lib.belowP[owner] and o.xg == lib.belowF[owner] then
        e.xf = o.xf
    end
end

-- The client's events. A target change: the target's streams start fresh (the carried rate stays) and the hints follow
-- its hostility; a gap between targets (no unit) is no flip. Combat start: an estimator that has seen no crossing yet
-- starts again from now, so a mob targeted at full long before the pull is not anchored at the moment it was targeted
-- (the TTD lab's note on the full anchor).
function lib.event(event)
    if event == "PLAYER_TARGET_CHANGED" then
        local s = lib.byToken.target
        if s then
            local owners = s.owners
            for i = 1, #owners do
                owners[i].e:Restart()
            end
            if lib.present("target") then
                local hostile = lib.hostile("target")
                if hostile ~= s.hostile then
                    s.hostile = hostile
                    for i = 1, #owners do
                        flip(s, owners[i])
                    end
                end
            end
            lib.touch(s)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        local now = GetTime()
        for i = 1, #lib.streams do
            local s = lib.streams[i]
            local lo, hi
            if s.lh then
                lo, hi = s.lh:Get()
            end
            for j = 1, #s.owners do
                local e = s.owners[j].e
                if e.known and e.n == 0 and not e.t0 then
                    e:Restart()
                    if lo then
                        e:Band(now, lo, hi)
                    end
                    lib.touch(s)
                end
            end
        end
    end
end

-- Tracks ------------------------------------------------------------------------------------------------------------

function lib:Track(owner, token, sink)
    local E = lib.ERR
    if type(owner) ~= "string" then
        return nil, E.OWNER_INVALID
    end
    if type(token) ~= "string" or not token:match("^%a%w*$") then
        return nil, E.UNIT_INVALID
    end
    if sink ~= nil and type(sink) ~= "function" then
        return nil, E.SINK_INVALID
    end
    local s = lib.byToken[token]
    if not s then
        local code
        s, code = open(token)
        if not s then
            return nil, code
        end
    end
    local o = s.byOwner[owner] or addOwner(s, owner)
    local h = setmetatable({ owner = owner, token = token, s = s, o = o }, lib.handleMeta)
    o.refs = o.refs + 1
    s.tracks[#s.tracks + 1] = h
    lib.reg[#lib.reg + 1] = h
    lib.syncPause(s)
    if sink then
        h:SetSink(sink)
    end
    return h
end

-- Every track and hint of the owner.
function lib:ReleaseAll(owner)
    for i = #lib.reg, 1, -1 do
        local h = lib.reg[i]
        if h and h.owner == owner then
            h:Release()
        end
    end
    if owner ~= nil then -- its records went with its tracks: nothing to push
        lib.rateF[owner], lib.rateS[owner], lib.rateE[owner] = nil, nil, nil
        lib.belowP[owner], lib.belowF[owner] = nil, nil
    end
end

-- ok, state, reason for a token: LibHiddenValues' answer for its health kind.
function lib:IsAvailable(token)
    if type(token) ~= "string" then
        return false, "unavailable", lib.ERR.UNIT_INVALID
    end
    local lhv, minor = LibStub(LHV_MAJOR, true)
    if not lhv then
        return false, "unavailable", "lhv-missing"
    end
    if minor < lib.LHV_MIN then
        return false, "unavailable", "lhv-old"
    end
    return lhv:IsAvailable("health", token)
end

local H = lib.H

-- est, lo, hi (seconds from now; nil unless live), state, reason.
function H:Get()
    if self.released then
        return nil, nil, nil, "released"
    end
    if self.paused then
        return nil, nil, nil, "paused"
    end
    local o = self.o
    lib.evaluate(self.s, GetTime())
    return o.est, o.lo, o.hi, o.state, o.why
end

function H:State()
    local _, _, _, state, why = self:Get()
    return state, why
end

-- true, or nil, code.
function H:SetSink(fn)
    if fn ~= nil and type(fn) ~= "function" then
        return nil, lib.ERR.SINK_INVALID
    end
    if self.released then
        return true
    end
    local s = self.s
    s.sinks = s.sinks + (fn and 1 or 0) - (self.sink and 1 or 0)
    self.sink, self.fState, self.fPub = fn, nil, nil
    lib.touch(s) -- a new sink hears the current answer next frame
    return true
end

function H:SetPaused(paused)
    if self.released then
        return
    end
    self.paused = paused and true or nil
    lib.syncPause(self.s)
    lib.touch(self.s)
end

function H:Release()
    if self.released then
        return
    end
    self:SetSink(nil)
    self.released = true
    remove(lib.reg, self)
    local s, o = self.s, self.o
    remove(s.tracks, self)
    o.refs = o.refs - 1
    if o.refs == 0 then
        remove(s.owners, o)
        s.byOwner[o.owner] = nil
    end
    if #s.tracks == 0 then
        close(s)
    else
        lib.syncPause(s)
    end
end

-- Hints -------------------------------------------------------------------------------------------------------------
-- Private to the owner: they reach that owner's estimators of hostile units only. An unchanged call pushes nothing, so
-- what an estimator learned (a threshold's factor) or dropped (a contradicted rate hint) is kept.

local function badNumber(x)
    return type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge
end

local function pushOwner(owner, push)
    for i = 1, #lib.streams do
        local s = lib.streams[i]
        local o = s.byOwner[owner]
        if o then
            push(s, o)
            lib.touch(s)
        end
    end
end

-- A time-window multiplier on the damage the owner's hostile units take: `factor` from startTime to endTime (GetTime()
-- seconds; nil: open). One per owner: a new call replaces it; to end early, call again with the same start and the real
-- end; factor nil or 1 clears it (for a wrong hint: clearing un-warps what it covered). true, or nil, code.
-- shortcut: one rate slot per owner, so an owner's own overlapping windows (a second call before the first ends)
-- replace each other; combine them in the caller (one window at the product) if that ever matters.
function lib:HintRate(owner, factor, startTime, endTime)
    local E = lib.ERR
    if type(owner) ~= "string" then
        return nil, E.OWNER_INVALID
    end
    if factor == nil or factor == 1 then
        if lib.rateF[owner] == nil then
            return true
        end
        lib.rateF[owner], lib.rateS[owner], lib.rateE[owner] = nil, nil, nil
    else
        if badNumber(factor) or factor <= 0 then
            return nil, E.FACTOR_INVALID
        end
        if badNumber(startTime) or (endTime ~= nil and (badNumber(endTime) or endTime <= startTime)) then
            return nil, E.TIME_INVALID
        end
        endTime = endTime or false
        if lib.rateF[owner] == factor and lib.rateS[owner] == startTime and lib.rateE[owner] == endTime then
            return true
        end
        lib.rateF[owner], lib.rateS[owner], lib.rateE[owner] = factor, startTime, endTime
    end
    pushOwner(owner, pushRate)
    return true
end

-- A health threshold: below `pct` the damage runs `factor` times faster; factor nil: learned from the owner's units
-- that cross it. One per owner; pct nil clears it. true, or nil, code.
function lib:HintBelow(owner, pct, factor)
    local E = lib.ERR
    if type(owner) ~= "string" then
        return nil, E.OWNER_INVALID
    end
    if pct == nil then
        if lib.belowP[owner] == nil then
            return true
        end
        lib.belowP[owner], lib.belowF[owner] = nil, nil
    else
        if badNumber(pct) or pct <= 0 or pct > 100 then
            return nil, E.PCT_INVALID
        end
        if factor ~= nil and (badNumber(factor) or factor <= 0) then
            return nil, E.FACTOR_INVALID
        end
        factor = factor or false
        if lib.belowP[owner] == pct and lib.belowF[owner] == factor then
            return true
        end
        lib.belowP[owner], lib.belowF[owner] = pct, factor
    end
    pushOwner(owner, pushBelow)
    return true
end

-- Diagnostics -------------------------------------------------------------------------------------------------------

-- One row per tracked token and owner, in creation order (a fresh array: call it from a command, not every frame):
-- token, owner, tracks and sinks (the owner's on that token), state, reason, est, lo, hi, crossings (kept for the
-- fit), drops (hints the data contradicted), the rate hint in force (rateFactor 1 when none; rateStart, rateEnd nil
-- when open) and the threshold (executePct nil when none; executeFactor with the stream's own measurement folded in).
function lib:GetStreams()
    local out, now = {}, GetTime()
    for i = 1, #lib.streams do
        local s = lib.streams[i]
        lib.evaluate(s, now)
        for j = 1, #s.owners do
            local o = s.owners[j]
            local e = o.e
            local sinks = 0
            for k = 1, #s.tracks do
                local h = s.tracks[k]
                if h.o == o and h.sink then
                    sinks = sinks + 1
                end
            end
            local rate = e.hf ~= 1
            out[#out + 1] = {
                token = s.token,
                owner = o.owner,
                tracks = o.refs,
                sinks = sinks,
                state = o.state,
                reason = o.why,
                est = o.est,
                lo = o.lo,
                hi = o.hi,
                crossings = e.n,
                drops = e.drops,
                rateFactor = e.hf,
                rateStart = rate and e.hs or nil,
                rateEnd = rate and e.he < NEVER and e.he or nil,
                executePct = e.xp > 0 and e.xp or nil,
                executeFactor = e:ExecuteFactor(),
            }
        end
    end
    return out
end
