-- Game/Events/Attackers.lua
-- Hits on us as combat-log rows (event-facade spec §2.4, §6, decision 6). The player's UNIT_COMBAT says what landed or
-- was avoided but not who swung, so the layer keeps (a) the set of hostiles targeting us, from UNIT_TARGET and the
-- target, focus and nameplate tokens (UnitIsUnit("<unit>target", "player"), through Plain: a secret answer counts as
-- not targeting us), and (b) a swing clock per attacker, an anchor and a period like our own hands: the period is
-- UnitAttackSpeed(unit) when plain, else learned from the gaps between hits on us. A hit is credited to the attacker
-- whose clock predicts a swing nearest it within ATTACK_TOLERANCE; while a single hostile targets us and its clock is
-- not set yet, to that one (which starts its clock); otherwise it stays unattributed and makes no row (no phantom
-- enemy for the tank branch, Events.lua's `ns.updateTarget( sourceGUID, ... )`). A physical wound also has each
-- attacker's amount band to go by (combat harness design §4): learned from the wounds its clock or the lone-hostile
-- rule credited, it separates two attackers of different strength. The same per-token reads count the hostiles
-- attacking someone else (VirtualState.LooseEnemies, tank design §2).
-- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
-- (docs/research/2026-10-14-virtual-combat-log-events.md, C2, C4, M1-M4, D13).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Plain, Note = S.Plain, S.Note
local L = I.Log
local floor = math.floor
local Stats = I.Stats

L.ATTACK_TOLERANCE = 0.2 -- seconds between a clock's predicted swing and a hit credited to it
L.unattributed = 0
-- A band fits a wound within [BAND_LO x its min, BAND_HI x its max] once BAND_N wounds taught it (margins UNMEASURED
-- in game; set from the harness only).
L.BAND_LO, L.BAND_HI, L.BAND_N = 0.8, 1.2, 3
L.onus = { credited = 0, byBand = 0 } -- byBand: the credits the bands chose among several hostiles on us

-- The tokens whose target is checked: the registry's 1-42 (target, focus, nameplate1-40); "<token>target" built once.
local U = I.Units
local TOKENS, INDEX, NT = U.TOKENS, U.INDEX, 42
local TT = {}
for i = 1, NT do
    TT[i] = TOKENS[i] .. "target"
end
local tokOnMe, tokSpeed, tokLoose = {}, {}, {}
for i = 1, NT do
    tokOnMe[i], tokSpeed[i], tokLoose[i] = false, 0, false
end

-- Attacker clocks by GUID (8, the oldest anchor gives way), each with its amount band (min and max over the slot's
-- life, of `atkN` wounds).
local N = 8
local atkGUID, atkAnchor, atkPeriod, atkLo, atkHi, atkN = {}, {}, {}, {}, {}, {}
local atkHitT = {} -- the latest learned hit (the anchor before any parry pull moved it)
for k = 1, N do
    atkGUID[k], atkAnchor[k], atkPeriod[k], atkLo[k], atkHi[k], atkN[k] = "", 0, 0, 0, 0, 0
    atkHitT[k] = 0
end

-- The clock of `guid`, or nil. Allocates nothing.
local function find(guid)
    for k = 1, N do
        if atkGUID[k] == guid then
            return k
        end
    end
end

-- The clock of `guid`, made on first credit in a free slot, else in the one with the oldest anchor.
local function clockOf(guid)
    local k = find(guid)
    if k then
        return k
    end
    local slot = 1
    for j = 1, N do
        if atkGUID[j] == "" then
            slot = j
            break
        elseif atkAnchor[j] < atkAnchor[slot] then
            slot = j
        end
    end
    atkGUID[slot], atkAnchor[slot], atkPeriod[slot], atkLo[slot], atkHi[slot], atkN[slot] = guid, 0, 0, 0, 0, 0
    atkHitT[slot] = 0
    return slot
end

local function recheck(api, i)
    local tok = TOKENS[i]
    local guid = U.Bound(i)
    local hostile = guid ~= "" and Plain(api, api.UnitCanAttack("player", tok)) == true
    local raw = api.UnitIsUnit(TT[i], "player") -- secret: tested with issecretvalue next, then read through Plain
    if guid ~= "" then -- an empty token's answer would overwrite a secret status
        Note("UnitIsUnit target-of", S.StatusOf(api, raw))
    end
    local onMe = Plain(api, raw)
    tokOnMe[i] = hostile and onMe == true
    -- attacking someone else: its target exists and is plainly not us (a secret answer counts as neither)
    tokLoose[i] = hostile and onMe == false and Plain(api, api.UnitExists(TT[i])) == true
    tokSpeed[i] = 0
    if tokOnMe[i] then
        local rawSpeed = api.UnitAttackSpeed(tok) -- secret: tested with issecretvalue next, then read through Plain
        Note("UnitAttackSpeed hostile", S.StatusOf(api, rawSpeed))
        local speed = Plain(api, rawSpeed)
        if type(speed) == "number" and speed > 0 then
            tokSpeed[i] = speed
        end
    end
end

local function onUnit(api, t, unit)
    local i = unit and INDEX[unit]
    if i and i <= NT then
        recheck(api, i)
    end
end
S.On("UNIT_TARGET", nil, onUnit)
S.On("NAME_PLATE_UNIT_ADDED", nil, onUnit)
S.On("NAME_PLATE_UNIT_REMOVED", nil, function(_, _, unit)
    local i = unit and INDEX[unit]
    if i and i <= NT then -- the registry unbound it; the plate's own answers clear here
        tokOnMe[i], tokSpeed[i], tokLoose[i] = false, 0, false
    end
end)
local function readTarget(api)
    recheck(api, 1)
    L.target = U.Bound(1)
end
S.On("PLAYER_TARGET_CHANGED", nil, readTarget)
S.OnStart(readTarget)
S.On("PLAYER_FOCUS_CHANGED", nil, function(api)
    recheck(api, 2)
end)

--- (tank design §2) The hostiles (target, focus, nameplates) whose target exists and is not the player, each GUID
--- once, as of their last UNIT_TARGET, plate or target/focus change. Allocates nothing.
function VS.LooseEnemies()
    local n = 0
    for i = 1, NT do
        if tokLoose[i] then
            local seen = false
            for j = 1, i - 1 do
                if tokLoose[j] and U.Bound(j) == U.Bound(i) then
                    seen = true
                    break
                end
            end
            if not seen then
                n = n + 1
            end
        end
    end
    return n
end

-- How far `t` lies from the nearest swing a clock predicts (huge when the clock is not set). Allocates nothing.
local function clockError(k, period, t)
    local anchor = k and atkAnchor[k] or 0
    if period <= 0 or anchor <= 0 then
        return math.huge
    end
    local d = (t - anchor) % period
    return d < period - d and d or period - d
end

-- A credited hit re-anchors the clock and, without a plain speed, refines the learned period from the gap.
local function learn(k, t, speed)
    local gap = t - atkAnchor[k]
    if speed > 0 then
        atkPeriod[k] = speed
    elseif atkAnchor[k] > 0 then
        local period = atkPeriod[k]
        if period <= 0 then
            if gap >= 1 and gap <= 5 then
                atkPeriod[k] = gap
            end
        else
            local n = floor(gap / period + 0.5)
            if n >= 1 and math.abs(gap - n * period) <= L.ATTACK_TOLERANCE then
                atkPeriod[k] = (Stats.Ema(period, 0, gap / n, 0.2, 0)) -- shortcut: a plain EMA; a dual-wielding attacker blurs it
            end
        end
    end
    atkAnchor[k], atkHitT[k] = t, t
end

local MISSES = { DODGE = true, PARRY = true, BLOCK = true, MISS = true }

local Bands = I.Bands

-- A wound's amount as its attacker's unmodified hit (Bands' "theirs": a crit halved, a crush / 1.5, a partly blocked
-- one nil), or nil for a secret amount or flag (read through Plain: nil).
local function base(amount, flag)
    if type(flag) ~= "string" then
        return nil
    end
    return Bands.Normalise(amount, flag, "theirs")
end

-- Whether clock k's band is usable and holds `a`.
local function fits(k, a)
    return k ~= nil and Bands.Fits(atkLo, atkHi, atkN, k, a, L.BAND_LO, L.BAND_HI, L.BAND_N)
end

-- Parry haste on a hostile (parry-haste spec decision 62): a PARRY row on its token pulls its clock's next swing by
-- L.ParryPull, whoever's attack it parried (the rule is the parrier's). One row comes on several tokens (target, plate,
-- soft target): applied once per GUID and row time. No row, no clock made. Allocates nothing. A row Rows.lua just
-- credited to our swing as this mob's parry (L.avoidRowT, L.avoidRowG) is dated at that swing: the server pulled the
-- clock a landing lag before the row.
-- A parry dated before the hostile's latest learned hit changes nothing: its pulled swing landed before our row.
local parriedGUID, parriedT = "", -1
local function parried(t, unit)
    local i = INDEX[unit]
    local guid = i and U.Bound(i) or ""
    if guid == "" or (guid == parriedGUID and t == parriedT) then
        return
    end
    parriedGUID, parriedT = guid, t
    local k = find(guid)
    if not k or atkAnchor[k] <= 0 then
        return
    end
    local period = i <= NT and tokSpeed[i] or 0
    if period <= 0 then
        period = atkPeriod[k]
    end
    if period <= 0 then
        return
    end
    local at = L.avoidRowT == t and L.avoidRowG == guid and L.avoidT or t
    if at < atkHitT[k] then -- the swing it pulled already landed (before our row): the learned hit holds its pull
        return
    end
    local a = atkAnchor[k]
    local p = a + (floor((at - a) / period) + 1) * period -- its next predicted swing after the parry
    atkAnchor[k] = a - L.ParryPull(p - at, period)
