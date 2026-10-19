-- Game/State/Sources/Swing.lua
-- Swing sources (spec §4.2): PLAYER_SWING (payload swingDuration, swingType; plain in combat) is a `Swing` with
-- a = swingType + 1, b = the duration, c = 4 ("swung": the swing clock's; it fires on avoided swings too, so it
-- pays nothing: Game/Events/Rows.lua stages c = 1, landed, when the swing's wound arrives), staged on the urgent
-- lane (Hekili's `state.swings` come from the swing rows, Game/Events/Rows.lua). Out of combat,
-- UNIT_ATTACK_SPEED and PLAYER_EQUIPMENT_CHANGED (and login, and combat end) read both hands' speeds (c = 0), the
-- unhasted base speeds (c = 2, speed x (1 + melee haste / 100)) and the melee haste multiplier (`Haste`, c = 1).
-- The ranged hand (a = 3, class-completion C7): swingType 2 (UNMEASURED: whether Forever fires it is a checkpoint) and
-- UnitRangedDamage's speed (c = 0, the stat cache's) out of combat on the same events.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Swing.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Note = S.Plain, S.Stage, S.Note

S.On("PLAYER_SWING", nil, function(api, t, duration, swingType)
    if type(duration) ~= "number" or type(swingType) ~= "number" or swingType > 2 then
        return
    end
    local hand = swingType + 1
    Stage(Obs.Swing, t, hand, duration, 4)
    S.Urgent("PLAYER_SWING")
end)

-- Both hands' speeds, base speeds and the melee haste, when plain (out of combat in practice). Allocates nothing.
local function readSpeeds(api, t)
    local rawMain, rawOff = api.UnitAttackSpeed("player") -- secret: tested with issecretvalue, read through Plain
    if api.issecretvalue(rawMain) or api.issecretvalue(rawOff) then
        Note("UnitAttackSpeed", "secret")
        return
    end
    local main, off = Plain(api, rawMain), Plain(api, rawOff)
    Note("UnitAttackSpeed", type(main) == "number" and "readable" or "nil")
    main = type(main) == "number" and main > 0 and main or 0
    off = type(off) == "number" and off > 0 and off or 0
    Stage(Obs.Swing, t, 1, main, 0)
    Stage(Obs.Swing, t, 2, off, 0)
    local p = Plain(api, api.GetMeleeHaste())
    if type(p) == "number" and p > -100 then
        local k = 1 + p / 100
        Stage(Obs.Haste, t, 0, k, 1)
        Stage(Obs.Swing, t, 1, main * k, 2)
        Stage(Obs.Swing, t, 2, off * k, 2)
    end
end

-- The ranged hand's speed: UnitRangedDamage's first return from the stat cache (Sources/Player.lua reads it first on
-- the same events, through issecretvalue and Plain; zeros before a plain read or on a client without it).
-- shortcut: ranged haste in combat is unread (the speed stays the out-of-combat one until a swingType 2 duration);
-- upgrade with a ranged-haste read when a pack gates on the ranged clock.
local function readRanged(t)
    local speed = VS.Stat("UnitRangedDamage")
    Stage(Obs.Swing, t, 3, speed > 0 and speed or 0, 0)
end

local function outOfCombat(api, t)
    if not I.inCombat then
        readSpeeds(api, t)
        readRanged(t)
    end
end
S.On("UNIT_ATTACK_SPEED", "player", outOfCombat)
S.On("PLAYER_EQUIPMENT_CHANGED", nil, outOfCombat)
S.On("PLAYER_REGEN_ENABLED", nil, outOfCombat)
S.OnStart(outOfCombat)
-- Build clears what the start read staged (PLAYER_LOGIN precedes the first build): read again
I.OnBuild(function(_, now)
    if I.api then
        outOfCombat(I.api, now)
    end
end)
