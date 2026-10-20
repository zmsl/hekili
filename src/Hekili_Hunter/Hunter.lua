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
local IMMOLATION_TRAP = { 13795, 14302, 14303, 14304, 14305 }
local IMMOLATION_TRAP_COST = { 50, 90, 135, 190, 245 }

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

-- Resourcefulness (440529, a Forever-only Survival talent): the melee strikes and the traps cost 60% less (DB2
-- 440529 effect 0, -60% mana cost; wowsims's 2/2 SV build pays 26 for Mongoose Bite, 32 for Wing Clip, 98 for
-- Immolation Trap). Raptor Strike keeps its price, as in wowsims's log, although the DB2 mask names it too.
local function resourceful(price)
    local priced = type(price) == "function" -- decided here: the returned function runs in the state's environment
    return function()
        local c = priced and price() or price
        return talent.resourcefulness.enabled and c * 0.4 or c
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

-- The time to the next main-hand swing (Hekili_Warrior/Warrior.lua's, after Hekili's Classic profile): wowsims's Melee
-- Weave casts Multi-Shot only when it ends before the walk in to that swing.
spec:RegisterStateExpr("mainhand_remains", function()
    -- out of combat no swing runs (nextMH is 0): anchor it at this evaluation, or its phase free-runs with the clock
    local mh = (nextMH == 0 and combat == 0) and now or nextMH
    if now == query_time then
        local real = mh - now
        return real > 0 and real or 0
    end
    if query_time <= mh then
        return mh - query_time
    end
    if mainhand_speed <= 0 then
        return 0
    end -- no swing speed read yet
    return mainhand_speed - (query_time - mh) % mainhand_speed
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

        spend = resourceful(cost(MONGOOSE_BITE_COST, MONGOOSE_BITE)),
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

        spend = resourceful(0.0581),
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

        spend = resourceful(cost(WING_CLIP_COST, WING_CLIP)),
        spendType = "mana",

        startsCombat = true,
        known = knows(WING_CLIP),
    },

    -- wowsims's Melee Weave lays it in melee range (its burn on the target is the trap's triggered spell, unmodelled);
    -- the 30 s is its category cooldown (DB2 SpellCooldowns).
    immolation_trap = {
        id = 13795,
        copy = rest(IMMOLATION_TRAP),
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        spend = resourceful(cost(IMMOLATION_TRAP_COST, IMMOLATION_TRAP)),
        spendType = "mana",

        startsCombat = false,
        known = knows(IMMOLATION_TRAP),
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
    -- Forever-only (tree 0: not in the DB2's Talent table; wowsims's tree places it in Survival, 2 ranks)
    resourcefulness = { 0, 440529, 2 },
})

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and
-- run it, never this block (tests/Forever/hunter_spec.lua checks it matches). Provisional (each description says why).
spec:RegisterPack(
    "Beast Mastery (wowsims.com)",
    20261020913,
    [[Hekili:DwvxVTjmu0Fl7HPfwZ4R0pwJwEyvBtRvRvtJUxnyWxcEa2iBZIYl8BFxNKLc0K0P9cY475C89Jdgsa5rseJAaYdH(Hxg4h6FDWmsKzDdqIAOzL0L4cbTgFEdq1MUK7XNGADxYKvYvAET2ntw7yrVUsszwftB5vMBfK0dkUUbYirF9Np84N)X8uROX1B1KevWzmylrqN9cN58Uetb0LSBpVCPc(nO6syqoTTc59XV)TUeC7UKNjul3ZMiAVIwbULhRr7rBQ0E7i7IV4(lTu4mfpgfvORWsHHRL2JLR7sOmMu8gCrjSw72L8jQHo)aPZK7V9ruKcJPrp3ZBj3u0MARaVrqDqnXKKnB21Z8z(N7pZ3fBSkzoVcha0mdxk0UnkajNsnl2M7AS)PkNMlZA1lcNIHBARQIX4HHD39mwNTWJAlDtSmpgBGXf0vLdy5VN1cfTXivXAJIxctB1askpEzgBrWEqOGhmr45lEfdsBZZD7h3TTPp1APyPuIcNYnGLJHQwcg3vyBIlUOpuBwWavCjpR80i511sCEHVfJZUMtdEfxSmoRI)cW0GQbegSxG4puroaWOQKQYOciwxindkE0PX3SRvOjBd4(0UUzOH9SjbVDYKGG3DHZRVYXX5dlQPCrbvWIvGDPU7ose6F0i5rFSvX1g9MVY3ARXLpS5REqqtRag5gsuVPQn4oFgjAWSNyqLhrmtHJmfNsIoYC(jT6hGeTP5z1dfD2ir)lJb(I(N1WjKvIZpIe99lNwHloIcJ8rNwKlpIi79xNM(vVy3DSbRxL2pYW(77psw1ZrAHD9Xgd79I9ZO)BNkXEyr7Vl6q2XNUjcRGW)fl0yF5af87vYp7AVnPdMq0wtHuH)vck5vC8k7VS7g5nHj)5p]]
)
spec:RegisterPack(
    "Marksmanship (wowsims.com)",
    20261020913,
    [[Hekili:DwvtZnnmq0FlCGHyAWFL(bnd(amadTdTddUCv2RTKJf2wYJKmz6f)BNvjHuB3KadxYiRDFp92DFsHeqEGetbdJCFOF4Lb(H(xhSGeBESLrIBH8kyfUqan4V3bQkDdi0L82(0zRLR18gTBUSXXM7J1sGA5lRJxBUrqYoi16wwoj(l)4(h(03x2mGssCjNszBXX05N8ax2NAkz9P72ZRqQy)IP6tPScOR20N((V91(uC7(0j00X9SAq7v2jmmLhTv7bT1AVDqDXpC)PwkCMJhIcXvJvbfxlThkx3NcuQu8kCrf7rTBF6hbdS8aIz2D38assPX0Qx65TIBk7YS63BsQoiNOMPlwC9cFQ)5(l8DXEQswWRXopKB4sH2TvXqWzGjAR21j2g48czENokCogUTRUobJhg2F7ZqDwKhylDtISibBFjLW6QrO83JksbTgPkrBu8k28ondbvKSkNgfSpjKWdkeEr0lOSSUIc3HXD7AhcTrkwjLiXzCdZIXaQvmJ7ASnXfxmmvRkOmvsfpV60zYBAK48c)kbNDTNo51CXQK8A(Fjnnt1YegSxG5FOICuctQsqLdcwIUuAgv8OtJVzxlrZ2gW9PDDZbT5SzbVE2SGG3CHZlVYXX5DrnaxuccAIIzxQ7VLeJ(hncEY9SAU2O3C9ERTgxE)MR7mbKvZOKpqIhmvTb35ZiXJM9edY8eG5kCKP4aj(iZ5N4Ayas8MMNLpK0fti9pig5lgEwJNqwko)ium0VCAgU4immXhDAsU8iKS3FDA4x9x7UtnydQ0Hrg3FF7ru1ahPnTRp2yyVxCOI(VDQe7HfV)TOdzhF6LiScc)xSqt9LJyWFqj)SN92ihuqqNPuQW)qIvXR54t2FE3lYBct(9]]
)
spec:RegisterPack(
    "Survival (wowsims.com)",
    20261020957,
    [[Hekili:DwvxVnnpu4FlCbIM3vYxDDJvrU4fbi2emHiJBDItStJjo2r2oRA3KF7CCBxBswtbXnvN4Z55581JDrbOhqXeSHIUp0p8Qa)q)BwEnk28udff3GZRWRbdbUg(nUv9i7rmVlD2g5gnRw7MlRDSX9exIjwUYAzCZTcu2jPv3qZrXF5N3)WN(Xk9E6qXLmcHUddvNpzIw1LAkPDP7pZRqQOpsvDPeAbULB6s))V)1Uu44U0Eu0Y8S5v7v2kmuLhPr7HB4AV9WCHpC)LwkCMdjqHfAou5eWwAtit3LIjeP4nGrf9jTBx6hXg8QtuiZ(2TpaKuAmn6vEERzMY2mBT7nkuhGtOEjlwCZcFI)L(l8DH5OswW4WKgNBysH2TrrbWzyt0UAxNuJvvZlK5T6OW5G7Mwopb8hg2D3lqDrKh226Mezrcm6skXBQgGY)aQifUXivjAJIvrN3QPaOIK15KOG9jm4qWaXNSGyfrVIqZAlkC773TTPp0APyTucjiJzOpZTfRbRwtnUBGXgtSSpeBvrOQKkwE15JKvxlH9h8vcSlBoFWByI1j5C2Fimnv1qfgy2aX3Vjh4yuxIv5ybnrxkndAEqXX2EQLOz7C4E8u3CS2CXSG)B2SGG3U051x7448(OAmtuIfKef1AQ7Udfd6inaE0DmotB0BVwVtEdM3V9AovGZ4uc6dO4EBxRZ96nu8anakE7QXgGbYXikYvWYtXWO4j24hzTVJdKgAjDXKKoCzCKRbANHv4LJi7zi91oNjfadlNGHrAQZtYvtqYbT25HF9uDrFP2Pg)J1IwYE3eK1tBAd7Mjc7OQSFc)N1SiBYIp860PeMhFBcuiH)nsOX6Ybm43RLFXdHBlhOGWTMsPc(BjAfJZGhX)8(3O36g97p]]
)
spec:RegisterPack(
    "BeastMastery",
    20261020217,
    [[Hekili:9AvxVnUnqWFl9PMGMt3f3VaUwFa(a6H0IMGItPVkjAPLwerIuGKkgUpOF7DwszBzz72dOa9HyiXD3zND2Dzu29zpNLwj8u2tlE3IF4(3HFV)hZs976OS0or5lIn4bTOf)(rs48pI)i7o24UgJOIbyDVQX)R6S1xelxhvML(WF(0Z)YNF)AgJ829GuRQQOyGKdE9jJLELSdfHCnumMTHIh614H7gkEU3Ajy5bX2xgkUPZAEv5ugTO59dfAZqHs)MnGUdfL1ujCzh5)PHcxTX7gk2Q81MEe(ws8QsVba6RHV1anywORgpWlSBi)xJZQO19sjEO1urnne8qAnTdfMEWZsqq3Ti1R4YeaBKJiejyaXi5zWEuyXHRjjQteSPDTGz3ChmAejkhA7EMmIukz7inEl1d2JYOMGRkCqL10XvaE0RyfCbW9ZIofI6tkoBmOLgttLzRg28BHyL232YNhj7MEHTsj0aN(UO0aBRSLcnIpfsyefCUYYAQWYYXEqreRuT8jrxdm(X(gV6nhJTnu5XIc55gH0ZSDRzRt16ERmoaWsXPD6v)XVd8TKKSKUmuon7UnjMlx8vUN4DQkASfurIQ)YWC)Mv9EZEEPanSc9gIdFA1XzTvOHYlBmgWkLl0hCK3hhwms0ExVJHwkqLLG9aRrQAW6HO0J5qxsNLIn2LIWmrUrMd6KZZy3PKl)kEEk5CBj9Dd)2zG8nlFBDy6WHTgBeG4izY0ZNg8)H8opBstzVB5IVKSIqT84wUetB317iKdz(MYQL3p1NsrttE818gLZFhF3YYW6jNLOLebAx58HjkDEOxDuAc(U0fMCpuCDKpjumLgWVFEXm3rIfHgDauoaUpN0v6)WYXURlzIh5HXGZWWfx)YDHXHlioN4Wjn0d0G3qc54CBT8UYbgYwFLYjn1Qi3hGkMLIvd(YUz3WY6OJVioaeE4PW96KwSg3xL9X9ZMWHJQwwAPvHoPsGz4zQxMhz4kqmrLMcXxGEYO(TZq9iaxtcNq(PwYsdYpZta73DnYEqTzV((R41rDFkHMR)zmgPJl()tI85RyNuNxFn8sY(5c0SfWJ5DQHtLN5Q(KTtUmoGWXf4ljQNknxCl9iuZ3ZJtP5XVKioNg0Zdx09)MIEz56FxN9rcJIU2yXh0qVOAu4FTm(nl3gmN93p]]
)
spec:RegisterPack(
    "Marksmanship",
    20261020551,
    [[Hekili:9A13Vnnmq4)w4j2eDH1cJhaLjvKyAGGjGmEnjUjNBSAIDW2PvfHYF7CNDBtAw6ysiXlB(h39D39DFNBINgFFCuoZcX3n7YzVz6LZU8QRMghz3wdXr1SSvSL4cjRc)7xy6vMkM0uiQPl3wQy5ealAeL2pkJxmkwMAilo62FC39F47VT6imke55G3pWGgDJsdRbDBA)q1MEBJ0c6jTP33O1GTn9SATATWiusw5BBtLQ2uH8ILyw2MMvazRAt3c231MAkuwtB6gHTq1GoUbyRfYLiu2c0wltVeSphTihw0W54Ikvouwc5TPCTQQnv1GPtgZynNJrAovmiok(oeULTbdgtMVpljWOSVnDbWXYbDwvTGrjZqdus0tm7Hn7ZKDifb6AqI7ISyYIzDbGMkWdY1QA0FgU0kiIAgI73z1c0RBeu0iqZuQYC1gjE3CrfvlripGfDKuutErBBtBK50MJDhp4BncIbJ8CxxSMIimxNXKWbaDP7xAkTIl8ysHVYv2(kcb4mg3sUVrTXiQmVK7BYepSVFo)RFgbtdCqdYmxvuU98Gd5aTLAfwJih2X85al)xkkxoBEJvTVOeycOzYLa5E)SLIhQOqcNxQOYuyC0VbSwVKqXXU6ITe0CgwtbOixR4Isu7ZYSOAZeuRbF)mK5KcjkEcMojfOoyIGh(msgf8W7cAQB)0da5fHVSWjkmj0GHdaVsmO)59D(FiUdJgxL1ycN9uIk6QMKjjCuLmPXaym4jlZYdN23MmwzzIFBsPWyNqpCe6gcPO4VjGHTRe6WaHmX1R6OgNTHms16mzWnymm(HJeJRRnsnCKbhX7hGWng4WFhatjaCE3vMOR)2D0pP5bN1MrHJ5uzE4qyirwqDM96WDsltqplsCAWhGrfndDac621qciHkbyUg544iCKHEWBWJRelBO3GDaHlUZ9KoizlWhXIF)ELl()dCASfbzGvzAb24fS4OtrJDiD0nXrogKqeH9vNe2ri3Xy3ErPRjDigtPy86tvGDKC)a)eAheQxDcu7Am9bDydkMi1ODVB8ODHhmHEe3F6P4NwtBW8BxC7FXJ3Y6nCtLXbe66DJ1eoMAgDiVdQHpt4LXj(VYWlKD85H3j)VXOJtx)DE26tySOluA8JDGvIsb(lt7(GMZDxh)N)]]
)
spec:RegisterPack(
    "Survival",
    20261020438,
    [[Hekili:LAvxVTnoqWFl3txcox1y3IdhAovGMIwK(vWH4u03KiL0sBctrQssfx)c)TF7sQylN44uG8qIL5U7S7mCiLlMwCtX8gUhkUA2zZ(7PNn7Sx)Q)PyUFthumVJxVIVaFqZBX)pV3ER8wUIcSrz4nuXv9sL)t6IQdIJRdQlMF53V6MpC9BCBRFPSPbs1aomHpASWTGnWURfb2L9ApyNeyFduaeyN0zn3kDsJMREtGPnbMu)If4Gfy1lH6vb2gWFEGDnVZBiO8w5km4p7HEOjWm6aZVexqd)YhyU1s9ccEJEHX4W1Vq6H)0fyyGgZ6atynTdL074vsL0VjWSaVzYWYl5RxHfW1ndl452fGNaPLBXjQ10akf19eyMECWQ5oV7uKdVJuhCumIHYVaWqd4L4pb13IqvbcuKWQnTv8JXZ1lbDsmPrDZaC7tts7W)8JylhBSxsLnDYd7ojECs6wFhjhxXSZJeqNgMgAPViRxrY0AdTP22saCjkxb2IEUTrY13jC)a3hcS3RKD4cUbLqirzdH5eUWtFU2S2jBDVuKmkXbl5lE3)91jevfGf01anQQn488jSNkUxsn(glhbxbcsS79NMHlrDPnbHlQGUuPjPziILRxazJNX0ERg1cHYqYV0fvgh49jdLrGBNvionGG3R8z4XfRbjeEcIxtdKlRZcP9XCE0duAeLiVlRidWePi)pQ6fISdemRVl85haZFL)YLXDmxjz8Ii0armgV(4IZTr)tzI8t6Da2hr5I6M8PteM6Ex(0TjJ4)Cg07pEj4N97mMyP1CLQm91sLeBlDBuEChIqifjBp6Kj1LX9UDAvm)82HJbLv4PGhqZusylDjBC5k0fFGOr)CjD6NgGoWNrpNvBqs8VZEyb0vnL1O7HsNCpzD1(3Mp4zCzBJxgTwFUyo6XPR6U3TPe7D0LUrGXhUkE)nO5v4LmfxCNbdtymplMhjkLThr8rkzmNP8E1JL3o2xmV2I4BLC0JFpvGG41pceB57yaEsDbr0tVWiEQ6qKFKhMcUTD7zn(9eJdyOhpRhZ1FiTBuLh2VVRZJdSDwpOAUd0JEeyh03)GuYqvME5EYsfL4TxRCmh2ZuHEmHFF6)06MpnY8E)sJf)LgWk89047ng(ffNgdx8))]]
)
