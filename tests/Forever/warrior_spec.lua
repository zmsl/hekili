-- tests/Forever/warrior_spec.lua: the Forever Warrior class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through a recording stand-in for Hekili (helpers/load_warrior.lua). What Hekili
-- does with them is verified in game (the plan's checkpoint).
local lw = require("Forever.helpers.load_warrior")

-- key = { spell IDs in rank order, cost in rage with every talent at rank 0, cooldown, gcd }, from the DB2 (the cost
-- column / 10; the cooldown is the larger of RecoveryTime and CategoryRecoveryTime; gcd "off" where StartRecoveryTime
-- is 0).
local KIT = {
    battle_shout = { { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, 10, 0, "spell" },
    battle_stance = { { 2457 }, 0, 1, "off" },
    berserker_rage = { { 18499 }, 0, 30, "spell" },
    berserker_stance = { { 2458 }, 0, 1, "off" },
    bloodrage = { { 2687 }, 0, 60, "off" },
    bloodthirst = { { 23881, 23892, 23893, 23894 }, 30, 6, "spell" },
    challenging_shout = { { 1161 }, 5, 600, "spell" },
    charge = { { 100, 6178, 11578 }, 0, 15, "off" },
    cleave = { { 845, 7369, 11608, 11609, 20569 }, 20, 0, "off" },
    concussion_blow = { { 12809 }, 10, 45, "off" },
    death_wish = { { 12328 }, 10, 180, "spell" },
    defensive_stance = { { 71 }, 0, 1, "off" },
    demoralizing_shout = { { 1160, 6190, 11554, 11555, 11556 }, 10, 0, "spell" },
    disarm = { { 676 }, 20, 60, "spell" },
    execute = { { 5308, 20658, 20660, 20661, 20662 }, 15, 0, "spell" },
    hamstring = { { 1715, 7372, 7373 }, 10, 0, "spell" },
    heroic_strike = { { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }, 15, 0, "off" },
    intercept = { { 20252, 20616, 20617 }, 10, 30, "off" },
    intimidating_shout = { { 5246 }, 25, 180, "spell" },
    last_stand = { { 12975 }, 0, 180, "off" },
    mocking_blow = { { 694, 7400, 7402, 20559, 20560 }, 10, 120, "spell" },
    mortal_strike = { { 12294, 21551, 21552, 21553 }, 30, 6, "spell" },
    overpower = { { 7384, 7887, 11584, 11585 }, 5, 5, "spell" },
    piercing_howl = { { 12323 }, 10, 0, "spell" },
    pummel = { { 6552, 6554 }, 10, 10, "spell" },
    recklessness = { { 1719 }, 0, 1800, "spell" },
    rend = { { 772, 6546, 6547, 6548, 11572, 11573, 11574 }, 10, 0, "spell" },
    retaliation = { { 20230 }, 0, 900, "spell" },
    revenge = { { 6572, 6574, 7379, 11600, 11601, 25288 }, 5, 5, "spell" },
    shield_bash = { { 72, 1671, 1672 }, 10, 12, "spell" },
    shield_block = { { 2565 }, 10, 5, "off" },
    shield_slam = { { 23922, 23923, 23924, 23925 }, 20, 6, "spell" },
    shield_wall = { { 871 }, 0, 900, "spell" },
    slam = {
        { 1240193, 1464, 8820, 11604, 11605, 1310196, 1310197, 1310198, 1310199, 1310200 },
        15,
        18,
        "spell",
    },
    spearing_strike = { { 1310222 }, 15, 20, "spell" },
    sunder_armor = { { 7386, 7405, 8380, 11596, 11597 }, 15, 0, "spell" },
    sweeping_strikes = { { 12292 }, 30, 30, "off" },
    taunt = { { 355 }, 0, 8, "off" },
    thunder_clap = { { 6343, 8198, 8204, 8205, 11580, 11581 }, 20, 6, "spell" },
    victory_rush = { { 402927 }, 0, 30, "spell" },
    whirlwind = { { 1680 }, 25, 10, "spell" },
}

-- key = { definition spell, max rank } of each of the 52 live talent nodes (ForeverProbe export, client 1.60.1.70374,
-- 2026-10-15: 17 Arms, 17 Fury, 18 Protection by the nodes' columns). Every owned multi-rank node reported its rank 1
-- spell at its current rank, so no rank aliases; Iron Will and Defiance define themselves by a higher DB2 rank's ID.
local TALENTS = {
    anger_management = { 12296, 1 },
    bloodthrill = { 1289682, 5 },
    deep_wounds = { 12834, 3 },
    deflection = { 16462, 5 },
    impale = { 16493, 2 },
    improved_charge = { 12285, 2 },
    improved_hamstring = { 12289, 3 },
    improved_heroic_strike = { 12282, 3 },
    improved_overpower = { 12290, 2 },
    improved_rend = { 12286, 3 },
    improved_slam = { 12862, 2 },
    improved_tactical_mastery = { 12295, 5 },
    mortal_strike = { 12294, 1 },
    spearing_strike = { 1310222, 1 },
    sweeping_strikes = { 12292, 1 },
    two_handed_weapon_specialization = { 12163, 3 },
    weaponmaster = { 1290261, 5 },
    blood_craze = { 16487, 3 },
    bloodthirst = { 23881, 1 },
    booming_voice = { 12321, 5 },
    cruelty = { 12320, 5 },
    death_wish = { 12328, 1 },
    dual_wield_specialization = { 23584, 5 },
    enrage = { 12317, 5 },
    flurry = { 12319, 5 },
    furious_precision = { 1323963, 3 },
    gore_drinker = { 1323967, 2 },
    improved_berserker_rage = { 20500, 2 },
    improved_execute = { 20502, 2 },
    improved_intercept = { 20504, 2 },
    lingering_rage = { 1323964, 5 },
    piercing_howl = { 12323, 1 },
    raging_blows = { 1310315, 1 },
    unbridled_wrath = { 12322, 5 },
    anticipation = { 12297, 5 },
    one_handed_weapon_specialization = { 16538, 5 }, -- "Bastion" on Forever
    concussion_blow = { 12809, 1 },
    defiance = { 12792, 3 },
    focused_rage = { 29787, 3 },
    improved_bloodrage = { 12301, 2 },
    improved_disarm = { 12313, 3 },
    improved_revenge = { 12797, 3 },
    improved_shield_bash = { 12311, 2 },
    improved_shield_wall = { 12312, 2 },
    improved_sunder_armor = { 12308, 3 },
    improved_thunder_clap = { 12287, 3 },
    iron_will = { 12962, 5 },
    last_stand = { 12975, 1 },
    master_of_defense = { 1310316, 2 },
    shield_slam = { 23922, 1 },
    shield_specialization = { 12298, 5 },
    vanguard = { 1310317, 1 },
}

local function rank(n)
    return setmetatable({}, {
        __index = function()
            return { rank = n, enabled = n > 0 }
        end,
    })
end

local function idsOf(a)
    local ids = { a.id }
    for _, v in ipairs(a.copy or {}) do
        ids[#ids + 1] = v
    end
    return ids
end

describe("Forever Warrior", function()
    local w

    before_each(function()
        w = lw.load()
    end)

    it(
        "registers the Classic kit plus Victory Rush and Spearing Strike with the DB2's ranks, costs and cooldowns",
        function()
            local e = lw.env(w)
            local n = 0
            for key, a in pairs(w.abilities) do
                n = n + 1
                local want = KIT[key]
                assert.is_not_nil(want, "unexpected ability " .. key)
                assert.are.same(want[1], idsOf(a), key)
                assert.are.same(
                    { want[2], want[3], want[4] },
                    { lw.run(a.spend, e) or 0, lw.run(a.cooldown, e), a.gcd },
                    key
                )
                assert.are.equal("function", type(a.known), key)
            end
            assert.are.equal(41, n)
            assert.are.equal(1.5, w.abilities.slam.cast)
            assert.is_true(w.abilities.heroic_strike.onNextSwing and w.abilities.cleave.onNextSwing)
        end
    )

    it("models the talent-modified costs from rank 1's value x the rank, Focused Rage on the offensive ones", function()
        local e = lw.env(w)
        e.talent = rank(2)
        local function at(key)
            return lw.run(w.abilities[key].spend, e)
        end
        -- Focused Rage -3 a rank; Raging Blows -3 (Cleave, Whirlwind); Improved Heroic Strike -1, Improved Execute -5,
        -- Improved Sunder Armor -3, Improved Thunder Clap -6 a rank; floored at 0
        assert.are.same({ 7, 8, 0, 3, 2, 13, 0, 24, 10 }, {
            at("heroic_strike"),
            at("cleave"),
            at("execute"),
            at("sunder_armor"),
            at("thunder_clap"),
            at("whirlwind"),
            at("overpower"),
            at("mortal_strike"),
            at("battle_shout"),
        })
        assert.are.same({ 8, 7 }, { lw.run(w.abilities.taunt.cooldown, e), lw.run(w.auras.shield_block.duration, e) })
    end)

    it("gates Spearing Strike on its talent, and Charge on Defensive Stance with Vanguard", function()
        local e = lw.env(w)
        assert.are.equal("spearing_strike", w.abilities.spearing_strike.talent)
        e.buff = setmetatable({ defensive_stance = { up = true } }, getmetatable(e.buff))
        assert.are.equal("battle_stance", lw.run(w.abilities.charge.buff, e))
        e.talent = rank(1)
        assert.are.equal("defensive_stance", lw.run(w.abilities.charge.buff, e))
    end)

    it("gates Charge on being out of combat and outside melee range, not LibRangeCheck", function()
        local e = lw.env(w)
        e.target.minR = 100 -- what LibRangeCheck leaves on Forever: nothing resolved
        e.action = { rend = { in_range = false } }
        assert.is_true(lw.run(w.abilities.charge.usable, e))
        e.combat = 5
        local ok, why = lw.run(w.abilities.charge.usable, e)
        assert.is_false(ok)
        assert.are.equal("cannot be in combat; target must be outside melee range", why)
        e.combat, e.action.rend.in_range = 0, true
        assert.is_false(lw.run(w.abilities.charge.usable, e))
    end)

    it("gates Intercept on the client's spell range, not LibRangeCheck", function()
        local e = lw.env(w)
        e.target.minR = 100 -- what LibRangeCheck leaves on Forever: nothing resolved
        e.action = { intercept = { in_range = true } }
        assert.is_true(lw.run(w.abilities.intercept.usable, e))
        e.action.intercept.in_range = false
        local ok, why = lw.run(w.abilities.intercept.usable, e)
        assert.is_false(ok)
        assert.are.equal("target must be within Intercept's range", why)
        e = lw.env(w)
        lw.run(w.abilities.intercept.now, e)
        assert.are.same({ "intercept_stun" }, e.applied)
    end)

    it(
        "declares the now-state of Charge, Bloodrage, Berserker Rage, the debuffs and the stances (spec §12a)",
        function()
            for _, k in ipairs({
                "charge",
                "bloodrage",
                "berserker_rage",
                "rend",
                "sunder_armor",
                "thunder_clap",
                "hamstring",
                "demoralizing_shout",
                "piercing_howl",
                "battle_stance",
                "defensive_stance",
                "berserker_stance",
            }) do
                assert.is_function(w.abilities[k].now, k)
            end
            local e = lw.env(w)
            w.game.known[100], w.game.known[6178] = true, true -- Charge rank 2
            lw.run(w.abilities.charge.now, e)
            assert.are.same({ 12 }, e.gained)
            assert.are.same({ "charge_stun" }, e.applied)
            e = lw.env(w)
            e.rage.current = 60
            w.game.known[1310185] = true -- Tactical Mastery: 10 kept
            lw.run(w.abilities.battle_stance.now, e)
            assert.are.same({ 50 }, e.spent)
            assert.are.same({ "battle_stance" }, e.applied)
            assert.are.same({ "defensive_stance", "berserker_stance" }, e.removed)
        end
    )

    describe("the reactive windows from the combat log (event-facade spec §6)", function()
        local ME, MOB = "Player-1", "Creature-1"

        local function row(t, sub, src, dst, a12, a15)
            w.game.now = t
            w.game.row = { t, sub, false, src, "", 0, 0, dst, "", 0, 0, a12, "", 1, a15 or 0 }
            w.events.COMBAT_LOG_EVENT_UNFILTERED()
        end

        local function reset(t)
            local e = lw.env(w)
            e.now, e.query_time, e.target.unit = t, t, MOB
            lw.run(w.hooks.reset_precast, e)
            return e
        end

        before_each(function()
            w.state.GUID = ME
            w.game.known[7384], w.game.known[6572] = true, true
        end)

        it("opens Overpower's window on our dodged swing for the rest of its 5 s, on that target only", function()
            row(10, "SWING_MISSED", ME, MOB, "DODGE")
            local e = reset(12)
            assert.are.equal(3, e.durations.overpower_ready)
            assert.is_nil(reset(16.5).durations.overpower_ready) -- past Classic's 6 s age test
            w = lw.load()
            w.state.GUID = ME
            w.game.known[7384] = true
            row(20, "SPELL_MISSED", ME, "Creature-2", 7384, "DODGE") -- another unit dodged
            assert.is_nil(reset(21).durations.overpower_ready)
        end)

        it("closes Overpower's window once Overpower is cast, and keeps the usability fallback", function()
            row(10, "SWING_MISSED", ME, MOB, "DODGE")
            row(10.5, "SPELL_CAST_SUCCESS", ME, MOB, 7384)
            row(11, "SWING_MISSED", ME, MOB, "PARRY")
            local e = reset(12)
            for _, k in ipairs(e.applied) do
                assert.are_not.equal("overpower_ready", k) -- the dodge's window was spent
            end
            w.game.usable[7384] = true -- the client says usable: a dodge the log did not attribute
            e = reset(13)
            assert.are.same({ "overpower_ready" }, { e.applied[#e.applied] })
            assert.is_nil(e.durations.overpower_ready)
        end)

        it("gates Overpower on its window, not on the usability read", function()
            local e = lw.env(w)
            w.game.usable[7384] = true
            assert.is_false(lw.run(w.abilities.overpower.usable, e))
            e.buff = { overpower_ready = { up = true } }
            assert.is_true(lw.run(w.abilities.overpower.usable, e))
        end)

        it("opens Revenge's window on a parry on us while Revenge is usable", function()
            row(20, "SWING_MISSED", MOB, ME, "PARRY")
            w.game.noMana[6572] = true -- usable but for rage
            assert.are.equal(4, reset(21).durations.revenge_usable)
            assert.is_nil(reset(26).durations.revenge_usable) -- older than 5 s: the full window from the read
            w.game.noMana[6572] = nil
            local e = reset(21)
            for _, k in ipairs(e.applied) do
                assert.are_not.equal("revenge_usable", k)
            end
        end)
    end)

    it("gates Thunder Clap, Execute and Spearing Strike on the stances Forever's tooltips name", function()
        local a = w.abilities
        assert.are.same({ nil, "berserker_stance" }, { a.thunder_clap.buff, a.thunder_clap.nobuff })
        assert.are.same({ nil, "defensive_stance" }, { a.execute.buff, a.execute.nobuff })
        assert.are.equal(0.2, a.execute.healthGate) -- VirtualState's target health (Families/TargetHealth.lua)
        assert.are.same({ "battle_stance", nil }, { a.spearing_strike.buff, a.spearing_strike.nobuff })
    end)

    it("uses the corrected Classic IDs and Forever's Overpower window", function()
        assert.are.same({ 12328, 12292 }, { w.abilities.death_wish.id, w.abilities.sweeping_strikes.id })
        assert.are.same({ 12328, 12292 }, { w.auras.death_wish.id, w.auras.sweeping_strikes.id })
        assert.are.same({ 1282733, 5 }, { w.auras.overpower_ready.id, w.auras.overpower_ready.duration })
        assert.are.same({ 29131, 10 }, { w.auras.bloodrage.id, w.auras.bloodrage.duration })
    end)

    it("registers every aura a handler, state function or stance gate names", function()
        local e = lw.env(w)
        for key, a in pairs(w.abilities) do
            lw.run(a.handler, e)
            for _, gate in ipairs({ lw.run(a.buff, e), a.nobuff }) do
                table.insert(e.applied, gate)
            end
        end
        for _, k in ipairs(e.applied) do
            assert.is_not_nil(w.auras[k], "unregistered aura " .. tostring(k))
        end
        for _, k in ipairs(e.removed) do
            assert.is_not_nil(w.auras[k], "unregistered aura " .. tostring(k))
        end
    end)

    it("gains rage per white swing from the unhasted weapon speed and the hand (Forever's measured rates)", function()
        local models = w.resource[2]
        local function near(want, got)
            assert.is_true(math.abs(got - want) < 1e-9, ("want %.4f, got %.4f"):format(want, got))
        end
        w.state.talent = setmetatable({
            unbridled_wrath = { rank = 5, enabled = true }, -- 0.075 x 5 = 0.375 rage a swing (one-hander)
            dual_wield_specialization = { rank = 3, enabled = true }, -- +30% off-hand rage
        }, getmetatable(rank(0)))
        w.state.main_hand.size = 1
        w.game.base = { 2.2, 2.5 }
        w.state.mainhand_speed, w.state.offhand_speed, w.state.haste = 2.2, 2.5, 1
        near(3.46 * 2.2 + 0.375, models.mainhand.value()) -- 7.612 + 0.375 = 7.987
        near(1.73 * 2.5 * 1.3 + 0.375, models.offhand.value()) -- 5.6225 + 0.375 = 5.9975
        -- haste shortens the swing but not its rage: the hasted speeds do not enter
        w.state.mainhand_speed, w.state.offhand_speed, w.state.haste = 1.76, 2.0, 1.25
        near(3.46 * 2.2 + 0.375, models.mainhand.value())
        near(1.73 * 2.5 * 1.3 + 0.375, models.offhand.value())
        w.state.main_hand.size = 2 -- a two-hander: 4.5 x speed, Unbridled Wrath 2 rage a proc
        w.game.base = { 3.3, 0 }
        near(4.5 * 3.3 + 0.75, models.mainhand.value()) -- 14.85 + 0.75 = 15.6
        assert.are.same({ "offhand", "offhand_speed" }, { models.offhand.swing, models.offhand.interval })
    end)

    it("takes the believed swing speed before a plain base speed is read", function()
        local models = w.resource[2]
        w.state.talent = rank(0)
        w.state.main_hand.size = 1
        w.game.base = { 0, 0 }
        w.state.mainhand_speed, w.state.offhand_speed = 2.6, 0
        assert.are.same({ 3.46 * 2.6, 0 }, { models.mainhand.value(), models.offhand.value() })
    end)

    it("gains Anger Management's rage every 3 s in combat through a combat-gated periodic entry", function()
        local am = w.resource[2].anger_management
        assert.are.same({ "anger_management", 3, 1 }, { am.talent, am.interval, am.value })
        assert.is_nil(am.aura)
        w.state.combat, w.state.query_time = 100, 107.5
        assert.are.same({ 106, false }, { am.last(), am.stop() })
        w.state.combat = 0
        assert.is_true(am.stop())
    end)

    it("loses rage out of combat at the tooltip's 1.25/s, 30% less with Anger Management", function()
        local decay = w.resource[4].decay
        w.state.talent = { anger_management = { rank = 0 } }
        assert.are.equal(1.25, decay())
        w.state.talent.anger_management.rank = 1
        assert.is_true(math.abs(0.875 - decay()) < 1e-9) -- 1.25 x (1 - 0.3 x 1) = 1.25 x 0.7 = 0.875
        assert.are.equal(1, w.resource[4].decayInterval()) -- stepped: lost at the start of each 1 s window
    end)

    it("declares no rage maximum of its own: a Gnome's 105 is the race pack's Expansive Mind", function()
        assert.is_nil(w.resource[4].max) -- 100 by default; the Gnome's race pack adds Expansive Mind
    end)

    it("gains Bloodrage's rage over time through an aura-gated regen entry", function()
        local models = w.resource[2]
        assert.are.equal(1, w.resource[1])
        assert.are.same(
            { "bloodrage", 1, 1 },
            { models.bloodrage.aura, models.bloodrage.interval, models.bloodrage.value }
        )
        w.state.buff = { bloodrage = { applied = 10 } }
        w.state.query_time = 13.4
        assert.are.equal(13, models.bloodrage.last())
        assert.are.equal("mainhand", models.mainhand.swing)
    end)

    it("registers the 52 live talent nodes with their definition spells and max ranks, and no rank aliases", function()
        local n, registered = 0, 0
        for key, t in pairs(TALENTS) do
            n = n + 1
            assert.are.same({ 0, t[1], t[2] }, w.talents[key], key)
        end
        for _ in pairs(w.talents) do
            registered = registered + 1
        end
        assert.are.same({ 52, 52 }, { n, registered })
        assert.is_nil(next(w.track))
    end)

    it("reads a queued strike and Revenge's window at reset, leaving the stance to the Forms source", function()
        local e = lw.env(w)
        w.game.form, w.game.formSpell[2] = 2, 71
        w.game.known[78], w.game.current[78] = true, true
        w.game.known[6572], w.game.noMana[6572] = true, true -- usable but for rage
        lw.run(w.hooks.reset_precast, e)
        assert.are.same({ "heroic_strike", "revenge_usable" }, e.applied)
        assert.are.same({}, e.removed)
    end)

    it("keeps Tactical Mastery's rage on a stance swap", function()
        local e = lw.env(w)
        w.game.known[1310185] = true
        e.talent = rank(1)
        e.swap_stance("berserker_stance")
        assert.are.same({ 25 }, e.spent) -- 50 rage, 10 + 1 x 15 kept (DB2 12295: 15 a rank)
        assert.are.same({ "berserker_stance" }, e.applied)
    end)

    it("silences with Shield Bash from rank 1 of Improved Shield Bash", function()
        local e = lw.env(w)
        lw.run(w.abilities.shield_bash.handler, e)
        assert.are.same({}, e.applied)
        e.talent = rank(1)
        lw.run(w.abilities.shield_bash.handler, e)
        assert.are.same({ "shield_bash_silenced" }, e.applied) -- DB2 12311: 100% at rank 1
    end)

    it("recommends Execute only inside the client's usability window, at the known rank", function()
        local e = lw.env(w)
        w.game.known[5308], w.game.known[20658] = true, true
        assert.is_false(lw.run(w.abilities.execute.usable, e))
        w.game.usable[20658] = true
        assert.is_true(lw.run(w.abilities.execute.usable, e))
    end)

    it("registers the Arms, Fury and Protection priorities exactly as tools/make_pack.lua prints them", function()
        local printed = {}
        local pipe = assert(io.popen("lua5.1 tools/make_pack.lua"))
        for line in pipe:lines() do
            printed[#printed + 1] = { line:match("^(%d+) (.+)$") }
        end
        pipe:close()
        assert.are.equal(3, #w.packs)
        for i, name in ipairs({ "Arms", "Fury", "Protection" }) do
            assert.are.same({ name, tonumber(printed[i][1]), printed[i][2] }, w.packs[i])
        end
        assert.are.same({ package = "Arms" }, w.options)
    end)

    it("opens with Charge before combat and closes the gap with Intercept in Arms and Fury", function()
        local packs = assert(loadfile("tools/make_pack.lua"))("lists", "warrior")
        local function actions(list, n)
            local out = {}
            for j = 1, n or #list do
                out[j] = list[j].action
            end
            return out
        end
        for i = 1, 2 do
            assert.are.same({ "battle_shout", "charge" }, actions(packs[i].lists.precombat), packs[i].name)
            assert.are.same({ "victory_rush", "intercept" }, actions(packs[i].lists.rotation, 2), packs[i].name)
        end
        -- Protection charges in Battle Stance, then swaps to Defensive Stance
        assert.are.same({ "battle_shout", "charge", "defensive_stance" }, actions(packs[3].lists.precombat))
    end)

    it("keeps its priorities in tools/packs/warrior.lua, tools/make_pack.lua's default class", function()
        local def = dofile("tools/packs/warrior.lua")
        local names = {}
        for i, p in ipairs(def.packs) do
            names[i] = p.name
        end
        assert.are.same({ 20261016, 1491, { "Arms", "Fury", "Protection" } }, { def.date, def.spec, names })
        local byName = assert(loadfile("tools/make_pack.lua"))("lists", "warrior")
        local byDefault = assert(loadfile("tools/make_pack.lua"))("lists")
        assert.are.same(byDefault, byName)
        assert.are.equal(def.packs[1].simc, byName[1].simc)
    end)

    it("writes priorities that name only registered abilities, auras, talents, settings and lists", function()
        local packs = assert(loadfile("tools/make_pack.lua"))("lists")
        local secretToken = require("Virtual.State.helpers.load").module().VirtualState.AplSecretToken
        local kinds = {
            buff = w.auras,
            debuff = w.auras,
            action = w.abilities,
            cooldown = w.abilities,
            talent = w.talents,
            settings = w.settings,
        }
        for _, p in ipairs(packs) do
            for list, entries in pairs(p.lists) do
                for i, e in ipairs(entries) do
                    local where = p.name .. " " .. list .. " " .. i
                    if e.list_name then
                        assert.is_not_nil(p.lists[e.list_name], where .. ": no list " .. e.list_name)
                    else
                        assert.is_not_nil(w.abilities[e.action], where .. ": no ability " .. e.action)
                    end
                    local c = e.criteria or ""
                    for kind, key in c:gmatch("(%a+)%.([%w_]+)") do
                        if kinds[kind] then
                            assert.is_not_nil(kinds[kind][key], where .. ": no " .. kind .. " " .. key)
                        end
                    end
                    assert.is_nil(secretToken(c), where) -- no health or time to die: secret on Forever (Task 9b)
                end
            end
        end
        for _, name in ipairs({ "execute_phase", "should_hs", "should_cleave", "mainhand_remains" }) do
            assert.are.equal("function", type(w.exprs[name]), name)
        end
    end)

    it("queues a strike only when the rage for the next strike and Whirlwind still arrives in time", function()
        local e = lw.env(w)
        e.query_time, e.mainhand_remains = 0, 2
        e.action = setmetatable({}, {
            __index = function()
                return { cost = 30 }
            end,
        })
        w.state.TimeToResource = function(_, _, amount)
            return amount / 10 -- 10 rage a second
        end
        w.game.known[23881], w.game.known[1680] = true, true
        assert.is_false(e.should_queue(15)) -- Bloodthirst and Whirlwind are both ready now: 60 rage needed at once
        w.state.TimeToResource = function()
            return 0
        end
        assert.is_true(e.should_queue(15))
        -- 40 rage now, Whirlwind in 3 s, the swing in 2 s: Bloodthirst and Whirlwind fit, the queued strike does not
        e.cooldown = setmetatable({ whirlwind = { remains = 3 } }, getmetatable(e.cooldown))
        w.state.TimeToResource = function(_, _, amount)
            return math.max(0, (amount - 40) / 10)
        end
        assert.is_true(e.should_queue(0))
        assert.is_false(e.should_queue(15))
    end)

    it("reserves no rage for a main strike or Whirlwind the character does not know", function()
        local e = lw.env(w)
        e.query_time, e.mainhand_remains = 0, 2
        e.action = setmetatable({}, {
            __index = function()
                return { cost = 30 }
            end,
        })
        w.state.TimeToResource = function(_, _, amount)
            return amount / 10 -- no rage now, 10 a second
        end
        assert.is_true(e.should_queue(15)) -- 15 rage by the swing in 2 s
        assert.is_false(e.should_queue(30))
    end)

    it("times the next main-hand swing past the last known one, and 0 with no weapon speed", function()
        local e = lw.env(w)
        e.now, e.query_time, e.nextMH, e.mainhand_speed = 0, 5, 1, 3
        assert.are.equal(2, lw.run(w.exprs.mainhand_remains, e))
        e.mainhand_speed = 0
        assert.are.equal(0, lw.run(w.exprs.mainhand_remains, e))
    end)
    it(
        "state.reset clears the pseudo-swing anchors before it rebuilds the resource forecasts (core edit E3)",
        function()
            local src = assert(io.open("src/Hekili/State.lua")):read("*a")
            local clear = src:find("state.swings.mh_pseudo = nil", 1, true)
            local loop = src:find("for k, power in pairs( class.resources ) do", 1, true)
            assert.is_truthy(clear and loop and clear < loop)
            assert.is_truthy(
                src:find("seed this pass's swing forecast (Forever E3)\n        state.swings.mh_pseudo = nil", 1, true)
            )
        end
    )
    it("both State.lua range reads ask the known rank's spell id (core edit E5)", function()
        local src = assert(io.open("src/Hekili/State.lua")):read("*a")
        local _, n =
            src:gsub('LSR%.IsSpellInRange%( ability%.rangeSpell or ns%.KnownSpellID%( ability%.id %), "target" %)', "")
        assert.are.equal(2, n)
        assert.is_nil(src:find("IsSpellInRange( ability.rangeSpell or ability.id", 1, true))
    end)
    it("the forecast's continuous rate excludes the aura-gated entries it ticks as events (core edit E7)", function()
        local src = assert(io.open("src/Hekili/State.lua")):read("*a")
        assert.is_truthy(src:find("-- Forever E7:[^\n]*\n        local regen = r%.regen or 0\n"))
        assert.is_nil(src:find("local regen = r.regen_combined", 1, true))
    end)
    it("a real pull with no swing seen anchors the first swing at the combat start (core edit E8)", function()
        local src = assert(io.open("src/Hekili/State.lua")):read("*a")
        local next_oh = src:find("state.nextOH = ", 1, true)
        local anchor = src:find(
            "-- Forever E8:[^\n]*\n        if state%.combat > 0 and state%.swings%.mh_actual == 0 then\n"
                .. "            state%.swings%.mh_pseudo = state%.combat\n"
        )
        assert.is_truthy(next_oh and anchor and next_oh < anchor)
        local block = src:sub(anchor, assert(src:find("\n        end\n", anchor, true)))
        assert.is_truthy(block:find("state.swings.oh_pseudo = state.combat + state.offhand_speed / 2", 1, true))
        assert.is_truthy(block:find("state:ForecastSwingbasedResources()", 1, true))
    end)
    it("the forecast horizon follows the forecast window, its loop guard scaled to it (core edit E9)", function()
        local src = assert(io.open("src/Hekili/State.lua")):read("*a")
        assert.is_truthy(src:find("local timeout = Hekili.DB.profile.performance.forecastWindow or 15\n", 1, true))
        assert.is_truthy(src:find("local maxIter = ceil( 3 * timeout ) + 10", 1, true))
        assert.is_truthy(src:find("iter < maxIter ) do", 1, true))
        assert.is_nil(src:find("FORECAST_DURATION", 1, true))
        local core = assert(io.open("src/Hekili/Core.lua")):read("*a")
        assert.is_truthy(
            core:find(
                "-- Forever E9:[^\n]*\n%s+local defaultMax = Hekili%.DB%.profile%.performance%.forecastWindow or 15\n"
            )
        )
    end)
    it("the forecast window is a global Performance option, default 15 s (core edit E9)", function()
        local opts = assert(io.open("src/Hekili/Options/Options.lua")):read("*a")
        assert.is_truthy(opts:find("frameBudget = 0.7,\n%s+forecastWindow = 15,"))
        assert.is_truthy(opts:find('forecastHeader = {\n%s+type = "header",\n%s+name = "Forecast",'))
        assert.is_truthy(opts:find('forecastWindow = {\n%s+type = "range",\n%s+name = "Forecast window %(s%)",'))
        assert.is_truthy(opts:find("Hekili.DB.profile.performance.forecastWindow = v", 1, true))
        assert.is_nil(w.settings.forecast_window)
    end)
end)
