-- Hekili_Shared/Races/HighOrderSkyborne.lua
-- The High Order Skyborne (Alliance; ChrRaces 95: wowsims tools/database/dbc/util.go:44-52, ui/sim/proto/utils.ts:62),
-- one of Forever's two Skyborne races (skill line 2980; the Windshaper, Horde, 96, has no file: its Skysight is a
-- movement utility). Its Forever racial (DB2 1.60.1.70338, SkillLineAbility 55323: RaceMasks_1 bit 32 only): Read Ley
-- Line (1259705: 2 s cast, on the GCD, 120 s), which grants Energized (1270842): on a mana user wowsims doubles the
-- whole mana regen, mp5 and spirit (MultiplyManaRegenSpeed(2)), for 30 s (sim/core/racials.go:204-241). The DB2 says
-- 15 s and +100% spirit regen (aura 110) and health regen (aura 88): wowsims followed (owner ruling, ledger SK1).
-- Shared passives (both Skyborne races): Wind Blessed (1259710; wowsims +3% attack and cast speed: the client's haste,
-- Hekili reads it) and Elemental Insight (1259707: +5% damage vs Elementals; no damage model). No resource maximum or
-- cost modifier. The UnitRace token is unconfirmed: the race ID decides (Engine/Schema/Races.lua).

local race = Hekili:NewRace("HighOrderSkyborne", 95)

race:RegisterAbility("read_ley_line", {
    id = 1259705,
    cast = 2,
    cooldown = 120,
    gcd = "spell",
    startsCombat = false,
    toggle = "cooldowns",

    handler = function()
        applyBuff("energized")
    end,
    -- The belief's now-state of the cast (event-facade spec §12a)
    now = function()
        applyBuff("energized")
    end,
})

race:RegisterAura("energized", {
    id = 1270842,
    duration = 30, -- wowsims racials.go:210; the DB2's SpellMisc says 15 s (DurationIndex 8)
    max_stack = 1,
})

-- the whole mana regen x 2 while Energized is up; a class with no mana resource (Warrior, Rogue) ignores it
race:RegisterRegenMod({ resource = "mana", aura = "energized", mult = 2 })
