-- Hekili_Mage/Mage.lua
-- The Forever Mage (Arcane and Fire, and an idle Frost, one spec a talent tree: Hekili:NewClass): the Mage kit with
-- Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build 1.60.1.70338,
-- wowdb), mana under the five-second rule (`fsr`), the casts and the two channels (Arcane Missiles and Evocation:
-- `channeled`, `tick_time`), Arcane Blast's charges (each +175% to its own cost, a fraction of base mana), Missile
-- Barrage (Arcane Missiles free, in half the time), Heating Up's cheaper Pyroblast casts, Fingers of Frost's charges
-- spent by each damage cast, Frost Channeling's cheaper Frost casts, Fire Vulnerability's stacks from Scorch,
-- Evocation's mana, Presence of Mind, Arcane Power's +30% cost, Clearcasting as a charged cost modifier, Counterspell,
-- and the school lockouts (each spell refuses while an interrupt has its school locked out: Hekili_Shared's
-- locked_out_<school>). The priorities are the wowsims.com packs (Arcane, Fire, and Frostfire as Fire's second by its
-- talents' points; the abilities and auras below are what wowsims/forever's arcane.apl.json, deepFire.apl.json and
-- ffb.apl.json cast or read).
-- Research: docs/research/2026-10-15-forever-mage/research.md.
-- From wowsims/forever's spell data, absent from the Forever DB2 at 70338 (ruling P6; in-game checks): Arcane Wrath
-- (1326079-1326082: ranks, levels, costs, 3.5 s cast, 6 s cooldown and its class mask), the talents' per-rank values
-- where the DB2 holds only the top rank's row (Improved Fireball, Improved Frostbolt, Wake of Fire, Improved Scorch).
-- The DB2 and wowsims's data disagree on Arcane Blast (DB2 2.5 s cast and 8 s charges; wowsims 1.5 s and 15 s from the
-- first charge, never refreshed). Ruling M9 (wowsims packs Task 12): wowsims's, which its exported log casts (1.5 s
-- unhasted; each charge run 15 s from the first) and whose data is the newer build (1.60.1.70450, hotfix 112887, against
-- the DB2's 70338); the in-game cast bar is the check.
-- Unmodelled: the procs' rolls (Missile Barrage, Heating Up, Clearcasting, Fingers of Frost: crits and procs are
-- unseen; the player aura walk reads them where plain), Combustion's crits, the DoTs and chills on the target (no
-- priority reads them), Master of Elements' refunds, pushback.
-- Credits: Hekili (registration API and pack format). wowsims/forever (MIT, ui/specs/mage/dps/apls/*.apl.json and
-- sim/mage/) is the reference for the abilities and the charge, proc, Evocation and gem rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase = Facade.UnitClassBase
local L = Hekili.L

if UnitClassBase("player") ~= "MAGE" then
    return
end

local state = Hekili.State
local floor = math.floor

-- The class kit and one spec a talent tree (ids the core's: Arcane 100081, Fire 100082, Frost 100083, unsupported:
-- wowsims/forever has no Frost APL; the client's one pseudo-spec, assumed 1485, only keys the legacy profile the core
-- migrates). Icons: the DB2 talent tabs'. Each package is the spec's wowsims.com pack.
local spec = Hekili:NewClass("MAGE", {
    specs = {
        {
            key = "arcane",
            name = L["Arcane"],
            tree = 1,
            icon = 135932,
            role = "attack",
            ranged = true,
            package = "Arcane (wowsims.com)",
        },
        {
            key = "fire",
            name = L["Fire"],
            tree = 2,
            icon = 135810,
            role = "attack",
            ranged = true,
            package = "Fire (wowsims.com)",
        },
        {
            key = "frost",
            name = L["Frost"],
            tree = 3,
            icon = 135846,
            role = "attack",
            ranged = true,
            unsupported = true,
        },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's; Arcane Wrath wowsims's), each rank's mana cost, cast or channel time.
local ARCANE_BLAST = { 400574, 1239696, 1239697, 1239699, 1239700 } -- 15% of base mana a rank (PowerCostPct)
local ARCANE_MISSILES = { 5143, 5144, 5145, 8416, 8417, 10211, 10212, 25345 }
local ARCANE_MISSILES_COST = { 85, 140, 235, 320, 410, 500, 595, 655 }
local ARCANE_MISSILES_TIME = { 3, 4, 5, 5, 5, 5, 5, 5 }
local ARCANE_WRATH = { 1326079, 1326080, 1326081, 1326082 } -- Forever-only, wowsims's (levels 25, 36, 48, 60)
local ARCANE_WRATH_COST = { 140, 220, 305, 395 }
local FROSTBOLT = { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304 }
local FROSTBOLT_COST = { 25, 35, 50, 65, 100, 130, 160, 195, 225, 260, 290 }
local FROSTBOLT_CAST = { 1.5, 1.8, 2.2, 2.6, 3, 3, 3, 3, 3, 3, 3 }
local FIREBALL = { 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306 }
local FIREBALL_COST = { 30, 45, 65, 95, 140, 185, 220, 260, 305, 350, 395, 410 }
local FIREBALL_CAST = { 1.5, 2, 2.5, 3, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5 }
local SCORCH = { 2948, 8444, 8445, 8446, 10205, 10206, 10207 }
local SCORCH_COST = { 50, 65, 80, 100, 115, 135, 150 }
local PYROBLAST = { 11366, 12505, 12522, 12523, 12524, 12525, 12526, 18809 }
local PYROBLAST_COST = { 125, 150, 195, 240, 285, 335, 385, 440 }
-- The trainer's family (8 s, on the GCD); the DB2's level-0 rune family (400616, 400618-400623: 15 s, off it) is no
-- Forever spell a Mage learns (research §0) and is not registered.
local FIRE_BLAST = { 2136, 2137, 2138, 8412, 8413, 10197, 10199 }
local FIRE_BLAST_COST = { 40, 75, 115, 165, 220, 280, 340 }
local FROSTFIRE_BOLT = { 401502, 1237312, 1237313 }
local FROSTFIRE_BOLT_COST = { 205, 285, 370 }

-- The talents' per-rank values (wowsims's data; the DB2 carries the top rank's on rank 1): Improved Fireball and
-- Improved Frostbolt -0.1 s cast a rank; Wake of Fire (11078, wowsims's Improved Fire Blast) -1 / -2 s Fire Blast
-- cooldown (the DB2's third rank, if Forever has one, as the second); Improved Scorch's Fire Vulnerability chance
-- 33 / 67 / 100%.
local WAKE_OF_FIRE = { 1, 2 }

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

-- The value of the highest known rank (the first rank's before any is known).
local function byRank(values, ids)
    return function()
        return values[knownRank(ids)] or values[1]
    end
end

-- The same, less Frost Channeling's -5% a rank (DB2 11160 effect 0, aura 108 misc 14 -15% at the top rank; its mask
-- names Frostbolt and Frostfire Bolt; wowsims's FFB log: 314.5 = 370 x 0.85 at 3/3).
local function frostChanneled(values, ids)
    return function()
        return (values[knownRank(ids)] or values[1]) * (1 - 0.05 * talent.frost_channeling.rank)
    end
end

-- Each spell refuses while an interrupt has its school locked out (Hekili_Shared's locked_out_<school>, C10). A new
-- closure per ability: each field function runs in the environment the engine gives it (in the belief's `now` context
-- the names are absent: never locked).
local function unlocked(school)
    if school == "arcane" then
        return function()
            return not locked_out_arcane, "arcane locked out"
        end
    elseif school == "fire" then
        return function()
            return not locked_out_fire, "fire locked out"
        end
    elseif school == "frost" then
        return function()
            return not locked_out_frost, "frost locked out"
        end
    end
    return function() -- frostfire: either school's lockout
        return not (locked_out_fire or locked_out_frost), "fire or frost locked out"
    end
end

-- A hard cast's `now` or `handler`: spends Presence of Mind (DB2 12043 aura 108 misc 10 -100% cast time on every cast
-- below, by the class mask; wowsims presence_of_mind.go: the first cast of its scope with a cast time takes it). Each
-- cast time reads it: 0 while it is up.
-- With `spends` (a `handler`'s): a Fingers of Frost charge spent too (below; no `now` verb spends a stack: the belief's
-- charges are the aura walk's).
local function casts(spends)
    return function()
        removeBuff("presence_of_mind")
        if spends and buff.fingers_of_frost.up then
            removeStack("fingers_of_frost")
        end
    end
end

-- The five-second rule (C3): spirit and mp5 regen per second, the declared starting point the out-of-combat read and
-- the in-combat calibration replace: wowsims's logs at 60 (the P1 gear, both builds: 2.913 a 0.1 s tick outside the
-- rule); no mp5. UNMEASURED in game.
local SPIRIT_REGEN = 29.13
-- Evocation (12051): spirit regen +1500% (aura 110) and all of it while casting (aura 134), 8 s; its periodic dummy
-- (aura 226) every second. A tick here is 15x the declared spirit rate (wowsims's logs: 46.6 a 0.1 s tick, 16x, the
-- 1x the regen's).
-- shortcut: fixed at build from SPIRIT_REGEN (the regen entries take a number), and the 1x spirit part the window
-- withholds inside the five-second rule is not added; upgrade when a regen entry can scale the calibrated rate.
local EVOCATION_TICK = 15 * SPIRIT_REGEN
spec:RegisterResource(
    Enum.PowerType.Mana,
    {
        evocation = {
            aura = "evocation",

            last = function()
                local app = state.buff.evocation.applied
                return app + floor(state.query_time - app)
            end,

            interval = 1,
            value = EVOCATION_TICK,
        },
    },
    nil,
    {
        -- the starting point: GetPowerRegenForPowerType's out-of-combat read calibrates both parts, the casting share
        -- included (Game/State/Sources/Power.lua's regen read)
        fsr = { spirit = SPIRIT_REGEN, mp5 = 0 },
        base = 1213, -- a fraction cost is of base mana (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
    }
)

-- The cost modifiers, each on the class mask's registered rank-1 IDs (DB2 SpellEffect masks against SpellClassSet 3;
-- Arcane Wrath's mask is wowsims's): Clearcasting (12536: -100%, a charge), Missile Barrage (400589: Arcane Missiles
-- -100%, a charge), Arcane Power (12042: +30%; Arcane Wrath inside its mask: wowsims's data, word 1 0x9000 covering its
-- 0x8000, and its log's 513.5 = 395 x 1.3 while Arcane Power is up).
local CLEARCASTING_SCOPE = { 400574, 5143, 2136, 133, 116, 401502, 11366, 2948, 1326079 }
spec:RegisterCostMod({ aura = "clearcasting", pct = -1, charges = 1, spells = CLEARCASTING_SCOPE })
spec:RegisterCostMod({ aura = "missile_barrage", pct = -1, charges = 1, spells = { 5143 } })
spec:RegisterCostMod({
    aura = "arcane_power",
    pct = 0.3,
    spells = { 400574, 5143, 2136, 133, 116, 401502, 11366, 2948, 1326079 },
})

spec:RegisterAuras({
    -- Arcane Blast's charges: +175% to its own cost a stack (DB2 400573 aura 108 misc 14), 4 at most, 15 s from the
    -- first (ruling M9: wowsims's data and log; the DB2's 8 s an in-game check). Nothing else spends them (wowsims
    -- arcane_charge.go).
    arcane_blast = { id = 400573, duration = 15, max_stack = 4 },
    -- The procs (unseen; the player aura walk reads them where plain): the next Arcane Missiles free in half the time;
    -- Pyroblast's cast -25% a stack; the next 2 spells as if the target were Frozen; the next spell free.
    missile_barrage = { id = 400589, duration = 15, max_stack = 1 },
    heating_up = { id = 400625, duration = 20, max_stack = 3 },
    fingers_of_frost = { id = 400669, duration = 15, max_stack = 2 },
    clearcasting = { id = 12536, duration = 15, max_stack = 1 },
    arcane_power = { id = 12042, duration = 15, max_stack = 1 },
    presence_of_mind = { id = 12043, duration = 3600, max_stack = 1 }, -- until the next cast (DB2 -1)
    combustion = { id = 11129, duration = 3600, max_stack = 1 }, -- until 3 crits (DB2 -1; unseen)
    evocation = { id = 12051, duration = 8, tick_time = 1, max_stack = 1 },
    -- The target's (unreadable in combat), modelled from our Scorches: Improved Scorch's 3% more Fire damage from us a
    -- stack, 5 at most, 30 s (wowsims: each Mage's own).
    fire_vulnerability = { id = 22959, duration = 30, max_stack = 5 },
})

-- Fingers of Frost (wowsims talents_frost.go registerFingersOfFrost): every damage spell cast, a channel aside, spends a
-- charge (the cast that granted them none: the grant, a Chill's 15% roll on its hit, is unseen, so the sim spends on
-- every cast). Each `handler` below with `spends` set.
-- shortcut: Arcane Missiles spends one a landed missile; its channel spends none here, and no build that casts it takes
-- Fingers of Frost; upgrade if a pack does.

-- An instant's `handler` (Fire Blast): only the charge.
local function fingered()
    return function()
        if buff.fingers_of_frost.up then
            removeStack("fingers_of_frost")
        end
    end
end

-- A Scorch's `now` or `handler`: Fire Vulnerability's stack (wowsims scorch.go: on a landed Scorch, at Improved
-- Scorch's chance), and Presence of Mind spent.
-- shortcut: the roll is unseen, so ranks 1-2 (33% / 67%) add a stack on every Scorch as rank 3 (100%) does; upgrade
-- if a pack reads the stack below 3/3.
local function scorched(spends)
    return function()
        removeBuff("presence_of_mind")
        if spends and buff.fingers_of_frost.up then
            removeStack("fingers_of_frost")
        end
        if talent.improved_scorch.rank > 0 then
            applyDebuff("target", "fire_vulnerability", nil, min(5, debuff.fire_vulnerability.stack + 1))
        end
    end
end

-- A Pyroblast's: every Heating Up stack spent unless Presence of Mind made it instant (wowsims talents_fire.go).
local function pyroblasted(spends)
    return function()
        if spends and buff.fingers_of_frost.up then
            removeStack("fingers_of_frost")
        end
        if not buff.presence_of_mind.up then
            removeBuff("heating_up")
        end
        removeBuff("presence_of_mind")
    end
end

-- An Arcane Blast's: a charge (the run keeps the first charge's end: wowsims arcane_charge.go), and Presence of Mind
-- spent.
local function charged(spends)
    return function()
        removeBuff("presence_of_mind")
        if spends and buff.fingers_of_frost.up then
            removeStack("fingers_of_frost")
        end
        addStack("arcane_blast", buff.arcane_blast.up and buff.arcane_blast.remains or nil)
    end
end

-- Presence of Mind and Combustion share category 1151's 180 s (DB2 SpellCategories): each sets the other's.
-- shortcut: both are "disabled while active" (their cooldown starts when the effect ends); here it starts at the cast,
-- the client's cooldown read corrects it.
local function shares(other, aura)
    return function()
        setCooldown(other, 180)
        applyBuff(aura)
    end
end

spec:RegisterAbilities({
    -- 15% of base mana, +175% a charge (0.15, 0.4125, 0.675, 0.9375, 1.2 of base at 0-4 charges): `spendBase` keeps
    -- the 1.2 a fraction of base (Spec.lua), as the smaller ones.
    arcane_blast = {
        id = 400574,
        copy = rest(ARCANE_BLAST),
        cast = function()
            return buff.presence_of_mind.up and 0 or 1.5 * haste -- ruling M9 (the DB2: 2.5)
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.15 * (1 + 1.75 * buff.arcane_blast.stack)
        end,
        spendType = "mana",
        spendBase = true,

        startsCombat = true,
        known = knows(ARCANE_BLAST),
        usable = unlocked("arcane"),

        now = charged(),
        handler = charged(true),
    },

    -- A channel: a missile a second (3, 4, then 5 s); under Missile Barrage 2.5 s with a missile every 0.5 s, free (its
    -- cost modifier takes the charge).
    arcane_missiles = {
        id = 5143,
        copy = rest(ARCANE_MISSILES),
        cast = function()
            local t = ARCANE_MISSILES_TIME[knownRank(ARCANE_MISSILES)] or 3
            return (buff.missile_barrage.up and t / 2 or t) * haste
        end,
        channeled = true,
        tick_time = function()
            return (buff.missile_barrage.up and 0.5 or 1) * haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(ARCANE_MISSILES_COST, ARCANE_MISSILES),
        spendType = "mana",

        startsCombat = true,
        known = knows(ARCANE_MISSILES),
        usable = unlocked("arcane"),
    },

    arcane_wrath = {
        id = 1326079,
        copy = rest(ARCANE_WRATH),
        cast = function()
            return buff.presence_of_mind.up and 0 or 3.5 * haste
        end,
        cooldown = 6,
        gcd = "spell",

        spend = byRank(ARCANE_WRATH_COST, ARCANE_WRATH),
        spendType = "mana",

        startsCombat = true,
        known = knows(ARCANE_WRATH),
        usable = unlocked("arcane"),

        now = casts(),
        handler = casts(true),
    },

    frostbolt = {
        id = 116,
        copy = rest(FROSTBOLT),
        cast = function()
            local base = FROSTBOLT_CAST[knownRank(FROSTBOLT)] or FROSTBOLT_CAST[1]
            return buff.presence_of_mind.up and 0 or (base - 0.1 * talent.improved_frostbolt.rank) * haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = frostChanneled(FROSTBOLT_COST, FROSTBOLT),
        spendType = "mana",

        startsCombat = true,
        known = knows(FROSTBOLT),
        usable = unlocked("frost"),

        now = casts(),
        handler = casts(true),
    },

    fireball = {
        id = 133,
        copy = rest(FIREBALL),
        cast = function()
            local base = FIREBALL_CAST[knownRank(FIREBALL)] or FIREBALL_CAST[1]
            return buff.presence_of_mind.up and 0 or (base - 0.1 * talent.improved_fireball.rank) * haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(FIREBALL_COST, FIREBALL),
        spendType = "mana",

        startsCombat = true,
        known = knows(FIREBALL),
        usable = unlocked("fire"),

        now = casts(),
        handler = casts(true),
    },

    scorch = {
        id = 2948,
        copy = rest(SCORCH),
        cast = function()
            return buff.presence_of_mind.up and 0 or 1.5 * haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(SCORCH_COST, SCORCH),
        spendType = "mana",

        startsCombat = true,
        known = knows(SCORCH),
        usable = unlocked("fire"),

        now = scorched(),
        handler = scorched(true),
    },

    -- 6 s, -25% a Heating Up stack (DB2 400625 aura 108 misc 10): 1.5 s at three.
    pyroblast = {
        id = 11366,
        copy = rest(PYROBLAST),
        cast = function()
            return buff.presence_of_mind.up and 0 or 6 * (1 - 0.25 * buff.heating_up.stack) * haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = byRank(PYROBLAST_COST, PYROBLAST),
        spendType = "mana",

        startsCombat = true,
        known = knows(PYROBLAST),
        usable = unlocked("fire"),

        now = pyroblasted(),
        handler = pyroblasted(true),
    },

    fire_blast = {
        id = 2136,
        copy = rest(FIRE_BLAST),
        cast = 0,
        cooldown = function()
            local r = talent.wake_of_fire.rank
            return 8 - (r > 0 and (WAKE_OF_FIRE[r] or WAKE_OF_FIRE[#WAKE_OF_FIRE]) or 0)
        end,
        gcd = "spell",

        spend = byRank(FIRE_BLAST_COST, FIRE_BLAST),
        spendType = "mana",

        startsCombat = true,
        known = knows(FIRE_BLAST),
        usable = unlocked("fire"),

        -- no `now`: removeStack is no `now` verb; the belief takes the charges from the aura walk
        handler = fingered(),
    },

    -- Frostfire: locked out by either school's lockout. Improved Fireball's -0.1 s a rank reaches it (DB2 11069's mask
    -- word 1 0x1000, Frostfire Bolt's; wowsims's FFB log: 2.5 s unhasted at 5/5).
    frostfire_bolt = {
        id = 401502,
        copy = rest(FROSTFIRE_BOLT),
        cast = function()
            return buff.presence_of_mind.up and 0 or (3 - 0.1 * talent.improved_fireball.rank) * haste
        end,
        cooldown = 0,
        gcd = "spell",

        spend = frostChanneled(FROSTFIRE_BOLT_COST, FROSTFIRE_BOLT),
        spendType = "mana",

        startsCombat = true,
        known = knows(FROSTFIRE_BOLT),
        usable = unlocked("frostfire"),

        now = casts(),
        handler = casts(true),
    },

    -- A channel of 8 s, its mana from the resource's evocation entry while its aura is up (a channel's `handler` never
    -- runs in Hekili's simulation: `start`).
    evocation = {
        id = 12051,
        cast = 8,
        channeled = true,
        tick_time = 1,
        cooldown = 480,
        gcd = "spell",

        startsCombat = false,
        known = knows({ 12051 }),
        usable = unlocked("arcane"),

        now = function()
            applyBuff("evocation")
        end,
        start = function()
            applyBuff("evocation")
        end,
    },

    -- Off the GCD (DB2 start recovery 0); 30 s category cooldown; locks the target's school out for 10 s.
    counterspell = {
        id = 2139,
        cast = 0,
        cooldown = 30,
        gcd = "off",

        spend = 100,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 2139 }),
        debuff = "casting",
        readyTime = state.timeToInterrupt,

        usable = unlocked("arcane"),

        handler = function()
            interrupt()
        end,
    },

    arcane_power = {
        id = 12042,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows({ 12042 }),

        now = function()
            applyBuff("arcane_power")
        end,
        handler = function()
            applyBuff("arcane_power")
        end,
    },

    presence_of_mind = {
        id = 12043,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows({ 12043 }),

        usable = function()
            return not buff.presence_of_mind.up, "already up"
        end,

        now = shares("combustion", "presence_of_mind"),
        handler = shares("combustion", "presence_of_mind"),
    },

    combustion = {
        id = 11129,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows({ 11129 }),

        usable = function()
            return not buff.combustion.up, "already up"
        end,

        now = shares("presence_of_mind", "combustion"),
        handler = shares("presence_of_mind", "combustion"),
    },
})

-- Talents: { talent tree (1 Arcane, 2 Fire, 3 Frost: the dominant tree picks the spec), rank 1's spell, max rank }: the
-- DB2's 49 nodes (`wowdb talents MAGE`; the tree is the DB2's Talent.TabID), keys the snake_case names. The cast times
-- read Improved Fireball and Improved Frostbolt, Fire Blast's cooldown Wake of Fire, Scorch Improved Scorch.
spec:RegisterTalents({
    -- Arcane (tree 1)
    arcane_subtlety = { 1, 11210, 2 },
    arcane_focus = { 1, 11222, 5 },
    improved_channeling = { 1, 11237, 5 },
    wand_specialization = { 1, 6057, 2 },
    magic_absorption = { 1, 29441, 5 },
    arcane_concentration = { 1, 11213, 5 },
    arcane_geometry = { 1, 11247, 2 },
    arcane_impact = { 1, 11242, 3 },
    arcane_resilience = { 1, 28574, 1 },
    arcane_shielding = { 1, 11252, 2 },
    improved_counterspell = { 1, 11255, 2 },
    arcane_meditation = { 1, 18462, 3 },
    presence_of_mind = { 1, 12043, 1 },
    arcane_mind = { 1, 11232, 5 },
    arcane_instability = { 1, 15058, 3 },
    arcane_power = { 1, 12042, 1 },
    -- Fire (tree 2)
    improved_fireball = { 2, 11069, 5 },
    impact_talent = { 2, 11103, 5 }, -- `impact` is a core identifier (tests/boundary_spec.lua)
    ignite = { 2, 11119, 5 },
    flame_throwing = { 2, 11100, 2 },
    wake_of_fire = { 2, 11078, 3 },
    incineration = { 2, 18459, 2 },
    improved_flamestrike = { 2, 11108, 3 },
    pyroblast = { 2, 11366, 1 },
    burning_soul = { 2, 11083, 2 },
    improved_scorch = { 2, 11095, 3 },
    improved_fire_ward = { 2, 11094, 2 },
    master_of_elements = { 2, 29074, 3 },
    critical_mass = { 2, 11115, 3 },
    blast_wave = { 2, 11113, 1 },
    fire_power = { 2, 11124, 5 },
    combustion = { 2, 11129, 1 },
    -- Frost (tree 3)
    frost_warding = { 3, 11189, 2 },
    improved_frostbolt = { 3, 11070, 5 },
    elemental_precision = { 3, 29438, 3 },
    ice_shards = { 3, 11207, 5 },
    frostbite = { 3, 11071, 3 },
    improved_frost_nova = { 3, 11165, 2 },
    permafrost = { 3, 11175, 3 },
    piercing_ice = { 3, 11151, 3 },
    cold_snap = { 3, 12472, 1 },
    improved_blizzard = { 3, 11185, 3 },
    arctic_reach = { 3, 16757, 2 },
    frost_channeling = { 3, 11160, 3 },
    shatter = { 3, 11170, 5 },
    ice_block = { 3, 11958, 1 },
    improved_cone_of_cold = { 3, 11190, 3 },
    winters_chill_talent = { 3, 11180, 5 }, -- `winters_chill` is upstream's (Engine/Sim/Scripts.lua)
    ice_barrier = { 3, 11426, 1 },
    -- Forever-only (tree 0: not in the DB2's Talent table; wowsims's tree places Missile Barrage, Arcane Blast and
    -- Arcane Wrath in Arcane, Heating Up in Fire, Ice Lance and Fingers of Frost in Frost; its ranks). Arcane Wrath's
    -- node spell is unknown: rank 1 of the spell it teaches (wowsims's) until the live export.
    missile_barrage = { 0, 400588, 2 },
    arcane_blast = { 0, 400574, 1 },
    arcane_wrath = { 0, 1326079, 1 },
    heating_up = { 0, 400624, 1 },
    ice_lance = { 0, 1312002, 1 },
    fingers_of_frost = { 0, 400647, 2 },
})

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and
-- run it, never this block (tests/Forever/mage_spec.lua checks it matches). Each pack's .simc is generated from its
-- wowsims recipe (`make wowsims-packs`, tools/wowsims/specs/mage_*.lua).
spec:RegisterPack(
    "Arcane (wowsims.com)",
    20261021946,
    [[Hekili:Ds1FVTjmq0VnBnArajK2TgvMuN2VA1A1KO)THdBtWRGnY20OknXN9DgsYySqx7uKSUC39E35ZVdYcYDKygy5KBxgS8SfblxC(QZiX2hR5K4AGEpSbnKqfEEPMcsEB6jBvBnIkJhvvnZL1JLkG5ykRruAVssYokPMAoLeFZLF5tRHoQiXfcgJ3Np3qNOeRBtTfOZD(8ZvA(dCDBkJNdnL220l)(3Atr3O1EcAe(U6z8RWBGpR24d1L4rxCp027hgLC2CKBninLy7YqBLRwctBkWyk5RrJ75pA8At)iyH1hPho5MRUdjPWARnR993iSfnzU22FuQZqoXwLfgEEyalyvqyGho80QCrjojaQvOKMikuwM0)NKsHXo3n7J4pOOGZ3CrEufibVAQ9IOfbTxVd4BI8Bm8eHLxzM7Su55jBOSOfdtPwZnCj1fnPsiztNz)GkPwTLRNolxRKSHx9p5Psym490mpxrBmrlC3JSM8CVDbsYaTgFP8AQpc6TAWwCe)zLaoHqQoPJRHE908kqinx0d6pJrXJFEemglQ4Vy1R6MW0gTMlTVp60GGGztNE4O0x1L(uzVC2W7rUwzSzkudV3P3HN6F)O3Enjgvqg0C0kLtHy62H7xfqZB72P5siRKZiFGet1OOqlas8qHZEfhgFKIRN1K(D(d9aXILEeZdE0DL9aJheIoqHptqJLMoSREMyhkwD4o9zIBV81H5SjhBtOt)RYVxJtI7e5UkH8(2r8ocuN02L37E6860qd7Q)hj)lvZ)sf9pHQ3DfpFIR4HTaI73an3ruZ7Xmuy2HcASfknj(R87fLc8dZFE33D7ct(1p]]
)
spec:RegisterPack(
    "Fire (wowsims.com)",
    20261021339,
    [[Hekili:ns17VTjmq0)CwJwe)izTBnk8HoT1TwTwnj6NnySnbVAWiFMwfPj(BFNHecJMuLVGom37D39UNHesEIeZPwb5XfblUkmyr4YLxtITBRfK4Ak7z6gmOIwIpVvAeTPx8Q(vqwcEmD5mxoBvAk3XtwJuzVRIKDukHAbJe)Wn)47RYrIiXfsox0NTayhL(vTP2c8WDN5NRnIxeM2uUiN2OSTP387F1MIh3MUdEJ03vjWVe7CFEn4tRvGpxiQDz4HV59hqxnBoYTHwbkSv5yS2vlj0Ms5CD1hWGNfBbV20VrT0vhPhU4H7EcjPWARHv((BK2IMmxB7pj1ziNyRYrzyzap4tbld8qHZOZLkuhOmRuxbrmQsL0)sIsc25ovps8IMrDNnxMhvsROE1m76OWG273b8Jr(atByfZZ1SgiAHlZl4ISM8CpNuN8sJQsyOzsL0U1dS4AD9L)90zyeLuzfS(YzJlsdisKwrjm3fPZZt2W4rHJtbh(SgORBpzoUzizJO80zuV1OZuuub6hOq3a11RfcukQ2K0u3pfrlhJRBs6ao(uQHrRejLsaq5gEdN7(qsg1yqlJxt9uoZWfZWzEdlKdRM27jX4EgWWjME3Ee6UJ1ByXWh7UZjQOzkbN8vsmZGQQrsjXJxV79f43N4l6znP)o5qpqSyPpjZNHD4S8dh6QElhjUtoDLgR)Yj1F0g2n2dyhCsoqF6mbDWB5qD5zIAVBZH5QtkpNWCDGMbl5Wah6y8ZtyCF6hCIUS(Y7x33Aapq0eZ7)x9RFNQ78Sex1h5qoI3BpKX2Oou0gBH2qI)P4z0dG)S72D)lR7ZK)9]]
)
spec:RegisterPack(
    "Frostfire (wowsims.com)",
    20261021000,
    [[Hekili:nsvBVPnmq4Fod0q5fO0PHiFOtBDRvRvtk9ZoXXVq8WjoY2HkKMYV9DobcbePcHe6IZ98Cp3DpoOq0BOyk2YqVopy(9HbZddccqX29vmuCfMSfVbckXfW)pQvglxOznPtEx9Uruy8iQIPUe3lvyQJSSAH0(ujk7Q8AQyeu8lp8ZFSYrekoxqPSUSzgY41yvtQnho8Wz(CLMTJPBsPmoUwABsF4p)UjfoUjDih1cFxnn(fqJ4tRm(4kjaNN5bbE)1OkNod4wJlnsqVuiw5QLW0KIPuv5NGGTS9gVM0VJT4vxrdtE5P3asYT2kZkF)ncBEDMt2(xK6uGtqQ0fl(6IaAWDblc8GPNwXfsyyGjwHQ0erWszs3djsHXoZn)Jy7ueS7SzcEubUe7vrSRJcdAE(aWph5BiknjFgxrQnrZDzoHYYQ5Cp3ajzxTSKPXzcPWU3ZyHf86L)B8m0ScSO0SE50HfP2WsewwHzMlsX5jBi0OWHP40xYgwX4zuTxRYKyO76eBOtST6iNbTz5MK6QofgTyiUwvEDGCaftBG6LWDEGdn48ZGF0CKKPaBZX341pDhmNpmfBEgfdlpdC0f2z3YX0EfQZfcHV2ELIvIZKmk6BOyIggvAbgfpCNDCzdV)ILDhRjDx561cYcLEuMVHD8nTKpPQoFekUDe4knu)fxu)bRwxB3JT3E4aD3nc6OHXHz5On6i(Jt007Q6LEOJX7)yghZ4CI3tUUZj(lxqCF(NzZqUFdwMxXMCe4PKgo7BXJRT5knk(xSTWId(SZJh(Qs7Rr))p]]
)
