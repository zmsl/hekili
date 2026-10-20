-- Hekili_Shaman/Shaman.lua
-- The Forever Shaman (Enhancement, and Elemental and Restoration idle, one spec a talent tree: Hekili:NewClass): the
-- Shaman kit with Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build
-- 1.60.1.70338, wowdb), the totems on the sim side (C6: `RegisterTotems` with each one's element and duration; the
-- summon's `now` writes the slot's modelled expiry, which Families/Totems.lua answers in combat), Lightning Shield's
-- charges spent by hits on us (`consumedBy`), Maelstrom Weapon's stacks on Lightning Bolt, Clearcasting as a charged
-- cost modifier, the shocks' shared cooldown, Reverberation, Improved Fire Nova and Shamanistic Focus, the weapon
-- imbues (C4's main_hand_enchant), mana under the five-second rule (`fsr`), and the default priority, Enhancement
-- (wowsims.com), translated from wowsims/forever's APL (tools/wowsims/specs/shaman_enhancement.lua). Research: the
-- class-completion research §4.
-- Unmodelled: Stormstrike's debuff (no priority reads it), the totems' effects, Flametongue and Windfury Weapon's
-- procs, Windfury Totem (the party's: never prompted), Improved Lightning Shield's extra charges.
-- From wowsims/forever's spell data, absent from the Forever DB2 at 70338 (in-game checks): Call of Flame's +3 s a
-- rank on Flame Shock, Stormstrike's cost. Fire Nova's (375 there) is not modelled (FIRE_NOVA_COST says why).
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
            package = "Enhancement (wowsims.com)",
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
-- The DB2's. wowsims/forever's spell data says 65, 120, 210, 290, 375 (its log: 375): not modelled, because at 375 the
-- secret-mana belief's lower bound stays under the cost while the truth is over it (the solo gate falls to 0.72: a
-- core gap). IN-GAME CHECK: Fire Nova's cost.
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
-- combat.
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

-- The shocks' shared 6 s cooldown (DB2 category 19), Reverberation (16040, aura 107 misc 11: rank 1's -200 ms x the
-- rank) taking 1 s off at 5/5: each sets the other's; Flame Shock leaves its DoT.
local function shockCooldown()
    return 6 - 0.2 * talent.reverberation.rank
end

local function shockEffect(other, debuffKey)
    return function()
        setCooldown(other, 6 - 0.2 * talent.reverberation.rank)
        if debuffKey then
            applyDebuff("target", debuffKey, 12 + 3 * talent.call_of_flame.rank) -- the aura's duration, explicit for `now`
        end
    end
end

-- Shamanistic Focus (1223030, aura 108 misc 14: -45% on the shocks and Lightning Shield, mask 0x90100400).
local function focused(costs, ids)
    return function()
        return byRank(costs, ids) * (1 - 0.45 * talent.shamanistic_focus.rank)
    end
end

