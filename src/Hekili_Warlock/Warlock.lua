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
    20261103000,
    [[Hekili:DJ1BVjUny8pl8gAqdraUU76QetQBttRBD3MUCs7DjXj2b8WXgf7CiKQYN9zNqi2MK2KPRW0ErRmp(553ZF5X)e(l8)SVheiq(FC58LVFXI5VB(85(EId7q(E7aXBbRLhOGu5)FijHGJfygTi0zpBphNYNfZsNO08aHbGk0IYXeXJu)OwbMVdf779xp8PN(JF83UhCcrFVnyievzgIh)cE7(IqXgur4rzUjSm0xqzfHquciNikcF4pFQiukwEshKCSRY9C39GmclERlCh3vfUqURmsc2NjZ3zLcM93CgDYuPNYauorMhq5zMYZyEriacz0BKh2IoWNve(tab4(wIiNF)XplbzJqSJFVR7ASytEKkjCTuDIetzGJwE3TltMd(WD3cNjRQzSemrw5bLPaFvohfGfOu(u1jMmMxhdxTO4xpQW3SYfIszuCCqwof1TwXacjO6Jbemxmv1HxfXyCbxxpq6oco5qqCEg3cUP4KvooJQ0DweGQUlaSMrpmBlLTN(8iikkpjX6U8DtgpQuUb4k56E2WOPjS4C(QLkF2fQgPhlllFN6tTzzZTwMXX72uwqsqTzN212(tLbQGroygGiOuevW1HGJecmDnFgGZXRPiyvsV6MALVzSZihNEOwDo0Mhv1WNDo2roPrgkElbX5u5FvDMXD6hDDp3xgi1QV2JaB7JFQ17CFCcbj(tM0Arwpm6vr2mRufA742Ok(kX(q6f9mK(pAHUwLEvKB80LSaFjh27rQ3)ImonLPExPTfn13zTLjcjrnBRmeg6M4oxeFYkTDIgMySRutF9DHggyUKuZItjLH6APQu3)xo2Cj)QlFdaY2heXiIwFbR66VKtOOmqeMGf2pDEocLZx6MR4efBpCwsEQCsCKtxZuDpHo55um1PldhF(WygkfGP8jtD6g0XTo2xB5KVF1TDv70fRMKdeGMKDwfnPvregdgKKNDWMNLVNKshxQRf5xftlEjJ7kMQYJFSKboIcIiiO)p47PbL6YJu)QKxs9ZxirTNgPtguz37SSRwpB6GvHAqfT)Q0vz(T90Tge7KONjd8mmW37L3snCcJQG6BTcQgV1fCnbQXn(ELZ7QQRe23)QWASAuRwEsSjGF4vb0C1zdIAYnH8UoHShlj)AX38IUm9TFBQwJSTu2Sb8DdVbC14I(1Jm6vPjOhfMnHfZhEx4Qqw9c)nLEK8dUluRGvhW(rSZ3TPXZRb2AHwO13x3A4dpG3y(xqfE4CHhkz4RlB4l8C5B(Yd1mKntNwETTDUWAp72Wh0Aa1Mhud4Tst(LHCrjK2SyQTOKwTX4D30RFr(1xjc2LjNnxQ2khk9SPivRxnfCFLA18rha35gM6LiiXaKl2WY89(f0wzJVi05Np(7WwET))a]]
)
spec:RegisterPack(
    "Demonology (wowsims.com)",
    20261105000,
    [[Hekili:TR16UTTnu4NL(hxl0m5lTonlioaTRyyDRRRyoa7FsIwI2M1sIcIuXlab6zFhQBwuMsI2nx6WgkAGcVCoFNl8Wd)ATMyDJ1cpehB95PJNE(KjJNnE8yRf87IWwlIqUBrRHpcrbWp)aoGgs9PRVl1z4o6ogjGz6sdmeR8oFkYtiTLjeF(hdTwQuWSiSR1I)6D)5N(JF63U0RsIwl2q88W5BdZC7qBxM6W3GtDkgB0kAm(wCCQJhEfkXNN68UV8Puhy4uhjHKqgjupB0ouSp1D7iVi2ibC9yJeiXEfjgBVmgf6zMnS5xz0qJZa9bJX8bRXd(Mk0pHL6G88OHVe(yl(oMjOmehDPcCn83)4nGq2W5rSlhnAnHVjzPWug1yPgGmb4JNEXBMUAm6Tx8gpqSVh7t3L64dRWp1zYfGaxIf7i1zbgftcxN68fej0OexrXeAmHdM8ge8RHaGxr89fqbmTuh2gqTPoFISceXnOOuNLy(omom1HWHj(a9ggGxXElaOWiP7G59jmUy0eFVCSY3i(zg2YGAoUYIpz(EIlmACMA5iFCi)SgOwSzKhRyp5YFygmwMVnHffM7itIm6hxMq2ymfmyiJf5Yj0qMzumgC3lr85KGaQiqEgz18x4HxMSALz5yMjrP)AXwMNWW2eooGDM4l6Qv2RD9MpPAbVAEwodyG2XjH42xva6R0y7auiYoIkgS9L6I89TZ)vBHfDM4C3Cg4R8X2bqQnXMJIxJ52UjXGqG8AW)wtalrHcrB7rPbNTI6MWMpvyPRiR3WTJXbGdNDDHzxFXMEjXiHuQlnwECYoc2vDPnCyPNR0dKFMjj6ELJxO3RMAoZyWlYLVzDHBI)BSBch(1bdFXqXcUfBJdXbem765V24(CR2KMWzep8mddT9Af(lpkp3BjWVSc0jei577qwxRHSCPuFpiPLL7klChsbJTHW8da3CRtE)WHsX0FyMXOUcRgxnXyqxY7fQ2nCEZW4(UWyl76(ddIdkIH7GQFKqiekfd3G99fvFv4sHToKtxdbtZa6T4aOgYG2fFvkY9n0NuInuNiRyFrw9KISADs9guKG7scY8SG5oq(4vP7QslMUig)vhmkCPcu10MtcW1owunD1zcd5Aoi(gBxkXpdZkpnvKHOAkjKuFI6G5Aj7rs9(WDgW5GOmLlQPzg5konC1Rh3WlC(yJ2QLOsGvJz2t5U55FdjBWfg2y)Secw9Ytmmx42yMigJSoe7LV95VSCXVuuLzOglRi7wPg3NMdUYQva3ZS1hZyHWFloI0QEQV2d1LKKuQRDy0wD0t56ouhvsi7GU2HarPnvWuRGGSvlcenTljVCp22XeR0es)lnqukcTcc7rYtza4P8WIgMUUbb1x(pV8op0AA4DnAp64VNDqZjYeR4Yf57KUAwVidYkQ6YToSu0U7aLngwTGYUho6UYAhzU044KiXIuIT9t3k6QTKthFT0D4twqTZgYZxvvRB9I6h(aUw68rjuwtZvnkphNeJ3IKF3Ku7pkBqU156UZAvXYYxWCr3nr3rp0TdM278wHRq8gpFk1ZEvs8DFh4qMm77bpcgQGhVfsu)FpYUdF5EFvV6YAMo9KSMgxAnFsl4u65eNAOQh8FA(1b5VUbEzZ0ZhR4TnGbzT4wiXdKCdkofp1NLXRAoFKWNFoJNvCiAPp2Z69wlQLNkMSGOQ8XZyDYIdsvZnvNhkX(ETM77aMPeB(nn2C5IBsMrUDANZmCp9PkK7SgY1ngSZycYAH(KtThn1NgKG46hH)c0Z5TQNoOT6XI3QdBbzVjuxqYMWBB1eAES64cpnVdxORl0uxxRRUu35Nqv)yhrMtSq8donyDXd2rxes8qeTycttxBvLtH3CY4woOwsLwhXYtLsTMCQLHJML2KoWP1HINbk1QDmSC2QZGtYmRMfF3xSTKaojtTdI4E4yIldynRUxcSY7sLGvFu0LjX2k5lvHsSWM1Wpq1C4plQ(hBr1fFLBP8jh1rRI3RKlX(UErHE2lvnOU4HIoWNukoE85HQwzjvMS8LwnpVOra4zJkWhoUaFwcc1rHCqOzTbnccplub(eFqrdJ)OdcLlqkaWBVxRoRr1DtopU0lDyt1zlq3t3FlSmP66a9sN)wzzQwaTA2MrY9TBDepGlNQkLTgOU)1wNSNoF76vV9qtvhCqCApw(yES6E6REMDs9ruZJIxs3NMVNsR)l6L0QHuTlF2L51h)w6tWLkookXTYwZp5Gzp2Zj637LWR8IIT88(N0B3K99xn7z8kStG3NN4R6obe26vIq8hLW3qJTw8l4TeFsQZWFU4)6IztB9p)]]
)
spec:RegisterPack(
    "Destruction (wowsims.com)",
    20261105000,
    [[Hekili:nJvBVTTnq4Fl5lo2ybYYUPPzb1dODfdnDzDdtbOFtsuIu2SwIuGKAggOq)23rkR3LDKl6sgcIHmV7EUN7okYhy3fUp66GrkI7NxAV8MflSFTTTTRJAFkX1jffUfTgEGHsGp)arQezHkkNL7pDhFNKMiTc5jZ0UUpMJWA4cYOXQ7zUbdISmLe668L393p8N)6VFhUgsxNnumMuehrgEQ8DxUVAdj3)WAZJ4cY)qe5(yseklwL7)U)6HCFy5C)2OKrNRzGC(oKiMhUDoovoxZySCUHmClZ3S(QKZMDfKhbIjJH6adpZ15LkZ9rymNDj8WwYEPfKeKcD3a8z6FC)JaiBuQu5DZNVMQ2KfOlH5DCDgGjqBYYBVEzKn6n3EngG99Ky(UC)yWJ4C)RTbadi6iY9VNfszebqSzLKkvq5cQApKpe8vgW2iACSMhigqF5giN5(pqJG4FeLM7hqu7ieOVqvGHpWFucKvh7b2PRq(oWEmvQ0RMfJliQAJ(tdXSGPVGdzc2IGm9zPvQGafzasTIMKW1TVROrRUatcYIISkxZkln)thczvMK4rvKe5v6N4rrERdXRwu5WpTcgqjCgn0tKXih3Re0x5cVeed5LY1lECxdZegtEWUjpsmjHWuYRI4HzYvl1mwsukkBT0cjL01mc2ZeYQllD(YjtVy60r42HsFWmc9HzFBAbTQ9aAHBJjsjd(3AldMdtoAEA6B)C1cPbZ1ocA7yYtPF9Zrfca(ZMnytUjngvtUDvPB0D5DRU4tW9Zzwmsk9)0gDPlJQjxNPNZg8Z5M9ru6JVjhGygpWCEsZ(BeD9gfK8eeLj)LBSBgdkjnMgTViTTpnshk03p0oAcErx4BDSGwZz7lmbv20loEGLh22Yeuot6fudm7fvHTJ2fmMB2gM(9XPJM2jdA4qB(TRgSscrsvl2wDhudI29QOUqwzqJwR3Y4crwQ5EL(WvBShGnm1hswumAT4W1KvDWkou096F7zRQuUbH57cYeSMRcB8iEkuQby9LIwPHkVy(BFL9KU7zB30QeymeC5FY1bKTiHL7iWtlvqAKvwOfdE8ZgzMegkiMGDFVRtJxb0gpiBOyDJgaxfG6idQPQaDCVAKX1tNGo4R7eCiiOIiOiq46tFS3pkPapRhp(F)Du1T8blzxhZ7r6bomaE95paEXKj8JtNWlYqOjlApeU58hcViYiEMFrzef)zpekDO9a4nhDa09m7AiBEPAB0UDKNi2sNsZKEsfkNuIYP1O8Dks5uQu017pF0U3PLN8CQpP)CZyS9GBH9rRKZs)sDYkxUtE6EbDV8mEHnn2JxzOt26EZEDav6GAV7By9qdjiYGFxfaL4xRqY4w376lDRuJtlo8usNmi29YRQUELwkJBDpETxIvWFov)gkdPGQ)8SMRd8ZSyqupAYuB4cxNps2sJP5(t)Td)8tgZU)7p]]
)
spec:RegisterPack(
    "SM Ruin (wowsims.com)",
    20261103000,
    [[Hekili:nJ17VnQny4)w6xAbDrqsUE96QgtQBtt72AVnDCs7BgmytIxm2iSzrrQI)2NnekgcKJe11Up0kJ977Z777ZR)XJcyb4RaFeuIbFE58L3SyX83pF(CGVCxgg4NbJ3axPgWGPQ)7)yz4xkiSYqRT8TcsQWjMNARTBhLdrASIkiu5NyGObHvKHJb()19F5H)4N(97GjjusSKWza)1eecx7gwepASURmuUgxgUFo3eEo(FW5LHiCcSGkldV)pFOmunDzObefexDOfUBH5uE8gxuMWvNQiHRinixzLt1No)TGZSNPIsoKjOQkaPgZ1rLikdHieNDLAWg8oHtz4pdLW7giBSE8tFvbYAPmtCNR7kICDrKUaC7zQTctvsJxE71ltMd)4TxJCu8zopHqvmoSIDeEfcCarItfZ0J4jjbRIrElk)T9g8opxeoLZiXQAHHh3QyiLgu)zaLiKZ0DwVioxifZijEww1l6ebzAicqCEQZggFl7slRlgDXNq4OIKKURuKzF5P6toofsyIV3BX1222pD0yEXybnHSATmObQBMBBBYbW0mkjzxqCrUOhvvtbNvmpWj4koB3iEvV2GP6LxuzzNKuBPzfyg8zj84cH3YQuFKSRBu(bpvygcUQSQdENftmwXEyT2zNjppVit)Lzg0Gv7QkGmDtSgI4BdI4u5E)QAIvoTFn9r5yCF)izRRodKGhkEgl3ZXQgIUSu3dfGP4umtD0XacbwkjSvchOqqwXWO6EO3vngFLAVIL1emRP2hkIAM(PMdRpBrooEdflem1F7p1oACmT9Wy1bPbJ1wmCZuItJDhgJNrqHF3JOdMgtIK7wvAIUFE3Hf)g5(P0lMyk9)uIUXKjrYTr61KGFn3SpHsF6KmjnLRLsm0fnnRn(1AMtRVpkqcBn1P(PBVikNJcskY31)TFGVsMHqzBpPy6x)fvQ)QvoPg(5k1GygmIIrGFe4BaLEX9YrQNVsocqQqDIozkqr73775xCUcYCce4F2IqolvitrgYX1HCkcrA5J(sXQBjb1sTRBRAA66jsVDem0LnpVC)OcAEju0ORUpm(MGPRLPLemTf4xDCtVbvfOBoYUTZIEMUkNdtVkB7MFFC08BqjqgBJEE6UaE7OaoO2OwanU65zexOr87(MPyxvtgq2oF3KCX8rXCcpz8sjJ6v9PL)7FF3yVXqLCVoq)78Nqh4ntJ1lNiR3KUGzw0Rl0)r0j0fEteH9kFuzcf)j3fAmOxhyC5idivRf2Mj7Hw)xTh6YvTD9F)RXUgHEaTznQbobfAT6bRqqHbSqUMNd8)v8gcLugA9l7)fOQwg8V)]]
)
spec:RegisterPack(
    "Shadow Brand (wowsims.com)",
    20261105000,
    [[Hekili:TR1wVTTnu4Fl5fxl0m5lTonlikaTRyyDRRRyUa7njtlrzZAjrbrQ4fGa9BFhQ7sMsM2n2PdBp0cfYdp3(ip8WVeZjMFXCUdIJn)00XtVAYKXZgpES5C(dHyZ5Hi7nOvWhbiF4)NVg5q3MS4DrOaNKfd3s3Yi(mDBQVMq4h8OihHcxgt84FiWCPuDZcX2MZ)R3(NF8p(PF7ghSpnG6rx9G581ehhC2YWm7(n4njl4RXjlYhBKlncFpokzHd2ff7Xtw82p)XKfWWjlARNyYiHtWgTff5rT3mYjKns40oSrc)XILUaRLc51tNq)RmAG2LGrHXyEqubkItfobHLSa54qdEb8Xg8dm9KfVhXr3iX5g(7F4lGswZ5HSBgnAfHVoEPiEg1sunqNqmGNE9RN6og9MRFTdO23HftNh5VxK5i2LHfh5Hd4G2NJrrKGvjl(mIeKSWdJCy5RXJWaToKWHbwMTmH7hK5DXHIieXkDCrer3guSUT0yitaqDe1L4b7iq2CcnGPhgHHyyjIBytJIIdfJEjX14ch8Yyxx9Qr1Jdt(18LzeZWweo2NDP4lQRR1kBhJjLc8sJu4acsRO4aC3s5J(knYYhfGScPPgVtrTrEEwz)OLiQUuS32Gb5lpSLpSXHyXrrRWCl74iqjWotihxtblrbcvB5qP(x6sTJzgtfXQlz1AUve2hs6S7Yd86cR7ehHeAPU2yzyLviSQ6AB4WICxrgiBZyC4Jshp3U3ovFM2GlY0VEDLRJ)BSDmh(XbdVyOqG7Xw4aSpbZUZ4vApMf160yoJ4GNPPPCwlpF5q5zzlH)30aQabnY99OR7uqx2uQhCaoGLLkZthnaJnbW8dG0CNt(4WHnW0FyM2O(GvTBNOnOp9DHSvdN500ESpFSJv94UG4GCmCluwHeaqydmCn2ZZLeHLKsHLoKtxbGPUp9ESpuhzq3QVClYJTSNsBSl3CMxJL6XlY3sMXgX4VuY4qz47XEwCIpw7UgWKwZYhi(AlBkXRPTRFWOLXRpvdRxFcfnVhXvC8im14IYt6H2In23(QXdAwV4QXnZEvHQm9voM(EkCzK9nSTbk)BH9sHwwD8GH5IIcmDeJrwfGDYwUXlke(fI6fdvqSIA9YSy1gwitwkbCRXgpmJfa)lFZEN2PUS7ARgAsQT2IrBuXofYTRnk1q6rwLHarrkzUPsGqZOwaeTJRgz59eBhcwPOl9VuGOqfkbcvEY5eaoNhwui0vfeKFnUrXTxOv0GhA1OZHFJ5G2tKQwyMbnV062z71Ze7kQ6zTXfvYAEDG028Qjsr3ahCxwD7FeFFQ4fhs9UIj703kf449So6Z7SbQ92ADMuLnHTxV(ub4kz5NyOSMnlB51ahhH3GA(cOgD)iTv3oNR)EKLHLfVf56(BhUNUH72z6UhAjPcXR18Ouhl34Oh(oiHmz23dzemubpAdSf9)ZiBB3S9ElEDccMw3zzmPd3SXJjowKQp)F60JmToi7TnW7AME1yjVSbciZ53d77an3ImqXB2zPKqMrBh85NsjLehGw6HDmFN58ABtftMZ6u24P0hzYbTQ4IQtOKyDVsX1TdftIf)6wlUq42SsKfNwz0OUN2uf6Dwl9AhbXzebzoxDwMQ8M6tdAqCZJiFb25QoTtp8pDQiGA3oqQcH6kQzi8ModH2hRom4P9L3cBDTI26ovTL8w(eM6h7bzoY6Wp58z1hHwhCriX7quIslftTLvofzZjJ74GAbNy9GLhl3yTjhl1pAxARgS2nVypveJPYXPjTRJwv3SGjn5E9UmQ90rPwQJ1UqDHJvCTyd3AFCTLQXUQExlDMkx7QX7yzHyZl)DGi7kSYTSLVBOU7k9HhzADFxwiXwv6vbEiEQ427SYxXPNuPAiMSqU5zM2hzuaaE2417PJyVNfqOUx0eeAxEqbq4zHxVZ8bffc(dgekeObaW7UZPERr1FllNwUI2Tf5ubu9093kHrYVwqTn1FlKgvz3I5AJKvnpDaphlJ3jPDhiVB0oNCp9X23By3dNt9qOWX903d5PNvCr9mNK2hrfNKSKQp0UIFQ)lMLuPNuLREEkIUDzRsgHffUT0MZpASSV4rqE1XL23l7vz1e74T6N1l3AM7VD2Z8nyhbroN1B6oc)RJBeb8hfZxtJmN)l4nepsYIH)C(FPEPtB(p]]
)
