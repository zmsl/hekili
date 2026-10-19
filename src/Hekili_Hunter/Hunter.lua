-- Hekili_Hunter/Hunter.lua
-- The Forever Hunter (Beast Mastery, Marksmanship and Survival, one spec a talent tree: Hekili:NewClass; D3's Turret
-- Hawk, Turret and Melee): the Hunter kit with Forever's spell data (ranks, costs, cooldowns, cast times and durations
-- from the Forever DB2 at build 1.60.1.70338, wowdb), mana under the five-second rule (the Forever Hunter spends mana,
-- never focus), Auto Shot as the ranged clock's anchor (`rangedSwing`, C7; no priority reads it: shots without weaving,
-- D5), Summon Hawk's guardians (two at most, 18 s each: RegisterPets `cap`, C1), the shared cooldowns (Arcane Shot and
-- Summon Hawk; Aimed Shot and Multi-Shot), Raptor Strike on the next swing, Mongoose Bite's window from the plain
-- usability read, and the default priorities (all provisional: no in-game check yet, D5).
-- Research: docs/research/2026-10-15-forever-hunter/research.md and the class-completion research §5.
-- Unmodelled: ranged haste on the auto-shot clock (Rapid Fire, Quick Shots; their haste on Aimed, Multi and Sniper
-- Shot's casts is modelled), the pet and its abilities (D6), Aspect of the Viper and the other runes no priority names,
-- Improved Aimed Shot's +2 s cast, Sniper Shot's range buff, Expose Prey's own Mongoose Bite window (the usability read
-- covers it), percent-of-base-mana costs (priced as a fraction of the maximum: overstated, research Q4).
-- Credits: Hekili (registration API and pack format; the on-next-swing queue read follows the Warrior's Heroic Strike).
-- wowsims/forever (MIT, ui/specs/hunter/dps/apls/turret.apl.json, turret_hawk.apl.json, melee.apl.json and sim/hunter/)
-- is the reference for the priorities and the Summon Hawk, Sniper Shot, Raptor Strike and Mongoose Bite rules; no code
-- is copied.

local Facade = Hekili.Client
local UnitClassBase, GetTime = Facade.UnitClassBase, Facade.GetTime
local IsSpellUsable, IsCurrentSpell = Facade.C_Spell.IsSpellUsable, Facade.C_Spell.IsCurrentSpell

if UnitClassBase("player") ~= "HUNTER" then
    return
end

local state = Hekili.State

-- The class kit and one spec a talent tree (ids the core's: Beast Mastery 100031, Marksmanship 100032, Survival
-- 100033; the client's one pseudo-spec, 1484, only keys the legacy profile the core migrates). Icons: the DB2 tabs'.
local spec = Hekili:NewClass("HUNTER", {
    specs = {
        {
            key = "beast_mastery",
            name = "Beast Mastery",
            tree = 1,
            icon = 132164,
            role = "attack",
            ranged = true,
            package = "BeastMastery",
        },
        {
            key = "marksmanship",
            name = "Marksmanship",
            tree = 2,
            icon = 132222,
            role = "attack",
            ranged = true,
            package = "Marksmanship",
        },
        {
            key = "survival",
            name = "Survival",
            tree = 3,
            icon = 132215,
            role = "attack",
            ranged = true,
            package = "Survival",
        },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's; a Forever-only row where it adds a rank), and each rank's mana cost.
local ARCANE_SHOT = { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 }
local ARCANE_SHOT_COST = { 25, 35, 50, 80, 105, 135, 160, 190 }
local AIMED_SHOT = { 19434, 20900, 20901, 20902, 20903, 20904 }
local AIMED_SHOT_COST = { 75, 115, 160, 210, 260, 310 }
local SERPENT_STING = { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 }
local SERPENT_STING_COST = { 15, 30, 50, 80, 115, 150, 190, 230, 250 }
local HUNTERS_MARK = { 1130, 14323, 14324, 14325, 1213268 } -- 1213268: Forever's rank 4 row
local HUNTERS_MARK_COST = { 15, 30, 45, 60, 60 }
local SNIPER_SHOT = { 1310687, 1310785, 1310786 } -- Forever-only (D4)
local SUMMON_HAWK = { 1293241, 1293525, 1293526, 1293527 } -- Forever-only (D4)
local SUMMON_HAWK_COST = { 80, 105, 135, 190 }
local RAPTOR_STRIKE = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 }
local RAPTOR_STRIKE_COST = { 10, 25, 35, 45, 55, 70, 85, 100 }
local MONGOOSE_BITE = { 1495, 14269, 14270, 14271 }
local MONGOOSE_BITE_COST = { 30, 40, 50, 65 }
local WING_CLIP = { 2974, 1310180, 14267, 14268 } -- 1310180: Forever's level 12 row
local WING_CLIP_COST = { 40, 40, 60, 80 }
local ASPECT_OF_THE_HAWK = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 }
local ASPECT_OF_THE_HAWK_COST = { 20, 35, 50, 70, 90, 110, 120 }
local ASPECT_OF_THE_BEAST = { 13161, 1299445, 1299446, 1299447 } -- ranks 2-4 Forever-only (D4)
local ASPECT_OF_THE_BEAST_COST = { 50, 70, 90, 110 }

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

local function cost(costs, ids)
    return function()
        return costs[knownRank(ids)] or costs[1]
    end
end

-- A shot's cast time under Rapid Fire's +40% and Quick Shots' +30% ranged haste (DB2 3045 and 6150 aura 140), which
-- the engine's spell haste (stale in combat) does not see.
local function rangedCast(base)
    return function()
        return base / ((buff.rapid_fire.up and 1.4 or 1) * (buff.quick_shots.up and 1.3 or 1))
    end
end

-- One aspect at a time (wowsims aspects.go): each removes the other.
local function aspectEffect(key, other)
    return function()
        removeBuff(other)
        applyBuff(key)
    end
end

local function aspect(key, other, ids, costs)
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

        now = aspectEffect(key, other),
        handler = aspectEffect(key, other),
    }
end

-- Two abilities on one category cooldown (DB2: Arcane Shot and Summon Hawk category 1173, Aimed Shot and Multi-Shot
-- category 2; 6 s each): each sets the other's. `hawk`: the cast also summons a hawk for 18 s. (A new closure for
-- each of `now` and `handler`: each runs in its own environment.)
local function shares(other, hawk)
    return function()
        setCooldown(other, 6)
        if hawk then
            summonPet("hawk", 18)
        end
    end
end

-- A `now` or `handler` that applies `key`: debuff on the target (`debuff` true) or buff on us; or removes buff `key`.
local function applies(key, debuff)
    return function()
        if debuff then
            applyDebuff("target", key)
        else
            applyBuff(key)
        end
    end
end
local function removes(key)
    return function()
        removeBuff(key)
    end
end

-- The five-second rule (C3): spirit and mp5 regen per second, the declared starting point the out-of-combat read and
-- the in-combat calibration replace. UNMEASURED: a level 60 Hunter's spirit regen and a little mp5 from gear.
spec:RegisterResource(Enum.PowerType.Mana, nil, nil, {
    fsr = { spirit = 15, mp5 = 2 },
})

-- Summon Hawk's guardians (C1): 2 up at most (DB2 1293527 effect 3), 18 s each (1293248's duration); the oldest gives
-- way to a third.
-- shortcut: the APLs' pet.hawk.count is the belief's count at query_time; summons the simulation predicts are not
-- counted (the shared 6 s cooldown blocks a second summon in the lookahead), count them if a pack needs it.
spec:RegisterPets({
    hawk = { spell = "summon_hawk", duration = 18, cap = 2 },
})

