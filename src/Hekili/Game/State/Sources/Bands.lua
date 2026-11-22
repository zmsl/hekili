-- Game/State/Sources/Bands.lua
-- Hidden-value bands (LibHiddenValues integration design 2.1-2.3, 5.1-5.3; lane B1, record-only): the one belief file
-- that watches health and power through LibHiddenValues-1.0, reached through the injected client's LibStub
-- (`api.LibStub`: the game's, a fake in tests). Watches: the target's and the player's health and each tracked power
-- the library proves (`step = 1`, `points = {}`: the band in points), derived from def.units and def.resources, made
-- out of combat while the capability is not unavailable (at the build, and at a drain while one is missing). Poll 1.6
-- re-asserts every live band as Obs.Band at each drain and logs one unknown at the change from live to anything else;
-- I.bandT[channel] keeps the library's stamp. Families/TargetHealth.lua reads the target's (lane B2); player health and
-- power wait for lanes B3-B4. A family that applies a band records it in I.bandUsed (a count) and I.bandUsedLo/Hi (what
-- it applied: the harness's containment check). A counter (I.bandDisagree, design 2.3) counts the settles at which the
-- belief's own value lies more than one cell (1%: 0.01 of health, max / 100 points of power) outside a live band, with
-- no effect on any output (for the target: a usable answer that contradicts the band, FABLE-FOR-OWNER 18). Pauses: every watch after 2 s with no drain (the event facade's frame update, I.BandsIdle), a power whose type
-- is neither the displayed power nor mana. Kill switch: def.providers.bands false releases every watch, out of combat
-- (in combat at PLAYER_REGEN_ENABLED, decision 89). Self-test: one retry out of combat 5 s after the first
-- PLAYER_ENTERING_WORLD.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Direct = S.Plain, S.Direct

local MAJOR = "LibHiddenValues-1.0"
local OWNER = "HekiliBelief" -- the border check keeps the bare addon name out of Game/ (design 2.1)
local MANA = 0 -- Enum.PowerType.Mana: fed in every form (design 5.3)
local IDLE = 2 -- seconds with no drain before every watch pauses (design 2.2)
local RETRY = 5 -- seconds after the first PLAYER_ENTERING_WORLD for the one self-test retry (design 5.2)
local TARGET, PLAYER = -1, 0 -- the health channels; a resource slot r >= 1 is its power's
local FUZZ = 1e-9 -- float slack on the one-cell margin

-- By watch k (n of them): its channel, its spec, its handle (false: none), its power type (false: a health watch),
-- why it is not asked again before the next build (false, a Watch refusal code or "unproven"), and whether it is paused.
local n = 0
local chan, spec, handle, ptype, refused, paused = {}, {}, {}, {}, {}, {}
-- By channel: the library's stamp of the last live band, its low and high end (the family's units), whether the last
-- poll logged a band, and how many settles found the belief's value outside it.
I.bandT, I.bandLo, I.bandHi, I.bandLive, I.bandDisagree = {}, {}, {}, {}, {}
-- By channel: how many bands a family applied since the build, and the last one as it applied it.
I.bandUsed, I.bandUsedLo, I.bandUsedHi = {}, {}, {}

local LHV -- the library, once found
local on = false -- the watches wanted (def.providers.bands), as applied
local idle, lastDrain = false, nil
local shown -- the client's displayed power type (nil: not read plain)
local pewT, retried = nil, false

local function readShown(api)
    local raw = api.UnitPowerType("player") -- secret: Plain next
    local v = Plain(api, raw)
    shown = type(v) == "number" and v or nil
end

-- Makes every missing watch the capability allows (out of combat). Allocates a handle per watch made.
local function ensure(api)
    if not on or n == 0 then
        return
    end
    if not LHV then
        LHV = api.LibStub(MAJOR, true) -- secret: LibStub's library table, an addon's own (never a hidden value)
        if not LHV then
            return
        end
        readShown(api)
    end
    for k = 1, n do
        if not handle[k] and not refused[k] then
            local s = spec[k]
            local _, state = LHV:IsAvailable(s.kind, s.unit)
            if state ~= "unavailable" then
                local h, code = LHV:Watch(OWNER, s)
                if not h then
                    refused[k] = code
                elseif select(2, h:State()) == "unproven" then -- a power the library does not prove (focus): none
                    h:Release()
                    refused[k] = "unproven"
                else
                    handle[k], paused[k] = h, false
                end
            end
        end
    end
end

-- The kill switch: every watch released, one unknown for each channel that had a band. Allocates nothing.
local function off(t)
    if LHV then
        LHV:ReleaseAll(OWNER)
    end
    for k = 1, n do
        local ch = chan[k]
        handle[k], refused[k], paused[k] = false, false, false
        if I.bandLive[ch] then
            I.bandLive[ch] = false
            Direct(Obs.Band, t, ch, 1, 0)
        end
    end
end

-- One retry of a failed self-test, RETRY s after the first world entry, out of combat; never again this session.
local function retry(t)
    if retried or not pewT or t < pewT + RETRY then
        return
    end
    local verdict, _, running = LHV:GetSelfTest()
    if running or verdict == nil then
        return -- the login run is still deciding
    end
    retried = true
    if verdict == false then
        LHV:SelfTest()
    end
end

I.OnBuild(function(def, now)
    if LHV then
        LHV:ReleaseAll(OWNER)
    end
    for k = 1, n do
        handle[k], refused[k], paused[k] = false, false, false
    end
    for ch in pairs(I.bandLive) do
        I.bandLive[ch] = false
    end
    n = 0
    local function add(ch, s, pt)
        n = n + 1
        chan[n], spec[n], handle[n], ptype[n], refused[n], paused[n] = ch, s, false, pt, false, false
        I.bandT[ch], I.bandLo[ch], I.bandHi[ch], I.bandLive[ch], I.bandDisagree[ch] = 0, 0, 0, false, 0
        I.bandUsed[ch], I.bandUsedLo[ch], I.bandUsedHi[ch] = 0, 0, 0
    end
    for _, unit in ipairs(def.units) do
        if unit == "target" or unit == "player" then
            add(unit == "target" and TARGET or PLAYER, { kind = "health", unit = unit, step = 1 }, false)
        end
    end
    for r, d in ipairs(def.resources) do
        if d.onTarget ~= true then -- a count bound to one target is read plain (Sources/Power.lua)
            add(r, { kind = "power", unit = "player", power = d.type, step = 1, points = {} }, d.type)
        end
    end
    local pv = def.providers
    on, idle = pv ~= nil and pv.bands == true, false
    if I.api and not I.inCombat then
        ensure(I.api)
    end
end)

-- Poll 1.6 (after the plain reads, before the usability ladder): the switch, the missing watches and the retry out of
-- combat, the pauses, then each watch's band. Allocates nothing once its watches exist.
S.Poll(1.6, function(api, t)
    lastDrain = t
    local pv = I.def.providers
    local want = pv ~= nil and pv.bands == true
    if want ~= on and not I.inCombat then
        on = want
        if not want then
            off(t)
        end
    end
    if not on then
        return
    end
    if not I.inCombat then
        ensure(api)
        if LHV then
            retry(t)
        end
    end
    idle = false
    for k = 1, n do
        local h = handle[k]
        if h then
            local pt = ptype[k]
            local hold = pt ~= false and shown ~= nil and pt ~= shown and pt ~= MANA
            if hold ~= paused[k] then
                h:SetPaused(hold) -- a resumed watch primes again
                paused[k] = hold
            end
            local ch = chan[k]
            local lo, hi, bt
            if h:State() == "live" then
                lo, hi, bt = h:Get()
            end
            if lo then
                if pt == false then
                    lo, hi = lo / 100, hi / 100 -- percent to the family's fraction
                end
                I.bandT[ch], I.bandLo[ch], I.bandHi[ch], I.bandLive[ch] = bt, lo, hi, true
                Direct(Obs.Band, t, ch, lo, hi)
            elseif I.bandLive[ch] then
                I.bandLive[ch] = false
                Direct(Obs.Band, t, ch, 1, 0) -- b > c: unknown
            end
        end
    end
end)

--- The event facade's frame update: after IDLE s with no drain every watch pauses (the next drain resumes them).
--- Allocates nothing.
function I.BandsIdle(now)
    if idle or not lastDrain or now - lastDrain <= IDLE then
        return
    end
    idle = true
    for k = 1, n do
        local h = handle[k]
        if h and not paused[k] then
            h:SetPaused(true)
            paused[k] = true
        end
    end
end

S.On("UNIT_DISPLAYPOWER", "player", function(api, t, unit)
    if unit == "player" then
        readShown(api)
    end
end)

S.On("PLAYER_ENTERING_WORLD", nil, function(api, t)
    pewT = pewT or t
end)

-- The disagreement counter: a live band against the belief's own value after the fold, beyond one cell (L1666 h; the
-- band lags the client by up to two frames, so a value one cell out is the crossing, not a disagreement). Allocates
-- nothing.
I.OnSettle(function(now)
    for k = 1, n do
        local ch = chan[k]
        if I.bandLive[ch] then
            local v, cell = nil, 0.01
            if ch == TARGET then
                v = I.th.est0
            elseif ch == PLAYER then
                v = VS.Health("player", now).est
            else
                v, cell = I.res.est0[ch], I.res.max[ch] / 100
            end
            if v < I.bandLo[ch] - cell - FUZZ or v > I.bandHi[ch] + cell + FUZZ then
                I.bandDisagree[ch] = I.bandDisagree[ch] + 1
            end
        end
    end
end)

local NAMES = { [TARGET] = "target health", [PLAYER] = "player health" }

-- Snapshot lines (English only): the library, its self-test, each watch, the library's own costs. Allocates.
I.OnSnapshot(function(out, now)
    if not LHV then
        out[#out + 1] = string.format("bands on=%s watches=%d library=none", tostring(on), n)
        return
    end
    local major, minor = LHV:GetVersion()
    local verdict = LHV:GetSelfTest()
    out[#out + 1] = string.format(
        "bands on=%s watches=%d library=%s %s selftest=%s idle=%s shown=%s",
        tostring(on),
        n,
        tostring(major),
        tostring(minor),
        verdict == nil and "pending" or (verdict and "pass" or "fail"),
        tostring(idle),
        tostring(shown)
    )
    for k = 1, n do
        local ch, h = chan[k], handle[k]
        local state, reason = "none", refused[k] or nil
        if h then
            state, reason = h:State()
        end
        out[#out + 1] = string.format(
            "band %s state=%s reason=%s band=%s-%s age=%.2f disagree=%d",
            NAMES[ch] or ("power " .. tostring(ptype[k])),
            tostring(state),
            tostring(reason),
            tostring(I.bandLive[ch] and I.bandLo[ch] or "?"),
            tostring(I.bandLive[ch] and I.bandHi[ch] or "?"),
            I.bandLive[ch] and now - I.bandT[ch] or 0,
            I.bandDisagree[ch]
        )
    end
    local bars, usFrame, usPeak, _, _, desyncs, _, splits = LHV:GetStats()
    out[#out + 1] = string.format(
        "bands stats bars=%s us/frame=%s peak=%s desyncs=%s splits=%s",
        tostring(bars),
        tostring(usFrame),
        tostring(usPeak),
        tostring(desyncs),
        tostring(splits)
    )
end)
