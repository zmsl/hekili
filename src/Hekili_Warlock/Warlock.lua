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
    20261107001,
    [[Hekili:LR1)VnQnu8)w6V0g01rcPl9ARkvQBtt72UDBA5K2VbXbBs8faJWMgfPQ83(SHqcoXyCOT5UT9dTLIF(9LpVN979m2ZX7ZEJHagY7tdhm8AhNbVFWahVXSvPiVXPGGfGz8hsaX8F)yyyeoGHjjRN0BjzjfhtTdiXwckxfraqb3MMJJyFiXBQsgttrbEJ)7h)Rp(h)4VDhylh9gphdHOYPHObAK2DRNWMJwpzZ76hsYqpHYwpbIcb5rS1tE8p)46j8xZFQotYX9fIN2FjilIeSOpmL2xOUqAFUM4VmJBV2fVW(lusI1LCjLbsOrC7aYFMiKmMUEcacjjxWFybAf1E9KFcWa3PqJ697F4ZCMmNXsP31V)mmBE(uHr0FpsT48KR4OrGBdGdbdHHb2CunJeIJ4ipOWeOU5uKpMHIPxkEIW15zbqxN1)6gcENBFikMKGd8ZYtqntvm4lKm)yqcWpLiEzZKgaII8l)x)imLDPiyWLItMfH8J54n2NbYMHy(b5zCMerMHdQZGPGebR9Hes8L4q3q8S5m)mumaNqFaIMMhgAxNiByEgOWNzQASrbGewP4fIrq7tiFuckgJOMytsgJgE9GeVOZbqYs)PKi2LHKGCQ7qXukSQnJjcIcq25P6NNJrZtTUhqir8PKqf8O3zLJlJQls4J)CVEno2590prjh33nYQVoFN19owNRJFNPA25PwwwpRrfBCsYRbaS5(beCKeAudXRSjfJeaOS3P49CNXtOiFgogz9Geuij7iCOiEmTqYIfy2PbIiP7VAW5Yr(xpqAIf7(OItBFNDll6ClFMdl89h9rrOyucJwpOKIymopO2akfplbblNU7fveFb3L1RNbKTXpOuIchYwODlfzOGfriknH)ZgNzJYPoThkljoPuwlrGfMiNk6ougB5GCWvBUaX6tvQProbzRw4i23UKq5wSTJXxzOk9VuhrflmYjSttoLoGt5IfdmDtDcQZy6cIt5BETQKVYvwuSTyxslOnxIUKANvLAuEWmeaUsBQgPDRVxBUolfQhygjzvdgv5ycRsUYI7h1k4wRGQcUupOUBaBtkxN0TaswwEQGijfRsg7gwiaLvcwJKk8vSuuwzEW9kRNlfVnjNrXq0if7oC0rMN1C8WZn7F5HrDc5)pziTbUHtymSCiMZqJuUxqq8T1eW2AYDr5zOfavXBDlaqliPcJQC53OpORtLK3CH8kGcHRpIqG(H5zR(gaqCg9naIuu6FRb)VbMXEBX760Gck1utx9r60)Hd7iGEEzpw8(RCUzGIoS4gK34NqzuoN37OOenptfNyL6Kz8r(uXXJHsatJqqVFWBCT4vXGBoxg(FRNwXBCqgMHYWaVXAbRULy4fKz4eLA4yk3XJX9k7HYVy4Z8kA25cLO1BCX((cvJRFx1S(zskHJUUMdlSzNAUJls6iZBClnePkCENHyqtmVwhmWjTzN3(osR5AuzYYrsnhPBObFc7j917ub(Q4eQRfMUC2a94K6aoPlumW4pANqfbnSx1BtkxD9WPTjo9DX9)VS1wN4SZh0R2Pi78TgLCDBXWhtiAzxFYAuhJu0d1VGo(00Gt3kixvitta0Uob)kdsT1(0BckTFGBfQu0nO5RZElSRd7luOWFFdkCv3HMRZVK2e7gG3AFILRZ3CfcoMv5B)M8htKF9VsVQyHMM3bF3ED(L9)sXLT86xEzoARDboFh1aFRJU195M)H9fC)6g33E)GVJZIoOOcUSEVHY6btLvdhzaxu30OOkGJ9)Y(7KxTV1SCcUBFn5OJGJod0KZSJlBBBb)R7Lhq3ThOtxFad977QdqaJ7VfXUv3v3)aLq7H3dHxRlIqHwT)EqA3MUTBOqbh1NPsqrRPgyL7VcYzZjzEJ)f0cCeE9KE)8M7)uXWE)Zd]]
)
spec:RegisterPack(
    "Demonology (wowsims.com)",
    20261107001,
    [[Hekili:TR16UTTnu4NL8hhl0m5lDoTnioaTRyyDRRRyoa7FsIwIYM1sIcIuXlab6zFhQBwuwxODtCc2gkAGcV8DUYdp8R1yIXTglCqCSXxMoE6LtMm(nJhpXyb)(qSXIqK9g0k4JaKp8ZpI9Pbup6Q7tSgULULr8z62uFnXkV3JICeOTmM4X)uGXYgbMfITnw8xV)p)8F8t)2voLiASynXXbNTnmZUdPDvIfFnoXkFSrU0i8D4OelhSlk2JNy9(V(5ely4eljqIjJeINnAlkYJAVzKtiBKqDDyJeAIPljcBUmcf4ONoS(3y0aTla5bJX8aRXb(MkKpHLyHCCObNdFSbFpthegIJUQb9A4V)PBbqwZ5HSRgnAfHVoEPWugvBPAaMG6JNHENTZu0uhxBa2pG9OBtS8Gv4Lyn5TaGlXIDKyTaJIibRsS(kIeOvOxHreAeHdM8Ae8RbGc7s88eQcyAjwS1GytS(mXfG4wuyI1smFlghKyr4WeFKEld0xXEZvqHrs3cZ7ryCXOXEoz6kFT4NP6wQQMPxPXNuFpXggnkvSCKhoGFrnTwSzKdlFpz4pmvnwMTnHffK5iJd16xV0HSXikyWqglYMtObm9Wim4UxI4Zj((urG8cI78ZCWlJDD1lgtpom5xZ3Y8yg2KWX(SleFrDDnxz7mFs5cE180CgWanJIdWTVkF03OrM(OaKzivmy7l1g55zM9RMcl6cX5U5mWx5Hn9HuBIjhfTcZnTJJaqG8AW)wbG1ypprsSW6eJEh2ehG9jy2nZF9aoDfaKUp9oSpejgmSHLKcVonMZio4zAvbFjkqO3MouQ)fUu7y28Pcb5swTMBgH9HOj7MCFA1fR7ehHeOufnwwsGziSRQOnCyryPW9MDGmo8HghpxUxpvFM2GZYWxVk464)gBhZHFDWWZ23K1EOUnRPCijpy4q5zHI9D7QeFLcSDG1nkGLnL65aNiyzUYC3HuWytam)aWn36KpmCOum9hMPnQRWQ21t0g0fEN10UHdZAAp0Lo2YUEO982TqPvsaec1oGtfsBvkffkNKENqE(5K88tvsIgKNQAt8t9rGIpq(GsHHxkfDBeJ)Q9gfU7bkUAYj(4kj4LtxMDRjxAcXxBAtjEP6CJNlYInnnJqrUrsBLa3dU4aYxdtHwuytp0wK1E9RNvZgVCSwBN5BcWYX07PM38SVHKc4wdtSxA9mw1Yimmx4uy6igJSka7KT95NxS4ZfvdgQWYYZcBuI7shbxy5kGlB24HzSa4V5PYTkNQRDFzjHuJYAlgTrf5uSU9LrjcIdKdoRDxsan9JZRC4QV4KOovt2IsrkzxJiAv34Lcf94aoKaQIQ0)MJwfYrPi1o19ugLoLh7uW0FuJun3tW8IRcrROb3xRRPd)63b1NifwXnvYxWD9SE1mi1PSZ6QQvdTypOX(flxqrtfhCZATRz20OO4qXIAu32nDRAxLLC86xlnnEYcQD2NE2Qk7ORxT(XpGRKmFscLvKCz)ZZXXr4ni53Qj1lvJ9n36CD3WDtXYIh282U7TUJwRBxzAVH8gCfIN(5rPoMUXr3)cWHmz2lbpcgkzhTbsu)FpY29FqFFvVEcSMAxAnFsl6P0Rxo2qvx6)0PhPFDq2JPGhsn9YXJ3)PuGbzS4oiXdqUgTQcgayPC5MXbk85xs52fhGw6HDm(GXIk5PIjZjhlB8uMUm4aQkUPQCFj23RvCF7XgMyZ)yTnxS46CCKzNMzSr3tZScCN1cUfecasicS8ickBUVB6Yec9YAcDNiuNOSDQA1Pbee35jcsGCEtRYPdk0EQ4qB)(E2zcvbs2eEBRMq9ZYhwor9gheY6DkkRBuvwn3UPqutg3rO5il))OZjxxKYDWL(eVrsjA5u03wwVo1DwVq2bEmwshsbSEroPJokLE)mqVxLdufZwEAAsQzvVg8UA1fKbkzQDqkOQScMk22QExCrRKq7JUWueBRUTuLeXcRxRDprZH)SO8F9NMUvSylfVhPQ22WJzYqSV7EAqo7qvbYpESOM8KssYle6UQuIPj)I8nqTxjqrVYjKWRhpEjF5gPQQQYrQ6f3uis9Sql5j(iNcg)ttKQafPOeV9wW6SKy3T(80s11(9ANUavRt89W4vt3(Owo)3lJxvcOLZwpsURjSd4XKz0M1yFgn3vBRt2t)WD9c8EOmRd(qoUhUFipCEhvApZoP(Oz5jXlPknb7Ox7)IEP26Ow(L0Qw(8PW82NSTU4BPXxcC0bZUShb3BhNFVxY3Ykk2YR(pP3Uj77VE2Z4vyhbDqN4R6ocnS1ReH4pkMVMgzS4xWBiEKeRH)C()1ntN24F(d]]
)
spec:RegisterPack(
    "Destruction (wowsims.com)",
    20261107001,
    [[Hekili:TV16UTTnu4NL8hhB0mFR1PTbXbODfdRBDDdZfy)ZY0s02SwsuqKkggiWp77qjRluIu3IJtq3qqcKfjp3phE4hDMpA(3MpZcXXZ)64HJVE0OHVD4WrZNX37HNpZdzUfTgEWf5a)9tyg3pWKtOUhw0DhDhJ4W6BsD6jM6EBkYsqULbeB(NDNVujLzEyZ5Z(Np83F5p)5F)gRusoF2gILfoADyMzz87Mdl4BWhwC8Ddwr9X3J9pSWcVcfyZpS4d)1xoSaE9HfYujGmqibSb7q(2uZTdS8ydesSfBqOWq7h(P(FNrD7DfWhFKlZg0dl4zQGVe2HfillQ7LWdBX7z9bMG4OBuipD)Jp)nGiB4Cp2ndgSMW3eSuOcdYn1EanbXgpb9EtRXOXwRmbY(rSnD3Hf2WmSpS4ndbcUelwXHfF21K4I9bbRxSq55tO(e(EGFi4JUG0UIyBlKdKli(SnappS4lKvW6)gY7WILy(omgSleomWNOFJbcRyThLoHgs3bJBtyCXBdSTIeu(gXFdfS(G33NcCccrqH2zwFpFmOKlr8PehhQW8Dfz10lSWldwTQF876h4D43oUKPbmSbHJDyxjEIUALXAtRPJsMWRMcoihQlX0WpWfRFwoOVt9nCqUidpQ4L6NQjY22i6Jgcv8krG(ugXDTn2WbcKigCK)Am3WmWhiInDnXmlb2GTTxr8d1oXBVhBGDXoem7UPVUdNUgiuFh69yhSlVtxftjK89PbCgXcpPxwIVe5kKBdlk15QvuZa20XcgTISEd3Wh7GiUS7oAtZo5(wbqGHiGVU66rT0IYJ0XI6tDmCswSsO1DY0I6UYgT2)yqs3lIgknkzRled(qXyhjJfBdYIUBzGFnuAtk1gMSllKFDpYpjlyip70nryko4dD7k5i(Pj9guMVO3TJ61Pm6DHQvdAzVEpuMmQzvpOpyBhufI4obiCdcLLwQKHhJ8HGidpWii7)sQqfBWkoGjIXFvXxdfDHclgCIdU3Dsw5EY1dq8ngMuITeJZkrhzTQre8UeIBdLjHyzVqslQM03ZuerF7RN0rod86HslmPIxMuw9gL8H1hj6TQTvYmkzmvYDY76xr9SPrpdXoWEQgy7WAvSSspdZ5any9rmgzTl2kA5tVmEYxcb2D7wJPDuBvYX0OwqVtMbSrYwBmJ5c)EmIxlFYo3I8sIsk51omABD4t88kYJekiYB7CHEtIln8HlZKdwLFsuotLUulpLSPr4TYR8sUIkmanXHwtr6hzVvmFQLNkvCpNEPZzAxnu9tQNsDBjtroEqTY9rRuUhXO(cAXE1LUbFz7IFrCpjYd6Jrw7tDpkwO0wr3wAdi9uiEO1u39AuQOXeALC)a3oPsJBMUxdPI0EHTYWQt4ALSPEl6IDy2rzR2jti2YkYuLfdOLPEpKV3(6izMuF)apXKukBPdRv6YmL2lFAowqL5mxOps9b9rEIgCBtmXpMjBLUSsp7x0eZicv6qpJ5PnrYRJCFIZHRfpFsYoZW5KdMofh4J3IuLH1Uq(sDMQ8LXb5VR80mnHb9knns)jDvykeHO2uQLXQa)9VamiJM8sWIGH6V(BHa1)3ISt)PUBQu9i1OC9ImDuNt25(1P1jt7fH(QrkLGsPTHNLj)Jh3YyPori7ytVD81dhwexhqHMp7EizdOCUlYqaNil86tIUZb4XVgEDkyx0sBS18poFwMCtXGhHhp69HyDpNduTMlkl63I196AUUc4Hlw8BYT44jNhW0i90i6cGQ4iVc6ordDJrxe4GpO5(eu0ypAaZfm96CmnLf1hQ8urn7WafeLteojGpVvlFYNi0mdA(one86D1Kx3vxEP(ihcw9EDXcPaZNL)6aOxfc9cYpAOg6NczF40YN8KHJTDxRtog9LbsFJREjadPwW0xtpCsj3qZz(Yknmtusgcjy(6njUXmGQRooj)EFNMBciuO0vhl9QbukskUIG6EhbHSvxzU4D6KyAvxEqif1xdRe7ydBIivoJxHC9Tr5lWLm9ecfoT81MkO9C4Nzj3bSQDglkiPkSIdXfrXQ2)rbFsPAnGj9uDjgNv4uFHamEMAuQSlYbA5RnvdV0Z2fyC6UbJxUEQSIQSNkFr)A4PEwUaJZCkxnu(NgpvmvK8sC9Ds2GdLiHTR8gqLGQBPW6woUUTdy3hbYUNjODBl2UneC3YlK2sl)jb(2INLkCc1TYYJbf3QAXjF)Ik4AlrXn75MIhnFwAAh6niVmckyLDe200JYdkkdHLkGbUem(AhWmnbyKu4HFMnsvbJ2tIvQUWaLcz8)fTsLK33yz5XQinbM4MEeVklaQ7KRzoI3llJJse(ILALN3U1X0LPpciMBx4xLymhT3Gg85AWgf6BGRD9c0A74l9UWKdXUDYzUvQIS)zRFjnFZqk(vdPQYkpz9v1cjuB)xqwgkGVH6pF2VI3sSjhw09xo()Fr4WZ)3d]]
)
spec:RegisterPack(
    "SM Ruin (wowsims.com)",
    20261107001,
    [[Hekili:nF1FVTPou0pl7FAt0Ias6BTRrLNuFVPP1U1(EQmP3)zWX2eCdyJWMfvPj(SpBAiy(LcrQR9PQg5479EoxFUboayo47apmusa3VWzX5ZN7CHJZCGN8PucWlfI2axRwWGjQp9URi4HCkRiyYw(wbnryH4jt159umhI1yTkNglVHbw1lSIucc49Fx)W3(N)(RlHHHXuKKYzaVikgtEUmIanixllcKrKIGD7zhYZi)GKveGjHW8yzrW1)73kcuBxeyaro1wtTWElmlMJ2yJtf26wflSfj(zQSSk)Q1JcoB6mflzqMiwDcWQ1CnRurraeJ5Stvl2qEsyve8jOeUSNUzYD38DfirszQyPT9AQmkFL(ay3k1Pkmvnn5dWlr4fWf4qKLspZ4H0yLIdlvhHBUG4tLKeXm9kEyO)Ae2DEXT7s49U2yscNrrQZcJmCwjWh5z(jqg0pLR3C4ur5zLH8vcUpjMKqysXSqokx4Uygn0vqKskBTWcke01mc2VSe3tRs(0tM8UjtgrAyYQ8WqREz0kpD6pN8CBvNrgbTjMiem1)wBy8TStgKhZC7YvdK6LRTe4MXWtvED5ypck8NoTxr2SngLi38uPf629Ddv8a9(Xmlgzl9)uHUkLrjY1m9AkWVM)yFeh9XlYRGSYmWCEIP(gsxhjvKNaPmXF6EUJzrIiiMV1FfpwURM56Ak5Cxm9nJrefFnMO8SS80Y7HzqvvZUpO1oAVYTswRdHGczJwHMgXz(X0qspyAeTdOMXAJknjHRDs6bYQqDWBFG2GPzWxct1GmrFFCRuK0pMF1zoN0uMp3z6aYCF4vClWt5hj0MXn9SJPcPO8XeE2IvT8(YhBGWGRIjyWFb8mmr0b35B98(L(waPc1rwKPtMUUZgzDD820f)hTkgLP6Nmku9Sih(s1xk7Rx1lP)9FF1AjV3JmWR8h66bUAa8HJFa8MzT9Y5T9Mmem7IMdHZp(HWBI13R8fkJ4WF0dHQeAoaUyWbqhVXAmnTtBc3hheUETnRH0WfypIZ1iE5GiE0oQgIY(anB)5ohITJXR140vhPfHTnS6q44CIRPQA7w802JRk9kBwtMpO9DjITD)6BsQZRTrxhMLL)5bZLr8mG3xiBOXu1RQ(5DVjAzyWVc]]
)
spec:RegisterPack(
    "Shadow Brand (wowsims.com)",
    20261107001,
    [[Hekili:TR1wVTTnu4Fl5fhl0m5lDoTnioaTRyyDRRRyUa7njtlrzZAjrbrQ4fGa9BFhkzD1KY0UXUbB7HwOWlNBFhE4HFjwJS(I1mxehB9PXdhF9OrdF1WHJSMXFicBnlc5SgTe(iefa))Svix6M05Vlgf6MoV)g6ggjGz6qdmel(bFkYviWfjeF(hcTwiv2SiSJ1S)6T)5h)JF63UXfhqdP(0LpynBfX1fNVnmZPBfEt6C(kC68TJnWJgJVhhNo3f7Hs85PZF7N)y6Cy405TLtczGWiyd2GI9PoRh4gXgimAx2aH9yZY2G9cX6nZMW8RmAOXvGsHXy(GxbcItfgbHLoh56sdVe(yn(bMz683J4OBKyC9)9p8fqiR48i2ndgSKWxLSq4pdATudqMGpGNGEJJ7y0yxphqSVdlMERN)ErKJ4u6wCKpoKdsFggftcxMo)Zisy6CFmYLTDp(egi1(eomWI8Tjm)WCRljs4HiwPHl8i6MWI9THMarcaQJPEeFiJa5Wj0qMzumg8Hfi(uhACCsKy0RiEtVWfViXZZSAuZKO0FD72MMWW2eooGDL4lQNN9sh3PJkxWlMMbhGtAhNeIvVQa0xPX2bOqKDent5kxQdY33o)hTfE1vIC7PmiE5JTdGehInhfVeZTDsIbHazMqmUMawH999iXyH)jg9ESnoehqWS7M(YEC6sqqMb07XbaA0RVKLKjEtAcNrCXtmQl8fOqHDB7sPbx5rDsythluKhz5kUDmoaqu2DBJQ1xSPBsmsiL6sJLNiyhb7QU063VaykcV5z6jrpkD8T692XMtm6DrU8nRlCt8FJDs4Wp2R)f76Ygp22Nn0gs2cgUuEouSByxh8TbW2HSUtdz5qP(q1HqwEOCB4ObySoeMVheMvo5J973at)Hjgd6cwnUDKrVUK3fY2nCG2W4XUSrf76r15TBGAwKqacnoGtfn2QwPOLPzBlft95frojZ4Gy8xizCOA99yFBojaBCxJaUrZQmi(kBhkXVPURNINRCzZiuEhc3N4jsJJYeTOgLzKJib82xoSxZZ1xpSXgR5iYKx5yM7P6108Vb4fUdWg7NvzIvpAZWCXHxMjIXildXU5BF6Lfl(sX56(ASSIc(Y0yvIfeblxbC1XAFmJfc)BBsPs9uFT7QRgssQU2GrR1rpfRBxDukbXrRExOoKesZ(4YAht2hojQ4iZx0cPAgAeOvBNVbuSNaWHaOAAs)BgTk0JwivL5EorPZ5XonC9NuKs(T7tlUudTKg(qR(Fo8ls71EImXcZ0R59D3ozVwMi1PQp5g36jRH5Es7(R2skAs4GB(sT9rccOIx5i16kMuPTvUGJ3Yu0(3zdu7SJ78vv2B2ET6tfGRLMFIHYA6SSt4P4Ky8AuZxD1OvkPDaRCUUBDwgww8eLx3DxYD0KSAJrDR1scfIhX5tPU2EjXp8miGmAYZHicgkzhVgsr))iYM292V3IxNaNP1DwthPWmB82LJfP6Y(hp(idR9YFkf8mQXxpuYdPahYA29qEhi5weqkEkplJ4ZCQcHp)ugrO4q0cFSR17SMvlnvm5wMUYhpJYkloivn3uDsSe77LAUVDO1sS5FS1MlwCBYkY9t7CQB3tVSc5orHClEzpOHyWZJjO85(M59sO0RBP0kvOpJxvMA9PbjiUUtasGEELs90bxyNkYW2TTNkxOUGA6cVwPl0(S8HLt0UJbHUEJM66oD1L8(mfQA0WoGMJS6)to5ADXU2bx6t8ejT4xtZyBz96SWz7czh4X4g2qMaBxKRg(OMJUNks605GXO2LtRk7wWQNCREx290LEVm1QQqCXDMnu6(49ltIQkbxlyLTU2vn3rZILnR8xkJS73kZSkFurDZv6RsYL6(UjrIUQKRgmz8uXZ4zLXJNjCxvdwLfxAESr95AnJkNr2RE6iz85lsv3uBIuTRVPbs9DHJXZ8ronC(tdsviLgOexDdvDwsS7gzoT8wTBNZzlq36eFRKxj)wi9Y8)wiWQsVfZ1gjRAP6aEAyohysB1qEpQQBBS7KIUEp9E4)QdYnoUNHFipdUIxSVZbP9rAYjjkP7J(R4k7)IrjvnvxVfyTREEk8UDzoRlYtK(wGJgl7YFeePDCH99YKwEnrfpH)SE5wZy)Tt(oFd2rWVZz9MUJW(uCJiG)Oe(kAS1SFbVM4tsN3)N3(xQy20w)Zd]]
)