end

S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
    if unit ~= "player" then
        if act == "PARRY" then
            parried(t, unit)
        end
        return
    elseif act ~= "WOUND" and not MISSES[act] then
        return
    end
    -- the hit's resolved time from the Outcomes provider (its own clock, plain), else the row's; the row keeps t. A
    -- white wound the provider would date but cannot is late by the taken lead: it moves no clock (`undated`)
    local te, undated = t, false
    if act == "WOUND" then
        local h, dates = I.outcomes.EnemyHitAt(t, school)
        if h then
            te = h
        elseif dates and school == 1 then
            undated = true
        end
    end
    local melee = act ~= "WOUND" or school == 1
    local wound = act == "WOUND" and school == 1
    local a = wound and base(amount, flag) or nil
    -- the candidates: each hostile targeting us once (a GUID can be the target and a plate); no clock is made here
    local best, bestErr, single, n, nTol, tolI, nFit, fitI = nil, L.ATTACK_TOLERANCE, nil, 0, 0, nil, 0, nil
    local nNew, newI = 0, nil -- candidates whose band is not usable yet
    for i = 1, NT do
        if tokOnMe[i] then
            local guid, seen = U.Bound(i), false
            for j = 1, i - 1 do
                seen = seen or (tokOnMe[j] and U.Bound(j) == guid)
            end
            if not seen then
                n, single = n + 1, i
                local k = find(guid)
                local period = tokSpeed[i]
                if period <= 0 and k then
                    period = atkPeriod[k]
                end
                local err = clockError(k, period, te)
                if melee and err <= L.ATTACK_TOLERANCE then
                    nTol, tolI = nTol + 1, i
                    if err <= bestErr then
                        best, bestErr = i, err
                    end
                end
                if not (k and atkN[k] >= L.BAND_N) then
                    nNew, newI = nNew + 1, i
                elseif fits(k, a) then
                    nFit, fitI = nFit + 1, i
                end
            end
        end
    end
    local byBand = false
    if wound and a then -- harness design §4.2: the clock, unless the bands say another; else the bands; else the lone one
        best = nil
        if nTol == 1 then
            best = tolI
            local k = find(U.Bound(tolI))
            if k and atkN[k] >= L.BAND_N and not fits(k, a) and nFit == 1 and nNew == 0 then
                best, byBand = fitI, true
            end
        elseif nFit == 1 and nNew == 0 and n > 1 then -- every band known, one holds it (alone: the lone rule's)
            best, byBand = fitI, true
        elseif nFit == 0 and nNew == 1 and n > 1 then -- every known band excludes it: the one without a band
            best = newI
        end
    end
    if not best and n == 1 then
        -- one hostile on us: it is that one (a spell, no clock yet, or a swing off its clock: a new phase, which
        -- learn re-anchors without refining the period, since the gap is off by more than the tolerance)
        best = single
    end
    if not best then
        L.unattributed = L.unattributed + 1
        return
    end
    L.onus.credited = L.onus.credited + 1
    local src, dst = U.Bound(best), L.player
    if melee then -- a spell does not follow the swing clock: no clock made or moved for it
        local k = clockOf(src)
        if not undated then
            learn(k, te, tokSpeed[best]) -- a band credit moves the clock too (it keeps the phase); the band learns later
        end
        if byBand then
            L.onus.byBand = L.onus.byBand + 1
        elseif a then -- a band learns from the clock's, the lone hostile's and the elimination's credits, never its own
            Bands.Learn(atkLo, atkHi, atkN, k, a, 0)
        end
    end
    local amt = type(amount) == "number" and amount or 0
    if act == "WOUND" and melee then
        L.Swing(t, "onus", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS, amt, flag, false)
    elseif act == "WOUND" then
        local mask = type(school) == "number" and school or 1
        L.SpellHit("SPELL_DAMAGE", t, "onus", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS, 0, mask, amt, flag)
    else
        L.Miss(t, "onus", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS, nil, 1, act, false)
    end
end)

-- Combat end: the clocks lose their anchors (a new pull starts them again); learned periods stay.
S.On("PLAYER_REGEN_ENABLED", nil, function()
    for k = 1, N do
        atkAnchor[k] = 0
    end
end)

I.OnSnapshot(function(out)
    out[#out + 1] =
        string.format("rows onus credited=%d unattributed=%d byBand=%d", L.onus.credited, L.unattributed, L.onus.byBand)
end)
