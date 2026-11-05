-- Hekili_Druid/Druid.lua
-- The Forever Druid (Balance, Feral, Guardian and an idle Restoration: Hekili:NewClass): the Classic Druid kit with
-- Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build 1.60.1.70338,
-- wowdb; energy and mana costs are DB2 points, rage the DB2 cost / 10), Forever's Shifting Power, Berserk, Primal Bite
-- and Lacerate, bear rage per white swing in Bear Form only, Enrage's rage over time, Clearcasting as a cost modifier,
-- forms from the belief's Forms source, the bleeds' misses from the combat log, and the default priorities (the
-- wowsims.com packs). Design:
-- docs/superpowers/specs/2026-10-15-forever-druid-pack.md.
-- Talents: the DB2's 47 Classic nodes plus three placeholders the live export replaces (checkpoint Q1). Only rank 1 of
-- each talent is in the Forever DB2, so a modifier is rank 1's value x the rank (Classic's convention), floored at 0;
-- no cooldown or duration modifier is modelled but Improved Shifting Power's (spec D5).
-- Credits: Hekili (registration API and pack format); the abilities, auras, handlers and `swap_form` are ported from
-- Hekili's Classic profile (origin/classic:Classic/Druid.lua). Ported from Taco Dog Forever
-- (src/TacoDogForever_Druid/): the not-behind window (Feral.lua), Enrage's 10 + 2/s and Faerie Fire free in form
-- (Bear.lua), and the `form` alias over the forms (Expressions.lua's RegisterForms). The Feral, Guardian and Balance
-- (wowsims.com) priorities translate wowsims/forever's default APLs (MIT, https://github.com/wowsims/forever).

local Facade = Hekili.Client
local C_Spell, UnitClassBase = Facade.C_Spell, Facade.UnitClassBase
local GetTime = Facade.GetTime
local L = Hekili:GetLocale("Hekili_Druid")

if UnitClassBase("player") ~= "DRUID" then
    return
end

local state = Hekili.State
local IsCurrentSpell = C_Spell.IsCurrentSpell
local floor, max, min = math.floor, math.max, math.min

-- The class kit and its specs (ids the core's: Balance 100111, Feral 100112, Guardian 100113, Restoration 100114).
-- Feral and Guardian ride the Feral Combat tree: its points pick Feral; Guardian is chosen (/hekili spec guardian).
local spec = Hekili:NewClass("DRUID", {
    specs = {
        {
            key = "balance",
            name = L["Balance"],
            tree = 1,
            icon = 136096,
            role = "attack",
            ranged = true,
            package = "Balance (wowsims.com)",
        },
        { key = "feral", name = L["Feral"], tree = 2, icon = 132115, role = "attack", package = "Feral (wowsims.com)" },
        {
            key = "guardian",
            name = L["Guardian"],
            tree = 2,
            icon = 132276,
            role = "tank",
            package = "Guardian (wowsims.com)",
        },
        { key = "restoration", name = L["Restoration"], tree = 3, icon = 136041, role = "healer", unsupported = true },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's), and the per-rank values the DB2 gives.
local CLAW = { 1082, 3029, 5201, 9849, 9850 }
local SHRED = { 5221, 6800, 8992, 9829, 9830 }
local RAKE = { 1822, 1823, 1824, 9904, 1289140 } -- 1289140: Forever's variant
local RIP = { 1079, 9492, 9493, 9752, 9894, 9896, 1289141 }
local FEROCIOUS_BITE = { 1328618, 22568, 22827, 22828, 22829, 31018, 1289142 }
local RAVAGE = { 6785, 6787, 9866, 9867 }
local POUNCE = { 9005, 9823, 9827 }
local POUNCE_BLEED = { 9007, 9824, 9826 }
local COWER = { 8998, 9000, 9892 }
local PROWL = { 5215, 6783, 9913 }
local DASH = { 1850, 9821 }
local SHIFTING_POWER = { 1322605 }
local BERSERK = { 417141 }
local CAT_FORM = { 768 }
local BEAR_FORM = { 5487, 9634 } -- Dire Bear Form is Bear Form's rank 2
local MOONKIN_FORM = { 24858 }
local TRAVEL_FORM = { 783 }
local AQUATIC_FORM = { 1066 }
local MAUL = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 }
local SWIPE = { 779, 780, 769, 9754, 9908 }
local PRIMAL_BITE = { 407995, 1238069, 1238070, 1238073 } -- Mangle, renamed
local LACERATE = { 1328617, 1328616, 414644, 1235826, 1235827 } -- hotfix 113554: the talent rank 1, rank 2 at 34
local DEMORALIZING_ROAR = { 99, 1735, 9490, 9747, 9898 }
local GROWL = { 6795 }
local BASH = { 5211, 6798, 8983 }
local BASH_STUN = { 2, 3, 4 }
local CHALLENGING_ROAR = { 5209 }
local ENRAGE = { 5229 }
local FRENZIED_REGENERATION = { 22842 }
local FERAL_CHARGE = { 1238122, 16979 } -- the trainer's spell, then the old talent's
local FAERIE_FIRE = { 770, 778, 9749, 9907 }
local FAERIE_FIRE_COST = { 55, 75, 95, 115 }
local WRATH = { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 }
local WRATH_COST = { 10, 20, 40, 50, 70, 80, 100, 120 }
local WRATH_CAST = { 1.5, 1.7, 2, 2, 2, 2, 2, 2 }
local STARFIRE = { 2912, 8949, 8950, 8951, 9875, 9876, 25298 }
local STARFIRE_COST = { 95, 135, 180, 230, 275, 315, 340 }
local MOONFIRE = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 }
local MOONFIRE_COST = { 25, 50, 75, 105, 150, 190, 235, 280, 325, 375 }
local INSECT_SWARM = { 5570, 24974, 24975, 24976, 24977 }
local INSECT_SWARM_COST = { 45, 85, 100, 140, 160 }
local HURRICANE = { 16914, 17401, 17402 }
local HURRICANE_COST = { 880, 1180, 1495 }
local ROOTS = { 339, 1062, 5195, 5196, 9852, 9853 }
local ROOTS_COST = { 50, 65, 80, 95, 110, 125 }
local ROOTS_DURATION = { 12, 15, 18, 21, 24, 27 }
local INNERVATE = { 29166 }
local BARKSKIN = { 22812 }
local NATURES_GRASP = { 16689, 16810, 16811, 16812, 16813, 17329 }
local NATURES_GRASP_COST = { 50, 65, 80, 95, 110, 125 }
local MARK_OF_THE_WILD = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }
local MARK_OF_THE_WILD_COST = { 20, 50, 100, 160, 240, 340, 445 }
local GIFT_OF_THE_WILD = { 21849, 21850 }
local GIFT_OF_THE_WILD_COST = { 900, 1200 }
local THORNS = { 467, 782, 1075, 8914, 9756, 9910 }
local THORNS_COST = { 35, 60, 105, 170, 240, 320 }
local HEALING_TOUCH = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 }
local HEALING_TOUCH_COST = { 25, 55, 110, 190, 280, 350, 425, 520, 630, 755, 840 }
local HEALING_TOUCH_CAST = { 1.5, 2, 2.5, 3, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5 }
local REGROWTH = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 }
local REGROWTH_COST = { 70, 125, 170, 210, 250, 305, 370, 445, 525 }
local REJUVENATION = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 }
local REJUVENATION_COST = { 25, 40, 75, 105, 135, 160, 195, 235, 280, 335, 360 }

-- The forms, in `buff.form`'s member order (one is up at a time).
local FORMS = { "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form" }

