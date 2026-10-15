-- Forever/spec/warrior_spec.lua: the Forever Warrior class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through a recording stand-in for Hekili (helpers/load_warrior.lua). What Hekili
-- does with them is verified in game (the plan's checkpoint).
local lw = require("Forever.spec.helpers.load_warrior")

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

    it("registers the Classic kit plus Victory Rush and Spearing Strike with the DB2's ranks, costs and cooldowns", function()
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
    end)

    it("models the talent-modified costs and cooldowns from rank 1's DB2 value x the rank", function()
        local e = lw.env(w)
        e.talent = setmetatable({}, {
            __index = function()
                return { rank = 2, enabled = true }
            end,
        })
        local function at(key, field)
            return lw.run(w.abilities[key][field], e)
        end
        assert.are.same(
            { 13, 14, 5, 9, 8, 6 },
            { at("heroic_strike", "spend"), at("cleave", "spend"), at("execute", "spend"), at("sunder_armor", "spend"),
                at("thunder_clap", "spend"), at("taunt", "cooldown") }
        )
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

    it("gains Bloodrage's rage over time through an aura-gated regen entry", function()
        local models = w.resource[2]
        assert.are.equal(1, w.resource[1])
        assert.are.same({ "bloodrage", 1, 1 }, { models.bloodrage.aura, models.bloodrage.interval, models.bloodrage.value })
        w.state.buff = { bloodrage = { applied = 10 } }
        w.state.query_time = 13.4
        assert.are.equal(13, models.bloodrage.last())
        assert.are.equal("mainhand", models.mainhand.swing)
    end)

    it("reads the stance, a queued strike and Revenge's window at reset", function()
        local e = lw.env(w)
        w.game.form, w.game.formSpell[2] = 2, 71
        w.game.known[78], w.game.current[78] = true, true
        w.game.known[6572], w.game.noMana[6572] = true, true -- usable but for rage
        lw.run(w.hooks.reset_precast, e)
        assert.are.same({ "defensive_stance", "heroic_strike", "revenge_usable" }, e.applied)
    end)

    it("keeps Tactical Mastery's rage on a stance swap", function()
        local e = lw.env(w)
        w.game.known[1310185] = true
        e.talent = setmetatable({}, {
            __index = function()
                return { rank = 2, enabled = true }
            end,
        })
        e.swap_stance("berserker_stance")
        assert.are.same({ 30 }, e.spent) -- 50 rage, 10 + 2 x 5 kept
        assert.are.same({ "berserker_stance" }, e.applied)
    end)

    it("recommends Execute only inside the client's usability window, at the known rank", function()
        local e = lw.env(w)
        w.game.known[5308], w.game.known[20658] = true, true
        assert.is_false(lw.run(w.abilities.execute.usable, e))
        w.game.usable[20658] = true
        assert.is_true(lw.run(w.abilities.execute.usable, e))
    end)
end)