local function shock(other, ids, costs, debuffKey)
    return {
        id = ids[1],
        copy = rest(ids),
        cast = 0,
        cooldown = shockCooldown,
        gcd = "spell",

        spend = focused(costs, ids),
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
    -- Call of Flame: wowsims spell data, absent from DB2 (wowdb effects 16038 has none): +3 s a rank (its effect 2,
    -- 3000/6000/9000). IN-GAME CHECK: Flame Shock duration with Call of Flame: 21 s?
    flame_shock = {
        id = 8050,
        copy = rest(FLAME_SHOCK),
        duration = function()
            return 12 + 3 * talent.call_of_flame.rank
        end,
        tick_time = 3,
        max_stack = 1,
    },
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

        spend = focused(LIGHTNING_SHIELD_COST, LIGHTNING_SHIELD),
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

        -- wowsims spell data, absent from DB2 (wowdb spell 17364 costs 125 flat): 8% of base mana, 121 at level 60
        -- (its log). shortcut: 121 at every level; below 60 it is less. IN-GAME CHECK: Stormstrike's cost.
        spend = 121,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 17364 }),
    },

    earth_shock = shock("flame_shock", EARTH_SHOCK, EARTH_SHOCK_COST),
    flame_shock = shock("earth_shock", FLAME_SHOCK, FLAME_SHOCK_COST, "flame_shock"),

    -- Hits around the fire totem up (wowsims fire_totems.go): unusable without one; its 10 s cooldown is DB2 category 35,
    -- Improved Fire Nova (16086, aura 107 misc 11: rank 1's -2000 ms x the rank) taking 4 s off at 2/2.
    fire_nova = {
        id = 408341,
        copy = rest(FIRE_NOVA),
        cast = 0,
        cooldown = function()
            return 10 - 2 * talent.improved_fire_nova.rank
        end,
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

-- Talents: { talent tree (1 Elemental, 2 Enhancement, 3 Restoration: the dominant tree picks the spec), rank 1's spell,
-- max rank }: the DB2's 46 nodes (`wowdb talents SHAMAN`; the tree is the DB2's Talent.TabID), keys the snake_case
-- names (a nameless node talent_<spell>), then Shamanistic Focus at tree 0. Reverberation and Improved Fire Nova
-- shorten cooldowns; Shamanistic Focus cuts the shocks' and Lightning Shield's cost.
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
    -- Forever-only (wowsims/forever's tree; not in the DB2's Talent table at 70338: checkpoint)
    shamanistic_focus = { 0, 1223030, 1 },
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
-- it, never this block (tests/Forever/shaman_spec.lua checks it matches).
spec:RegisterPack(
    "Enhancement (wowsims.com)",
    20261020199,
    [[Hekili:vAvtVTnoq0Fl7PTb1qFe3yhhuxGSOTOTytqbuotzkrkjwtrkqs1GCr)23Hkowu0s2DVyqZzM3mZJ8nIOy0tOec2qrpED01RIJUokEZguI5LgkkPbNVhxcle4A43ViQWICAnvy629UNLpRz16GCz9vwxFHlXelCzTmU57cu2KiRBO5OKKVD)d3)4D0berjvmcH(AyuD(5s3DD7mv0UDh2lSqQO)MQ62rOf4wo4(9)8F72bB3TBmkTSqBbOd1v4ASi0PacXnCD4becG)e8lTuC1cixkSqZHwHaRL2CZ0D7WeIu83WI90x0bD7(m2GVBIA6Dp89NaqQmMg9DHHLmtvBMTnc9C9katOgjlxUzzej6drlJcaIvjlyCG9X5gMuOdAuui4mSzBPcNttLfPyMk1in06ffY8w92Rxao10Y5PGx329Jtc99Bdl4WzQrkkBPhI1jM1thJ2OOIstLnNuScwmBwxnncaNJt1nkMO80SEZXy2wJ)LuL27DJ0U1IwTTvlslZjBJxWk2Ang0KB(4TrhJdYaHwlfS8uvRGEMGwpkOmUusslAvV4U7z4xaQ(ncatbkAnMj0FC7imVezDeIEJZasbtrtfYFJpewFtK1wueKZH4YXAdqLbTnUbXzLvgHLI1vmkN4MY)QpyFp8aqdqpCcDsbBlQzBAPQg6C2E60vuMKBoPxQXuoeKSo9zkUrkc0gyYZNCUq82fwOEL57h1qeApgoM96Mxj)ElxKAF7(XNIJot9Bt7RgdCA4G9c5ZIUFGsaXSgm6n5JZ0gD)82xNXalFSF(lvGZ4uc6FqjoxyTgpi6rjNOhqj5kMHQyyRXJkbKbs6FiMUkLjHBDpCl9G7TWh0mwV(GNxdWnLozaLt1yOK(ZdBFa4EZfW1x8mG8m6VXWVAw4NsKna(XlphHl2c36zHBwD3aM(ghxP3EbIWtu6WdUI5XyUzMJwNl1w3IJoplnR8DQEZkGgtAX(IahwBsXTZXWW(J7SyFrWBr4mmO3p)B3NkdGrbx8Cp2)6)C9TtRn3aeapJ9Z(h(O5utjg(MP9EXFSwYNtCHzThP6(YGPMc4g7Q)NIoFYYfRBCN559wHEMb4gCRPsQqjFJUNXzWlS(6Hhq1Bg9F)]]
)

-- The hand-built Enhancement list, replaced by Enhancement (wowsims.com): a saved choice of it falls back to the default.
spec:RetirePacks({ "Enhancement" })
