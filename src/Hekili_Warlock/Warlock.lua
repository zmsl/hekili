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
-- 3110-11763, 10-115 mana; Lash of Pain 7814-11780, 65-160 mana: pet-bar, D6), Bane of Havoc's cast on a second target
-- (its debuff too: both wait for core's C7), Curse of Exhaustion and Tongues, Soul Harvest's regen, and pushback; the armors, Fel
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
local CURSES = { "curse_of_the_elements", "curse_of_recklessness", "curse_of_weakness" }
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

    -- Bane of Havoc's debuff (1225228, 300 s) is NOT registered: the translator would read it (and the cast on a second
    -- target, which it cannot express, would land on the main target). Waits for core's second-target cast (C7).

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
    soul_harvest = { id = 1242853, duration = 10, max_stack = 1 },
    -- No priority reads these (wowsims talents_demonology.go, armors.go): the player aura walk shows them where plain.
    fel_domination = { id = 18708, duration = 15, max_stack = 1 },
    soul_link = { id = 19028, copy = 25228, duration = 3600, max_stack = 1 },
    demonic_knowledge = { id = 412732, duration = 3600, max_stack = 1 },
    master_demonologist = { id = 23785, duration = 3600, max_stack = 1 }, -- one id for the four demons' effects
    demon_armor = { id = 11735, duration = 1800, max_stack = 1 },
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
-- unhasted; `cost` a fraction of base mana (PowerCostPct), `shard` its Soul Shard.
local function summon(key, id, cost, shard)
    return {
        id = id,
        cast = function()
            return 10 - 2 * talent.master_summoner.rank
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return cost * (1 - 0.2 * talent.master_summoner.rank)
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
    20261111000,
    [[Hekili:TR16UTTnu4NL8NeB0m5lDPRnioaDByyDRRByUa7FsMwIYM1sIcIujWab(zFhsDXIYus0Qjozflfnqv8C)cpKFQ2tS)S9CpehB)PPJN(MjWpJhp2EoFBm2EEmYDdAf8qeke(9799diUCcnA3Ib3tVNrczwU0WHck3gqrEcPTmLeW)qK9sTcMfJDTN)pV)V)4F(t)(1OsjApFnXZdNXgM52I2UE3c(A8Uf5VBKpnbFhoz3cpSpknGVBX7)RpUBb8A4PQcjLmsOE2O7rjbu3nJ8IzJeMRhBeyjo3Na(RL8fwFHrJgEjOPeuela8dp4zQqZe2UfippA0fWdBWBzw7w8Zio6Anw0G)4dFgeYAopMD9OrRi81PlfoXOAKoeKjy44RqVZ1BkAQNVRfevtO(KaiYJKUaZkobdmVeXNXwJ8O37SKc(7VLV8SL4egozdjA1LPmSdf8PvUEZMusXRMnsSaHJdzntIhoKgrCDssJWntvi6l0eNqueYjMkEzZK6IccCY(Nobeg)sr90mgyNbyNqiLrC4OKvyUJBk4bob0ve3QcyjksiAhpkn8sI)mFYQ1CNeCiIeXU1dVm133QkrwEPjizA3uZi3a8O8m1luJG27Wo4iCibZmXNuCMwK1TkYQsY8sFQBkB2ubldKUv(IIcrxSvA8dd4OaCe3Iec1h3H9CQWUfocTma7DUKvrPvGmma8D(GZYdu50FxAqeobTKeq4BfcUTLZJ13miZQTQQtxeJ)knVhmzq)oCsiEi8t7E8KVX9y91lUuAaWDet69NLlsLk5nrW6pmyqJRD(G2zuPz57UA4O26xgEZKHN3M8oth3PXG3(qlMyJmPUVdIV2XLscuIgvdW5(uptj3Qeku0DaXxShqSuZIn1SIDfDV386XNRUBZBgRWOCOHojv(oRo2OBw2ZqybgR5GdWHqToR6gbmmNdYGzHymYQiObqYYSlki(ciLnyGbKLNh0QrrcPm0wsbmXztaMXIG)MNmBupvP9qDPijT66EmAJj6PGUd1rPeulU6kfi6p1zMgLeu9ArIOUFPeL7W3oMCLHM0)rtefIWOKWEl5uMaoLnlg46MMe0FkLzOWyyZRTzYv90CYTf7ZyHwNL02qTZkgnQUycg5TT1rnk7wFtRZ6gQX8qROrBBWPYwt4vcM2FAUBUQZGBLdXkLIY586vGTjJRx2MlnjjnwqKIHvOJ9lluG2tFxHKI4ROvu1yUD2Rh(qM6TOPCgXdFLMDho6kZZAUE4HMZVqzuVI8FtwsBqA4ewdRwInzQrg3xrr87msbms8A5X39XA1qL1BSpPknLnkDCpLkP0ak1ZXpnPmFMf)2)ALc0menYPu5DURrrr4aWvRM4lVoYmCAcEdsxRw)Q9BT(qx5rr1(BBVFRx3gP57WOjuiQ6ldVVacitU6fqerwe1zF)tGBuB62SjnyGk3NRV5O2S)Pt7za98SRxcxTCYBhR5YLGdzp)oCcdKCnWtf4gWKi2MH0j84NKi4MJbI9pApVsbQyXCOdTNVhBqBoiwd5QeTqbtV2qMQIFOGVV3q(oarrbZxvJ5cIRJNsw0XjdP6oULHqUVPb5wnHbAjb8(ecYEU5qokK(put67Lt963JZJQpusOR3AOUU1uDP)uIcv9Ugvvdi390bD3tn2D7JvvickdeJ9f9pq0yY4)pCKfoMidh13kQs4OLnG7)uYhDSnBdCZEHUPHnCLdUKHX67nVFB1c4r1gApeM0hlCsLwv9n)lSQIbTk2uxaOkLy9XcfsuE2cjfnT3FPo5WFMx(rX0nouxvRKRUgrOrw7Dqdap6Xcq2tkitp9ibwPJqNlRUbB9obdsapBGX(4Hg7ZssOQvOMeQ34Bqs4zbm2tCJIbo)rNekiqjbWB(WFhXX)vqqtD(rlyN1k4zTJEw)Gp7Ra)SteaATHGw77z1ZWL5yKD4LyK0AA7SHaLvPUTKovvuFWUgv8mGu2ravwlyLv5ef7nV69R7pp3r0HMH42j4uZTHQrhOT1c4s9dmKJblI9zUN5Guxqx9KeLA683zNw24TzEk8RdXKt3UafgS2lm07SyB(JaIU(fW7eJUS(8gak5iA6BESC)gw0744l8zRh(rnpTZApu9NGzThsshFz1d)0QDoSwwhJs5RPj2Z)v8gyq6Ufd(L8)xPkx2(F)d]]
)
spec:RegisterPack(
    "Demonology (wowsims.com)",
    20261108000,
    [[Hekili:TR1AVTTnx4Fl5lowOzYx6CwAqCaAxXW6766kMdW(MKOLOTzTKOGiv8cqG(T)EOUzDHsI2nXjyBOObkKhEUZZ5WNwJjg3zSWbXXgFz64PxozY4RgpESXc(dbyJfbi7TO1Wh(ip4NFe7r9PU01peBnChDhJ4X0TPEAckFWLICeCBzeXL)jFJLszmlaBBS4VE)F(5)4N)TRDk4OXInehhC6XWm7oK21Xw8n4yRS1gTIgIVhhgB5GxHIC5XwV)RFo2cwo2QctIiJeINnAhk0LAVDKtaBKqDDyJeAI5ksi2CziY3rpzz9VXO(AxaYdwJ5cwJd8nviFcl2c54q9ph(yl(bMoimehDTe9A4V)P7aMSHZdyxpA0AcFt0sHPmQgPAapb1hpd9oBNPOPoRSb2(bSlDxSLlqHBS1KRagUelorS1cmkK4Vo26RiIVwUEfesOHeoyYBqWV6dk8kIRRqvatl2ITbeBS1NjRawChki2AjMVdJ9JTiCyJpsVJb6R4SzkOWiP7G9DjmUy1ixNuDLVr8ZeDlrvt1RK4tIVNydRgMiwoYf7ZVOMwlomYHLDMu(pmrnwMEmHf5N6iJc06xV0HSXqkyWqglYMtO(m9Gqm4UxI4ZzajjX54)xJnFZ8reppQioFbz18ZCWlJwTspFn9OGIdnpIHnjCSh7cXx0vRmxB7mFsbbaVCsTFZWiFC7u5H(gn00d5JmdOIfBNuBKRRz6VAkm4lexlNZaxPl20dY8jMCu4Am30okeycK2dU)smyd21vy7cRtS69ytSp2JGz3o)Td401aJ09O3J9Ga1GHsijH960ioJ4GNPvM5lr(c920Hs9Uyf1oInFQqqRiR3WndXEqWMDBMpTmX6orHibxkZnwAoIzaCQYCB4W8WsU7n9(AuWJsxptU3mvFM2GZs5VEzMRJ)BSDeh(1bdpRPjR9yDBwt5qswWWHYtdfnD7QeFRey7Gx3QaVSPuxh4cdl1vM5oQem26d7paCZTU5JdhwjM(dZ0g1vyv7MjAd6IFNj70WDDnTh7shB5up2EE7oOYlXhcHAhWTIkhTskAEPKS8Zjz5NQKenilv1M4L4JafFq1lk5gEHu0Trm(BASk0AcQ9AYjE4sj4fBxKDRvT0eIVX0MsCt0zP3lsJnY2rOi3wrBRWCxOVcKVgKWArHn9aBrw7nVDwnB8YXATDNxgd3xYUNAEZt)gskGMkMy3K6zSYLryyUWPW0rmgzTp2j94ZppN4ZfvdgQazzzHsL4(0rWfwqb0UzRlMX8H)MLk3QCktBtzvHtsL1omARkYjNUMYOGdIlKdoRDxIpn5JZlD5QV4KOoLmBrPivvxJiAv34Rek6XbCibufvP)jhTYLJsrQ9Q7PmkDkV2PGP)KgPKptW88wHO1u)hQn10H3(Dq9nsyROtv1gC3mRxnR8K1LvljJypq68IfeKpuXbpSw7AMnnmmkqqKuDB)2TQDLi541VwgA8Kfu7Co9uQkMORxT(PpGRKmFwcLLKCX8ZZXrH4TOQVvRYSusNBU196EGBzXY8h2Cv3Zw3XO1TRmTpqUexH4PFUuQJ5QOWhEf4qMm71GhbdLSd3cjQ)NhzxZh03x1RNbRPwtR5tArpR86LJnu1L(pD6r6xhK(yk4HutVC84MpLcmiJf3djEaNRH6QabawcuVPqKcF(LeOFX(OLUyhJpySOuEQyZmSZsxpbPldoWvfpuzSVeN7TkEUgOHjo8pw7W5exhJJu70mfS6EgMvW3zTW3CabajecwEibLU33nCzcHEznHUxeQdu2EvT82ahe98ebjqo)uRYPdi0EUWqR5Cp7nHYmQQjCvRMq97Yhwor9bheY6DkkRBvvwYh3uiQjJ7i0CKL)FYXKRlq5o4sFI3iPeSCk6BlQxN4oRxi7aVgxrhsyy9ICvU6Ou69la8ELUqLVBXTPjjMv9AW7RvNdgyftTdqbvfvWeX2w178gTveAFWfMWX2QBxPsIGW61ABiAo8Nff)7)iRRytNQKUG5eL)OLYMKKx8Kk2(Aqjrz2Zvfqi5Pc)YtkskVsWeRuDiz(LQTPAVCHIELtiQypDGx(6nsvwvRgPQxbuHi1lc2LN4RCky8pprQCUujkXBFoTolj298rpV4H1CG8ecuToX3dSyY6(Owo)3lSyLcOf7wpsUFsTd4fNPyRjDye5J(26M9m0CxptVhC16a0KJ719hYRR3J32lStQpSyEw8sQILWEm4(3OxQTXUR(CBvlF(CyEnrKRlqzK(CHJoy2L9iaO74879IqxArXwGg4K2DRQV)MzVGTWocmJoXT6ocnS1wIq8hfX3qdnw8R4TexsS1WFj7)(NjBB8))d]]
)
spec:RegisterPack(
    "Destruction (wowsims.com)",
    20261111001,
    [[Hekili:TVvBVTTTt8pl5nowOz(PwN1gyhG2vmSU)DDdZbyVZY0s02Sws0qKkggiWF23rjRhOePEkopG(FjibYIhV73D8UJhpMmF487MpZgXXZ)2ObJUEi81GbdNpJFyhE(SDiRTO1WdEix43FgZ4(bwCc174IU7P7zexwplQRHG0douKTGDldio8V4nFPsoZ2HTMp7F(4F)1)8x(F3yNYY5Z2qSTXrZdZSktE3CCbFd(4ItVR)kQp(ES)Xf24vOah(XfF8V(6XfWRpUqMlbK(ceW6Vh57qT223EhRVaX2S(HGH2l8t9(oJ6zCfihFKhZb0dB4zQqUe2XfiBBQ3LWdBXhy9aHG4OBuGNU)XxUdyYgoFh7M(9xt4BcwkuH(5i1a4jaB8y0hSShHgzVYcy7NWo09hx4au4CCX7gamCjwmJJl(INfXd7daZigu78juFc)aipe8rpaTRioocCG8a4Z2aY84IVswbZ)o0UJlwI57XyWUq4WaFMEhdaRyUNqNqdP7HXDimU4Tbo2raLVr87qG1dw99PGKaxeuODM1BNpguYLi(ugmhZveaY)EHbFZ0(exxQW6Efz10lSXldwTQx876fSlzstdyytch7YUs8eD1kZ1w2thMqaWlBSl1Jyz6h4H1tLl67uFtxKhYChv8s9KAHCCmJ(OPWcCLioykJ4T2bB6c(zetoYFnMBAf4dmXHUMyLLbBWoocDxODI3Ep2e7HDjy2TtFBhoDnWOEU07XUypENUkijK99ObCgXgp2ilZxI8e420MsDVAf1kGnDKqqRiR3Wn9XUiIh72t20Se3Zoa8BeXd1vxpPL2uEKowuFQJHtYIvcVUvMxuVvoO1(NCs62nAOuVKTEGlANI(ogpCr4RyBq209MqiGjWixSz0leuKvorVDzGFnmlwuQdqShtcrs24iu1T7fAh8HUDLwQ(PXg9lB1YyYqJoLXVlunBqlnmEOmmQzwpO3DCpKgJ4ngyCdC2LMQKHhJ8b3mZDGri0EgRIKKuCXgSIdyHy83u81qwBiZKjN4InUvYkBiNXaX3yArjoscolIojAvJiKDjm3bYZcE77czTiFtVDwcF(jVDCh5y0RhinXKCIzcQ1BuY74FIPtuBRKfuYyQWDAc7kY4nn6zW3b2u2e7eMnJLf9mmNd8G1dXyK1Ey7OPp9YyIVeCS72TgKDsBvkXuVwqVtOa2SzRdMX8GFo5XRvozPTOSK4KszThJ2wh5etxrzKWbrCBNl0Bs8OHpCzMyWQwNePZuPl1ALs20iwTYR8slfvyaAYcAnH0pYRwXYPwRuPW95Cv65mSRgQ(zDLsDHltrU7GCLhIMPCvKr1f0I9QlDd(Y2f)I4AsKh0hJSpKU8OyIsBfnP0cqmuap0AQ3bnkv0ycTsUEGjJR04MP(2qUiTxyRmS6axRWM6TOlwdAhLfJNqqSLvePkddOKjJhYx9FDqMf13pyNGiLylDyTOldjThFAo4qLXmxO3t9b9EEIcCBJpXpMbBLoTspDyeHzGqLlOpJXPnb51b3N5y4AjZNKOZmso5GPtXb(4TivryTZLV0ftvRLXo5VV8WmnUbgLggP)KUkmfcxuhkfo9FG)HxbgKHJFnyrWq(x)TGJ6)zr2R)u3nfvpsnkxTith25SDUFDADczVk0xnOuQvkT19Sm8pAul9L6e1zhh6KrxpyqX(6ak08z3dbBaNZDtiI2jYcV)LOlTaE8BH3hd2dT0bBp)tZNLj2um4P(Rh9(WUHpNdCTMtkB)XfZ7T1CEf6yUyYVl3KJjoFdtJ0tZOBqQIJ8k47yn8nU7IGe8bn3NGIg7r3sDHqVoNqtfr9BMEkuZomWbr6eXIeiNFwRCYhi0mdA(kneY691uw3wxzP(ihcr9bD(cPTUpR8Bsl8RUh(camCGgeK2u)qYYhEPatnDFTZEx8lRn(no)wOjSonYVM(ajjLdnN5t80WyvjmeYW8zKswgZ02DPvnT7oEEURGqqPltx6LhOeskUeH6ElcHIvxIW49cLeAvxVqih1NLRe7ydlZifNXZqod4W8PatipHrHKLp7vbTNdFpl5MKvT3zIZt8nqRAVYIOn1QO4SGrITQTXuaMuUwJUTEUUlKN1UY(kP)6zsKPYUi7nM3BOgRsVy3dY57IqE9UsLfQYRu53zOgRuVi3dYZCixnu(NMvQyUiTkX1xqAdoBJulIL3LQKMdxA3HlV9WTR)WpIge)m1H422I4g2J4YtK2sl)zPlWfpswib1nZYJPzWvvhu(Ikvi1w2m4Sh)kE08rPPLX3G4YOokRSSXMgEuUtrznQPIUjxsRcBx)DAs)vs7Y8lSrQQUX9KyLQB3Ks788)pALkjUVXy5XQinPBZn9CGvMau3XBZCoWxxghLnkmg1kpuER9PltFeDQUDUFv2Q6O9g00MVgSrH(c4AxTaT2o(AVkmzxSjJFMlLQO4FXQxsZFGjf)lmPQ0kpz1v1ceQT(likdfW3q9Np73WBjoKJl6(RN()ajC45)l]]
)
spec:RegisterPack(
    "SM Ruin (wowsims.com)",
    20261110000,
    [[Hekili:nFvyVTTnq0Fl7lj2ybs2URERb1dOBddRDTzdvfOFJs0KNSzLePaj1mcWG(Tpsfllkk5fzGUKLahOW7DV3X7S5JgTe9juefRb0DRwSA9YLlxy(bfPVVeqrLysgEN5boUW83OpuN8XkgVoz2bXbfRqfqefZT4UpxGPwU2wXY1VLJ2okTQsGGI(8B(47)JF(3VfNMMZiAMGJI2ZOu4H0af5SADBDIEpuNCCTWuHe(lqwNqHuCvUUo5n)57RtmlxN4qrfl0kTk8awMlizH0svOTuPQqvrS0GkO5Fd(IsWNFJrfjMRYn7aQ5zHvvMQobtPc(1MhYG7vb1j)cwJVDKQz2hE7NmKSxRlv3ggUJP3xT1Ubc9Go3WPPOHxIFfHUcVIMscm9tPiLLB644MUJAdujHm8nvkiwKMgVJq3SS(DhJ(TBc3Mle040k59)lyaPcKzm(UZJXgGPHc15HqHcbNrm9moCEuf4ViKXfyooUuyx88qjvYMqXMbBmKdfaxRUjvqQuBwDdlDJc0AtvRcWkfBhhOXnPS56wWxF1SVz2SjaJcBRstdgvXGQY5)9ShkRoesGKLdkf38kiJloWV6S64IDOw9yAuToa4SPOtlUHACIbd)ZNpAt2TmMutU)UY2O9R7EDXhP2VKzXelP)N2OBHmPMCNspLn4NY3SpHT(0BYBX8geuHOWT)MY2TxBeVaZ4QFCZ6fUjP2JPIdXBf56J5S0MtJMhJzp0Nag96nrfszvzZzyos1wSNcgCu2xVPTT2fIGv6ELcRCVGhNZsHr40j6asDJ5ZkROqyDSgHY2qd47uaFYSkeRXLwsMzphpOKOJZfV(flUQFBE9I5NPnpgF1Vdfz89uwt)(3niNP0QMRJ8GvU5X7AUEcWXBZbk6NqroMi2Gh9hnqA8hrAdLtmJohtBwVyQzDYd1M13nXSo5QAt6LtmjxFwBERNyEdCETj)9EjtKM6rYWMBK94hK81YC9j9aN)7p1VRLp6wgf18Xq77indGF4YhapBgVF9CEFwgcUvr)HWRU8HWZIX8t8huMWM)IhcTa6pawU4StGbw3oh66427XNV)qhFJAR3XPJl1jkx2qPVbshLxSLVtF5uaVnGVXZa1UKld4S96I4jOVN1abN2vf6KQDzpD8T5AH3EpaxLF07x0WOVb4yJsloFVUbkRB(ncxP3lKOOFdYy5mZ3z)xp(vYBcJ(Nd]]
)
spec:RegisterPack(
    "Shadow Brand (wowsims.com)",
    20261111000,
    [[Hekili:TR1AVTTnx4Fl5lkwOzYx6CxBqCaAxXW6766kMlW(MKPLOSzTKOGiv8mqG)T)EOUyDXKY0ojobBRanqrK8C75OdpNNw7H2FZEQhIJT)YObJEZq4pdgmWEkFtm2EAmYDfAb8qeke(50Lip66TZ(qckYB7SERPRzKqMLln0uS5nbuKNqGZtjb8pfzpxQSzXyx7P)17)Zp)h)8VDThoKgrdOl2ypDjXZdNFmmZTBfE92z8L4TZkExFFAc(oCY2zEyFuAaF7S3)1pVDg86TZAlNusFHrW6VgLeqDx13lM1xy0ES(c7XHLDaN5I9BLTG13z0iZRaLcVJfaEfiiovyee22zippA0LWdRWBywBN9rehDTeJR3V)PVbczjNhZUUF)fe(Y05c)PFRTAcYe8b8y07C9gHg557cI9dyXYfE(hfroI7o3IJcWrCq6tXOes0ITZ(kIeTDwag5XkotaHbsThHdVyE(XeMFuU1Lgl8qeBNHl8i66OYZTMMcrcaQtO(KaiJa5Yj0iMvCcg8H5i(KYihfqG)3El)Qj9DPjjPXI3FfXFYfE45P((wvV1knE3bNKYWoeooKDL4jQVVZcxVjd3TbqEE5rbNK0iS6DfI(onXjefHCIPzkx5wDrbbo5)QJWTVsK8pHbb0aStiKzrC4OKfyUJBAciei1faHAcyjoiWNKGf(N4T3HDWr4qcMD7KxBWPlabzfsVdhcWLrpjBjt8w0uoJ4HhBwx4Zrrc72XJsdVYN6MYMmsOiFYILCNeCia5SBlIQ13SLxAcsiL6sJLNP4edNQU061ReykdV5FkKgFV03xO3Bgzn204IC5Bvx4w4)g7MYHF1O3f77YM332Nn1gskadpkphk2pSRd(2ay7qw3QHSCP0a4JGiwEOSiC0amwfbRBaHzLlEFVEnW0FySz)UGvZBgAA0L8Uq2PHV4nnVVlBuXPUxDE7AOOgjcGWgyyTcdzHL8QvwKqOyYDypNARBHJqZdWEgzAwuomavuAWyxIzX(VlnicNGMtci8n1YpLUCzAAP7wxNUig)vsEpuVh0VdNeInRLBx3AltTnpIQancvA9jPmvxKPCIUZTnsWmBwvfXx64sjbn1D9pPZvUSvekVdHhq8fF2gNjArnzRyxXhC386bgnRJ9MbQYHKjVQlCoq16j5pdPZWLIo4GSkXS6rBgMlquMfIXilIG8ZSJm5YYnFPOowpn2w5fCY0y1hsqeC3oGllxfGzSi4VfFeQup137(6QHKKQR1y0kD0t5(2xh7KGOuIXfQdjr0ShUSwzHdHtIkSY8fTqQMHgbA125BafhiaCmaQMM0)KrRs9OfsvzUNtu6C(zNgU(JksjVBMjLxIJwqJ20QFVJVXbJ2lKjwXL0nVV7MXh0YAoxqJB9KnGGH0UDRTLYMIo6MnvBFKWqQySpPwx5IkTTDB40TmfT7E2a1oNWiFx76f9Gw9tfGRLMFKHYA6CxN)tWPj4vOMtz2OvkPD8RCTUhvqgww2R7B7EQGogkqTXOEucjHcXqRbuQNJFAYMxabKHJFjerWqj7Kvqk6)frwlD(WJ1GEGotR7SMmuHz2y2LtfP6Y(hn6edRg5JsbJrn6ndKmif4q2tVdY7aj3Irwb1fSmMGZ5ofE8lzmdxmiU9hSNwlnvSyb1F5VpJIoBoivnpuDs7eN71AEU9OXtC4FS1Hl3CBYzY9tNCUSpqVSc5owHClNSh0qc45jeu(ApyE(ek9nTuALk0NHVktT(YGeex3jajqp)Ks90b3FpvK)TFBpvUqDb10fERsxO93Yhxor7oge66DAQRB1vxY7ZuOQHd6aAoXQ)p6Kj2fBIhDPpXisAXNOMX2D1RZcNTlKTlXQ6cNgX4NkIjFwzMmls0U68rwqRbAKjW2LTRffvZw5JfDL6uIyOQ7gQ43uUvVppN6s0zMAvD1rz3dnu6HyantITVxqwwSyFTRRVNMfBB6U)b5KDtVcrRk7PAkS6EL0X4Yv(HU6vIjvjxnO(5XIy2ZkfrVqi7RgSklU08RR2zeAGspBKY(4Xk7lxKQUP2ePuxOwdJ9SIsN1p50W5FAqQsP0aL4Q7aTZsID353tlrF7pQr2g0ToXdLTp53cPxM)dHXVk9wUwBKSQh0Jyw6CsdL2rI8M6vU4bghOlcioaHHDWg0PXBXXWBqfrIpZbPdXY0tsusxwsQix8FJrjvT8RAEVJ2aFOE3(un2fBtshz4KXYU8hbZJNwy)GupMxtubNhN1l3Ag7Vz8Z8nyNaHyN1B6ob7tXnIa(Js5lPj2t)v8ksaz7SE)sX)xxZw2()d]]
)
