-- LibTimeToDie.lua: the entry point. LibStub("LibTimeToDie-1.0"): seconds until a unit's health reaches 0, with a
-- range (lo, hi), from LibHiddenValues' 1% health bands. Consumers name what to track (unit tokens); the library opens
-- one LibHiddenValues health watch per token (step 1, shared by every track of it, released with the last), feeds its
-- bands to an estimator per token (Estimator.lua, the TTD lab's winner, lifted as is) and answers Get. A target change
-- starts a fresh stream (the estimator carries the last rate); a re-prime of the same unit keeps the history; gone (no
-- unit, plainly dead) clears the stream and keeps the handle. Hints (HintRate, HintBelow) are numbers only.
--
-- Upgrades: the newest minor on the client runs; Estimator.lua returns unless this copy won LibStub (lib.loading).
-- State lives on lib as plain data; scripts are one-line dispatchers through lib. The addon name and the private table
-- from `...` are never used (an embedded copy would receive its host's).
local MAJOR, MINOR = "LibTimeToDie-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return
end
lib.loading = true

local LHV_MAJOR = "LibHiddenValues-1.0"
local NEVER = 1e9 -- the estimator's end of an open-ended rate hint
lib.POLL = 0.1 -- seconds between the driver's reads of a stream
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

-- The combined hint as last pushed to every stream (rate: factor, start, end; threshold: percent, factor).
lib.cur = lib.cur or { rf = false, rs = false, re = false, xp = false, xf = false }

local function pushRate(e)
    local c = lib.cur
    if c.rf then
        e:Hint("rate", c.rf, c.rs, c.re or nil)
    else
        e:Hint("rate", nil)
    end
end

local function pushBelow(e)
    local c = lib.cur
    e:Hint("execute", c.xp and c.xf, c.xp or nil) -- a nil percent clears
end

-- Opens the LibHiddenValues watch of a stream: nil, or a code it refused with. Without the library the stream reads
-- unavailable (lhv-missing) and tries again whenever it is read.
local function attach(s)
    local lhv = LibStub(LHV_MAJOR, true)
    if not lhv then
        s.why = "lhv-missing"
        return nil
    end
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

local function open(token)
    local s = { token = token, tracks = {}, sinks = 0, e = lib.Estimator.New(), at = false, due = false, pub = false }
    s.state, s.why = "priming", nil
    pushRate(s.e)
    pushBelow(s.e)
    local code = attach(s)
    if code then
        return nil, code
    end
    lib.byToken[token] = s
    lib.streams[#lib.streams + 1] = s
    lib.wake()
    return s
end

-- A band or a hint arrived: the next read computes again, the driver reads it next frame.
function lib.touch(s)
    s.at, s.due = false, false
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

-- A band (or unknown) from LibHiddenValues. Unknown keeps the history (a re-prime of the same unit) unless the unit is
-- gone: the stream is cleared then. A target change is told by the client's event, not by LibHiddenValues.
function lib.lhvSink(lh, lo, hi, _, t)
    local s = lib.byLhv[lh]
    if not s then
        return
    end
    lib.touch(s)
    if lo == nil then
        if lh:State() == "gone" then
            s.e:Restart()
        end
        return
    end
    s.e:Band(t, lo, hi)
end

-- Brings a stream's answer up to `now` (once per frame; a band or a hint since then reads it again).
function lib.evaluate(s, now)
    if s.at == now then
        return
    end
    s.at = now
    if not s.lh and s.why == "lhv-missing" then
        attach(s)
    end
    local lh, state, why = s.lh, nil, nil
    local est, lo, hi
    if not lh then
        state, why = "unavailable", s.why
    else
        local ls, lr = lh:State()
        if ls == "live" or ls == "priming" then -- priming: a re-prime of the same unit keeps answering
            local es
            est, lo, hi, es = s.e:Get(now)
            if est then
                state, why = "live", es
            else
                state = ls == "priming" and "priming" or "unknown"
            end
        elseif ls == "pending" then
            state, why = "priming", "pending"
        elseif ls == "gone" or ls == "paused" then
            state = ls
        else -- unavailable (its reason), suspended
            state, why = "unavailable", lr or ls
        end
    end
    s.est, s.lo, s.hi, s.state, s.why = est, lo, hi, state, why
    s.pub = est and s.e.tPub or false
end

-- The driver: every stream is read every POLL seconds and in the frame after a band or a hint (the estimator keeps its
-- carried rate and its deadband from these reads; the TTD lab polled every 0.1-0.25 s); then a track's sink is called
-- when its published death time or its state changed. It unsets itself when no stream is left.
function lib.drive()
    local now = GetTime()
    local streams = lib.streams
    for i = #streams, 1, -1 do
        local s = streams[i]
        if s and (not s.due or now >= s.due) then
            s.due = now + lib.POLL
            lib.evaluate(s, now)
            local tracks = s.sinks > 0 and s.tracks or lib.NONE
            for j = #tracks, 1, -1 do
                local h = tracks[j]
                local fn = h and h.sink
                if fn then
                    local paused = h.paused
                    local state = paused and "paused" or s.state
                    local pub = not paused and s.pub
                    if state ~= h.fState or pub ~= h.fPub then
                        h.fState, h.fPub = state, pub
                        local ok, err
                        if paused then
                            ok, err = pcall(fn, h, nil, nil, nil, state)
                        else
                            ok, err = pcall(fn, h, s.est, s.lo, s.hi, state)
                        end
                        if not ok and not h.sinkErr then
                            h.sinkErr = true
                            lib.report(err)
                        end
                    end
                end
            end
        end
    end
    if #streams == 0 then
        lib.frame:SetScript("OnUpdate", nil)
    end
end

function lib.wake()
    local f = lib.frame
    if f and f:GetScript("OnUpdate") == nil then
        f:SetScript("OnUpdate", lib.onUpdate)
    end
end

-- The client's events. A target change: the target's stream starts fresh (the carried rate stays). Combat start: a
-- stream that has seen no crossing yet starts again from now, so a mob targeted at full long before the pull is not
-- anchored at the moment it was targeted (the TTD lab's note on the full anchor).
function lib.event(event)
    if event == "PLAYER_TARGET_CHANGED" then
        local s = lib.byToken.target
        if s then
            s.e:Restart()
            lib.touch(s)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        local now = GetTime()
        for i = 1, #lib.streams do
            local s = lib.streams[i]
            local e = s.e
            if e.known and e.n == 0 and not e.t0 then
                e:Restart()
                local lo, hi
                if s.lh then
                    lo, hi = s.lh:Get()
                end
                if lo then
                    e:Band(now, lo, hi)
                end
                lib.touch(s)
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
    local h = setmetatable({ owner = owner, token = token, s = s }, lib.handleMeta)
    s.tracks[#s.tracks + 1] = h
    lib.reg[#lib.reg + 1] = h
    lib.syncPause(s)
    if sink then
        h:SetSink(sink)
    end
    return h
end

function lib:ReleaseAll(owner)
    for i = #lib.reg, 1, -1 do
        local h = lib.reg[i]
        if h and h.owner == owner then
            h:Release()
        end
    end
    if owner ~= nil and (lib.rateF[owner] or lib.belowP[owner]) then
        lib.rateF[owner], lib.rateS[owner], lib.rateE[owner] = nil, nil, nil
        lib.belowP[owner], lib.belowF[owner] = nil, nil
        lib.pushHints()
    end
end

-- ok, state, reason for a token: LibHiddenValues' answer for its health kind.
function lib:IsAvailable(token)
    if type(token) ~= "string" then
        return false, "unavailable", lib.ERR.UNIT_INVALID
    end
    local lhv = LibStub(LHV_MAJOR, true)
    if not lhv then
        return false, "unavailable", "lhv-missing"
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
    local s = self.s
    lib.evaluate(s, GetTime())
    return s.est, s.lo, s.hi, s.state, s.why
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
    s.due = false -- a new sink hears the current answer next frame
    return true
end

function H:SetPaused(paused)
    if self.released then
        return
    end
    self.paused = paused and true or nil
    lib.syncPause(self.s)
end

function H:Release()
    if self.released then
        return
    end
    self:SetSink(nil)
    self.released = true
    remove(lib.reg, self)
    local s = self.s
    remove(s.tracks, self)
    if #s.tracks == 0 then
        close(s)
    else
        lib.syncPause(s)
    end
end

-- Hints -------------------------------------------------------------------------------------------------------------

local function badNumber(x)
    return type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge
end

-- A time-window multiplier on the damage every stream takes: `factor` from startTime to endTime (GetTime() seconds;
-- nil: open). One per owner: a new call replaces it; to end early, call again with the same start and the real end;
-- factor nil or 1 clears it (for a wrong hint: clearing un-warps what it covered). true, or nil, code.
function lib:HintRate(owner, factor, startTime, endTime)
    local E = lib.ERR
    if type(owner) ~= "string" then
        return nil, E.OWNER_INVALID
    end
    if factor == nil or factor == 1 then
        lib.rateF[owner], lib.rateS[owner], lib.rateE[owner] = nil, nil, nil
    else
        if badNumber(factor) or factor <= 0 then
            return nil, E.FACTOR_INVALID
        end
        if badNumber(startTime) or (endTime ~= nil and (badNumber(endTime) or endTime <= startTime)) then
            return nil, E.TIME_INVALID
        end
        lib.rateF[owner], lib.rateS[owner], lib.rateE[owner] = factor, startTime, endTime or false
    end
    lib.pushHints()
    return true
end

-- A health threshold: below `pct` the damage runs `factor` times faster; factor nil: learned from the streams that
-- cross it. One per owner; pct nil clears it. true, or nil, code.
function lib:HintBelow(owner, pct, factor)
    local E = lib.ERR
    if type(owner) ~= "string" then
        return nil, E.OWNER_INVALID
    end
    if pct == nil then
        lib.belowP[owner], lib.belowF[owner] = nil, nil
    else
        if badNumber(pct) or pct <= 0 or pct > 100 then
            return nil, E.PCT_INVALID
        end
        if factor ~= nil and (badNumber(factor) or factor <= 0) then
            return nil, E.FACTOR_INVALID
        end
        lib.belowP[owner], lib.belowF[owner] = pct, factor or false
    end
    lib.pushHints()
    return true
end

-- Combines every owner's hints into the estimator's one rate and one threshold slot and pushes a part to every stream
-- only when it changed: a push replaces what the estimator learned (a threshold's factor) or dropped (a rate hint the
-- data contradicted). Rate: from the latest start, the product of the hints in force then, to the first of their ends.
-- Threshold: the highest percent, the product of the given factors (a learned one counts 1, the estimator learns on).
-- shortcut: owners' rate windows that only partly overlap lose the parts outside the overlap at the latest start, and
-- several thresholds act as one at the highest; upgrade to a list in the estimator if several owners ever need that.
function lib.pushHints()
    local S
    for _, s in pairs(lib.rateS) do
        if not S or s > S then
            S = s
        end
    end
    local rf, re = false, false
    if S then
        rf = 1
        for o, f in pairs(lib.rateF) do
            local s, e = lib.rateS[o], lib.rateE[o]
            if s <= S and (not e or e > S) then
                rf = rf * f
                if e and (not re or e < re) then
                    re = e
                end
            end
        end
        if rf == 1 then
            rf, S, re = false, nil, false
        end
    end
    local xp, xf = false, false
    for o, p in pairs(lib.belowP) do
        xp = xp and math.max(xp, p) or p
        xf = (xf or 1) * (lib.belowF[o] or 1)
    end
    local c = lib.cur
    local rateChanged = c.rf ~= rf or c.rs ~= (S or false) or c.re ~= re
    local belowChanged = c.xp ~= xp or c.xf ~= xf
    c.rf, c.rs, c.re, c.xp, c.xf = rf, S or false, re, xp, xf
    for i = 1, #lib.streams do
        local s = lib.streams[i]
        if rateChanged then
            pushRate(s.e)
        end
        if belowChanged then
            pushBelow(s.e)
        end
        lib.touch(s)
    end
end

-- Diagnostics -------------------------------------------------------------------------------------------------------

-- One row per tracked token, in creation order (a fresh array: call it from a command, not every frame): token,
-- tracks, sinks, state, reason, est, lo, hi, crossings (kept for the fit), drops (hints the data contradicted), the
-- rate hint in force (rateFactor 1 when none; rateStart, rateEnd nil when open) and the threshold (executePct nil when
-- none; executeFactor with the stream's own measurement folded in).
function lib:GetStreams()
    local out, now = {}, GetTime()
    for i = 1, #lib.streams do
        local s = lib.streams[i]
        lib.evaluate(s, now)
        local e = s.e
        local rate = e.hf ~= 1
        out[i] = {
            token = s.token,
            tracks = #s.tracks,
            sinks = s.sinks,
            state = s.state,
            reason = s.why,
            est = s.est,
            lo = s.lo,
            hi = s.hi,
            crossings = e.n,
            drops = e.drops,
            rateFactor = e.hf,
            rateStart = rate and e.hs or nil,
            rateEnd = rate and e.he < NEVER and e.he or nil,
            executePct = e.xp > 0 and e.xp or nil,
            executeFactor = e:ExecuteFactor(),
        }
    end
    return out
end
