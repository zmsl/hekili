-- VirtualState/Sources/Player.lua
-- Player sources (spec §4.2): combat start and end, movement, spell haste, the player's health (poll 1.5) and the
-- out-of-combat stat cache (login, PLAYER_REGEN_ENABLED, PLAYER_EQUIPMENT_CHANGED).
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Player.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, ReadOf = VS.Obs, I.ReadOf
local Plain, Stage, Direct, Note = S.Plain, S.Stage, S.Direct, S.Note

-- One stat call, read where it is called so the secrets check sees every client read. Allocates nothing.
local function statCall(api, name, arg)
    if name == "UnitStat" then
        return api.UnitStat("player", arg) -- secret: readStat tests every return with issecretvalue
    elseif name == "GetSpellBonusDamage" then
        return api.GetSpellBonusDamage(arg) -- secret: readStat tests every return
    elseif name == "UnitAttackPower" then
        return api.UnitAttackPower("player") -- secret: readStat tests every return
    elseif name == "UnitWeaponAttackPower" then
        return api.UnitWeaponAttackPower("player") -- secret: readStat tests every return
    elseif name == "UnitDamage" then
        return api.UnitDamage("player") -- secret: readStat tests every return
    elseif name == "UnitArmor" then
        return api.UnitArmor("player") -- secret: readStat tests every return
    elseif name == "GetMasteryEffect" then
        return api.GetMasteryEffect() -- secret: readStat tests every return
    elseif name == "GetCritChance" then
        return api.GetCritChance() -- secret: readStat tests every return
    elseif name == "GetSpellCritChance" then
        return api.GetSpellCritChance("player") -- secret: readStat tests every return
    elseif name == "GetRangedCritChance" then
        return api.GetRangedCritChance() -- secret: readStat tests every return
    elseif name == "GetCombatRating" then
        return api.GetCombatRating(arg) -- secret: readStat tests every return
    elseif name == "GetCombatRatingBonus" then
        return api.GetCombatRatingBonus(arg) -- secret: readStat tests every return
    end
end

-- One stat call's returns into its cache slot, only when every return is plain. Allocates nothing.
local function readStat(api, i, t)
    local e = I.STATS[i]
    local r1, r2, r3, r4, r5, r6, r7 = statCall(api, e[1], e.arg) -- secret: tested with issecretvalue below
    if
        api.issecretvalue(r1)
        or api.issecretvalue(r2)
        or api.issecretvalue(r3)
        or api.issecretvalue(r4)
        or api.issecretvalue(r5)
        or api.issecretvalue(r6)
        or api.issecretvalue(r7)
    then
        Note("stats", "secret")
        return
    end
    local v = I.statVal[i]
    v[1], v[2], v[3], v[4] = Plain(api, r1) or 0, Plain(api, r2) or 0, Plain(api, r3) or 0, Plain(api, r4) or 0
    v[5], v[6], v[7] = Plain(api, r5) or 0, Plain(api, r6) or 0, Plain(api, r7) or 0
    I.statT[i] = t
    Note("stats", "readable")
end

local function readStats(api, t)
    if I.inCombat then
        return
    end
    for i = 1, #I.STATS do
        local e = I.STATS[i]
        -- a client without this function or CR_* constant: skip, the slot keeps its zeros
        if api[e[1]] ~= nil and (type(e[2]) ~= "string" or e.arg ~= nil) then
            readStat(api, i, t)
        end
    end
end

local function readSpellHaste(api, t, direct)
    local raw = api.UnitSpellHaste("player") -- secret: Plain next
    Note("UnitSpellHaste", S.StatusOf(api, raw))
    local v = Plain(api, raw)
    if type(v) == "number" then
        if direct then
            Direct(Obs.Haste, t, 0, v, 2)
        else
            Stage(Obs.Haste, t, 0, v, 2)
        end
    end
end

S.OnStart(function(api, t)
    -- the stat arguments: the CR_* constants as this client defines them (a missing one is skipped: zeros)
    Note("stats CR_* constants", "complete")
    for i, e in ipairs(I.STATS) do
        local arg = e[2]
        if type(arg) == "string" then
            arg = api[arg] -- a CR_* constant (a number), not a client function
        end
        e.arg = arg
        local byArg = I.statIndex[e[1]] or {}
        I.statIndex[e[1]] = byArg
        if arg ~= nil or e[2] == nil then
            byArg[arg or 0] = i
        else
            Note("stats CR_* constants", "partial")
        end
    end
    I.inCombat = Plain(api, api.InCombatLockdown()) == true
    I.class = Plain(api, api.UnitClassBase("player"))
    readStats(api, t)
    readSpellHaste(api, t, true)
end)

S.On("PLAYER_REGEN_DISABLED", nil, function(api, t)
    I.inCombat = true
    Stage(Obs.CombatStart, t)
end)

S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    I.inCombat = false
    Stage(Obs.CombatEnd, t)
    readStats(api, t)
    readSpellHaste(api, t)
end)

S.On("PLAYER_EQUIPMENT_CHANGED", nil, function(api, t)
    readStats(api, t)
end)

S.On("PLAYER_STARTED_MOVING", nil, function(api, t)
    Stage(Obs.Moving, t, 0, 1)
end)

S.On("PLAYER_STOPPED_MOVING", nil, function(api, t)
    Stage(Obs.Moving, t, 0, 0)
end)

S.On("UNIT_SPELL_HASTE", "player", function(api, t, unit)
    if unit == "player" then
        readSpellHaste(api, t)
    end
end)

-- Poll 1.5: the player's health, when plain (unprobed on Forever, cleanup Q11), and its maximum.
S.Poll(1.5, function(api, t)
    local rawMax = api.UnitHealthMax("player") -- secret: Plain next
    local max = Plain(api, rawMax)
    if type(max) == "number" and max > 0 then
        I.healthMax = max
    end
    local raw = api.UnitHealth("player") -- secret: Plain next
    Note("UnitHealth player", S.StatusOf(api, raw))
    local v = Plain(api, raw)
    if type(v) == "number" and I.healthMax > 0 then
        Direct(Obs.Read, t, 0, v / I.healthMax, ReadOf.Health) -- nonzero: healthMax > 0 checked
    end
end)
