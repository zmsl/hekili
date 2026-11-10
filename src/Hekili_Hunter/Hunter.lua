-- Hekili_Hunter/Hunter.lua
-- The Forever Hunter (Beast Mastery, Marksmanship and Survival, one spec a talent tree: Hekili:NewClass): the Hunter
-- kit with Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build
-- 1.60.1.70338, wowdb), mana under the five-second rule (the Forever Hunter spends mana, never focus), Auto Shot as the
-- ranged clock's anchor (`rangedSwing`, C7), Summon Hawk's guardians (two at most, 18 s each: RegisterPets `cap`, C1),
-- the shared cooldowns (Arcane Shot and Summon Hawk; Aimed Shot and Multi-Shot), Raptor Strike on the next swing,
-- Mongoose Bite's window from the plain usability read, Immolation Trap, Resourcefulness's cheaper strikes and traps,
-- the time to the next main-hand swing (`mainhand_remains`, the weave's Multi-Shot gap), and the default priorities
-- (the wowsims.com packs, translated from wowsims/forever's Melee Weave; no in-game check yet).
-- Research: docs/research/2026-10-15-forever-hunter/research.md and the class-completion research §5.
-- Unmodelled: ranged haste on the auto-shot clock (Rapid Fire, Quick Shots; their haste on Aimed, Multi and Sniper
-- Shot's casts is modelled), the pet and its abilities (D6), Aspect of the Viper and the other runes no priority names,
-- Improved Aimed Shot's +2 s cast, Sniper Shot's range buff, Expose Prey's own Mongoose Bite window (the usability read
-- covers it), Resourcefulness's second effect (1242688: 30 s of 50% mana regen while casting after a critical strike;
-- the mana belief's `mult` hook scales a whole rate, not the spirit part inside the five-second rule).
-- Credits: Hekili (registration API and pack format; the on-next-swing queue read follows the Warrior's Heroic Strike).
-- wowsims/forever (MIT, ui/specs/hunter/dps/apls/default.apl.json, the Melee Weave, and sim/hunter/) is the source of
-- the priorities (tools/wowsims/specs/hunter_*.lua) and the reference for the Summon Hawk, Sniper Shot, Raptor Strike
-- and Mongoose Bite rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase, GetTime = Facade.UnitClassBase, Facade.GetTime
local IsSpellUsable, IsCurrentSpell = Facade.C_Spell.IsSpellUsable, Facade.C_Spell.IsCurrentSpell
local L = Hekili:GetLocale("Hekili_Hunter")

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
            name = L["Beast Mastery"],
            tree = 1,
            icon = 132164,
            role = "attack",
            ranged = true,
            package = "Beast Mastery (wowsims.com)",
            movement = true, -- the pack reads toggle.movement: the weave's move reaches the strikes (R5/R12)
        },
        {
            key = "marksmanship",
            name = L["Marksmanship"],
            tree = 2,
            icon = 132222,
            role = "attack",
            ranged = true,
            package = "Marksmanship (wowsims.com)",
            movement = true, -- the pack reads toggle.movement: the weave's move reaches the strikes (R5/R12)
        },
        {
            key = "survival",
            name = L["Survival"],
            tree = 3,
            icon = 132215,
            role = "attack",
            ranged = true,
            package = "Survival (wowsims.com)",
            movement = true, -- the pack reads toggle.movement: the weave's move reaches the strikes (R5/R12)
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

-- The talents' cost cuts, their percents added (each a SPELLMOD_COST percent: DB2 aura 108, misc 14):
-- - Resourcefulness (440529, a Forever-only Survival talent, 2 ranks): 30% / 60% off the strikes and traps (DB2 mask
--   194: Raptor Strike and Mongoose Bite, Wing Clip, the traps). The DB2 carries only the top rank's -60; the rank-1
--   -30 is wowsims/forever's generated spell data (MIT, sim/core/spelldata/spells_auto_gen.go `440529: {{-30, -60}`).
--   Strider Kick takes it too, as wowsims's log shows (39.6), though its DB2 mask is outside 440529's.
-- - Efficiency (19416, 5 ranks): 3% a rank off the shots, stings and strikes (DB2 mask: Raptor Strike, Mongoose Bite,
--   Wing Clip, Arcane Shot, Multi-Shot, Serpent Sting, Aimed Shot, Summon Hawk, and Strider Kick since hotfix 113554
--   (wowsims: mask word 2 8192 -> 2105344); not the traps, Hunter's Mark, Rapid Fire or the aspects). The DB2 carries
--   the 5/5 -15; wowsims's data `19416: {{-3, -6, -9, -12, -15}}`.
-- wowsims's logs: 2/2 Resourcefulness pays 40 Raptor Strike, 26 Mongoose Bite, 32 Wing Clip, 98 Immolation Trap; 2/5
-- Efficiency 94 Raptor Strike, 75.2 Wing Clip, 178.6 Arcane Shot, 235 Serpent Sting.
local RESOURCEFUL = { 0.3, 0.6 }
local function discounted(price, resourceful, efficient)
    local priced = type(price) == "function" -- decided here: the returned function runs in the state's environment
    return function()
        local c = priced and price() or price
        local off = (resourceful and RESOURCEFUL[talent.resourcefulness.rank] or 0)
            + (efficient and 0.03 * talent.efficiency.rank or 0)
        return c * (1 - off)
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
-- the in-combat calibration replace, as wowsims's logs measure them at 60: hunter_beast_mastery 7.94 a second while
-- casting (Bestial Discipline 2/2's 50% share of 15.88) and 15.88 outside, so spirit 7.94, mp5 7.94 and share 0.5;
-- hunter_marksmanship and hunter_survival 0 while casting and 15.88 outside. Forever's Spirit regen is `6.25 + Spirit/8`
-- a second for every class (wowsims mana.go:75-76), not Classic's formula.
-- Resourcefulness (1242688, DB2 aura 134) and Rapid Recuperation (1242512) are +50% of Spirit regen while casting.
-- shortcut: Rapid Recuperation's share is 25/50% on a Serpent Sting hit and 50/100% on spending Rapid Killing by rank,
-- one aura ID for both (wowsims talents_marksmanship.go:160-200); 0.5 is the common rank; upgrade if a build's rank or
-- source differs.
-- state.spec: the functions run in the state's environment (the file's `spec` is the class).
spec:RegisterResource(
    Enum.PowerType.Mana,
    {
        resourcefulness = { aura = "resourcefulness", share = 0.5 },
        rapid_recuperation = { aura = "rapid_recuperation", share = 0.5 },
    },
    nil,
    {
        fsr = {
            spirit = function()
                return state.spec.beast_mastery and 7.94 or 15.88
            end,
            mp5 = function()
                return state.spec.beast_mastery and 7.94 or 0
            end,
            share = function()
                return state.spec.beast_mastery and 0.5 or 0
            end,
        },
        base = 1720, -- a fraction cost is of base mana (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
    }
)

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
    -- Resourcefulness (talent 440529): a melee or ranged ability's crit gives +50% Spirit regen while casting (the mana
    -- entry). Rapid Recuperation (talent 1223987): the same share on a Serpent Sting hit or spending Rapid Killing.
    resourcefulness = { id = 1242688, duration = 30, max_stack = 1 },
    rapid_recuperation = { id = 1242512, duration = 15, max_stack = 1 },
    -- Mongoose Bite's window after we dodge (Defensive State, 5 s), timed from the plain usability flip (reset_precast).
    defensive_state = { id = 5302, duration = 5, max_stack = 1 },
    -- Raptor Strike queued on the next main-hand swing (C_Spell.IsCurrentSpell, applied in reset_precast).
    raptor_strike = {
        duration = function() -- until the swing that takes it (R13); out of combat no swing runs: a whole one
            -- shortcut: in combat out of melee mainhand_remains is 0 too (the swing stays due), so a strike queued there
            -- also lasts a whole swing; upgrade if the replay shows a strike queued out of melee mattering
            local r = state.mainhand_remains
            return r > 0 and r or state.mainhand_speed
        end,
        max_stack = 1,
    },
    -- The target's debuffs, modelled from our casts (target auras are unreadable in combat).
    serpent_sting = {
        id = 1978,
        copy = rest(SERPENT_STING),
        duration = 15,
        tick_time = 3,
        dot = "debuff",
        max_stack = 1,
    },
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
    -- past a due swing out of melee none comes: wowsims's timer stays due (0) until the walk in lands one
    if not target.within5 then
        return 0
    end
    if mainhand_speed <= 0 then
        return 0
    end -- no swing speed read yet
    return mainhand_speed - (query_time - mh) % mainhand_speed
end)

-- The ranged auto-shot clock (C7): the next Auto Shot and the ranged speed, from the belief's hand 3 (Engine/Sim/
-- State.lua's swings.ranged_*), anchored like mainhand_remains; shots fire from range, so a due one repeats.
spec:RegisterStateExpr("ranged_speed", function()
    return swings.ranged_speed
end)

spec:RegisterStateExpr("ranged_remains", function()
    local r = swings.ranged_projected
    if r == 0 then
        return 0 -- no shot believed yet: no clock, and no wrap (a wrap would forecast a weave open before any shot)
    end
    if now == query_time then
        local real = r - now
        return real > 0 and real or 0
    end
    if query_time <= r then
        return r - query_time
    end
    local speed = swings.ranged_speed
    if speed <= 0 then
        return 0
    end -- no ranged speed read yet (the client raises on x % 0)
    return speed - (query_time - r) % speed
end)

-- The weave window (re-pin design §3a, decision 11; R17: timing only, no walk time): from an Auto Shot whose next
-- main-hand swing comes before the next shot, until that swing or the next shot, whichever comes first (controller
-- ruling, 8b-2 fix round 2): the span a strike can be queued for the swing between two shots (no aura shows it).
-- Opens: the shot's own now() (its observed cast success closes the last shot's span and opens this one when it fits)
-- and the evaluator's false->true edge (the same test). Closes: the evaluator, true from the shot while the main hand
-- has not swung since it and for one ranged speed at most, turns false at the swing or a speed after the shot
-- (`close_on_false`); the next shot's now(); Raptor Strike's now() and handler(). On the shot's own Drain the
-- evaluator answers what the shot's now() decided (`weaveShot`), so a window the shot opened has a true evaluation
-- before its close edge and one it did not open gets no edge. The ranged speed is UnitRangedDamage's (the belief's
-- stat read; the now context has no ranged clock speed). A due main-hand swing (none comes out of melee) counts as
-- before the shot. Its length (owner 2026-11-04) is 1.2 x the ranged shot time at each open, a liberal cap since the
-- window mostly closes on its own: in the belief the evaluator's read (`now_duration`), in the forecast ranged_speed's
-- (`duration`, under state), each written in its own layer as now() and handler() are. The forecast's window (each
-- pack's open_window line, tools/wowsims/specs/hunter_*.lua `extra`) ends at Raptor Strike's handler or that length.
-- (The evaluator and the shot's now() run in the belief's now context: the test is written in each.)
local weaveShot = 0 -- the shot's now(): 1 it opened the window, 2 it did not; the evaluator reads it once (an upvalue)
local weaveCombat = 0 -- the evaluator's last `combat`: its fall to 0 (combat end) clears a weaveShot left unread
spec:RegisterWindow("weave", {
    evaluator = function()
        if combat == 0 and weaveCombat > 0 then
            weaveShot = 0
        end
        weaveCombat = combat
        if weaveShot > 0 then
            local opened = weaveShot == 1
            weaveShot = 0
            return opened
        end
        local shot, last, rs = lastSwing(3), lastSwing(1), stat("UnitRangedDamage")
        return shot > 0
            and rs > 0
            and mainhand_speed > 0
            and now - shot < rs
            and last < shot
            and last + mainhand_speed <= shot + rs
    end,
    close_on_false = true,
    duration = function()
        return 1.2 * swings.ranged_speed -- ranged_speed's read
    end,
    now_duration = function()
        return 1.2 * stat("UnitRangedDamage")
    end,
})

spec:RegisterAbilities({
    -- The ranged auto attack: its success is the ranged hand's shot (C7; whether Forever sends it per shot is a
    -- checkpoint). Never recommended.
    auto_shot = {
        id = 75,
        expects = "travel",
        velocity = 40,
        school = "physical",
        cast = 0,
        cooldown = 0,
        gcd = "off",
        rangedSwing = true,

        startsCombat = true,
        known = knows({ 75 }),

        -- the shot ends the last shot's weave and opens its own when it fits (the weave window above)
        now = function()
            closeWindow("weave")
            local last, rs = lastSwing(1), stat("UnitRangedDamage")
            weaveShot = 2
            if rs > 0 and mainhand_speed > 0 and last < now and last + mainhand_speed <= now + rs then
                openWindow("weave")
                weaveShot = 1
            end
        end,
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

    -- the Beast Mastery talent (DB2 19574: 2 min, free, off the GCD); its 18 s rage is the pet's, so no player aura
    bestial_wrath = {
        id = 19574,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        toggle = "cooldowns",
        startsCombat = false,
        known = knows({ 19574 }),
    },

    serpent_sting = {
        id = 1978,
        expects = "ticks",
        school = "nature",
        velocity = 40, -- its debuff dot aura: 3 s over 15 s
        copy = rest(SERPENT_STING),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = discounted(cost(SERPENT_STING_COST, SERPENT_STING), false, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(SERPENT_STING),

        now = applies("serpent_sting", true),
        handler = applies("serpent_sting", true),
    },

    arcane_shot = {
        id = 3044,
        expects = "travel",
        velocity = 40,
        school = "arcane",
        copy = rest(ARCANE_SHOT),
        cast = 0,
        -- Improved Arcane Shot (19454): -0.3 s a rank (wowsims's curve; DB2 has only rank 1's row)
        cooldown = function()
            return 6 - 0.3 * talent.improved_arcane_shot.rank
        end,
        gcd = "spell",

        spend = discounted(cost(ARCANE_SHOT_COST, ARCANE_SHOT), false, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(ARCANE_SHOT),

        now = shares("summon_hawk"),
        handler = shares("summon_hawk"),
    },

    -- The dive, then a hawk for 18 s (wowsims summon_hawk.go).
    summon_hawk = {
        id = 1293241,
        expects = "none", -- a summon has no damage row: a velocity would open a flight ticket that never pays
        copy = rest(SUMMON_HAWK),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = discounted(cost(SUMMON_HAWK_COST, SUMMON_HAWK), false, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(SUMMON_HAWK),

        now = shares("arcane_shot", true),
        handler = shares("arcane_shot", true),
    },

    aimed_shot = {
        id = 19434,
        expects = "travel",
        velocity = 40,
        school = "physical",
        copy = rest(AIMED_SHOT),
        cast = rangedCast(2),
        cooldown = 6,
        gcd = "spell",

        spend = discounted(cost(AIMED_SHOT_COST, AIMED_SHOT), false, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(AIMED_SHOT),

        now = shares("multi_shot"),
        handler = shares("multi_shot"),
    },

    -- 13.9% of base mana (DB2 PowerCostPct): a fraction of the mana meta's `base`.
    multi_shot = {
        id = 2643,
        expects = "travel",
        velocity = 30,
        school = "physical", -- pays the pinned target's row only
        cast = rangedCast(0.5),
        cooldown = 6,
        gcd = "spell",

        spend = discounted(0.139, false, true),
        spendType = "mana",

        startsCombat = true,
        known = knows({ 2643 }),

        now = shares("aimed_shot"),
        handler = shares("aimed_shot"),
    },

    sniper_shot = {
        id = 1310687,
        expects = "travel",
        velocity = 60,
        school = "physical",
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

        spend = discounted(cost(RAPTOR_STRIKE_COST, RAPTOR_STRIKE), true, true),
        spendType = "mana",

        startsCombat = true,
        onNextSwing = true,
        known = knows(RAPTOR_STRIKE),

        usable = function()
            return not buff.raptor_strike.up, "a strike is already queued"
        end,

        -- the weave's strike ends its window: in the belief at the real cast, in the forecast at the simulated one
        -- (written apart: the owner's rule, never one function for both)
        now = function()
            closeWindow("weave")
        end,

        handler = function()
            applyBuff("raptor_strike")
            closeWindow("weave")
        end,
    },

    mongoose_bite = {
        id = 1495,
        copy = rest(MONGOOSE_BITE),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = discounted(cost(MONGOOSE_BITE_COST, MONGOOSE_BITE), true, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(MONGOOSE_BITE),

        usable = function()
            return buff.defensive_state.up, "only usable after dodging"
        end,

        now = removes("defensive_state"),
        handler = removes("defensive_state"),
    },

    -- Forever-only (D4): 5.81% of base mana (DB2 PowerCostPct): a fraction of the mana meta's `base`.
    strider_kick = {
        id = 1317257,
        cast = 0,
        cooldown = 8,
        gcd = "spell",

        spend = discounted(0.0581, true, true),
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

        spend = discounted(cost(WING_CLIP_COST, WING_CLIP), true, true),
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

        spend = discounted(cost(IMMOLATION_TRAP_COST, IMMOLATION_TRAP), true, false),
        spendType = "mana",

        startsCombat = false,
        known = knows(IMMOLATION_TRAP),
    },
})

-- Talents: { talent tree (1 Beast Mastery, 2 Marksmanship, 3 Survival: the dominant tree picks the spec), rank 1's
-- spell, max rank }: Forever's tree as wowsims/forever's ui/sim/talents/trees/hunter.json lists it (tools/wowsims/talents.lua
-- writes it; tests/Forever/talent_trees_spec.lua checks it and the spec detection over it). A key is Classic's where the
-- talent exists there (code reads `talent.<key>.rank`), else the snake_case of the node's name. The costs read Efficiency
-- and Resourcefulness.
spec:RegisterTalents({
    -- Beast Mastery (tree 1)
    deadly_aspects = { 1, 19552, 5 },
    endurance_training = { 1, 19583, 5 },
    focused_fire = { 1, 1223755, 2 },
    improved_aspect_of_the_monkey = { 1, 19549, 3 },
    improved_revive_pet = { 1, 24443, 2 },
    pathfinding = { 1, 19559, 2 },
    bestial_swiftness = { 1, 19596, 1 },
    unleashed_fury = { 1, 19616, 5 },
    improved_mend_pet = { 1, 19572, 2 },
    ferocity = { 1, 19598, 5 },
    summon_hawk = { 1, 1293241, 1 },
    spirit_bond = { 1, 19578, 2 },
    intimidation = { 1, 19577, 1 },
    bestial_discipline = { 1, 19590, 2 },
    frenzy = { 1, 19621, 5 },
    bestial_wrath = { 1, 19574, 1 },
    -- Marksmanship (tree 2)
    hawk_eye = { 2, 19498, 3 },
    improved_concussive_shot = { 2, 19407, 5 },
    lethal_attacks = { 2, 19426, 5 },
    improved_stings = { 2, 1310661, 3 },
    efficiency = { 2, 19416, 5 },
    careful_aim = { 2, 1223984, 5 },
    rapid_killing = { 2, 415405, 2 },
    improved_arcane_shot = { 2, 19454, 5 },
    lone_wolf = { 2, 415370, 1 },
    trueshot_aura = { 2, 1299346, 1 },
    mortal_shots = { 2, 19485, 5 },
    rapid_recuperation = { 2, 1223987, 2 }, -- wowsims's Marksmanship (spell_data_auto_gen.go:401); the DB2 names the spell only
    barrage = { 2, 19461, 3 },
    scatter_shot = { 2, 19503, 1 },
    ranged_weapon_specialization = { 2, 19507, 5 },
    sniper_shot = { 2, 1310687, 1 },
    -- Survival (tree 3)
    improved_tracking = { 3, 24293, 5 },
    deflection = { 3, 19295, 5 },
    entrapment = { 3, 19184, 5 },
    savage_strikes = { 3, 19159, 2 },
    survivalist = { 3, 19255, 5 },
    improved_wing_clip = { 3, 19228, 3 },
    clever_traps = { 3, 19239, 2 },
    surefooted = { 3, 19290, 3 },
    deterrence = { 3, 19263, 1 },
    survival_tactics = { 3, 19376, 2 },
    predators_edge = { 3, 1310627, 5 },
    counterattack = { 3, 19306, 1 },
    resourcefulness = { 3, 440529, 2 },
    expose_prey = { 3, 1310532, 2 },
    survivalists_discipline = { 3, 1310496, 2 },
    strider_kick = { 3, 1317257, 1 },
    lightning_reflexes = { 3, 19168, 5 },
    lacerating_strikes = { 3, 1310533, 1 },
})

-- Beast Mastery's HHA (re-pin ruling R15; wowsims bm_weave's default_hawks APL at e2842f0a78: a sequence of Summon
-- Hawk, Summon Hawk, Arcane Shot under "Use Summon Hawk" and "Use Arcane Shot", reset when complete): a stepped window
-- that loops, open for the fight ("combat": no timer). Its evaluator is the fight (`combat`), not a constant: a held
-- true opens once ever, since combat end closes every window and keeps the last evaluation. On the kit: a tree's own
-- registration would land in the kit's table anyway (a tree reads its fields through the kit), and only Beast
-- Mastery's pack reads it.
spec:RegisterWindow("hha", {
    evaluator = function()
        return combat > 0
    end,
    duration = "combat",
    steps = { "summon_hawk", "summon_hawk", "arcane_shot" },
    loop = true,
})

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and
-- run it, never this block (tests/Forever/hunter_spec.lua checks it matches). Each pack's .simc is generated from its
-- wowsims recipe (`make wowsims-packs`, tools/wowsims/specs/hunter_*.lua).
spec:RegisterPack(
    "Beast Mastery (wowsims.com)",
    20261110000,
    [[Hekili:LVvutUPnq4Fl3lU2tVIp7lxAYn13mntBNKon30PK(kyzq2Oya5bjo3BMm8BVRW2yHSbldI8c5bhojTF7NwjT7YQbNjoFXX2hXXopp9UPVDYKj3b)ZXM)6gSJ9gK3A0k4Hyue87hWigpB(NHFXjVMnF4w6wgjIz5rJgjg9RHuKVaXfPKq(NIDwCwWzBWEo2F8FF(l)()84cbOUr7W0XoG47J3jiM5DbD(y2CEaoB((2gVKMGFbNKn3hVeLgcY9R)9FLnhAoB(jaLsglicBCqAm00y)nSXcE7d)xK7wm6fSfGA4OBbTKGIzHWmXhEMk0kHLnh57tJ)b4H14xzwzZ)neh94zyZWp)PVaGeW5BypoE8kcpiDHycmwzOJamboIFa9Ep)POP(l9Sa7AcDjjeS)ipoHgZS2KGbHxG4Z2rDgy(swFlz5SB8XlsxU0sUDR0nz)5jI(JZgJetFUlDPlyeDdqB3broaN2NmmZsqBi(Uljj4BtzyyylDx55pBIaaokzfMBrt5mIp(HbCse(PzpuimOzCyAmM5gswfWpda7eyGcqYaSiKsb9NM8AZehSn4K1K4vnuCgNGcD3MG4bncbFCenM45Ma2Hgbqe6R0ey5ng5UHkASrOuA7ZsQxkB2uD2gbIc7a4ady8eYA1PWoKK3mSf2YtIlPBHK(4e31eV11psWuTIsbnSGWX1pusuefoMc)LlCKDt9dElS(76fsYh2WB21HLmVSwht3g)THv21apkn0hEOCFj4iejM90eRhgnAqn2aCYgCmhSIITIsMTdlaLgaScOSy(UsGLct(4IZXWSdiMvqaYkg)FClPULLcL4HIXUSak)Csj1DD6ocC2skaPMbwRJd6QvHyRi6l4iyspyOWigGI9D3Bp)LIgaVty)FsSdFWWBgwS2jX29lDNPdsSl4nFfE0GHdZF4i(ZU7BLB5PzhgYonw(Vkp2rJgPkDPrFhmGrTWBypW6C1U47B2eDIB17Sj6fmUNzw0mdJEMv5AsBQNzAAqUi9ml01KQupZ0OK)xpB2Fnj1EZqvIvMxkwgvlNjZGS1uPTPRzwc0GCJmmbAuIigLdnlQVrPqlcXAuE0(4zgLoTi4Hr5r9EQnQQ0TerkCODmO2sm1zA60su1zQ6CL4QZu23TsK1zZaLZDftHJvdBpnpPOvo2VaHuGbRC7fHegNLFTj7UKb4XNZVgfCmAri235do2sB2fDUVY9o2hZuWX2lb2RKqqo2vuXChoOznbwodGsqF(IalG(EnH(yKDnb(n6cCreBnb(bTbwksSMy)wnXwocRMq)ZAc9jro1e)3PG)rHQOo(hvPCho25oLf75aqFFLGwUC2fsnP2D9hdeiaFYDkOFyKYUiQrNciupYvyfLDfFbmupDDadfFSxaf1dshqPW5PS815eT1ErpLBQNfpDVXLUIbPfh5rkTUl0J6rZczo6Nvw51C5e5WPEA8aCsEZRdUAU1IC4vprwS3Pi5OQDpVdb1ZCxPd)o4fKV(3qULVI8LFhz5aztuDO04iz9dBxEWFv3KnmeDpYIPBIyxi3JEKft3mmVCsv9iJMU5oFXSf7r2mDFTa9sdUhz4uZTsNC46jMhDYnDQjtMSNyxfMTRmj5EKLXSj)36AUwQErDvA2TML5LCQBsO1mCRBsD0mCRZssZm0RRshYmSRtt8Wmu0aH4Bpr0jy69DyW02pdeeSDHTmdhQUISM9IoAuXxVxnerXYEvfF1SCgOWBQQ(Vvx8wZZHQkGCDf)18SOQsq)9V4XMFUvvHXRWxH23nhaox8zXS)tzX5mxa3bvv(coo1TQ6nJWp9k3kynt9tIPeGv)zZKtxGWOuEanXX(J41Kqs28H)X(V6N8UD())]]
)
spec:RegisterPack(
    "Marksmanship (wowsims.com)",
    20261110000,
    [[Hekili:9MvxVTQrq0Fl5LuB1ui2T(2CJKVsTQT6ER6nQQK(k41SdWwdSODxIvKQ43EN1FcRn4TetYdry2zoZHDyoZSc)j(p77rjkW)PP3p9dtMm5E8pFp1RfGVxbjCfjgViNKH))ReXkzgjxMWkQwmAnFTKLjDc5zJ12(AkNq14TSKLQ(sU)YZcTSac99(8F)0Z)6F9ywni99syukS1pqg2zaFSAHkbQwS7EUrCb8ciQwqHiszQQAXp9N)r1c82vlmGPK5Q5G0nPmxbcxAH0vtzQ0nllynqEbCqmthFhgdb6wk(qqXR56yYKvliukp)BWlwbVkDQw8lef5XZWLrF9lpJGKOufYhDDJzQKYLA67Ay6yetKYWmYhdPtjtPrHo4wQGhXsXnEsOIXZLofcaDEjrnFl1Lb69V7yrZVHcllJICQFFNYIQF)ex)25Ue9JVkGhfGBHbjK1BHydaNUwDyMlifmAqeta3vkb0SOG4q68jAauermOC4LkjJcZo4egriTmhKbPS4e1zCKLbFA(SB7aGLPCog3sXR9ZDCpbeRy5X9YDkKXZzHbc8POxaKr(hUatk5KGcU(M9cLgj9iEyPC(uBs(ORyEtHmqQeSvMpcBrQEkCn(IklVrS1EsbrWkw4QUTe3QI5CmclzkOBtzzzCS4c)vawOv0TXRXSxqykBJzJUz7co15LZQC(68)DuRlDBiNNsXlAUMaYiSC5NM4mB84B7ypaefqUc3f1VivBBBFcOHbygWiz(qDWiIqsoeit4QtlEAyzgkNXSXWolo5XXPGtg)fidP4T3mcv2IbAW(h(57(nw)d0VBK(MjK89)(Wp3z(4X9O8EiPGvcedkbSrIzijGLIudjf()iZnK8OhfQdjDml1hYyziwmKHY2EkgC4TXGo7jnyr60EAdwOoxpXblyVB9uVYpb(E4qZsKqgNTiLjvYnhPz7PaWlFAZrCGCYYuG6)Z(E1ErvV4UHR99o2903luG5zbJGheQ54y(kmIwcy9UInG88t6PH(7Te6JD7Se4FWwGp0fZsGNzjW17ozj0FWsOpPRJL4)Jg4F0PwgO(yiRVGV3gXo97fiOp0kOnNR8Gxt68nYJcSAW)Ob47nSELxhHeryY9TardfUlGHzf1EmmKUUakMLr7r5GMuD)7sB6nloDk3mRdp9vJlnQFTKtDlRL21XXSSCVp1MyODXOh2aHzb4He6HbbUec2wN1Ia51EeJnCYS2S3ASdc7mlY7Pm9GWntnIEQ0peCBQP4tVBwmiSZ2bfSRFZGqrtntB0LU6eXgLTPMkOxsz7QZsnjAtETfTXbHdM6ZThV3w061aftn1(V4efxxoRPGPu)LNi56ZbtbDBMO56ZI2gV79FIOR9ZMs)Xm29bio3zYo)C1xEG8ZCASdcnsZpKrdaB)JDSHUiHjLQeUW37ZWkwkRAXOFB33QzZY()h]]
)
spec:RegisterPack(
    "Survival (wowsims.com)",
    20261110000,
    [[Hekili:LR13poQnq4)w2xsjQBjBY296ERAwPw1wDxv7QtLTVcXbBsCdGr2MeTsN4V9oM8lWjqCa27fUhorGXFZN)S9mdZI7y3xDDWijX9Lj3n5dJhp(o4FUoY3siUoji)vOfWfXOi4)Ds5RPRrHzZS2W2iOrcBFw0qLDVfYqyfwZtPHYph7o)SWksi(UoF6FF51F)FEsSdoxNLumMSDmeHFLo6PSzYLKSz7U3OagNSMWZMHjbO0qz2SF5l)v2m42zZkarkDKYVIrltJLe(iCIyKIMyXiXAVne0AInGx4WBb85OyriqCmCnt5pQiBgcJzXFhCXkYBc7Sz)gsIE6m8W6V)8RailLYeXtJgTGkxMoxr9rAMoeWeOl5b0h9XtqtWb(2GmYzb0qqOr(sklwyNWjWGNJKt3sDHxeIV6wAW0BWK5Pbb2fVVDAs2FEYq)(PJqQPV0Jf4bYN3s0MTqKdWPpRimt5Oek2lGYj3MkiGzbEl8XthRaqI4lisBwQuqXKhgiPrKNN(WHbdEMeMgteEH0flLNbGTdyGgqfbyEiJb(pL)wZgoOne(kA8IgnCmjIft994WSOraeH(pghwCIrEjm1nBekLw8dy(PIPtmztamuy9tcmqi50v6tHTivCPCdSHLgxY3QrIjCVvu)v1BjivlymWdZPss9MsJIyWHm4xEWbUK6nEdS655hsZnZ6MTpWUiVSxfZ2e)vRkF0aFgledxu(zCseIglEES9ddhoOgnGWtiXsqfvBKkiB7xakzaScOTy(yrWqCFumXtSKjp9qujlJGqAutmS2dPSflcj2rS1KiGIdSut5LOyS3Uz)pF4gqKac(hu7hhyDJ1bLUaH3j0N5b0ypiY5cYWbww5xCe)P391Y355P7nzRhl)RY2oC4q9rxY67adg2Iip9a15QdN230etYr0Z0edt81ZuLRjBEptAAqkYEMcPN3VNn91kMPNn7VMk0UXsNyL5LMYORCDz5qTMkTT2JULanirFNsGMLvTtPqlsH1P8O95l6u6CHGZDQVQpsyN6ktF7Fno0oguB3dE380PDF4DZvNR7fVBo7Bw3p64zGRZAiClqiToahsfsrEtN32Zw4YxYBcnjgnpKGD)vxNcBuvpCx7qDDoMf11XNdRZCkY1PI2q6kbpBiWfZowc6Z3Bof03Bi0hZ6ziW)OPaFiBMHa)GHaxmlLHq)bdH(KSpgI)pPH)Xbvrlqp6YIpW1jpONAFba6JvcA5obEyuJRDN5XaTkW)Og47nS4jWACjGW47QaIsr6Uag6NS2JHwiSlGI(XO9OCi2uXXxxmQwhK6uUPFo80TgxQ5SfwCkAzHLDLF0pwUFmfQCO6GspMdH(bWdlOhki4siy65Skcu(o8sxx)BD1Yx76YV3vXeaJ1JC04ma9dTlxZ0dm2WuB9iftpAFdZz3FuSj6j3ACXi9inZ0YKnRkREKWPx)Ij1i0tKhtQ9zIEnwxQ2NEI2PKMQklSIA66rkJPVUPz1Q262IvQTaMwh91wvyRzzo7mTM1RR(RUHBgxB4vvPt3WntRc7ARPOty39MwXtJYE3nuuVaJgKNS9eXKms3xvhjmmJu7zPIevLw0Sy)Ddh0Z)uT)AN3AutWUVQoEuzxW6woROGEO(dlsv2fTUNd6b03ZH66cx3Zc9q37zX3(U411ZnP6tNE3N7S7z(7jSFMwUxWxUjYYt)liCiqJq)ZMUeGv)PvNtxGWOu5sg315tKv0qA2mR)y3xgE(JD)))]]
)

-- The hand-built lists the wowsims.com packs replaced: a saved choice of one falls back to the spec's default.
spec:RetirePacks({ "BeastMastery", "Marksmanship", "Survival" })
