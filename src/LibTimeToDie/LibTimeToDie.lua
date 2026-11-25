-- LibTimeToDie.lua: the entry point. LibStub("LibTimeToDie-1.0"): seconds until a unit's health reaches 0, with a
-- range (lo, hi), from LibHiddenValues' 1% health bands. Consumers name what to track (unit tokens); the library opens
-- one LibHiddenValues health watch per token (step 1, shared by every track of it, released with the last) and feeds
-- its bands to one estimator per owner of that token (Estimator.lua, the TTD lab's winner): each owner's estimate
-- sees the shared crossings and that owner's hints only. A target change starts a fresh stream (the last rate may only
-- lengthen its first answers); a re-prime of the same unit keeps the history; gone (no unit, plainly dead) clears the
-- stream and keeps the handle. Hints (HintRate, HintBelow) are numbers only and reach hostile units only.
-- Minor 5, lives: the owners' records of one mob (a life, with an id) move with it between the target and its
-- nameplate. Switching away hands the old target's life to its plate (a 5% watch: a lazy stream, no tracks); switching
-- back takes it again, so the estimate resumes at once. A life moves between tokens only on a plain UnitIsUnit true.
--
-- Upgrades: the newest minor on the client runs; Estimator.lua returns unless this copy won LibStub (lib.loading).
-- State lives on lib as plain data; scripts are one-line dispatchers through lib. The addon name and the private table
-- from `...` are never used (an embedded copy would receive its host's).
local MAJOR, MINOR = "LibTimeToDie-1.0", 5
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return
end
lib.loading = true

local LHV_MAJOR = "LibHiddenValues-1.0"
local NEVER = 1e9 -- the estimator's end of an open-ended rate hint
local IDLE = math.huge -- a stream's next driver read when only a band, a read, a hint or a capability change wakes it
lib.LHV_MIN = 10 -- the oldest LibHiddenValues minor this library runs on (below it: unavailable, lhv-old); 10: plates
lib.POLL = 0.1 -- seconds between the driver's reads of a stream
lib.RETRY = 1 -- seconds between the driver's tries to open a stream's watch (no LibHiddenValues, too old, refused)
lib.NONE = lib.NONE or {} -- shared and never written
lib.RECENT = 4 -- lazy plate lives (past targets) kept at most; the oldest goes first
lib.WIDEN = 1.1 -- a plate-fed (5%) range, both ends (the plates lab: about the 1% coverage again)
lib.VETO = 3 -- a new feeder's first band this far above the life's last (its lo over the last hi): a new life

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
        untracked = "Untracked: this owner has no estimate on that unit token now.",
        ["lhv-missing"] = "LibHiddenValues is not loaded.",
        ["lhv-old"] = "The LibHiddenValues loaded is older than this library needs.",
        fit = "Estimated from the recent fall of the health.",
        seed = "Estimated from the fall since the unit was first seen (little data yet).",
        prior = "Estimated from the rate from before a heal or a stall.",
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
lib.plates = lib.plates or {} -- [token] = true while a nameplate token is shown (ADDED to REMOVED)
lib.recent = lib.recent or {} -- plate streams holding a past target's life, newest last
lib.noRecent = lib.noRecent or {} -- [owner] = true: opted out (SetRecent)
lib.lastId = lib.lastId or 0 -- the last life's id
lib.linkTok, lib.linkAt = lib.linkTok or false, lib.linkAt or 0 -- a plate ADDED for the target: linked at a later read

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
lib.onEvent = function(_, event, unit) -- minor 5: always this copy's (minor 4's dropped the unit)
    local ok, err = pcall(lib.event, event, unit)
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
    lib.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    lib.frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    lib.frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
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
    lib.spec.unit, lib.spec.step = s.token, s.step
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

-- Lives -------------------------------------------------------------------------------------------------------------
-- A life (L) is one mob's records: { id, owners, byOwner, feeder, lo, hi }. A stream holds one life (s.owners and
-- s.byOwner are its tables); the target stream and a plate stream may hold the same one. Only the feeder's bands reach
-- its estimators (the target at 1% while it holds the life, else the plate at 5%); lo, hi: the last band it gave.

local function newLife(s)
    lib.lastId = lib.lastId + 1
    return { id = lib.lastId, owners = {}, byOwner = {}, feeder = s, lo = false, hi = false }
