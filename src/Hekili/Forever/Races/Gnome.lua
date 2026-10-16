-- Forever/Races/Gnome.lua
-- The Gnome's Forever racials (DB2 1.60.1.70338): Eureka! (15 s: the next 3 abilities in its scope cost 10% less,
-- +10% damage not modelled; 120 s, off the GCD; one ID per class: 1259813 Warrior, 1259812 Rogue, 1259817 Mage,
-- 1259821 Warlock, 1259823 Priest), Expansive Mind (+5% maximum resources: 20591 Priest/Mage/Warlock, 1259802
-- Warrior, 1259803 Rogue) and Escape Artist (20589: roots and snares removed, immune for 3 s; 120 s, on the GCD).
-- Engineering Specialization is a profession passive. Inert for any other race (Races.lua).

local addon, ns = ...
local Hekili = _G[ addon ]

local race = Hekili:NewRace( "Gnome" )

local EUREKA = { 1259812, 1259817, 1259821, 1259823 } -- the other classes' Eureka!

-- Eureka!'s cost scope (its effect 0: aura 108 misc 14 -10, class masks against the class's SpellClassSet) by class
-- file: rank-1 IDs of the class's skill-line spells the masks cover, from
-- select distinct o.SpellID, n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID
--   join SpellPower p on p.SpellID=o.SpellID join spell_skill k on k.spell_id=o.SpellID where o.SpellClassSet=<set>
--   and not (((o.SpellClassMask_0 & 4294967295)&<m0>)=0 and ((o.SpellClassMask_1 & 4294967295)&<m1>)=0
--   and ((o.SpellClassMask_2 & 4294967295)&<m2>)=0)
-- (no ManaCost filter: a percent cost reads 0 there). Higher ranks resolve through the class's `copy` lists; an ID the
-- loaded class does not register is absent (Races.lua, Modifiers.lua). Not listed: Rebuke 425609 (a Paladin spell in
-- the Rogue's set), Felfire 24530 (no class), the Warrior's Execute 20647 (the triggered damage: no GCD, no rank; the
-- cast is 5308's ranks).
local EUREKA_SPELLS = {
    -- set 4, masks 1784679630 / 5 / 1: Heroic Strike, Cleave, Slam, Execute, Overpower, Mortal Strike, Bloodthirst,
    -- Whirlwind, Shield Slam, Revenge, Thunder Clap, Hamstring, Intercept, Mocking Blow, Pummel, Shield Bash, Spearing
    -- Strike, Quick Strike. Not: Rend, Sunder Armor, the shouts, Concussion Blow, Death Wish, Disarm, Retaliation, Shield
    -- Block.
    WARRIOR = {
        78, 845, 1240193, 5308, 7384, 12294, 23881, 1680, 23922, 6572, 6343, 1715, 20252, 694, 6552, 72, 1310222, 429765,
    },
    -- set 8, masks 100794910 / 2097408 / 0: Ambush, Backstab, Eviscerate, Ghostly Strike, Gouge, Hemorrhage, Kick,
    -- Mutilate, Riposte, Sinister Strike
    ROGUE = { 8676, 53, 2098, 14278, 1776, 16511, 1766, 1310707, 14251, 1752 },
    -- set 3, masks 549591799 / 4096 / 0: Arcane Blast, Arcane Explosion, Arcane Missiles, Blast Wave, Blizzard, Cone of
    -- Cold, Fire Blast (both), Fireball, Flamestrike, Frost Nova, Frostbolt, Frostfire Bolt, Ice Lance, Pyroblast, Scorch
    MAGE = { 400574, 1449, 5143, 11113, 10, 120, 2136, 400618, 133, 2120, 122, 116, 401502, 1312002, 11366, 2948 },
    -- set 5, masks 541165 / 8650880 / 0: Conflagrate, Death Coil, Drain Life (both), Drain Soul, Hellfire, Immolate,
    -- Rain of Fire, Searing Pain, Shadow Bolt, Shadowburn, Soul Fire, Wrack
    WARLOCK = { 1293817, 6789, 689, 403677, 1120, 1949, 348, 5740, 5676, 686, 17877, 6353, 1316697 },
    -- set 6, masks 150224528 / 8388614 / 0: Binding Heal, Flash Heal, Greater Heal, Heal, Holy Fire, Holy Nova, Lesser
    -- Heal, Mana Burn, Mind Blast, Mind Flay, Penance, Prayer of Healing, Shadow Word: Death (both), Smite, Starshards
    PRIEST = { 401937, 2061, 2060, 2054, 14914, 15237, 2050, 8129, 8092, 15407, 402174, 596, 401955, 1309595, 585, 10797 },
}

race:RegisterAbility( "eureka", {
    id = 1259813,
    copy = EUREKA,
    cast = 0,
    cooldown = 120,
    gcd = "off",
    startsCombat = false,
    toggle = "cooldowns",

    handler = function ()
        applyBuff( "eureka", 15, 3 )
    end,
    -- VirtualState's now-state of the cast (event-facade spec §12a)
    now = function ()
        applyBuff( "eureka", 15, 3 )
    end,
} )

race:RegisterAura( "eureka", {
    id = 1259813,
    copy = EUREKA,
    duration = 15,
    max_stack = 3,
} )

race:RegisterAbility( "escape_artist", {
    id = 20589,
    cast = 0,
    cooldown = 120,
    gcd = "spell",
    startsCombat = false,
    toggle = "defensives",

    handler = function ()
        applyBuff( "escape_artist" )
    end,
    now = function ()
        applyBuff( "escape_artist" )
    end,
} )

race:RegisterAura( "escape_artist", {
    id = 20589,
    duration = 3,
    max_stack = 1,
} )

race:RegisterResourceMod( { max = 0.05 } ) -- Expansive Mind: +5% maximum resources

-- The loaded class's scope (Classes.lua sets class.file before any race file runs); a class with no Eureka! (none
-- exists for a Hunter, Shaman, Paladin or Druid) declares no cost modifier.
local spells = EUREKA_SPELLS[ Hekili.Class.file ]
if spells then
    race:RegisterCostMod( {
        aura = "eureka",
        pct = -0.10,
        charges = 3,
        spells = spells,
    } )
end
