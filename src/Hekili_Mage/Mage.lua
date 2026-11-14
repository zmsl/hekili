-- Hekili_Mage/Mage.lua
-- The Forever Mage (Arcane, Fire and Frost, one spec a talent tree: Hekili:NewClass): the Mage kit with
-- Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build 1.60.1.70338,
-- wowdb), mana under the five-second rule (`fsr`), the casts and the two channels (Arcane Missiles and Evocation:
-- `channeled`, `tick_time`), Arcane Blast's charges (each +175% to its own cost, a fraction of base mana), Missile
-- Barrage (Arcane Missiles free, in half the time), Heating Up's cheaper Pyroblast casts, Fingers of Frost's charges
-- spent by each damage cast, Frost Channeling's cheaper Frost casts, Fire Vulnerability's stacks from Scorch,
-- Evocation's mana, Presence of Mind, Arcane Power's +30% cost, Clearcasting as a charged cost modifier, Counterspell,
-- and the school lockouts (each spell refuses while an interrupt has its school locked out: Hekili_Shared's
-- locked_out_<school>), and the Frost kit (Winter's Chill, Cone of Cold, Ice Lance, Ice Barrier, Cold Snap, Blizzard,
-- Frost Nova, Ice Block). The priorities are the wowsims.com packs (Arcane, Fire, Frostfire as Fire's second by its
-- talents' points, and Frost; the abilities and auras below are what wowsims/forever's arcane.apl.json,
-- deepFire.apl.json, ffb.apl.json and frost.apl.json cast or read, and the Frost spells a Frost player presses).
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
-- priority reads them), Master of Elements' refunds where no crit is seen (a seen crit refunds: `onCrit`), pushback.
-- Credits: Hekili (registration API and pack format). wowsims/forever (MIT, ui/specs/mage/dps/apls/*.apl.json and
-- sim/mage/) is the reference for the abilities and the charge, proc, Evocation and gem rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase = Facade.UnitClassBase
local L = Hekili:GetLocale("Hekili_Mage")

if UnitClassBase("player") ~= "MAGE" then
    return
end

local state = Hekili.State

-- The class kit and one spec a talent tree (ids the core's: Arcane 100081, Fire 100082, Frost 100083; the client's one
-- pseudo-spec, assumed 1485, only keys the legacy profile the core migrates). Icons: the DB2 talent tabs'. Each package is the spec's wowsims.com pack.
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
            package = "Frost (wowsims.com)",
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
-- Frost's (the DB2's ranks and costs; Ice Lance's and Ice Barrier's ladders as wowsims's spell data lists them).
local CONE_OF_COLD = { 120, 8492, 10159, 10160, 10161 }
local CONE_OF_COLD_COST = { 210, 290, 380, 465, 555 }
local ICE_LANCE = { 1312002, 400640, 1240044, 1240045, 1240046, 1240047 }
local ICE_LANCE_COST = { 45, 55, 70, 105, 120, 160 }
local ICE_BARRIER = { 11426, 13031, 13032, 13033 }
local ICE_BARRIER_COST = { 305, 360, 420, 480 }
local BLIZZARD = { 10, 6141, 8427, 10185, 10186, 10187 }
local BLIZZARD_COST = { 320, 520, 720, 935, 1160, 1400 }
local FROST_NOVA = { 122, 865, 6131, 10230 }
local FROST_NOVA_COST = { 55, 85, 115, 145 }
local ICE_BLOCK = { 11958 }
local ICE_BLOCK_COST = { 15 }

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
-- names Frostbolt, Frostfire Bolt, Cone of Cold, Ice Lance, Ice Barrier, Blizzard, Frost Nova and Ice Block (bit 19);
-- wowsims's FFB log: 314.5 = 370 x 0.85 at 3/3, its Frost log: Cone of Cold 527.25, Ice Barrier 456).
local function frostChanneled(values, ids)
    return function()
        return (values[knownRank(ids)] or values[1]) * (1 - 0.05 * talent.frost_channeling.rank)
    end
end

-- Master of Elements (29074, 3 ranks; wowsims talents_fire.go registerMasterOfElements): a Fire or Frost cast's crit
-- refunds 10% a rank of its base cost (the rank's cost before Frost Channeling). Crits are seen only through the cast's
-- own (`onCrit`, Families/Now.lua), so the belief is a lower bound where none is seen: no expected value is added
-- (a read of the crit chance would be, if it proves plain in combat: needs in-game check). A closure per ability.
local function mastered(costs, ids)
    return function()
        local r = talent.master_of_elements.rank
        if r > 0 then
            gain(0.1 * r * (costs[knownRank(ids)] or costs[1]), "mana")
        end
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
-- With `spends` (a `handler`'s): a Fingers of Frost charge spent too (below; Fire Blast's `now` spends it too, the other
-- casts leave the belief's charges to the aura walk).
local function casts(spends)
    return function()
        removeBuff("presence_of_mind")
        if spends and buff.fingers_of_frost.up then
            removeStack("fingers_of_frost")
        end
    end
end

-- Winter's Chill (11180, 5 ranks; wowsims talents_frost.go registerWinterChill): a landed Frostbolt adds a stack of the
-- target's Winter's Chill (12579: 5 at most, 15 s; Cone of Cold spends them). A Frostbolt's `now` or `handler`: the
-- same as `casts`, and the stack.
-- shortcut: the roll (20% a rank) is unseen, so ranks 1-4 add a stack on every Frostbolt as rank 5 (100%) does;
-- upgrade if a pack reads the stack below 5/5.
local function chilled(spends)
    return function()
        removeBuff("presence_of_mind")
        if spends and buff.fingers_of_frost.up then
            removeStack("fingers_of_frost")
        end
        if talent.winters_chill_talent.rank > 0 then
            applyDebuff("target", "winters_chill", nil, min(5, debuff.winters_chill.stack + 1))
        end
    end
end

-- The five-second rule (C3): spirit and mp5 regen per second, the declared starting point the out-of-combat read and
-- the in-combat calibration replace, as wowsims's logs measure them at 60 (the P1 gear, 29.13 a second outside the
-- rule in every build): Arcane all of it while casting (Arcane Meditation 50% + Mage Armor 50%: share 1), so spirit 0
-- and mp5 29.13; Fire and Frostfire half (Mage Armor's 50%: share 0.5), 14.57 / 14.56 (the logs' Tag 2 / Tag 1).
-- Forever's Spirit regen is `6.25 + Spirit/8` a second for every class (wowsims mana.go:75-76). UNMEASURED in game.
-- shortcut: Mage Armor assumed up, as every wowsims export pre-buffs it (30 min): its aura is registered (below) but the
-- share does not read it. A share function is read once at the build with no belief (Engine/Schema/Tracked.lua), and a
-- regen entry on the aura would stop the out-of-combat read from calibrating the split (Resources.lua readAt: a share
-- entry up is a mixed pair, never stored): a Mage in Ice Armor still has its Evocation counted double (gaps.md BX).
-- Upgrade with a core static share the belief re-reads (needs a central item) when such a build matters.
-- Evocation (12051, 8 s): spirit regen +1500% (aura 110) and all of it while casting (aura 134): the learned spirit
-- regen x 16 in and out of the rule (wowsims evocation.go:11-27; its logs 466 a second).
-- state.spec: the functions run in the state's environment (the file's `spec` is the class).
spec:RegisterResource(
    Enum.PowerType.Mana,
    {
        evocation = { aura = "evocation", spirit = 16, share = 1 },
    },
    nil,
    {
        fsr = {
            spirit = function()
                return state.spec.arcane and 0 or 14.57
            end,
            mp5 = function()
                return state.spec.arcane and 29.13 or 14.56
            end,
            share = function()
                return state.spec.arcane and 1 or 0.5
            end,
        },
        base = 1213, -- a fraction cost is of base mana (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
    }
)

-- The cost modifiers, each on the class mask's registered rank-1 IDs (DB2 SpellEffect masks against SpellClassSet 3;
-- Arcane Wrath's mask is wowsims's): Clearcasting (12536: -100%, a charge), Missile Barrage (400589: Arcane Missiles
-- -100%, a charge), Arcane Power (12042: +30%; Arcane Wrath inside its mask: wowsims's data, word 1 0x9000 covering its
-- 0x8000, and its log's 513.5 = 395 x 1.3 while Arcane Power is up).
-- Arcane Missiles (5143) keeps Clearcasting when Missile Barrage pays for the cast (wowsims ef6fb99ee1): its own
-- registration with `unless`; every other spell in the mask still spends it while Barrage is up.
spec:RegisterCostMod({
    aura = "clearcasting",
    pct = -1,
    charges = 1,
    -- Cone of Cold, Ice Lance, Blizzard and Frost Nova too (the mask's bits 9, 17, 7, 6; Ice Barrier and Ice Block not):
    -- wowsims's Frost log casts Cone of Cold for 0 under it (72.00)
    spells = { 400574, 2136, 133, 116, 401502, 11366, 2948, 1326079, 120, 1312002, 10, 122, 1449, 2120, 11113, 1326053 },
})
spec:RegisterCostMod({ aura = "clearcasting", pct = -1, charges = 1, spells = { 5143 }, unless = "missile_barrage" })
spec:RegisterCostMod({ aura = "missile_barrage", pct = -1, charges = 1, spells = { 5143 } })
spec:RegisterCostMod({
    aura = "arcane_power",
    pct = 0.3,
    spells = { 400574, 5143, 2136, 133, 116, 401502, 11366, 2948, 1326079, 1449, 2120, 11113, 1326053 },
})

spec:RegisterAuras({
    -- Arcane Blast's charges: +100% to its own cost a stack, 4 at most, 18 s from the first (hotfix 113554, wowsims
    -- 5508974417; the DB2 70707 base file: +175%, 15 s). Nothing else spends them (wowsims arcane_charge.go).
    arcane_blast = { id = 400573, duration = 18, max_stack = 4 },
    -- The procs (unseen; the player aura walk reads them where plain): the next Arcane Missiles free in half the time;
    -- Pyroblast's cast -25% a stack; the next 2 spells as if the target were Frozen; the next spell free.
    missile_barrage = { id = 400589, duration = 15, max_stack = 1 },
    heating_up = { id = 400625, duration = 20, max_stack = 3 },
    -- 400670: the id the client's Cooldown Manager links for the talent's item (audit A1; the pin registers 400669 only)
    fingers_of_frost = { id = 400669, copy = { 400670 }, duration = 15, max_stack = 2 },
    clearcasting = { id = 12536, duration = 15, max_stack = 1 },
    arcane_power = { id = 12042, duration = 15, max_stack = 1 },
    presence_of_mind = { id = 12043, duration = 3600, max_stack = 1 }, -- until the next cast (DB2 -1)
    -- until 3 crits (DB2 -1; unseen): the Cooldown Manager's item links 28682 (the crit counter, 10 stacks, applied and
    -- removed with 11129: wowsims combustion.go), so its loss ends the belief's aura where the 3 crits are unseen
    combustion = { id = 11129, copy = { 28682 }, duration = 3600, max_stack = 1 },
    evocation = { id = 12051, duration = 8, tick_time = 1, max_stack = 1 },
    -- The armors (audit B2; the pin's rank lists, one up at a time): only Mage Armor's 50% regen while casting matters
    -- to the mana model; a rank's aura carries its spell's id.
    mage_armor = { id = 6117, copy = { 22782, 22783 }, duration = 1800, max_stack = 1 },
    ice_armor = { id = 7302, copy = { 7320, 10219, 10220 }, duration = 1800, max_stack = 1 },
    frost_armor = { id = 168, copy = { 7300, 7301 }, duration = 1800, max_stack = 1 },
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
    -- 15% of base mana, +100% a charge (0.15, 0.3, 0.45, 0.6, 0.75 of base at 0-4 charges; hotfix 113554):
    -- `spendBase` prices each a fraction of base (Spec.lua).
    arcane_blast = {
        id = 400574,
        copy = rest(ARCANE_BLAST),
        cast = function()
            return buff.presence_of_mind.up and 0 or 1.5 * haste -- ruling M9 (the DB2: 2.5)
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.15 * (1 + buff.arcane_blast.stack)
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
        expects = "travel",
        velocity = 24, -- DB2 and wowsims Speed 24
        copy = rest(ARCANE_WRATH),
        cast = function()
            -- Accelerant (Improved Fireball's 11069 node; wowsims): 0.1 s off a rank
            return buff.presence_of_mind.up and 0 or (3.5 - 0.1 * talent.improved_fireball.rank) * haste
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
        expects = "travel",
        velocity = 28,
        school = "frost",
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

        now = chilled(),
        handler = chilled(true),
        onCrit = mastered(FROSTBOLT_COST, FROSTBOLT),
    },

    fireball = {
        id = 133,
        expects = "travel",
        velocity = 24,
        school = "fire",
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
        onCrit = mastered(FIREBALL_COST, FIREBALL),
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
        onCrit = mastered(SCORCH_COST, SCORCH),
    },

    -- 6 s, -25% a Heating Up stack (DB2 400625 aura 108 misc 10): 1.5 s at three.
    pyroblast = {
        id = 11366,
        expects = "travel",
        velocity = 24,
        school = "fire",
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
        onCrit = mastered(PYROBLAST_COST, PYROBLAST),
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

        now = fingered(),
        handler = fingered(),
        onCrit = mastered(FIRE_BLAST_COST, FIRE_BLAST),
    },

    -- Frostfire: locked out by either school's lockout. Improved Fireball's -0.1 s a rank reaches it (DB2 11069's mask
    -- word 1 0x1000, Frostfire Bolt's; wowsims's FFB log: 2.5 s unhasted at 5/5).
    frostfire_bolt = {
        id = 401502,
        expects = "travel",
        velocity = 24, -- no school: DB2 mask 20 (fire and frost), U7 deferred
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
        onCrit = mastered(FROSTFIRE_BOLT_COST, FROSTFIRE_BOLT),
    },

    -- A channel of 8 s; its mana is the mana resource's evocation regen entry (spirit x 16, all of it while casting)
    -- while its aura is up (a channel's `handler` never runs in Hekili's simulation: `start`).
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

-- Frost (wowsims/forever's frost.apl.json, the Frost (wowsims.com) pack): Cone of Cold on five Winter's Chill stacks,
-- Cold Snap to reset it, Ice Barrier kept for Frigid Power, Ice Lance on a Fingers of Frost charge, and the AoE list's
-- Blizzard. Values from the DB2 (costs, cooldowns, durations, the class masks: Frost Channeling's bit 19 names Cone of
-- Cold, Ice Lance, Ice Barrier and Blizzard) where wowsims's log agrees (Cone of Cold 527.25 = 555 x 0.95 and Ice
-- Barrier 456 = 480 x 0.95 under Frost Channeling 1/3). Blink (the list's pre-pull leap) is not in the pack: its line's
-- time reads Blink's aura duration, which the translator does not fold (the pack's `# Omitted:` line).
spec:RegisterAuras({
    -- The target's (unreadable in combat), modelled from our Frostbolts: Winter's Chill, 5 at most, 15 s.
    winters_chill = { id = 12579, duration = 15, max_stack = 5 },
    -- Ice Barrier's shield (60 s or until it breaks: no damage taken is modelled) and its Frigid Power (1326891, the
    -- full 60 s however soon the shield breaks: wowsims ice_barrier.go), which the pack's Ice Barrier line reads.
    ice_barrier = { id = 11426, copy = { 13031, 13032, 13033 }, duration = 60, max_stack = 1 },
    frigid_power = { id = 1326891, duration = 60, max_stack = 1 },
    ice_block = { id = 11958, duration = 10, max_stack = 1 },
})

-- Ice Lance's or Cone of Cold's `now` or `handler`: a Fingers of Frost charge spent (a damage cast). Ice Lance on a
-- Frozen target (a charge up) adds a Winter's Chill stack first (wowsims rolls it at the cast's result, the charge still
-- up; the same shortcut as `chilled`), and sets Fire Blast's cooldown (category 19, 8 s: wowsims ice_lance.go).
-- shortcut: Fire Blast's cast does not set Ice Lance's (no pack casts both); upgrade if one does.
local function lanced()
    return function()
        if buff.fingers_of_frost.up then
            if talent.winters_chill_talent.rank > 0 then
                applyDebuff("target", "winters_chill", nil, min(5, debuff.winters_chill.stack + 1))
            end
            removeStack("fingers_of_frost")
        end
        setCooldown("fire_blast", 8)
    end
end
-- Cone of Cold spends every Winter's Chill stack on the target it lands on (wowsims consumeWintersChill).
local function coned()
    return function()
        if buff.fingers_of_frost.up then
            removeStack("fingers_of_frost")
        end
        removeDebuff("target", "winters_chill")
    end
end
-- Cold Snap: every Frost-only cooldown ends (wowsims cold_snap.go: Frost Nova, Cone of Cold, Ice Block and Ice Barrier).
local function snapped()
    return function()
        setCooldown("frost_nova", 0)
        setCooldown("cone_of_cold", 0)
        setCooldown("ice_block", 0)
        setCooldown("ice_barrier", 0)
    end
end
local function barriered()
    return function()
        applyBuff("ice_barrier")
        applyBuff("frigid_power")
    end
end
local function blocked()
    return function()
        applyBuff("ice_block")
    end
end

spec:RegisterAbilities({
    cone_of_cold = {
        id = 120,
        school = "frost",
        copy = rest(CONE_OF_COLD),
        cast = 0,
        cooldown = 10,
        gcd = "spell",

        spend = frostChanneled(CONE_OF_COLD_COST, CONE_OF_COLD),
        spendType = "mana",

        startsCombat = true,
        known = knows(CONE_OF_COLD),
        usable = unlocked("frost"),

        now = coned(),
        handler = coned(),
        onCrit = mastered(CONE_OF_COLD_COST, CONE_OF_COLD),
    },

    -- 8 s on category 19, shared with Fire Blast (wowsims ice_lance.go; the DB2 holds the category on rank 1 only).
    ice_lance = {
        id = 1312002,
        expects = "travel",
        velocity = 38,
        school = "frost",
        copy = rest(ICE_LANCE),
        cast = 0,
        cooldown = 8,
        gcd = "spell",

        spend = frostChanneled(ICE_LANCE_COST, ICE_LANCE),
        spendType = "mana",

        startsCombat = true,
        known = knows(ICE_LANCE),
        usable = unlocked("frost"),

        now = lanced(),
        handler = lanced(),
        onCrit = mastered(ICE_LANCE_COST, ICE_LANCE),
    },

    ice_barrier = {
        id = 11426,
        copy = rest(ICE_BARRIER),
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        spend = frostChanneled(ICE_BARRIER_COST, ICE_BARRIER),
        spendType = "mana",

        startsCombat = false,
        known = knows(ICE_BARRIER),
        usable = unlocked("frost"),

        now = barriered(),
        handler = barriered(),
    },

    -- Off the GCD; 10 minutes (DB2 RecoveryTime; the pin's row: CooldownMs 600000, no GCD).
    cold_snap = {
        id = 12472,
        cast = 0,
        cooldown = 600,
        gcd = "off",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows({ 12472 }),

        now = snapped(),
        handler = snapped(),
    },

    -- A channel of 8 s, a tick a second (the AoE list's filler: three targets or more).
    blizzard = {
        id = 10,
        copy = rest(BLIZZARD),
        cast = 8,
        channeled = true,
        tick_time = 1,
        cooldown = 0,
        gcd = "spell",

        spend = frostChanneled(BLIZZARD_COST, BLIZZARD),
        spendType = "mana",

        startsCombat = true,
        known = knows(BLIZZARD),
        usable = unlocked("frost"),
    },

    -- No pack line casts these two; a Frost player presses them (wowsims frost_nova.go, ice_block.go; the pin's rows:
    -- Frost Nova 25 s, less Improved Frost Nova's 2 s a rank; Ice Block 300 s, 15 mana, its 10 s self aura).
    frost_nova = {
        id = 122,
        school = "frost",
        copy = rest(FROST_NOVA),
        cast = 0,
        cooldown = function()
            return 25 - 2 * talent.improved_frost_nova.rank
        end,
        gcd = "spell",

        spend = frostChanneled(FROST_NOVA_COST, FROST_NOVA),
        spendType = "mana",

        startsCombat = true,
        known = knows(FROST_NOVA),
        usable = unlocked("frost"),
        onCrit = mastered(FROST_NOVA_COST, FROST_NOVA),
    },

    ice_block = {
        id = 11958,
        cast = 0,
        cooldown = 300,
        gcd = "spell",

        spend = frostChanneled(ICE_BLOCK_COST, ICE_BLOCK),
        spendType = "mana",

        startsCombat = false,
        toggle = "defensives",
        known = knows(ICE_BLOCK),
        usable = unlocked("frost"),

        now = blocked(),
        handler = blocked(),
    },
})

-- The rest of the kit (coverage lane: a manual press costs what it costs and starts its cooldown; no priority casts
-- these, wowsims's sim/mage/ casts none of the buffs): the AoE casts, Blink, the wards and Mana Shield, Frost Blast,
-- Polymorph and the buffs. Ranks, costs, cooldowns and durations from the pin's spell rows (spells_auto_gen.go).
-- Frost Channeling (bit 19) reaches Frost Ward and Frost Blast; Clearcasting and Arcane Power reach Arcane Explosion,
-- Flamestrike, Blast Wave and Frost Blast (the class masks, above). Improved Fire Ward / Frost Warding's reflect and the
-- absorbs' sizes are unmodelled (no damage is predicted).
-- The Cooldown Manager's items: every aura below carries the buff ID the client links (CooldownViewer.lua build).
spec:RegisterAuras({
    -- Blast Wave's slow on the target (6 s)
    blast_wave = { id = 11113, copy = { 13018, 13019, 13020, 13021 }, duration = 6, max_stack = 1 },
    -- the wards and Mana Shield on the player (30 s, 60 s; the pin's rows)
    fire_ward = { id = 543, copy = { 8457, 8458, 10223, 10225 }, duration = 30, max_stack = 1 },
    frost_ward = { id = 6143, copy = { 8461, 8462, 10177, 28609 }, duration = 30, max_stack = 1 },
    mana_shield = { id = 1463, copy = { 8494, 8495, 10191, 10192, 10193 }, duration = 60, max_stack = 1 },
    -- the buffs (1 h, 10 min); Arcane Brilliance's 23028 is the group's
    arcane_intellect = { id = 1459, copy = { 1460, 1461, 10156, 10157, 23028 }, duration = 3600, max_stack = 1 },
    dampen_magic = { id = 604, copy = { 8450, 8451, 10173, 10174 }, duration = 600, max_stack = 1 },
    amplify_magic = { id = 1008, copy = { 8455, 10169, 10170 }, duration = 600, max_stack = 1 },
    -- Frost Blast's slow (9 s; the Forever-only ranks 1326053-5, wowsims's older data)
    frost_blast = { id = 1326053, copy = { 1326054, 1326055 }, duration = 9, max_stack = 1 },
    -- Polymorph on the target (the client's ranks 1320379, 1324187-9; 50 s at the top rank, the pin's 20-50 s ladder)
    polymorph = { id = 1320379, copy = { 1324187, 1324188, 1324189 }, duration = 50, max_stack = 1 },
    -- The talents' target auras, shown by the Cooldown Manager, never applied here (their producers are unseen crits,
    -- chills and interrupts): Ignite's DoT (4 s), Frostbite's root (5 s), Impact's stun (2 s), Improved Blizzard's and
    -- Frost Armor's chill (1.5 s, 5 s), Improved Counterspell's silence (4 s: the 10 s school lockout is the shared one).
    ignite = { id = 412538, duration = 4, max_stack = 1 },
    frostbite = { id = 12494, duration = 5, max_stack = 1 },
    impact_stun = { id = 12355, duration = 2, max_stack = 1 }, -- `impact` is a core identifier
    improved_blizzard_chill = { id = 12484, duration = 1.5, max_stack = 1 },
    chilled = { id = 6136, duration = 5, max_stack = 1 },
    counterspell_silenced = { id = 1324401, copy = { 1329553 }, duration = 4, max_stack = 1 },
})

do
    local ARCANE_EXPLOSION = { 1449, 8437, 8438, 8439, 10201, 10202 }
    local ARCANE_EXPLOSION_COST = { 75, 120, 185, 250, 315, 390 }
    local FLAMESTRIKE = { 2120, 2121, 8422, 8423, 10215, 10216 }
    local FLAMESTRIKE_COST = { 195, 330, 490, 650, 815, 990 }
    local BLAST_WAVE = { 11113, 13018, 13019, 13020, 13021 }
    local BLAST_WAVE_COST = { 215, 270, 355, 450, 545 }
    local MANA_SHIELD = { 1463, 8494, 8495, 10191, 10192, 10193 }
    local MANA_SHIELD_COST = { 40, 60, 80, 100, 120, 140 }
    local FIRE_WARD = { 543, 8457, 8458, 10223, 10225 }
    local FROST_WARD = { 6143, 8461, 8462, 10177, 28609 }
    local WARD_COST = { 85, 135, 195, 255, 320 } -- both wards
    local FROST_BLAST = { 1326053, 1326054, 1326055 }
    local FROST_BLAST_COST = { 40, 65, 90 }
    local POLYMORPH = { 118, 12824, 12825, 12826 }
    local POLYMORPH_COST = { 60, 90, 120, 150 }
    local ARCANE_INTELLECT = { 1459, 1460, 1461, 10156, 10157 }
    local ARCANE_INTELLECT_COST = { 60, 185, 520, 945, 1510 }
    local DAMPEN_MAGIC = { 604, 8450, 8451, 10173, 10174 }
    local DAMPEN_MAGIC_COST = { 100, 200, 300, 400, 500 }
    local AMPLIFY_MAGIC = { 1008, 8455, 10169, 10170 }
    local AMPLIFY_MAGIC_COST = { 150, 250, 350, 450 }
    local MAGE_ARMOR = { 6117, 22782, 22783 }
    local MAGE_ARMOR_COST = { 270, 380, 490 }
    local ICE_ARMOR = { 7302, 7320, 10219, 10220 }
    local ICE_ARMOR_COST = { 240, 320, 410, 500 }
    local FROST_ARMOR = { 168, 7300, 7301 }
    local FROST_ARMOR_COST = { 60, 110, 170 }
    local ARMORS = { "mage_armor", "ice_armor", "frost_armor" }

    -- The wards share a 30 s category cooldown (category 56): each sets the other's.
    local function warded(aura, other)
        return function()
            applyBuff(aura)
            setCooldown(other, 30)
        end
    end
    -- An armor: one up at a time, so a cast ends the other two (the Warlock pack's armored()).
    local function armored(aura)
        return function()
            for i = 1, #ARMORS do
                if ARMORS[i] ~= aura then
                    removeBuff(ARMORS[i])
                end
            end
            applyBuff(aura)
        end
    end
    -- A buff cast on ourselves.
    local function buffed(aura)
        return function()
            applyBuff(aura)
        end
    end
    local function blasted()
        return function()
            if buff.fingers_of_frost.up then
                removeStack("fingers_of_frost")
            end
            applyDebuff("target", "blast_wave")
        end
    end

    spec:RegisterAbilities({
        arcane_explosion = {
            id = 1449,
            school = "arcane",
            copy = rest(ARCANE_EXPLOSION),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(ARCANE_EXPLOSION_COST, ARCANE_EXPLOSION),
            spendType = "mana",

            startsCombat = true,
            known = knows(ARCANE_EXPLOSION),
            usable = unlocked("arcane"),

            now = fingered(),
            handler = fingered(),
        },

        flamestrike = {
            id = 2120,
            school = "fire",
            copy = rest(FLAMESTRIKE),
            cast = function()
                return buff.presence_of_mind.up and 0 or 3 * haste
            end,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(FLAMESTRIKE_COST, FLAMESTRIKE),
            spendType = "mana",

            startsCombat = true,
            known = knows(FLAMESTRIKE),
            usable = unlocked("fire"),

            now = casts(),
            handler = casts(true),
            onCrit = mastered(FLAMESTRIKE_COST, FLAMESTRIKE),
        },

        blast_wave = {
            id = 11113,
            school = "fire",
            copy = rest(BLAST_WAVE),
            cast = 0,
            cooldown = 45,
            gcd = "spell",

            spend = byRank(BLAST_WAVE_COST, BLAST_WAVE),
            spendType = "mana",

            startsCombat = true,
            known = knows(BLAST_WAVE),
            usable = unlocked("fire"),

            now = blasted(),
            handler = blasted(),
            onCrit = mastered(BLAST_WAVE_COST, BLAST_WAVE),
        },

        -- 35% of base mana, 15 s, on the GCD (the pin's row; wowsims blink.go).
        blink = {
            id = 1953,
            -- a move step Hekili never recommends (owner, L844): the wowsims replay keeps it out of the decisions (read by
            -- the replay only)
            movesOnly = true,
            school = "arcane",
            cast = 0,
            cooldown = 15,
            gcd = "spell",

            spend = 0.35,
            spendType = "mana",

            startsCombat = false,
            known = knows({ 1953 }),
            usable = unlocked("arcane"),
        },

        -- shortcut: the mana it drains a point absorbed (wowsims defensives.go registerManaShieldSpell, less with
        -- Arcane Shielding by rank) is unmodelled (no damage taken is); the live mana read corrects it. Upgrade if a
        -- priority casts it.
        mana_shield = {
            id = 1463,
            school = "arcane",
            copy = rest(MANA_SHIELD),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(MANA_SHIELD_COST, MANA_SHIELD),
            spendType = "mana",

            startsCombat = false,
            known = knows(MANA_SHIELD),
            usable = unlocked("arcane"),

            now = buffed("mana_shield"),
            handler = buffed("mana_shield"),
        },

        fire_ward = {
            id = 543,
            school = "fire",
            copy = rest(FIRE_WARD),
            cast = 0,
            cooldown = 30,
            gcd = "spell",

            spend = byRank(WARD_COST, FIRE_WARD),
            spendType = "mana",

            startsCombat = false,
            known = knows(FIRE_WARD),
            usable = unlocked("fire"),

            now = warded("fire_ward", "frost_ward"),
            handler = warded("fire_ward", "frost_ward"),
        },

        frost_ward = {
            id = 6143,
            school = "frost",
            copy = rest(FROST_WARD),
            cast = 0,
            cooldown = 30,
            gcd = "spell",

            spend = frostChanneled(WARD_COST, FROST_WARD),
            spendType = "mana",

            startsCombat = false,
            known = knows(FROST_WARD),
            usable = unlocked("frost"),

            now = warded("frost_ward", "fire_ward"),
            handler = warded("frost_ward", "fire_ward"),
        },

        -- Forever's Frost Blast (a 1.5 s Frostbolt: wowsims's older data; the live Cooldown Manager lists 1326053).
        -- It is not in the pin, so its class mask is unchecked: the Clearcasting, Arcane Power and Frost Channeling
        -- reaches assume Frostbolt's (needs in-game check: learnable, cost). `known` keeps it dormant where the spellbook
        -- lacks it.
        frost_blast = {
            id = 1326053,
            expects = "travel",
            velocity = 28,
            school = "frost",
            copy = rest(FROST_BLAST),
            cast = function()
                return buff.presence_of_mind.up and 0 or 1.5 * haste
            end,
            cooldown = 0,
            gcd = "spell",

            spend = frostChanneled(FROST_BLAST_COST, FROST_BLAST),
            spendType = "mana",

            startsCombat = true,
            known = knows(FROST_BLAST),
            usable = unlocked("frost"),

            now = chilled(),
            handler = chilled(true),
            onCrit = mastered(FROST_BLAST_COST, FROST_BLAST),
        },

        polymorph = {
            id = 118,
            school = "arcane",
            copy = rest(POLYMORPH),
            cast = function()
                return buff.presence_of_mind.up and 0 or 1.5 * haste
            end,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(POLYMORPH_COST, POLYMORPH),
            spendType = "mana",

            startsCombat = true,
            known = knows(POLYMORPH),
            usable = unlocked("arcane"),

            now = casts(),
            handler = casts(),
        },

        arcane_intellect = {
            id = 1459,
            school = "arcane",
            copy = rest(ARCANE_INTELLECT),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(ARCANE_INTELLECT_COST, ARCANE_INTELLECT),
            spendType = "mana",

            startsCombat = false,
            known = knows(ARCANE_INTELLECT),
            usable = unlocked("arcane"),

            now = buffed("arcane_intellect"),
            handler = buffed("arcane_intellect"),
        },

        dampen_magic = {
            id = 604,
            school = "arcane",
            copy = rest(DAMPEN_MAGIC),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(DAMPEN_MAGIC_COST, DAMPEN_MAGIC),
            spendType = "mana",

            startsCombat = false,
            known = knows(DAMPEN_MAGIC),
            usable = unlocked("arcane"),

            now = buffed("dampen_magic"),
            handler = buffed("dampen_magic"),
        },

        amplify_magic = {
            id = 1008,
            school = "arcane",
            copy = rest(AMPLIFY_MAGIC),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(AMPLIFY_MAGIC_COST, AMPLIFY_MAGIC),
            spendType = "mana",

            startsCombat = false,
            known = knows(AMPLIFY_MAGIC),
            usable = unlocked("arcane"),

            now = buffed("amplify_magic"),
            handler = buffed("amplify_magic"),
        },

        -- The armors (the pin's rows: 30 min, on the GCD, no cooldown); Ice and Frost Armor share Frost Channeling's
        -- mask bit 19 (their word 0 0x2080000), Mage Armor not.
        mage_armor = {
            id = 6117,
            school = "arcane",
            copy = rest(MAGE_ARMOR),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = byRank(MAGE_ARMOR_COST, MAGE_ARMOR),
            spendType = "mana",

            startsCombat = false,
            known = knows(MAGE_ARMOR),
            usable = unlocked("arcane"),

            now = armored("mage_armor"),
            handler = armored("mage_armor"),
        },

        ice_armor = {
            id = 7302,
            school = "frost",
            copy = rest(ICE_ARMOR),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = frostChanneled(ICE_ARMOR_COST, ICE_ARMOR),
            spendType = "mana",

            startsCombat = false,
            known = knows(ICE_ARMOR),
            usable = unlocked("frost"),

            now = armored("ice_armor"),
            handler = armored("ice_armor"),
        },

        frost_armor = {
            id = 168,
            school = "frost",
            copy = rest(FROST_ARMOR),
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = frostChanneled(FROST_ARMOR_COST, FROST_ARMOR),
            spendType = "mana",

            startsCombat = false,
            known = knows(FROST_ARMOR),
            usable = unlocked("frost"),

            now = armored("frost_armor"),
            handler = armored("frost_armor"),
        },
    })

    -- The Cooldown Manager's "Mana Gems" item (1318827, a bag item's use spell; not in the pin): a passive registration
    -- only names its ID for the Cooldown Manager map. No ability is made and nothing is tracked (Tracked.lua tracks a
    -- spellbook rank; an item's use is never in the spellbook): the gem's cooldown is Hekili_Shared's mana_gem's.
    spec:RegisterAbility("mana_gems", { id = 1318827, passive = true })

    -- Not registered (one line each): Slow Fall (a reagent utility, no forecast use), Remove Lesser Curse (a dispel:
    -- no curse on us is read), Conjure Food / Water / Mana Gem and the Teleports and Portals (out of combat).
end

-- Talents: { talent tree (1 Arcane, 2 Fire, 3 Frost: the dominant tree picks the spec), rank 1's spell, max rank }:
-- Forever's tree as wowsims/forever's ui/sim/talents/trees/mage.json lists it (tools/wowsims/talents.lua writes it;
-- tests/Forever/talent_trees_spec.lua checks it and the spec detection over it). A key is Classic's where the talent
-- exists there (code reads `talent.<key>.rank`), else the snake_case of the node's name. The cast times read Improved
-- Fireball and Improved Frostbolt, Fire Blast's cooldown Wake of Fire, Scorch Improved Scorch.
spec:RegisterTalents({
    -- Arcane (tree 1)
    wand_specialization = { 1, 6057, 2 },
    improved_channeling = { 1, 11237, 5 },
    arcane_resilience = { 1, 28574, 3 },
    arcane_subtlety = { 1, 11210, 2 },
    magic_absorption = { 1, 29441, 2 },
    arcane_concentration = { 1, 11213, 5 },
    missile_barrage = { 1, 400588, 2 },
    arcane_geometry = { 1, 11247, 2 },
    arcane_impact = { 1, 11242, 3 },
    arcane_blast = { 1, 400574, 1 },
    arcane_shielding = { 1, 11252, 2 },
    improved_counterspell = { 1, 11255, 2 },
    arcane_meditation = { 1, 18462, 3 },
    arcane_wrath = { 1, 1326079, 1 },
    presence_of_mind = { 1, 12043, 1 },
    arcane_mind = { 1, 11232, 5 },
    arcane_instability = { 1, 15058, 3 },
    arcane_power = { 1, 12042, 1 },
    -- Fire (tree 2)
    incineration = { 2, 18459, 5 },
    improved_fireball = { 2, 11069, 5 },
    ignite = { 2, 11119, 5 },
    flame_throwing = { 2, 11100, 2 },
    impact_talent = { 2, 11103, 3 }, -- `impact` is a core identifier (tests/boundary_spec.lua)
    burning_soul = { 2, 11083, 3 },
    improved_flamestrike = { 2, 11108, 3 },
    pyroblast = { 2, 11366, 1 },
    wake_of_fire = { 2, 11078, 2 },
    improved_scorch = { 2, 11095, 3 },
    improved_fire_ward = { 2, 11094, 2 },
    heating_up = { 2, 400624, 1 },
    master_of_elements = { 2, 29074, 3 },
    critical_mass = { 2, 11115, 3 },
    blast_wave = { 2, 11113, 1 },
    fire_power = { 2, 11124, 3 },
    combustion = { 2, 11129, 1 },
    -- Frost (tree 3)
    frost_warding = { 3, 11189, 2 },
    improved_frostbolt = { 3, 11070, 5 },
    elemental_precision = { 3, 29438, 3 },
    ice_shards = { 3, 11207, 5 },
    frostbite = { 3, 11071, 3 },
    improved_frost_nova = { 3, 11165, 2 },
    permafrost = { 3, 11175, 3 },
    frost_channeling = { 3, 11160, 3 },
    improved_blizzard = { 3, 11185, 3 },
    ice_lance = { 3, 1312002, 1 },
    arctic_reach = { 3, 16757, 2 },
    ice_block = { 3, 11958, 1 },
    shatter = { 3, 11170, 3 },
    improved_cone_of_cold = { 3, 11190, 3 },
    cold_snap = { 3, 12472, 1 },
    fingers_of_frost = { 3, 400647, 2 },
    winters_chill_talent = { 3, 11180, 5 }, -- `winters_chill` is upstream's (Engine/Sim/Scripts.lua)
    ice_barrier = { 3, 11426, 1 },
})

-- Pack from the talents (Engine/Schema/Selectors.lua; after the Hekili classic branch's pack selectors). Fire and
-- Frostfire are both Fire's (the tree with the most points): wowsims's Frostfire build is 0/29/22, its Fire build
-- 16/32/3, whose only Frost talent is Elemental Precision; Ice Shards (5/5 in the Frostfire build) marks Frost as the
-- second tree. Any other Fire build runs Fire's default, Fire (wowsims.com).
spec:RegisterSelector("frostfire", { spec = "fire", pack = "Frostfire (wowsims.com)" }, function(tab1, tab2, tab3)
    return tab2 > tab1 and tab2 > tab3 and talent.ice_shards.rank > 0
end)

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and
-- run it, never this block (tests/Forever/mage_spec.lua checks it matches). Each pack's .simc is generated from its
-- wowsims recipe (`make wowsims-packs`, tools/wowsims/specs/mage_*.lua).
spec:RegisterPack(
    "Arcane (wowsims.com)",
    20261110000,
    [[Hekili:9IvuVTTnq4Fl5LmlmdP4SLU1G5hYWA36qBrbuFMsuKu2SMMuGKkgEWW)23rjzzzBkh7eyNhcOjV7((U7Op(LGgH(okMITm0xV)U7F3OrJUd(bfBxwWqXfyYm8eyHeph(9tAcwYwNoyHAHHp3esuZdCwTuOWuxKYk5c7NKOmVb1uWiO4V80F)HhXvHcfpLtPSA7zgspq846u7uyZM9IYvA2Zm96uklhxkSRtF6BFEDkSnSAtak5ro8mrZHmiIwyIWfc4xvNhcRd)HrjdgcXwJLgbqxkSw5WIBwNIPuL8NGfZylnHRt)lSf)Ohom4lF67qqMATfMhJIMWTtlZC0oAptdGycuL9a(9e6947P5KqO4Pv5CbujWelxjnHfAg4Cg2owZW0ebBzIGdz0)EGb)84MSjzHgBN2AXycwisQ)a4RXo01(gZEwrWU9gYZhphlXHfeBIq9hJhDxRVqmzLA2m8WsdlrLNNmHqhpY5YGSY88W5CJb4BsgwRHcByzXQb1(g2LmHZKQfYBjkLGcl29mxITmiOlOzcLIMKxQxETbMPnm9mUCYvgyhAClBU5kJBZ5fQfm9vgA3LUKjS5xzyBoVj6MH5ksPPg3EGTR3Wx3mmjXryiesQhYFtVKC1XiPhowDCvm3K47dFtYdB)C4Odonyvlz6XXxlzdcE1U2xE2D)CUgAacSX6X6d2pxRm2mLW6kv3yXcM0UbzU0yXzCb3UmKjXzcySE7SZ2zG7oCTUlwDzGjz6j8)JrHRb32KV7yBDch4jMUzNDNX22d94)Mg4oh1P75ZLZKHqh7qhofAFeoS6yP0nTxc2906BbRoGlqnefdpmAGaUNsb3RwgNGIwMbF4RvIvA6PO)CZtMO4DGdft0WCvnhJIpZkgYc0Ohm2sKUX)87Wx(wSll(LZklowd)T0X90YbYzDA9Q0T5RNULw7jrzBsSV8M6Rlj1Au3MHEAMDgD7qEBzPsYZo1K(Eq6v)IKV2sF8zRAOlpN(1tLtTcLU8C6HtKtTAOU8u6DNiL6kV6YZQF7ez1gLxxEg979(95EG7Gs3gDAO4kHAU8aI77pXmDFzpEh05raZrvW4iambY)m1U279XHZvc3Bsd3Bre3lxd67f4DQbod77z0T68QmRV3P6k8RYW9Ns1gVnkb7w5FzfH1pd1(xsF6IloIcH9QbviGlTtvWCG)HndWFD6Gp28)cO6y0))]]
)
spec:RegisterPack(
    "Fire (wowsims.com)",
    20261110000,
    [[Hekili:1EvBVTTnq4Fl5lzwygsXU1DRbrdOdBDRdRfdq9ZuMI8KnNLffiPsMhm0V9DuswVyl)w9scGHepYN7549QitiFLeWPgG8LPpm9DtMm5b8psGztgqcYOSv0f4dP014VFuOGI5JEr(IwSw7YKRDS7ztIKYT4eLlsmFkLeniK6mGrc(8h(TF9XyeisWsbNdv7g0SbH)XI5ML4I1R5flvWZGQyohIP5jMI5F4V(ZI54YfZRpEUWZQjT3AK5E8mThnlr7XbiZUdx8n3)wltDgJyROP6eKQC8zPvxcDXCkNlt)o8HvWgTBX8FHAOpoahg95p9veKLgtM(rpVfcZY8ilT92BRoiMivHz03Z4tPt5Xmx8ItjJfj49aLzeYuTBMcWdhrn(zBuYOeQ2u8h1c9z0KKWQxcteAZyRlXhEwYO21glI9hDxLC3MJ7Ukv(s6210uQBI8PdeZKAJtJo(EFVgrJJLSCT)KsCJYJJDxcOIsxeMN5QnyCH)BU)q9b)dWYTBRhQw3DyF7bxvZKk2YAfnTurJ4qPUkpWZ5jPGIgjseMnv68PzBp(ouWAQiv)0mN7ploVD7oUxXIoeVhZHCfSIooxdHY44WfmE1vYzW3FwxqIsKsEyCUAZTceO0GAfYYBei7PfgyT(gXXgUMRlJ)UnGSrOHlG13imufJMwhQvfqDx5P7UUBE22dxCxWtDurpzm8hNMG9EIgoEVElRfAnMGR7MlvQ5AbHruLclsHmA)SLimBVxkDBkuDontkt44dDLuBe)KFNdzrQYcom3Rzf3M6i(kGYdtGnyrMuOIcLCgWB(fI)f4iBVVg)E7TIxodGPnpQxDQrh)83JfbF2DsFroBBUhg6ixjdDqF5bh4sO9j4W2tzs314R6l1(2gNThWf8oKeGTn0iG71d1w5xBB12Wm8LVu2ehsPrjaN8Z7AOqc6PosatH58kbLeCL3yedsJJOJwI0f)R3d)67ITwXBUkR4uo8BXJpGlhjNXohu5und5thGw73M)m95BT29NLOkUkSAiV2RIb86DyX3YqbTuOrkjOS6O1GpH)PTiNDxV94S6SD(NT9)TrioXmeTmVswJvo1Y)z7X)on9S3dTrLLtF01(oB3ql8V7cHVDUKRwf)WLQIMjwUAv8JxOkAML5Q1W7Vqn0oLZvRIjpCH6y3aqxVgowX)UZP0pfz4zIEngkQKGhVgYrgg6aBy3Gu9Rvm5uflSJ9myrZdgK6BysQsTVFrO9s4lRN38fDNQlDBPWQ)dO5MLsfj43HvO7g)oZpw)zKLIj)h]]
)
spec:RegisterPack(
    "Frostfire (wowsims.com)",
    20261110000,
    [[Hekili:1EvxpQnou0Fl9fwIwuYaT0UD0KhAv7SDwTTALY8Sdo23aEXehz7mtPcLF771jqcHphwAbjKtSVN7X3p8XqgsEKeXPwG8Tr3m6Tdho8g8djYUmhir5u2C6uCqgDb(79ALXMk0q5K(pRE2iwy8zQfEUfUuQOChyjfcP9HmsYbX1Kdms0x)WF(5BDarIMj4COE1GHDCFCB5e7m8LRFxqQsdpb6YjCiLwiTLt(W)83LtWxxozBmkeboFAcwGBKaEUjGMlrZtt8Xb()RrL5naXwtZmsKVCCSY5lHPCcLZvz)goyoS04xo5tul92dWH(F9HhrqMzT5MBdcMkSZksC0oyNL6HyIufgtFpJpIoINY8XONwLkKyWGYScvMXpxdOXjuBy(sTkrsn2Y)A9KHmQugx)qSuySdCjNq4jfJ6E3arAy)xvpVFJ5(ZZupNTAbnJ6lv3T30mmI514JFpmWWuA2SbPkwHjCufO95qsrAQVlYg)uHmd00eHuyx6BSyLYDJxD8vOHfurM5UXE9oloVz1g(xZcF47aRWkYM61HJqHgMthuyGyvAA8ugpCOJPNb)WXBdsIuP4XPf6LxlqG2a65ilVsGCwlSWcZvIJlzhpfwCLW0uKSUyOcH(vamdOUSsCr(AdFDV9R8AtEBJALV3d210kBkglrkhN66KxxvmQJ5BAXJtus7UaNGTio42qMURUUxOXg)MwNqnq5Xsyj2xLb1nsvmcWi0uXpaUFrEV1y2zT1q6DamDLPnTMD6Mooo9W()N8h2DkVvnD1hYKlKPEE923GlH(NGlRo1w7vmLsYXr7mR7PLER2JtymLeHNCAqa3rlXD4NXj50Wq8HVvPObz0ejWjFCZzQKOoUJeX0ylMwqjrxyKJyrASJp2cSlpT(RpV2geAJurvjt3wb3pV(47NtLNVMe9bY0NJMw3DeQe7puE(aCEx1VZi)16)DLyRR1IRVful5otLW5K5gV6NME5jemB3v1ZD6m)wsfUqCBgPsQD793z1qCW)Mxi8TIWxSlg)sDrJ88f7I3(cDrJW9f7H39c9Wgj9l2b)XXRt))OK3YOMzBQRg6837pQ)oPeFlUT3pOlWdV5iNV3vJVAPhtkyZve2MwN6Qc1N90CP8tPY0goQ)grlSZuAs0xG5ysb)Rc3V(Fcunn5)o]]
)
spec:RegisterPack(
    "Frost (wowsims.com)",
    20261112001,
    [[Hekili:1EvBVTTnq4Fl9lBXygYrUlnRbvfidBzRfRbdW9ZsMI8KnNPifiPINlk0V9D0YswYwsw1B7lj08UNN749QDOF4NdxWiwi8553o)n(((ZV9w)Wf2Dzq4ImcDdzfEqssX)(KwzSflVzRARHNA8OQ0joL2jueMJO4CUW(bzyCNCAYaA4Ip94V9RpK4ykCXAoJbLQdgA3g4HIL21qXYd3nlrPHxaDXsgKqYfO6p(N)rXs86ILv4Z5ZCgZmlf9(zSmZmsMaH6e7Hh9(lJsozkYSMinc0vz4zLZsCtXscJPKFpEydSZ4vS8xiwYdD4b38Pp8zKK1wBM5HzZwXTRZJDo9StuDcYj6xWDK3szZjZzjupmWPvjCbgxjulxjnEzAabhtSbCkeft0AoONYtcEvCEsIxJl9YZk(4zW(HGYNyScdlvIdOeHiQ8drcUXo1LmdsjssKvPegNbCFYlJAJeQ3fCxnwKqixdBitZnqKkjjAfLf47qS3Js4YvG2GsIkJTnCleBSqPyrj56DxjEugO3GkDD4DG4wi1CDW3hIwbPxh6Ud7ef4iWD)lqeiHuoyEFWRBHujyrgjj7CdFZRkvdlYKorroD92ivBLFLIjtgEOTmnKs4s0e3pPTnoQZ0efn3uAagS)TTLlTU3gDnxi8mwCoq7YcxTOGiPqtW30DCPeU)3v781fPh88ZUg(BGMBrEMm5uJw1vuA25hZgA(kolktTf7oo8OFx74659gEh7cc0aHfjGDyYscDPHRz4ffL4U)OCmHg0xWCGWX7d8BXrFH0Vnk()PY5UjD5QDKigEmvj0yb)lFHOzfFmCboz0GIoznHRzX42MGaW)98(vuGKelaw4phUGQXEAnN4w3muWPAUkIOXZkCXEh2rRfn8)AURZATj(1NqCJ8HtJgU2HmwtBpuU6YjlN5)XEFxDLJA)AoCF97zUJW7oHWkavPtuhCF(XMLUsCvyA1P1vwOsX62Ts2pSWF4AI2BYAeOpzCCzDwu5xSPHF3H70xURC14LlAWa83qfXXLMJL5tt29YC960XY8Pz9(yUEr7yj(nJK4QvWJL377TU4SnUJS0Wnecj(NgPd)FE)8977NFBVVRHwypMjG(32l1x768b3NFXjN(xAEF3l6hXmm)(MZu7OLZzQ)(0dneRLvUW41bgX120OXj521kKYFh2WfC83y80HFcXEXH)d]]
)
