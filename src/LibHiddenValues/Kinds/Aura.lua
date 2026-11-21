-- Kinds/Aura.lua: auras on the player or the target, read from the client's Cooldown Manager (Cdm.lua finds the items
-- and forwards their values). what = "up": presence (lo == hi, 1 up, 0 not); "stacks": the stack count; "left": the
-- seconds left. Stacks and seconds are unknown while the aura is absent.
--
-- The bars: a hook's secret cannot go through a curve, so each edge has a raw bar ranged just below it, fed the
-- client's value as it is (AuraBandProbe 0.2.0/0.2.1: per-stack bars, a 2.9-3.0 s bar). Stacks are whole numbers on a
-- bar (e - 1, e): never inside, a clean two-level toggle. Seconds fall through a bar (e - W, e) and may land inside it
-- for a frame: that frame fires and so does the next, which a toggle cannot tell from a fall followed at once by a
-- refresh back above the edge. So a seconds bar firing on the frame after its last firing primes again (the run
-- rule; the seconds come every frame, so it answers within HOLD + 2 frames) and its handles keep their band
-- meanwhile. Edge 1 of stacks is presence itself and has no bar.
-- Priming: a new bar holds low HOLD frames (pushes in between are dropped) and starts below its edge. Its state is
-- right from then on, but it says something only once the client has pushed into it (lib.barFed), and again after
-- each time the aura was absent: seconds come every frame while the aura is up; stacks only when the client rewrites
-- the count (an application, a refresh, a target swap, a layout pass), so a stacks watch made while its aura is up is
-- unknown until then. Hook-fed bars follow every push, so a target swap does not prime them; a re-layout (UI scale, a
-- loading screen) does.
--
-- This file reaches the shared machinery by wrapping lib.sync, lib.feed, lib.fire, lib.decode, lib.reprime, lib.event
-- and lib.drive for aura sources (every script dispatches through lib, so this is the library's own upgrade path);
-- other kinds go through unchanged.
local lib = LibStub and LibStub("LibHiddenValues-1.0", true)
if not (lib and lib.loading) then
    return
end

local cdm = lib.cdm
local W = 0.01 -- seconds: a seconds bar's range below its edge
local WHAT = { up = true, stacks = true, left = true }
local RELAYOUT = { UI_SCALE_CHANGED = true, DISPLAY_SIZE_CHANGED = true, LOADING_SCREEN_DISABLED = true }
lib.barLast = lib.barLast or {} -- the frame of a seconds bar's last counted firing
lib.barFed = lib.barFed or {} -- the client pushed into the bar since its priming and since the aura was last absent
lib.barSoft = lib.barSoft or {} -- a seconds bar priming again after a run: its handles keep their band until it is fed

local function sortMerge(list)
    table.sort(list)
    local out = {}
    for i = 1, #list do
        if list[i] ~= out[#out] then
            out[#out + 1] = list[i]
        end
    end
    return out
end

-- Reads and checks the spec into the handle; returns an error text for bad-spec.
local function validate(spec, h)
    local unit, spell, what, edges, max = spec.unit, spec.spell, spec.what, spec.edges, spec.max
    if type(unit) ~= "string" or not unit:match("^%a%w*$") then
        return "unit must be a unit token"
    end
    if type(spell) ~= "number" or not (spell > 0) or spell % 1 ~= 0 then
        return "spell must be a spell ID"
    end
    if not WHAT[what] then
        return 'what must be "up", "stacks" or "left"'
    end
    if edges ~= nil and type(edges) ~= "table" then
        return "edges must be a list"
    end
    if max ~= nil and (type(max) ~= "number" or not (max >= 1) or max % 1 ~= 0) then
        return "max must be a whole number of stacks, 1 or more"
    end
    local cut = {}
    if what == "stacks" then
        for i = 1, edges and #edges or 0 do
            local e = edges[i]
            if type(e) ~= "number" or not (e >= 1) or e % 1 ~= 0 or (max and e > max) then
                return "stacks edges must be whole numbers from 1 to max"
            end
            cut[i] = e
        end
        if #cut == 0 then
            for e = 1, max or 0 do
                cut[e] = e
            end
        end
        if #cut == 0 then
            return "edges or max required"
        end
    elseif what == "left" then
        for i = 1, edges and #edges or 0 do
            local e = edges[i]
            if type(e) ~= "number" or not (e > W) then
                return "seconds edges must be numbers above " .. W
            end
            cut[i] = e
        end
        if #cut == 0 then
            return "edges required"
        end
    end
    cut = sortMerge(cut)
    local bars = {}
    for i = 1, #cut do
        if cut[i] > 1 or what == "left" then
            bars[#bars + 1] = cut[i]
        end
    end
    h.unit, h.spell, h.what, h.cut, h.edges = unit, spell, what, cut, bars
    h.top = what == "up" and 1 or (what == "stacks" and max) or math.huge
    h.key = "aura|" .. unit .. "|" .. spell .. "|" .. what
    if not lib.kinds.aura.units[unit] then
        h.unproven = "unproven"
    end
end

-- The capability of a spec without a watch (IsAvailable(kind, spec)): state, reason.
local function status(spec)
    local h = { kind = "aura" }
    if validate(spec, h) then
        return "unavailable", "bad-spec"
    end
    if h.unproven then
        return "unavailable", h.unproven
    end
    if cdm.dirty and lib.realised and not InCombatLockdown() then
        local ok, err = pcall(cdm.resolve)
        if not ok then
            lib.cdmFail(err)
            return lib.capOf("aura")
        end
    end
    return cdm.statusOf(h.spell, h.what)
end

lib.kinds.aura = {
    api = "C_CooldownViewer",
    units = { player = true, target = true }, -- the Cooldown Manager reads these two only
    validate = validate,
    status = status,
    why = function()
        return cdm.off and "cdm-off" or nil
    end,
}

-- Tells each owner of the source's handles that its answer changed: fn("aura", state, reason, h). quiet: only note
-- the answer (the first one, given inside Watch: the consumer reads h:State() after it).
function lib.auraTell(s, quiet)
    local state, reason = lib.capOf("aura")
    if state == "ready" and s.cap then
        state, reason = s.cap, s.why
    end
    if state == s.capState and reason == s.capWhy then
        return
    end
    s.capState, s.capWhy = state, reason
    if quiet then
        return
    end
    local hs = s.handles
    for j = #hs, 1, -1 do
        local h = hs[j]
        local fn = h and lib.capCb[h.owner]
        if fn then
            local ok, err = pcall(fn, "aura", state, reason, h)
            if not ok then
                lib.report(err)
            end
        end
    end
end

-- Bars --------------------------------------------------------------------------------------------------------------

-- A free pool bar for the source, priming; nil at the cap. lib.allocBar without its percent curve (aura bars have none).
local function alloc(s)
    local free = lib.free
    if #free == 0 and not (pcall(lib.newBar) and #free > 0) then
        return nil
    end
    local i = free[#free]
    free[#free] = nil
    lib.barSrc[i], lib.barState[i], lib.barPrime[i] = s, false, lib.HOLD + 1
    return i
end

local function release(s, e)
    local i = s.bar[e]
    lib.barFrame[i]:SetMinMaxValues(0, 2) -- back to the pool's shape
    lib.freeBar(i)
    s.bar[e] = nil
end

-- Brings an aura source in line with the capability, its placement and its references. A paused handle only mutes:
-- the client's pushes cost nothing, so the bars stay fed and need no priming when it resumes.
local function sync(s)
    if not s.placed then
        s.cap, cdm.dirty = "pending", true -- the first answer comes from the next read
        if cdm.cataloged then
            cdm.place()
        end
    end
    local ready = lib.realised and lib.capOf("aura") == "ready" and not s.cap and s.cd ~= nil
    if ready then
        for e, n in pairs(s.ref) do
            if n > 0 and not s.bar[e] then
                local i = alloc(s)
                if i then
                    lib.barFrame[i]:SetMinMaxValues(e - (s.what == "left" and W or 1), e)
                    lib.barLast[i], lib.barFed[i], lib.barSoft[i] = nil, false, nil
                end
                s.bar[e] = i
            end
        end
    end
    for e in pairs(s.bar) do
        if not ready or s.ref[e] == 0 then
            release(s, e)
        end
    end
    s.active = ready and #s.handles > 0
    if s.capState then
        lib.auraTell(s)
    end
    s.dirty = true
    lib.wake()
end

-- Every bar of an active aura source holds low again, then waits for the next push.
local function reprime(s)
    for _, i in pairs(s.bar) do
        lib.barPrime[i], lib.barFed[i], lib.barSoft[i] = lib.HOLD + 1, false, nil
    end
    s.dirty = true
    lib.wake()
end

-- One frame of an active aura source: presence (from the item showing it now), and the low hold of priming bars.
local function feed(s)
    local up
    if not cdm.off then
        local item = cdm.byCd[s.cd]
        if (item == nil or cdm.idOf(item) ~= s.cd) and cdm.scanFrame ~= lib.frameNo then
            cdm.scan() -- a reshuffle no acquire announced, or an item lost to secret identity: once a frame
            item = cdm.byCd[s.cd]
        end
        if item and cdm.idOf(item) == s.cd and cdm.live(item) then
            local a = rawget(item, "auraInstanceID")
            up = issecretvalue(a) or a ~= nil -- a secret: only tested, never compared
            if up then
                local u = rawget(item, "auraDataUnit")
                if not issecretvalue(u) and u ~= nil and u ~= s.unit then
                    up = false -- shown, but on the other unit
                end
            end
        end
    end
    if up ~= s.up then
        s.up, s.dirty, s.seen, s.seenFrame = up, true, GetTime(), lib.frameNo
    end
    s.gone = up == nil
    local prime, frames, fed = lib.barPrime, lib.barFrame, lib.barFed
    for _, i in pairs(s.bar) do
        local p = prime[i]
        if p > 1 then
            frames[i]:SetValue(0)
            prime[i] = p - 1
            s.dirty = true
            lib.nPush = lib.nPush + 1
        elseif p == 1 then
            lib.barState[i], prime[i], s.dirty = false, 0, true
        end
        if not up then
            fed[i], lib.barSoft[i] = false, nil
        end
    end
end

-- A bar's anchored child fired. Seconds bars: a firing on the frame after the last one is a fall through the bar.
local function fire(s, i)
    if lib.barPrime[i] > 0 then
        return
    end
    local f = lib.frameNo
    if s.what == "left" and lib.barLast[i] == f - 1 then -- a run: prime this bar again, its handles hold their band
        lib.barPrime[i], lib.barFed[i], lib.barSoft[i], lib.barLast[i] = lib.HOLD + 1, false, true, nil
        s.dirty = true
        return
    end
    lib.barState[i] = not lib.barState[i]
    lib.barLast[i] = f
    lib.nFire = lib.nFire + 1
    s.dirty, s.seen, s.seenFrame = true, GetTime(), f
end

-- The handle's band, then its sink when the band changed (the same rules as lib.decode: one call per frame).
local function decode(h)
    local lo, hi
    local s = h.src
    local state = lib.stateOf(h)
    if s.up and (state == "live" or state == "priming") then
        local soft = lib.barSoft
        for k = 1, #h.edges do
            if soft[s.bar[h.edges[k]]] then
                return -- a seconds bar priming again after a run: the band stands
            end
        end
    end
    if state == "live" then
        if h.what == "up" then
            lo = s.up and 1 or 0
            hi = lo
        elseif s.up then
            local st, fed, cut = lib.barState, lib.barFed, h.cut
            local below = false
            lo, hi = 0, h.top
            for k = 1, #cut do
                local e = cut[k]
                local i = s.bar[e]
                if i and not fed[i] then -- not pushed since its priming or the aura's last absence
                    lo, hi = nil, nil
                    break
                end
                if (i and st[i]) or (not i and e <= 1) then
                    if below then -- at or above an edge but below a lower one: a firing was lost
                        lib.desyncs = lib.desyncs + 1
                        reprime(s)
                        return
                    end
                    lo = e
                elseif not below then
                    below, hi = true, e
                end
            end
        end
    end
    if lo == h.lo and hi == h.hi then
        return
    end
    local frame = lib.frameNo
    if h.stamp == frame then
        s.dirty = true
        return
    end
    local dir = 0
    if lo and h.lo then
        dir = (lo > h.lo or hi > h.hi) and 1 or -1
    end
    local sf = s and s.seenFrame
    local t = (lo and sf and sf >= frame - 1) and s.seen or GetTime()
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

-- The wraps -----------------------------------------------------------------------------------------------------------

local baseSync, baseFeed, baseFire, baseDecode = lib.sync, lib.feed, lib.fire, lib.decode
local baseReprime, baseEvent, baseDrive = lib.reprime, lib.event, lib.drive

function lib.sync(s)
    if s.kind == "aura" then
        return sync(s)
    end
    return baseSync(s)
end

function lib.feed(s)
    if s.kind == "aura" then
        return feed(s)
    end
    return baseFeed(s)
end

function lib.fire(i)
    local s = lib.barSrc[i]
    if s ~= nil and s.kind == "aura" then
        return fire(s, i)
    end
    return baseFire(i)
end

function lib.decode(h)
    if h.kind == "aura" then
        return decode(h)
    end
    return baseDecode(h)
end

-- The shared callers (a target swap, a re-layout, the percent desync) do not apply: aura bars prime by their own rule.
function lib.reprime(s)
    if s.kind == "aura" then
        return
    end
    return baseReprime(s)
end

function lib.event(event, ...)
    if cdm.EVENTS[event] then
        return lib.cdmEvent(event, ...)
    end
    if RELAYOUT[event] then
        local srcs = lib.sources
        for i = 1, #srcs do
            local s = srcs[i]
            if s.kind == "aura" and s.active then
                reprime(s)
            end
        end
    end
    return baseEvent(event, ...)
end

-- Before the frame: read the Cooldown Manager again when something announced a change.
function lib.drive(elapsed)
    if cdm.dirty and lib.realised then
        local ok, err = pcall(cdm.resolve)
        if not ok then
            lib.cdmFail(err)
        end
    end
    return baseDrive(elapsed)
end

-- Diagnostics -----------------------------------------------------------------------------------------------------

-- One row per aura source with a handle, in creation order: { unit =, spell =, what =, handles =, bars =, active =,
-- cooldownID =, placement = "bar" | "icon" | nil, state =, reason =, up = true | false | nil }; then the Cooldown
-- Manager's own facts: off (cdm-off), read (the catalogue was read), text and value pushes forwarded, values refused,
-- layout reads. A fresh array: a cold path.
function lib:GetAuraSources()
    local out = {}
    for n = 1, #lib.sources do
        local s = lib.sources[n]
        if s.kind == "aura" and #s.handles > 0 then
            local bars = 0
            for _ in pairs(s.bar) do
                bars = bars + 1
            end
            local state, reason = lib.capOf("aura")
            if state == "ready" and s.cap then
                state, reason = s.cap, s.why
            end
            out[#out + 1] = {
                unit = s.unit,
                spell = s.spell,
                what = s.what,
                handles = #s.handles,
                bars = bars,
                active = s.active and true or false,
                cooldownID = s.cd,
                placement = s.place == 1 and "bar" or s.place == 2 and "icon" or nil,
                state = state,
                reason = reason,
                up = s.up,
            }
        end
    end
    return out,
        cdm.off and true or false,
        cdm.cataloged and true or false,
        cdm.nText,
        cdm.nValue,
        cdm.nRefused,
        cdm.nScan
end
