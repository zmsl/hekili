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
-- Unmodelled: the procs' rolls (Nightfall's Shadow Trance, Decimation below 35%: the player aura walk reads them where
-- plain), Shadow and Flame's buffs and its shard refund, the shard a kill or Drain Soul returns, the sim's spent
-- shards (a list evaluation reads the bag count; two shard spells in one queue may outrun it: gaps.md's reagent
-- prediction), Life Tap's health and Demonic Energies' share of it to the demon, the demon's spells (Firebolt
-- 3110-11763, 10-115 mana; Lash of Pain 7814-11780, 65-160 mana: pet-bar, D6), Bane of Havoc, Curse of Exhaustion and
-- Tongues, the armors, Fel Domination, Soul Link and pushback.
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
        },
        {
            key = "destruction",
            name = L["Destruction"],
            tree = 3,
            icon = 136186,
            role = "attack",
            ranged = true,
            package = "Destruction (wowsims.com)",
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
-- the in-combat calibration replace: wowsims's logs at 60 (the five builds on the preraid gear: 1.04 a 0.1 s tick
-- inside the rule, 4.428 outside it, Blessing of Wisdom's mp5 included). UNMEASURED in game.
spec:RegisterResource(Enum.PowerType.Mana, nil, nil, {
    fsr = { spirit = 33.88, mp5 = 10.4 },
    base = 1373, -- a fraction cost is of base mana (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
})

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

    -- The player's. The procs (unseen; the player aura walk reads them where plain): Nightfall's next Shadow Bolt
    -- instant; Decimation's faster Soul Fire with no shard (below 35% target health).
    shadow_trance = { id = 17941, duration = 10, max_stack = 1 },
    decimation = { id = 440873, duration = 10, max_stack = 1 },
    amplify_curse = { id = 18288, duration = 30, max_stack = 1 },
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

-- Shadow Bolt's: Shadow Trance spent by an instant cast (wowsims talents_affliction.go).
-- shortcut: in the belief a Shadow Trance up at the cast's success is spent, a proc during a hard cast too; the
-- player aura walk corrects it where plain.
local function bolted()
    return function()
        if buff.shadow_trance.up then
            removeBuff("shadow_trance")
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
local function branded()
    return function()
        local r = talent.demonic_brand.rank
        if r > 0 then
            applyDebuff("target", "demonic_brand", nil, 2 * min(r, 3))
        end
    end
end

-- Conflagrate's: our Immolate consumed, unless Shadow and Flame keeps it (20% a rank, wowsims's curve).
-- shortcut: the roll is unseen; below 5/5 the Immolate is taken as consumed (an early recast at worst).
local function conflagrated()
    return function()
        if talent.shadow_and_flame.rank < 5 then
            removeDebuff("target", "immolate")
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

        spend = cataclysmic(SHADOW_BOLT_COST, SHADOW_BOLT),
        spendType = "mana",

        startsCombat = true,
        known = knows(SHADOW_BOLT),
        usable = unlocked("shadow"),

        now = bolted(),
        handler = bolted(),
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

        now = branded(),
        handler = branded(),
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
    20261021000,
    [[Hekili:DJv3ooQnu4NLCtgqnkqMmDB3rkvAARQ62UDBvzL6DagSjXnGncB2OinIN9AdHGTdmduTBsvVyg5C858D(nh)P4VY)J(Eqah5)H7DV)nRCVFLRRRVh)yoY3lheVhSvCGaYe))PKKuCmhtjvHwhOhy4m2YyAMTuZJPuauIwujoL)oIFuVaZYrX(E)1t)57)9F4xFeCgrFVDyie1ygIf)cE7XQq(ouv4jzoj0c0NqfvHqucOmLxf(0F8(QqHyXjvqkXos3ZCoaksPX7DG5mhz4czoIij4qHiFxwly5FZOe7fcpvaiSurEafNPspJzvHaiKsUtCyp6iBzv4pc4Gh7jIS(T39rbi748C2JooBX8DLrYKWXqvBbMIahUE9Bx7cDFWDT7srvTGMGtfvEqDkW2uYqbyokJTqEIkI5TXWnRQ(Ltk8vBCGOmkbhhuusqdRvminnO5JbPygFHSdVjIszCMQEGS8uCYXG4YcMbClWjBSSM1O7YiarExaylLCC5Ec9a55zquuzsIXDL52ZNvlxdCPCvpRz0IeACjBZ9sFoeQAPhTOOmx(P(SS7wdZy48D1fKeuF2PCTP)KzGmyedMbOuugIWzQqWqCoMSLTeWy4TeeSjP3CxRY3n3AML1iuRnh6ZJYA4ZwN6iN1OafVpfXyeXFnDM5d6hvDV0xAi1RVoGa7hJFA17sFCgbb(229wKvdJrvK1ZkzH2mU1QIVsSpLEXidP)JwOBvzuf5opDnlWxZH9rK6JViJZYOY3v6Brt7DgBzIqcul2lcHPUjEWfXNTszNOMjA7kv0xDxOMb6ljvS4CsPPUsQk09)LJnxZV6Y2bG0dbr0uEVVG1C9NktjOcqeofZnF68seQNVunxYjk2C4SM8u9K4mRHMPgEc1(5mmXAidNF5WybkdGjm7fwdd68Eh7BT0(728Wq1ovXYj5aoOlzx2qtAtukLcdskloAYZY3tqPJj01G8RKPfRMXDdtvXXpuZahrarPiO)377PaL8Ytu)AKxt9ZNlqDKgPsguA3Ad7A1ZKoytOg0q7VjDLM)WiDRgXob6fIaVad89E5TutNWOmO(AJGQZBdbxxGQDJVx98US6kG9nVkSARgvQLNfRd438QaQV6Sdrf56q(Tdc5iws(5IV5vDz6x(TPknY(sz9gWBNEd4MXf9Zhz0Bstqnk0BcRCNEx4Mqw9k)nLrK8tUl0QGrhW8rSl3TPWZRd2wHgOn2x364dpH3y(xqfE6CHNkz4BlB4R8C5x8LhYzitMo98AB)CHvE2TJpOXaQjpOoW7LM8ld5QAinzX0ArnTATX7HPx)I8RVreSRtotUu9voK6zsrQvVwk4(s1A5JobUZDm1RrqGbOKVJw479ZO9IgFvO1pD63HT(A))5d]]
)
spec:RegisterPack(
    "Demonology (wowsims.com)",
    20261021001,
    [[Hekili:nJvBVnQrq4Fl5lxGEUyWoj9UOWjDxpv1R9A6PsK63awGf7TgyrSl1Ysr8B)MDbSbmKawPovrXcV7mpZZm7lZd22W(bBRaehBF)c9f3yOVWqx3W2IVlfBBLI83GwbpKGIHp)moMMqJOR2v4QSLULrIzA(0yvHL7IOOabAE5Ki(xsS96fywk2326V)4F91)8N)9Bd2JOT1AsqaU0nmZ)jI2TfU814c3QXMhsZW)loRWnahIYJ4fUF8BFTWfgUWTfi5K5IWZMVfLfr93mpiLnxq3a2CbtCcjzyhVmusGMCyT)HrtuNbXdgJfbzta8mveFcRWffeqtUeEydEhtdcgIJUThEP8hF5baK1CEk725Zxr4RZ9ePY8oMQcyc0py5Y3Vupq)k9L6aSFchr3w4gbwev4A8oaqpSWJcxlmkJKSQW9BisIAnVsZi0mchs51i4RjaHdjrrcQaPwHlBne2c3VscbiEaLw46H5BX4KcxchM4Z0hyaFf(wrqrss3cZhryCXO5rbLCLVw8PKBsQwYl56JS2t8HrZKHLJIWj8zDyTWzuaRYNs8vK0WR0nrgLuwiZtvFEEPb7gZOqcd7yr(CcnHzMZWoeooMnt8enm0zLFGPrXVvzWBnLBaa26KLNGh2kFuuKt5xDeXCM4KHPhLY4SzKqtfLYj18qjciCcO0yTnjajFJIYfdo5JbyV8WW2ZaP7BMQpz4yOOYUZ04kvv1hFYyEXqbnKSAn3PgQB0vvF(AalnIWDAwjMiZfb(cfLwX(hvu4Ky8BBnO6pORT8Av17m7qSMWnlK6NZmxiPYajA788dMqI2eow52uNuy2MWvJw9oMYlmYt7JkOv0KDT4YjTG0DcjShLb31jbiXXuXLw9r(656WB)8m5wFh40OdochdNyzn9NH5COOW0qmgzvcoWr6I5L1gFjSLvrzeMvrKEJOiPFS(O0ElYW(BIWmwc8F1zQbJttBpowTqQ3yTfJ2mM4uB3XXypca(Doa1hngvrUDwjk0D5DRQ4ZW9PSwmsk9)0cDTjJQiFisNZc85CZ(is9XxKJazeoCuQOMMI5AXOe0Dggxp9wgv3Q6tIrYAr7RMyqZDPcTQfrJN3fFAwwEQ4B9Df4Hz7gPgx83xMUFmTsUB6frPboH5z7gq5GwZu10ddf1SnqiABEz)Hj1a8Xjy(hmnExJgeT4eKD48m8g05MrlemY2cK3Xas15LfeBvyY3Pqss4P7LVWcob5fHdS)KTvd6kMSsXh4X(LeBo8Nv17gmfi2lAe8)(fJ0PMYif(TSJF(GWCCgbzBDYsfpjTIJrS4tRwCkYfpup6EYVCr1P8fkRwwHY0vprzAQz1PjKCKuU5HgbXVEyIpEvNn222WwBl5LwI9EqGUzWanKE0dO28cT2O(tNyD)fqP6XjT02287DpBw3qi7beRhSnyVFqWgrh8xkvTN1o9)3l3QXXM(s52lag6tFf4vtY7lNM3xLvHMSOZQq3gGJyv4vrt8z(OYis(jVkuBqNvGUQjQ9RwHzZ1KMAQLopSKIJvdFID1mgUF8tfJ9s03NUgs0gUjzVAXBq69d3Pa2TByVD6eg2Tb3rvAP6Ww5)eKiEqjF7wNts7XJtuYmiIFkksl11Fg53cj)K1vuoFnnZ26xXBirKcxLFP6h6woT93)d]]
)
spec:RegisterPack(
    "Destruction (wowsims.com)",
    20261021001,
    [[Hekili:nJvxVnUnqWFl3lxSqnSLJtt7fCQaj9qrtB61IQa03KeLiLnRPiniPQHbc0V9UKY6tlNto4AsFicuK7o7S7sRzrcwe8yGpgPjbF(s3lVEH7LlCDxe4R3VLe4VfLSbTcwWrzWZpruAzEIMk4frt2j2POzQzjImhJP7zce2axCoLPVNhepiYQTKKa))62)8HF)h)1BWnqg4VMIXKs)iQKNlE3uePxtkIoS38uHK8pezreMKIYz6IOB)JhkIGTlI6IsoDUHbQ57qsMizZC8w1CdJXQ5wYiMzFB2FReCNPqCKiUIb5bgwlmXLQkIqySGFbSydzVAgeeKgDZa8zYVD)JaiR16TQBMpFfvVop2KcZ7zQdGjqB8YLFyPl29k3LUaS3ryIDfrmWcwr0vUaGXeJhfr3ZtOCIeiMtfP2kPcjvVhIhcELdSnLYygEG4a9vRHywe9anf8)r02IOyIEhHa1fQgo4tIhvazn(EGDMmuSdoNrvAZU5mCjr1RnpTeBg09LcisWveKToR8YvKqQMKPMAwjstdxLG9wu8lhm4B8GQDMGttcL5CYPTkbXyHLVgAiXuZvrVyHqPvtPPEtMuE4Sye3ariwiYMTHdS(9tM8UtE4tysCEAA3tY368(Z1hjjdr5Qp6T4khhNNE2y(Utf0u6Q16WkOU21XPDnOT5ttfj5kVlT5(jWRlC)GhG3qWHwj477G3lI79pWc7rS4J9irsU02YdHFhhsyKmchAOTiJIO1u(k1mKsrxXj4qRlExuz8fqRAYKry2b(nyenzWtvxHQTqss2Wikfh(7WDPtgN22ECS6G0GXAhbTzmXPYUJJrnca(odxKBtJrvK7MvMcDFE3Pk(f4(50lgjL(FAHUYKrvKBI0Rzb(18Y(is9XxKPzzcJqC7AB1hFQod8QtFriL5BnVnKtnNEKB8ugALrCT87ShQz1rPJCqRy3HVQ1iSyxCUK3jlQ1TBVld0Kd1OgwmRuIZlMje4W0C5((AKb(WydkW2Edyzujv2X6kNfcw(z7yEeokMrWb3f43ckZHhKTl33kBhObuhPtTfYn(TSNFjWmjejff4)IfRFrQ1JrU(51Rphb7M6r)rwkBjHLZqx2wnLPRoDzA866nrTTTb(2B7MwieOV9z6hVOKF8k(htpRTD531NKFJ47DFTMb4v97I)3lo1624qPC3gW3D(nG3S5d(6nGWBstOnl62e((ZVj8Mm)WR8pugrYF2nHkd62a(WjBadmKrdQvB2fSfUFr06m9rlwwVDpe7RH34q9WkDfrgEOLHMAXIFF5(k8BgJXAwF1966q9CnwZ6RUvzw1GoGr6A1WZycLM5HSiayGY1RfYa)FMSHYOfrt(Pd)hvShh8V]]
)
spec:RegisterPack(
    "SM Ruin (wowsims.com)",
    20261021000,
    [[Hekili:nJvxVrQnu0Fl5LeqDeWKjnTBuPsBBvv32KTRwwP(Mbd2mJ7ySrythnsr8BV2WqWWazzgLM0hsKX(Ep379C9hhnGLGVacqqjg8XR9U(2LExV0ZZdei3NJbb5WKTW1QbmyM6)bpuf95scRkYAhFNGKjCs4z2A72t5qKgR4scv(bgiEuyf54eqWF9(pF)F(Z)XDW0ukjrs4mqWgccHBCdlsMmw3vfj3GRIomNBkVa)p4IQieofwsLvrV)t3xfPMUkYaIsIRo0c3DWckpzRlkx4QtvKWvKfwOSYP(tN)wWz2lurPaYeuvfGuJ56OsevrqeIZUsnylEVWPk6xGs4DJKnwp8HVOazJuMlUZ1DnrUPmwxaUdm1wHPkPrRw9UvEiVB8w55O4ZcEkHQyCyn7i8lf4qIeNjwOhXttdxNG8xw97hm4B8Dr4moJKOQfgEARsGuAyZNHuIqUq3z9J5CHuSGK6Bz1SOtmKPHieX5zoBz8DSlTSUyYfFeHJltt7VszU9LNQpf4miHj(b)L3yBB)4ZgZlMkOPK1BKHTqDRNTTjhaZYPK09HjLfIbuvdfCwX8iNGR5S9t4vZAJMQxErTL9ssTLMvGzWxKYtkf(xxN6tKD9JYp6RcZyWvNv9W7SyIPk2JR1E7m5ffL56VmZGwS6wvbKPBInqeFxymNkp4xDtS2PdRPpkNGh6hjFt9zGu8yXZy5bow3q0LL6EOqmfNHzQJogqiWsjHTw4afcYAgg10d9VQ14Ru7vSSMHzT1(yruZ0p2Ey9jlkWjBPyHGP(7WP2jJJPThhREinAS2HHBNtCAT74y8eck87FeD00ywKC)Qst0dZ7ES4xj3pLEXmtP)Ns0TMmlsUlsVMe8R5M9zu6ZNKjzzCTuIXUOPDTPVwZCA99rHsyNPonpD7ht5CuyAzX(HV9dcuYmekBhift)6VOw9xJYj1WpwRgeZGXumc8tGadO0lEqosZ81YrasfQZ0jtbkA)wnWVKcfKfeii4SfHCwQqMJmKNxhYPiePJpgkfRPLe2i1UPTQPPBMj92tWqF288Y9NvqZlHIgD19TtVjy(Az6ibtBbb1h30Bqvb62Nz32zrpZxLZXPxTT9ZVVBY8BujqgBJEA6(a(9tc4OAJ6a04QNNqCPgX39vtX(QMmGSB((j5sVjXCgpz8sjJ6v9PL)7FF3yVXyL8GoWW78Nrh4ntJ1lNiR3KUGzwmOlm8r0z0fEteH9kFuzgf)j3fAnyqhyA5iJivRd22jhG2WxTh7YvTDdF)R1UwHEaTzTQbobfAD6bRrqHbSuUHxac(n8wcLufz9Rh(fOQxg8Vp]]
)
spec:RegisterPack(
    "Shadow Brand (wowsims.com)",
    20261021001,
    [[Hekili:nJvBVnQrq4Fl5lxGEPyW(U07IcN0LEQQx710tLtQFdyHDXERbwe7sTSue)2Vz5ndyibSsDQIseE3zEMNzMDzECSnS)MTfgji23VuF51g6ln01nSTe7ti2wji)TO1WdXOi4VwBqy2UC37srX4CxLDSDCAexZNfPknEFidHLa6LrdfFo22BqS5jeFBR)(J)1x(ZF(3VbtIyXSq2692wBOymP0nc3)Xd4n5UInKC3Q1weWsj)ljn3ftcqzHIC3p(1VK7clN72hNm6cjj4l2Hsdz(BxGt4lKKgZxi5JdVWbhpP9AfBO9pCwS6vqqH14Hqwbajyssq55UimMfFj8WwYEUwU7Nqc0ndqoL)4ZFdazJqKWVzXI1uXMmpz(SONPQaMqoGxT69R0X6VrFLoa7De52vz(NKvoQFtAjqHKybGUfbLsJxN7(veno3nKGW8kFcPCavfQawWR0nj9JlzxwImdr8gIlZi2U4A)2XYGkb0Qtzb0q4ebYxqzXCZmoXHkir8RKpXccCw7JnnY)TkdETzrDfyRtAwmzCR8rHHoLF0rgZRKN8m9ymUGFfnWurPCtnpuSechmJfPTngi5RuuUy0nFat8Ycc6UdKUVAU(KsIGIk)wtJ3OQQ(WJgZlglOb01Beo1qDTUQ6txd4jHuHt7kXmzUmWxOO0j2)OIIGgrEDNfv)bDTvVvv9wZEeRnCxfW8Z4MllOYijA388dMqI2goE5XuNey32WvJw9jMYBHzjdrf0Aw8(oC5KAi93Oa2JYGB7La0OiM8nbdr(696XB)S0IJ(oWTrhsijcUXYB7pNieqrHRH4C66yc2PWfZlRn(s4iRIYemRIidgrzs)q9vPglsj(BdjCEm8B1DQrJtBBpowDqAWyTJG2oL4uB3XXObba)ExGgIgtQi3nRKf6(8Utv8j4(C6ftKs)pTqxBYKkYhI05SaFopSpHuF6f5qAaXrGsK10eIqlcfJU14A95pYO6TQ(0iurTO7RM4WWDNaAA9RZmEAx8zPPzjYpn0RapSB)ivPUIbQ0girBwtRK6MEHmg2jilD)ich0ANPMEeOMMUfAaDnVC8WSM)9Wmm)dMgVR18HoCcYoswkzl6CZOLsgzBbQ74aP6jexEsHxOxVGKWt3x89biXiVqc2(oBRw0vUzLGpWJMwITa(XQs09CGOrZi4)9lNOtTvrk9Bvp)8tbitPiBRtwP4jjvCkAfFCXIZrT4H6r)l(LnvNYVVwvBfktV5rktZnRonDKtKYTV0ij(BhN4tx0zRJTTS12Q4DwYZEqGUE0anMC0dO2wiBxu)PtSU)miu94KUW2U87Dpzw3sh7beRxSlyVFuWMWa8NlrTN1b9)3R2Q11MHs5Unad953bEXu8(8j59fPl0Mf96c9haoHUWlIK4Z8vLjK8ZUluBqVoqF1e1(vRWSDpPTK6cNhxsXXIHpXPAgJpp(XIrJc9M01OaTXhsoOu8wKUz5EfW(tdByWbL7f21F(2rf6cXHDs)zOq8Gq(UtoNL0JhMPIzqd)CeKwkR)mYVLf8ROUIYeByP2w)kzlnKM7Q8lv)VJl22(7)]]
)