spec:RegisterAuras({
    aspect_of_the_hawk = { id = 13165, copy = rest(ASPECT_OF_THE_HAWK), duration = 3600, max_stack = 1 },
    aspect_of_the_beast = { id = 13161, copy = rest(ASPECT_OF_THE_BEAST), duration = 3600, max_stack = 1 },
    rapid_fire = { id = 3045, duration = 15, max_stack = 1 },
    -- Aspect of the Hawk's proc (Deadly Aspects) on an Auto Shot: +30% ranged haste.
    quick_shots = { id = 6150, duration = 12, max_stack = 1 },
    -- Mongoose Bite's window after we dodge (Defensive State, 5 s), timed from the plain usability flip (reset_precast).
    defensive_state = { id = 5302, duration = 5, max_stack = 1 },
    -- Raptor Strike queued on the next main-hand swing (C_Spell.IsCurrentSpell, applied in reset_precast).
    raptor_strike = {
        duration = function()
            return state.mainhand_speed
        end,
        max_stack = 1,
    },
    -- The target's debuffs, modelled from our casts (target auras are unreadable in combat).
    serpent_sting = { id = 1978, copy = rest(SERPENT_STING), duration = 15, tick_time = 3, max_stack = 1 },
    hunters_mark = { id = 1130, copy = rest(HUNTERS_MARK), duration = 120, max_stack = 1 },
})

