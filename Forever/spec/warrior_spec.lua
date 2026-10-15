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

-- key = the talent's rank spells (wowdb talents WARRIOR, r1..r5): 18 Arms, 17 Fury, 17 Protection.
local TALENTS = {
    improved_heroic_strike = { 12282, 12663, 12664 },
    deflection = { 16462, 16463, 16464, 16465, 16466 },
    improved_rend = { 12286, 12658, 12659 },
    improved_charge = { 12285, 12697 },
    improved_tactical_mastery = { 12295, 12676, 12677, 12678, 12679 },
    improved_thunder_clap = { 12287, 12665, 12666 },
    improved_overpower = { 12290, 12963 },
    anger_management = { 12296 },
    deep_wounds = { 12834, 12849, 12867 },
    two_handed_weapon_specialization = { 12163, 12711, 12712, 12713, 12714 },
    impale = { 16493, 16494 },
    axe_specialization = { 12700, 12781, 12783, 12784, 12785 },
    sweeping_strikes = { 12292 },
    mace_specialization = { 12284, 12701, 12702, 12703, 12704 },
    sword_specialization = { 12281, 12812, 12813, 12814, 12815 },
    polearm_specialization = { 12165, 12830, 12831, 12832, 12833 },
    improved_hamstring = { 12289, 12668, 23695 },
    mortal_strike = { 12294 },
    booming_voice = { 12321, 12835, 12836, 12837, 12838 },
    cruelty = { 12320, 12852, 12853, 12855, 12856 },
    improved_demoralizing_shout = { 12324, 12876, 12877, 12878, 12879 },
    unbridled_wrath = { 12322, 12999, 13000, 13001, 13002 },
    improved_cleave = { 12329, 12950, 20496 },
    piercing_howl = { 12323 },
    blood_craze = { 16487, 16489, 16492 },
    improved_battle_shout = { 12318, 12857, 12858, 12860, 12861 },
    dual_wield_specialization = { 23584, 23585, 23586, 23587, 23588 },
    improved_execute = { 20502, 20503 },
    enrage = { 12317, 13045, 13046, 13047, 13048 },
    improved_slam = { 12862, 12330, 20497, 20498, 20499 },
    death_wish = { 12328 },
    improved_intercept = { 20504, 20505 },
    improved_berserker_rage = { 20500, 20501 },
    flurry = { 12319, 12971, 12972, 12973, 12974 },
    bloodthirst = { 23881 },
    shield_specialization = { 12298, 12724, 12725, 12726, 12727 },
    anticipation = { 12297, 12750, 12751, 12752, 12753 },
    improved_bloodrage = { 12301, 12818 },
    toughness = { 12299, 12761, 12762, 12763, 12764 },
    iron_will = { 12300, 12959, 12960, 12961, 12962 },
    last_stand = { 12975 },
    improved_shield_block = { 12945, 12307, 12944 },
    improved_revenge = { 12797, 12799, 12800 },
    defiance = { 12303, 12788, 12789, 12791, 12792 },
    improved_sunder_armor = { 12308, 12810, 12811 },
    improved_disarm = { 12313, 12804, 12807 },
    improved_taunt = { 12302, 12765 },
    improved_shield_wall = { 12312, 12803 },
    concussion_blow = { 12809 },
    improved_shield_bash = { 12311, 12958 },
    one_handed_weapon_specialization = { 16538, 16539, 16540, 16541, 16542 },
    shield_slam = { 23922 },
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

    it("registers the three talent trees, and maps every higher rank spell to its rank 1 for the trait walk", function()
        local n, aliases = 0, 0
        for key, ranks in pairs(TALENTS) do
            n = n + 1
            assert.are.same({ 0, ranks[1], #ranks }, w.talents[key], key)
            for r = 2, #ranks do
                assert.are.equal(ranks[1], w.track[ranks[r]], key .. " rank " .. r)
            end
            aliases = aliases + #ranks - 1
        end
        local registered, tracked = 0, 0
        for _ in pairs(w.talents) do
            registered = registered + 1
        end
        for _ in pairs(w.track) do
            tracked = tracked + 1
        end
        assert.are.same({ 52, 52, 120, 120 }, { n, registered, aliases, tracked })
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
                return { rank = 1, enabled = true }
            end,
        })
        e.swap_stance("berserker_stance")
        assert.are.same({ 25 }, e.spent) -- 50 rage, 10 + 1 x 15 kept (DB2 12295: 15 a rank)
        assert.are.same({ "berserker_stance" }, e.applied)
    end)

    it("silences with Shield Bash from rank 1 of Improved Shield Bash", function()
        local e = lw.env(w)
        lw.run(w.abilities.shield_bash.handler, e)
        assert.are.same({}, e.applied)
        e.talent = setmetatable({}, {
            __index = function()
                return { rank = 1, enabled = true }
            end,
        })
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
            printed[#printed + 1] = line
        end
        pipe:close()
        assert.are.equal(3, #w.packs)
        for i, name in ipairs({ "Arms", "Fury", "Protection" }) do
            assert.are.same({ name, 20261015, printed[i] }, w.packs[i])
        end
        assert.are.same({ package = "Arms" }, w.options)
    end)

    it("writes priorities that name only registered abilities, auras, talents, settings and lists", function()
        local packs = assert(loadfile("tools/make_pack.lua"))("lists")
        local secretToken = require("VirtualState.spec.helpers.load").module().VirtualState.AplSecretToken
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
end)