-- Shifting Power's energy (DB2 1322605 effect 30, base 40) and bear rage per white swing (spec §2.3, D4): the
-- two-hand rate (4.5 a second) x the form's unhasted 2.5 s swing, 11.25 a swing, and a crit doubles it (22.5: wowsims
-- 7c28cfa731 core/rage.go, from Forever combat logs; owner ruling W1 2026-11-02), until checkpoint Q8.
-- The swing is the form's fixed period, not the belief's out-of-combat base read, which holds the pull's form (1.0 s
-- after a Cat pull) through an in-combat shift (GCD kinds design D4; checkpoint G6 reads both forms' speeds).
local SHIFTING_POWER_ENERGY = 40
local BEAR_RAGE_RATE = 4.5
local BEAR_SWING = 2.5
-- Primal Fury ("Blood Frenzy" on Forever, DB2 16958; wowsims/forever talents_feral_combat.go): a melee crit of ours in
-- Bear Form gives 16959's 5 rage, always at 2/2 and half the time at 1/2 (wowsims's ladder): its expected rage. The
-- Cat's combo point on a builder's crit is not declared: combo points are a plain read on Forever.
local PRIMAL_FURY = 5
local function primalFury(rank)
    return PRIMAL_FURY * rank / 2
end
-- A bear strike's `onCrit` (the belief's own crit, Families/Now.lua): a closure per ability.
local function primalFuryOnCrit()
    return function()
        if buff.bear_form.up then
            gain(primalFury(talent.primal_fury.rank), "rage")
        end
    end
end

local function rest(ids)
    local out = {}
    for i = 2, #ids do
        out[#out + 1] = ids[i]
    end
    return out
end

-- The highest known rank of a rank list, from the belief's spellbook: the same answer in the sim's `state`
-- environment and in a `now` handler's (event-facade spec §12a).
-- A helper's environment is the file's, so it keeps this local; a pack function's bare `knownRank` is its environment's.
local rankOf = state.knownRank

local function knows(ids)
    return function()
        return rankOf(ids) > 0
    end
end

-- A per-rank value at the highest known rank, else the first rank's (nothing known yet).
local function byRank(values, ids)
    return values[rankOf(ids)] or values[1]
end

-- Moonglow (16845) on its class mask's spells (Wrath, Moonfire, Starfire, Insect Swarm, Hurricane, Entangling Roots,
-- Thorns) and Improved Wrath (16814 effect 1) on Wrath: the DB2's -25% and -50% are the full ranks'. Moonglow's ranks
-- follow wowsims/forever's ladder (spells_auto_gen.go 16845: -8, -17, -25 %; its log: Moonfire 281.25 at 3/3).
local MOONGLOW = { 0.92, 0.83, 0.75 }
local function moonglow(rank)
    return MOONGLOW[rank] or 1
end

-- shortcut: after a /reload in combat energy's regen rate stays 0 for the rest of the fight (the belief's calibrate
-- returns early at ref == 0); upgrade with a `regen` meta field forwarded by the adapter after checkpoint Q3.
-- refundOnAvoid (energy here, rage below): the share an ability flagged `refundOnAvoid = true` gives back when dodged,
-- parried or missed (wowsims/forever druid/feral.go refundOnMiss and MissRefund: 0.8 where the DB2 flags Discount
-- Power On Miss). Not Ferocious Bite (flagged in the DB2, but wowsims issues no refund), Swipe, Faerie Fire (Feral) or
-- Demoralizing Roar.
spec:RegisterResource(Enum.PowerType.Energy, nil, nil, { refundOnAvoid = 0.8 })
spec:RegisterResource(Enum.PowerType.ComboPoints)

spec:RegisterResource(
    Enum.PowerType.Rage,
    {
        -- Rage per white swing in Bear or Dire Bear Form only (the Warrior's speed rule; Cat and caster swings add
        -- none).
        -- `aura` gates it in both layers (the belief's swing entry, spec §0.3; Hekili's forecast); `stop` too.
        -- A white crit adds one more base swing (without the two-hand factor), as wowsims's, and Primal Fury's rage:
        -- `crit`. A yellow crit's Primal Fury is the strikes' `onCrit`.
        -- shortcut: misses, Natural Reaction and rage from damage taken are unmodelled; the belief's swing-scale
        -- calibration absorbs a steady bias. Upgrade from the combat-log rows once a non-cast `now` exists.
        mainhand = {
            swing = "mainhand",
            aura = "bear_form",

            last = function()
                local swing = state.swings.mainhand
                local t = state.query_time
                if state.mainhand_speed == 0 then
                    return 0
                end
                return swing + floor((t - swing) / state.mainhand_speed) * state.mainhand_speed
            end,

            interval = "mainhand_speed",

            stop = function()
                return state.swings.mainhand == 0 or not state.buff.bear_form.up
            end,
            value = function()
                return BEAR_RAGE_RATE * BEAR_SWING
            end,
            crit = function()
                return BEAR_RAGE_RATE * BEAR_SWING + primalFury(talent.primal_fury.rank)
            end,
        },

        -- Enrage's aura (25503): 2 rage every second for 10 s (DB2: periodic energize 20 every 1000 ms).
        -- No `pausesDecay`: whether Enrage pauses the out-of-combat decay is unverified (checkpoint Q9).
        enrage = {
            aura = "enrage",

            last = function()
                local app = state.buff.enrage.applied
                return app + floor(state.query_time - app)
            end,

            interval = 1,
            value = 2,
        },
    },
    nil,
    {
        -- Out-of-combat rage loss per second: the Warrior's measured 1.25 (its Rage tooltip), until checkpoint Q9 reads
        -- it in Bear Form.
        decay = function()
            return 1.25
        end,
        -- Stepped and front-loaded, as the Warrior's.
        decayInterval = function()
            return 1
        end,
        refundOnAvoid = 0.8, -- the Energy line's note above
    }
)

-- Mana: secret even out of combat. A cost below 1 is a percent of base mana (DB2 PowerCostPct: the forms, Shifting
-- Power, Innervate), priced in both layers from `base`: wowsims's 1244 at 60 (its log: Shifting Power and Cat Form
-- 684 = 55%, Innervate 62 = 5%, whole mana rounded down) until the client's cost read teaches the player's own. The
-- five-second rule (C3): spirit regen a second outside it, none inside it, the declared start the out-of-combat read
-- replaces (wowsims/forever's Feral and Balance logs: 2.175 and 2.2 mana a 0.1 s tick outside it, pre-raid gear).
spec:RegisterResource(
    Enum.PowerType.Mana,
    {
        -- Innervate (DB2 29166), as wowsims/forever applies its two effects (sim/core/spelldata/parse_effects_table.go):
        -- A_MOD_POWER_REGEN_PERCENT +400% (spirit regen x 5) and A_MOD_MANA_REGEN_INTERRUPT 100% (all of it while
        -- casting), so 5 x the full spirit regen inside the five-second rule too (its Feral log: 108.75 = 5 x 21.75 a
        -- second over 22-41 s). wowsims's rule (owner: matches the game), not yet measured on Forever.
        -- DB2 29166: aura 110 +400% (`spirit` x 5), aura 134 100% (`share` 1). Its seconds weigh the calibration.
        innervate = { aura = "innervate", spirit = 5, share = 1 },
        -- The Serenity Field trinket's buff (item 272439; DB2 aura 1291103: aura 29 Spirit +72, 15 s; an item's buff any
        -- Druid may wear; the other classes' packs: docs/dev/gaps.md): Spirit +72 raises the spirit regen S = 6.25 +
        -- Spirit/8 by 9 a second, so the part x (S + 9) / S, Spirit the belief's out-of-combat read (druid_balance.log:
        -- Tag 2 22.0 -> 31.0 over 114.9-126 s at Spirit 126); 1 before that read.
        serenity_field = {
            aura = "serenity_field",
            item = 272439, -- the replay's key: wowsims logs the buff by its item
            spirit = function()
                local _, s = stat("UnitStat", 5)
                return s > 0 and 1 + 9 / (6.25 + s / 8) or 1
            end,
        },
    },
    nil,
    {
        fsr = { spirit = 22, mp5 = 0 },
        base = 1244, -- wowsims's ExtraClassBaseStats, level 60
    }
)