end

local function hold(s, L)
    s.life, s.owners, s.byOwner = L, L.owners, L.byOwner
end

-- Another stream holding s's life, or false.
local function other(L, s)
    for i = 1, #lib.streams do
        local x = lib.streams[i]
        if x ~= s and x.life == L then
            return x
        end
    end
    return false
end

-- s's first band as its life's feeder: true when it is fed. A life with no band yet takes it as any first band; else it
-- is never a crossing (a 5% cell's top read after a 1% band would be a heal, the plates lab), only the veto: its bottom
-- VETO or more above the last band's top (health never proves identity, but this one cannot be that mob's now).
local renew
local function handover(s, lo, hi)
    s.hand = false
    local L = s.life
    if not L.hi then
        return true
    end
    if lo - L.hi >= lib.VETO then
        renew(s)
        return true
    end
    L.lo, L.hi = lo, hi
    return false
end

-- s feeds its life from now: the band it holds now (a plate, not touched by the event) is the hand-over band, or the
-- next one is. Never read from LibHiddenValues here: in an event handler it may not have seen the event yet.
local function feed(s)
    s.life.feeder = s
    if s.hi then
        handover(s, s.lo, s.hi)
    else
        s.hand = true
    end
end

-- s lets go of its life; the life's other holder feeds it, or it is gone.
local function leave(s)
    local L = s.life
    if not L then
        return
    end
    s.life = false
    if L.feeder == s then
        L.feeder = other(L, s)
        if L.feeder then
            feed(L.feeder)
        end
    end
end

