-- tests/Forever/warrior_spec.lua: the Forever Warrior class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through a recording stand-in for Hekili (helpers/load_warrior.lua). What Hekili
-- does with them is verified in game (the plan's checkpoint).
local lw = require("Forever.helpers.load_warrior")
local alloc = require("Game.State.helpers.alloc")
-- the project interpreter when bootstrapped, else the system one (as tools/list_api_reads.sh picks it)
local LUA = io.open(".lua/bin/lua") and ".lua/bin/lua" or "lua5.1"

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
            assert.are.equal(1.5, lw.run(w.abilities.slam.cast, e))
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

    -- The belief prices a cast in Families/Now.lua's context: its reads (talent, max, ...) and no state functions.
    it("prices the offensive costs in the belief's now context, which has no state functions", function()
        local e = lw.env(w)
        local ctx = { talent = rank(2), max = math.max, min = math.min, floor = math.floor }
        for _, key in ipairs({ "whirlwind", "mortal_strike", "sunder_armor", "execute" }) do
            assert.are.equal(
                lw.run(w.abilities[key].spend, setmetatable({ talent = ctx.talent }, { __index = e })),
                lw.run(w.abilities[key].spend, ctx),
                key
            )
        end
        assert.are.equal(13, lw.run(w.abilities.whirlwind.spend, ctx))
    end)

    it("casts Slam in 1.0 s with a 1.0 s GCD on a 15 s cooldown with Improved Slam (Forever DB2 12862)", function()
        local e = lw.env(w)
        local slam = w.abilities.slam
        local function fields()
            return { lw.run(slam.cast, e), lw.run(slam.gcdTime, e), lw.run(slam.cooldown, e) }
        end
        e.talent = rank(0)
        assert.are.same({ 1.5, nil, 18 }, fields()) -- no gcdTime: the "spell" GCD kind's 1.5 s
        e.talent = rank(2)
        assert.are.same({ 1.0, 1.0, 15 }, fields())
    end)

    it("leaves the swing timer alone on a Slam (no handler: Improved Slam's 2/2 tooltip, the wowsims build)", function()
        assert.is_nil(w.abilities.slam.handler)
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
                "battle_shout",
                "challenging_shout",
                "concussion_blow",
                "death_wish",
                "disarm",
                "intimidating_shout",
                "last_stand",
                "mocking_blow",
                "mortal_strike",
                "overpower",
                "recklessness",
                "retaliation",
                "shield_bash",
                "shield_block",
                "shield_wall",
                "sweeping_strikes",
                "taunt",
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

        -- Windfury Totem's party aura on the warrior (DB2 8515/10609/10612, effect 35 area aura party), not the
        -- Shaman's totem casts (8512/10613/10614).
        it("tracks Windfury as the party aura the totem grants, every rank", function()
            local a = w.auras.windfury
            assert.are.same({ 8515, { 10609, 10612 } }, { a.id, a.copy })
        end)

        -- Victorious (DB2 402975): 20 s from a kill that yields XP or honor (402974's PROC_FLAG_KILL). The client's
        -- usability flips at the kill, so the flip timestamps the window.
        it("opens Victorious on the usability flip for the rest of its 20 s, and not without the flip", function()
            w.game.known[402927] = true
            assert.are.same({ 402975, 20 }, { w.auras.victorious.id, w.auras.victorious.duration })
            w.game.now = 10
            w.events.SPELL_UPDATE_USABLE() -- no kill (or no XP): the client says no
            assert.is_nil(reset(11).durations.victorious)
            for _, k in ipairs(reset(11).applied) do
                assert.are_not.equal("victorious", k)
            end
            w.game.usable[402927] = true -- a kill with XP at t=12
            w.game.now = 12
            w.events.SPELL_UPDATE_USABLE()
            assert.are.equal(16, reset(16).durations.victorious)
            w.game.now = 32
            w.game.usable[402927] = nil -- expired (or cast): the client says no
            w.events.SPELL_UPDATE_USABLE()
            for _, k in ipairs(reset(33).applied) do
                assert.are_not.equal("victorious", k)
            end
        end)

        it("gates Victory Rush on Victorious and removes it on the cast", function()
            local e = lw.env(w)
            w.game.known[402927], w.game.usable[402927] = true, true
            assert.is_false(lw.run(w.abilities.victory_rush.usable, e)) -- window closed before the cooldown ends
            e.buff = { victorious = { up = true } }
            assert.is_true(lw.run(w.abilities.victory_rush.usable, e))
            lw.run(w.abilities.victory_rush.handler, e)
            assert.are.same({ "victorious" }, e.removed)
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
        near(3.46 * 3.3, models.mainhand.crit()) -- a white crit: one more base swing, 3.46 x speed with a two-hander too
        w.state.main_hand.size, w.game.base = 1, { 2.2, 2.5 }
        near(3.46 * 2.2, models.mainhand.crit())
        near(1.73 * 2.5, models.offhand.crit()) -- the off hand's own base (unmeasured on Forever)
        assert.are.same({ "offhand", "offhand_speed" }, { models.offhand.swing, models.offhand.interval })
    end)

    describe("rage from damage taken (the main-hand entry's `taken`, Protection design §1.3)", function()
        local taken, e

        -- The belief's `now` context as `taken` sees it: these auras up, these talent ranks, the stat cache.
        local function ctx(auras, ranks)
            e = {
                stat = w.state.stat,
                buff = setmetatable({}, {
                    __index = function(_, k)
                        return { up = auras[k] == true }
                    end,
                }),
                talent = setmetatable({}, {
                    __index = function(_, k)
                        return { rank = ranks[k] or 0 }
                    end,
                }),
            }
        end

        local function run(kind, amount, level)
            return lw.run(taken, e, kind, amount, level)
        end

        before_each(function()
            taken = w.resource[2].mainhand.taken
            w.game.stat.UnitArmor = { 593, 593 } -- base, effective: the second is the armor
            w.game.healthMax = 203
            ctx({}, {})
        end)

        it(
            "gives magey's log 01: 110 pre-armor from a level-5 attacker at 593 armor and 203 health is 5.4 rage",
            function()
                local sum, band = 0, 0
                for _ = 1, 20 do
                    local g, wd = run("WOUND", 3.2, 5) -- 64 post-armor over 20 hits: 64 / (1 - 593 / 1418) = 110
                    sum, band = sum + g, band + wd
                end
                assert.is_true(math.abs(sum - 110 * 10 / 203) < 1e-3, tostring(sum)) -- 5.419
                assert.is_true(math.abs(band - 0.15 * sum) < 1e-9)
                assert.is_true(math.abs(sum - 5.4) <= band)
            end
        )

        it(
            "adds the cached block value to a partial block, and estimates a full block from the unblocked amounts",
            function()
                w.game.stat.UnitArmor = { 0, 0 }
                w.game.healthMax = 100
                w.game.stat.GetShieldBlock = { 20 }
                assert.are.same({ 3, 0.15 * 3 }, { run("BLOCKED", 10, 5) }) -- (10 + 20) x 10 / 100
                local full = run("BLOCK", 0, 5)
                -- min(block value 20, the average unblocked amount 0.2 x 30) x 10 / 100
                assert.is_true(math.abs(full - 0.6) < 1e-9, tostring(full))
                local g, wd = run("BLOCK", 0, 5)
                assert.are.equal(g, wd) -- a full block's band is its whole estimate
                w.events.PLAYER_REGEN_ENABLED() -- the fight ends: the next fight learns its own unblocked amounts
                assert.are.same({ 0, 0 }, { run("BLOCK", 0, 5) })
            end
        )

        it("divides back Defensive Stance's 10% and Shield Wall's reduction (rage from the unreduced hit)", function()
            local open = run("WOUND", 50, 20)
            ctx({ defensive_stance = true }, {})
            assert.is_true(math.abs(run("WOUND", 50, 20) - open / 0.9) < 1e-9)
            ctx({ defensive_stance = true, shield_wall = true }, {})
            assert.is_true(math.abs(run("WOUND", 50, 20) - open / 0.36) < 1e-9)
        end)

        it("adds Shield Specialization's 20% a rank of 5 rage on a block, partial or full", function()
            w.game.stat.GetShieldBlock = { 0 }
            ctx({}, { shield_specialization = 1 })
            assert.are.same({ 1, 4 }, { run("BLOCK", 0, 20) }) -- p = 0.2: 1 expected, half-width max(p, 1 - p) x 5
            ctx({}, { shield_specialization = 5 })
            assert.are.same({ 5, 5 }, { run("BLOCK", 0, 20) })
            assert.are.same({ 0, 0 }, { run("DODGE", 0, 20) })
            w.game.stat.UnitArmor, w.game.healthMax = { 0, 0 }, 100
            ctx({}, { shield_specialization = 1 })
            assert.are.same({ 3 + 1, 0.15 * 3 + 4 }, { run("BLOCKED", 30, 20) }) -- a partial block: the hit's, plus the proc
        end)

        it("allocates nothing over every kind", function()
            w.game.stat.GetShieldBlock = { 20 }
            w.state.equipped.shield = true
            e = { -- plain tables: the belief's proxies are preallocated, so only `taken` itself is measured
                stat = w.state.stat,
                buff = { defensive_stance = { up = true }, shield_wall = { up = false } },
                talent = { shield_specialization = { rank = 1 }, master_of_defense = { rank = 1 } },
            }
            local f = setfenv(taken, e)
            local KINDS = { "WOUND", "BLOCKED", "BLOCK", "DODGE", "PARRY", "MISS" }
            assert.are.equal(
                0,
                alloc.bytes(function(i)
                    f(KINDS[i % 6 + 1], 40, 20)
                end, 100)
            )
        end)

        it("adds Master of Defense's 50% a rank of 5 rage on a dodge or parry, only with a shield", function()
            ctx({}, { master_of_defense = 1 })
            assert.are.same({ 0, 0 }, { run("DODGE", 0, 20) }) -- no shield
            w.state.equipped.shield = true
            assert.are.same({ 2.5, 2.5 }, { run("DODGE", 0, 20) })
            ctx({}, { master_of_defense = 2 })
            assert.are.same({ 5, 5 }, { run("PARRY", 0, 20) })
            assert.are.same({ 0, 0 }, { run("MISS", 0, 20) })
        end)
    end)

    it("blocks twice per Shield Block: aura stacks spent by blocks, not ability charges", function()
        local aura, ability = w.auras.shield_block, w.abilities.shield_block
        assert.are.same({ 2, { BLOCK = true, BLOCKED = true } }, { aura.max_stack, aura.consumedBy })
        assert.is_nil(ability.charges)
        local env = lw.env(w)
        lw.run(ability.handler, env)
        lw.run(ability.now, env)
        assert.are.same({ { "shield_block", "shield_block" }, 2 }, { env.applied, env.stacks.shield_block })
    end)

    it("takes the believed swing speed before a plain base speed is read", function()
        local models = w.resource[2]
        w.state.talent = rank(0)
        w.state.main_hand.size = 1
        w.game.base = { 0, 0 }
        w.state.mainhand_speed, w.state.offhand_speed = 2.6, 0
        assert.are.same({ 3.46 * 2.6, 0 }, { models.mainhand.value(), models.offhand.value() })
    end)

    it("gains Anger Management's 1.5 rage every 5 s in combat through a combat-gated periodic entry", function()
        local am = w.resource[2].anger_management
        assert.are.same({ "anger_management", 5, 1.5 }, { am.talent, am.interval, am.value })
        assert.is_nil(am.aura)
        w.state.combat, w.state.query_time = 100, 107.5
        assert.are.same({ 105, false }, { am.last(), am.stop() })
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

    it(
        "gives back 80% of an avoided ability's rage where wowsims does, per ability (not Cleave or Whirlwind)",
        function()
            assert.are.equal(0.8, w.resource[4].refundOnAvoid)
            local yes = {}
            for key, a in pairs(w.abilities) do
                if a.refundOnAvoid then
                    yes[#yes + 1] = key
                end
            end
            table.sort(yes)
            assert.are.same({
                "bloodthirst",
                "concussion_blow",
                "disarm",
                "execute",
                "hamstring",
                "heroic_strike",
                "mocking_blow",
                "mortal_strike",
                "overpower",
                "pummel",
                "rend",
                "revenge",
                "shield_bash",
                "shield_slam",
                "slam",
                "spearing_strike",
                "sunder_armor",
            }, yes)
        end
    )

    it("declares no rage maximum of its own: a Gnome's 105 is the race pack's Expansive Mind", function()
        assert.is_nil(w.resource[4].max) -- 100 by default; the Gnome's race pack adds Expansive Mind
    end)

    it("gains Bloodrage's rage over time through an aura-gated regen entry", function()
        local models = w.resource[2]
        assert.are.equal(1, w.resource[1])
        assert.are.same(
            { "bloodrage", 1, 1, true },
            { models.bloodrage.aura, models.bloodrage.interval, models.bloodrage.value, models.bloodrage.pausesDecay }
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
            assert.are.same({ t[1], t[2] }, { w.talents[key][2], w.talents[key][3] }, key)
        end
        for _ in pairs(w.talents) do
            registered = registered + 1
        end
        assert.are.same({ 52, 52 }, { n, registered })
        -- Tactical Mastery, a passive: declared, and the Schema tells the belief to watch it (Engine/Schema/Spec.lua)
        assert.are.same({ id = 1310185, passive = true }, w.passives.tactical_mastery)
    end)

    it("places every registered talent in a tree, 17 Arms, 18 Fury and 17 Protection", function()
        -- the DB2's tabs (wowdb talents WARRIOR): Improved Slam is Fury's and Improved Thunder Clap Arms's, though the
        -- pane groups them with the other tree; a Forever-only node is its section's
        local n = { 0, 0, 0 }
        for key, t in pairs(require("Forever.helpers.load_warrior").load().talents) do
            assert.is_true(t[1] >= 1 and t[1] <= 3, key)
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ 17, 18, 17 }, n)
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

    it("registers the five priorities (Arms and Fury twice) exactly as tools/make_pack.lua prints them", function()
        local printed = {}
        local pipe = assert(io.popen(LUA .. " tools/make_pack.lua"))
        for line in pipe:lines() do
            printed[#printed + 1] = { line:match("^(%d+) (.+)$") }
        end
        pipe:close()
        assert.are.equal(5, #w.packs)
        for i, name in ipairs({ "Fury (wowsims.com)", "Arms (wowsims.com)", "Arms", "Fury", "Protection" }) do
            assert.are.same({ name, tonumber(printed[i][1]), printed[i][2] }, w.packs[i])
        end
        assert.is_nil(w.options) -- each spec's package is NewClass's
        assert.are.equal("WARRIOR", w.class)
        local keys = {}
        for i, s in ipairs(w.def.specs) do
            keys[i] = s.key .. "=" .. tostring(s.package) .. "@" .. s.tree
        end
        assert.are.same({ "arms=Arms@1", "fury=Fury@2", "protection=Protection@3" }, keys)
    end)

    it(
        "opens with Charge before combat in Arms and Fury (Fury with Intercept too), and closes the gap with Intercept in Arms",
        function()
            local packs = assert(loadfile("tools/make_pack.lua"))("lists", "warrior")
            local function actions(list, n)
                local out = {}
                for j = 1, n or #list do
                    out[j] = list[j].action
                end
                return out
            end
            for _, p in ipairs(packs) do
                packs[p.name] = p
            end
            assert.are.same({ "battle_shout", "charge" }, actions(packs.Arms.lists.precombat))
            assert.are.same({ "victory_rush", "intercept" }, actions(packs.Arms.lists.rotation, 2))
            -- Fury: Battle Shout, then Charge in Battle Stance or Intercept in Berserker Stance (wowsims's pre-pull move)
            assert.are.same({ "battle_shout", "charge", "intercept" }, actions(packs.Fury.lists.precombat))
            -- Protection charges in Battle Stance, then swaps to Defensive Stance
            assert.are.same({ "battle_shout", "charge", "defensive_stance" }, actions(packs.Protection.lists.precombat))
        end
    )

    it("keeps its priorities in src/Hekili_Warrior/APLs/, tools/make_pack.lua's default class", function()
        local def = dofile("src/Hekili_Warrior/APLs/packs.lua")
        assert.are.same(
            { "WARRIOR", { "Fury (wowsims.com)", "Arms (wowsims.com)", "Arms", "Fury", "Protection" } },
            { def.class, def.packs }
        )
        local byName = assert(loadfile("tools/make_pack.lua"))("lists", "warrior")
        local byDefault = assert(loadfile("tools/make_pack.lua"))("lists")
        assert.are.same(byDefault, byName)
        assert.are.equal("Fury (wowsims.com)", byName[1].name)
    end)

    it("writes priorities that name only registered abilities, auras, talents, settings and lists", function()
        local packs = assert(loadfile("tools/make_pack.lua"))("lists")
        local secretToken = require("Game.State.helpers.load").module().VirtualState.AplSecretToken
        local racial = require("Forever.helpers.engine").abilitySet("WARRIOR").racial -- every race's (the registry)
        local kinds = {
            buff = w.auras,
            debuff = w.auras,
            action = w.abilities,
            cooldown = w.abilities,
            talent = w.talents,
            settings = w.settings,
            threat = { situation = true, on_me = true, lost = true, loose = true }, -- Engine/Schema/Spec.lua's `threat` table
        }
        for _, p in ipairs(packs) do
            for list, entries in pairs(p.lists) do
                for i, e in ipairs(entries) do
                    local where = p.name .. " " .. list .. " " .. i
                    if e.list_name then
                        assert.is_not_nil(p.lists[e.list_name], where .. ": no list " .. e.list_name)
                    else
                        -- use_items is Hekili's `all` (Hekili_Shared/Shared/Items.lua), as in druid_spec
                        assert.is_true(
                            w.abilities[e.action] ~= nil or e.action == "use_items" or racial[e.action] ~= nil,
                            where .. ": no ability " .. e.action
                        )
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

    it(
        "tanks in Protection: threat first, Shield Block kept up, no defensives, the rage thresholds as settings",
        function()
            local packs = assert(loadfile("tools/make_pack.lua"))("lists")
            local prot = packs[#packs]
            assert.are.equal("Protection", prot.name)
            local order = {}
            for i, e in ipairs(prot.lists.default) do
                order[i] = e.action
            end
            assert.are.same({
                "shield_bash",
                "mocking_blow",
                "defensive_stance",
                "taunt",
                "challenging_shout",
                "shield_block",
                "victory_rush",
                "bloodrage",
                "battle_shout",
                "run_action_list",
                "run_action_list",
            }, order)
            assert.are.equal(
                "buff.shield_block.stack<2&(rage.current>=40||!buff.revenge_usable.up&cooldown.revenge.remains<=1.5)",
                prot.lists.default[6].criteria
            ) -- a stored | is ||
            for list, entries in pairs(prot.lists) do
                for _, e in ipairs(entries) do
                    for _, never in ipairs({ "last_stand", "shield_wall", "healthstone" }) do
                        assert.are_not.equal(never, e.action, list)
                    end
                end
            end
            local d = prot.desc
            assert.is_nil(d:find("provisional"))
            assert.are.same({ 50, 40, 3 }, {
                w.settings.prot_heroic_strike_rage.default,
                w.settings.prot_cleave_rage.default,
                w.settings.challenging_shout_loose.default,
            })
        end
    )

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
    it("anchors the next swing at the evaluation out of combat, so its phase does not run with the clock", function()
        local e = lw.env(w)
        e.combat, e.nextMH, e.mainhand_speed = 0, 0, 3
        e.now, e.query_time = 100, 101.5
        assert.are.equal(1.5, lw.run(w.exprs.mainhand_remains, e))
        e.now, e.query_time = 200, 201.5 -- a later evaluation, the same offset: the same answer
        assert.are.equal(1.5, lw.run(w.exprs.mainhand_remains, e))
        e.query_time = 200
        assert.are.equal(0, lw.run(w.exprs.mainhand_remains, e))
    end)
    it(
        "state.reset clears the pseudo-swing anchors before it rebuilds the resource forecasts (core edit E3)",
        function()
            local src = assert(io.open("src/Hekili/Engine/Sim/State.lua")):read("*a")
            local clear = src:find("state.swings.mh_pseudo = nil", 1, true)
            local loop = src:find("for k, power in pairs( class.resources ) do", 1, true)
            assert.is_truthy(clear and loop and clear < loop)
            assert.is_truthy(
                src:find("seed this pass's swing forecast (Forever E3)\n        state.swings.mh_pseudo = nil", 1, true)
            )
        end
    )
    it("both State.lua range reads ask the known rank's spell id (core edit E5)", function()
        local src = assert(io.open("src/Hekili/Engine/Sim/State.lua")):read("*a")
        local _, n =
            src:gsub('LSR%.IsSpellInRange%( ability%.rangeSpell or ns%.KnownSpellID%( ability%.id %), "target" %)', "")
        assert.are.equal(2, n)
        assert.is_nil(src:find("IsSpellInRange( ability.rangeSpell or ability.id", 1, true))
    end)
    it("the forecast's continuous rate excludes the aura-gated entries it ticks as events (core edit E7)", function()
        local src = assert(io.open("src/Hekili/Engine/Sim/State.lua")):read("*a")
        assert.is_truthy(src:find("-- Forever E7:[^\n]*\n        local regen = r%.regen or 0\n"))
        assert.is_nil(src:find("local regen = r.regen_combined", 1, true))
    end)
    it("a real pull with no swing seen anchors the first swing at the combat start (core edit E8)", function()
        local src = assert(io.open("src/Hekili/Engine/Sim/State.lua")):read("*a")
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
        local src = assert(io.open("src/Hekili/Engine/Sim/State.lua")):read("*a")
        assert.is_truthy(src:find("local timeout = Hekili.Engine.settings.performance.forecastWindow or 15\n", 1, true))
        assert.is_truthy(src:find("local maxIter = ceil( 3 * timeout ) + 10", 1, true))
        assert.is_truthy(src:find("iter < maxIter ) do", 1, true))
        assert.is_nil(src:find("FORECAST_DURATION", 1, true))
        local core = assert(io.open("src/Hekili/Engine/Sim/Core.lua")):read("*a")
        assert.is_truthy(
            core:find(
                "-- Forever E9:[^\n]*\n%s+local defaultMax = isMain and %( Hekili%.Engine%.settings%.performance%.forecastWindow or 15 %)"
                    .. " or %( display%.forecastPeriod or 15 %)\n"
            )
        )
    end)
    it("the forecast window is a global Performance option, default 15 s (core edit E9)", function()
        local opts = assert(io.open("src/Hekili/Options/Options.lua")):read("*a")
        assert.is_truthy(opts:find("frameBudget = 0.7,\n%s+forecastWindow = 15,"))
        assert.is_truthy(opts:find('forecastHeader = {\n%s+type = "header",\n%s+name = "Forecast",'))
        assert.is_truthy(opts:find('forecastWindow = {\n%s+type = "range",\n%s+name = "Forecast window %(s%)",'))
        assert.is_truthy(opts:find("Hekili.DB.profile.performance.forecastWindow = v", 1, true))
        assert.is_truthy(opts:find('forecastWindowInfo = {\n%s+type = "description",'))
        assert.is_nil(w.settings.forecast_window)
    end)
end)

-- The wowsims lines (class-completion Task 5) on the headless engine, as fury_spec checks Fury's: each line's `if=` runs
-- through the real Scripts.lua against a booted Arms Warrior (helpers/warrior_world.lua) with the state pinned per case.
describe("the Arms and Protection lines from wowsims/forever (class-completion Task 5)", function()
    local headless = require("Game.harness.headless")
    local ww = require("Forever.helpers.warrior_world")
    local H, st, pack

    -- Protection adds Revenge (every rank) to the Arms kit, so its cooldown is read.
    -- `noMortalStrike`: the Arms build without the talent (neither Mortal Strike known nor its talent taken).
    local function boot(stance, name, noMortalStrike)
        local c = ww.character()
        c.form, pack = ww.FORM[stance], name
        if noMortalStrike then
            local ms, known, talents = {}, {}, {}
            for _, id in ipairs(ww.IDS.mortal_strike) do
                ms[id] = true
            end
            for _, id in ipairs(c.known) do
                if not ms[id] then
                    known[#known + 1] = id
                end
            end
            for k, v in pairs(c.talents) do
                talents[k] = v
            end
            talents[ww.IDS.mortal_strike[1]] = nil
            c.known, c.talents = known, talents
        end
        if name == "Protection" then
            local revenge = lw.load().abilities.revenge
            c.known[#c.known + 1] = revenge.id
            for _, id in ipairs(revenge.copy) do
                c.known[#c.known + 1] = id
            end
        end
        H = headless.new({ character = c, pack = name })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert(headless.cycle(H, H.ctl.now + 0.2))
        st = H.Hekili.State
        st.reset("Primary", true)
        assert.is_true(st.buff[stance].up, stance)
    end

    -- The `n`th `action` entry of `list` in the booted pack: its condition as the engine evaluates it now, and its focus.
    local function check(list, action, n)
        n = n or 1
        for i, e in ipairs(H.Hekili.DB.profile.packs[pack].lists[list]) do
            if e.action == action then
                n = n - 1
                if n == 0 then
                    local ok, err = H.Hekili.Scripts:CheckScript(pack .. ":" .. list .. ":" .. i)
                    assert.is_nil(err, action)
                    return ok and true or false, e.focus
                end
            end
        end
        error("no " .. action .. " line")
    end

    local function cds(ms, wwcd, revenge)
        st.cooldown.mortal_strike.expires = st.query_time + ms
        st.cooldown.whirlwind.expires = st.query_time + wwcd
        st.cooldown.revenge.expires = st.query_time + (revenge or 9)
    end

    it("Arms: Rend in Battle Stance at 1.5 s or less, with Mortal Strike, outside execute (focus 2)", function()
        boot("battle_stance", "Arms")
        rawset(st.rage, "current", 50)
        assert.is_true(st.talent.mortal_strike.enabled)
        local ok, focus = check("rotation", "rend")
        assert.is_true(ok) -- not up
        assert.are.equal(2, focus)
        st.applyDebuff("target", "rend", 2)
        assert.is_false((check("rotation", "rend")))
        st.removeDebuff("target", "rend") -- a shorter application does not shorten the running one
        st.applyDebuff("target", "rend", 1.4)
        assert.is_true((check("rotation", "rend")))
        boot("berserker_stance", "Arms")
        assert.is_false((check("rotation", "rend")))
        -- the rotation list runs only outside the execute phase
        local d = H.Hekili.DB.profile.packs.Arms.lists.default
        assert.are.same(
            { "run_action_list", "execute", "execute_phase" },
            { d[4].action, d[4].list_name, d[4].criteria }
        )
    end)

    it(
        "Arms: Overpower at focus 1, Slam within 0.3 s after the main-hand swing (focus 2), leaving Mortal Strike's rage",
        function()
            boot("battle_stance", "Arms")
            assert.are.equal(1, select(2, check("rotation", "overpower")))
            rawset(st.rage, "current", 100)
            cds(9, 9)
            rawset(st, "mainhand_speed", 3.6)
            rawset(st, "mainhand_remains", 3.4) -- swung 0.2 s ago
            local ok, focus = check("rotation", "slam")
            assert.is_true(ok)
            assert.are.equal(2, focus)
            rawset(st, "mainhand_remains", 3.31)
            assert.is_true((check("rotation", "slam")))
            rawset(st, "mainhand_remains", 3.29) -- swung 0.31 s ago
            assert.is_false((check("rotation", "slam")))
            -- Mortal Strike ready within Slam's cast: Slam only with Mortal Strike's rage left over
            rawset(st, "mainhand_remains", 3.4)
            local slam, ms = st.action.slam.cost, st.action.mortal_strike.cost
            cds(1.4, 9)
            rawset(st.rage, "current", slam + ms - 1)
            assert.is_false((check("rotation", "slam")))
            rawset(st.rage, "current", slam + ms)
            assert.is_true((check("rotation", "slam")))
            cds(1.6, 9) -- Mortal Strike after the cast: nothing reserved
            rawset(st.rage, "current", slam)
            assert.is_true((check("rotation", "slam")))
            -- without Mortal Strike nothing is reserved (an unlearned spell's cooldown reads ready)
            boot("battle_stance", "Arms", true)
            assert.is_false(st.action.mortal_strike.known)
            rawset(st.rage, "current", slam)
            rawset(st, "mainhand_speed", 3.6)
            rawset(st, "mainhand_remains", 3.4)
            assert.is_true((check("rotation", "slam")))
            rawset(st, "mainhand_speed", 0) -- no swing speed read: no window
            rawset(st, "mainhand_remains", 0)
            assert.is_false((check("rotation", "slam")))
        end
    )

    it(
        "Arms: Battle Shout at 10 s or less, Hamstring under Windfury with Mortal Strike and Whirlwind 1.5 s away",
        function()
            boot("battle_stance", "Arms")
            rawset(st.rage, "current", 50)
            st.applyBuff("battle_shout", 11)
            assert.is_false((check("rotation", "battle_shout")))
            assert.is_false((check("precombat", "battle_shout")))
            st.applyBuff("battle_shout", 9.9)
            assert.is_true((check("rotation", "battle_shout")))
            assert.is_true((check("precombat", "battle_shout")))
            cds(9, 9)
            assert.is_false((check("rotation", "hamstring"))) -- no Windfury Totem
            st.applyBuff("windfury", 10)
            assert.is_true((check("rotation", "hamstring")))
            cds(1, 9)
            assert.is_false((check("rotation", "hamstring")))
            cds(9, 1)
            assert.is_false((check("rotation", "hamstring")))
            cds(1.6, 1.6)
            assert.is_true((check("rotation", "hamstring")))
        end
    )

    it("Protection: Shield Block at 40 rage, or with Revenge near ready and its window shut", function()
        boot("defensive_stance", "Protection")
        cds(9, 9, 9)
        rawset(st.rage, "current", 40)
        assert.is_true((check("default", "shield_block")))
        rawset(st.rage, "current", 39)
        assert.is_false((check("default", "shield_block")))
        cds(9, 9, 1.4)
        assert.is_true((check("default", "shield_block")))
        st.applyBuff("revenge_usable", 3) -- Revenge's window open: Revenge, not the block
        assert.is_false((check("default", "shield_block")))
        st.removeBuff("revenge_usable")
        cds(9, 9, 1.6)
        assert.is_false((check("default", "shield_block")))
        rawset(st.rage, "current", 100)
        st.applyBuff("shield_block", nil, 2) -- both blocks still up: no recast
        assert.is_false((check("default", "shield_block")))
    end)

    it(
        "Protection: Rend when not up, Sunder to 5 and at 10 s or less, Shield Bash, Taunt and Mocking Blow at focus 1",
        function()
            boot("defensive_stance", "Protection")
            rawset(st.rage, "current", 50)
            assert.is_true((check("single", "rend")))
            st.applyDebuff("target", "rend", 5)
            assert.is_false((check("single", "rend")))
            st.applyDebuff("target", "sunder_armor", 11, 5)
            assert.is_false((check("single", "sunder_armor")))
            st.removeDebuff("target", "sunder_armor")
            st.applyDebuff("target", "sunder_armor", 9.9, 5)
            assert.is_true((check("single", "sunder_armor")))
            st.applyDebuff("target", "sunder_armor", 30, 4)
            assert.is_true((check("single", "sunder_armor")))
            for _, key in ipairs({ "shield_bash", "taunt", "mocking_blow" }) do
                assert.are.equal(1, select(2, check("default", key)), key)
            end
        end
    )
end)
