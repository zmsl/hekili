-- Hekili_Shaman/Shaman.lua
-- The Forever Shaman (Enhancement, and Elemental and Restoration idle, one spec a talent tree: Hekili:NewClass): the
-- Shaman kit with Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build
-- 1.60.1.70338, wowdb), the totems on the sim side (C6: `RegisterTotems` with each one's element and duration; the
-- summon's `now` writes the slot's modelled expiry, which Families/Totems.lua answers in combat), Lightning Shield's
-- charges spent by hits on us (`consumedBy`), Maelstrom Weapon's stacks on Lightning Bolt, Clearcasting as a charged
-- cost modifier, the shocks' shared cooldown, the weapon imbue as a precombat reminder (C4's main_hand_enchant), mana
-- under the five-second rule (`fsr`), and the default priorities (all provisional: no in-game check yet, D5). Research:
-- the class-completion research §4.
-- Unmodelled: Stormstrike's debuff (no priority reads it), the totems' effects, Flametongue and Windfury Weapon's
-- procs, Windfury Totem (the party's: never prompted), Improved Lightning Shield's extra charges.
-- Credits: Hekili (registration API, pack format and `summonTotem`'s signature, State.lua). wowsims/forever (MIT,
-- ui/specs/shaman/enhancement/apls/default.apl.json and sim/shaman/) is the reference for the priorities and the totem,
-- Fire Nova, Maelstrom Weapon and Clearcasting rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase = Facade.UnitClassBase

if UnitClassBase("player") ~= "SHAMAN" then
    return
end

local state = Hekili.State
local max = math.max

-- The class kit and one spec a talent tree (ids the core's: Elemental 100071 and Restoration 100073, unsupported;
-- Enhancement 100072; the client's one pseudo-spec, 1489, only keys the legacy profile the core migrates). Icons: the
-- DB2 talent tabs'. Elemental gets its priority with the class-completion plan (it drops `unsupported`).
local spec = Hekili:NewClass("SHAMAN", {
    specs = {
        {
            key = "elemental",
            name = "Elemental",
            tree = 1,
            icon = 136048,
            role = "attack",
            ranged = true,
            unsupported = true,
        },
        {
            key = "enhancement",
            name = "Enhancement",
            tree = 2,
            icon = 136051,
            role = "attack",
            package = "Enhancement",
        },
        { key = "restoration", name = "Restoration", tree = 3, icon = 136052, role = "healer", unsupported = true },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's), and each rank's mana cost.
local LIGHTNING_BOLT = { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 }
local LIGHTNING_BOLT_COST = { 15, 30, 45, 60, 85, 110, 135, 160, 190, 220 }
local LIGHTNING_BOLT_CAST = { 1.5, 2, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5 }
local LIGHTNING_SHIELD = { 324, 325, 905, 945, 8134, 10431, 10432 }
local LIGHTNING_SHIELD_COST = { 45, 80, 125, 180, 240, 305, 370 }
local EARTH_SHOCK = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }
local EARTH_SHOCK_COST = { 30, 50, 85, 145, 240, 345, 450 }
local FLAME_SHOCK = { 8050, 8052, 8053, 10447, 10448, 29228 }
local FLAME_SHOCK_COST = { 55, 95, 160, 250, 345, 410 }
local FIRE_NOVA = { 408341, 408342, 408343, 408344, 408345 } -- Forever's spell (no totem): from the fire totem up
local FIRE_NOVA_COST = { 95, 170, 280, 395, 520 }
local ROCKBITER_WEAPON = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 }
local ROCKBITER_WEAPON_COST = { 15, 25, 50, 75, 100, 125, 150 }
local FLAMETONGUE_WEAPON = { 8024, 8027, 8030, 16339, 16341, 16342 }
local FLAMETONGUE_WEAPON_COST = { 30, 55, 80, 105, 130, 155 }
local WINDFURY_WEAPON = { 8232, 8235, 10486, 16362 }
local WINDFURY_WEAPON_COST = { 90, 115, 140, 165 }
local FROSTBRAND_WEAPON = { 8033, 8038, 10456, 16355, 16356 }
local FROSTBRAND_WEAPON_COST = { 60, 85, 110, 135, 160 }

-- The totems this file summons: element (the slot Hekili's `totem.<element>` reads), ranks, costs, and each rank's
-- duration in seconds (DB2). Windfury Totem is the party's (research §4): not registered, never prompted.
local TOTEMS = {
    searing_totem = {
        element = "fire",
        ids = { 3599, 6363, 6364, 6365, 10437, 10438 },
        cost = { 25, 45, 75, 110, 145, 170 },
        duration = { 30, 35, 40, 45, 50, 55 },
    },
    flametongue_totem = {
        element = "fire",
        ids = { 8227, 8249, 10526, 16387 },
        cost = { 90, 140, 200, 275 },
        duration = { 300, 300, 300, 300 },
    },
    strength_of_earth_totem = {
        element = "earth",
        ids = { 8075, 8160, 8161, 10442, 25361 },
        cost = { 25, 65, 125, 225, 275 },
        duration = { 300, 300, 300, 300, 300 },
    },
    grace_of_air_totem = {
        element = "air",
        ids = { 8835, 10627, 25359 },
        cost = { 155, 250, 310 },
        duration = { 300, 300, 300 },
    },
    mana_spring_totem = {
        element = "water",
        ids = { 5675, 10495, 10496, 10497 },
        cost = { 40, 60, 80, 100 },
        duration = { 300, 300, 300, 300 },
    },
}

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
    return values[knownRank(ids)] or values[1]
end

local function cost(costs, ids)
    return function()
        return byRank(costs, ids)
    end
end

-- A totem: its summon (the `now` and the `handler`, two closures so each gets its own environment) fills its element's
-- slot for the known rank's duration, with Hekili's summonTotem(name, element, duration).
local function summon(key)
    local t = TOTEMS[key]
    return function()
        summonTotem(key, t.element, byRank(t.duration, t.ids))
    end
end

local function totemAbility(key)
    local t = TOTEMS[key]
    return {
        id = t.ids[1],
        copy = rest(t.ids),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = cost(t.cost, t.ids),
        spendType = "mana",

        startsCombat = false,
        known = knows(t.ids),

        now = summon(key),
        handler = summon(key),
    }
end

-- A weapon imbue on the main hand: 60 minutes (DB2 tooltip), the shared main_hand_enchant pseudo-aura (C4), read out of
-- combat; the precombat reminder casts the one the `imbue` setting names.
local function imbue(ids, costs)
    return {
        id = ids[1],
        copy = rest(ids),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(costs, ids),
        spendType = "mana",

        startsCombat = false,
        known = knows(ids),

        now = function()
            applyBuff("main_hand_enchant", 3600)
        end,
        handler = function()
            applyBuff("main_hand_enchant", 3600)
        end,
    }
end

-- The shocks' shared 6 s cooldown (DB2 category 19): each sets the other's; Flame Shock leaves its DoT.
local function shockEffect(other, debuffKey)
    return function()
        setCooldown(other, 6)
        if debuffKey then
            applyDebuff("target", debuffKey)
        end
    end
end

local function shock(other, ids, costs, debuffKey)
    return {
        id = ids[1],
        copy = rest(ids),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = cost(costs, ids),
        spendType = "mana",

        startsCombat = true,
        known = knows(ids),

        now = shockEffect(other, debuffKey),
        handler = shockEffect(other, debuffKey),
    }
end

-- The five-second rule (C3): spirit and mp5 regen per second, the declared starting point the out-of-combat read and
-- the in-combat calibration replace. UNMEASURED: a level 60 Shaman's spirit regen and a little mp5 from gear.
spec:RegisterResource(Enum.PowerType.Mana, nil, nil, {
    fsr = { spirit = 17, mp5 = 2 },
})

-- The totems (C6): each one's element and duration with its ranks, for `totem.<key>`.
local registered = {}
for key, t in pairs(TOTEMS) do
    registered[key] = { id = t.ids[1], copy = rest(t.ids), element = t.element, duration = t.duration }
end
spec:RegisterTotems(registered)

spec:RegisterAuras({
    -- 3 charges (DB2 ProcCharges), each hit that lands on us spending one.
    lightning_shield = {
        id = 324,
        copy = rest(LIGHTNING_SHIELD),
        duration = 600,
        max_stack = 3,
        consumedBy = { WOUND = true, BLOCKED = true },
    },
    -- Maelstrom Weapon (408498, a rune: D4, inert until learned): our melee hits stack it to 5, Lightning Bolt spends it.
    maelstrom_weapon = { id = 408505, duration = 30, max_stack = 5 },
    -- Elemental Focus's Clearcasting (16246): the next elemental damage spell costs nothing (1 charge, 15 s).
    clearcasting = { id = 16246, duration = 15, max_stack = 1 },
    -- The target's DoT, modelled from our cast (target auras are unreadable in combat).
    flame_shock = { id = 8050, copy = rest(FLAME_SHOCK), duration = 12, tick_time = 3, max_stack = 1 },
})

-- Clearcasting (16246): aura 108 misc 14 (cost) -100% on the spells its class mask names (-1743781885 / 4096 against
-- SpellClassSet 11); the registered ones: Lightning Bolt, Earth Shock, Flame Shock, Fire Nova (rank 1 IDs, the others
-- through each ability's `copy`). Covered but unregistered: Chain Lightning, Frost Shock, the rune shocks.
spec:RegisterCostMod({
    aura = "clearcasting",
    pct = -1,
    charges = 1,
    spells = { 403, 8042, 8050, 408341 },
})

spec:RegisterAbilities({
    -- Maelstrom Weapon (408505 aura 108 base -20, two effects on Lightning Bolt's class mask): each stack takes 20% off
    -- its cast time and cost; five make it instant and free.
    lightning_bolt = {
        id = 403,
        copy = rest(LIGHTNING_BOLT),
        cast = function()
            return byRank(LIGHTNING_BOLT_CAST, LIGHTNING_BOLT) * max(0, 1 - 0.2 * buff.maelstrom_weapon.stack)
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(LIGHTNING_BOLT_COST, LIGHTNING_BOLT) * max(0, 1 - 0.2 * buff.maelstrom_weapon.stack)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(LIGHTNING_BOLT),

        now = function()
            removeBuff("maelstrom_weapon")
        end,
        handler = function()
            removeBuff("maelstrom_weapon")
        end,
    },

    lightning_shield = {
        id = 324,
        copy = rest(LIGHTNING_SHIELD),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(LIGHTNING_SHIELD_COST, LIGHTNING_SHIELD),
        spendType = "mana",

        startsCombat = false,
        known = knows(LIGHTNING_SHIELD),

        now = function()
            applyBuff("lightning_shield", nil, 3)
        end,
        handler = function()
            applyBuff("lightning_shield", nil, 3)
        end,
    },

    stormstrike = {
        id = 17364,
        cast = 0,
        cooldown = 8,
        gcd = "spell",

        spend = 125,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 17364 }),
    },

    earth_shock = shock("flame_shock", EARTH_SHOCK, EARTH_SHOCK_COST),
    flame_shock = shock("earth_shock", FLAME_SHOCK, FLAME_SHOCK_COST, "flame_shock"),

    -- Hits around the fire totem up (wowsims fire_totems.go): unusable without one; its 10 s cooldown is DB2 category 35.
    fire_nova = {
        id = 408341,
        copy = rest(FIRE_NOVA),
        cast = 0,
        cooldown = 10,
        gcd = "spell",

        spend = cost(FIRE_NOVA_COST, FIRE_NOVA),
        spendType = "mana",

        startsCombat = true,
        known = knows(FIRE_NOVA),
        -- its usability answer is a mana rung (the ladder) although it also needs a fire totem: the costliest spell, so
        -- without it the believed lower bound never reaches 520 (checkpoint: no totem answers not usable, not short)

        usable = function()
            return totem.fire.up, "requires a fire totem"
        end,
    },

    searing_totem = totemAbility("searing_totem"),
    flametongue_totem = totemAbility("flametongue_totem"),
    strength_of_earth_totem = totemAbility("strength_of_earth_totem"),
    grace_of_air_totem = totemAbility("grace_of_air_totem"),
    mana_spring_totem = totemAbility("mana_spring_totem"),

    rockbiter_weapon = imbue(ROCKBITER_WEAPON, ROCKBITER_WEAPON_COST),
    flametongue_weapon = imbue(FLAMETONGUE_WEAPON, FLAMETONGUE_WEAPON_COST),
    windfury_weapon = imbue(WINDFURY_WEAPON, WINDFURY_WEAPON_COST),
    frostbrand_weapon = imbue(FROSTBRAND_WEAPON, FROSTBRAND_WEAPON_COST),
})

-- The imbue the precombat reminder casts while the main hand has none (research §4: Rockbiter by default).
spec:RegisterSetting("imbue", 1, {
    type = "select",
    name = "Weapon Imbue",
    desc = "The weapon imbue recommended before combat while your main hand has none.",
    values = { "Rockbiter Weapon", "Flametongue Weapon", "Windfury Weapon", "Frostbrand Weapon" },
    width = "full",
}, "enhancement")

-- The mana lines' floors (D7: a percent of the maximum, one setting a line; wowsims: Fire Nova above 10%, the mana
-- potion below 80%, Demonic Rune below 70%). Off by default: mana is secret and `mana.pct` reads the belief's
-- low-biased lower bound (0 on a fresh boot, climbing with regen), so a floor line becomes usable only after a warm-up
-- and a "below" line errs early (Retribution's precedent); the usability answers still refuse at a real lack.
local function manaSetting(key, name, desc, ...)
    spec:RegisterSetting(key, 0, {
        type = "range",
        name = name,
        desc = desc,
        min = 0,
        max = 100,
        step = 1,
        width = "full",
    }, ...)
end
manaSetting(
    "fire_nova_mana",
    "Fire Nova Mana Floor",
    "Fire Nova as a filler only while your mana is at least this percent of its maximum. 0 turns the floor off.",
    "enhancement"
)
manaSetting(
    "potion_mana",
    "Mana Potion Below",
    "A Major Mana Potion while your mana is under this percent of its maximum. Mana is estimated low, so the line errs early (it can fire near full mana). 0 turns the line off.",
    "enhancement"
)
manaSetting(
    "rune_mana",
    "Demonic Rune Below",
    "A Demonic Rune while your mana is under this percent of its maximum. Mana is estimated low, so the line errs early (it can fire near full mana). 0 turns the line off.",
    "enhancement"
)

-- Talents: { talent tree (1 Elemental, 2 Enhancement, 3 Restoration: the dominant tree picks the spec), rank 1's spell,
-- max rank }: the DB2's 46 nodes (`wowdb talents SHAMAN`; the tree is the DB2's Talent.TabID), keys the snake_case
-- names (a nameless node talent_<spell>). No ability reads one yet.
spec:RegisterTalents({
    -- Elemental (tree 1)
    convection = { 1, 16039, 5 },
    concussion = { 1, 16035, 5 },
    earths_grasp = { 1, 16043, 2 },
    elemental_warding = { 1, 28996, 3 },
    call_of_flame = { 1, 16038, 3 },
    elemental_focus = { 1, 16164, 1 },
    reverberation = { 1, 16040, 5 },
    talent_16041 = { 1, 16041, 5 },
    improved_fire_nova = { 1, 16086, 2 },
    eye_of_the_storm = { 1, 29062, 3 },
    elemental_devastation = { 1, 30160, 3 },
    elemental_reach = { 1, 28999, 2 },
    elemental_fury = { 1, 16089, 1 },
    elemental_alacrity = { 1, 16578, 5 },
    talent_16166 = { 1, 16166, 1 },
    -- Enhancement (tree 2)
    ancestral_knowledge = { 2, 17485, 5 },
    shield_specialization = { 2, 16253, 5 },
    guardian_totems = { 2, 16258, 2 },
    thundering_strikes = { 2, 16255, 5 },
    improved_ghost_wolf = { 2, 16262, 2 },
    improved_lightning_shield = { 2, 16261, 3 },
    enhancing_totems = { 2, 16259, 2 },
    two_handed_axes_and_maces = { 2, 16269, 1 },
    anticipation = { 2, 16254, 5 },
    flurry = { 2, 16256, 5 },
    toughness = { 2, 16252, 5 },
    improved_weapon_totems = { 2, 29192, 2 },
    elemental_weapons = { 2, 16266, 3 },
    spirit_weapons = { 2, 16268, 1 },
    weapon_mastery = { 2, 29082, 5 },
    stormstrike = { 2, 17364, 1 },
    -- Restoration (tree 3)
    improved_healing_wave = { 3, 16182, 5 },
    tidal_focus = { 3, 16179, 5 },
    improved_reincarnation = { 3, 16184, 2 },
    ancestral_healing = { 3, 16176, 3 },
    totemic_focus = { 3, 16173, 5 },
    natures_guidance = { 3, 16180, 3 },
    healing_focus = { 3, 16181, 5 },
    totemic_mastery = { 3, 16189, 1 },
    natural_grace = { 3, 29187, 3 },
    restorative_totems = { 3, 16187, 5 },
    tidal_mastery = { 3, 16194, 5 },
    healing_way = { 3, 29206, 3 },
    natures_swiftness = { 3, 16188, 1 },
    purification = { 3, 16178, 5 },
    mana_tide_totem = { 3, 16190, 1 },
})

-- The priority, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and run
-- it, never this block (tests/Forever/shaman_spec.lua checks it matches). Provisional (its description says why).
spec:RegisterPack(
    "Enhancement",
    20261019322,
    [[Hekili:vE13ZXPnq4)w6lnjtDV47CCAJtVmJtBCt7K4PtjZK3aeG4q9ajgjHV5EH)27UIFdsy7xSbjTF7UFA)w2ZFR)389siAQ)97UC3B3E523D1UD(E6ZLuFVss8rYb4boPa(7N4zeEmTGY14ENZfKe0(OkwU(V4(rwHsvsJ998(8TF927VHogImwscTXmQcoZDcj9bQSoCKJQd9YifeED4llLIhykMGtYVPoKlQdz8F(aez1HXz04J1HNP63xhQZGv0cnTOouLl0QlQd)c7qMMZ4hq8y08KxOqRiYdu4bcpP1mvMi(O6f4dejfwnwiYteNa)dVxhwisO554gPsbGVOcc3yIspbLmg(UamQs9QBAx8eLuIlXkIQOJpTjuHZhrtfOpIffremr(tjjgExKwhElt2AINws5h0znR)jIeF8ugLBqdpgMZGBaePfL6ZD2rjst()TgMP3eivyOB7mZgB1D8wMaX7UCdZ7Hew32maGePOejd4rndVm3bzYDgpCV4bsdT875q0G0MXhg8g5ZpkY1niCDD4xj0CL2q2FVLbhWE77rcrilGtWosVONqAdRMiDKZFjjvJgEsCsXkuVoTPKdRgMu0D7)8famjnLcST5sGNF(vBa2djmOEeWQuOHIr4y)bTqWzX1H)BfFYn7ypNYG6gJJASonxiKTvvkQgzcK6fPWTAeCPLqtjv56nGstkaJb9hjgDOAtPK2uJSxczzedYOGMQRlyP77aBJPqB)2F8hIQst3uqy8aidtcGec(VEtvz9FVaYFA)RtXBwTGFOI6g2DpBypX4jPvYZUX8QNnMGiuPJK4rDI6BE2OM3vkgOmv)iOnymFhNqCaLUbI0actgye4gqmpTbw7jr(ZTd1Ponu12xaDkffblm3SQt7XQYavj2JyHLNGU6tc59fK)tidm20kdQuy(MgCioz)w0wCZnLX6FR)(O5KgR6rc8CsJ8jqcQNNcm45waIfcpvexP2VZnXVcRT02fShEzbxibCqE3EEtaBkuIh1GBMrlQUg7RhTkdJ5Mo5oJ05LjM0SVhP9qjcA5Uijk6A92kU2O0WabFy)1t4aSGnW8DZjXsc1GXOTNftn0Tzh7C6Ol)pmiQ73VTeW3d6FJtfmBSJCg8rzZ0nnnsHhV3mTdLtIGVG7)rFVrfB4MTny99wuD77flX2SmcU5k11(AimEIEzCD)6oOVIhH)QzWpy4KQ8b)SuA47zUPWqfa8npgGDL(dq6q2mf3RDIRnjYa493W9WTfH7TUdtxQMbmNV50i9xEmgOvsnIagRbNc2VodSboRxdIh7DRZoo1E2Yju9oLS2EP7uYQYCe9pS(0eB7C5tNfJuYMZnxay5IDz1Utjoaj(Zn6(uLnDCNdMpo0y)8mglYMiEc7mz4OvCYAdjztk35KzJkTIhwBKjBA7(0y(GtR4J1gGYMo3TM7PizTO0xRrMRUFwu12UcDHsNGFv9SJEGU7FAr2p8jNzJFzbNUXWmkcqtqQ0zcPV3NPhz5m4h30(dOFLzB)))d]]
)
