-- Hekili_Warlock/Warlock.lua
-- The Forever Warlock (Affliction, Demonology and Destruction, one spec a talent tree: Hekili:NewClass): the Warlock
-- kit with Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build
-- 1.60.1.70338, wowdb), mana under the five-second rule (`fsr`), the casts and the five channels (Drain Life, Drain
-- Soul, Wrack, Rain of Fire, Hellfire: `channeled`, `tick_time`; unhasted, as wowsims's rows), the DoTs, Banes and
-- Curses on the target from our casts (one Bane and one Curse a target: each removes the others), Soul Shards as an
-- item count (`soul_shards`, item 6265: Soul Fire, Shadowburn and the summons need one), Life Tap's mana (its rank's
-- amount, its level gain and Spirit, Improved Life Tap's +10% a rank), the demon (RegisterPets: the five summons;
-- Demonic Sacrifice's effects, ended by a summon unless Demonic Pact keeps another demon's), Nightfall's Shadow
-- Trance (an instant Shadow Bolt), Decimation (a faster Soul Fire with no shard; its talent's shorter cooldown),
-- Demonic Sacrifice (the demon out for its effect), Amplify Curse (spent by Bane of Agony and Curse of Weakness),
-- Conflagrate on our Immolate (consumed unless Shadow and Flame keeps it), Demonic Brand from Searing Pain, Wrack's
-- debuff, the talents' cast and cost cuts (Bane, Improved Corruption, Cataclysm, Master Summoner), and the school
-- lockouts (Hekili_Shared's locked_out_<school>). The priorities are the five wowsims.com packs in APLs/packs.lua
-- (Affliction, SM Ruin, Demonology, Shadow Brand, Destruction); the abilities and auras below are what wowsims/forever's
-- five Warlock builds (ui/specs/warlock/dps/builds/*.build.json) cast or read.
-- Research: docs/research/2026-10-15-forever-warlock/research.md.
-- From wowsims/forever's data (MIT, https://github.com/wowsims/forever; sim/warlock/ and sim/core/spelldata), where the
-- Forever DB2 at 70338 lacks it: the live talent tree (ui/sim/talents/trees/warlock.json: its 52 nodes, their trees and
-- ranks; the DB2's Talent table is the older one), the talents' per-rank values (spells_auto_gen.go's curves: the DB2
-- carries the top rank's on rank 1), the Soul Shard reagents (soul_shards.go useReagents: Soul Fire, Shadowburn, the
-- Voidwalker, Succubus, Incubus and Felhunter), the demon each Demonic Sacrifice effect belongs to
-- (talents_demonology.go: Imp 18789, Felhunter 18790, Succubus 18791, Voidwalker 18792; the Incubus, absent from
-- wowsims, as the Succubus: the same Sayaad), the base mana (1373 at 60: base_stats_auto_gen.go) and the starting regen
-- (the five builds' logs at 60, preraid gear).
-- Not on Forever (the DB2 has no row): Backlash, Dark Pact, Curse of Shadow; Curse of Agony and Doom are Banes.
-- The demon's mana is the client's (`pet.mana`: UnitPower("pet"), plain; central fix 27), read, not predicted.
-- Unmodelled: the procs' rolls (Nightfall's Shadow Trance, Revelation: the player aura walk reads them where plain,
-- the spell's glow in combat; Decimation is also applied by a Shadow Bolt or Searing Pain the simulation lands on a
-- target under 35% health, which is secret on Forever), Shadow and Flame's shard refund (its buffs are applied), the
-- shard a kill or Drain Soul returns, the sim's spent
-- shards (a list evaluation reads the bag count; two shard spells in one queue may outrun it: gaps.md's reagent
-- prediction), Life Tap's health and Demonic Energies' share of it to the demon, the demon's spells (Firebolt
-- 3110-11763, 10-115 mana; Lash of Pain 7814-11780, 65-160 mana: pet-bar, D6), Bane of Havoc's 15% damage share,
-- Curse of Exhaustion and Tongues, Soul Harvest's regen, and pushback; the armors, Fel
-- Domination, Soul Link and the other demon auras are registered, read where plain, never cast.
-- Credits: Hekili (registration API and pack format). wowsims/forever (MIT) is the reference for the mechanics above;
-- no code is copied.

local Facade = Hekili.Client
local UnitClassBase = Facade.UnitClassBase
local GetItemCount = Facade.C_Item.GetItemCount
local L = Hekili:GetLocale("Hekili_Warlock")

if UnitClassBase("player") ~= "WARLOCK" then
    return
end

local state = Hekili.State
local floor = math.floor

-- The class kit and one spec a talent tree (ids the core's: Affliction 100091, Demonology 100092, Destruction 100093;
-- the client's one pseudo-spec, assumed 1490, only keys the legacy profile the core migrates). Icons: the DB2 talent
-- tabs'. Each spec's package is its wowsims.com pack (APLs/packs.lua).
local spec = Hekili:NewClass("WARLOCK", {
    specs = {
        {
            key = "affliction",
            name = L["Affliction"],
            tree = 1,
            icon = 136145,
            role = "attack",
            ranged = true,
            package = "Affliction (wowsims.com)",
        },
        {
            key = "demonology",
            name = L["Demonology"],
            tree = 2,
            icon = 136172,
            role = "attack",
            ranged = true,
            package = "Demonology (wowsims.com)",
            movement = true, -- the Demonology and Shadow Brand packs read toggle.movement: the move reaches Hellfire (R8)
        },
        {
            key = "destruction",
            name = L["Destruction"],
            tree = 3,
            icon = 136186,
            role = "attack",
            ranged = true,
            package = "Destruction (wowsims.com)",
            movement = true, -- the Destruction pack's Hellfire line reads toggle.movement (re-pin e5a9cd2a2d, R8)
        },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's), each rank's mana cost, cast time or duration.
local SHADOW_BOLT = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 }
local SHADOW_BOLT_COST = { 25, 40, 70, 110, 160, 210, 265, 315, 370, 380 }
local SHADOW_BOLT_CAST = { 1.7, 2.2, 2.8, 3, 3, 3, 3, 3, 3, 3 }
local IMMOLATE = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 }
local IMMOLATE_COST = { 25, 45, 90, 155, 220, 295, 370, 380 }
local CORRUPTION = { 172, 6222, 6223, 7648, 11671, 11672, 25311 }
local CORRUPTION_COST = { 35, 55, 100, 160, 225, 290, 340 }
local CORRUPTION_DURATION = { 12, 15, 18, 18, 18, 18, 18 }
local BANE_OF_AGONY = { 980, 1014, 6217, 11711, 11712, 11713 }
local BANE_OF_AGONY_COST = { 25, 50, 90, 130, 170, 215 }
local CURSE_OF_THE_ELEMENTS = { 440892, 1311676, 1311677, 1311680 } -- Forever's own (class mask 0 in spell_skill)
local CURSE_OF_THE_ELEMENTS_COST = { 50, 100, 150, 200 }
local CURSE_OF_RECKLESSNESS = { 704, 7658, 7659, 11717 }
local CURSE_OF_RECKLESSNESS_COST = { 35, 60, 90, 115 }
local CURSE_OF_WEAKNESS = { 702, 1108, 6205, 7646, 11707, 11708 }
local CURSE_OF_WEAKNESS_COST = { 20, 35, 70, 95, 130, 175 }
local SIPHON_LIFE = { 18265, 18879, 18880, 18881 }
local SIPHON_LIFE_COST = { 150, 205, 285, 365 }
local DRAIN_LIFE = { 689, 699, 709, 7651, 11699, 11700 } -- the 403677-403689 family (15 s, SoD) is not Forever's
local DRAIN_LIFE_COST = { 55, 85, 135, 185, 240, 300 }
local DRAIN_SOUL = { 1120, 8288, 8289, 11675 }
local DRAIN_SOUL_COST = { 55, 125, 210, 290 }
local DEATH_COIL = { 6789, 17925, 17926 }
local DEATH_COIL_COST = { 435, 525, 600 }
local CONFLAGRATE = { 1293817, 1293818, 17962, 18930, 18931, 18932 }
local CONFLAGRATE_COST = { 100, 130, 165, 200, 230, 255 }
local SHADOWBURN = { 17877, 18867, 18868, 18869, 18870, 18871 }
local SHADOWBURN_COST = { 105, 130, 190, 245, 305, 365 }
local SEARING_PAIN = { 5676, 17919, 17920, 17921, 17922, 17923 }
local SEARING_PAIN_COST = { 45, 68, 91, 118, 141, 168 }
local INCINERATE = { 412758, 1293812, 1293813 }
local INCINERATE_COST = { 205, 265, 325 }
local SOUL_FIRE = { 6353, 17924 }
local SOUL_FIRE_COST = { 305, 335 }
local RAIN_OF_FIRE = { 5740, 6219, 11677, 11678 }
local RAIN_OF_FIRE_COST = { 295, 605, 885, 1185 }
local HELLFIRE = { 1949, 11683, 11684 }
local HELLFIRE_COST = { 645, 975, 1300 }
-- Life Tap: effect 0's points by rank and each rank's base level; +1 a level to ten above it (DB2 per_level 1,
-- MaxLevel = BaseLevel + 10; wowsims lifetap.go: base + Spirit of health into as much mana, x Improved Life Tap).
local LIFE_TAP = { 1454, 1455, 1456, 11687, 11688, 11689 }
local LIFE_TAP_POINTS = { 20, 65, 130, 210, 300, 420 }
local LIFE_TAP_LEVEL = { 6, 16, 26, 36, 46, 56 }

-- The talents' per-rank values (wowsims's curves; the DB2 carries the top rank's on rank 1): Cataclysm 3/6/10% off
-- the Destruction spells' cost (17778; DB2 mask: Shadow Bolt, Immolate, Rain of Fire, Soul Fire, Hellfire, Shadowburn,
-- Searing Pain, Conflagrate, Incinerate; wowsims's logs: 342 = 380 x 0.9 at 3/3).
local CATACLYSM = { 0.03, 0.06, 0.1 }

local SOUL_SHARD = 6265 -- the item (ItemSparse)

local function rest(ids)
    local out = {}
    for i = 2, #ids do
        out[#out + 1] = ids[i]
    end
    return out
end

-- The highest known rank of a rank list, from the belief's spellbook: the same answer in the sim's `state`
-- environment and in a `now` handler's (event-facade spec §12a).
local knownRank = state.knownRank

local function knows(ids)
    return function()
        return knownRank(ids) > 0
    end
end

local function byRank(values, ids)
    return function()
        return values[knownRank(ids)] or values[1]
    end
end

-- The same, less Cataclysm's cut (DB2 17778 effect 0: aura 108 misc 14, a cost percent).
local function cataclysmic(values, ids)
    return function()
        local r = talent.cataclysm.rank
        return (values[knownRank(ids)] or values[1]) * (1 - (CATACLYSM[min(r, 3)] or 0))
    end
end

-- Doomcaller's Attire (AQ, set 499, db.json setId; sim/warlock/item_sets.go): five pieces; the 3-piece 26116 (Immolate's
-- damage) and the 5-piece 26117 (Shadow Bolt -15% mana, a percent modifier added to Cataclysm's: DB2 effect 702131).
local DOOMCALLER = { 21334, 21335, 21336, 21337, 21338 }
spec:RegisterGear("doomcaller", unpack(DOOMCALLER))
spec:RegisterSetBonus("doomcaller_3pc", 26116)
spec:RegisterSetBonus("doomcaller_5pc", 26117)

-- Shadow Bolt's mana: Cataclysm's cut and the Doomcaller 5-piece's.
local function boltCost()
    return function()
        local cut = (CATACLYSM[min(talent.cataclysm.rank, 3)] or 0) + (set_bonus.doomcaller_5pc > 0 and 0.15 or 0)
        return (SHADOW_BOLT_COST[knownRank(SHADOW_BOLT)] or SHADOW_BOLT_COST[1]) * (1 - cut)
    end
end

-- A cast time less Bane's 0.1 s a rank (DB2 17788 effect 0: aura 107 misc 10 on Shadow Bolt, Immolate and Incinerate),
-- hasted. `base`: a number, or a table by rank of `ids`. The reads are arguments: a field function's caller passes its
-- own `talent` and `haste` (Hekili setfenv's only the field function itself, never a closure it calls).
local function banedTime(base, ids, bane, h)
    local b = ids and (base[knownRank(ids)] or base[1]) or base
    return (b - 0.1 * bane) * h
end
local function baned(base, ids)
    return function()
        return banedTime(base, ids, talent.bane.rank, haste)
    end
end

-- Each spell refuses while an interrupt has its school locked out (Hekili_Shared's locked_out_<school>, C10); in the
-- belief's `now` context the names are absent: never locked.
local function unlocked(school)
    if school == "fire" then
        return function()
            return not locked_out_fire, "fire locked out"
        end
    end
    return function()
        return not locked_out_shadow, "shadow locked out"
    end
end

-- A shard spell's `usable`: a Soul Shard in the bags (the client's count, read here so the belief's `now` context, the
-- cost ladder's precondition, has it too), or `waived` up (Decimation's A_NO_REAGENT_USE on Soul Fire), and its
-- school unlocked (the lockout read here: a nested closure would not run in the engine's environment).
local function sharded(fire, waived)
    return function()
        if GetItemCount(SOUL_SHARD) < 1 and not (waived and buff[waived].up) then
            return false, "no soul shard"
        end
        if fire then
            return not locked_out_fire, "fire locked out"
        end
        return not locked_out_shadow, "shadow locked out"
    end
end

-- The five-second rule (C3): spirit and mp5 regen per second, the declared starting point the out-of-combat read and
-- the in-combat calibration replace: wowsims's logs at 60 (re-pin e2842f0a78: the four Human builds on the preraid
-- gear, 1.52 a 0.1 s tick inside the rule, 5.333 outside it, Blessing of Wisdom's mp5 included; was the Orc builds'
-- 1.04 / 4.428, Affliction's still 1.12 / 4.433). UNMEASURED in game.
-- Fel Energy (the Voidwalker sacrifice, aura 18792, DB2 aura 21: 2 every 4000 ms; wowsims talents_demonology.go:168-185):
-- 2% of max mana every 4 s while it is up, the tick times counted from its application.
spec:RegisterResource(
    Enum.PowerType.Mana,
    {
        fel_energy = {
            aura = "fel_energy",

            last = function()
                local app = state.buff.fel_energy.applied
                return app + 4 * floor((state.query_time - app) / 4)
            end,

            interval = 4,
            value = function()
                local max = mana and mana.max
                return type(max) == "number" and 0.02 * max or 0 -- inert before the first read
            end,
        },
    },
    nil,
    {
        fsr = { spirit = 38.13, mp5 = 15.2 },
        base = 1373, -- a fraction cost is of base mana (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
    }
)

-- The Soul Shards in the bags (plain [W PR13]); read live each evaluation.
-- shortcut: a shard spell the simulation casts spends none (no bag write in the sim; gaps.md's reagent prediction), so
-- two in one queue may outrun the count; upgrade with a sim-side spent counter if a pack queues two (wowsims's builds
-- carry 32).
spec:RegisterStateExpr("soul_shards", function()
    return GetItemCount(SOUL_SHARD)
end)

-- The Curses and the Banes: one of each per Warlock per target (wowsims warlock.go deactivateOtherCurses/Banes).
local CURSES =
    { "curse_of_the_elements", "curse_of_recklessness", "curse_of_weakness", "curse_of_tongues", "curse_of_exhaustion" }
local BANES = { "bane_of_agony", "bane_of_doom" }

-- The Demonic Sacrifice effect each demon leaves (the demons' creature IDs: the summons' effect 0, DB2).
local SACRIFICE = {
    imp = "burning_shadow",
    voidwalker = "fel_energy",
    succubus = "touch_of_fire",
    incubus = "touch_of_fire",
    felhunter = "fel_stamina",
}
local SACRIFICES = { "burning_shadow", "fel_stamina", "touch_of_fire", "fel_energy" }
local DEMONS = { "imp", "voidwalker", "succubus", "incubus", "felhunter" }

-- The demon out in the simulation's `pet` (nil: none, or the belief's `now` context, which has no `pet`).
local function demonOut(p)
    for i = 1, p and #DEMONS or 0 do
        if p[DEMONS[i]].up then
            return DEMONS[i]
        end
    end
end

spec:RegisterPets({
    imp = { id = 416, spell = "summon_imp", duration = 3600 },
    voidwalker = { id = 1860, spell = "summon_voidwalker", duration = 3600 },
    succubus = { id = 1863, spell = "summon_succubus", duration = 3600 },
    incubus = { id = 185317, spell = "summon_incubus", duration = 3600 },
    felhunter = { id = 417, spell = "summon_felhunter", duration = 3600 },
})

local function corruptionDuration()
    return CORRUPTION_DURATION[knownRank(CORRUPTION)] or 18
end

spec:RegisterAuras({
    -- The target's (unreadable in combat), modelled from our casts.
    corruption = {
        id = 172,
        copy = rest(CORRUPTION),
        duration = corruptionDuration,
        max_stack = 1,
    },
    immolate = { id = 348, copy = rest(IMMOLATE), duration = 15, max_stack = 1 },
    bane_of_agony = { id = 980, copy = rest(BANE_OF_AGONY), duration = 24, max_stack = 1 },
    bane_of_doom = { id = 603, duration = 60, max_stack = 1 },
    curse_of_the_elements = { id = 440892, copy = rest(CURSE_OF_THE_ELEMENTS), duration = 300, max_stack = 1 },
    curse_of_recklessness = { id = 704, copy = rest(CURSE_OF_RECKLESSNESS), duration = 120, max_stack = 1 },
    curse_of_weakness = { id = 702, copy = rest(CURSE_OF_WEAKNESS), duration = 120, max_stack = 1 },
    siphon_life = { id = 18265, copy = rest(SIPHON_LIFE), duration = 30, max_stack = 1 },
    wrack = { id = 1316697, duration = 6, max_stack = 1 }, -- the channel's debuff: +10% from Corruption and Agony
    -- Searing Pain's brand (Demonic Brand 1293695): 10 s, 2 charges a rank (wowsims's curve; its logs land 6 at 3/3).
    -- shortcut: the demon's attacks spend the charges (unseen); the model keeps them all for the 10 s.
    demonic_brand = { id = 1293696, duration = 10, max_stack = 6 },
    -- Improved Shadow Bolt's (a Shadow Bolt crit's: the belief's own crit, Shadow Bolt's `onCrit`).
    shadow_vulnerability = { id = 17794, duration = 12, max_stack = 1 },

    -- Bane of Havoc's (1225228, 300 s; wowsims bane_of_havoc.go): one target at a time, never the main one (the pack's
    -- other_target=1 line, option D).
    bane_of_havoc = { id = 1225228, copy = { 1324473 }, duration = 300, max_stack = 1 }, -- 1324473: the client's buff

    -- The player's. The procs (their rolls unseen; the player aura walk reads them where plain, in combat the glow of
    -- the spell they light: `overlay`, needs in-game check): Nightfall's next Shadow Bolt instant; Decimation's
    -- faster Soul Fire with no shard (below 35% target health).
    shadow_trance = { id = 17941, duration = 10, max_stack = 1, overlay = 686 },
    decimation = { id = 440873, duration = 10, max_stack = 1, overlay = 6353 },
    amplify_curse = { id = 18288, duration = 30, max_stack = 1 },
    -- The Doomcaller's Attire bonuses' hidden auras: tracked so set_bonus.doomcaller_* reads them.
    doomcaller_3pc = { id = 26116, duration = 3600, max_stack = 1 },
    doomcaller_5pc = { id = 26117, duration = 3600, max_stack = 1 },
    -- The weapon enchant 8217's proc (wowsims enchants.go revelationBuffs; each class has its own id): the next
    -- Shadow Bolt's crit chance +100%, one charge. A random proc: read, never predicted.
    revelation = { id = 1323392, duration = 15, max_stack = 1 },
    -- Shadow and Flame's (Conflagrate: the Shadow buff, Shadowburn: the Fire buff; wowsims talents_destruction.go; its
    -- names.json calls the first plain `shadow`).
    shadow_and_flame_shadow = { id = 1293816, duration = 20, max_stack = 1 },
    shadow_and_flame_fire = { id = 426311, duration = 20, max_stack = 1 },
    -- Drain Soul's kill buff (10 s, regen +100%): a kill's, no producer here (the Drain Soul line is in no priority).
    soul_harvest = { id = 1242853, copy = { 437032 }, duration = 10, max_stack = 1 }, -- 437032: the talent's, which the Cooldown Manager links
    -- No priority reads these (wowsims talents_demonology.go, armors.go): the player aura walk shows them where plain.
    fel_domination = { id = 18708, duration = 15, max_stack = 1 },
    soul_link = { id = 19028, copy = 25228, duration = 3600, max_stack = 1 },
    demonic_knowledge = { id = 412732, duration = 3600, max_stack = 1 },
    master_demonologist = { id = 23785, duration = 3600, max_stack = 1 }, -- one id for the four demons' effects
    demon_armor = { id = 11735, copy = { 706, 1086, 11733, 11734 }, duration = 1800, max_stack = 1 },
    blood_pact = { id = 11767, duration = 3600, max_stack = 1 },
    -- The channels' own auras (the kit models the channels: `channeled`).
    hellfire_channel = { id = 11684, duration = 15, max_stack = 1 },
    rain_of_fire_channel = { id = 11678, duration = 8, max_stack = 1 },
    drain_soul_channel = { id = 11675, duration = 15, max_stack = 1 },
    drain_life_channel = { id = 11700, duration = 5, max_stack = 1 },
    -- Demonic Sacrifice's effects (2 h; wowsims: until a summon cancels it).
    burning_shadow = { id = 18789, duration = 7200, max_stack = 1 },
    fel_stamina = { id = 18790, duration = 7200, max_stack = 1 },
    touch_of_fire = { id = 18791, duration = 7200, max_stack = 1 },
    fel_energy = { id = 18792, duration = 7200, max_stack = 1 },
    demonic_sacrifice = {
        alias = SACRIFICES,
        aliasMode = "first",
        aliasType = "buff",
        duration = 7200,
    },
})

-- The coverage lane's auras, each on the ID the Cooldown Manager links (CooldownViewer.lua build); durations from the
-- pin's spell rows at the top rank. The target's (Fear, Howl of Terror, Banish, Death Coil's horror, Subjugate Demon,
-- Aftermath's daze, the two curses) are never applied here but by our own casts below; the player's are the wards, armor,
-- Demon Skin and Detect Invisibility.
spec:RegisterAuras({
    fear = { id = 1324448, copy = { 1324451, 1324453 }, duration = 20, max_stack = 1 }, -- the client's ranks
    howl_of_terror = { id = 5484, copy = { 17928 }, duration = 15, max_stack = 1 },
    banish = { id = 1324462, copy = { 1324463 }, duration = 30, max_stack = 1 },
    death_coil = { id = 1324459, duration = 3, max_stack = 1 }, -- the horror
    subjugate_demon = { id = 1324468, duration = 300, max_stack = 1 },
    aftermath = { id = 18118, copy = { 18119 }, duration = 5, max_stack = 1 }, -- Conflagrate's daze
    curse_of_tongues = { id = 1714, copy = { 11719 }, duration = 30, max_stack = 1 },
    curse_of_exhaustion = { id = 18223, duration = 12, max_stack = 1 },
    shadow_ward = { id = 6229, copy = { 11739, 11740, 28610 }, duration = 30, max_stack = 1 },
    demon_skin = { id = 687, copy = { 696 }, duration = 1800, max_stack = 1 },
    detect_invisibility = { id = 132, copy = { 2970, 11743 }, duration = 600, max_stack = 1 },
})

-- A DoT's or Curse's `now` and `handler`: its debuff on the target, the others of its group (`group`: a Curse's or a
-- Bane's) removed, Amplify Curse spent (`amplified`: Bane of Agony and Curse of Weakness, DB2 18288 effect 0's mask;
-- wowsims: spent at the cast). `duration`: the debuff's when its aura's is a function (a `now` must pass it: the belief
-- writes nothing for a function duration, Families/Now.lua).
local function lands(key, group, amplified, duration)
    return function()
        for i = 1, group and #group or 0 do
            if group[i] ~= key then
                removeDebuff("target", group[i])
            end
        end
        applyDebuff("target", key, duration and duration())
        if amplified then
            removeBuff("amplify_curse")
        end
    end
end

-- Shadow Bolt's: Shadow Trance spent by an instant cast (wowsims talents_affliction.go), and Revelation's charge by
-- any cast (wowsims enchants.go: the next cast the crit modifier reaches).
-- In the belief `instant` is true only for a cast that started none (Families/Now.lua); the sim's cast time is 0 while
-- the buff is up, so its handler spends on the buff alone.
-- `sim`: the simulation's handler, which also reads the target's health for Decimation: a landed Shadow Bolt (or Searing
-- Pain) at a target under 35% (wowsims talents_demonology.go), and applies Shadow Vulnerability for Revelation's
-- guaranteed crit. The belief's `now` has no target to read (its health is secret on Forever: the glow read of
-- `decimation` carries it in game; the crit's own `onCrit` carries the vulnerability).
local function bolted(sim)
    if sim then
        return function()
            if buff.shadow_trance.up then
                removeBuff("shadow_trance")
            end
            if buff.revelation.up then
                removeBuff("revelation")
                if talent.improved_shadow_bolt.rank > 0 then
                    applyDebuff("target", "shadow_vulnerability")
                end
            end
            if talent.decimation.rank > 0 and target.health.pct < 35 then
                applyBuff("decimation")
            end
        end
    end
    return function()
        if instant and buff.shadow_trance.up then
            removeBuff("shadow_trance")
        end
        if buff.revelation.up then
            removeBuff("revelation")
        end
    end
end

-- Shadow Bolt's `onCrit` (the belief's own crit, Families/Now.lua): Improved Shadow Bolt's Shadow Vulnerability on the
-- target (DB2 17793; wowsims's logs: 17794 for 12 s after a crit), the only way the belief sees it.
local function vulnerable()
    return function()
        if talent.improved_shadow_bolt.rank > 0 then
            applyDebuff("target", "shadow_vulnerability")
        end
    end
end

-- Searing Pain's: Demonic Brand's charges on the target, 2 a rank.
-- `sim`: also Decimation at a target under 35%, as Shadow Bolt's (`bolted`).
local function branded(sim)
    if sim then
        return function()
            local r = talent.demonic_brand.rank
            if r > 0 then
                applyDebuff("target", "demonic_brand", nil, 2 * min(r, 3))
            end
            if talent.decimation.rank > 0 and target.health.pct < 35 then
                applyBuff("decimation")
            end
        end
    end
    return function()
        local r = talent.demonic_brand.rank
        if r > 0 then
            applyDebuff("target", "demonic_brand", nil, 2 * min(r, 3))
        end
    end
end

-- Conflagrate's: our Immolate consumed, unless Shadow and Flame keeps it (20% a rank, wowsims's curve); and with the
-- talent its Shadow damage buff.
-- shortcut: the roll is unseen; below 5/5 the Immolate is taken as consumed (an early recast at worst).
local function conflagrated()
    return function()
        if talent.shadow_and_flame.rank < 5 then
            removeDebuff("target", "immolate")
        end
        if talent.shadow_and_flame.rank > 0 then
            applyBuff("shadow_and_flame_shadow")
        end
    end
end

-- Shadowburn's: with Shadow and Flame its Fire damage buff (the shard refund is unmodelled).
local function burned()
    return function()
        if talent.shadow_and_flame.rank > 0 then
            applyBuff("shadow_and_flame_fire")
        end
    end
end

-- Life Tap's: its rank's points, the level gain, and Spirit (the belief's out-of-combat stat read) as mana, x Improved
-- Life Tap's +10% a rank (wowsims's logs: 774 = (424 + 221) x 1.2 at 2/2). The health is not tracked.
local function tapped()
    return function()
        local r = max(knownRank(LIFE_TAP), 1)
        local lvl = LIFE_TAP_LEVEL[r]
        local _, spirit = stat("UnitStat", 5)
        gain(
            (LIFE_TAP_POINTS[r] + min(max(level, lvl), lvl + 10) - lvl + spirit)
                * (1 + 0.1 * talent.improved_life_tap.rank),
            "mana"
        )
    end
end

-- A summon's: the demon (the belief models the pet unit up until its first observation; in the simulation the demon
-- out is dismissed first, the same demon included: wowsims summon.go), and Demonic Sacrifice's effect cancelled (any
-- demon's without Demonic Pact, the sacrificed demon's own with it).
local function summons(key)
    return function()
        removeBuff("fel_domination") -- the next summon spends it (wowsims talents_demonology.go applyFelDomination)
        local out = demonOut(pet) -- nil in the belief's `now` context (no `pet`)
        if out then
            dismissPet(out)
        end
        summonPet(key)
        local pact = talent.demonic_pact.enabled
        for i = 1, #SACRIFICES do
            if not pact or SACRIFICES[i] == SACRIFICE[key] then
                removeBuff(SACRIFICES[i])
            end
        end
    end
end

-- A summon: 10 s, -2 s and -20% cost a rank of Master Summoner (wowsims's curve; DB2 18709 mask: the five summons),
-- and Fel Domination's -5.5 s and -50% while its buff is up (DB2 18708 effects 0, 1, the same mask); unhasted; `cost` a fraction of base mana (PowerCostPct), `shard` its Soul Shard.
local function summon(key, id, cost, shard)
    return {
        id = id,
        cast = function()
            return max(0, 10 - 2 * talent.master_summoner.rank - (buff.fel_domination.up and 5.5 or 0))
        end,
        cooldown = 0,
        gcd = "spell",

        -- Fel Domination's -50% adds to Master Summoner's -20% a rank (both percent cost modifiers on the summons)
        spend = function()
            return cost * (1 - 0.2 * talent.master_summoner.rank - (buff.fel_domination.up and 0.5 or 0))
        end,
        spendType = "mana",
        spendBase = true, -- the 1 (100%) a fraction too

        startsCombat = false,
        known = knows({ id }),
        usable = shard and sharded() or unlocked("shadow"),

        now = summons(key),
        handler = summons(key),
    }
end

-- Demonic Sacrifice's: the demon out dismissed, every effect ended, the sacrificed demon's own up (wowsims
-- talents_demonology.go). The belief's `now` has no demon key: its dismissal is of the pet unit (any key) and the new
-- effect is the player aura walk's.
local function sacrifices()
    return function()
        local key = demonOut(pet)
        for i = 1, #SACRIFICES do
            removeBuff(SACRIFICES[i])
        end
        if key then
            applyBuff(SACRIFICE[key])
        end
        dismissPet(key or "demon")
    end
end

spec:RegisterAbilities({
    shadow_bolt = {
        id = 686,
        expects = "travel",
        velocity = 20,
        school = "shadow",
        copy = rest(SHADOW_BOLT),
        cast = function()
            if buff.shadow_trance.up then
                return 0 -- DB2 17941: -100% cast time on Shadow Bolt
            end
            return banedTime(SHADOW_BOLT_CAST, SHADOW_BOLT, talent.bane.rank, haste)
        end,
        cooldown = 0,
        gcd = "spell",

        spend = boltCost(),
        spendType = "mana",

        startsCombat = true,
        known = knows(SHADOW_BOLT),
        usable = unlocked("shadow"),

        now = bolted(false),
        handler = bolted(true),
        onCrit = vulnerable(),
    },

    immolate = {
        id = 348,
        copy = rest(IMMOLATE),
        cast = baned(2),
        cooldown = 0,
        gcd = "spell",

        spend = cataclysmic(IMMOLATE_COST, IMMOLATE),
        spendType = "mana",

        startsCombat = true,
        known = knows(IMMOLATE),
        usable = unlocked("fire"),
        missable = true,

        now = lands("immolate"),
        handler = lands("immolate"),
    },

    -- 2 s, -0.4 s a rank of Improved Corruption (wowsims's curve; DB2 17810 mask: Corruption); wowsims's logs: 0.8 s at
    -- 3/5, 0.4 s at 4/5.
    corruption = {
        id = 172,
        copy = rest(CORRUPTION),
        cast = function()
            return max(0, 2 - 0.4 * talent.improved_corruption.rank) * haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(CORRUPTION_COST, CORRUPTION),
        spendType = "mana",

        startsCombat = true,
        known = knows(CORRUPTION),
        usable = unlocked("shadow"),
        missable = true,

        now = lands("corruption", nil, nil, corruptionDuration),
        handler = lands("corruption", nil, nil, corruptionDuration),
    },

    bane_of_agony = {
        id = 980,
        copy = rest(BANE_OF_AGONY),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(BANE_OF_AGONY_COST, BANE_OF_AGONY),
        spendType = "mana",

        startsCombat = true,
        known = knows(BANE_OF_AGONY),
        usable = unlocked("shadow"),
        missable = true,

        now = lands("bane_of_agony", BANES, true),
        handler = lands("bane_of_agony", BANES, true),
    },

    -- One hit at the end of its minute; 60 s cooldown (DB2 RecoveryTime).
    bane_of_doom = {
        id = 603,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = 300,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 603 }),
        usable = unlocked("shadow"),
        missable = true,

        now = lands("bane_of_doom", BANES),
        handler = lands("bane_of_doom", BANES),
    },

    -- Bane of Havoc (the Destruction talent's spell; wowsims bane_of_havoc.go): 5% of base mana, a Bane (it takes our
    -- other Bane off its target). The pack casts it on another target only (other_target=1: Recommend Target Swaps).
    -- shortcut: Agony and Doom do not take Havoc off their target here (wowsims's deactivateOtherBanes does); add
    -- bane_of_havoc to BANES if a pack ever casts a Bane on the Havoc target.
    bane_of_havoc = {
        id = 1225228,
        expects = "debuff", -- a dummy aura, no damage (DB2, wowsims): its ticket takes its own avoid only
        cast = 0,
        cooldown = 0,
        gcd = "off", -- wowsims: no SpellCooldowns row, so off the GCD (its TODO; ledger: confirm in game)

        spend = 0.05,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 1225228 }),
        missable = true,

        now = lands("bane_of_havoc", BANES),
        handler = lands("bane_of_havoc", BANES),
    },

    curse_of_the_elements = {
        id = 440892,
        expects = "debuff", -- no damage (DB2, wowsims): its ticket takes its own avoid only
        copy = rest(CURSE_OF_THE_ELEMENTS),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(CURSE_OF_THE_ELEMENTS_COST, CURSE_OF_THE_ELEMENTS),
        spendType = "mana",

        startsCombat = true,
        known = knows(CURSE_OF_THE_ELEMENTS),
        usable = unlocked("shadow"),
        missable = true,

        now = lands("curse_of_the_elements", CURSES),
        handler = lands("curse_of_the_elements", CURSES),
    },

    curse_of_recklessness = {
        id = 704,
        expects = "debuff", -- no damage (DB2, wowsims): its ticket takes its own avoid only
        copy = rest(CURSE_OF_RECKLESSNESS),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(CURSE_OF_RECKLESSNESS_COST, CURSE_OF_RECKLESSNESS),
        spendType = "mana",

        startsCombat = true,
        known = knows(CURSE_OF_RECKLESSNESS),
        usable = unlocked("shadow"),
        missable = true,

        now = lands("curse_of_recklessness", CURSES),
        handler = lands("curse_of_recklessness", CURSES),
    },

    curse_of_weakness = {
        id = 702,
        expects = "debuff", -- no damage (DB2, wowsims): its ticket takes its own avoid only
        copy = rest(CURSE_OF_WEAKNESS),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(CURSE_OF_WEAKNESS_COST, CURSE_OF_WEAKNESS),
        spendType = "mana",

        startsCombat = true,
        known = knows(CURSE_OF_WEAKNESS),
        usable = unlocked("shadow"),
        missable = true,

        now = lands("curse_of_weakness", CURSES, true),
        handler = lands("curse_of_weakness", CURSES, true),
    },

    siphon_life = {
        id = 18265,
        copy = rest(SIPHON_LIFE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(SIPHON_LIFE_COST, SIPHON_LIFE),
        spendType = "mana",

        startsCombat = true,
        known = knows(SIPHON_LIFE),
        usable = unlocked("shadow"),
        missable = true,

        now = lands("siphon_life"),
        handler = lands("siphon_life"),
    },

    -- The channels: unhasted (wowsims: the rows carry no haste attribute); a channel's `handler` never runs in Hekili's
    -- simulation (`start`).
    drain_life = {
        id = 689,
        copy = rest(DRAIN_LIFE),
        cast = 5,
        channeled = true,
        tick_time = 1,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(DRAIN_LIFE_COST, DRAIN_LIFE),
        spendType = "mana",

        startsCombat = true,
        known = knows(DRAIN_LIFE),
        usable = unlocked("shadow"),
    },

    drain_soul = {
        id = 1120,
        copy = rest(DRAIN_SOUL),
        cast = 15,
        channeled = true,
        tick_time = 3,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(DRAIN_SOUL_COST, DRAIN_SOUL),
        spendType = "mana",

        startsCombat = true,
        known = knows(DRAIN_SOUL),
        usable = unlocked("shadow"),
    },

    wrack = {
        id = 1316697,
        cast = 6,
        channeled = true,
        tick_time = 1,
        cooldown = 0,
        gcd = "spell",

        spend = 200,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 1316697 }),
        usable = unlocked("shadow"),

        now = lands("wrack"),
        start = lands("wrack"),
    },

    rain_of_fire = {
        id = 5740,
        copy = rest(RAIN_OF_FIRE),
        cast = 8,
        channeled = true,
        tick_time = 2,
        cooldown = 0,
        gcd = "spell",

        spend = cataclysmic(RAIN_OF_FIRE_COST, RAIN_OF_FIRE),
        spendType = "mana",

        startsCombat = true,
        known = knows(RAIN_OF_FIRE),
        usable = unlocked("fire"),
    },

    hellfire = {
        id = 1949,
        copy = rest(HELLFIRE),
        cast = 15,
        channeled = true,
        tick_time = 1,
        cooldown = 0,
        gcd = "spell",

        spend = cataclysmic(HELLFIRE_COST, HELLFIRE),
        spendType = "mana",

        startsCombat = true,
        known = knows(HELLFIRE),
        usable = unlocked("fire"),
    },

    -- 120 s category cooldown.
    death_coil = {
        id = 6789,
        expects = "travel",
        velocity = 24,
        school = "shadow",
        copy = rest(DEATH_COIL),
        cast = 0,
        cooldown = 120,
        gcd = "spell",

        spend = byRank(DEATH_COIL_COST, DEATH_COIL),
        spendType = "mana",

        startsCombat = true,
        known = knows(DEATH_COIL),
        usable = unlocked("shadow"),
    },

    -- Our Immolate on the target is its condition (wowsims conflagrate.go); 10 s category cooldown.
    conflagrate = {
        id = 1293817,
        copy = rest(CONFLAGRATE),
        cast = 0,
        cooldown = 10,
        gcd = "spell",

        spend = cataclysmic(CONFLAGRATE_COST, CONFLAGRATE),
        spendType = "mana",

        startsCombat = true,
        known = knows(CONFLAGRATE),
        usable = function()
            if not debuff.immolate.up then
                return false, "no immolate"
            end
            return not locked_out_fire, "fire locked out"
        end,

        now = conflagrated(),
        handler = conflagrated(),
    },

    -- A Soul Shard; 15 s category cooldown.
    shadowburn = {
        id = 17877,
        copy = rest(SHADOWBURN),
        cast = 0,
        cooldown = 15,
        gcd = "spell",

        spend = cataclysmic(SHADOWBURN_COST, SHADOWBURN),
        spendType = "mana",

        startsCombat = true,
        known = knows(SHADOWBURN),
        usable = sharded(),

        now = burned(),
        handler = burned(),
    },

    searing_pain = {
        id = 5676,
        copy = rest(SEARING_PAIN),
        cast = function()
            return 1.5 * haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = cataclysmic(SEARING_PAIN_COST, SEARING_PAIN),
        spendType = "mana",

        startsCombat = true,
        known = knows(SEARING_PAIN),
        usable = unlocked("fire"),
        missable = "demonic_brand",

        now = branded(false),
        handler = branded(true),
    },

    incinerate = {
        id = 412758,
        expects = "travel",
        velocity = 20,
        school = "fire",
        copy = rest(INCINERATE),
        cast = baned(2.5),
        cooldown = 0,
        gcd = "spell",

        spend = cataclysmic(INCINERATE_COST, INCINERATE),
        spendType = "mana",

        startsCombat = true,
        known = knows(INCINERATE),
        usable = unlocked("fire"),
    },

    -- 6 s, -0.4 s a rank of Bane (DB2 17788 effect 1), then Decimation's -20% a rank (440873 effect 0 at the talent's
    -- rank: wowsims's logs 2.4 s = (6 - 2) x 0.6 at 5/5 and 2/2); 60 s, -45% a rank of Decimation (440870 effect 1); a
    -- Soul Shard, none under Decimation.
    soul_fire = {
        id = 6353,
        expects = "travel",
        velocity = 24,
        school = "fire",
        copy = rest(SOUL_FIRE),
        cast = function()
            local c = 6 - 0.4 * talent.bane.rank
            if buff.decimation.up then
                c = c * (1 - 0.2 * talent.decimation.rank)
            end
            return c * haste
        end,
        cooldown = function()
            return 60 * (1 - 0.45 * talent.decimation.rank)
        end,
        gcd = "spell",

        spend = cataclysmic(SOUL_FIRE_COST, SOUL_FIRE),
        spendType = "mana",

        startsCombat = true,
        known = knows(SOUL_FIRE),
        usable = sharded(true, "decimation"),
    },

    life_tap = {
        id = 1454,
        copy = rest(LIFE_TAP),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        startsCombat = false,
        known = knows(LIFE_TAP),
        usable = unlocked("shadow"),

        now = tapped(),
        handler = tapped(),
    },

    -- Off the GCD; 180 s.
    amplify_curse = {
        id = 18288,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows({ 18288 }),

        now = function()
            applyBuff("amplify_curse")
        end,
        handler = function()
            applyBuff("amplify_curse")
        end,
    },

    summon_imp = summon("imp", 688, 0.8),
    summon_voidwalker = summon("voidwalker", 697, 1, true),
    summon_succubus = summon("succubus", 712, 1, true),
    summon_incubus = summon("incubus", 713, 1, true),
    summon_felhunter = summon("felhunter", 691, 1, true),

    -- The talent's (18788): no cast time, cost, cooldown or GCD row (DB2); needs a demon out.
    demonic_sacrifice = {
        id = 18788,
        cast = 0,
        cooldown = 0,
        gcd = "off",

        startsCombat = false,
        known = knows({ 18788 }),
        usable = function()
            local p = pet -- the simulation's; the belief's `now` context has none (the client's answer decides)
            if p and not demonOut(p) then
                return false, "no demon"
            end
            return true
        end,

        now = sacrifices(),
        handler = sacrifices(),
    },
})

-- The coverage lane's casts (a manual press costs what it costs; no priority casts them). Ranks, costs, cooldowns from the
-- pin's spell rows; `CostPct` ones as fractions of base mana.
do
    local FEAR = { 5782, 6213, 6215 }
    local HOWL_OF_TERROR = { 5484, 17928 }
    local HOWL_OF_TERROR_COST = { 150, 200 }
    local BANISH = { 710, 18647 }
    local BANISH_COST = { 100, 200 }
    local SUBJUGATE_DEMON = { 1098, 11725, 11726 }
    local SUBJUGATE_DEMON_COST = { 300, 500, 700 }
    local HEALTH_FUNNEL = { 755, 3698, 3699, 3700, 11693, 11694, 11695 }
    local DRAIN_MANA = { 5138, 6226, 11703, 11704 }
    local DRAIN_MANA_COST = { 95, 155, 225, 310 }
    local SHADOW_WARD = { 6229, 11739, 11740, 28610 }
    local SHADOW_WARD_COST = { 135, 195, 255, 320 }
    local DEMON_SKIN = { 687, 696 }
    local DEMON_SKIN_COST = { 50, 120 }
    local DEMON_ARMOR = { 706, 1086, 11733, 11734, 11735 }
    local DEMON_ARMOR_COST = { 275, 520, 800, 1150, 1580 }
    local DETECT_INVISIBILITY = { 132, 2970, 11743 }
    local DETECT_INVISIBILITY_COST = { 50, 90, 140 }
    local CURSE_OF_TONGUES = { 1714, 11719 }
    local CURSE_OF_TONGUES_COST = { 80, 110 }

    -- A buff on ourselves; a demon armor ends the other armor (one at a time).
    local function armored(aura)
        return function()
            removeBuff(aura == "demon_armor" and "demon_skin" or "demon_armor")
            applyBuff(aura)
        end
    end
    local function buffed(aura)
        return function()
            applyBuff(aura)
        end
    end
    -- A debuff on the target (Fear, Howl of Terror, Banish, Subjugate Demon).
    local function debuffed(aura)
        return function()
            applyDebuff("target", aura)
        end
    end

    spec:RegisterAbilities({
        -- 15% of base mana, 1.5 s (the pin's rows; Forever's own aura ids are the client's).
        fear = {
            id = 5782,
            school = "shadow",
            copy = rest(FEAR),
            cast = function()
                return 1.5 * haste
            end,
            cooldown = 0,
            gcd = "spell",

            spend = 0.15,
            spendType = "mana",

            startsCombat = true,
            known = knows(FEAR),
            usable = unlocked("shadow"),

            now = debuffed("fear"),
            handler = debuffed("fear"),
        },

        -- 2 s cast, 40 s category cooldown.
        howl_of_terror = {
            id = 5484,
            school = "shadow",
            copy = rest(HOWL_OF_TERROR),
            cast = function()
                return 2 * haste
            end,
            cooldown = 40,
            gcd = "spell",

            spend = byRank(HOWL_OF_TERROR_COST, HOWL_OF_TERROR),
            spendType = "mana",

            startsCombat = true,
            known = knows(HOWL_OF_TERROR),
            usable = unlocked("shadow"),

            now = debuffed("howl_of_terror"),
            handler = debuffed("howl_of_terror"),
        },

        banish = {
            id = 710,
            school = "shadow",
            copy = rest(BANISH),
            cast = function()
                return 1.5 * haste
            end,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(BANISH_COST, BANISH),
            spendType = "mana",

            startsCombat = true,
            known = knows(BANISH),
            usable = unlocked("shadow"),

            now = debuffed("banish"),
            handler = debuffed("banish"),
        },

        -- 3 s cast, a Soul Shard (the pin's rows; its 300 s is the control's duration, no cooldown row).
        subjugate_demon = {
            id = 1098,
            school = "shadow",
            copy = rest(SUBJUGATE_DEMON),
            cast = function()
                return 3 * haste
            end,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(SUBJUGATE_DEMON_COST, SUBJUGATE_DEMON),
            spendType = "mana",

            startsCombat = true,
            known = knows(SUBJUGATE_DEMON),
            usable = sharded(),

            now = debuffed("subjugate_demon"),
            handler = debuffed("subjugate_demon"),
        },

        -- The pin's channels (10 s and 5 s, a tick a second, unhasted as Drain Life). Health Funnel needs a demon out.
        -- shortcut: Health Funnel's cost is health (the pin's Type -2 power: an initial cost and a cost a second), no
        -- spend here (no health spend type), so Improved Health Funnel stays inert; upgrade if a priority casts it.
        health_funnel = {
            id = 755,
            copy = rest(HEALTH_FUNNEL),
            cast = 10,
            channeled = true,
            tick_time = 1,
            cooldown = 0,
            gcd = "spell",

            startsCombat = false,
            known = knows(HEALTH_FUNNEL),
            usable = function()
                local p = pet -- the simulation's; the belief's `now` context has none (the client's answer decides)
                if p and not demonOut(p) then
                    return false, "no demon"
                end
                return not locked_out_shadow, "shadow locked out"
            end,
        },

        -- shortcut: the mana Drain Mana gains (a tick takes up to its rank's amount, capped by the target's mana, which
        -- is unseen) is unmodelled; the live mana read corrects it. Upgrade if a priority casts it.
        drain_mana = {
            id = 5138,
            copy = rest(DRAIN_MANA),
            cast = 5,
            channeled = true,
            tick_time = 1,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(DRAIN_MANA_COST, DRAIN_MANA),
            spendType = "mana",

            startsCombat = true,
            known = knows(DRAIN_MANA),
            usable = unlocked("shadow"),
        },

        -- 30 s category cooldown; the absorb's size is unmodelled.
        shadow_ward = {
            id = 6229,
            school = "shadow",
            copy = rest(SHADOW_WARD),
            cast = 0,
            cooldown = 30,
            gcd = "spell",

            spend = byRank(SHADOW_WARD_COST, SHADOW_WARD),
            spendType = "mana",

            startsCombat = false,
            known = knows(SHADOW_WARD),
            usable = unlocked("shadow"),

            now = buffed("shadow_ward"),
            handler = buffed("shadow_ward"),
        },

        -- 2 s cast, a 1 h cooldown, 100% of base mana (the pin's CostPct 100; no summon modifier's mask reaches it); an
        -- Infernal Stone is the reagent (not read here); the demon is not modelled.
        inferno = {
            id = 1122,
            school = "fire",
            cast = function()
                return 2 * haste
            end,
            cooldown = 3600,
            gcd = "spell",

            spend = 1,
            spendType = "mana",
            spendBase = true, -- the 1 (100%) a fraction too

            startsCombat = true,
            toggle = "cooldowns",
            known = knows({ 1122 }),
            usable = unlocked("fire"),
        },

        demon_skin = {
            id = 687,
            copy = rest(DEMON_SKIN),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(DEMON_SKIN_COST, DEMON_SKIN),
            spendType = "mana",

            startsCombat = false,
            known = knows(DEMON_SKIN),
            usable = unlocked("shadow"),

            now = armored("demon_skin"),
            handler = armored("demon_skin"),
        },

        demon_armor = {
            id = 706,
            copy = rest(DEMON_ARMOR),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(DEMON_ARMOR_COST, DEMON_ARMOR),
            spendType = "mana",

            startsCombat = false,
            known = knows(DEMON_ARMOR),
            usable = unlocked("shadow"),

            now = armored("demon_armor"),
            handler = armored("demon_armor"),
        },

        detect_invisibility = {
            id = 132,
            copy = rest(DETECT_INVISIBILITY),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(DETECT_INVISIBILITY_COST, DETECT_INVISIBILITY),
            spendType = "mana",

            startsCombat = false,
            known = knows(DETECT_INVISIBILITY),
            usable = unlocked("shadow"),

            now = buffed("detect_invisibility"),
            handler = buffed("detect_invisibility"),
        },

        -- The curse slot's other two (one curse per target: CURSES); Tongues is a plain cast, Exhaustion the Affliction
        -- talent's (18223, 8% of base mana; wowsims leaves it a TODO). Amplify Curse reaches Exhaustion (DB2 18288).
        curse_of_tongues = {
            id = 1714,
            expects = "debuff", -- no damage
            copy = rest(CURSE_OF_TONGUES),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(CURSE_OF_TONGUES_COST, CURSE_OF_TONGUES),
            spendType = "mana",

            startsCombat = true,
            known = knows(CURSE_OF_TONGUES),
            usable = unlocked("shadow"),
            missable = true,

            now = lands("curse_of_tongues", CURSES),
            handler = lands("curse_of_tongues", CURSES),
        },

        curse_of_exhaustion = {
            id = 18223,
            expects = "debuff", -- no damage
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = 0.08,
            spendType = "mana",

            startsCombat = true,
            known = knows({ 18223 }),
            usable = unlocked("shadow"),
            missable = true,

            now = lands("curse_of_exhaustion", CURSES, true),
            handler = lands("curse_of_exhaustion", CURSES, true),
        },

        -- The Demonology talent (18708): 300 s, off the GCD (no GCD row), the next summon 5.5 s faster for half the mana
        -- within 15 s (the summons above read the buff).
        fel_domination = {
            id = 18708,
            cast = 0,
            cooldown = 300,
            gcd = "off",

            startsCombat = false,
            toggle = "cooldowns",
            known = knows({ 18708 }),

            now = buffed("fel_domination"),
            handler = buffed("fel_domination"),
        },
    })

    -- Cooldown Manager items whose spells are bag items' uses (Healthstone, Soulstone Resurrection; no pin row): a
    -- passive registration only names each ID for the Cooldown Manager map. No ability is made and nothing is tracked
    -- (Tracked.lua tracks a spellbook rank; an item's use is never in the spellbook): the cooldown is Hekili_Shared's
    -- healthstone's.
    for _, id in ipairs({ 6262, 6263, 5720, 5723, 11732, 20707, 20762, 20763, 20764, 20765 }) do
        spec:RegisterAbility("track_use_" .. id, { id = id, passive = true })
    end

    -- Not registered (one line each): Create Healthstone / Soulstone / Firestone / Spellstone (out of combat, a shard),
    -- Unending Breath (utility), Sense Demons (tracking), Eye of Kilrogg (a channel that moves the camera), Ritual of
    -- Summoning and Ritual of Doom (group rituals), Curse of Idiocy (the pin's row has no learn level: not trained).
end

-- Talents: { talent tree (1 Affliction, 2 Demonology, 3 Destruction: the dominant tree picks the spec), rank 1's spell,
-- max rank }: Forever's live tree, wowsims/forever's (ui/sim/talents/trees/warlock.json: 17, 19 and 16 nodes, each
-- spell in the DB2), keys its field names in snake_case.
spec:RegisterTalents({
    -- Affliction (tree 1)
    improved_life_tap = { 1, 18182, 2 },
    suppression = { 1, 18174, 5 },
    improved_corruption = { 1, 17810, 5 },
    grim_reach = { 1, 18218, 2 },
    soul_harvest = { 1, 437032, 2 },
    improved_drains = { 1, 403511, 3 },
    improved_bane_of_agony = { 1, 18827, 2 },
    fel_concentration = { 1, 17783, 3 },
    amplify_curse = { 1, 18288, 1 },
    pandemic = { 1, 427712, 3 },
    malevolence = { 1, 1310949, 5 },
    nightfall = { 1, 18094, 2 },
    curse_of_exhaustion = { 1, 18223, 1 },
    siphon_life = { 1, 18265, 1 },
    soul_siphon = { 1, 17804, 3 },
    shadow_mastery = { 1, 18271, 5 },
    wrack = { 1, 1316697, 1 },
    -- Demonology (tree 2)
    improved_health_funnel = { 2, 18703, 2 },
    improved_imp = { 2, 18694, 3 },
    demonic_embrace = { 2, 18697, 5 },
    unholy_power = { 2, 18769, 5 },
    demonic_aegis = { 2, 1235316, 2 },
    improved_voidwalker = { 2, 18705, 3 },
    fel_vitality = { 2, 18731, 3 },
    demonic_energies = { 2, 1225214, 2 },
    improved_sayaad = { 2, 18754, 3 },
    demonic_sacrifice = { 2, 18788, 1 },
    master_summoner = { 2, 18709, 2 },
    decimation = { 2, 440870, 2 },
    fel_domination = { 2, 18708, 1 },
    demonic_brand = { 2, 1293695, 3 },
    improved_felhunter = { 2, 1225217, 3 },
    soul_link = { 2, 19028, 1 },
    demonic_knowledge = { 2, 412732, 3 },
    master_demonologist = { 2, 23785, 5 },
    demonic_pact = { 2, 425464, 1 },
    -- Destruction (tree 3)
    destructive_reach = { 3, 17917, 2 },
    improved_shadow_bolt = { 3, 17793, 5 },
    bane = { 3, 17788, 5 },
    molten_skin = { 3, 1225220, 5 },
    cataclysm = { 3, 17778, 3 },
    aftermath = { 3, 18119, 5 },
    ruin = { 3, 17959, 5 },
    shadowburn = { 3, 17877, 1 },
    intensity = { 3, 18135, 3 },
    agonizing_flames = { 3, 17927, 3 },
    conflagrate = { 3, 1293817, 1 },
    pyroclasm = { 3, 18073, 2 },
    bane_of_havoc = { 3, 1225228, 1 },
    fire_and_brimstone = { 3, 412751, 3 },
    shadow_and_flame = { 3, 426316, 5 },
    incinerate = { 3, 412758, 1 },
})

-- Packs from the talents (Engine/Schema/Selectors.lua; after the Hekili classic branch's pack selectors).
-- SM Ruin (31/0/20) stops Affliction at Shadow Mastery and takes Ruin from Destruction; the Affliction build
-- (35/11/5, aff_wrack) goes on to Wrack (an older Affliction build took Ruin too, so Ruin alone does not tell them
-- apart). Shadow Brand and Demonology are both 2/31/18: only Shadow Brand takes Improved Shadow Bolt (the fire brand
-- build spends those points on Aftermath). Any other build runs its tree's default.
spec:RegisterSelector("sm_ruin", { spec = "affliction", pack = "SM Ruin (wowsims.com)" }, function(tab1, tab2, tab3)
    return tab1 > tab2 and tab1 > tab3 and talent.ruin.rank > 0 and talent.wrack.rank == 0
end)
spec:RegisterSelector(
    "shadow_brand",
    { spec = "demonology", pack = "Shadow Brand (wowsims.com)" },
    function(tab1, tab2, tab3)
        return tab2 > tab1 and tab2 > tab3 and talent.improved_shadow_bolt.rank > 0
    end
)

-- A curse's name as the client shows it (localization spec §5): the client's, already in the player's language and as
-- its tooltip words it, read once here (a plain string); `english` when the client has no name for it (not cached).
local function curseName(id, english)
    local info = Facade.C_Spell.GetSpellInfo(id)
    return info and info.name or english
end

-- The assigned curse (tools/wowsims/apl.lua rule 16; the recipes' `select`): wowsims's Curses class option, a choice
-- the packs' curse lines read as `settings.assigned_curse='<key>'`; every build's (and so the harness's) is Elements.
spec:RegisterSetting("assigned_curse", "elements", {
    type = "select",
    name = L["Assigned Curse"],
    desc = L["The curse the wowsims.com priority keeps on the target (wowsims's Curses option). No Curse: none."],
    values = {
        elements = curseName(440892, L["Curse of the Elements"]),
        recklessness = curseName(704, L["Curse of Recklessness"]),
        weakness = curseName(702, L["Curse of Weakness"]),
        nocurse = L["No Curse"],
    },
    width = "full",
    sim = "elements",
})

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and
-- run it, never this block (tests/Forever/warlock_spec.lua checks it matches). Each pack's .simc is generated from its
-- wowsims recipe (`make wowsims-packs`, tools/wowsims/specs/warlock_*.lua).
spec:RegisterPack(
    "Affliction (wowsims.com)",
    20261113000,
    [[Hekili:TRvBVTTnq4Fl5lP2OzYVKLUMG4a0THH1TUUH5cSVjzAjkBwljkisLade4F77OEZKYuuYQjoDflbTqv8E)oEh5JQ9e7pzp3dXX2FC64PVzYKjxoE8y758TXy75Xi3nOvWdrOq4VFNVFaXLtOr7wm4b6dmsiZYLgouq52akYtiTLPKa(7JSxQvWSySR98)5D)9h(ZF63Vbvjr75RjEE4C2WmxdA7MDl4RX7wu8Ur(0e894KDl8W(O0a(UfV7V(WUfWRHNKfskzKq9SrpGscOUBg5fZgjmxp2iWsCEib8xRSxy9zgnA4fGMsqrSaWp8GNPcnty7wG88OrVcEydElZA3IFgXr3OXIg8hV)tGqwZ5XSBgnAfHVoDPWjgvJ0HGmbdhFf6AxVPOPE(UwqunH6tcGipkZfywXjyG5Li(m2AKh9bNLuWF)TILNTeNWWjBirRUiLHDOGpTY1B2KkkE9SrIfiCCiRzs8WH0iIRtsAeUzQcrFMM4eIIqoXuXlBMuxuqGt()0jGW4xiQNMXa7ma7ecPmIdhLScZDCtbpWjGUI4klGLOiHOD8O0Wli(Z8jRwZDsWHise7op8YuFFlzIS8stqzP9UAgfgGhLNREHAe0Ep2bhHdjywx8jfNXGSUtrwsjZl8PUPSztfSmiZTkwuui6ITsJFCahfGJ4wKqO(4ESNJe7w4i0YaS35zSkkTcYcdaFNp4SIavb93NgeHtqljbe(wHGnTCrS(2b5wTLSoDrm(R18EWKb97WjH4HWpM94jFJ7X6RxCP0aG7iwM3FwHivQK3ebR)4GbnU25dmZOYMLV7QHJmTFz4TtgEUj5DMoUtJbV9rdMyJmP23bXx74sjbkrd5aCHp1ZuYDkHcfDhq8f9aIZ0SOPMvSRy37Txo(C1UnVzScJzdnAO0Ujf0SNLPzqR6CqkBVaTAP55S8NHqnmQ0bhGdH9pSlC36w1QtSLtQzddZ5GmzwigJSkc2KLjIzVQK5xbLfdg0bYkY1ATarsVk9vrbmvBtaMXIG)uuW0OEKP9qDPijT66bmAtx0tjDhQJkjOwa3wkr0dqNz2RKIAuqKyQ7Nkr9w81Jj31rt6)OjMsr0RKYEl7uMqoLBM6GR31KI(tkndfgdDk3Mlx1tuM1AUpJMmopZ0G1ZkhpRUycg5T144oLjg3ACE7qnMhAfnABdov(AcVsW0(tuE7vTgCLoiDMuuoRzVcSnzC9Y2CPjjPXcImT7R6mD7jxOqT3iqIKY4TyRPQXD3Slh(yUQSOPCgXdFLMUhhDL6znxF8yZ5BOSQxzIVjlX7qA4ewtRwInzANmoPI6JTi(6oPagjED2vk8XA1G06nUprMMQnkTC3jPuAaL654NMuLpZJF7FTsbAoklfuQ8o31OOiCa4QYj(QRindNMG3G0TvRF1(gRp0vEuwT)wZ7361nKA(EvAcfIQ(QW7xbbKjx9vqejRiQ199pdUrTPDZM0GbQChZ(MJmz)tN2ZakK5lV55K3oE85YxaE61dp8gWGhAp)ECcduvneEfGBWYGvohow4XpMbZCbqn2)O9CPkwXIf4BApFpaM2CqSDKRkinfmDzhzsgKtbFFFh57aypfmFvnMljUoOp5rhNC40B5Ajc5(MgKRCge0sc49jeK98UJlQq6)qnPVxo1lOpopQ(ukHUEBh11DDvx6pgPqvx3OQAaEXNp8fFUbyCFSsIiOmqCoaX(hiAmz8)hoYdhtYch1Bfjfom0rU)JnFYbG1ecS9cc2oUHRAswwySEV59TvlXWvBO9qepFQaZnZQQ38V0QkN8QytTHYBMeRpwOuIzh2iJIM69lxckORPE56SndHRwqi2w878QVtOUHV6nqE7dKmilT4tbVw(E8zJrRAnj5TDagSNkONpPWL98JXPUtjDqkr2U(ItjVyap)0H88PjT0uROdy5loL8Ia78jEJuhC(wtj8MpG6rCfffy)uNXzaWpJi(zgYV(H53xaOFNiu)mb7NU(Asr6(fU6oWEhErRmAvpyD9n4YvcL1Igr3tQNqfDQQO(Hp0OIxa49oc89maWN05q2BEkUpx(mNhXo0CycpbNS3eumTarObeX6hcohdEj7ZCVWbP2WB7zjk10G58t0352mph(1HajQRlqPbR9sn9olAYFe4k2Va(XdSy(g)gq35i6c08C6(n9O3b2VYh2E4NQ90o89q13NHVLSipjTBhRUtdRpKKw(EYh(bLTlUKnkLVMMyp)xXBGzT7wm4xk(FaC2Y2)7p]]
)
spec:RegisterPack(
    "Demonology (wowsims.com)",
    20261113000,
    [[Hekili:TR1AVTTnx4Fl5lowOEYxsDwBqCaA3WW6766kMlW(MKPLOSzTKOGiv8mqG(T)EOUzrjkzzhNlyBOObkKhEUZZ5WNwJXgFZyUnIJn(YKrtUE84XxnA0iJ58DbyJ5biRnOvWh(ip4N)m2J6tDPR2fVO)w6wgXJPBr90euUZLISfCBzeXL)jFJLkzmlaBzm)V(WF(5)4N(TBSl4OX81eBBC6XWmRwK2nXl4RXXlYwBOdneFpomEHn2bf5YJx8HV(54fWYXlKysezOq8SHBrHUuRndTdydfQRnBOqtmDiHyZLHiFB9KL1)oJ6RnaKhSgZfSgB4BQq(ew8cKTn1)s4Jn4DmDqyio6gf6v)F)tFdyYAopGDZWHRi81rlfMYWkKQb8euF8u07TSNGMy7ybS9Jyx624fUafUXlg)oGHlXIteVyogfs8xfV4RiIVwUEfesOHeoyYoexxyHTGebIxJSfm6JuxEcBt5rIVmXprSGvfwpSiYf7ZhurccLazZYoJlHbkBFchwyz6Xes3p1OJceooeRWFiCu0T(5NBlncCWqMtif0si7czXjuFMEqigCnlr8zmGKKys8)R2MVz2qINhvetgqCMDHnEzKJJE(A6rbfhAwedBs4yp2aXxuhhZvw2ZgxqaWl7u73mmYh3mvEOVtdn9q(iZaQyXMj1c56AM(RMcdEG4k0mg4kDXMEqwkXKJcxH5MwrHatGuuW9xIbRXUUcBxyDIvVhBI9XEem7Uzx1Jtxbms3JEp2dcu96RGKe2RtJ4mInEQwzMVe5l0BtBk1BGd1kInBIqqoKvR5MHypiyZUlZNwMyD7OqKGlL5glnhXmaovzU1VFEyj39ME3kk4bLRNj3BNOpvR3fP8xVmZ1X)n2kId)AV(xu3K1EOQnR15qswWWMYtdf1D7Dj(kfyBHx31bEzrPUW9vFwQRmZDifm24d73dCZnU5d97lft)HPAdBlSQD7yTETXVluDA4UUM2dTPJnCQhAoVvuZI4dHqTJ4wH0rLsrZlLKLFool)Sljr9YsvTiEj(iqX7jFrj3WlKIUfIXFtTvH2iqnCtoXdxkbVy7ISBn5sti(AtlkXnrNvEVin2OAhHICNK2kXCxIJi3piH1IcB6bwIS2BVAAfB86rAnDNxA9KMmMlHEmnjNclypPzgqIcacxbbwu2EgQFG6OZs)gs0GgvMy3KAKSbw7SkUPlsbkvQIH5chpthXyKv(y7u2n7Y8dFPOIt)oqwwMUsnyFkpyDfuaT024IzmF4VzxxAuoLPTUSK4KszTfJ20f5KtxDzuWbXL(Ex0SlXNM8XLLUaFO4MOwOkB5KICYUkr0RQZqk0CahYXeG7Ok9p5OxUCoPi3E1)5mQ9CETSdM(znYPEUKz5TJrRO(7Qm52XpcqVQBKWwr3s5MS3o9GAw5P7BjdQVIX(7PCg2ccYh05OhGSzn1IgggfiiQt66EYBuBlrYPRVnmy7ZwqV13sKsvXuNhuRlNqCEsa6KmlfApFHYssUyg)z4Oq8gK87jLM3t5S9nUx7pkqvSm)XxVR95)Bz8)MvMMF0GcxH45PUuQTPtu4UxboKXtFn4rWqj9WnqI6)5r2wh0Hdv96jWAQ0uB24g0tPxyDQHQ20)jtor)kKaK)GRjxpAuVYp)7Tt0Q)(pWcnMFpKjcIQcSUcylyjyjNIbl85xsWwg7Jw6ITn(OX8sjUInZa8lD9e45m4ax74HkdyN4Cx1XZvdcpXHFBLdNtCvGzsTtZu0WpW0Wc(oTb(MJIbiHqWYdjO09E0y8je61ve6Er0D092RQL3g4GOjOiibY5hBuoTG73tfWF1heAVjuMrYMW7A0eQE5(4YjQojHqwVVJY6UUkl1ZJke14rTeAoX(bNDGeBdjXJUwO4rvDclXo6BlkGN4oRwi7iVglPdjmSAroPRoDk9(fatYsxOY3T4204eZQAn491QZrWuYuBbjZUcLzIyBQ6DENxjHEimot4yt1TLQKiiSAT2cc3JCzcDvRv2Mk2m8OhcFudXFMx8prMQEW1dHk65Mtu(BMK0U6p4kvShQDylkJsqzGLl)y6KM4f1UlPqDa7NZfYTpRye9kb9V2YpuQ8p642lgUTNpGBFff7AQMCn((OJBViO2(mFLSdg)5jUXBEwsffsLMF4eg568aIx9hnKqG8i3Tm6ZJalpv9Skl1Q3cui1telVs3Ok2vs28YttEeVkofqqLdmPE88g38ad23g2chamWwq650GK4yqaypiHVWoPdbG0tIxQR4DSh4W)n6LA6PbYqc01YNpfMxDyeBd4iLpP5KdMTzpcufpn)(XdRyAvYgWZ4zTDNCW42PNwpT69I62OvpIoGDhwS2MjSuhSJuJpTUNhJwNKJGI4RPHgZ)v8gIljEr)Fj7)4SjBB8))d]]
)
spec:RegisterPack(
    "Destruction (wowsims.com)",
    20261113000,
    [[Hekili:TVvBVTTTt8pl5nowOz(HK6S2G4aST)yyz)36kMlqFNKPLOTzTKOHOummqG)SVJuwpqjs9u8CZwhkAGd5X7(X7jEKNJ5yZpzoZbfIn)W1JU(2XJhFZOrJmNfUFl2C2wK9g0k4d(ip4N)pmlmiYoKq9pmV)o6ogXJnWM6zWjDVlf5Wz3IiIB4J(MluYz2wST5Sp)d)5V9h)0))oNmwAoBnXXbhVomZUk5D3H5HRXhMFCSHlPb4NWbhM7GxIICdpm)h(4VDyom8H5YCjImKJa2WDOaxQ9MHoBzd5i2Hnuag6aXVn4lmQVXvGCcq(mxyF4aFMYLlHDyoYXH6Fj8Hn49SbGqqHO7uGN()(JFcyY6WWTS7goCfjCD0c(wyybsnaEcWgpb9EBNRrx7S0gy7Nb6PrW4p6Bt8XbamaEIauGCX(W4ldOEhM7cCW9W83oYibFBdi0as4EGcIRlmWoGthMpdJci(Rom)JiIpGlU(54mRro0DhM)JuU2BbMdRc0FyoNZUWq(yhyXiFqLeGxgGzRXWmp65rDfiK67csE3AmFnHC1sKlq7oyPWKlxgluohrfLSnIfoaCNcOaWbFoKWWXgSnadATfOWPmGzwlja8(1st(MPdjhrXvKLtVWbViA5YbjJniAB6IMgXWwKqSh7k(NauzTY2z64ucaE5G9O(eBRGiFSEQ8qFHgy5H8rwBP8b1tQnY11k(xTCjSWR4bwtzGk2fB5boUeRquWkCOLDuaWex6kIDEgSg76Y378DhF0NWwyFShbZEy6n9cPRagnWJ(e2dCp61xbjc2paCQyeh8eJ8mFbYNJBlhk17QLu7i20R5cAjz16qRaSh4eWE4OonpXdCIaxtEaMcUTg9e1wwLCffIEdoUvHFfKrrOoU3fjd5qdhiXShgzy0yT6r9jWKyTzznxtmrs2Mk41dY8I6V0fTk4O7y)(XtL5pUXNUZVxzVuJNVqmeteBybrAwaJ8WwXdWPiVCIhDruGF97eBk1fi2NjHijRzmQ63)cTt(C)(sofF3eJHv5xyC)yJEvXVluTAyxAy8CvyuZQEwVJFCINjgYEq1ewjTujfFC(rRT80PC9zYwKKMVorHvEcEQU3uEy4ahiBUviXdB8GKw2qo3ekCTLnL4kj48i6OOvndx2vWCxYsEKZwbR5z2gS1M7ZF)nt6jNn42rslmn7BU0h6vkfD8pY07vRRm6PqjkRDpgVSaokrtSvbrKFbcziVBYo1Tu0Myn60zxOdppluMGIuL8PSmgoOMdfMg)zWPhsLAHDfj8zxzV3onNhKylVzGHddbEYgGymYk4i8y2n9YKfFjeH2VFdi7OovjcYc)GDxkfW5ZBCXmMp8)JggTYjpTLLLeNuklOkJnnroj0vwgPCGNacohsll8PIpCzoVM6SB88YQ2lDYYjRQ4wVIkdjttnkK2yGBiK(3S1lroDYYLb)ZPv7Cgw2GT(j1YPUcTPiVTqI59XRSqvOIcG6qrjvwjtvLRCrsXxYtgGro7ZmpkwO0zU3xzLwgkGhAf1FVMnv8Ck3vIIT1SS454lJVOS6LUFsT2KC3nqiCPAf6K9q3E6CULsR8PI0b9vCH0EkVDvkbj2vEEczybvMA8CXRZ1eKAtdcI2YjQrynJCTOnhjDhVAUVwTrWxOpU5z9Xb87v0fxTVrc9ZVSkV(FmH5GqTg0Zy4FBqEtWT6B305y6gjZCrRNUOZCso99aMIJcWBqQIW6MlFLgtv2YeN83vDyMg3aJkdJ0)adkufCxuxk1XAzuW(xbkKXtEnOrWq(3GnGJ6)Pr2P)XoAlQEH7Oc1QmDCVt2ZTCMFVfzvBQeFvOu1GsPNjRRXavH)RVUJoSqKvYlnD9TJg1l)B49wi)APhXd2HMZEccXbrvOJD83oMj6tyCZ1Gp(brFdX(OfUyhZF0CwUmc8jp22M4XfnzXme4Adxu(2UWx3nnCDLAedFXVTWItiU4RJhVpTI70znpdaNVt0W3KNsgKqaSZdiO45EXDQHl0Bli0mr08E0Kb18tdCGNeJBKa589ALtrGwxFA0BTKi1Cw(wcXPd(X70IIIXNTZSwSklUSEFdL1dnvwQV(fxuJhPZLmRDrsQ800W132O67BKabfdFtqqwJKeKvmGvbMA7H6N8ohvvRJADExHkuFSywZJAOtq6Hfc1zX8yTmLHegemuxUT8T6rYQPT0Gtt)PeGsxIXSgwPeskACvt7CLqSftnMi2KZOLeADT0sWXkscQxp2YAS0xI1PSgRmTrYAKt3pUyM2uYtrLGSIjjLtBiKO4CEDj4uzl03QS66vMj)FZs)UFOQSKuaM8DgrvziL1n5qx5KSXITUkeQamkFGEy48VfN4KYutuoa1G(aCQ6I3zTFbVs6euv(hkb)l2U9vRhENUM49kY2P7i2s89fB3(Q0bVZCizd28Ng7wO(AZBXLnL6uG851v0JGkBsq1DjOBTj4f0NGZuJc6ANcAzRcuLSn)vm6KM)K0mGY3svqGCvtfZ1K3FRCzdnTNa1vRwXA(vi1o2tG8xenzwjzhM)cnTiUmUXcklGUTHhv7uu1tPvttfQ4fJ72lWPY5w7tHK2SHVYkP6EV0)w0sn959YAaX3IAPkI7BnwEPBK200H2EJ4xjxjw3RyK7gXVUmbkFF4euR8rq6CKtv7hEhl6MtE7Bzr8rsAEO1wC(K(6g7wjiDwX(pUI)Y)1PQnFFQoVv(D6GDxklSCEMMDZZxqrKA(Yxv(BFLQdwsWB(IaBjI7wbOTb1IiFuu4AAG5SFbVH4somV)pF8VLoX0M)1p]]
)
spec:RegisterPack(
    "SM Ruin (wowsims.com)",
    20261112001,
    [[Hekili:nJvyVTTnq0Fl9lj2ybswURzRb1dOBddRBTDdvfOFJs0KNSzLePaj1mcqH(TpszllAAPgzGUKHIgOO7DV3X7S57qqrOpIIPynGE)YflVnkkA5IfrOy99vakUctYXBmpWXLMFg)UM0puZ4nPZ2j2PyLQaIOCUf39fcm1Y16AwH(nC06bPvvbeu8NE9hE7F9l)5D4SScgrZeCu8wgLc7tduKr16UMu9wOj9W7cZes4FaztkfYW1f6M0x)3VTj186MuhkQzHwPvH7WYcbjpKwPcTLkvfQktKgubT)AWNvc(8BmQiXCvH5eqnplSQYunPykvWV28qoCVkOj9xXA8DdunZE3B(OHKTADL6UWWnm92612dqOh05gonfn8c8lj0L4L0msGPFkfzScthh32DuRGAjKJVPwbjISSKne6QOM)4q0VBv46cHGMKvlV)RGbKkqMZ4BghJnatdLQXHqHsbNrm9momoQs8NfYKsmhNujSVCCOKAzBOeZGnbkGsGRv3Kji1QvlVHLTsbATPQvbyLITHd0K2uwDDh4RVA2ZMnBcWOW66SSGbvmOUA(xMTVS6ribsEbOuCZ)dY5ID8RgvhxSNR1jmnOw7aC(u0Pd35ACKbd)ZNpyt2TmMut(0tLTr7x3N0fFGA)sMftSK(FAJUdYKAY9k9y2GFm)W(eo6tVjVgZBrqfIs3(BgBZwTr8smJR(Pv3UWnj1wmvSlzTOqFiNiBoTAEiM9sFcy07KjQqkRRAVdZrQUI9yWGdY(QvDT1(qeSsFsPWQ2k4jfSmyaoDIEgPUX8zLvwkSowdqzxOZ47yaFYSkKOXvwsMzVhpOIOtkeV65lU6028TlMpsBEm(Ew3HPh6(pU9LwHmImaaIWwGOyJPPYeZBXIcMsRA3Lz)EaMhFF7UnahVUaOOFgf74azdEWC1aP1CfPnuoXm6TBTz98PM1rdyBwF)eZ6OLSnPxmXKCnPT5D7eZ7mBBBY)GxYePPEKmSzDUh(wOVvoZpQ3w9FVLrFlFWJmkU97W2prAga)4LpaEYCT)2zB)KmeCRIthcV8YhcpjU6pYFrzch(lEi0b40bq0IrNaN577CPRZQcE857p0Z3G7e0ZPJT0rkJAP03aPNYlEFbN(YXaEhaFJNZu7s2KW541hXtqFpRZeCA7z0lv3R90X3MRdE3seUk)GlN0YOVb4qJsloFVUVMYJVgZdThdA))IX16Tcjk(3HCwbRjD2VD4VkqBy0)(]]
)
spec:RegisterPack(
    "Shadow Brand (wowsims.com)",
    20261113000,
    [[Hekili:TR16UTTnu4NL8hhlup5lPoRnioaTRyyDRRRyUa7FsMwI2M1sIcIuXZab(zFhQBMsMuwYXnjyBOObk8Y5opx(ATgA9vRPUio26ZJgm66HdhE1GbdSMY3gITMgICwJwcFeG8HFoDfYLUz3S3hHcC3nR7g6ggXNz6q9nehERhf5ki48yIh)JbwZvsBwi2XA6F9U)8t)Xp9B34I9Pbup6YTwtxrCDXPxdZCQNH3SBgFfE3SS16VGgHVhhTBMlEbk2JVB27(YN2ndwE3SQ0jM0xieS(BqrEuN19Ddz9fcTlRVqESzjxWEU48MjBy(ngnWOhWuynMhOvaH4uHqqy7MHCDPbxcFSgVLzUB2hqC0nkeUU)(h)kqKvCEi7M(9xs4RINl0N(voQbqtqhWJrV1XDeAK7chGSVhl2otZ)GWYrCkuloYdhWbQpfJIibl3n7lisWUzEyKll7oEegq1UeoSW80Rje)GuPlouOHiwHGl0i6MG87THgdwcWvhrxq8GicKdNqdyMHryqhMJ4tYTCuWd8RhS9RM03HgffhkwVhzXKlCXZJxSWC)QMXHfxCsmdBt4yFwpXx0flSx64ozyXba65MAfSJIdW6pLp6B0iBFuaYoKMWCTh1b55zN(R2c1UNi4FcdmOEyBFiYIyZrrlXCBN4iGiqOl4eKiWkSN3csewOFIvVhBJdW(em7Ujx1HtxceY0NEp2hCxD6Q4ijK3KgZzex8ydzIphfiKBBxk1V3cQtmBYibJwqwUIBhH9bxo7UmRQ8HnDJJqcQitnwAKIDiClzQ1TBUJj38M(uio8bLRNX3Bhzo2OZfP03uM4M4)g7eZHFTt3louLnEOQoB0yxsMZWLYtDfhA2BI)TKJTgADxdOLdL6bpccyPMYmZrjNX6ay)oGzw7Mp0TBjF6pm2OFDUvJBhA0Po6DHQBdV4nmEOozuZTEqFC7giPgjaCHL8HsjgsmlPzRmj(qYK7XU2s7BIdqZ9WUDs4SiDOhkl1qNIaZSZFFSxaocnN4r4BLIpvUDEyAU6kZtheJ)kfRd57b(BZj(ydPyBzPnp02OfzbkzQA0tsvSols5evN7kfGzuoRkIVY2Hs8kZB5N0Pmx1ocMxdX9ilepBdtiTiNSzOJ4b3TxnOt58yxpqxmKo6P3kLWiGjQmwuMu1QJKQFs63WBbOIQn2ljnoRNZwNIKrqghzxhdZfHhmteJrwgab7jKyYL5x(srsXUn4y5vlvjb7FvcAxXjGkVR9Wmwa83Sx0A5J8zpKxLOKsETbJw3e(KFUd5rbfe5L6CHEtsan5JlLYXCm)MiDTkD5K8CLnvcVxvJrjxZrmiTXb3qr6FZEVC(CsEU9I)tPx7P8zzdu9ZQNtDRttY7yaTKgSTsZLTVlLov3iHSIockxC92XhvYkpesnXqDvoDshLTAlDK8oYADNU6LxIVpvmZzJK28dRvwloWPlPA69(jZPx74oPNQOX4Jk1LdioFbanIZfU2ZJRuINfJHmbhhHxJkpYBP(6uo(H29QFUfv(Y8gVFt9JOuZek6fg9Z1OWuiMG2JsDTxehT9fGbz44xcwemKspAneI()wKnkhwTTc0JuzQutBYqnIzPbPovpvDY)OrNOzf8)5ZBn66bd6ipL3RhzC4yEGgAn9Eiqeyvf8IfaRWsWPofzx4ZpNGBDgmbwV3AQuCRyZmGjtxpbarloq1gEjziff37QgEVdazuC5xx5Y5hUk0rP6PDks7hPzybDhRHU54oaCic08ickDVhnkKcMEDfMUNfnh)X9IQ82afe1)eojGp)Ow(udYKFVGM8W(G2RcYeQSk8gTQq1h3TlMOAlecE92gYR7AkVu3iQGvdhuJR5elhC2H6SoSoBDUqXmvncTZgABlsGNyoRMiRiWAFfOs24VxWM(SIBAILOA25wMqRK3iHGvtBlzf1Js45cm1MKIyOUAd7rFvTuFikSnfg2e2QR0rE7eLy6XWNnHIvRlOkkwCUQ51RJZ14JocuUwI)mT4F0rv9lOra1fdUF4UssOQPdtz(XkGxJiPefjyz5j)tA7OiussKAayvNlOMFsb16fcCL1gJOs4F0(TNnGMpFin)cY3vTKWb(UC6(O9BplWm)e)KSbk)5XVX139RIePLgwiZG0MMeppOoE4yojhOChavZLixSxvXLMd9O6AxY8UU2JYi8ja)4E(MVxjUYL7)TfZXNIGPYUHupqH2npYOi1HgYrqVSgOPonquAdMf7r18z2iDmiV(UyLAkcn7r68)IwjDJBOBwZwlGpwT7qCpRdPlLJRCY(Y60hbmONMzV94GMMKudampPv7k7mUD8PvstvzOM1B1JSeyZrZRMgd3xeRLYC7lD2g5njgbfZxrJSM(l41epYUzD)5S)RdNST1)m]]
)
