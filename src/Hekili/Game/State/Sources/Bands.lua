-- Game/State/Sources/Bands.lua
-- Hidden-value bands (LibHiddenValues integration design 2.1-2.3, 5.1-5.3; lane B1): the one belief file
-- that watches health and power through LibHiddenValues-1.0, reached through the injected client's LibStub
-- (`api.LibStub`: the game's, a fake in tests). Watches: the target's and the player's health and each tracked power
-- the library proves (`step = 1`, `points = {}`: the band in points), derived from def.units and def.resources, made
-- out of combat while the capability is not unavailable (at the build, and at a drain while one is missing). Poll 1.6
-- re-asserts every live band as Obs.Band at each drain and logs one unknown at the change from live to anything else;
-- I.bandT[channel] keeps the library's stamp. Families/TargetHealth.lua reads the target's (lane B2), Families/Player.lua
-- the player's (lane B3), Families/Resources.lua a power's (lane B4). A family that applies a band
-- records it in I.bandUsed (a count) and I.bandUsedLo/Hi (what it applied: the harness's containment check). A counter
-- (I.bandDisagree, design 2.3) counts the
-- settles at which the belief's own value lies more than one cell (1%: 0.01 of health, max / 100 points of power)
-- outside a live band, with no effect on any output (for the target and a power: a usable answer that contradicts the
-- band, which wins and clips it for its drain, L1675). Pauses: every watch after 2 s with no drain (the
-- event facade's frame update, I.BandsIdle), a power whose type is neither the displayed power nor mana. Kill switch:
-- def.providers.bands false releases every watch, out of combat (in combat at PLAYER_REGEN_ENABLED, decision 89).
-- Self-test: one retry out of combat 5 s after the first PLAYER_ENTERING_WORLD. Points (design 3.3, lane B7): the
-- active priority's thresholds (def.bandPoints) go to each power handle out of combat, at a new def.bandGen or a new
-- max; a refusal keeps the old set. A refused watch or set is asked again when combat ends (L1666 c: the caps are
-- shared, so a refusal can pass). A handle that answers max-unknown (the max never read plain: no points) is replaced by a
-- percent one for this build, converted at the belief's max and widened a point each side (design 2.4), only once that
-- max was read plain (I.maxPlain): a guessed one would make a measured floor of a percent, so then it logs no band.
-- A power that proves plain in combat (R.readable) releases its watch when combat ends, for this build.
-- Stacks (lane aura-stacks, L2023): each player aura the active priority reads as `buff.<key>.stack <op> N`
-- (def.bandStacks: its edges, Engine/Sim/Scripts.lua PackBands) with an edge from 2 to its max_stack is watched as the
-- library's aura kind (`what = "stacks"`, edge 1 added: the absent band is then [0, 1)) on the first of its IDs the
-- Cooldown Manager names, made out of combat and listed again when def.bandGen brings another edge set; poll 1.6 logs
-- a live band as Obs.Band on channel I.STACK_BAND - j in whole stacks (Families/Auras.lua applies it). In their own
-- arrays: the health and power loops, and the harness's I.bandLive walk, never see them.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Direct = S.Plain, S.Direct
local ceil = math.ceil

--- The client's own delay before a band's firing, which the library's Latency does not count ("the client's own delay
--- before it is not counted", its README): three frames at 60 fps (the integration design's bound). A band's whole
--- delay behind one of our events is I.bandShows[channel] = h:Latency() (seven frames, by the measured frame time, so
--- it grows as the frame rate falls) + this: about 0.17 s at 60 fps (Families/Resources.lua's hold).
I.BAND_MARGIN = I.Lat.lag("band.margin")
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
-- By watch k: the points' generation and max last resolved (false: not since the handle was made), the set the handle
-- holds, and the code that refused the latest one (false: none).
local pointGen, pointMax, points, pointCode = {}, {}, {}, {}
local percent = {} -- by watch k: the power's percent handle (max-unknown)
local want = {} -- the list being resolved (never a def.bandPoints table: those are the stored sources)
-- By channel: the library's stamp of the last live band, its low and high end (the family's units), whether the last
-- poll logged a band, and how many settles found the belief's value outside it.
I.bandT, I.bandLo, I.bandHi, I.bandLive, I.bandDisagree = {}, {}, {}, {}, {}
I.bandShows = {} -- by power or stack channel: the band's delay behind an event of ours (I.BAND_MARGIN)
-- (L1805) By channel: the watch works (switched on, the library found, its handle accepted and "live", or "priming"
-- again: not refused, released, paused or unavailable). Families/Player.lua holds a lost band only while it is true.
I.bandOK = {}
I.auraKnown = false -- the library's aura kind answers (its own capability report; the stack watches use it)
-- By channel: how many bands a family applied since the build, and the last one as it applied it.
I.bandUsed, I.bandUsedLo, I.bandUsedHi = {}, {}, {}

-- Stack watches by watch i (sn of them): its aura index, spec, edge list as text (a kept watch's test), handle (false:
-- none), cuts as a set (a band's hi is exclusive at a cut above lo), why it is not asked again before combat's end
-- (false or a code), the index of the aura ID it watches, and whether the last poll logged a band. sGen: the
-- def.bandGen listed (false: none since the build).
local sn, sJ, sSpec, sSig, sHandle, sCut, sRefused, sNext, sLive = 0, {}, {}, {}, {}, {}, {}, {}, {}
local sGen = false

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

-- Puts p into `want` (sorted, distinct) when it is a whole point of 1..max.
local function addPoint(p, max)
    if p < 1 or p > max or p % 1 ~= 0 then
        return
    end
    local i = #want
    while i > 0 and want[i] > p do
        i = i - 1
    end
    if i > 0 and want[i] == p then
        return
    end
    for j = #want, i + 1, -1 do
        want[j + 1] = want[j]
    end
    want[i + 1] = p
end

-- Power watch k's thresholds at the belief's max, sent when their generation or the max moved and the set changed
-- (a new point primes the band for about 9 frames). Allocates only when the set changes (out of combat).
local function setPoints(k)
    local max, gen = I.res.max[chan[k]], I.def.bandGen or 0
    if pointGen[k] == gen and pointMax[k] == max then
        return
    end
    pointGen[k], pointMax[k], pointCode[k] = gen, max, false
    for i = #want, 1, -1 do
        want[i] = nil
    end
    local all = I.def.bandPoints
    local e = all and all[ptype[k]]
    if e then
        for i = 1, #e.points do
            addPoint(e.points[i], max)
        end
        for i = 1, #e.deficit do
            addPoint(max - e.deficit[i], max)
        end
        for i = 1, #e.pct do
            addPoint(ceil(e.pct[i] * max / 100 - FUZZ), max)
        end
    end
    local have, same = points[k], #want == #points[k]
    for i = 1, #want do
        same = same and have[i] == want[i]
    end
    if same then
        return
    end
    local ok, code = handle[k]:SetPoints(want)
    if not ok then
        pointCode[k] = code
        return
    end
    for i = 1, #have > #want and #have or #want do
        have[i] = want[i]
    end
end

-- A power watch that cannot answer in points (max-unknown) becomes a percent one (out of combat, once a build).
local function toPercent()
    for k = 1, n do
        local h = handle[k]
        if h and ptype[k] and not percent[k] then
            local _, why = h:State()
            if why == "max-unknown" then
                h:Release()
                handle[k], percent[k] = false, true
                spec[k].points = nil -- this build's own spec
            end
        end
    end
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
                    if ptype[k] then -- it starts with no point
                        pointGen[k], points[k], pointCode[k] = false, {}, false
                    end
                end
            end
        end
    end
end

-- Stack watch i's band is no longer live: one unknown.
local function stackLost(i, t)
    if sLive[i] then
        sLive[i] = false
        Direct(Obs.Band, t, I.STACK_BAND - sJ[i], 1, 0)
    end
end

-- The stack watches def.bandStacks asks for (out of combat, at a new def.bandGen; cold: allocates). A watch whose aura
-- and edges stand keeps its handle and band (bandGen moves at every script load); every other old one is released.
local function listStacks(t)
    local def = I.def
    sGen = def.bandGen or 0
    local old, k = {}, 0
    for i = 1, sn do
        old[sJ[i]] = i
    end
    local nJ, nSpec, nSig, nH, nCut, nRef, nNext, nLive = {}, {}, {}, {}, {}, {}, {}, {}
    for j, a in ipairs(def.auras) do
        local max = a.max_stack
        max = type(max) == "number" and max >= 1 and max % 1 == 0 and max or nil
        local edges, cut = { 1 }, { [1] = true }
        for _, e in ipairs(def.bandStacks and def.bandStacks[a.key] or {}) do
            if e > 1 and e % 1 == 0 and (not max or e <= max) then
                edges[#edges + 1], cut[e] = e, true
            end
        end
        if #edges > 1 then -- edge 1 alone has no bar: nothing beyond presence
            k = k + 1
            local sig, i = table.concat(edges, ","), old[j]
            if i and sSig[i] == sig then
                nJ[k], nSpec[k], nSig[k], nH[k], nCut[k] = j, sSpec[i], sig, sHandle[i], sCut[i]
                nRef[k], nNext[k], nLive[k] = sRefused[i], sNext[i], sLive[i]
                sHandle[i], sLive[i] = false, false -- kept: neither released nor told unknown below
            else
                nJ[k], nSig[k], nH[k], nCut[k], nRef[k], nNext[k], nLive[k] = j, sig, false, cut, false, 1, false
                nSpec[k] = { kind = "aura", unit = "player", what = "stacks", edges = edges, max = max }
            end
            local ch = I.STACK_BAND - j
            I.bandT[ch], I.bandShows[ch] = I.bandT[ch] or 0, I.bandShows[ch] or I.BAND_MARGIN
        end
    end
    for i = 1, sn do
        if sHandle[i] then
            sHandle[i]:Release()
        end
        stackLost(i, t)
    end
    sJ, sSpec, sSig, sHandle, sCut, sRefused, sNext, sLive = nJ, nSpec, nSig, nH, nCut, nRef, nNext, nLive
    sn = k
end

-- Every missing stack watch, out of combat: on the aura's IDs in order, the next one while the Cooldown Manager names
-- none (`not-in-cdm`, also once a pending answer turns into it); any other answer stays the watch's own (its State).
local function ensureStacks()
    for i = 1, sn do
        local h, ids = sHandle[i], I.def.auraIds[sJ[i]]
        if h and select(2, h:State()) == "not-in-cdm" and ids[sNext[i] + 1] then
            h:Release()
            sHandle[i], sNext[i] = false, sNext[i] + 1
        end
        while not sHandle[i] and not sRefused[i] do
            local s = sSpec[i]
            s.spell = ids[sNext[i]]
            local nh, code = LHV:Watch(OWNER, s)
            if not nh then
                sRefused[i] = code
            elseif select(2, nh:State()) == "not-in-cdm" and ids[sNext[i] + 1] then
                nh:Release()
                sNext[i] = sNext[i] + 1
            else
                sHandle[i] = nh
            end
        end
    end
end

-- The kill switch: every watch released, one unknown for each channel that had a band. Allocates nothing.
local function off(t)
    if LHV then
        LHV:ReleaseAll(OWNER)
    end
    for i = 1, sn do
        sHandle[i], sRefused[i] = false, false
        stackLost(i, t)
    end
    I.auraKnown = false
    for k = 1, n do
        local ch = chan[k]
        handle[k], refused[k], paused[k], I.bandOK[ch] = false, false, false, false
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
        I.bandLive[ch], I.bandOK[ch] = false, false
    end
    I.auraKnown = false
    n, sn, sGen = 0, 0, false -- the stack watches listed again from this def (the log and their bands are cleared)
    local function add(ch, s, pt)
        n = n + 1
        chan[n], spec[n], handle[n], ptype[n], refused[n], paused[n] = ch, s, false, pt, false, false
        percent[n] = false
        I.bandT[ch], I.bandLo[ch], I.bandHi[ch], I.bandLive[ch], I.bandDisagree[ch] = 0, 0, 0, false, 0
        I.bandOK[ch] = false
        I.bandUsed[ch], I.bandUsedLo[ch], I.bandUsedHi[ch] = 0, 0, 0
        if pt then
            I.bandShows[ch] = I.BAND_MARGIN -- until the handle says
        end
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
        toPercent()
        ensure(api)
        if LHV then
            retry(t)
            for k = 1, n do
                if handle[k] and ptype[k] and not percent[k] then
                    setPoints(k)
                end
            end
            if sGen ~= (I.def.bandGen or 0) then
                listStacks(t)
            end
            ensureStacks()
        end
    end
    idle = false
    I.auraKnown = LHV ~= nil and (LHV:IsAvailable("aura")) == true
    for k = 1, n do
        local h, pt = handle[k], ptype[k]
        -- the plain read is better and free; the family ignores the band meanwhile, so the watch waits for combat's end
        if h and pt and not I.inCombat and I.res.readable[chan[k]] then
            h:Release()
            h, handle[k], refused[k] = false, false, "readable"
            local ch = chan[k]
            if I.bandLive[ch] then
                I.bandLive[ch] = false
                Direct(Obs.Band, t, ch, 1, 0)
            end
        end
        if h then
            local hold = pt ~= false and shown ~= nil and pt ~= shown and pt ~= MANA
            if hold ~= paused[k] then
                h:SetPaused(hold) -- a resumed watch primes again
                paused[k] = hold
            end
            local ch = chan[k]
            local lo, hi, bt
            local st = h:State()
            I.bandOK[ch] = st == "live" or st == "priming"
            if st == "live" and (not percent[k] or I.maxPlain[ch]) then
                lo, hi, bt = h:Get()
            end
            if lo then
                if pt == false then
                    lo, hi = lo / 100, hi / 100 -- percent to the family's fraction
                else
                    if percent[k] then -- in points at the belief's max, a point wider each side
                        local max = I.res.max[ch]
                        lo, hi = lo * max / 100 - 1, hi * max / 100 + 1
                        lo, hi = lo > 0 and lo or 0, hi < max and hi or max
                    end
                    I.bandShows[ch] = h:Latency() + I.BAND_MARGIN
                end
                I.bandT[ch], I.bandLo[ch], I.bandHi[ch], I.bandLive[ch] = bt, lo, hi, true
                Direct(Obs.Band, t, ch, lo, hi)
            elseif I.bandLive[ch] then
                I.bandLive[ch] = false
                Direct(Obs.Band, t, ch, 1, 0) -- b > c: unknown
            end
        else
            I.bandOK[chan[k]] = false
        end
    end
    -- the stack watches: a live band in whole stacks (hi exclusive at a cut above lo; the top `max` closed)
    for i = 1, sn do
        local h, lo, hi, bt = sHandle[i], nil, nil, nil
        if h and h:State() == "live" then
            lo, hi, bt = h:Get()
        end
        if lo then
            local ch = I.STACK_BAND - sJ[i]
            if hi > lo and sCut[i][hi] then
                hi = hi - 1
            end
            I.bandT[ch], I.bandLo[ch], I.bandHi[ch], sLive[i] = bt, lo, hi, true
            I.bandShows[ch] = h:Latency() + I.BAND_MARGIN
            Direct(Obs.Band, t, ch, lo, hi)
        else
            stackLost(i, t)
        end
    end
end)

--- (L1805; the core's fourth belief read, Facade.Known, owner "yes" 2026-11-23) Whether the hidden values of `kind`
--- answer now, each kind on its own (one broken leaves the others): 1 the player's health (its estimate is a reading:
--- a plain read, a live band or one held, Families/Player.lua; false means it reads full), 2 power type `powerType`
--- (read plain in combat, or its band live; false means the model), 3 the library's aura kind (its capability report:
--- a Cooldown Manager read would answer; the core's own Cooldown Manager reader, Hekili.cdmOff, is apart). Allocates
--- nothing.
function VS.Known(kind, powerType)
    if kind == 1 then
        return I.HealthKnown()
    elseif kind == 2 then
        local r = I.res.slotOf[powerType]
        return r ~= nil and (I.res.readable[r] == true or I.bandLive[r] == true)
    elseif kind == 3 then
        return I.auraKnown
    end
    return false
end

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

S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    for k = 1, n do
        if refused[k] ~= "unproven" and refused[k] ~= "readable" then
            refused[k] = false
        end
        if pointCode[k] then
            pointGen[k] = false
        end
    end
    for i = 1, sn do
        sRefused[i] = false
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
            local v, cell, hi = nil, 0.01, I.bandHi[ch]
            if ch == TARGET then
                v = I.th.est0
                -- the family's live-target floor over an empty band (0 0, minor 9) is no disagreement: judged as 0-1 is
                local low = I.TARGET_HEALTH_FLOOR - cell
                hi = hi > low and hi or low
            elseif ch == PLAYER then
                v = VS.Health("player", now).est
            else
                v, cell = I.res.est0[ch], I.res.max[ch] / 100
            end
            if v < I.bandLo[ch] - cell - FUZZ or v > hi + cell + FUZZ then
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
        local state, reason, held = "none", refused[k] or nil, ""
        if h then
            state, reason = h:State()
            if ptype[k] and percent[k] then
                held = " points=max-unknown"
            elseif ptype[k] and points[k] then
                held = " points=" .. (pointCode[k] or tostring(#points[k]))
            end
        end
        out[#out + 1] = string.format(
            "band %s state=%s reason=%s band=%s-%s age=%.2f disagree=%d%s",
            NAMES[ch] or ("power " .. tostring(ptype[k])),
            tostring(state),
            tostring(reason),
            tostring(I.bandLive[ch] and I.bandLo[ch] or "?"),
            tostring(I.bandLive[ch] and I.bandHi[ch] or "?"),
            I.bandLive[ch] and now - I.bandT[ch] or 0,
            I.bandDisagree[ch],
            held
        )
    end
    for i = 1, sn do -- why a priority's stack read follows the library or not (not on the Cooldown Manager's bars...)
        local h, ch = sHandle[i], I.STACK_BAND - sJ[i]
        local state, reason = "none", sRefused[i] or nil
        if h then
            state, reason = h:State()
        end
        out[#out + 1] = string.format(
            "band stacks %s spell=%s edges=%s state=%s reason=%s band=%s-%s",
            tostring(I.def.auras[sJ[i]].key),
            tostring(sSpec[i].spell),
            sSig[i],
            tostring(state),
            tostring(reason),
            tostring(sLive[i] and I.bandLo[ch] or "?"),
            tostring(sLive[i] and I.bandHi[ch] or "?")
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
