-- Hekili_Priest/Priest.lua
-- The Forever Priest (Discipline and Shadow, and an idle Holy, one spec a talent tree: Hekili:NewClass): the Priest kit
-- with Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build
-- 1.60.1.70338, wowdb), mana under the five-second rule (`fsr`), the casts and the four channels (Mind Flay, Penance,
-- Starshards and the wand's Shoot: `channeled`, `tick_time`), Shadowform as a form (core's form reads, Sources/Forms.lua)
-- and its -50% on the Shadow spells' costs, Inner Focus and Holy Purpose as charged cost modifiers, Mental Agility's and
-- Devouring Contagion's cheaper spells, Divine Fury's faster Smite and Holy Fire, Improved Mind Blast's cooldown,
-- Improved Shadow Word: Pain's duration, the DoTs on the target from our casts, Dark Sacrifice's mana, and the school
-- lockouts (Hekili_Shared's locked_out_<school>). The priorities are the wowsims.com packs ("Shadow (wowsims.com)" on
-- Shadow, "Smite (wowsims.com)" on Discipline: wowsims/forever's ui/specs/priest/dps/builds/testing.build.json and
-- smite_testing.build.json, translated; the generated blocks at the end).
-- Research: docs/research/2026-10-15-forever-priest/research.md.
-- From wowsims/forever's spell data, absent from the Forever DB2 at 70338 (ruling P6; in-game checks): the talents'
-- per-rank values where the DB2 holds only the top rank's row (Mental Agility, Devouring Contagion, Divine Fury,
-- Improved Mind Blast, Improved Shadow Word: Pain), the Forever-only talent nodes' trees and ranks (wowsims's
-- ui/sim/talents/trees/priest.json), Dark Inspiration (talent 1326159, aura 1326168), Dark Sacrifice's Spirit share.
-- Where the DB2 and wowsims's newer data (build 70450) disagree and wowsims's log casts its own (the Mage lane's ruling
-- M9 precedent; wowsims packs Task 14; in-game checks): Devouring Plague's cooldown 24 s (DB2 60 s), Shadow Word:
-- Death's 18 s (DB2 15 s).
-- Unmodelled: the procs' rolls (Holy Purpose from Searing Light, Spirit Tap on a kill, Dark Inspiration, Shadow Weaving:
-- unseen; the player aura walk reads the player's where plain), the DoTs' resists, Shadow Word: Death's backlash, Inner
-- Focus's crit, pushback, the healing spells Shadowform forbids (no priority casts one).
-- Credits: Hekili (registration API and pack format). wowsims/forever (MIT, https://github.com/wowsims/forever:
-- ui/specs/priest/dps/builds/*.build.json and sim/priest/) is the reference for the abilities and the talent, proc,
-- wand and Dark Sacrifice rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase = Facade.UnitClassBase
local L = Hekili:GetLocale("Hekili_Priest")

if UnitClassBase("player") ~= "PRIEST" then
    return
end

local state = Hekili.State
local floor = math.floor

-- The class kit and one spec a talent tree (ids the core's: Discipline 100051, Holy 100052, unsupported: a healing
-- tree; Shadow 100053; the client's one pseudo-spec only keys the legacy profile the core migrates). Icons: the DB2
-- talent tabs'. Each package is the spec's wowsims.com pack (Smite's on Discipline: its build's dominant tree).
local spec = Hekili:NewClass("PRIEST", {
    specs = {
        {
            key = "discipline",
            name = L["Discipline"],
            tree = 1,
            icon = 135987,
            role = "attack",
            ranged = true,
            package = "Smite (wowsims.com)",
        },
        { key = "holy", name = L["Holy"], tree = 2, icon = 237542, role = "healer", unsupported = true },
        {
            key = "shadow",
            name = L["Shadow"],
            tree = 3,
            icon = 136207,
            role = "attack",
            ranged = true,
            package = "Shadow (wowsims.com)",
        },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's), each rank's mana cost or cast time.
local SHADOW_WORD_PAIN = { 589, 594, 970, 992, 2767, 10892, 10893, 10894 }
local SHADOW_WORD_PAIN_COST = { 25, 50, 95, 155, 230, 305, 385, 470 }
local MIND_BLAST = { 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947 }
local MIND_BLAST_COST = { 50, 80, 110, 150, 185, 225, 265, 310, 350 }
local MIND_FLAY = { 15407, 17311, 17312, 17313, 17314, 18807 }
local MIND_FLAY_COST = { 45, 70, 100, 135, 165, 205 }
local DEVOURING_PLAGUE = { 2944, 19276, 19277, 19278, 19279, 19280 }
local DEVOURING_PLAGUE_COST = { 215, 350, 495, 645, 810, 985 }
-- Forever's (level 32-56); not the level-0 rune 401955 (research §0)
local SHADOW_WORD_DEATH = { 1309595, 1309633, 1309635, 1309636 }
local SHADOW_WORD_DEATH_COST = { 175, 205, 250, 340 }
local SHADOWGUARD = { 18137, 19308, 19309, 19310, 19311, 19312 } -- the Troll's (wowsims priest.go)
local SHADOWGUARD_COST = { 50, 85, 120, 160, 200, 250 }
local DARK_SACRIFICE = { 1277324, 1277325, 1277326, 1277327, 1277328 } -- the Undead's
local STARSHARDS = { 10797, 19296, 19299, 19302, 19303, 19304, 19305 } -- the Night Elf's
local STARSHARDS_COST = { 50, 85, 140, 190, 245, 300, 350 }
local SMITE = { 585, 591, 598, 984, 1004, 6060, 10933, 10934 }
local SMITE_COST = { 20, 30, 60, 95, 140, 185, 230, 280 }
local SMITE_CAST = { 1.5, 2, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5 }
local HOLY_FIRE = { 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261 }
local HOLY_FIRE_COST = { 85, 95, 125, 145, 170, 200, 230, 255 }
local PENANCE = { 402174, 1240720, 1240721, 1316995 }
local PENANCE_COST = { 150, 220, 270, 385 }
local HOLY_NOVA = { 15237, 15430, 15431, 27799, 27800, 27801 }
local HOLY_NOVA_COST = { 185, 290, 400, 520, 635, 750 }
local POWER_WORD_SHIELD = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 }
local POWER_WORD_SHIELD_COST = { 45, 80, 130, 175, 210, 250, 300, 355, 425, 500 }
local INNER_FIRE = { 588, 7128, 602, 1006, 10951, 10952 }
local INNER_FIRE_COST = { 30, 65, 105, 165, 235, 315 }

-- The talents' per-rank values (wowsims's data; the DB2 carries the top rank's on rank 1): Mental Agility -3 / -7 /
-- -10% on Smite, Holy Fire and the instants its mask names; Devouring Contagion -25 / -50% on Devouring Plague; Divine
-- Fury -0.1 s a rank on Smite and Holy Fire; Improved Mind Blast -0.5 s a rank; Improved Shadow Word: Pain +3 s a rank.
-- A rank past wowsims's (the DB2's Era maxima: Mental Agility 5) reads as its last.
local MENTAL_AGILITY = { 0.03, 0.07, 0.1 }
local DEVOURING_CONTAGION = { 0.25, 0.5 }

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

-- A talent's per-rank value from `values` (0 untaken; past the list, its last).
local function perRank(values, r)
    return r > 0 and (values[r] or values[#values]) or 0
end

-- The value of the highest known rank (the first rank's before any is known).
local function byRank(values, ids)
    return function()
        return values[knownRank(ids)] or values[1]
    end
end

-- The same, less Mental Agility's percent (DB2 14520 effect 0: aura 108 misc 14; its mask names Power Word: Shield,
-- Smite, Inner Fire, Shadow Word: Pain, Devouring Plague, Power Infusion, Holy Fire, Holy Nova, Vampiric Embrace,
-- Shadowform and Shadowguard; wowsims's Smite log: 252 = 280 x 0.9 at 3/3).
local function agile(values, ids)
    return function()
        return (values[knownRank(ids)] or values[1]) * (1 - perRank(MENTAL_AGILITY, talent.mental_agility.rank))
    end
end

-- Each spell refuses while an interrupt has its school locked out (Hekili_Shared's locked_out_<school>, C10). A new
-- closure per ability: each field function runs in the environment the engine gives it (in the belief's `now` context
-- the names are absent: never locked).
local function unlocked(school)
    if school == "shadow" then
        return function()
            return not locked_out_shadow, "shadow locked out"
        end
    elseif school == "holy" then
        return function()
            return not locked_out_holy, "holy locked out"
        end
    end
    return function()
        return not locked_out_arcane, "arcane locked out"
    end
end

-- A DoT's `now` or `handler`: the debuff on the target at its registered duration. A new closure per field: the
-- engine binds each field function to its own environment.
local function dot(key)
    return function()
        applyDebuff("target", key)
    end
end

-- Shadow Word: Pain's 18 s, +3 s a rank of Improved Shadow Word: Pain (wowsims's 3000 / 6000 ms; DB2 15275 aura 107
-- misc 1 +6000 at the top rank): its aura's duration, and its `now` and `handler` pass it (the belief takes no
-- function duration).
local function painDuration()
    return 18 + 3 * talent.improved_shadow_word_pain.rank
end
local function pain()
    return function()
        applyDebuff("target", "shadow_word_pain", 18 + 3 * talent.improved_shadow_word_pain.rank)
    end
end

-- The five-second rule (C3): the regen per second the declared starting point the out-of-combat read and the in-combat
-- calibration replace: wowsims's Shadow log at 60 (testing.build.json: 2.863 a 0.1 s tick while casting, Meditation's
-- 50% of the spirit part and the mp5 under Dark Inspiration; 4.175 outside the rule before it, so the spirit part's
-- other half 16.62 under it). The Smite build's: 35.73 and 20.12. UNMEASURED in game.
local CASTING_REGEN, SPIRIT_REGEN = 28.63, 16.62
-- Dark Sacrifice (1277324-1277328, 15 s): mana every 3 s, 320 at the top rank (DB2 aura 24) and Spirit once over its
-- five ticks (wowsims dark_sacrifice.go, the tooltip's $o2+$SPI), Spirit the Undead Smite build's (about 272).
-- shortcut: fixed at build at the top rank and that Spirit (the regen entries take a number); upgrade when a regen entry
-- can scale by rank and the read Spirit.
local DARK_SACRIFICE_TICK = 320 + 272 / 5
spec:RegisterResource(
    Enum.PowerType.Mana,
    {
        dark_sacrifice = {
            aura = "dark_sacrifice",

            last = function()
                local app = state.buff.dark_sacrifice.applied
                return app + 3 * floor((state.query_time - app) / 3)
            end,

            interval = 3,
            value = DARK_SACRIFICE_TICK,
        },
    },
    nil,
    {
        fsr = { spirit = SPIRIT_REGEN, mp5 = CASTING_REGEN },
        base = 1376, -- a fraction cost is of base mana (wowsims's priest base mana at 60, base_stats_auto_gen.go)
    }
)

-- The cost modifiers, each on the class mask's (or school's) registered rank-1 IDs: Shadowform's -50% on Shadow spells
-- (DB2 15473 effect 3: aura 72 misc 32, the school; wowsims's Shadow log: Mind Blast 175 = 350 x 0.5), Inner Focus's
-- free next spell (14751 effect 0: aura 108 misc 14 -100, a charge; its mask), Holy Purpose's free Holy Nova (1284536
-- effect 0, a charge; Searing Light's proc).
spec:RegisterCostMod({
    aura = "shadowform",
    pct = -0.5,
    spells = { 589, 2944, 8092, 15286, 15407, 15473, 18137, 1309595 },
})
spec:RegisterCostMod({
    aura = "inner_focus",
    pct = -1,
    charges = 1,
    spells = { 17, 585, 588, 589, 2944, 8092, 10060, 10797, 14914, 15237, 15286, 15407, 15473, 18137, 402174, 1309595 },
})
spec:RegisterCostMod({ aura = "holy_purpose", pct = -1, charges = 1, spells = { 15237 } })

-- The wand's speed: the ranged hand's (UnitRangedDamage's first return, the belief's out-of-combat stat read), else
-- the Smite build's Brilliant Wand (ItemSparse 249385, ItemDelay 1200) before a plain read.
local WAND_SPEED = 1.2
local function wand()
    local s = state.stat("UnitRangedDamage")
    return s > 0 and s or WAND_SPEED
end
local function wandSpeed()
    return function()
        return wand()
    end
end
-- Shoot's target aura: its one shot, a wand speed after the press (the world's), as each channel's aura lasts its
-- channel.
local function shot()
    return function()
        applyDebuff("target", "shoot", wand())
    end
end

spec:RegisterAuras({
    -- A form (DB2 15473 effect 0: aura 36 misc 28): core's form reads keep it (Sources/Forms.lua); supersedes
    -- Hekili_Shared's id-less stub.
    shadowform = { id = 15473, duration = 3600, max_stack = 1 },
    shadowguard = { id = 18137, copy = rest(SHADOWGUARD), duration = 600, max_stack = 3 }, -- 3 charges
    inner_fire = { id = 588, copy = rest(INNER_FIRE), duration = 600, max_stack = 20 }, -- 20 charges
    inner_focus = { id = 14751, duration = 3600, max_stack = 1 }, -- until the next spell (DB2 -1)
    power_word_shield = { id = 17, copy = rest(POWER_WORD_SHIELD), duration = 30, max_stack = 1 },
    weakened_soul = { id = 6788, duration = 15, max_stack = 1 },
    -- The procs (unseen; the player aura walk reads them where plain): Spirit Tap on a kill, Dark Inspiration from Mind
    -- Blast and a full Mind Flay (wowsims's: absent from the DB2), Holy Purpose from Holy Fire's ticks (Searing Light).
    spirit_tap = { id = 15271, duration = 15, max_stack = 1 },
    dark_inspiration = { id = 1326168, duration = 10, max_stack = 1 },
    holy_purpose = { id = 1284536, duration = 10, max_stack = 1 },
    dark_sacrifice = { id = 1277324, copy = rest(DARK_SACRIFICE), duration = 15, tick_time = 3, max_stack = 1 },
    -- The target's (unreadable in combat), modelled from our casts.
    shadow_word_pain = {
        id = 589,
        copy = rest(SHADOW_WORD_PAIN),
        duration = painDuration,
        tick_time = 3,
        max_stack = 1,
    },
    devouring_plague = { id = 2944, copy = rest(DEVOURING_PLAGUE), duration = 24, tick_time = 3, max_stack = 1 },
    holy_fire = { id = 14914, copy = rest(HOLY_FIRE), duration = 10, tick_time = 2, max_stack = 1 },
    vampiric_embrace = { id = 15286, duration = 30, max_stack = 1 },
    shadow_weaving = { id = 15258, duration = 15, max_stack = 5 },
    -- The channels' auras on the target (wowsims's logs key each by the cast's ID; the client's Penance channel aura is
    -- the DB2's 1316994-family child: unmeasured).
    mind_flay = { id = 15407, copy = rest(MIND_FLAY), duration = 3, tick_time = 1, max_stack = 1 },
    starshards = { id = 10797, copy = rest(STARSHARDS), duration = 6, tick_time = 1, max_stack = 1 },
    penance = { id = 402174, copy = rest(PENANCE), duration = 2, tick_time = 1, max_stack = 1 },
    shoot = { id = 5019, duration = WAND_SPEED, max_stack = 1 },
})

spec:RegisterAbilities({
    shadow_word_pain = {
        id = 589,
        copy = rest(SHADOW_WORD_PAIN),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = agile(SHADOW_WORD_PAIN_COST, SHADOW_WORD_PAIN),
        spendType = "mana",

        startsCombat = true,
        known = knows(SHADOW_WORD_PAIN),
        usable = unlocked("shadow"),

        now = pain(),
        handler = pain(),
    },

    -- 1.5 s; 8 s, -0.5 s a rank of Improved Mind Blast (DB2 category recovery 8000; 15273 aura 107 misc 11).
    mind_blast = {
        id = 8092,
        copy = rest(MIND_BLAST),
        cast = function()
            return 1.5 * haste
        end,
        cooldown = function()
            return 8 - 0.5 * talent.improved_mind_blast.rank
        end,
        gcd = "spell",

        spend = byRank(MIND_BLAST_COST, MIND_BLAST),
        spendType = "mana",

        startsCombat = true,
        known = knows(MIND_BLAST),
        usable = unlocked("shadow"),
    },

    -- A channel of 3 s, a tick a second (DB2 period 1000; a channel's `handler` never runs in Hekili's simulation:
    -- `start`).
    mind_flay = {
        id = 15407,
        copy = rest(MIND_FLAY),
        cast = function()
            return 3 * haste
        end,
        channeled = true,
        tick_time = function()
            return haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(MIND_FLAY_COST, MIND_FLAY),
        spendType = "mana",

        startsCombat = true,
        known = knows(MIND_FLAY),
        usable = unlocked("shadow"),

        now = dot("mind_flay"),
        start = dot("mind_flay"),
    },

    -- 24 s (wowsims's data, build 70450: CategoryCooldownMs 24000 on every rank; its log recasts it 24.5-26 s apart; the
    -- DB2 at 70338 says 60 s, category 691: the Mage lane's ruling M9 precedent, an in-game check); -25 / -50% a rank of
    -- Devouring Contagion (DB2 1309950 effect 0; wowsims's Shadow log: 246.25 = 985 x 0.5 x 0.5 in Shadowform) after
    -- Mental Agility.
    devouring_plague = {
        id = 2944,
        copy = rest(DEVOURING_PLAGUE),
        cast = 0,
        cooldown = 24,
        gcd = "spell",

        spend = function()
            return (DEVOURING_PLAGUE_COST[knownRank(DEVOURING_PLAGUE)] or DEVOURING_PLAGUE_COST[1])
                * (1 - perRank(MENTAL_AGILITY, talent.mental_agility.rank))
                * (1 - perRank(DEVOURING_CONTAGION, talent.devouring_contagion.rank))
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(DEVOURING_PLAGUE),
        usable = unlocked("shadow"),

        now = dot("devouring_plague"),
        handler = dot("devouring_plague"),
    },

    -- 18 s (wowsims's data, build 70450: CategoryCooldownMs 18000 on every rank; its log recasts it 18.3 s apart at the
    -- least; the DB2 at 70338 says 15 s, category 1169: ruling M9's precedent, an in-game check).
    shadow_word_death = {
        id = 1309595,
        copy = rest(SHADOW_WORD_DEATH),
        cast = 0,
        cooldown = 18,
        gcd = "spell",

        spend = byRank(SHADOW_WORD_DEATH_COST, SHADOW_WORD_DEATH),
        spendType = "mana",

        startsCombat = true,
        known = knows(SHADOW_WORD_DEATH),
        usable = unlocked("shadow"),
    },

    vampiric_embrace = {
        id = 15286,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = agile({ 40 }, { 15286 }),
        spendType = "mana",

        startsCombat = true,
        known = knows({ 15286 }),
        usable = unlocked("shadow"),

        now = dot("vampiric_embrace"),
        handler = dot("vampiric_embrace"),
    },

    -- 40% of base mana (DB2 PowerCostPct), Mental Agility's cut; its own 1.5 s recovery (category 39).
    shadowform = {
        id = 15473,
        cast = 0,
        cooldown = 1.5,
        gcd = "spell",

        spend = function()
            return 0.4 * (1 - perRank(MENTAL_AGILITY, talent.mental_agility.rank))
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows({ 15473 }),
        nobuff = "shadowform",

        now = function()
            applyBuff("shadowform")
        end,
        handler = function()
            applyBuff("shadowform")
        end,
    },

    shadowguard = {
        id = 18137,
        copy = rest(SHADOWGUARD),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = agile(SHADOWGUARD_COST, SHADOWGUARD),
        spendType = "mana",

        startsCombat = false,
        known = knows(SHADOWGUARD),

        now = function()
            applyBuff("shadowguard", nil, 3)
        end,
        handler = function()
            applyBuff("shadowguard", nil, 3)
        end,
    },

    -- No mana cost: health (DB2 aura 226). 600 s (category 1144). Its mana is the resource's dark_sacrifice entry while
    -- its aura is up.
    dark_sacrifice = {
        id = 1277324,
        copy = rest(DARK_SACRIFICE),
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows(DARK_SACRIFICE),
        usable = unlocked("shadow"),

        now = function()
            applyBuff("dark_sacrifice")
        end,
        handler = function()
            applyBuff("dark_sacrifice")
        end,
    },

    -- A channel of 6 s, a tick a second (DB2 SpellMisc channel flag; period 1000); 30 s (category 2522).
    starshards = {
        id = 10797,
        copy = rest(STARSHARDS),
        cast = function()
            return 6 * haste
        end,
        channeled = true,
        tick_time = function()
            return haste
        end,
        cooldown = 30,
        gcd = "spell",

        spend = byRank(STARSHARDS_COST, STARSHARDS),
        spendType = "mana",

        startsCombat = true,
        known = knows(STARSHARDS),
        usable = unlocked("arcane"),

        now = dot("starshards"),
        start = dot("starshards"),
    },

    -- -0.1 s a rank of Divine Fury (DB2 18530 aura 107 misc 10; its mask names Smite and Holy Fire).
    smite = {
        id = 585,
        copy = rest(SMITE),
        cast = function()
            return ((SMITE_CAST[knownRank(SMITE)] or SMITE_CAST[1]) - 0.1 * talent.divine_fury.rank) * haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = agile(SMITE_COST, SMITE),
        spendType = "mana",

        startsCombat = true,
        known = knows(SMITE),
        usable = unlocked("holy"),
    },

    -- 3.5 s, Divine Fury's cut; its DoT (10 s, a tick each 2 s) from the cast's success.
    holy_fire = {
        id = 14914,
        copy = rest(HOLY_FIRE),
        cast = function()
            return (3.5 - 0.1 * talent.divine_fury.rank) * haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = agile(HOLY_FIRE_COST, HOLY_FIRE),
        spendType = "mana",

        startsCombat = true,
        known = knows(HOLY_FIRE),
        usable = unlocked("holy"),

        now = dot("holy_fire"),
        handler = dot("holy_fire"),
    },

    -- A channel of 2 s, a bolt at its start and each second (DB2 1316994 period 1000: three); 12 s (category 2414).
    penance = {
        id = 402174,
        copy = rest(PENANCE),
        cast = function()
            return 2 * haste
        end,
        channeled = true,
        tick_time = function()
            return haste
        end,
        cooldown = 12,
        gcd = "spell",

        spend = byRank(PENANCE_COST, PENANCE),
        spendType = "mana",

        startsCombat = true,
        known = knows(PENANCE),
        usable = unlocked("holy"),

        now = dot("penance"),
        start = dot("penance"),
    },

    -- Every enemy within 10 yards; free under Holy Purpose (its cost modifier takes the charge).
    holy_nova = {
        id = 15237,
        copy = rest(HOLY_NOVA),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = agile(HOLY_NOVA_COST, HOLY_NOVA),
        spendType = "mana",

        startsCombat = true,
        known = knows(HOLY_NOVA),
        usable = unlocked("holy"),
    },

    -- 4 s (category 56); Weakened Soul for 15 s.
    power_word_shield = {
        id = 17,
        copy = rest(POWER_WORD_SHIELD),
        cast = 0,
        cooldown = 4,
        gcd = "spell",

        spend = agile(POWER_WORD_SHIELD_COST, POWER_WORD_SHIELD),
        spendType = "mana",

        startsCombat = false,
        toggle = "defensives",
        known = knows(POWER_WORD_SHIELD),
        nobuff = "weakened_soul",

        now = function()
            applyBuff("power_word_shield")
            applyBuff("weakened_soul")
        end,
        handler = function()
            applyBuff("power_word_shield")
            applyBuff("weakened_soul")
        end,
    },

    inner_fire = {
        id = 588,
        copy = rest(INNER_FIRE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = agile(INNER_FIRE_COST, INNER_FIRE),
        spendType = "mana",

        startsCombat = false,
        known = knows(INNER_FIRE),

        now = function()
            applyBuff("inner_fire", nil, 20)
        end,
        handler = function()
            applyBuff("inner_fire", nil, 20)
        end,
    },

    -- Off the GCD (DB2 start recovery 0); 180 s.
    -- shortcut: the client starts the cooldown when the buff is spent (wowsims's OnExpire); here at the cast, the
    -- client's cooldown read corrects it.
    inner_focus = {
        id = 14751,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows({ 14751 }),
        nobuff = "inner_focus",

        now = function()
            applyBuff("inner_focus")
        end,
        handler = function()
            applyBuff("inner_focus")
        end,
    },

    -- 20% of base mana, Mental Agility's cut; off the GCD; 180 s. On the player here (the wowsims builds cast it on
    -- themselves); the aura is Hekili_Shared's (`shared = "player"`: another Priest's too), not re-registered.
    power_infusion = {
        id = 10060,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        spend = function()
            return 0.2 * (1 - perRank(MENTAL_AGILITY, talent.mental_agility.rank))
        end,
        spendType = "mana",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows({ 10060 }),

        now = function()
            applyBuff("power_infusion")
        end,
        handler = function()
            applyBuff("power_infusion")
        end,
    },

    -- The wand (5019, off the GCD, free): wowsims's Shoot is a channel that blocks the rotation until its one shot, a
    -- wand speed later (its core/wand.go; the Smite log's target aura 5019 from the cast to the shot). UNMEASURED: what
    -- the client shows for an auto-repeat Shoot (a channel, a success per shot).
    shoot = {
        id = 5019,
        expects = "travel",
        velocity = 20,
        school = "physical", -- the wand's school: U7 deferred
        cast = wandSpeed(),
        channeled = true,
        tick_time = wandSpeed(),
        cooldown = 0,
        gcd = "off",

        startsCombat = true,
        known = knows({ 5019 }),

        now = shot(),
        start = shot(),
    },
})

-- Talents: { talent tree (1 Discipline, 2 Holy, 3 Shadow: the dominant tree picks the spec), rank 1's spell, max rank }:
-- the DB2's 47 nodes (`wowdb talents PRIEST`; the tree is the DB2's Talent.TabID, the max rank its rank slots), keys
-- the snake_case names; then the Forever-only nodes, absent from the DB2's Talent table, in wowsims's tree
-- (ui/sim/talents/trees/priest.json: their trees and ranks; the definition spell its spellId). wowsims's Forever tree
-- drops some Era nodes (Unbreakable Will, Improved Power Word: Fortitude, Divine Spirit, Force of Will, Lightwell,
-- Shadow Affinity, Improved Fade, Improved Vampiric Embrace and the unnamed Holy 14911) and gives others fewer ranks
-- (Silent Resolve, Mental Agility, Wand Specialization 3 / 3 / 2; Twilight Focus 3 to the DB2's 2): the DB2's are kept
-- until the live export (no Forever node holds them). The costs read Mental Agility and Devouring Contagion, the cast
-- times Divine Fury, Mind Blast's cooldown Improved Mind Blast, Shadow Word: Pain's duration Improved Shadow Word: Pain.
spec:RegisterTalents({
    -- Discipline (tree 1)
    unbreakable_will = { 1, 14522, 5 },
    wand_specialization = { 1, 14524, 5 },
    silent_resolve = { 1, 14523, 5 },
    improved_power_word_fortitude = { 1, 14749, 2 },
    improved_power_word_shield = { 1, 14748, 3 },
    martyrdom = { 1, 14531, 2 },
    inner_focus = { 1, 14751, 1 },
    meditation = { 1, 14521, 3 },
    improved_inner_fire = { 1, 14747, 3 },
    mental_agility = { 1, 14520, 5 },
    improved_mana_burn = { 1, 14750, 2 },
    mental_strength = { 1, 18551, 5 },
    divine_spirit = { 1, 14752, 1 },
    force_of_will = { 1, 18544, 5 },
    power_infusion = { 1, 10060, 1 },
    -- Holy (tree 2)
    twilight_focus = { 2, 14913, 2 },
    improved_renew = { 2, 14908, 3 },
    holy_specialization = { 2, 14889, 5 },
    spell_warding = { 2, 27900, 5 },
    divine_fury = { 2, 18530, 5 },
    holy_nova = { 2, 15237, 1 },
    blessed_recovery = { 2, 27811, 3 },
    inspiration = { 2, 14892, 3 },
    holy_reach = { 2, 27789, 2 },
    improved_healing = { 2, 14912, 3 },
    searing_light = { 2, 14909, 2 },
    holy_14911 = { 2, 14911, 2 }, -- the DB2 names neither the node nor its spell (tier 4, column 0)
    spirit_of_redemption = { 2, 20711, 1 },
    spiritual_guidance = { 2, 14901, 5 },
    spiritual_healing = { 2, 14898, 5 },
    lightwell = { 2, 724, 1 },
    -- Shadow (tree 3)
    spirit_tap = { 3, 15270, 5 },
    blackout = { 3, 15268, 5 }, -- wowsims's node names 15326, the DB2's rank 5
    shadow_affinity = { 3, 15318, 3 },
    improved_shadow_word_pain = { 3, 15275, 2 },
    shadow_focus = { 3, 15260, 5 },
    improved_psychic_scream = { 3, 15392, 2 },
    improved_mind_blast = { 3, 15273, 5 },
    mind_flay = { 3, 15407, 1 },
    improved_fade = { 3, 15274, 2 },
    shadow_reach = { 3, 17322, 3 },
    shadow_weaving = { 3, 15257, 5 },
    silence = { 3, 15487, 1 },
    vampiric_embrace = { 3, 15286, 1 },
    improved_vampiric_embrace = { 3, 27839, 2 },
    darkness = { 3, 15259, 5 },
    shadowform = { 3, 15473, 1 },
    -- Forever-only (wowsims's trees and ranks)
    power_in_light = { 1, 1309969, 5 },
    twin_disciplines = { 1, 1225132, 5 },
    holy_precision = { 1, 1309957, 3 },
    soul_warding = { 1, 402000, 1 },
    penance = { 1, 402174, 1 },
    renewed_hope = { 1, 425280, 5 },
    divine_aegis = { 1, 431622, 3 },
    binding_heal = { 2, 401937, 1 },
    litany_of_light = { 2, 1317006, 2 },
    prayer_of_mending = { 2, 401859, 1 },
    improved_mind_flay = { 3, 1225139, 2 },
    dark_inspiration = { 3, 1326159, 5 },
    devouring_contagion = { 3, 1309950, 2 },
    early_demise = { 3, 1310076, 2 },
})

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and
-- run it, never this block (tests/Forever/priest_spec.lua checks it matches). Each pack's .simc is generated from its
-- wowsims recipe (`make wowsims-packs`, tools/wowsims/specs/priest_*.lua).
spec:RegisterPack(
    "Shadow (wowsims.com)",
    20261021002,
    [[Hekili:vA17Vnkoq0)w2V0lrxe)k71TnAzL2v7EA7Q7QQo6Nn4Gnb3a2iBtJIuf)TF2MuIHajz)sIXEM3B8mZBaGp4zqeckXGhd8cU13lW3Zlaej3xHbrvW0TWnQfuyP63OCiITRjz2o2obPu4KYkNRTAFbdI0iTUMuiFGcwpkOIkCki6P)7HFe98kHbmquobHWTEGfPtqYQMezoUj5WEUzmo(vmVjbHZG1fYMKV(0)0KO2UjPdGAIRMrHBfNGfsxuLWvhGiHRu9mHUXX8OZlcgD(cffCivuOIBKAnttjr0Karig9pul2I3lCAs(oucxnsOm7FF4zfi5szLyLR7gImVETo6Dhy6CfMQigTC59l9qEF0BPNJklYzzKcvwgMkjmQWPIJvoVgkdBtvBQHC0csw4hwxNL5yTPtD1nTE1B3Tu2oAZVobV)m0TKqrXRlGcz35hyrfJLdjrVNIJotvaGG8TXcykNKrsXAhkHuOtAnNJPYphg455zBpUOMIfXfKn5Yf1cCmlllEtkk0x77mjPehU8n9FFj0)oV3oCDSDR9(mVhQ1C8w4fXl4iEghgbjneejUu0hSExzCjJssJ5QqAARkHVW4X6KrCftV50M2MCJ3X4O4kiHUiJLwlcdmPFe2QaC0MHLb8RSAUQtoUQaUPgpgedTzaeJ0kmi2qyOm3(qcLI5XgQgK7BP3)e8ZkG7nfMzhkewq0wnUr1E(QJV9bZFB2hMY85ZhLJExHsvb1KioasNvVRmark1OqD0G5ufeHuygm2oDrT8rZGsmfUUaJaF7DvQAMwNcbePudsmNabrJOEasfltasF1KnqNQQ04SCaowfbDK2HRT8Xg131hwcUZO40m(XRLrJa7CCfyXLTAuZYFDLS0Pw1oD7v6KT(v73NUs)orrRD(UboBv6Nw5oSR54HGitVTUdrb(9xe8r002x0(h2hCFVjAcpoiWy25B4TMmySEyN9ujtlHCxy5BqyypDVWsRA71u97nh5SdsmSpS)(u21wnS)SlNOh10Ron(ihGo1g19I4lpxX8I8PgSCX39FUro9Q2MWcwlZzCq0pXBjfe13Z83h(CfZXG)p]]
)
spec:RegisterPack(
    "Smite (wowsims.com)",
    20261021001,
    [[Hekili:LszuVnnmqC8pl8cSkQssthdOImjqaInbtt49StCJV0ywITLTtR6l5ZoNtZABkztdqvQY6U)3V7YDNnDg9okHZCa9M4O4lMffplkAgL42QbkrZYVNTcpiz14)KAHdAZoBJAJvuBdYv1t8I2wPyCpOLnIk3vs6YrzA1qoLC7pV6lK7wWf2CHUsirULcoh2ffyZhpplAZCLOXEBHfkdSgmTzCOG1u5AZ(4TFVndn3M9q8nIqFoTHAJaSUqU2g6lrUn06LK6qRc5QGoJb)YQKtMI5XWK2kS(54zLpVcBBgJZvYxHhUh2AdAZ(mZXwms9C2pU6oesPZPTlcdxjCLnl9FcHNiDcYelB(85VFEep68O5rby30OkevytHL7ekPnqBam4LmxIwTbmPczrJf9mTXcPQII0v58KzTx3RpXwQuUHoNkksQzswGo39HKzr7f)6KWsv120cHbMwOYBSjXEXN9coSSPOiyV3Gg9lpGioAY)jJlhLHuTM1f7Ha1ngTY2fRx8AifKqnooVmz(aa2sgxTjDJYWt1mH84A5Hs5uni1JrObjtMd(i2zmO3sGby8TdYMF)zyFno6pe0EnLGtA)46K7cvcRZ2D3B36lE8MU7IycxwbC6NOKJMHEN9Be49i)eMsYnygmcgLC8SL6WmDcOdkFgd2d5zVgkPRx6bJ0N)ps)YNf9ZpH(a5(9Jbj8zUN4b)MhTSFITJJB6dDoSQV4rQ6(9NJZ2yBwEeV9rq0Tin(0oUBA)UNmqh(JS)nK)M1SHp30bcrXACLkdL8n4ErLaFU7R9VM15M(7)]]
)