-- Talents: { talent tree (1 Balance, 2 Feral Combat, 3 Restoration: the dominant tree picks the spec), rank 1's spell,
-- max rank }: the DB2's 47 Classic nodes (16 Balance, 16 Feral Combat, 15 Restoration; the tree is the DB2's
-- Talent.TabID), keys Classic's, until the live export (checkpoint Q1) replaces them. The last two are placeholders
-- the export replaces, so no reader names an unregistered key; their tree is 0 until the export places them.
spec:RegisterTalents({
    -- Balance (16)
    improved_wrath = { 1, 16814, 5 },
    natures_grasp = { 1, 16689, 1 },
    improved_natures_grasp = { 1, 17245, 4 },
    improved_entangling_roots = { 1, 16918, 3 },
    improved_moonfire = { 1, 16821, 5 },
    natural_weapons = { 1, 16902, 5 },
    natural_shapeshifter = { 1, 16833, 3 },
    improved_thorns = { 1, 16836, 3 },
    omen_of_clarity = { 1, 16864, 1 },
    natures_reach = { 1, 16819, 2 },
    vengeance = { 1, 16909, 5 },
    improved_starfire = { 1, 16850, 5 },
    natures_grace = { 1, 16880, 1 },
    moonglow = { 1, 16845, 3 },
    moonfury = { 1, 16896, 5 },
    moonkin_form = { 1, 24858, 1 },
    -- Feral Combat (16)
    ferocity = { 2, 16934, 5 },
    feral_aggression = { 2, 16858, 5 },
    feral_instinct = { 2, 16947, 5 },
    brutal_impact = { 2, 16940, 2 },
    thick_hide = { 2, 16929, 5 },
    feline_swiftness = { 2, 17002, 2 },
    feral_charge = { 2, 16979, 1 },
    sharpened_claws = { 2, 16942, 3 },
    -- Shredding Attacks: wowsims/forever's 3 points (Shred 42 at 3/3, its log; the DB2 node lists 2 rank spells)
    improved_shred = { 2, 16966, 3 },
    predatory_strikes = { 2, 16972, 3 },
    blood_frenzy = { 2, 16952, 2 },
    primal_fury = { 2, 16958, 2 }, -- "Blood Frenzy" on Forever
    savage_fury = { 2, 16998, 2 },
    faerie_fire_feral = { 2, 16857, 1 },
    heart_of_the_wild = { 3, 17003, 5 }, -- hotfix 113554: moved to Restoration
    leader_of_the_pack = { 2, 17007, 1 },
    predatory_discipline = { 2, 1328613, 1 }, -- hotfix 113554: Bite keeps its extra energy
    lacerate = { 2, 1328617, 1 }, -- hotfix 113554: Lacerate's rank 1 is a talent
    -- Restoration (15)
    improved_mark_of_the_wild = { 3, 17050, 5 },
    furor = { 2, 17056, 5 }, -- hotfix 113554: moved to Feral Combat
    improved_healing_touch = { 3, 17069, 5 },
    natures_focus = { 3, 17063, 5 },
    improved_enrage = { 3, 17079, 2 },
    reflection = { 3, 17106, 3 },
    insect_swarm = { 3, 5570, 1 },
    subtlety = { 3, 17118, 5 },
    tranquil_spirit = { 3, 24968, 5 },
    improved_rejuvenation = { 3, 17111, 3 },
    natures_swiftness = { 3, 17116, 1 },
    gift_of_nature = { 3, 17104, 5 },
    improved_tranquility = { 3, 17123, 2 },
    improved_regrowth = { 3, 17074, 5 },
    swiftmend = { 3, 18562, 1 },
    -- Forever-only placeholders, replaced by the export (checkpoint Q1).
    natures_splendor = { 0, 1223083, 1 },
    eclipse = { 0, 408248, 3 },
})