-- Mongoose Bite's window from the plain usability read (the player aura walk may be secret in combat; the Rogue's
-- Cutthroat precedent): usable, or short only of mana, is the window; its 5 s from the flip's time.
local biteAt, biteOpen = 0, false
local function biteUsable()
    local r = knownRank(MONGOOSE_BITE)
    if r == 0 then
        return false
    end
    local usable, noMana = IsSpellUsable(MONGOOSE_BITE[r])
    return usable == true or noMana == true
end
spec:RegisterEvent("SPELL_UPDATE_USABLE", function()
    local u = biteUsable()
    if u ~= biteOpen then
        biteOpen = u
        biteAt = u and GetTime() or 0
    end
end)

spec:RegisterHook("reset_precast", function()
    local r = knownRank(RAPTOR_STRIKE)
    if r > 0 and IsCurrentSpell(RAPTOR_STRIKE[r]) then
        applyBuff("raptor_strike")
    end
    if now == query_time and biteUsable() then
        if biteAt > 0 and now - biteAt < 5 then
            applyBuff("defensive_state", biteAt + 5 - now)
        else
            applyBuff("defensive_state")
        end
    end
end)

spec:RegisterAbilities({
    -- The ranged auto attack: its success is the ranged hand's shot (C7; whether Forever sends it per shot is a
    -- checkpoint). Never recommended.
    auto_shot = {
        id = 75,
        cast = 0,
        cooldown = 0,
        gcd = "off",
        rangedSwing = true,

        startsCombat = true,
        known = knows({ 75 }),
    },

    hunters_mark = {
        id = 1130,
        copy = rest(HUNTERS_MARK),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(HUNTERS_MARK_COST, HUNTERS_MARK),
        spendType = "mana",

        startsCombat = false,
        known = knows(HUNTERS_MARK),

        now = applies("hunters_mark", true),
        handler = applies("hunters_mark", true),
    },

    aspect_of_the_hawk = aspect(
        "aspect_of_the_hawk",
        "aspect_of_the_beast",
        ASPECT_OF_THE_HAWK,
        ASPECT_OF_THE_HAWK_COST
    ),
    aspect_of_the_beast = aspect(
        "aspect_of_the_beast",
        "aspect_of_the_hawk",
        ASPECT_OF_THE_BEAST,
        ASPECT_OF_THE_BEAST_COST
    ),

    rapid_fire = {
        id = 3045,
        cast = 0,
        cooldown = 300,
        gcd = "off",

        spend = 100,
        spendType = "mana",

        toggle = "cooldowns",
        startsCombat = false,
        known = knows({ 3045 }),

        now = applies("rapid_fire"),
        handler = applies("rapid_fire"),
    },

    serpent_sting = {
        id = 1978,
        copy = rest(SERPENT_STING),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(SERPENT_STING_COST, SERPENT_STING),
        spendType = "mana",

        startsCombat = true,
        known = knows(SERPENT_STING),

        now = applies("serpent_sting", true),
        handler = applies("serpent_sting", true),
    },

    arcane_shot = {
        id = 3044,
        copy = rest(ARCANE_SHOT),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = cost(ARCANE_SHOT_COST, ARCANE_SHOT),
        spendType = "mana",

        startsCombat = true,
        known = knows(ARCANE_SHOT),

        now = shares("summon_hawk"),
        handler = shares("summon_hawk"),
    },

    -- The dive, then a hawk for 18 s (wowsims summon_hawk.go).
    summon_hawk = {
        id = 1293241,
        copy = rest(SUMMON_HAWK),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = cost(SUMMON_HAWK_COST, SUMMON_HAWK),
        spendType = "mana",

        startsCombat = true,
        known = knows(SUMMON_HAWK),

        now = shares("arcane_shot", true),
        handler = shares("arcane_shot", true),
    },

    aimed_shot = {
        id = 19434,
        copy = rest(AIMED_SHOT),
        cast = rangedCast(2),
        cooldown = 6,
        gcd = "spell",

        spend = cost(AIMED_SHOT_COST, AIMED_SHOT),
        spendType = "mana",

        startsCombat = true,
        known = knows(AIMED_SHOT),

        now = shares("multi_shot"),
        handler = shares("multi_shot"),
    },

    -- 13.9% of base mana (DB2 PowerCostPct), priced as a fraction of the maximum (overstated: research Q4).
    multi_shot = {
        id = 2643,
        cast = rangedCast(0.5),
        cooldown = 6,
        gcd = "spell",

        spend = 0.139,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 2643 }),

        now = shares("aimed_shot"),
        handler = shares("aimed_shot"),
    },

    sniper_shot = {
        id = 1310687,
        copy = rest(SNIPER_SHOT),
        cast = rangedCast(4),
        cooldown = 15,
        gcd = "spell",

        spend = 365,
        spendType = "mana",

        startsCombat = true,
        known = knows(SNIPER_SHOT),
    },

    -- On the next main-hand swing (wowsims raptor_strike.go), paid there; its 6 s category cooldown.
    raptor_strike = {
        id = 2973,
        copy = rest(RAPTOR_STRIKE),
        cast = 0,
        cooldown = 6,
        gcd = "off",

        spend = cost(RAPTOR_STRIKE_COST, RAPTOR_STRIKE),
        spendType = "mana",

        startsCombat = true,
        onNextSwing = true,
        known = knows(RAPTOR_STRIKE),

        usable = function()
            return not buff.raptor_strike.up, "a strike is already queued"
        end,

        handler = function()
            applyBuff("raptor_strike")
        end,
    },

    mongoose_bite = {
        id = 1495,
        copy = rest(MONGOOSE_BITE),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = cost(MONGOOSE_BITE_COST, MONGOOSE_BITE),
        spendType = "mana",

        startsCombat = true,
        known = knows(MONGOOSE_BITE),

        usable = function()
            return buff.defensive_state.up, "only usable after dodging"
        end,

        now = removes("defensive_state"),
        handler = removes("defensive_state"),
    },

    -- Forever-only (D4): 5.81% of base mana (DB2 PowerCostPct), priced as a fraction of the maximum (research Q4).
    strider_kick = {
        id = 1317257,
        cast = 0,
        cooldown = 8,
        gcd = "spell",

        spend = 0.0581,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 1317257 }),
    },

    wing_clip = {
        id = 2974,
        copy = rest(WING_CLIP),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(WING_CLIP_COST, WING_CLIP),
        spendType = "mana",

        startsCombat = true,
        known = knows(WING_CLIP),
    },
})