-- An owner's record on s's life. From a record (`from`): its copy, restarted (a new unit: the carried slope and the
-- learned factor, as minor 4's Restart). Else a new estimator that starts from the feeder's band now, when it has one
-- (the history before it is not replayed; never while a hand-over is due, the band may be another unit's).
local function addOwner(s, owner, from)
    local L, o = s.life, nil
    if from then
        o = { owner = owner, e = from.e:Clone(), state = "priming", pub = false }
        o.e:Restart()
    else
        o = { owner = owner, e = lib.Estimator.New(), state = "priming", pub = false }
        pushRate(s, o)
        pushBelow(s, o)
        local f = L.feeder
        if f and f.lh and not f.hand then
            local lo, hi = f.lh:Get()
            if lo then
                o.e:Band(GetTime(), lo, hi)
            end
        end
    end
    L.owners[#L.owners + 1] = o
    L.byOwner[owner] = o
    lib.touch(s)
    return o
end

-- s holds L; every owner tracking s has a record on it (from: the life s held before, the records to copy).
local function bind(s, L, from)
    hold(s, L)
    for i = 1, #s.tracks do
        local owner = s.tracks[i].owner
        if not L.byOwner[owner] then
            addOwner(s, owner, from and from.byOwner[owner])
        end
    end
end

-- The veto: s's life is not this unit's; s gets a new one (copies of its records, restarted).
function renew(s)
    local L = s.life
    leave(s)
    bind(s, newLife(s), L)
end

-- Whether the target is the unit on token: a plain true only (a secret is no link, and never tested as a boolean).
local function isUnit(token)
    local v = UnitIsUnit("target", token)
    return not (issecretvalue and issecretvalue(v)) and v == true
end

-- The shown plate that is the target's, or false.
function lib.findPlate()
    for token in pairs(lib.plates) do
        if isUnit(token) then
            return token
        end
    end
    return false
end

local function remove(list, x)
    for i = #list, 1, -1 do
        if list[i] == x then
            table.remove(list, i)
            return
        end
    end
end

-- An explicit plate stream joins the target's life (it is the target's plate).
local function share(p, t)
    leave(p)
    bind(p, t.life)
end

local close

-- A stream (life: a lazy one, holding that life, no tracks). The target's records its plate; an explicit plate
-- that is the target's shares the target's life.
local function open(token, life)
    local s = { token = token, tracks = {}, sinks = 0, at = false, due = false, retryAt = 0 }
    s.lo, s.hi, s.hand, s.plate, s.lazy = false, false, false, false, life and true or false
    s.step = token:match("^nameplate%d+$") and 5 or 1
    s.state, s.why, s.hostile = "priming", nil, lib.hostile(token)
    hold(s, life or newLife(s))
    local code = attach(s)
    if code then
        return nil, code
    end
    lib.byToken[token] = s
    lib.streams[#lib.streams + 1] = s
    if life then
        feed(s)
    elseif token == "target" then
        s.plate = lib.findPlate()
    elseif s.step == 5 then
        local t = lib.byToken.target
        if t and lib.plates[token] and isUnit(token) then
            t.plate = token
            share(s, t)
        end
    end
    lib.wake()
    return s
end

function close(s)
    leave(s)
    remove(lib.recent, s)
    if s.lh then
        lib.byLhv[s.lh] = nil
        s.lh:Release()
        s.lh = nil
    end
    lib.byToken[s.token] = nil
    remove(lib.streams, s)
    if s.token == "target" then -- the lazy lives were kept for it
        for i = #lib.recent, 1, -1 do
            local p = lib.recent[i]
            if p and p.lazy then
                close(p)
            end
        end
    end
end

-- The old target's life to its plate at a target change: true when the target let go of it. To a shown plate only,
-- with a band (none: dead, gone or never read), held by that plate when it is tracked; to a lazy stream when some
-- record has a crossing and some owner did not opt out, over RECENT the oldest lazy life going first (not keep, the
-- plate stream the target is taking back).
function lib.handOff(s, L, keep)
    local token = s.plate
    if not token or not lib.plates[token] or not L.hi then
        return false
    end
    local p = lib.byToken[token]
    if p then
        if p.life ~= L then
            return false
        end
        leave(s)
    else
        local cross, kept = false, false
        for i = 1, #L.owners do
            local o = L.owners[i]
            cross = cross or o.e.n > 0
            kept = kept or not lib.noRecent[o.owner]
        end
        if not (cross and kept) then
            return false
        end
        local lazy = 0
        for i = 1, #lib.recent do
            lazy = lazy + ((lib.recent[i].lazy and lib.recent[i] ~= keep) and 1 or 0)
        end
        for _ = lib.RECENT, lazy do
            for i = 1, #lib.recent do
                if lib.recent[i].lazy and lib.recent[i] ~= keep then
                    close(lib.recent[i])
                    break
                end
            end
        end
        leave(s)
        p = open(token, L)
        if not p then -- refused (no bar): the life goes, as before minor 5
            return true
        end
    end
    lib.recent[#lib.recent + 1] = p
    return true
end

-- A band (or unknown) from LibHiddenValues, to every owner's estimator of the life its stream feeds (another stream's
-- feed: kept as that stream's band only). Unknown keeps the history (a re-prime of the same unit) unless the unit is
-- gone: the life is cleared then (and never handed on). A target change is told by the client's event.
function lib.lhvSink(lh, lo, hi, _, t)
    local s = lib.byLhv[lh]
    if not s then
        return
    end
    s.lo, s.hi = lo or false, hi or false
    local L = s.life
    if L.feeder ~= s then
        return
    end
    lib.touch(s)
    if lo == nil then
        if lh:State() == "gone" then
            L.lo, L.hi = false, false
            for i = 1, #L.owners do
                L.owners[i].e:Restart()
            end
        end
        return
    end
    if s.hand and not handover(s, lo, hi) then
        return
    end
    L = s.life -- the veto's new life: this is its first band
    L.lo, L.hi = lo, hi
    local owners = L.owners
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
    local f = s.life.feeder
    if f and f ~= s then -- the feeder's watch answers for the life
        lib.evaluate(f, now)
        s.state = f.state
        return
    end
    local wide = s.step == 5 and lib.WIDEN
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
                if wide then
                    lo, hi = lo / wide, hi * wide
                end
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
    if lib.linkTok and now >= lib.linkAt then
        lib.link()
    end
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
                    local o = s.byOwner[h.owner]
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

-- A plate ADDED for the target, linked at the driver's read POLL later unless a target change came first.
function lib.link()
    local token = lib.linkTok
    lib.linkTok = false
    local t = lib.byToken.target
    if t and lib.plates[token] and isUnit(token) then
        t.plate = token
        local p = lib.byToken[token]
        if p and p.life ~= t.life then
            share(p, t)
        end
    end
end

-- A plate event's unit: a plain "nameplate1" to "nameplate40" (issecretvalue first: a secret is never matched).
local function plateToken(unit)
    if (issecretvalue and issecretvalue(unit)) or type(unit) ~= "string" or not unit:match("^nameplate%d+$") then
        return nil
    end
    return unit
end

-- A target change. The same unit again (its plate holds the target's life, or is the one recorded): nothing changes.
-- Else the old life goes to its plate (lib.handOff), and the target takes the new unit's life from its plate, or gets a
-- new one (copies of the old records, restarted: the last rate only lengthens), or restarts its own in place when it
-- kept it (no plate: as before minor 5, nothing allocated). The hints follow its hostility; a gap between targets (no
-- unit) is no flip.
local function targetChanged(s)
    s.lo, s.hi = false, false -- the old unit's band: LibHiddenValues may not have seen the event yet
    local L, token = s.life, lib.findPlate()
    local p = token and lib.byToken[token]
    if token and (token == s.plate or (p and p.life == L)) then
        s.plate = token
        lib.touch(s)
        return
    end
    local moved = lib.handOff(s, L, p)
    s.plate = token
    local hostile = s.hostile
    if lib.present("target") then
        hostile = lib.hostile("target")
    end
    local flipped = hostile ~= s.hostile
    s.hostile = hostile
    local T = p and p.life
    if T and T ~= L and T.hi then -- back to a mob whose plate holds its life: it resumes now
        leave(s)
        hold(s, T)
        T.feeder, s.hand = s, true
        bind(s, T, L)
        if p.lazy then
            close(p)
        else
            remove(lib.recent, p)
        end
        for i = 1, #T.owners do
            local o = T.owners[i]
            local owner, from = o.owner, L.byOwner[o.owner]
            pushRate(s, o)
            pushBelow(s, o)
            if from and lib.belowP[owner] and not lib.belowF[owner] then -- learned: the newest learning carries
                o.e.xf = from.e:ExecuteFactor()
            end
        end
    else
        if moved or other(L, s) then
            leave(s)
            bind(s, newLife(s), L)
        else
            lib.lastId = lib.lastId + 1
            L.id, L.lo, L.hi = lib.lastId, false, false
            for i = 1, #L.owners do
                L.owners[i].e:Restart()
            end
        end
        if flipped then
            for i = 1, #s.owners do
                flip(s, s.owners[i])
            end
        end
    end
    if moved and L.feeder and L.feeder.lazy then -- an opted-out owner's record does not move
        for i = #L.owners, 1, -1 do
            local o = L.owners[i]
            if lib.noRecent[o.owner] then
                table.remove(L.owners, i)
                L.byOwner[o.owner] = nil
            end
        end
    end
    lib.touch(s)
end

-- The client's events. Combat start: an estimator with no crossing yet starts again from now, so a mob targeted at
-- full long before the pull is not anchored at the moment it was targeted (the TTD lab's note on the full anchor).
-- Combat end releases the lazy lives. A plate REMOVED ends its hold at once (a returning token is a new unit): a lazy
-- life goes, a tracked plate gets a fresh life.
function lib.event(event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        lib.linkTok = false
        local s = lib.byToken.target
        if s then
            targetChanged(s)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        local now = GetTime()
        for i = 1, #lib.streams do
            local s = lib.streams[i]
            local lo, hi
            if s.lh then
                lo, hi = s.lh:Get()
            end
            for j = 1, s.life.feeder == s and #s.owners or 0 do -- a shared life: its feeder's band only
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
    elseif event == "PLAYER_REGEN_ENABLED" then
        for i = #lib.recent, 1, -1 do
            local p = lib.recent[i]
            if p and p.lazy then
                close(p)
            end
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        unit = plateToken(unit)
        if unit then
            lib.plates[unit] = true
            if lib.byToken.target and isUnit(unit) then
                lib.linkTok, lib.linkAt = unit, GetTime() + lib.POLL
                lib.wake()
            end
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        unit = plateToken(unit)
        if unit then
            lib.plates[unit] = nil
            if lib.linkTok == unit then
                lib.linkTok = false
            end
            local t = lib.byToken.target
            if t and t.plate == unit then
                t.plate = false
            end
            local p = lib.byToken[unit]
            if p and p.lazy then
                close(p)
            elseif p then
                remove(lib.recent, p)
                leave(p)
                p.lo, p.hi, p.hand = false, false, true
                bind(p, newLife(p))
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
    s.lazy = false -- a lazy plate tracked: explicit from now
    if not s.byOwner[owner] then
        addOwner(s, owner)
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

-- Every track and hint of the owner.
function lib:ReleaseAll(owner)
    for i = #lib.reg, 1, -1 do
        local h = lib.reg[i]
        if h and h.owner == owner then
            h:Release()
        end
    end
    if owner ~= nil then -- its records went with its tracks (and off the past targets' plates): nothing to push
        for i = 1, #lib.recent do
            local L = lib.recent[i].life
            remove(L.owners, L.byOwner[owner])
            L.byOwner[owner] = nil
        end
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

-- est, lo, hi (seconds from now; nil unless live), state, reason, id (the life's: a whole number, plain).
function H:Get()
    if self.released then
        return nil, nil, nil, "released"
    end
    if self.paused then
        return nil, nil, nil, "paused"
    end
    local s = self.s
    lib.evaluate(s, GetTime())
    local o = s.byOwner[self.owner]
    return o.est, o.lo, o.hi, o.state, o.why, s.life.id
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
    local s, owner = self.s, self.owner
    remove(s.tracks, self)
    local L, kept = s.life, false
    for i = 1, #lib.streams do -- the record stays while a track of its owner is on a stream holding its life
        local x = lib.streams[i]
        if x.life == L then
            for j = 1, #x.tracks do
                kept = kept or x.tracks[j].owner == owner
            end
        end
    end
    if not kept then
        remove(L.owners, L.byOwner[owner])
        L.byOwner[owner] = nil
    end
    if #s.tracks == 0 then
        close(s)
    else
        lib.syncPause(s)
    end
end

-- est, lo, hi, state, reason, id for whatever life token holds now (an owner's record on it), no handle; no record:
-- nil, nil, nil, "untracked" (a lazy life released, a plate token another unit names now, a token not tracked).
function lib:Get(owner, token)
    local s = lib.byToken[token]
    local o = s and s.byOwner[owner]
    if not o then
        return nil, nil, nil, "untracked"
    end
    lib.evaluate(s, GetTime())
    return o.est, o.lo, o.hi, o.state, o.why, s.life.id
end

-- token, id of the i-th newest past target whose plate still holds its life with a record of the owner's; nil past
-- the end.
function lib:Recent(owner, i)
    local n = 0
    for j = #lib.recent, 1, -1 do
        local p = lib.recent[j]
        if p.byOwner[owner] then
            n = n + 1
            if n == i then
                return p.token, p.life.id
            end
        end
    end
    return nil
end

-- Whether the owner's records follow its past targets to their plates (on by default). Off: they are dropped at the
-- hand-off, so its target restarts as before minor 5. true, or nil, code.
function lib:SetRecent(owner, on)
    if type(owner) ~= "string" then
        return nil, lib.ERR.OWNER_INVALID
    end
    lib.noRecent[owner] = not on or nil
    return true
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
            local tracks, sinks = 0, 0
            for k = 1, #s.tracks do
                local h = s.tracks[k]
                if h.owner == o.owner then
                    tracks = tracks + 1
                    sinks = sinks + (h.sink and 1 or 0)
                end
            end
            local rate = e.hf ~= 1
            out[#out + 1] = {
                token = s.token,
                owner = o.owner,
                tracks = tracks,
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

-- Load: the plates already shown (an addon loaded later sees no ADDED for them); an upgrade from minor 4: the records
-- a stream holds become its life.
for i = 1, 40 do
    local token = "nameplate" .. i
    if lib.present(token) then
        lib.plates[token] = true
    end
end
for i = 1, #lib.streams do
    local s = lib.streams[i]
    if not s.life then
        local lo, hi = false, false
        if s.lh then
            lo, hi = s.lh:Get()
        end
        lib.lastId = lib.lastId + 1
        s.life =
            { id = lib.lastId, owners = s.owners, byOwner = s.byOwner, feeder = s, lo = lo or false, hi = hi or false }
        s.lo, s.hi, s.hand, s.lazy = lo or false, hi or false, false, false
        s.step = s.token:match("^nameplate%d+$") and 5 or 1
        s.plate = s.token == "target" and lib.findPlate()
    end
end
