-- VirtualState/Sources/Attackers.lua
-- Hits on us as combat-log rows (event-facade spec §2.4, §6, decision 6). The player's UNIT_COMBAT says what landed or
-- was avoided but not who swung, so the layer keeps (a) the set of hostiles targeting us, from UNIT_TARGET and the
-- target, focus and nameplate tokens (UnitIsUnit("<unit>target", "player"), through Plain: a secret answer counts as
-- not targeting us), and (b) a swing clock per attacker, an anchor and a period like our own hands: the period is
-- UnitAttackSpeed(unit) when plain, else learned from the gaps between hits on us. A hit is credited to the attacker
-- whose clock predicts a swing nearest it within ATTACK_TOLERANCE; while a single hostile targets us and its clock is
-- not set yet, to that one (which starts its clock); otherwise it stays unattributed and makes no row (no phantom
-- enemy for the tank branch, Events.lua's `ns.updateTarget( sourceGUID, ... )`).
-- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
-- (docs/research/2026-10-14-virtual-combat-log-events.md, C2, C4, M1-M4, D13).

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain, Note = S.Plain, S.Note
local L = I.Log
local floor = math.floor

L.ATTACK_TOLERANCE = 0.2 -- seconds between a clock's predicted swing and a hit credited to it
L.unattributed = 0

-- The tokens whose target is checked: target, focus, nameplate1-40; each with "<token>target" built once.
local TOKENS, TT, INDEX = { "target", "focus" }, {}, {}
for i = 1, 40 do
    TOKENS[#TOKENS + 1] = "nameplate" .. i
end
for i = 1, #TOKENS do
    TT[i], INDEX[TOKENS[i]] = TOKENS[i] .. "target", i
end
local tokGUID, tokOnMe, tokSpeed = {}, {}, {}
for i = 1, #TOKENS do
    tokGUID[i], tokOnMe[i], tokSpeed[i] = "", false, 0
end

-- Attacker clocks by GUID (8, the oldest anchor gives way).
local N = 8
local atkGUID, atkAnchor, atkPeriod = {}, {}, {}
for k = 1, N do
    atkGUID[k], atkAnchor[k], atkPeriod[k] = "", 0, 0
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
    atkGUID[slot], atkAnchor[slot], atkPeriod[slot] = guid, 0, 0
    return slot
end

local function recheck(api, i)
    local tok = TOKENS[i]
    local guid = Plain(api, api.UnitGUID(tok)) or ""
    local hostile = guid ~= "" and Plain(api, api.UnitCanAttack("player", tok)) == true
    local raw = api.UnitIsUnit(TT[i], "player") -- secret: tested with issecretvalue next, then read through Plain
    if guid ~= "" then -- an empty token's answer would overwrite a secret status
        Note("UnitIsUnit target-of", S.StatusOf(api, raw))
    end
    tokGUID[i], tokOnMe[i] = guid, hostile and Plain(api, raw) == true
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
    if i then
        recheck(api, i)
    end
end
S.On("UNIT_TARGET", nil, onUnit)
S.On("NAME_PLATE_UNIT_ADDED", nil, onUnit)
S.On("NAME_PLATE_UNIT_REMOVED", nil, function(_, _, unit)
    local i = unit and INDEX[unit]
    if i then -- the token still answers during the event: clear it rather than recheck
        tokGUID[i], tokOnMe[i], tokSpeed[i] = "", false, 0
    end
end)
S.On("PLAYER_TARGET_CHANGED", nil, function(api)
    recheck(api, 1)
end)
S.On("PLAYER_FOCUS_CHANGED", nil, function(api)
    recheck(api, 2)
end)

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
                atkPeriod[k] = period * 0.8 + gap / n * 0.2 -- shortcut: a plain EMA; a dual-wielding attacker blurs it
            end
        end
    end
    atkAnchor[k] = t
end

local MISSES = { DODGE = true, PARRY = true, BLOCK = true, MISS = true }

S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
    if unit ~= "player" or (act ~= "WOUND" and not MISSES[act]) then
        return
    end
    local melee = act ~= "WOUND" or school == 1
    -- the candidates: each hostile targeting us once (a GUID can be the target and a plate); no clock is made here
    local best, bestErr, single, n = nil, L.ATTACK_TOLERANCE, nil, 0
    for i = 1, #TOKENS do
        if tokOnMe[i] then
            local guid, seen = tokGUID[i], false
            for j = 1, i - 1 do
                seen = seen or (tokOnMe[j] and tokGUID[j] == guid)
            end
            if not seen then
                n, single = n + 1, i
                local k = find(guid)
                local period = tokSpeed[i]
                if period <= 0 and k then
                    period = atkPeriod[k]
                end
                local err = clockError(k, period, t)
                if melee and err <= bestErr then
                    best, bestErr = i, err
                end
            end
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
    local src, dst = tokGUID[best], L.player
    if melee then -- a spell does not follow the swing clock: no clock made or moved for it
        learn(clockOf(src), t, tokSpeed[best])
    end
    if act == "WOUND" and melee then
        local r = L.Emit("SWING_DAMAGE", 21, t, true, "onus", "inferred", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS)
        r[12], r[13], r[14], r[15], r[16], r[17] = type(amount) == "number" and amount or 0, 0, 1, 0, 0, 0
        r[18], r[19], r[20], r[21] = flag == "CRITICAL", flag == "GLANCING", flag == "CRUSHING", false
    elseif act == "WOUND" then
        local r = L.Emit("SPELL_DAMAGE", 24, t, true, "onus", "inferred", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS)
        local mask = type(school) == "number" and school or 1
        r[12], r[13], r[14], r[16], r[17], r[18] = 0, "", mask, 0, mask, 0
        r[15] = type(amount) == "number" and amount or 0
        r[19], r[20], r[21], r[22], r[23], r[24] = 0, 0, flag == "CRITICAL", false, false, false
    else
        local r = L.Emit("SWING_MISSED", 15, t, true, "onus", "inferred", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS)
        r[12], r[13], r[14], r[15] = act, false, 0, false
    end
end)

-- Combat end: the clocks lose their anchors (a new pull starts them again); learned periods stay.
S.On("PLAYER_REGEN_ENABLED", nil, function()
    for k = 1, N do
        atkAnchor[k] = 0
    end
end)

I.OnSnapshot(function(out)
    out[#out + 1] = string.format("rows unattributed hits on us=%d", L.unattributed)
end)