-- The filler lines' mana floors (D7: a percent of the maximum, one setting a line). Off by default: mana is secret and
-- `mana.pct` reads the belief's low-biased lower bound, which reaches the maximum only after an out-of-combat rest
-- (about 5-6 minutes), so a floor is honest after that rest (Retribution's and Enhancement's precedent).
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
    "arcane_shot_mana",
    "Arcane Shot Mana Floor",
    "Arcane Shot only while your mana is at least this percent of its maximum. Mana is estimated low until you rest out of combat. 0 turns the floor off.",
    "beast_mastery",
    "marksmanship"
)
manaSetting(
    "wing_clip_mana",
    "Wing Clip Mana Floor",
    "Wing Clip as a filler only while your mana is at least this percent of its maximum. Mana is estimated low until you rest out of combat. 0 turns the floor off.",
    "survival"
)

-- Talents: { talent tree (1 Beast Mastery, 2 Marksmanship, 3 Survival: the dominant tree picks the spec), rank 1's
-- spell, max rank }: the DB2's 46 nodes (`wowdb talents HUNTER`; the tree is the DB2's Talent.TabID), keys the
-- snake_case names (a nameless node talent_<spell>). No ability reads one yet.
spec:RegisterTalents({
    -- Beast Mastery (tree 1)
    deadly_aspects = { 1, 19552, 5 },
    endurance_training = { 1, 19583, 5 },
    improved_eyes_of_the_beast = { 1, 19557, 2 },
    improved_aspect_of_the_monkey = { 1, 19549, 5 },
    thick_hide = { 1, 19609, 3 },
    improved_revive_pet = { 1, 24443, 2 },
    pathfinding = { 1, 19559, 2 },
    bestial_swiftness = { 1, 19596, 1 },
    unleashed_fury = { 1, 19616, 5 },
    improved_mend_pet = { 1, 19572, 2 },
    ferocity = { 1, 19598, 5 },
    spirit_bond = { 1, 19578, 2 },
    intimidation = { 1, 19577, 1 },
    bestial_discipline = { 1, 19590, 2 },
    frenzy = { 1, 19621, 5 },
    bestial_wrath = { 1, 19574, 1 },
    -- Marksmanship (tree 2)
    improved_concussive_shot = { 2, 19407, 5 },
    efficiency = { 2, 19416, 5 },
    improved_hunters_mark = { 2, 19421, 5 },
    lethal_attacks = { 2, 19426, 5 },
    aimed_shot = { 2, 19434, 1 },
    improved_arcane_shot = { 2, 19454, 5 },
    hawk_eye = { 2, 19498, 3 },
    improved_serpent_sting = { 2, 19464, 5 },
    mortal_shots = { 2, 19485, 5 },
    scatter_shot = { 2, 19503, 1 },
    barrage = { 2, 19461, 3 },
    talent_19491 = { 2, 19491, 3 },
    ranged_weapon_specialization = { 2, 19507, 5 },
    trueshot_aura = { 2, 19506, 1 },
    -- Survival (tree 3)
    improved_tracking = { 3, 24293, 3 },
    humanoid_slaying = { 3, 19151, 3 },
    deflection = { 3, 19295, 5 },
    entrapment = { 3, 19184, 5 },
    savage_strikes = { 3, 19159, 2 },
    improved_wing_clip = { 3, 19228, 5 },
    clever_traps = { 3, 19239, 2 },
    survivalist = { 3, 19255, 5 },
    deterrence = { 3, 19263, 1 },
    survival_tactics = { 3, 19376, 2 },
    surefooted = { 3, 19290, 3 },
    improved_feign_death = { 3, 19286, 2 },
    killer_instinct = { 3, 19370, 3 },
    counterattack = { 3, 19306, 1 },
    lightning_reflexes = { 3, 19168, 5 },
    talent_19386 = { 3, 19386, 1 },
})

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and
-- run it, never this block (tests/Forever/hunter_spec.lua checks it matches). Provisional (each description says why).
spec:RegisterPack(
    "BeastMastery",
    20261019217,
    [[Hekili:9AvxVnUnqWFl9PMGMt3z3VqVwFa(a6H0IlbfrPVkjAPLwerIuGKkgUpOF7Dws)HSSD7buG(qcK4U7SZo7U0kBw2ZzPvcpL9483n)hM9Uz)08z)ywQFBhLL2jkFrSgpOfT4)FKeo)d4pYULnUTXiQyaw1RA8)MoB1fXY1rLzP3)Np(8V(07xXyK3UhKAvvffdKCWRpzS0RKDOiKRHIDzBO4(EnE4UHIN7TwcwUxS5LHIB6SMxvoLrlAE)qH2muO0VznO7qrznvcx2s(FEOWvB8UHInkFTPhHVHeVQ0RbG(A4BnqdMf6QDh4f21K)RXzv0QEPep0AQOMgcEiTM2Hctp4zjiO7wK6LCzcGnYDiejyaXi5zWEqyXHRijQteSPDLGz3uhmAejkhAZEMSdPuY2rA8wQhShLrnbxv4GkRPJRa8OxXk4CG7tIofI6tkoBmOLgttLzJg28BGyL232YNhj76EHTsj0aN(UO0aBlTLcnIpfsyefCUYYAQWYYXEqrelvT8jrxdm(H(gV6nhJTnu5XIc55gH0ZSDJzJt16ERmoaWsXPD6L)XNb(wsswsxgkNMT3MeZLl(k3t8ovfTRfurIQ)YWC)ML9EZEEPanSc9AIdFC1XzTvOHYlBmgWkLl0hCK3hhwms0ExTLHwkqLLG9aRrQAW6HO0J5qxsNLIn2fIWmrUrMd6KZZy3PKl(kEEk5CBj9Dd)(zG8nlEBDy6WHTgBeG4izY4Zhh8)H8onBstzVBX8VKSIqT84wUetB317iKdz(6YQfZg7tPOPjp(AEJY5VJVBzry9KZs0sIaTRC(WeLop0RoknbFx4ctUhkUoYNekMsd43VmFI7iXIqJoakha3Nt6k9FyXUURlzKh5HXGZWWfx)YDHXHlioN4Wjn0d0G3qc54CBT8UYbgYwFLYjn1Qi3hGkMLIvd(YUj3WY6OJVioaeE4XW96KwSc3xL9X9ZMWHJQwwAPvHoPsGz4jQxMhz4kqmsLgdXxGEYO(Ttq9iaxtchr(XwYsdYpZta73DnYEqTzV((R41rDFmHMQ)zmgP7w8)Ne5ZxXoPoV(A4LK9ZfOjlGhZ7ydNkptv9rBNCzCaHJlWxsupvAU4w6rOMUNhNsZJFjrConONhUO7)nf9YY1)Uo7JegfDTXIpOHEr1OWpTS7BwUnyo7V)d]]
)
spec:RegisterPack(
    "Marksmanship",
    20261019551,
    [[Hekili:9AvxVTPsq0Fl9PMO6qcPnv6MkIKRuJsRAIUnK(kWAywZkd7s3DjwUQIF7DMfBaJXTr6kDFjz)yMZmZzoZAI8JEkkmJzHOhU8IlFV)f()Zvx5hfA3ubrHvS0vSL4cjRe)79m9ktjtAYfv0LBkuSmcGf1Ic7NLrlMeltfKgfE33F4Pp941L7HrUildA9dmOr3Q0WZGUjzyOAsURwAb9SMKNQ1AW2KCsLw9SWiuswX1njsvtIqE2smlBssZH0vnjBa7hAsm5kRPjzTWMRQrhxdSNfYLiu2C0wltVeSVgTidwuZ54IsvguuaznjCTQSjrvJPtkZynNIrAovmiok(weUJTgdgtMTlljWOSVjzbWXYbDwvUGrjZydus0tm7H17YKTifc6kqI7cTyYIzDoGMkWdY0Qk0FgU0kiI6se3hzvc0RBfu0iqtvQIm1AjE3CrjvlHipGfDOuurErBBsQLz0M9Dhp4B1cIbdB5U(y5JimxNYKqhGU09(6cR4SwmPWx6k72kcb4eg3sUVwT2iknNZBBYepSRFo)F)kcMg4GgKPUQOyZPED5aTLAfwJid2Y8zal7NkkxozETvTROeycOzYLa5(WSLIhQOqcNxOOYuyC0VbS2wjHIJD1fBiO5mSM8qrUwXffO2NLAr1MXRsdT9ZaMtkeR4Xy6eNJ6GzcEWRizK3H35vx18Lda5nbNN7efMyAWWbqRs0B45dD()qChhnUkT2eC5ljQORAsMeZrvYSAdGXGhVmnlWFOnPSII42TXfcJDg9WrGBiKIs7nEmSDfth6jKXUEvp14SnGrQwNjJUbJHPD4i246Atud7zWE8EheUXah(BbWNaW5DFzIU(l3r)GMhCwBMeoMtL1chcdjY8QsT3eSvAz8gyrStdEagL0muhe0TpdXGekfG5gKJJcXrg6bVrpUsSSHEd2beU4b3t6GKTaFel6J7uU4)740ilcYiRs1cSXlyrHhJg7rAVBIcDmiHic7BpkStqUtXUdIsFtQlg(umE3XkWEsEyGFbTdc1RocQ9nMHGoUbfrKA423n(JDHdMq3J7p(u8lRPnA(TpUdV4p3YgmCtLrhc99UPAc7tntoK3d14NjALXXTFLrRq2XNDVt()gJonD935zBBcJfDUsJFSdSsuiWFzA7h0CQ76OFp]]
)
spec:RegisterPack(
    "Survival",
    20261019438,
    [[Hekili:LAvxVnUnqWFl9PEb1vxSZHI7JQcCPOhY9rcoCkf9njsjTuMWuKQKuX1VWF7DxsfBLeNChqEiXYC3D2DgoKYLllVUSOL7HYRwD6QFB5PlFZRo71Lf(DdqzXaVzdVdFqZ7X)xmAVrEdxrb2Pm8wQ46rPY)rDz9rXXnanLfx83xD9F9T362x)AzBlKQbCycFWyHBaBGDBlcSlg1EWUiWUeuaeyVyWAUr6Kgnx92atBcmP(x7WblWAwdnBcSDG)Db234dEdbL3k3Gb)3ryeAdmJoW8RXf0W)5dm3wPUJG3O7mghU(5sp8ZUadd0A2gycRPFQKrhVwQK(DbMf4TlMwEnF7gSaUUDAbp32bEcKEUfNOEtlOuu3tGzgXbRH78Utqo8EsDWrXiMk)CadnHxI)euxgHQgeOiHvB6R5pfp3Ug0jXKg1DtWDxAsAh(NFgB5yJ9sQSLlEy3jXJts32Bj58kw9Uib0PHPLw6ZYMnKmT1qBQ99eaxGYvG1nYTTsU(wH7FW9Ha7pvYbCb3KsiKOSHW8cUWtFU1S1j7DVuKmkXbl5lE)x)YcIQcWc6gGgv1oCE(i2tf3lPgFTLJGRabj2J(tYWLOU0NGWfvqxQ0K0mfXY1Dq28zmT3QrTqOmK8lDrLXbEFYqze42znItli4JkFgECXAqcHNG4n0a5YgSqAFmNh9avgrfY7QAYaSqkY)P6rHi7ibZghcF6bW8l5VCDChZvrgVicTqeJ5RpV4CB0)uLi)IrhG9ru110MVCHW0m6YxUpze)NZGE)Xlb)QFKXelTHRuvPVwPKyBPBJYJ7qecPiz3HozsDvCV7GwfZpVF6yqvnEk4b0mLe2sxYgxTbDXhjA0pxrN(Pbya8z0ZzngKe)(QhwaDvtvd6EO0j3t2qJ)pYN8mUS9XRIwRpvwGEC6QU7DBkXEhDPBey8HRI3FdAEnEjt553AWWeMZZYIirPS9iIpsjZ5mL3zpwEhyFzrJfX3k5Oh)EQabXREei2Z35a8D1ferp9cJ4PQJr(zEyk4(2DhRXpMyCed98z9PC9ht7Mv5X97h688a7N1JQMha9jpcCa67FqkzOQsVCpzPIs8(RvEkh2ZuHEmH)U0)7RB(0iZh9Rnw8xAaBW3tJV3y6xuCsmC5))d]]
)
