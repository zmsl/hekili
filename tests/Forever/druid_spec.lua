-- tests/Forever/druid_spec.lua: the Forever Druid class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through a recording stand-in for Hekili (helpers/load_druid.lua), and its `now`
-- handlers run by VirtualState itself, in Families/Now.lua's strict context. What Hekili does with the rest is verified
-- in game (the plan's checkpoint).
local ld = require("Forever.helpers.load_druid")
local alloc = require("Virtual.State.helpers.alloc")

-- key = { spell IDs in rank order, cost with every talent at rank 0 (a list: by rank; below 1: a fraction of maximum
-- mana), spendType, cooldown, gcd }, from the DB2: energy and mana costs as points, rage as the cost / 10; the
-- cooldown is the larger of RecoveryTime and CategoryRecoveryTime; gcd "totem" for the 1.0 s StartRecoveryTime, "off"
-- where it is 0 or has no row.
local KIT = {
    claw = { { 1082, 3029, 5201, 9849, 9850 }, 45, "energy", 0, "totem" },
    shred = { { 5221, 6800, 8992, 9829, 9830 }, 60, "energy", 0, "totem" },
    rake = { { 1822, 1823, 1824, 9904, 1289140 }, 40, "energy", 0, "totem" },
    rip = { { 1079, 9492, 9493, 9752, 9894, 9896, 1289141 }, 30, "energy", 0, "totem" },
    ferocious_bite = { { 22568, 22827, 22828, 22829, 31018, 1289142 }, 35, "energy", 0, "totem" },
    ravage = { { 6785, 6787, 9866, 9867 }, 60, "energy", 0, "totem" },
    pounce = { { 9005, 9823, 9827 }, 50, "energy", 0, "totem" },
    cower = { { 8998, 9000, 9892 }, 20, "energy", 10, "totem" },
    prowl = { { 5215, 6783, 9913 }, 0, nil, 10, "off" },
    dash = { { 1850, 9821 }, 0, nil, 300, "off" },
    shifting_power = { { 1322605 }, 0.55, "mana", 16, "totem" },
    berserk = { { 417141 }, 0, nil, 180, "off" },
    cat_form = { { 768 }, 0.55, "mana", 0, "spell" },
    bear_form = { { 5487, 9634 }, 0.55, "mana", 0, "spell" },
    moonkin_form = { { 24858 }, 0.35, "mana", 0, "spell" },
    travel_form = { { 783 }, 0.20, "mana", 0, "spell" },
    aquatic_form = { { 1066 }, 0.20, "mana", 0, "spell" },
    maul = { { 6807, 6808, 6809, 8972, 9745, 9880, 9881 }, 15, "rage", 0, "off" },
    swipe_bear = { { 779, 780, 769, 9754, 9908 }, 20, "rage", 0, "spell" },
    primal_bite = { { 407995, 1238069, 1238070, 1238073 }, 20, "rage", 6, "spell" },
    lacerate = { { 414644, 1235826, 1235827 }, 15, "rage", 0, "spell" },
    demoralizing_roar = { { 99, 1735, 9490, 9747, 9898 }, 10, "rage", 0, "spell" },
    growl = { { 6795 }, 0, nil, 8, "off" },
    bash = { { 5211, 6798, 8983 }, 10, "rage", 60, "spell" },
    challenging_roar = { { 5209 }, 15, "rage", 600, "spell" },
    enrage = { { 5229 }, 0, nil, 60, "off" },
    frenzied_regeneration = { { 22842 }, 0, nil, 180, "spell" },
    feral_charge = { { 1238122, 16979 }, 5, "rage", 15, "off" },
    faerie_fire = { { 770, 778, 9749, 9907 }, { 55, 75, 95, 115 }, "mana", 0, "spell" },
    wrath = {
        { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 },
        { 10, 20, 40, 50, 70, 80, 100, 120 },
        "mana",
        0,
        "spell",
    },
    starfire = {
        { 2912, 8949, 8950, 8951, 9875, 9876, 25298 },
        { 95, 135, 180, 230, 275, 315, 340 },
        "mana",
        0,
        "spell",
    },
    moonfire = {
        { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 },
        { 25, 50, 75, 105, 150, 190, 235, 280, 325, 375 },
        "mana",
        0,
        "spell",
    },
    insect_swarm = { { 5570, 24974, 24975, 24976, 24977 }, { 45, 85, 100, 140, 160 }, "mana", 0, "spell" },
    hurricane = { { 16914, 17401, 17402 }, { 880, 1180, 1495 }, "mana", 0, "spell" },
    entangling_roots = { { 339, 1062, 5195, 5196, 9852, 9853 }, { 50, 65, 80, 95, 110, 125 }, "mana", 0, "spell" },
    innervate = { { 29166 }, 0.05, "mana", 360, "spell" },
    barkskin = { { 22812 }, 0, nil, 60, "spell" },
    natures_grasp = { { 16689, 16810, 16811, 16812, 16813, 17329 }, { 50, 65, 80, 95, 110, 125 }, "mana", 60, "spell" },
    mark_of_the_wild = {
        { 1126, 5232, 6756, 5234, 8907, 9884, 9885 },
        { 20, 50, 100, 160, 240, 340, 445 },
        "mana",
        0,
        "spell",
    },
    gift_of_the_wild = { { 21849, 21850 }, { 900, 1200 }, "mana", 0, "spell" },
    thorns = { { 467, 782, 1075, 8914, 9756, 9910 }, { 35, 60, 105, 170, 240, 320 }, "mana", 0, "spell" },
    healing_touch = {
        { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 },
        { 25, 55, 110, 190, 280, 350, 425, 520, 630, 755, 840 },
        "mana",
        0,
        "spell",
    },
    regrowth = {
        { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },
        { 70, 125, 170, 210, 250, 305, 370, 445, 525 },
        "mana",
        0,
        "spell",
    },
    rejuvenation = {
        { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },
        { 25, 40, 75, 105, 135, 160, 195, 235, 280, 335, 360 },
        "mana",
        0,
        "spell",
    },
}

-- key = { rank 1's spell, max rank }: the DB2's 47 Classic nodes (`wowdb talents DRUID`), then the three placeholders
-- the live export (checkpoint Q1) replaces.
local TALENTS = {
    improved_wrath = { 16814, 5 },
    natures_grasp = { 16689, 1 },
    improved_natures_grasp = { 17245, 4 },
    improved_entangling_roots = { 16918, 3 },
    improved_moonfire = { 16821, 5 },
    natural_weapons = { 16902, 5 },
    natural_shapeshifter = { 16833, 3 },
    improved_thorns = { 16836, 3 },
    omen_of_clarity = { 16864, 1 },
    natures_reach = { 16819, 2 },
    vengeance = { 16909, 5 },
    improved_starfire = { 16850, 5 },
    natures_grace = { 16880, 1 },
    moonglow = { 16845, 3 },
    moonfury = { 16896, 5 },
    moonkin_form = { 24858, 1 },
    ferocity = { 16934, 5 },
    feral_aggression = { 16858, 5 },
    feral_instinct = { 16947, 5 },
    brutal_impact = { 16940, 2 },
    thick_hide = { 16929, 5 },
    feline_swiftness = { 17002, 2 },
    feral_charge = { 16979, 1 },
    sharpened_claws = { 16942, 3 },
    improved_shred = { 16966, 2 },
    predatory_strikes = { 16972, 3 },
    blood_frenzy = { 16952, 2 },
    primal_fury = { 16958, 2 },
    savage_fury = { 16998, 2 },
    faerie_fire_feral = { 16857, 1 },
    heart_of_the_wild = { 17003, 5 },
    leader_of_the_pack = { 17007, 1 },
    improved_mark_of_the_wild = { 17050, 5 },
    furor = { 17056, 5 },
    improved_healing_touch = { 17069, 5 },
    natures_focus = { 17063, 5 },
    improved_enrage = { 17079, 2 },
    reflection = { 17106, 3 },
    insect_swarm = { 5570, 1 },
    subtlety = { 17118, 5 },
    tranquil_spirit = { 24968, 5 },
    improved_rejuvenation = { 17111, 3 },
    natures_swiftness = { 17116, 1 },
    gift_of_nature = { 17104, 5 },
    improved_tranquility = { 17123, 2 },
    improved_regrowth = { 17074, 5 },
    swiftmend = { 18562, 1 },
    improved_shifting_power = { 1322670, 2 },
    natures_splendor = { 1223083, 1 },
    eclipse = { 408248, 3 },
}

-- The abilities whose cast changes the now-state beyond its declared cost, cooldown and GCD (spec §4).
local NOW = {
    "rake",
    "rip",
    "ferocious_bite",
    "ravage",
    "pounce",
    "prowl",
    "dash",
    "shifting_power",
    "berserk",
    "cat_form",
    "bear_form",
    "moonkin_form",
    "travel_form",
    "aquatic_form",
    "lacerate",
    "demoralizing_roar",
    "growl",
    "bash",
    "challenging_roar",
    "enrage",
    "frenzied_regeneration",
    "feral_charge",
    "faerie_fire",
    "wrath",
    "moonfire",
    "insect_swarm",
    "entangling_roots",
    "innervate",
    "barkskin",
    "natures_grasp",
    "mark_of_the_wild",
    "gift_of_the_wild",
    "thorns",
    "hurricane",
}

-- Clearcasting's covered abilities (spec §7), by rank 1's ID.
local COVERED = {
    8921,
    2912,
    5570,
    16914,
    5185,
    8936,
    774,
    1082,
    1822,
    5221,
    1079,
    22568,
    9005,
    6785,
    779,
    6807,
    414644,
    5211,
    1238122,
    339,
    467,
    16689,
    407995,
    99,
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

local function near(want, got)
    assert.is_true(math.abs(got - want) < 1e-9, ("want %.4f, got %.4f"):format(want, got))
end

-- A buff/debuff table whose named keys are up (with the given fields) and the rest down.
local function auras(up)
    return setmetatable(up, {
        __index = function()
            return { up = false, remains = 0, stack = 0, applied = 0 }
        end,
    })
end

describe("Forever Druid", function()
    local w

    before_each(function()
        w = ld.load()
    end)

    it(
        "registers the kit with the DB2's ranks, costs, cooldowns and GCDs, and no rune or Tiger's Fury spell",
        function()
            local e = ld.env(w)
            local n = 0
            for key, a in pairs(w.abilities) do
                n = n + 1
                local want = KIT[key]
                assert.is_not_nil(want, "unexpected ability " .. key)
                assert.are.same(want[1], idsOf(a), key)
                assert.are.same({ want[3], want[4], want[5] }, { a.spendType, ld.run(a.cooldown, e), a.gcd }, key)
                assert.are.equal("function", type(a.known), key)
                if type(want[2]) == "table" then
                    for r, cost in ipairs(want[2]) do -- the cost of each rank, as the spellbook learns it
                        w.game.known[want[1][r]] = true
                        assert.are.equal(cost, ld.run(a.spend, e), key .. " rank " .. r)
                    end
                else
                    assert.are.equal(want[2], ld.run(a.spend, e) or 0, key)
                end
            end
            assert.are.equal(44, n)
            local stale = { tigers_fury = true }
            for _, id in ipairs({
                5217,
                417045,
                407988,
                417157,
                414684,
                439748,
                408124,
                408247,
                408120,
                410176,
                411128,
                414924,
            }) do
                stale[id] = true
            end
            for key, a in pairs(w.abilities) do
                assert.is_nil(stale[key], key)
                for _, id in ipairs(idsOf(a)) do
                    assert.is_nil(stale[id], key .. " " .. id)
                end
            end
            assert.is_true(w.abilities.maul.onNextSwing)
            assert.are.same({ true, 10 }, { w.abilities.hurricane.channeled, w.abilities.hurricane.cast })
            -- Wrath's cast at its top rank (the cost loop above learned every rank)
            assert.are.same(
                { 2, 3.5, 2 },
                { ld.run(w.abilities.wrath.cast, e), w.abilities.starfire.cast, w.abilities.regrowth.cast }
            )
        end
    )

    it("models the talent-modified costs from rank 1's value x the rank, floored at 0", function()
        local e = ld.env(w)
        e.talent = rank(2)
        local function at(key)
            return ld.run(w.abilities[key].spend, e)
        end
        -- Ferocity -1 a rank; Shredding Attacks -6 a rank (Shred; Lacerate by its DB2 text, checkpoint Q12)
        assert.are.same(
            { 43, 38, 13, 18, 18, 48, 3 },
            { at("claw"), at("rake"), at("maul"), at("swipe_bear"), at("primal_bite"), at("shred"), at("lacerate") }
        )
        -- Natural Shapeshifter -10% a rank on the forms and Shifting Power
        for key, cost in pairs({
            cat_form = 0.44,
            bear_form = 0.44,
            shifting_power = 0.44,
            moonkin_form = 0.28,
            travel_form = 0.16,
            aquatic_form = 0.16,
        }) do
            near(cost, at(key))
        end
        assert.are.same(
            { 8, 1.3 },
            { ld.run(w.abilities.shifting_power.cooldown, e), ld.run(w.abilities.wrath.cast, e) }
        )
        e.talent = rank(5)
        assert.are.same({ 40, 0, 30 }, { at("claw"), at("lacerate"), at("shred") })
    end)

    it(
        "gates every ability on the form it needs, Ravage and Pounce on Prowl, Faerie Fire free only in Cat or Bear",
        function()
            local a = w.abilities
            local gates = {
                cat_form = {
                    "claw",
                    "shred",
                    "rake",
                    "rip",
                    "ferocious_bite",
                    "cower",
                    "prowl",
                    "dash",
                    "shifting_power",
                },
                prowl = { "ravage", "pounce" },
                bear_form = {
                    "maul",
                    "swipe_bear",
                    "primal_bite",
                    "lacerate",
                    "demoralizing_roar",
                    "growl",
                    "bash",
                    "challenging_roar",
                    "enrage",
                    "frenzied_regeneration",
                    "feral_charge",
                },
            }
            for gate, keys in pairs(gates) do
                for _, k in ipairs(keys) do
                    assert.are.same({ gate, nil }, { a[k].buff, a[k].nobuff }, k)
                end
            end
            for _, k in ipairs({
                "wrath",
                "starfire",
                "moonfire",
                "insect_swarm",
                "hurricane",
                "entangling_roots",
                "healing_touch",
                "regrowth",
                "rejuvenation",
                "mark_of_the_wild",
                "gift_of_the_wild",
                "thorns",
                "innervate",
                "natures_grasp",
            }) do
                assert.are.same({ nil, "feral_form" }, { a[k].buff, a[k].nobuff }, k)
            end
            for _, k in ipairs({ "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form" }) do
                assert.are.same({ nil, k }, { a[k].buff, a[k].nobuff }, k)
            end
            for _, k in ipairs({ "faerie_fire", "barkskin" }) do
                assert.are.same({ nil, nil }, { a[k].buff, a[k].nobuff }, k)
            end
            local e = ld.env(w)
            assert.are.same(
                { "cat_form", 55, 0 },
                { ld.run(a.berserk.buff, e), ld.run(a.faerie_fire.spend, e), ld.run(a.faerie_fire.cooldown, e) }
            )
            e.buff = auras({ bear_form = { up = true }, feral_form = { up = true } })
            assert.are.same(
                { "bear_form", 0, 6 },
                { ld.run(a.berserk.buff, e), ld.run(a.faerie_fire.spend, e), ld.run(a.faerie_fire.cooldown, e) }
            )
        end
    )

    it("registers the DB2's 47 talent nodes and the three placeholders, and no rank aliases", function()
        local n, registered = 0, 0
        for key, t in pairs(TALENTS) do
            n = n + 1
            assert.are.same({ 0, t[1], t[2] }, w.talents[key], key)
        end
        for _ in pairs(w.talents) do
            registered = registered + 1
        end
        assert.are.same({ 50, 50 }, { n, registered })
    end)

    it("reads only registered talent keys, in the class file and every race file", function()
        local files = { "src/Hekili/Forever/Classes/Druid.lua" }
        local ls = assert(io.popen("ls src/Hekili/Forever/Races/*.lua"))
        for f in ls:lines() do
            files[#files + 1] = f
        end
        ls:close()
        local n = 0
        for _, f in ipairs(files) do
            local src = assert(io.open(f)):read("*a")
            for key in src:gmatch("talent%.([%w_]+)") do
                n = n + 1
                assert.is_not_nil(w.talents[key], f .. ": talent." .. key .. " is not registered")
            end
        end
        assert.is_true(n > 0)
    end)

    it("registers every aura a handler, `now`, state function, gate, resource entry or alias names", function()
        local e = ld.env(w)
        e.talent = rank(1) -- Wrath's Eclipse
        for _, a in pairs(w.abilities) do
            ld.run(a.handler, e)
            ld.run(a.now, e)
            ld.run(a.start, e)
            for _, gate in ipairs({ ld.run(a.buff, e), a.nobuff, a.aura }) do
                table.insert(e.applied, gate)
            end
        end
        e.swap_form("bear_form")
        for _, m in pairs(w.resources[1].models) do
            table.insert(e.applied, m.aura)
        end
        for _, alias in ipairs({ w.auras.form, w.auras.feral_form, w.auras.bleed }) do
            for _, k in ipairs(alias.alias) do
                table.insert(e.applied, k)
            end
        end
        table.insert(e.applied, w.costMods[1].aura)
        for _, list in ipairs({ e.applied, e.removed, e.added }) do
            for _, k in ipairs(list) do
                k = type(k) == "table" and k[1] or k
                assert.is_not_nil(w.auras[k], "unregistered aura " .. tostring(k))
            end
        end
    end)

    describe("the now-state (spec §4, event-facade spec §12a)", function()
        it("declares `now` beside `handler` exactly on the abilities whose cast changes more than its cost", function()
            local has = {}
            for _, k in ipairs(NOW) do
                has[k] = true
            end
            for key, a in pairs(w.abilities) do
                assert.are.equal(has[key] == true, type(a.now) == "function", key)
                if a.now then
                    assert.are_not.equal(a.now, a.handler, key) -- two closures: one shared would be refused
                end
            end
        end)

        it(
            "writes the debuffs, Lacerate's stack to 5, Pounce's stun with Brutal Impact and Bash's at rank 0",
            function()
                local e = ld.env(w)
                for _, k in ipairs({ "rake", "rip", "demoralizing_roar", "faerie_fire" }) do
                    ld.run(w.abilities[k].now, e)
                end
                assert.are.same({ "rake", "rip", "demoralizing_roar", "faerie_fire" }, e.applied)
                e = ld.env(w)
                e.debuff = auras({ lacerate = { up = true, stack = 4 } })
                ld.run(w.abilities.lacerate.now, e)
                assert.are.same({ 15, 5 }, { e.durations.lacerate, e.stacks.lacerate })
                e.debuff = auras({ lacerate = { up = true, stack = 5 } })
                ld.run(w.abilities.lacerate.now, e)
                assert.are.equal(5, e.stacks.lacerate)
                e = ld.env(w)
                e.talent = rank(2)
                ld.run(w.abilities.pounce.now, e)
                assert.are.same(
                    { { "pounce", "pounce_bleed" }, { "prowl" }, 3 },
                    { e.applied, e.removed, e.durations.pounce }
                )
                e = ld.env(w)
                ld.run(w.abilities.bash.now, e) -- the spellbook answers 0: rank 1's 2 s
                assert.are.equal(2, e.durations.bash)
                w.game.known[5211], w.game.known[6798] = true, true
                e.talent = rank(1)
                ld.run(w.abilities.bash.now, e)
                assert.are.equal(3.5, e.durations.bash)
                w.game.known[8921], w.game.known[8924] = true, true
                ld.run(w.abilities.moonfire.now, e)
                ld.run(w.abilities.insect_swarm.now, e)
                assert.are.same({ 15, 14 }, { e.durations.moonfire, e.durations.insect_swarm }) -- Nature's Splendor
            end
        )

        it("gains Shifting Power's 40 energy and Enrage's 10 rage, and Bite spends the energy left", function()
            local e = ld.env(w)
            ld.run(w.abilities.shifting_power.now, e)
            ld.run(w.abilities.enrage.now, e)
            e.energy.current = 25
            ld.run(w.abilities.ferocious_bite.now, e)
            assert.are.same({ { 40, "energy" }, { 10, "rage" } }, e.gained)
            assert.are.same({ { 25, "energy" } }, e.spent)
            assert.are.same({ "enrage" }, e.applied)
        end)

        it("adds Wrath's Eclipse charges only with the talent, and Starfire's handler spends one", function()
            local e = ld.env(w)
            ld.run(w.abilities.wrath.now, e)
            assert.are.same({}, e.added)
            e.talent = rank(1)
            ld.run(w.abilities.wrath.now, e)
            ld.run(w.abilities.wrath.handler, e)
            assert.are.same({ { "eclipse", 2 }, { "eclipse", 2 } }, e.added)
            ld.run(w.abilities.starfire.handler, e)
            assert.are.same({}, e.removed)
            e.buff = auras({ eclipse = { up = true, stack = 2 } })
            ld.run(w.abilities.starfire.handler, e)
            assert.are.same({ "eclipse" }, e.removed)
        end)

        it("writes no combo points from any `now`", function()
            local e = ld.env(w)
            e.talent = rank(1)
            for _, k in ipairs(NOW) do
                ld.run(w.abilities[k].now, e)
            end
            for _, list in ipairs({ e.gained, e.spent }) do
                for _, v in ipairs(list) do
                    assert.are_not.equal("combo_points", v[2])
                end
            end
        end)
    end)

    it("shifts: Bear Form spends all rage and removes the other forms and Maul; Cat Form writes no energy", function()
        local e = ld.env(w)
        e.rage.current = 40
        ld.run(w.abilities.bear_form.now, e)
        assert.are.same({ { 40, "rage" } }, e.spent)
        assert.are.same({ "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form", "maul" }, e.removed)
        assert.are.same({ "bear_form" }, e.applied)
        e = ld.env(w)
        ld.run(w.abilities.cat_form.now, e)
        e.swap_form("cat_form")
        assert.are.same({ {}, {}, { "cat_form", "cat_form" } }, { e.spent, e.gained, e.applied })
        e = ld.env(w)
        e.rage.current = 30
        e.swap_form("bear_form")
        assert.are.same({ { 30, "rage" } }, e.spent)
    end)

    it("reads Maul's queue at reset, leaving the form to the Forms source", function()
        local e = ld.env(w)
        w.game.form, w.game.formSpell[2] = 2, 9634
        w.game.known[6807], w.game.current[6807] = true, true
        e.now, e.query_time = 10, 10
        ld.run(w.hooks.reset_precast, e)
        assert.are.same({ "maul" }, e.applied)
        assert.are.same({}, e.removed)
    end)

    it(
        "gains rage per white swing in Bear Form only, at the form's fixed 2.5 s x 3.46; Enrage 2/s; decay 1.25",
        function()
            local models = w.resources[1].models
            w.state.buff.bear_form = { up = false }
            w.state.swings.mainhand, w.state.mainhand_speed = 5, 2.5
            assert.are.same(
                { "mainhand", "bear_form", "mainhand_speed" },
                { models.mainhand.swing, models.mainhand.aura, models.mainhand.interval }
            )
            assert.is_true(models.mainhand.stop()) -- out of Bear Form
            w.state.buff.bear_form.up = true
            assert.is_false(models.mainhand.stop())
            near(2.5 * 3.46, models.mainhand.value()) -- before a plain base read
            w.game.base = { 1.0, 0 } -- a Cat pull's base, stale after the shift (D4: the form's period, not the read)
            w.state.mainhand_speed = 2.0 -- hasted: the rage follows the unhasted speed
            near(8.65, models.mainhand.value())
            near(8.65, models.mainhand.crit()) -- a white crit: one more base swing
            assert.are.same({ "enrage", 1, 2 }, { models.enrage.aura, models.enrage.interval, models.enrage.value })
            assert.is_nil(models.enrage.pausesDecay) -- unverified (checkpoint Q9)
            w.state.buff.enrage, w.state.query_time = { applied = 10 }, 13.4
            assert.are.equal(13, models.enrage.last())
            assert.are.equal(1.25, w.resources[1].meta.decay())
            assert.are.equal(1, w.resources[1].meta.decayInterval()) -- stepped, as the Warrior's
        end
    )

    it("declares energy with no regen model, combo points and mana with no maximum, in Classic's order", function()
        assert.are.same({ 3, 4, 1, 0 }, w.order)
        for _, pt in ipairs({ 3, 4, 0 }) do
            assert.are.same({ nil, nil }, { w.resources[pt].models, w.resources[pt].meta }, pt)
        end
        assert.is_nil(w.resources[1].meta.max)
    end)

    it("declares Clearcasting as one cost modifier over the covered rank-1 IDs, and no `spend` reads it", function()
        assert.are.equal(1, #w.costMods)
        local m = w.costMods[1]
        assert.are.same({ "clearcasting", -1, 1, COVERED }, { m.aura, m.pct, m.charges, m.spells })
        local first = {}
        for _, a in pairs(w.abilities) do
            first[a.id] = true
        end
        for _, id in ipairs(m.spells) do
            assert.is_true(first[id], tostring(id)) -- each is the rank-1 ID of a registered ability
        end
        local src = assert(io.open("src/Hekili/Forever/Classes/Druid.lua")):read("*a")
        assert.is_nil(src:find("buff%.clearcasting")) -- the modifier, not each `spend`, prices it
    end)

    describe("the combat log and the not-behind window", function()
        local ME, MOB = "Player-1", "Creature-1"

        local function row(t, sub, spellID)
            w.game.now = t
            w.game.row = { t, sub, false, ME, "", 0, 0, MOB, "", 0, 0, spellID, "", 1, "DODGE" }
            w.events.COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED")
        end

        local function reset(t, debuffs)
            local e = ld.env(w)
            e.now, e.query_time = t, t
            e.debuff = auras(debuffs or {})
            ld.run(w.hooks.reset_precast, e)
            return e
        end

        local function removed(e, key)
            for _, k in ipairs(e.removed) do
                if k == key then
                    return true
                end
            end
            return false
        end

        before_each(function()
            w.state.GUID = ME
        end)

        it("removes a missed Rake or Rip at the next reset, not a hit or a newer application", function()
            row(10, "SPELL_MISSED", 1823) -- Rake rank 2, dodged
            assert.is_true(removed(reset(11, { rake = { up = true, applied = 9.9 } }), "rake"))
            assert.is_false(removed(reset(13, { rake = { up = true, applied = 12 } }), "rake")) -- reapplied since
            row(20, "SPELL_CAST_SUCCESS", 1079) -- a Rip that landed
            assert.is_false(removed(reset(21, { rip = { up = true, applied = 20 } }), "rip"))
            row(30, "SPELL_MISSED", 9827) -- Pounce: its bleed
            assert.is_true(removed(reset(31, { pounce_bleed = { up = true, applied = 29.9 } }), "pounce_bleed"))
        end)

        it("opens not_behind for the rest of 5 s after a listed error, never for another", function()
            w.spec.notBehindErrors[51] = true -- the type checkpoint Q11 records
            w.game.now = 20
            w.events.UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 50, "Another error.")
            assert.is_nil(reset(21).durations.not_behind)
            w.events.UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 51, "You must be behind your target.")
            assert.are.equal(3, reset(22).durations.not_behind)
            assert.is_nil(reset(25.5).durations.not_behind)
        end)
    end)

    describe("excess_e (ported from Taco Dog Forever)", function()
        local e, excess

        before_each(function()
            e = ld.env(w)
            e.energy = { current = 100, max = 100, regen = 10 }
            e.combo_points.current = 5
            e.debuff = auras({ rip = { remains = 5 }, rake = { remains = 6 } })
            e.cooldown = setmetatable({ shifting_power = { remains = 30 } }, getmetatable(e.cooldown))
            e.action = setmetatable({ rip = { cost = 30 }, rake = { cost = 40 } }, getmetatable(e.action))
            for _, id in ipairs({ 1079, 1822, 1322605 }) do
                w.game.known[id] = true
            end
            excess = setfenv(w.exprs.excess_e, e)
        end)

        it("allows Shred when the energy covers it, Rip and Rake in time", function()
            -- Rake's 40 at 6 s, Rip's 30 at 5 s less 10 s of regen: 10 held back
            assert.are.equal(90, excess())
        end)

        it("holds Shred when Rip at 5 combo points is due within the regen", function()
            e.energy.current = 40
            e.debuff = auras({ rip = { remains = 2 }, rake = { remains = 9 } })
            assert.are.equal(30, excess()) -- below Shred's 60
            e.combo_points.current = 4 -- Rip not due at settings.rip_cp: nothing for it
            assert.are.equal(40, excess())
        end)

        it("credits Shifting Power's 40 once it is off cooldown", function()
            e.energy.current = 40
            e.debuff = auras({ rip = { remains = 2 }, rake = { remains = 9 } })
            e.cooldown.shifting_power.remains = 0
            assert.are.equal(40, excess())
        end)

        it("is -math.huge when the spender's GCD would delay a refresh that could start on time", function()
            e.debuff = auras({ rip = { remains = 0.5 }, rake = { remains = 6 } })
            assert.are.equal(-math.huge, excess())
            e.energy.current = 20 -- Rip could not start on time anyway
            assert.is_true(excess() > -math.huge)
        end)

        it("reserves nothing for a Rip the druid does not know", function()
            w.game.known[1079] = nil
            e.energy.current = 40
            e.debuff = auras({ rip = { remains = 2 }, rake = { remains = 9 } })
            assert.are.equal(40, excess())
        end)

        it("allocates nothing over 1000 calls", function()
            assert.are.equal(
                0,
                alloc.bytes(function()
                    excess()
                end, 1000)
            )
        end)
    end)

    it("reads shred_ok from the behind setting, the group and the not-behind window", function()
        local e = ld.env(w)
        local ok = function()
            return ld.run(w.exprs.shred_ok, e)
        end
        assert.is_false(ok())
        e.group = true
        assert.is_true(ok())
        e.buff = auras({ not_behind = { up = true } })
        assert.is_false(ok())
        e.settings.behind = true
        assert.is_true(ok())
    end)

    it("registers the Feral, Guardian and Balance packs exactly as tools/make_pack.lua druid prints them", function()
        local printed = {}
        local pipe = assert(io.popen("lua5.1 tools/make_pack.lua druid"))
        for line in pipe:lines() do
            printed[#printed + 1] = { line:match("^(%d+) (.+)$") }
        end
        pipe:close()
        assert.are.equal(3, #w.packs)
        for i, name in ipairs({ "Feral", "Guardian", "Balance" }) do
            assert.are.same({ name, tonumber(printed[i][1]), printed[i][2] }, w.packs[i])
        end
        assert.are.equal(w.specID, dofile("tools/packs/druid.lua").spec) -- the packs' spec is the file's
    end)

    it("writes priorities that name only registered abilities, auras, talents, settings and lists", function()
        local packs = assert(loadfile("tools/make_pack.lua"))("lists", "druid")
        local secretToken = require("Virtual.State.helpers.load").module().VirtualState.AplSecretToken
        local shared = { use_items = true } -- Hekili's `all` (Forever/Shared/Items.lua's use_items)
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
                        assert.is_true(
                            w.abilities[e.action] ~= nil or shared[e.action],
                            where .. ": no ability " .. e.action
                        )
                    end
                    local c = e.criteria or ""
                    for kind, key in c:gmatch("(%a+)%.([%w_]+)") do
                        if kinds[kind] then
                            assert.is_not_nil(kinds[kind][key], where .. ": no " .. kind .. " " .. key)
                        end
                    end
                    assert.is_nil(secretToken(c), where) -- no health or time to die: secret on Forever
                end
            end
        end
        for _, name in ipairs({ "excess_e", "shred_ok" }) do
            assert.are.equal("function", type(w.exprs[name]), name)
        end
    end)

    it(
        "declares its pseudo-spec once, as a placeholder until checkpoint Q1, and the settings the packs read",
        function()
            assert.are.equal(1499, w.specID)
            for key, default in pairs({
                rip_cp = 5,
                bite_finisher = false,
                behind = false,
                buffs = true,
                dump_rage = 60,
                use_enrage = false,
                moonkin = true,
                trash_dots = true,
                starfire_filler = false,
                hurricane_targets = 4,
                innervate = true,
            }) do
                assert.are.equal(default, w.settings[key].default, key)
            end
            assert.are.same({ package = "Feral" }, w.options)
        end
    )
end)

-- The Druid's `now` handlers as VirtualState runs them: bound to Families/Now.lua's context (Hekili's verbs onto the
-- belief, nothing else reachable), on our own casts' success.
describe("Forever Druid in VirtualState's now context", function()
    local load = require("Virtual.State.helpers.load")
    local fake = require("Virtual.State.helpers.fake_api")
    local fs = require("Virtual.State.helpers.fake_spec")
    local dvs = require("Forever.helpers.druid_vs")
    local ns, VS, I, api, ctl, w, h, saved

    local function cast(id, t)
        ctl.now = t
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
        ctl.Tick(t + 0.01)
        VS.Drain(t + 0.02)
    end

    local function power(pt, t)
        return VS.Power(pt, t).est
    end

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        saved = {}
        for _, k in ipairs({ "GetTime", "UnitGUID", "CreateFrame", "issecretvalue", "debugprofilestop" }) do
            saved[k] = rawget(_G, k) or false
        end
        _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue =
            api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
        _G.debugprofilestop = function()
            return 0
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        w, h = dvs.boot(ns, api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        fs.clock = nil
    end)

    it("runs a Feral and a bear sequence: costs, energy, forms, debuffs and bear rage, with no `now` error", function()
        I.Sources.Direct(VS.Obs.CombatStart, 1.5) -- in combat: no rage decay
        cast(768, 2) -- Cat Form: 55 mana (0.55 of the declared 100)
        assert.is_not_nil(VS.Aura("player", 768, 2.1))
        near(45, power(0, 2.1))
        cast(5221, 3) -- Shred: 60 of 100 energy
        cast(1322605, 4) -- Shifting Power: +40
        assert.are.equal(80, power(3, 4.1))
        cast(1822, 5) -- Rake: 40, and its 9 s debuff
        assert.are.equal(14, VS.Aura("target", 1822, 5.1).est)
        cast(22568, 6) -- Ferocious Bite: 35, then the 5 left
        assert.are.equal(0, power(3, 6.1))
        cast(5487, 7) -- Bear Form
        assert.are.same({ true, false }, { VS.Aura("player", 5487, 7.1) ~= nil, VS.Aura("player", 768, 7.1) ~= nil })
        I.Sources.Direct(VS.Obs.Swing, 8, 1, 2.5, 4) -- PLAYER_SWING, then Rows.lua's landed wound
        I.Sources.Direct(VS.Obs.Swing, 8, 1, 0, 1)
        VS.Drain(8)
        near(8.65, power(1, 8))
        cast(5229, 9) -- Enrage: 10 now, 2 a second
        I.Settle(12)
        near(8.65 + 10 + 6, power(1, 12))
        cast(414644, 13) -- Lacerate twice: 2 stacks
        cast(414644, 14)
        assert.are.equal(2, select(2, VS.Aura("target", 414644, 14.1)))
        cast(768, 15) -- back to Cat Form: the swing pays nothing
        I.Sources.Direct(VS.Obs.Swing, 16, 1, 2.5, 4)
        I.Sources.Direct(VS.Obs.Swing, 16, 1, 0, 1)
        VS.Drain(16)
        assert.are.equal(power(1, 15.1), power(1, 16))
        assert.are.same({ 0, 9 }, { I.nowErrors, I.nowRuns })
    end)

    it("opens each GCD at its kind's length across shifts, and a hard cast's at its start (GCD kinds §1.6)", function()
        local Direct, Obs = I.Sources.Direct, VS.Obs
        local function gcd(t, len) -- the GCD spell's edges around our cast at t: its duration as GcdInfo answers it
            Direct(Obs.Cooldown, t, 0, 1, 1)
            VS.Drain(t + 0.03)
            local _, d = VS.GcdInfo(t + 0.03)
            Direct(Obs.Cooldown, t + len, 0, 0, 1)
            VS.Drain(t + len + 0.01)
            return d
        end
        cast(5221, 2) -- Shred x2: the totem kind learns 1.0
        gcd(2, 1)
        cast(5221, 4)
        gcd(4, 1)
        assert.are.same({ 0, 1 }, I.gcdLearned)
        cast(5487, 6) -- Bear Form: the spell kind, not the last learned length
        assert.are.equal(1.5, gcd(6, 1.5))
        cast(768, 8) -- Cat Form
        gcd(8, 1.5)
        cast(5221, 10)
        assert.are.equal(1, gcd(10, 1))
        ctl.form = 0 -- a manual unshift (no cast), then Healing Touch's hard cast
        ctl.Fire("UPDATE_SHAPESHIFT_FORM")
        ctl.now, ctl.casting = 12, { 12000, 15500 }
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-2", 5185)
        ctl.Tick(12.01)
        ctl.casting = nil
        assert.are.equal(1.5, gcd(12.02, 1.5))
        assert.is_truthy(VS.Snapshot():find("learned=1.5000/1.0000", 1, true))
    end)

    it("runs every declared `now` in the context without an error", function()
        local runs = 0
        local t = 2
        for _, a in pairs(w.abilities) do
            if a.now then
                t = t + 1
                cast(a.id, t)
                runs = runs + 1
            end
        end
        assert.are.same({ 0, runs }, { I.nowErrors, I.nowRuns }, tostring(I.nowError))
    end)

    it("makes a covered cast free while Clearcasting is believed up, which the cast then takes", function()
        cast(5221, 2) -- 40 energy left
        I.AuraModel(1, I.auras.bySpell[16870], 3, 18, 1, 3, VS.Obs.CastSuccess, false)
        cast(5221, 4) -- free
        assert.are.same({ 40, nil }, { power(3, 4.1), VS.Aura("player", 16870, 4.1) })
        cast(5221, 5)
        assert.are.equal(0, power(3, 5.1))
    end)

    it("allocates nothing over 1000 casts with `now` handlers", function()
        function h:ForceUpdate() end -- the fake records each call; Hekili's own only sets fields
        local t = 2
        local bytes = alloc.bytes(function()
            t = t + 1
            cast(1322605, t)
            cast(1822, t + 0.3)
            cast(414644, t + 0.6)
        end, 1000)
        assert.are.equal(0, bytes)
    end)
end)