spec:RegisterAuras({
    serenity_field = { id = 1291103, duration = 15, max_stack = 1 },
    aquatic_form = {
        id = 1066,
        duration = 3600,
        max_stack = 1,
    },
    barkskin = {
        id = 22812,
        duration = 15,
        max_stack = 1,
    },
    bash = {
        id = 5211,
        copy = rest(BASH),
        duration = function()
            return (BASH_STUN[knownRank(BASH)] or 2) + 0.5 * talent.brutal_impact.rank
        end,
        max_stack = 1,
    },
    bear_form = {
        id = 5487,
        copy = { 9634 },
        duration = 3600,
        max_stack = 1,
    },
    berserk = {
        id = 417141,
        duration = 15,
        max_stack = 1,
    },
    -- The Howling Idol's equip aura (272427): "Reduces the cooldown of your Shifting Power ability" (DB2 1291059).
    howling_idol = {
        id = 1291059,
        duration = 3600,
        max_stack = 1,
    },
    -- The Wolfshead Helm's equip aura (8345, DB2 17768): Shifting Power +5 energy, Enrage's instant rage +50%
    -- (wowsims/forever sim/druid/items.go; its log gains the aura at 0 s and 45 energy a Shifting Power).
    wolfshead_helm = {
        id = 17768,
        duration = 3600,
        max_stack = 1,
    },
    -- Classic's alias without the other classes' bleeds.
    bleed = {
        alias = { "rake", "rip", "pounce_bleed", "lacerate" },
        aliasType = "debuff",
        aliasMode = "longest",
    },
    cat_form = {
        id = 768,
        duration = 3600,
        max_stack = 1,
    },
    challenging_roar = {
        id = 5209,
        duration = 6,
        max_stack = 1,
    },
    -- Omen of Clarity's proc (a passive on Forever): the next covered ability is free (the cost modifier below). It
    -- procs at most once per 10 s (16864's SpellAuraOptions.ProcCategoryRecovery 10000; wowsims ICDMs 10000), the ICD
    -- wowsims names by 16864.
    clearcasting = {
        id = 16870,
        duration = 15,
        max_stack = 1,
        icd = 10,
        icdSpell = 16864,
    },
    dash = {
        id = 1850,
        copy = rest(DASH),
        duration = 15,
        max_stack = 1,
    },
    demoralizing_roar = {
        id = 99,
        copy = rest(DEMORALIZING_ROAR),
        duration = 30,
        max_stack = 1,
    },
    eclipse = {
        id = 408255,
        copy = { 441260 },
        duration = 15,
        max_stack = 4,
    },
    entangling_roots = {
        id = 339,
        copy = rest(ROOTS),
        duration = function()
            return ROOTS_DURATION[knownRank(ROOTS)] or 12
        end,
        max_stack = 1,
    },
    -- The rage entry's aura: 25503 is the 10 s buff, 5229 the cast.
    enrage = {
        id = 25503,
        copy = { 5229 },
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    faerie_fire = {
        id = 770,
        copy = rest(FAERIE_FIRE),
        duration = 40,
        max_stack = 1,
    },
    feral_charge_effect = {
        id = 19675,
        duration = 4,
        max_stack = 1,
    },
    -- Cat or Bear Form: Faerie Fire's free cost and cooldown.
    feral_form = {
        alias = { "cat_form", "bear_form" },
        aliasType = "buff",
        aliasMode = "first",
    },
    form = {
        alias = FORMS,
        aliasType = "buff",
        aliasMode = "first",
    },
    frenzied_regeneration = {
        id = 22842,
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    gift_of_the_wild = {
        id = 21849,
        copy = rest(GIFT_OF_THE_WILD),
        duration = 3600,
        max_stack = 1,
    },
    growl = {
        id = 6795,
        duration = 3,
        max_stack = 1,
    },
    hurricane = {
        id = 16914,
        copy = rest(HURRICANE),
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    innervate = {
        id = 29166,
        duration = 20,
        tick_time = 1,
        max_stack = 1,
    },
    insect_swarm = {
        id = 5570,
        copy = rest(INSECT_SWARM),
        duration = function()
            return 12 + 2 * talent.natures_splendor.rank
        end,
        tick_time = 2,
        dot = "debuff", -- Insect Swarm's schedule
        max_stack = 1,
    },
    lacerate = {
        id = 1328617,
        copy = rest(LACERATE),
        duration = 15,
        tick_time = 3,
        max_stack = 5,
    },
    mark_of_the_wild = {
        id = 1126,
        copy = rest(MARK_OF_THE_WILD),
        duration = 3600,
        max_stack = 1,
    },
    -- Maul queued on the next swing (C_Spell.IsCurrentSpell, applied in reset_precast), a full swing long.
    maul = {
        duration = function()
            return state.mainhand_speed
        end,
        max_stack = 1,
    },
    moonfire = {
        id = 8921,
        copy = rest(MOONFIRE),
        duration = function()
            return (knownRank(MOONFIRE) > 1 and 12 or 9) + 3 * talent.natures_splendor.rank
        end,
        tick_time = 3,
        dot = "debuff", -- upstream's aura field (Engine/Sim/State.lua:3302): Moonfire's schedule
        max_stack = 1,
    },
    moonkin_form = {
        id = 24858,
        duration = 3600,
        max_stack = 1,
    },
    natures_grace = {
        id = 16886,
        duration = 3,
        max_stack = 1,
    },
    natures_grasp = {
        id = 16689,
        copy = rest(NATURES_GRASP),
        duration = 45,
        max_stack = 1,
    },
    -- The target faces us: the rest of 5 s after a "must be behind" error (reset_precast).
    not_behind = {
        duration = 5,
        max_stack = 1,
    },
    pounce = {
        id = 9005,
        copy = rest(POUNCE),
        duration = function()
            return 2 + 0.5 * talent.brutal_impact.rank
        end,
        max_stack = 1,
    },
    pounce_bleed = {
        id = 9007,
        copy = rest(POUNCE_BLEED),
        duration = 18,
        tick_time = 3,
        max_stack = 1,
    },
    prowl = {
        id = 5215,
        copy = rest(PROWL),
        duration = 3600,
        max_stack = 1,
    },
    rake = {
        id = 1822,
        copy = rest(RAKE),
        duration = 9,
        tick_time = 3,
        max_stack = 1,
    },
    rip = {
        id = 1079,
        copy = rest(RIP),
        duration = 12,
        tick_time = 2,
        max_stack = 1,
    },
    thorns = {
        id = 467,
        copy = rest(THORNS),
        duration = 600,
        max_stack = 1,
    },
    travel_form = {
        id = 783,
        duration = 3600,
        max_stack = 1,
    },
})

-- Clearcasting (16870): aura 108 misc 14 (cost) -100% on the abilities its class masks name (15973374 / 100664659 /
-- 1024 / 142606400 against SpellClassSet 7), so the next one is free; a covered cast whose declared cost is above 0
-- takes the charge. The rank-1 IDs of the covered abilities this file registers (higher ranks resolve through each
-- ability's `copy`), from
--   select distinct o.SpellID, n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID
--     join SpellPower p on p.SpellID=o.SpellID where o.SpellClassSet=7 and (p.ManaCost>0 or p.PowerCostPct>0) and not
--     ((o.SpellClassMask_0 & 15973374)=0 and (o.SpellClassMask_1 & 100664659)=0 and (o.SpellClassMask_2 & 1024)=0
--     and (o.SpellClassMask_3 & 142606400)=0)
-- Covered but unregistered: Tranquility, Swiftmend, the rune spells. Not covered: Wrath, Faerie Fire, Cower,
-- Challenging Roar, Mark and Gift of the Wild, Shifting Power. Checkpoint Q6 confirms Primal Bite and Demoralizing Roar
-- (usable at 0 rage with Clearcasting up).
spec:RegisterCostMod({
    aura = "clearcasting",
    pct = -1,
    charges = 1,
    spells = {
        8921,
        2912,
        5570,
        16914,
        5185,
        8936,
        774,
        1082,
        1822,
        5221,
        1079,
        1328618,
        9005,
        6785,
        779,
        6807,
        1328617,
        5211,
        1238122,
        339,
        467,
        16689,
        407995,
        99,
    },
})

-- A shift (Classic's swap_form, Forever's rules): the other forms and a queued Maul go; into Bear all rage is lost
-- (Furor's 20%-a-rank chance of 10 is unknowable at the cast: none); into Cat the energy is kept (Furor's Forever
-- restore is unmodelled until checkpoint Q3). The forms' `now` write the same lines.
spec:RegisterStateFunction("swap_form", function(form)
    for i = 1, #FORMS do
        removeBuff(FORMS[i])
    end
    removeBuff("maul")
    if form == "bear_form" then
        spend(rage.lo, "rage") -- the sim's floor (border batch 2)
    end
    applyBuff(form)
end)

-- The UI_ERROR_MESSAGE types of "You must be behind your target" (checkpoint Q11 records it; until then none, and the
-- window never opens). On the spec object so the headless specs can name one. Shred's positional fallback (its
-- `usable`, the packs' Claw) depends on it: until Q11 fills it, Shred is never refused.
local NOT_BEHIND_ERRORS = {}
spec.notBehindErrors = NOT_BEHIND_ERRORS
local NOT_BEHIND_WINDOW = 5
local behindErrAt = 0

spec:RegisterEvent("UI_ERROR_MESSAGE", function(_, errorType)
    if NOT_BEHIND_ERRORS[errorType] then
        behindErrAt = GetTime()
    end
end)

spec:RegisterHook("reset_precast", function()
    -- The form comes from the belief's Forms source (Game/State/Sources/Forms.lua) through the aura walk.
    local maul = knownRank(MAUL)
    if maul > 0 and IsCurrentSpell(MAUL[maul]) then
        applyBuff("maul")
    end

    if now == query_time and behindErrAt > 0 and now - behindErrAt < NOT_BEHIND_WINDOW then
        applyBuff("not_behind", behindErrAt + NOT_BEHIND_WINDOW - now)
    end
end)

spec:RegisterAbilities({
    aquatic_form = {
        id = 1066,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.20 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(AQUATIC_FORM),
        nobuff = "aquatic_form",

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            applyBuff("aquatic_form")
        end,

        handler = function()
            swap_form("aquatic_form")
        end,
    },

    barkskin = {
        id = 22812,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        startsCombat = false,
        known = knows(BARKSKIN),
        toggle = "defensives",

        now = function()
            applyBuff("barkskin")
        end,

        handler = function()
            applyBuff("barkskin")
        end,
    },

    bash = {
        id = 5211,
        copy = rest(BASH),
        cast = 0,
        cooldown = 60, -- Brutal Impact's -30 s unmodelled (a cooldown modifier)
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims bash.go; DB2 Discount Power On Miss
        known = knows(BASH),
        form = "bear_form",

        now = function()
            applyDebuff("target", "bash", (BASH_STUN[knownRank(BASH)] or 2) + 0.5 * talent.brutal_impact.rank)
        end,

        handler = function()
            applyDebuff("target", "bash")
        end,
    },

    bear_form = {
        id = 5487,
        copy = { 9634 },
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.55 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(BEAR_FORM),
        nobuff = "bear_form",

        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            spend(rage.current, "rage")
            applyBuff("bear_form")
        end,

        handler = function()
            swap_form("bear_form")
        end,
    },

    berserk = {
        id = 417141,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        known = knows(BERSERK),
        toggle = "cooldowns",
        -- "Requires Cat Form, Bear Form, Dire Bear Form" (DB2 text): whichever is up.
        form = function()
            if buff.bear_form.up then
                return "bear_form"
            end
            return "cat_form"
        end,

        now = function()
            applyBuff("berserk")
            setCooldown("primal_bite", 0) -- Berserk removes Primal Bite's cooldown (DB2 text)
        end,

        handler = function()
            applyBuff("berserk")
            setCooldown("primal_bite", 0)
        end,
    },

    cat_form = {
        id = 768,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.55 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(CAT_FORM),
        nobuff = "cat_form",

        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            applyBuff("cat_form")
        end,

        handler = function()
            swap_form("cat_form")
        end,
    },

    challenging_roar = {
        id = 5209,
        expects = "debuff", -- no damage (DB2, wowsims): its ticket takes its own avoid only
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        spend = 15,
        spendType = "rage",

        startsCombat = true,
        known = knows(CHALLENGING_ROAR),
        form = "bear_form",

        now = function()
            applyDebuff("target", "challenging_roar")
        end,

        handler = function()
            applyDebuff("target", "challenging_roar")
        end,
    },

    claw = {
        id = 1082,
        copy = rest(CLAW),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 45 - talent.ferocity.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims claw.go; DB2 Discount Power On Miss
        known = knows(CLAW),
        form = "cat_form",

        handler = function()
            gain(1, "combo_points")
        end,
    },

    cower = {
        id = 8998,
        copy = rest(COWER),
        cast = 0,
        cooldown = 10,
        gcd = "totem",

        spend = 20,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims cower.go; DB2 Discount Power On Miss
        known = knows(COWER),
        form = "cat_form",
    },

    dash = {
        id = 1850,
        copy = rest(DASH),
        cast = 0,
        cooldown = 300,
        gcd = "off",

        startsCombat = false,
        known = knows(DASH),
        form = "cat_form",

        now = function()
            applyBuff("dash")
        end,

        handler = function()
            applyBuff("dash")
        end,
    },

    demoralizing_roar = {
        id = 99,
        -- it deals no damage, so its ticket pays its own avoid only, never a Maul's wound in its frame
        expects = "debuff",
        copy = rest(DEMORALIZING_ROAR),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows(DEMORALIZING_ROAR),
        form = "bear_form",

        now = function()
            applyDebuff("target", "demoralizing_roar")
        end,

        handler = function()
            applyDebuff("target", "demoralizing_roar")
        end,
    },

    -- 10 rage now (DB2 effect 30 base 100), then 2 a second for 10 s from its aura (the rage resource's entry).
    enrage = {
        id = 5229,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        startsCombat = false,
        known = knows(ENRAGE),
        form = "bear_form",

        now = function()
            gain(buff.wolfshead_helm.up and 15 or 10, "rage")
            applyBuff("enrage")
        end,

        handler = function()
            gain(buff.wolfshead_helm.up and 15 or 10, "rage")
            applyBuff("enrage")
        end,
    },

    entangling_roots = {
        id = 339,
        copy = rest(ROOTS),
        cast = 1.5,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(ROOTS_COST, ROOTS) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(ROOTS),
        nobuff = "feral_form",

        now = function()
            applyDebuff("target", "entangling_roots", ROOTS_DURATION[knownRank(ROOTS)] or 12)
        end,

        handler = function()
            applyDebuff("target", "entangling_roots")
        end,
    },

    faerie_fire = {
        id = 770,
        expects = "debuff", -- no damage (DB2, wowsims): its ticket takes its own avoid only
        copy = rest(FAERIE_FIRE),
        cast = 0,
        -- Free with a 6 s cooldown in Cat or Bear Form (TDF Bear.lua; checkpoint Q7 confirms).
        cooldown = function()
            return (buff.cat_form.up or buff.bear_form.up) and 6 or 0 -- not the `feral_form` alias: no belief read
        end,
        gcd = "spell",

        spend = function()
            if buff.cat_form.up or buff.bear_form.up then
                return 0
            end
            return byRank(FAERIE_FIRE_COST, FAERIE_FIRE)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(FAERIE_FIRE),

        now = function()
            applyDebuff("target", "faerie_fire")
        end,

        handler = function()
            applyDebuff("target", "faerie_fire")
        end,
    },

    feral_charge = {
        id = 1238122,
        copy = { 16979 },
        cast = 0,
        cooldown = 15,
        gcd = "off",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        known = knows(FERAL_CHARGE),
        form = "bear_form",

        now = function()
            applyDebuff("target", "feral_charge_effect")
        end,

        handler = function()
            applyDebuff("target", "feral_charge_effect")
        end,
    },

    -- Bite converts all the energy left after its cost (DB2 22568 text), Clearcasting's free Bite too.
    ferocious_bite = {
        id = 1328618, -- hotfix 113554: rank 1 at 24 (22568 now rank 2)
        copy = rest(FEROCIOUS_BITE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 35,
        spendType = "energy",

        startsCombat = true,
        known = knows(FEROCIOUS_BITE),
        form = "cat_form",

        usable = function()
            return combo_points.current > 0, "requires combo points"
        end,

        -- Predatory Discipline (hotfix 113554, wowsims ferocious_bite.go): the extra energy stays
        now = function()
            if not talent.predatory_discipline.enabled then
                spend(energy.current, "energy")
            end
        end,

        handler = function()
            spend(combo_points.current, "combo_points")
            if not talent.predatory_discipline.enabled then
                spend(energy.lo, "energy") -- the sim's floor (border batch 2)
            end
        end,
    },

    -- Its rage drain is unmodelled: health is secret, and the drain stops at full health.
    frenzied_regeneration = {
        id = 22842,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        startsCombat = false,
        known = knows(FRENZIED_REGENERATION),
        toggle = "defensives",
        form = "bear_form",

        now = function()
            applyBuff("frenzied_regeneration")
        end,

        handler = function()
            applyBuff("frenzied_regeneration")
        end,
    },

    gift_of_the_wild = {
        id = 21849,
        copy = rest(GIFT_OF_THE_WILD),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(GIFT_OF_THE_WILD_COST, GIFT_OF_THE_WILD)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(GIFT_OF_THE_WILD),
        nobuff = "feral_form",

        now = function()
            applyBuff("gift_of_the_wild")
        end,

        handler = function()
            applyBuff("gift_of_the_wild")
        end,
    },

    growl = {
        id = 6795,
        expects = "debuff", -- no damage (DB2, wowsims): its ticket takes its own avoid only
        cast = 0,
        cooldown = 8,
        gcd = "off",

        startsCombat = true,
        known = knows(GROWL),
        form = "bear_form",

        now = function()
            applyDebuff("target", "growl")
        end,

        handler = function()
            applyDebuff("target", "growl")
        end,
    },

    -- No pack line: registered so a cast spends Clearcasting.
    healing_touch = {
        id = 5185,
        copy = rest(HEALING_TOUCH),
        cast = function()
            return byRank(HEALING_TOUCH_CAST, HEALING_TOUCH)
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(HEALING_TOUCH_COST, HEALING_TOUCH)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(HEALING_TOUCH),
        nobuff = "feral_form",
    },

    hurricane = {
        id = 16914,
        copy = rest(HURRICANE),
        cast = 10,
        channeled = true,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(HURRICANE_COST, HURRICANE) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(HURRICANE),
        nobuff = "feral_form",
        aura = "hurricane",

        now = function()
            applyDebuff("target", "hurricane")
        end,

        start = function()
            applyDebuff("target", "hurricane")
        end,
    },

    innervate = {
        id = 29166,
        cast = 0,
        cooldown = 360,
        gcd = "spell",

        spend = function()
            return 0.05
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(INNERVATE),
        toggle = "cooldowns",

        -- From any other form: the client leaves it to cast (Classic's handler, swap_form( "" )); the Feral priority
        -- shifts back after it.
        -- wowsims/forever: castable in Moonkin Form; UNMEASURED on Forever (checkpoint in layout.md)
        now = function()
            for i = 1, #FORMS do
                if FORMS[i] ~= "moonkin_form" then
                    removeBuff(FORMS[i])
                end
            end
            removeBuff("maul")
            applyBuff("innervate")
        end,

        handler = function()
            for i = 1, #FORMS do
                if FORMS[i] ~= "moonkin_form" then
                    removeBuff(FORMS[i])
                end
            end
            removeBuff("maul")
            applyBuff("innervate")
        end,
    },

    insect_swarm = {
        id = 5570,
        expects = "ticks",
        school = "nature", -- its debuff dot aura: 2 s ticks over 12 s
        copy = rest(INSECT_SWARM),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(INSECT_SWARM_COST, INSECT_SWARM) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(INSECT_SWARM),
        nobuff = "feral_form",

        now = function()
            applyDebuff("target", "insect_swarm", 12 + 2 * talent.natures_splendor.rank)
        end,

        handler = function()
            applyDebuff("target", "insect_swarm")
        end,
    },

    lacerate = {
        id = 1328617,
        copy = rest(LACERATE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        -- Shredding Attacks: -1 rage a rank, wowsims's (its log: Cost = 13 at 2/3); the DB2 text's ${$m2/-10} reads 6
        -- (m2 = -60; checkpoint Q12)
        spend = function()
            return max(0, 15 - talent.improved_shred.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims lacerate.go; DB2 Discount Power On Miss
        onCrit = primalFuryOnCrit(),
        known = knows(LACERATE),
        form = "bear_form",

        now = function()
            applyDebuff("target", "lacerate", 15, min(5, debuff.lacerate.stack + 1))
        end,

        handler = function()
            applyDebuff("target", "lacerate", 15, min(5, debuff.lacerate.stack + 1))
        end,
    },

    mark_of_the_wild = {
        id = 1126,
        copy = rest(MARK_OF_THE_WILD),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(MARK_OF_THE_WILD_COST, MARK_OF_THE_WILD)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(MARK_OF_THE_WILD),
        nobuff = "feral_form",

        now = function()
            applyBuff("mark_of_the_wild")
        end,

        handler = function()
            applyBuff("mark_of_the_wild")
        end,
    },

    maul = {
        id = 6807,
        copy = rest(MAUL),
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = function()
            return max(0, 15 - talent.ferocity.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims maul.go; DB2 Discount Power On Miss
        onCrit = primalFuryOnCrit(),
        -- The belief: paid at the main hand's next swing, which then brings no rage. Hekili's own simulation pays
        -- at the press (the Warrior's Heroic Strike alike), so the two differ by up to one swing.
        onNextSwing = true,
        known = knows(MAUL),
        form = "bear_form",

        usable = function()
            return not buff.maul.up, "Maul is already queued"
        end,

        handler = function()
            applyBuff("maul")
        end,
    },

    moonfire = {
        id = 8921,
        expects = "instant",
        school = "arcane", -- its debuff dot aura ticks every 3 s, 9 or 12 s by rank
        copy = rest(MOONFIRE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(MOONFIRE_COST, MOONFIRE) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(MOONFIRE),
        nobuff = "feral_form",

        now = function()
            local base = knownRank(MOONFIRE) > 1 and 12 or 9 -- rank 1 lasts 9 s
            applyDebuff("target", "moonfire", base + 3 * talent.natures_splendor.rank)
        end,

        handler = function()
            applyDebuff("target", "moonfire")
        end,
    },

    moonkin_form = {
        id = 24858,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.35 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(MOONKIN_FORM),
        nobuff = "moonkin_form",

        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            applyBuff("moonkin_form")
        end,

        handler = function()
            swap_form("moonkin_form")
        end,
    },

    natures_grasp = {
        id = 16689,
        copy = rest(NATURES_GRASP),
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = function()
            return byRank(NATURES_GRASP_COST, NATURES_GRASP)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(NATURES_GRASP),
        nobuff = "feral_form",

        now = function()
            applyBuff("natures_grasp")
        end,

        handler = function()
            applyBuff("natures_grasp")
        end,
    },

    pounce = {
        id = 9005,
        copy = rest(POUNCE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 50,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims pounce.go; DB2 Discount Power On Miss
        known = knows(POUNCE),
        missable = "pounce_bleed",
        buff = "prowl",

        now = function()
            removeBuff("prowl")
            applyDebuff("target", "pounce", 2 + 0.5 * talent.brutal_impact.rank)
            applyDebuff("target", "pounce_bleed")
        end,

        handler = function()
            removeBuff("prowl")
            applyDebuff("target", "pounce")
            applyDebuff("target", "pounce_bleed")
            gain(1, "combo_points")
        end,
    },

    primal_bite = {
        id = 407995,
        copy = rest(PRIMAL_BITE),
        cast = 0,
        -- 6 s (DB2 category); Berserk (417141, DB2 text) "removes its cooldown": its `now` and handler end the running
        -- one and none starts while it is up (the belief evaluates this in its own context, Families/Casts.lua).
        cooldown = function()
            return buff.berserk.up and 0 or 6
        end,
        gcd = "spell",

        spend = function()
            return max(0, 20 - talent.ferocity.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims primal_bite.go; DB2 Discount Power On Miss
        onCrit = primalFuryOnCrit(),
        known = knows(PRIMAL_BITE),
        form = "bear_form",
    },

    prowl = {
        id = 5215,
        copy = rest(PROWL),
        cast = 0,
        cooldown = 10,
        gcd = "off",

        startsCombat = false,
        known = knows(PROWL),
        form = "cat_form",

        usable = function()
            return combat == 0, "cannot be in combat"
        end,

        now = function()
            applyBuff("prowl")
        end,

        handler = function()
            applyBuff("prowl")
        end,
    },

    rake = {
        id = 1822,
        copy = rest(RAKE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 40 - talent.ferocity.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims rake.go; DB2 Discount Power On Miss
        known = knows(RAKE),
        -- a dodged, parried or missed cast leaves no debuff (core: Engine/Schema/Spec.lua trackMisses)
        missable = true,
        form = "cat_form",

        now = function()
            applyDebuff("target", "rake")
        end,

        handler = function()
            applyDebuff("target", "rake")
            gain(1, "combo_points")
        end,
    },

    ravage = {
        id = 6785,
        copy = rest(RAVAGE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 60,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims ravage.go; DB2 Discount Power On Miss
        known = knows(RAVAGE),
        buff = "prowl",

        now = function()
            removeBuff("prowl")
        end,

        handler = function()
            removeBuff("prowl")
            gain(1, "combo_points")
        end,
    },

    -- No pack line: registered so a cast spends Clearcasting.
    regrowth = {
        id = 8936,
        copy = rest(REGROWTH),
        cast = 2,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(REGROWTH_COST, REGROWTH)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(REGROWTH),
        nobuff = "feral_form",
    },

    rejuvenation = {
        id = 774,
        copy = rest(REJUVENATION),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(REJUVENATION_COST, REJUVENATION)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(REJUVENATION),
        nobuff = "feral_form",
    },

    rip = {
        id = 1079,
        copy = rest(RIP),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 30,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims rip.go; DB2 Discount Power On Miss
        known = knows(RIP),
        missable = true,
        form = "cat_form",

        usable = function()
            return combo_points.current > 0, "requires combo points"
        end,

        now = function()
            applyDebuff("target", "rip")
        end,

        handler = function()
            applyDebuff("target", "rip")
            spend(combo_points.current, "combo_points")
        end,
    },

    -- Forever's Tiger's Fury replacement: 55% of base mana into 40 energy (DB2 1322605). No toggle: it is the core.
    shifting_power = {
        id = 1322605,
        cast = 0,
        -- spec D5; checkpoint Q4. 8 s by hotfix 113554 (wowsims 5508974417; Improved Shifting Power removed; the
        -- DB2 70707 base file still says 16). The Howling Idol's equip aura (1291059) takes 0.5 s off (DB2 1291059
        -- effect 1310233 -500 ms; wowsims sim/druid/item_idols.go and TestHowlingIdolShortensShiftingPower, both pins).
        cooldown = function()
            return buff.howling_idol.up and 7.5 or 8
        end,
        gcd = "totem",

        spend = function()
            return 0.55 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(SHIFTING_POWER),
        form = "cat_form",

        now = function()
            gain(SHIFTING_POWER_ENERGY + (buff.wolfshead_helm.up and 5 or 0), "energy")
        end,

        handler = function()
            gain(SHIFTING_POWER_ENERGY + (buff.wolfshead_helm.up and 5 or 0), "energy")
        end,
    },

    shred = {
        id = 5221,
        copy = rest(SHRED),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 60 - 6 * talent.improved_shred.rank)
        end, -- Shredding Attacks
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims shred.go; DB2 Discount Power On Miss
        known = knows(SHRED),
        form = "cat_form",

        -- Shred needs us behind the target, which the game tells only by refusing: a "must be behind" error opens the
        -- not-behind window (TDF Feral.lua), where Shred is refused and the packs' Claw fallbacks
        -- (`!action.shred.ready`) fire; settings.behind says the player always stands behind.
        usable = function()
            return settings.behind or not buff.not_behind.up, "not behind the target"
        end,

        handler = function()
            gain(1, "combo_points")
        end,
    },

    starfire = {
        id = 2912,
        expects = "instant",
        school = "arcane",
        copy = rest(STARFIRE),
        cast = 3.5, -- shorter with an Eclipse charge (unmodelled)
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(STARFIRE_COST, STARFIRE) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(STARFIRE),
        nobuff = "feral_form",

        -- No `now`: spending a charge is no `now` verb; the belief's charges end with the 15 s aura.
        handler = function()
            if buff.eclipse.up then
                removeStack("eclipse")
            end
        end,
    },

    swipe_bear = {
        id = 779,
        copy = rest(SWIPE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return max(0, 20 - talent.ferocity.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        known = knows(SWIPE),
        form = "bear_form",
        onCrit = primalFuryOnCrit(),
    },

    thorns = {
        id = 467,
        copy = rest(THORNS),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(THORNS_COST, THORNS) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(THORNS),
        nobuff = "feral_form",

        now = function()
            applyBuff("thorns")
        end,

        handler = function()
            applyBuff("thorns")
        end,
    },

    travel_form = {
        id = 783,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.20 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(TRAVEL_FORM),
        nobuff = "travel_form",

        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            applyBuff("travel_form")
        end,

        handler = function()
            swap_form("travel_form")
        end,
    },

    wrath = {
        id = 5176,
        expects = "travel",
        velocity = 20,
        school = "nature",
        copy = rest(WRATH),
        cast = function()
            return byRank(WRATH_CAST, WRATH) - 0.1 * talent.improved_wrath.rank
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(WRATH_COST, WRATH)
                * moonglow(talent.moonglow.rank)
                * (1 - 0.5 * talent.improved_wrath.rank / 5)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(WRATH),
        nobuff = "feral_form",

        -- Eclipse's charges (R §9 open: +1 or +2 a Wrath) while the talent is known.
        now = function()
            if talent.eclipse.rank > 0 then
                addStack("eclipse", nil, 2)
            end
        end,

        handler = function()
            if talent.eclipse.rank > 0 then
                addStack("eclipse", nil, 2)
            end
        end,
    },
})

-- The setting Shred's `usable` reads (TDF's name and default).
spec:RegisterSetting("behind", false, {
    type = "toggle",
    name = L["Always Behind"],
    desc = L["When enabled, Shred is recommended over Claw as if you always stand behind the target."],
    width = "full",
})

-- The maintenance debuff (tools/wowsims/apl.lua rule 15; the recipe's `maintenance`): a raid's debuff, off in game
-- (open-world mobs die before it pays off), on under the harness (`sim`: wowsims's raid boss).
spec:RegisterSetting("maintain_demoralizing_roar", false, {
    type = "toggle",
    name = L["Maintain Demoralizing Roar"],
    desc = L["Keep Demoralizing Roar on the target, as a raid tank does, and recast it only when it is missing (that includes the levels before " .. "Lacerate). Off: the priority never shows it, and Berserk no longer waits for it."],
    width = "full",
    sim = true,
}, "guardian")

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc (a wowsims.com
-- pack's from its recipe, `make wowsims-packs`); edit those and run it, never these blocks
-- (tests/Forever/druid_spec.lua checks they match). Pick one with /hekili priority <name>. Restoration is deferred.
spec:RegisterPack(
    "Feral (wowsims.com)",
    20261103001,
    [[Hekili:TVvBVnkoq4Fl9lCWT9siPT7lvLv6ovT66P7wD6YEFfIdyA8fceHnTksr53(nM3IDWKaKQUkD5lvjMXJNz8mpEWpP2JS)M9epedB)1XMJF)OrMxzAoYEcB9kS9Kvi3fOhHpeIwc)9l4yuW2P6ph9mLSKoWnAPbxO1bripUIMLqcypeAptPoPRWU2tU)F(3hU)wFUQSNmN45HZKhtDvVc3UDkBoE708Xg6hfJFchVDQh2hLeW2o9x)7)C7uy4TtlMFcziF1Od9ItiEdtxnxeBiAvaDiYdTIrEcpa(2G)JgfACjSeXOqAay0EWNJ4ljHUDkYZlk8NGpSaVMoy707rm0Tkmf9)6HVbkzoJTIE7WHpsyZtMXT(H7jQbOtWIXJ)41J9nrF4Jx7nacHXr(KaicJCzKOqQfyRoWmwEjX36Izj((dkgzqYQT)rUyVZAOlkiWj7Robek7s(oL1mCmfhV44c6gff4f9Civuu68yS3L(rUjuRrClqx)ISNUZkwecZAZ(wMHw2ibyuSlIYiHpYhvYocqplR7tu5ALZp1UZNS8yXyK3AdJJhpMfGXEsbdi1jYLeLqDMry4mlg2xNf5SkIeYGu0K4yCi7Zw3ODHUp5X5mNy8sejK(zRrMggBQr8R0Ke(URKTp6CIp3fH59mooBDl9jXhL5CA66QIoA4qC8JRheeD31MGPCXre6gWGbXQ3fld2XKv5HApCQs5dW3oQecoYCkK00OzcEN1yLsQmnqxV03(fPh7grzgVd2FUtqrPdM6)LQhTaVNLWhrHF(jTJnjLo6bf9oRrQL9u9vUMYDwdTdKv1OsgaZ3dWBeLKecwYtOI6LgxGRVefI45HJU20uR4lYvv)mphviL16ktn1P1LRBoCyb0qQWfJPkL9gj32hHJjyhFsCM7u3IXqbqrYGOL4qNiFhaOlMWwpahIaufVnvNfX1ZjlmlIHjTlKzXfO0v3JkS4Aqb3LriU9lKvOo7sVYya0MQb3RMyJczuLwpkTiRQSQnxXSvWERfAQrap7CJIH25fzayBQkHcqiUlOs0ACHsWLIQnHKQ8sTYuUIuZItXVmHIHekFNhD9A95X1hUueCUOlq5cdKJzOPe)u5G7NbPmFuCK8LOIT9EJQbqO2LpN8UnglDgQeKG2kO3SbJkg0yJAKdT(4UQ4U0c3hyoCc5zBn9fFxIH8LTfoBx81(wrBIOVoTIkKKPSri1pROhQxU3asD3usdTF)Xc14zV)8B(tB6re6re6reQGiCg0ouFLBFLBFLBLk3DNLxET4w4GKqm1jGVROOP9cvlFdt61mE1BEQgblVWNIHl2KhDJHuphPxxTfKKj9sU1E)0s1ukkPQGvS)sP8vQ3dJqRkCqvWabfNF)HwLTnDEIt08YKsiHZaeHM7vcf)v3Cli(jTM5SC79eHg)H9yaLkRuvF2QQUG0h7jpbjnW47XGmN1bAkJ1zu)cF8RPmyNFj72)wbfQ2tkAZc(umHHJji7jvOs1MbRqTkqMUJSL3jJk8CGz(8VQlZV8egUgUEpnSZGRTtYMYo6oZjncBpjf5Mh1G19MdSUN6cREJxnVScXmaKq2gFFxIUzhwXN(hQz6Y06k76TJE3wWVl3G(yngKCFqYguzmRR8(2WwL20sMF7e4CZrNBb8SAmR2aAjaqRgHUBq0TbJUvG0NUhlbtFGuSS82p1P6W8J)5kyKznAOKS4Uc89QWACJOno1pR7ajbk)K80oYN8PqOC3zuUJukFcCk3ksL)oXQCtOvUn8k)IsSmKuYekfpqlt5Tii0V0z7XbnhgC3BJDMG73Cxtif)Gn6M20LiI0z72(PEM4p4DbOwBh(T1YHxY64wb4IqE1l39sTl5fgR8fggRklxQNc5DVgDtvclfiM0AX29EGkCCHBlK)Ws1umLo2TtRymOBug04Fcf1uJ0isdAiRbkrUu8YrhMI1wZXAFG)Gez1hEoeUqLRe6TfuGA6dFfI5TKbX(gtEZ0yYXit8fGnXgEhz10JK0ycxBY(xTBrLFLx16T)bz9Wg9Wg9Wghh248OVR(Q5(Q5(Q5JxnNDnb7O7TfxuG4V9i57NlFH2JHc96EqJ)DhDKF4rP(cykOe28Oy7j)oEbjGSDQ(xY)NBo9X2))p]]
)
spec:RegisterPack(
    "Balance (wowsims.com)",
    20261104001,
    [[Hekili:1svxpTnpu4FlCdJQvL0uYauffPxeAAG2lAAHDRBCIpPXRo2r2o0H0u(TVJtHGBA7y7IDtL754NpSppoKiYdKeg1cK7Noz6zrrtINmjIKyFQgij108v0L4cjTc)9AQGkZH20twRwB4vMGCv1i32EsOOmhvznCH9wjjBVSAQHCsYnF9B3EZSSnKrsk5mgSbbyYpKkZAtTLyXNRfwO0WJGUnLbf0gHTn9)(YNBtXYTPVYqdp0PPjKPB4SWN1mKwlWsBagG)j47gLC0yucnvAeOXz4ALtsUPnLYyk57WfRGNmbTP3qT0z7XkN8)3(assP1wBMfgUKBlBYCUpCWwhHCIogMEr80Ij0ZViMfGxJAvbxG3i0Clxjnb1AabNrTZRuk5kUCbIVAmVy(rznffb(vdAQBVBhGVFE4An1w6W4A(iSaKqfhmxg3V9)s2robrJemle8LL2XngyHQOyXYC28i)DXLsq)iEz64SIkPb152fc1LXtoUWbDHgQOCP5QtN4JZjCbxdJlu5nM5t7Sed6nLR3adHKai3M1u8eShy(9haTSrR55ujS7D0vZJ93PXs1E(kYb4Ko6HCbV24m1XBxaHKV6QOFE0gwcEHIa4hqEJLlxoAKVeDdR27ijyiXG1g8(rWnwt3l2nzxC59DVGbjntamY1VeEij(JpssUMBbnNss27WLyrLgqK3C1PspX(dFhUtpGb6h)(Q)gXahFXd4ZZ67gc2(86kss6gpUZds2hEtYgen89)Rn2M0ZoWjUpk5RZorkhdNFqB9hgO(TjQxD0lD79FKt9loG)7sFe3qnP)li)tJyBl8bV0UmUZuOTOn2sLMK8jyfxWXV4(XN)GAxBYV(d]]
)
spec:RegisterPack(
    "Guardian (wowsims.com)",
    20261105000,
    [[Hekili:LJvBVnQrq4Fl(lPGQfy7MCxAuisTkQT5u7PQY1VcSMDWERxyr7UCP5Kf)27SgS9ABW21nsPv9djb2DE5zEMxyuIgh9POqkrdrFCYOjVB84r3mA0OOq9lLquyjjDbzg(qbjh)9pwrKugPOoX5zXZkwUYlvK7AK7fUGqn2AAfJRFQiAANMvvcPrHp(B)(tpE3SwRffoNrPqJkGkTx)CxDIEouN0EMFMqcFgK1juiJuX11jF3V(Z1j4X1jwMOI5BCRYNkRyu)mqs4tbI0NuYv(ekPuZ(m4HV59hkrH7q0nssHIJWNIplmULPQtiuQO4RWhwaVO8QtEKOj31bCC(LN(eAK5ADP6oF)zm98QPMiWFprDrBIOgMC71tYgrE)Txt9qYukYyCKUjPAMOqfKs484MxI5mLEOjBeKkeCQ45cv9hAf8Rd8ZKqXxyanwcZGcmsnxmKLfmhiC9CVYu99tgzRr3gFbaLXvLNwqkjhlqSLlhtfdRuqSillEwkny8WmrALc)lIdjkThx8qWUOOxLMyuAqJGELswoHhpLPbVffySBBckKlWml7lSIzXsbrA0ubAn(UYlNWk04pXhi2vodOW0QSmVdUYRQ8Q1(Mtsn0zRJrL6dtlxNy25kjyqG6bm2qS8NlB5H77WkPcL21DNSkbKmioJjHv0rlETo(neP2a10wfJf35RG5kqU5ipRYjVnfVbtbPcKl2l5JQ706WwbAJMnqE9XsGqFzBqEyoSjupskE5GZOkX9I5XGRTsMBdCKTaEvbOWMPzZ1De)DtaTKAZrvLUlh0LywESTvoyDzHDJLJJtlXSPOblK2)iLg)mWdb34EWnTX49bJ9WBh0nID6eHl7ot6(V9u5HmBNZESi5ZasxDSrqBDyZW2alOT)Diw6kp))Imt9hIcXpQQq13BRdZNRuMLt209HV8XvR(afKPCGg99rHwDGMlB)8lUrtdlGAlrxkzKOWx3zthL3(NtCNM5I0iHDMSH9qRDOKZCCvpZRqiOnBmAkI7k5S29wHqxOElE(7vYF518V9jVnCZ6o)OWvT(g2PHvBwp(y06(l310Ze3S2)2UMoy81wOZnpTti7SbQXsFZLGL2zUg9V(s0VTcdv)MElDS2rDdvoU)ocZURgd(U(Rf7l9ALPoP5FFpH7b1t2E(mk)E13)98wR8K7vUAQ0T9vTTD13Di6xRnJFLIbti8T9ecBwmENa4GDMBAHxx23rlS9i43UT5(p8a0tnb9iFK5ma3rxT7ODX7mehRbiv65c88FcwW4S6eNFO9)IWQRJ(R]]
)

-- The hand-built lists the wowsims.com packs replace (wowsims packs plan, P9): a saved choice of one falls back to the
-- spec's default.
spec:RetirePacks({ "Feral", "Guardian", "Balance" })
