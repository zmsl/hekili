-- Hekili_Druid/Druid.lua
-- The Forever Druid (Balance, Feral, Guardian and an idle Restoration: Hekili:NewClass): the Classic Druid kit with
-- Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build 1.60.1.70338,
-- wowdb; energy and mana costs are DB2 points, rage the DB2 cost / 10), Forever's Shifting Power, Berserk, Primal Bite
-- and Lacerate, bear rage per white swing in Bear Form only, Enrage's rage over time, Clearcasting as a cost modifier,
-- forms from the belief's Forms source, the bleeds' misses from the combat log, and the default priorities (Feral;
-- Guardian and Balance provisional). Design: docs/superpowers/specs/2026-10-15-forever-druid-pack.md.
-- Talents: the DB2's 47 Classic nodes plus three placeholders the live export replaces (checkpoint Q1). Only rank 1 of
-- each talent is in the Forever DB2, so a modifier is rank 1's value x the rank (Classic's convention), floored at 0;
-- no cooldown or duration modifier is modelled but Improved Shifting Power's (spec D5).
-- Credits: Hekili (registration API and pack format); the abilities, auras, handlers and `swap_form` are ported from
-- Hekili's Classic profile (origin/classic:Classic/Druid.lua). Ported from Taco Dog Forever
-- (src/TacoDogForever_Druid/): the `excess_e` energy reservation (Expressions.lua, itself after Zachary Samsel's
-- `excess_e` in Hekili's Wrath Feral module, origin/wrath_release:Wrath/Druid.lua L413-566), the Feral, bear and
-- Balance priorities (APLs/feral.simc, bear.simc, balance.simc, after Nerdegghead and the guides they cite), the
-- not-behind window (Feral.lua), Enrage's 10 + 2/s and Faerie Fire free in form (Bear.lua), and the `form` alias over
-- the forms (Expressions.lua's RegisterForms).

local Facade = Hekili.Client
local C_Spell, UnitClassBase = Facade.C_Spell, Facade.UnitClassBase
local GetTime = Facade.GetTime

if UnitClassBase("player") ~= "DRUID" then
    return
end

local state = Hekili.State
local IsCurrentSpell = C_Spell.IsCurrentSpell
local floor, max, min, huge = math.floor, math.max, math.min, math.huge

-- The class kit and its specs (ids the core's: Balance 100111, Feral 100112, Guardian 100113, Restoration 100114).
-- Feral and Guardian ride the Feral Combat tree: its points pick Feral; Guardian is chosen (/hekili spec guardian).
local spec = Hekili:NewClass("DRUID", {
    specs = {
        {
            key = "balance",
            name = "Balance",
            tree = 1,
            icon = 136096,
            role = "attack",
            ranged = true,
            package = "Balance",
        },
        { key = "feral", name = "Feral", tree = 2, icon = 132115, role = "attack", package = "Feral" },
        { key = "guardian", name = "Guardian", tree = 2, icon = 132276, role = "tank", package = "Guardian" },
        { key = "restoration", name = "Restoration", tree = 3, icon = 136041, role = "healer", unsupported = true },
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
local FEROCIOUS_BITE = { 22568, 22827, 22828, 22829, 31018, 1289142 }
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
local LACERATE = { 414644, 1235826, 1235827 }
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
-- Warrior's measured one-hand main-hand rate x the form's unhasted 2.5 s swing, 8.65 a swing, until checkpoint Q8.
-- The swing is the form's fixed period, not the belief's out-of-combat base read, which holds the pull's form (1.0 s
-- after a Cat pull) through an in-combat shift (GCD kinds design D4; checkpoint G6 reads both forms' speeds).
local SHIFTING_POWER_ENERGY = 40
local BEAR_RAGE_RATE = 3.46
local BEAR_SWING = 2.5
-- Rip's and Rake's energy (Rake's before Ferocity's -1 a rank), shared by their `spend` and `excess_e`'s reservations.
local RIP_COST = 30
local RAKE_COST = 40

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

-- A per-rank value at the highest known rank, else the first rank's (nothing known yet).
local function byRank(values, ids)
    return values[knownRank(ids)] or values[1]
end

-- shortcut: after a /reload in combat energy's regen rate stays 0 for the rest of the fight (the belief's calibrate
-- returns early at ref == 0); upgrade with a `regen` meta field forwarded by the adapter after checkpoint Q3.
spec:RegisterResource(Enum.PowerType.Energy)
spec:RegisterResource(Enum.PowerType.ComboPoints)

spec:RegisterResource(
    Enum.PowerType.Rage,
    {
        -- Rage per white swing in Bear or Dire Bear Form only (the Warrior's speed rule; Cat and caster swings add none).
        -- `aura` gates it in both layers (the belief's swing entry, spec §0.3; Hekili's forecast); `stop` too.
        -- A white crit adds one more base swing, as the Warrior's (magey/forever-warrior issue 3 names the Bear and Dire Bear
        -- match; unmeasured here): `crit`.
        -- shortcut: misses, Blood Frenzy, Natural Reaction and rage from damage taken are unmodelled; the belief's
        -- swing-scale calibration absorbs a steady bias. Upgrade from the combat-log rows once a non-cast `now` exists.
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
                return BEAR_RAGE_RATE * BEAR_SWING
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
        -- Stepped and front-loaded, as the Warrior's (a function: Engine/Schema/Spec.lua setfenv's every meta field).
        decayInterval = function()
            return 1
        end,
    }
)

-- Mana: secret even out of combat; costs below 1 are fractions of the maximum in both layers (spec §0.1).
spec:RegisterResource(Enum.PowerType.Mana)

-- Talents: { talent tree (1 Balance, 2 Feral Combat, 3 Restoration: the dominant tree picks the spec), rank 1's spell,
-- max rank }: the DB2's 47 Classic nodes (16 Balance, 16 Feral Combat, 15 Restoration; the tree is the DB2's
-- Talent.TabID), keys Classic's, until the live export (checkpoint Q1) replaces them. The last three are placeholders
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
    improved_shred = { 2, 16966, 2 }, -- Shredding Attacks
    predatory_strikes = { 2, 16972, 3 },
    blood_frenzy = { 2, 16952, 2 },
    primal_fury = { 2, 16958, 2 }, -- "Blood Frenzy" on Forever
    savage_fury = { 2, 16998, 2 },
    faerie_fire_feral = { 2, 16857, 1 },
    heart_of_the_wild = { 2, 17003, 5 },
    leader_of_the_pack = { 2, 17007, 1 },
    -- Restoration (15)
    improved_mark_of_the_wild = { 3, 17050, 5 },
    furor = { 3, 17056, 5 },
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
    improved_shifting_power = { 0, 1322670, 2 },
    natures_splendor = { 0, 1223083, 1 },
    eclipse = { 0, 408248, 3 },
})

spec:RegisterAuras({
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
        max_stack = 1,
    },
    lacerate = {
        id = 414644,
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
        22568,
        9005,
        6785,
        779,
        6807,
        414644,
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
        spend(rage.current, "rage")
    end
    applyBuff(form)
end)

-- The UI_ERROR_MESSAGE types of "You must be behind your target" (checkpoint Q11 records it; until then none, and the
-- window never opens). On the spec object so the headless specs can name one.
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
        known = knows(BASH),
        buff = "bear_form",

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
        buff = function()
            if buff.bear_form.up then
                return "bear_form"
            end
            return "cat_form"
        end,

        now = function()
            applyBuff("berserk")
        end,

        handler = function()
            applyBuff("berserk")
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
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        spend = 15,
        spendType = "rage",

        startsCombat = true,
        known = knows(CHALLENGING_ROAR),
        buff = "bear_form",

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
        known = knows(CLAW),
        buff = "cat_form",

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
        known = knows(COWER),
        buff = "cat_form",
    },

    dash = {
        id = 1850,
        copy = rest(DASH),
        cast = 0,
        cooldown = 300,
        gcd = "off",

        startsCombat = false,
        known = knows(DASH),
        buff = "cat_form",

        now = function()
            applyBuff("dash")
        end,

        handler = function()
            applyBuff("dash")
        end,
    },

    demoralizing_roar = {
        id = 99,
        copy = rest(DEMORALIZING_ROAR),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows(DEMORALIZING_ROAR),
        buff = "bear_form",

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
        buff = "bear_form",

        now = function()
            gain(10, "rage")
            applyBuff("enrage")
        end,

        handler = function()
            gain(10, "rage")
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
            return byRank(ROOTS_COST, ROOTS)
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
        copy = rest(FAERIE_FIRE),
        cast = 0,
        -- Free with a 6 s cooldown in Cat or Bear Form (TDF Bear.lua; checkpoint Q7 confirms).
        cooldown = function()
            return buff.feral_form.up and 6 or 0
        end,
        gcd = "spell",

        spend = function()
            if buff.feral_form.up then
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
        buff = "bear_form",

        now = function()
            applyDebuff("target", "feral_charge_effect")
        end,

        handler = function()
            applyDebuff("target", "feral_charge_effect")
        end,
    },

    -- Bite converts all the energy left after its cost (DB2 22568 text), Clearcasting's free Bite too.
    ferocious_bite = {
        id = 22568,
        copy = rest(FEROCIOUS_BITE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 35,
        spendType = "energy",

        startsCombat = true,
        known = knows(FEROCIOUS_BITE),
        buff = "cat_form",

        usable = function()
            return combo_points.current > 0, "requires combo points"
        end,

        now = function()
            spend(energy.current, "energy")
        end,

        handler = function()
            spend(combo_points.current, "combo_points")
            spend(energy.current, "energy")
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
        buff = "bear_form",

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
        cast = 0,
        cooldown = 8,
        gcd = "off",

        startsCombat = true,
        known = knows(GROWL),
        buff = "bear_form",

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
            return byRank(HURRICANE_COST, HURRICANE)
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

        spend = 0.05,
        spendType = "mana",

        startsCombat = false,
        known = knows(INNERVATE),
        toggle = "cooldowns",

        -- From any form: the client leaves it to cast (Classic's handler, swap_form( "" )); the Feral priority shifts
        -- back after it.
        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            applyBuff("innervate")
        end,

        handler = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            applyBuff("innervate")
        end,
    },

    insect_swarm = {
        id = 5570,
        copy = rest(INSECT_SWARM),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(INSECT_SWARM_COST, INSECT_SWARM)
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
        id = 414644,
        copy = rest(LACERATE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        -- Shredding Attacks: -6 rage a rank by its DB2 text (m2 = -60; checkpoint Q12)
        spend = function()
            return max(0, 15 - 6 * talent.improved_shred.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        known = knows(LACERATE),
        buff = "bear_form",

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
        -- The belief: paid at the main hand's next swing, which then brings no rage. Hekili's own simulation pays
        -- at the press (the Warrior's Heroic Strike alike), so the two differ by up to one swing.
        onNextSwing = true,
        known = knows(MAUL),
        buff = "bear_form",

        usable = function()
            return not buff.maul.up, "Maul is already queued"
        end,

        handler = function()
            applyBuff("maul")
        end,
    },

    moonfire = {
        id = 8921,
        copy = rest(MOONFIRE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(MOONFIRE_COST, MOONFIRE)
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
        cooldown = 6, -- Berserk's no-cooldown rule unmodelled
        gcd = "spell",

        spend = function()
            return max(0, 20 - talent.ferocity.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        known = knows(PRIMAL_BITE),
        buff = "bear_form",
    },

    prowl = {
        id = 5215,
        copy = rest(PROWL),
        cast = 0,
        cooldown = 10,
        gcd = "off",

        startsCombat = false,
        known = knows(PROWL),
        buff = "cat_form",

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
            return max(0, RAKE_COST - talent.ferocity.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(RAKE),
        -- a dodged, parried or missed cast leaves no debuff (core: Engine/Schema/Spec.lua trackMisses)
        missable = true,
        buff = "cat_form",

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

        spend = RIP_COST,
        spendType = "energy",

        startsCombat = true,
        known = knows(RIP),
        missable = true,
        buff = "cat_form",

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
        cooldown = function()
            return 16 - 4 * talent.improved_shifting_power.rank
        end, -- spec D5; checkpoint Q4
        gcd = "totem",

        spend = function()
            return 0.55 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(SHIFTING_POWER),
        buff = "cat_form",

        now = function()
            gain(SHIFTING_POWER_ENERGY, "energy")
        end,

        handler = function()
            gain(SHIFTING_POWER_ENERGY, "energy")
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
        known = knows(SHRED),
        buff = "cat_form",

        handler = function()
            gain(1, "combo_points")
        end,
    },

    starfire = {
        id = 2912,
        copy = rest(STARFIRE),
        cast = 3.5, -- shorter with an Eclipse charge (unmodelled)
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(STARFIRE_COST, STARFIRE)
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
        buff = "bear_form",
    },

    thorns = {
        id = 467,
        copy = rest(THORNS),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(THORNS_COST, THORNS)
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
        copy = rest(WRATH),
        cast = function()
            return byRank(WRATH_CAST, WRATH) - 0.1 * talent.improved_wrath.rank
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(WRATH_COST, WRATH)
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

-- Shred needs us behind the target, which the game tells only by refusing: in a group the tank holds it, so Shred;
-- otherwise Claw. settings.behind says the player stands behind; a "must be behind" error says the target faces us
-- for 5 s (TDF Feral.lua; Classic's combat_mode setting replaced by Hekili's `group`).
spec:RegisterStateExpr("shred_ok", function()
    return settings.behind or (group and not buff.not_behind.up)
end)

-- excess_e (ported from Taco Dog Forever's Expressions.excess_e, credited above): the energy a GCD-triggering spender
-- (Shred, Claw) may use now and still pay the coming Rip (at settings.rip_cp combo points) and Rake refreshes, with
-- Shifting Power's energy counted once it is off cooldown, unless its GCD would start a refresh later than without it.
-- Up to three events sorted by due time in preallocated arrays (no table per call); solved backwards: the energy
-- needed before each event is its cost plus whatever regen cannot cover of the events after it, which honours the
-- energy cap. -math.huge when the spender's GCD would delay a refresh that could otherwise start on time. A refresh the
-- druid does not know reserves nothing. Refreshes are reserved at full price (the spender uses up Clearcasting); no
-- time to die (Forever hides target health). Times are relative to query_time.
local TOLERANCE = 0.1 -- within this much of its due time a refresh counts as on time
local CAT_GCD = 1 -- gcd = "totem"
local evT, evC, evK = { 0, 0, 0 }, { 0, 0, 0 }, { false, false, false } -- due, energy (negative: the credit), credit
local evS, evS0 = { 0, 0, 0 }, { 0, 0, 0 } -- start times with and without the credit

local function insertEvent(n, at, c, k)
    local j = n
    while j >= 1 and evT[j] > at do
        evT[j + 1], evC[j + 1], evK[j + 1] = evT[j], evC[j], evK[j]
        j = j - 1
    end
    evT[j + 1], evC[j + 1], evK[j + 1] = at, c, k
    return n + 1
end

-- Forward pass into `out`: nothing starts before the GCD before it ends (every event is on the GCD).
local function starts(n, gcdFree, useCredit, out)
    for k = 1, n do
        if useCredit or not evK[k] then
            local st = evT[k]
            if st < gcdFree then
                st = gcdFree
            end
            out[k] = st
            gcdFree = st + CAT_GCD
        end
    end
end

spec:RegisterStateExpr("excess_e", function()
    local cur, cap, regen = energy.current, energy.max, energy.regen
    local gcdFree = CAT_GCD
    local n = 0
    -- Rip, then Rake: due when the debuff falls off; -math.huge when it could start on time but for the spender's GCD
    -- (Clearcasting may make it free then: action.x.cost); reserved at the full price.
    if knownRank(RIP) > 0 and combo_points.current >= settings.rip_cp then
        local due = debuff.rip.remains
        if due < gcdFree - TOLERANCE and min(cap, cur + regen * due) >= action.rip.cost then
            return -huge
        end
        n = insertEvent(n, due, RIP_COST, false)
    end
    if knownRank(RAKE) > 0 then
        local due = debuff.rake.remains
        if due < gcdFree - TOLERANCE and min(cap, cur + regen * due) >= action.rake.cost then
            return -huge
        end
        n = insertEvent(n, due, max(0, RAKE_COST - talent.ferocity.rank), false)
    end
    if knownRank(SHIFTING_POWER) > 0 then
        n = insertEvent(n, cooldown.shifting_power.remains, -SHIFTING_POWER_ENERGY, true)
    end
    -- Use the credit only if its GCD starts no refresh later than without it.
    starts(n, gcdFree, false, evS0)
    starts(n, gcdFree, true, evS)
    local useCredit = true
    for k = 1, n do
        if not evK[k] and evS[k] > evS0[k] + TOLERANCE then
            useCredit = false
        end
    end
    local st = useCredit and evS or evS0
    -- Backward: the energy needed just before each event so it and everything after it are paid for.
    local need, nextStart = 0, nil
    for k = n, 1, -1 do
        if useCredit or not evK[k] then
            local carry = need
            if nextStart then
                carry = need - regen * (nextStart - st[k])
                if carry < 0 then
                    carry = 0
                end
            end
            need = evC[k] + carry
            if need < 0 then
                need = 0
            end
            nextStart = st[k]
        end
    end
    if nextStart then
        need = need - regen * nextStart
        if need < 0 then
            need = 0
        end
    end
    return cur - need
end)

-- The settings the priorities read (TDF's names and defaults).
spec:RegisterSetting("rip_cp", 5, {
    type = "range",
    name = "Rip Combo Points",
    desc = "Select the combo points at which Rip is applied and its energy reserved.",
    width = "full",
    min = 1,
    max = 5,
    step = 1,
})

spec:RegisterSetting("bite_finisher", false, {
    type = "toggle",
    name = "Ferocious Bite Finisher",
    desc = "When enabled, Ferocious Bite spends 5 combo points while Rip is up and no energy is held back.",
    width = "full",
}, "feral")

spec:RegisterSetting("behind", false, {
    type = "toggle",
    name = "Always Behind",
    desc = "When enabled, Shred is recommended over Claw as if you always stand behind the target.",
    width = "full",
})

spec:RegisterSetting("buffs", true, {
    type = "toggle",
    name = "Out-of-Combat Buffs",
    desc = "When enabled, Mark of the Wild and Thorns are recommended before combat when missing.",
    width = "full",
}, "feral", "balance")

spec:RegisterSetting("dump_rage", 60, {
    type = "range",
    name = "Swipe Rage Threshold",
    desc = "Select the rage at or above which the Guardian priority spends rage on Swipe.",
    width = "full",
    min = 0,
    max = 100,
    step = 1,
}, "guardian")

spec:RegisterSetting("use_enrage", false, {
    type = "toggle",
    name = "Use Enrage",
    desc = "When enabled, the Guardian priority uses Enrage when rage is short.",
    width = "full",
}, "guardian")

spec:RegisterSetting("moonkin", true, {
    type = "toggle",
    name = "Moonkin Form",
    desc = "When enabled, the Balance priority recommends Moonkin Form before combat.",
    width = "full",
}, "balance")

spec:RegisterSetting("trash_dots", true, {
    type = "toggle",
    name = "Moonfire on Trash",
    desc = "When enabled, the Balance priority keeps Moonfire on targets that are not bosses.",
    width = "full",
}, "balance")

spec:RegisterSetting("starfire_filler", false, {
    type = "toggle",
    name = "Starfire Filler",
    desc = "When enabled, the Balance priority fills with Starfire instead of Wrath.",
    width = "full",
}, "balance")

spec:RegisterSetting("hurricane_targets", 4, {
    type = "range",
    name = "Hurricane Targets",
    desc = "Select the number of enemies at which the Balance priority channels Hurricane (0: never).",
    width = "full",
    min = 0,
    max = 10,
    step = 1,
}, "balance")

spec:RegisterSetting("innervate", true, {
    type = "toggle",
    name = "Innervate",
    desc = "When enabled, the Feral and Balance priorities use Innervate when mana runs low.",
    width = "full",
}, "feral", "balance")

-- Lacerate's refresh window and the Innervate mana fractions (class-completion D7: a fraction of the maximum per line).
spec:RegisterSetting("lacerate_refresh", 4.5, {
    type = "range",
    name = "Lacerate Refresh Window",
    desc = "Select the seconds left on a 5-stack Lacerate at which the Guardian priority refreshes it (wowsims uses 1.5; "
        .. "the default 4.5 allows for the debuff being modelled, not read).",
    width = "full",
    min = 0,
    max = 15,
    step = 0.5,
}, "guardian")

spec:RegisterSetting("feral_innervate_mana", 40, {
    type = "range",
    name = "Feral Innervate Mana",
    desc = "Select the mana percentage below which the Feral priority uses Innervate (wowsims: 1400 mana).",
    width = "full",
    min = 0,
    max = 100,
    step = 1,
}, "feral")

spec:RegisterSetting("balance_innervate_mana", 10, {
    type = "range",
    name = "Balance Innervate Mana",
    desc = "Select the mana percentage below which the Balance priority uses Innervate.",
    width = "full",
    min = 0,
    max = 100,
    step = 1,
}, "balance")

-- The three priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and
-- APLs/*.simc; edit those and run it, never these blocks (tests/Forever/druid_spec.lua checks they
-- match). Pick one with /hekili priority <name>. Guardian and Balance are provisional (their descriptions say why);
-- Restoration is deferred.
spec:RegisterPack(
    "Feral",
    20261019313,
    [[Hekili:fFvBVTTnq4Fl5lEnygQ25LU1I6cS2GILHTIIOTVkjAQt2eMMuGKkEgyq)23DKYksYwPEbByFjHH85EUx4ZDIjzEYVNeNZCqYxUA2vVz(S5V965xNe72xcjXLm(g2kCHITf)5Nbdts7UxQz5KLlRes39QKLNKeBjWtIV7H)4(7ExrW21I8CiGhS4HFwBGhbtDMN76S7mvI86SxXzUlNwNXKIvka3yNWTg)PENvS1(6IGvFNTo730kncUo7N(6VI2za0rGId1zALC)LVRolETHyqRQZ(KeygoZ6eQvi4pjz7WdQqR1f1zLARWj0kYXyGweq9v9ok(wcsnc(Mz1zGcmR2xNvPYPt6tktH(62zHigPg56JGXcMn4zRbwEWxS6S8kmiFGTbqipikX9W4WTg30c4kUE7snfucLZ2WlHgxA94WiOGjLeFfifQqDKlfLLyKmTHldyrYqo0TvIM8E3Aq1aYXmRiFwW4as(EDfvdwRL5(CYJ5qw3WAbs8AcSc8Cc)jAQnf83AuSEVcn4ruuqEhRsu2fC5wMctFtLcT2UwBCrOMYOlesuJX40vGnQ0aufG5wSLz2KQlsrhNUtiZNkkwGviQCBJwwvuyNCb9ROHaJQkBozfEzo4K6F5ip99lEnELzu2r9q44rTg1HPO0ClzFWGd701KfNhmKpBJimTK0Ge8WLqeVYGIC37Vz2F1qqhniL2dWH6Xo0wzHuHd2A7U5YGiDkDikOsxXZxm3hH5G3fgu75ROVYRmtdcZdU4dpvWmIYuoI7GDIs0Sl7NxOoCAHMxzd(4K5GhvQEtxl5OY9BA4fNYsmm6A4ljh6rh13g47QtuL6cfhiP5cDLnDjw17RTWnslekb2kzMC6y62j9cIjhA0(WaXWXfyYtnvIowfqf5pjIRTUJQVu6mUHeKJStCOzVBnPnnBpDYq1(eAwquj39(wW(puK2AskHyOEEX1ZMCAHFy3gXS)IijgNlAX4CWhNKcRZ6)6huWQKoC5x8FneuSLsip5JhggLeFiIXvg8kZiyjXh15M4qpmcb97K7sZXD0NBln5VRhXFTT4eOBgaQtloLYTg1u16LK)708trXTdIINCYZ293TgI7Ke7fyuCJC(M)zCEXXKsQ5(C(dJY5lj1FYt4F33r)4OoAqvVdh4gTKCfrYBhra0FOtxY)pz4dfkZNnQ43FX1jeoJPsEghTF0FR1PGDgJR8eoS)8eLL)hhw9uc2YyVBBh9oPMNB8CJRg(qOtF9)sF50ZnNl8aPVP)AFh1Znd7Ch66RlSkIZK4Fg2iKc89On)Jfx6po5V)d]]
)
spec:RegisterPack(
    "Guardian",
    20261019907,
    [[Hekili:TE1wVTjsu4Fl9LSBuSOXUnTnrHi1QOEtPrrLDFfyaoypkWmOzgsKRwXV99CamEmySCC8lXoNlFNBFNzg7p1)F89sygW)(zNp7dtpF6LxE(h99mllaFVcw8JS54xeSC8VFRKPs4mbPyzMKLqohvYZm)q4hTvC0fqSV3T)(F)XTxnVZ9f8KeOXfqJ6)QubpbQQWvrOk8wvjpPk8VJaMAsvyHs(exZLcw2vvHKWQqfMAvHCrSmh)KjqZtGy2s87kuqPihy6sfKCkcal1qb4z5ZAEU(TPnr8V0Ra7ZpChgnfKckqeJUlfzlpfJ1xaLgup2HWdkEoldLZnaI7TqUuXY4)HlMxf(BzD2EhlguyZOk0iRcVOn5qWvGEbKqjnQAbQxdgmP4Ie5Zt2eBkdQcJLYmuNav(lwzwlsEpZlaYpZceII6YL6go4Krjt5z4WIfBW2L2PqbydkIzCPcnal88j8u33evMM60jYPSO6NTUS3gEM7BvLIGM)liJRntiIIltcKNK8NGaqa5CqFJ7mBhJAARtk1qGmnnyECI7uYReOoGjw91af2wXaFYQUbwuuJkic7tokiNXfi(V3gFcxuBU2w4aqRlWDerBNZAhQtsLXLA3zwj7kvoAdUXCJ7fN0xrBsETloWnya0DQcAPf2HYQ8SfNYafhcs5kWoXTepwkJwhj16bPvD(E9f2(KJ0SHtLA2vCPcxom342yTdzQtSuBoRvG9yHK)FVzlkEuGtq7iQj2Cq9I(Gi11UskZlcQ34T8eeKKHzBNxKMgJoXg3RhjF3OzJg(hoKGZN5ifgBxOIodCqoU7HtNi331sq)vN313ZH07wfBJ60QADFUVMxZmFnQhiv4Kdko9lH9C3W3dp1NUhP39u0HxA66men8J7RVxeeSOmiX)lRonLUVQ3u13lwHLIIZ8921O33GrShOwDCkIDbPLwyd9acbH37gjj7ihKrVFeJSMdKzxmIzRB7KvFypRaA6zN(h0iEuQ0XMlrv2hhP(TiqBBuVj)YNGc5iPyan7Ig1DD6gyo4M2TrAgNtmBn(9UwUHFh08koIHVfYZlGm(kUIExmYnOTJXhFvlG9PVdkPJXf5RZ1vAqwe9KbAwUdMwVfYpDKiK3F5iaTo7wJYUEKaH10Z3twZHDaWlytVoBgB9Y6qRrZHHVSOgY99m6Mxvyd)H(OJ6Wo2r5B9vinhZ09W(JZbn1yYknlKyt77WJ8mo(dIA)LzNwR2))p]]
)
spec:RegisterPack(
    "Balance",
    20261019598,
    [[Hekili:LA17pTnmq0)w4lDuTQcLnyaAbPHyt0Pn00YM23CIBItRvDSJSDAvLMYF77U8d3KssrA8fO139EVZNVNDjZi)I4htTmYtxC(fxn78z3C5nxt8T7Yye)mA0A6s4dsAk837PcQmQC9DcfngXUiNlSZLKf9sJjJfr8F4N)E(d3UOb9kECmRcbZaH)IsZ2W0fH18xe(GoNhxeEAMwTHB4kjvCBrykvslc5MIqzv(AgnMUqaaOsi9phj4zg2BGeIwr1lH115yuesUmsjt46uw8yGRVRuY1CzriiE6KQVdrBOAU0WISfH(BP60IW1Sm4l5zqI(wQUkrL0jzJGgiH)OP2vfHwvrycxiGvEmxR5ruzngyBSdIJ5BraZLsMEd07aTbvSRGpyy2M9BIMgz5iWtPjwCBVvT1WtnNLu13W9RRZ9PF8TjyJjHPzLlOKIDJNchzAfuoq3VInZ0mnlsLUGA9sR6fbjyRGN4bIB5YLMP1bgDYI8KKPTtBAEwXxFgtV17SuQEDGkja2fbB5I4o8H0yAy7GebgRJSKNypis)AzxP0sZGkufUnApEtRUdi3QJWo(0Si7h3tyvJnWLtq5PsdJqvKBGOwwQP9IruHiO6RbcUXobnqEuvxHx1myeupnC35JqqBybmjlLZm3DKKBRxA947KevuUX7cuMtIzUZnmg2HpDHYy(RJtRMAwfeRSMXTzJxo9hyWH)(ySDCKvK024n1EKASZkXMcwz5YrLeWQSntHeJwFN3SEb3cKRGBcgGwlWl0c3w031c0(zgOT75Aq93y6KmqMRz3HqIpy3WRJo4wo8e2GxgcGH)9u5LQmjE1um5(glhXVrqIFKggz0CkXVNIHyb(hGcxH1HJQceWzX7utO5c7XQd3WCBsEf2HJvWo7bM07oiPEu)15j2R7HoWQtPGQhYWZjOCE)GLZWENEnp9Dexo7J9fqOlFrH6Zs1(aBF0UmF1WmFmd3EQBCuoANH0(Hbon3N9ZfAitkY31dWxPPDWrz3L9VKPQ5zPENOo6RyhB09WNO6L9)7306Zp0OC1txVOEUx4kBxqdJMJlr8FKTMl4WVyO(NwnUmm5F]]
)
