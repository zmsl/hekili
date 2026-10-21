-- tests/Forever/druid_spec.lua: the Forever Druid class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through a recording stand-in for Hekili (helpers/load_druid.lua), and its `now`
-- handlers run by VirtualState itself, in Families/Now.lua's strict context. What Hekili does with the rest is verified
-- in game (the plan's checkpoint).
local ld = require("Forever.helpers.load_druid")
local alloc = require("Game.State.helpers.alloc")
-- the project interpreter when bootstrapped, else the system one (as tools/list_api_reads.sh picks it)
local LUA = io.open(".lua/bin/lua") and ".lua/bin/lua" or "lua5.1"

-- key = { spell IDs in rank order, cost with every talent at rank 0 (a list: by rank; a percent of base mana as whole
-- mana at 60: the fraction x the mana meta's `base` 1244, floored), spendType, cooldown, gcd }, from the DB2: energy and mana costs as points, rage as the cost /
-- 10; the cooldown is the larger of RecoveryTime and CategoryRecoveryTime; gcd "totem" for the 1.0 s
-- StartRecoveryTime, "off" where it is 0 or has no row.
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
    shifting_power = { { 1322605 }, 684, "mana", 16, "totem" },
    berserk = { { 417141 }, 0, nil, 180, "off" },
    cat_form = { { 768 }, 684, "mana", 0, "spell" },
    bear_form = { { 5487, 9634 }, 684, "mana", 0, "spell" },
    moonkin_form = { { 24858 }, 435, "mana", 0, "spell" },
    travel_form = { { 783 }, 248, "mana", 0, "spell" },
    aquatic_form = { { 1066 }, 248, "mana", 0, "spell" },
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
    innervate = { { 29166 }, 62, "mana", 360, "spell" },
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
    improved_shred = { 16966, 3 }, -- wowsims/forever's 3 points (Shred 42 at 3/3; the DB2 node lists 2 rank spells)
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

-- A declared mana cost as the engine prices it: a fraction is of the mana meta's `base`, floored (Spec.lua).
local function priced(w, c, spendType)
    if spendType == "mana" and c and c > 0 and c < 1 then
        return math.floor(c * w.resources[0].meta.base + 1e-6)
    end
    return c
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
                        assert.are.equal(cost, priced(w, ld.run(a.spend, e), a.spendType), key .. " rank " .. r)
                    end
                else
                    assert.are.equal(want[2], priced(w, ld.run(a.spend, e), a.spendType) or 0, key)
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
        -- Ferocity -1 a rank; Shredding Attacks -6 a rank on Shred, -1 on Lacerate (wowsims's log: Cost = 13 at 2/3;
        -- the DB2 text reads 6, checkpoint Q12)
        assert.are.same(
            { 43, 38, 13, 18, 18, 48, 13 },
            { at("claw"), at("rake"), at("maul"), at("swipe_bear"), at("primal_bite"), at("shred"), at("lacerate") }
        )
        -- Natural Shapeshifter -10% a rank on the forms and Shifting Power: a fraction of the base mana
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
        -- at 60 of the base mana, 1244 (wowsims's log: Shifting Power and Cat Form 684 = 55%, Innervate 62 = 5%)
        assert.are.equal(1244, w.resources[0].meta.base)
        local function mana(key)
            return priced(w, at(key), "mana")
        end
        assert.are.same({ 547, 348 }, { mana("shifting_power"), mana("moonkin_form") })
        e.talent = rank(0)
        assert.are.same({ 684, 684, 62 }, { mana("shifting_power"), mana("cat_form"), mana("innervate") })
        e.talent = rank(2)
        assert.are.same(
            { 8, 1.3 },
            { ld.run(w.abilities.shifting_power.cooldown, e), ld.run(w.abilities.wrath.cast, e) }
        )
        e.talent = rank(5)
        assert.are.same({ 40, 10, 30 }, { at("claw"), at("lacerate"), at("shred") })
    end)

    it(
        "cuts the Balance spells' mana by Moonglow and Wrath's by Improved Wrath (wowsims's log at 3/3 and 5/5)",
        function()
            local e = ld.env(w)
            e.talent = setmetatable({ moonglow = { rank = 3 }, improved_wrath = { rank = 5 } }, {
                __index = function()
                    return { rank = 0, enabled = false }
                end,
            })
            for _, id in ipairs({ 9912, 9835, 25298, 24977 }) do
                w.game.known[id] = true
            end
            -- DB2 16845 -25% and 16814 -50% at the full ranks; wowsims: Wrath 45, Moonfire 281.25, Starfire 255, IS 120
            assert.are.same({ 45, 281.25, 255, 120 }, {
                ld.run(w.abilities.wrath.spend, e),
                ld.run(w.abilities.moonfire.spend, e),
                ld.run(w.abilities.starfire.spend, e),
                ld.run(w.abilities.insect_swarm.spend, e),
            })
            -- below 3/3 wowsims's ladder (spells_auto_gen.go 16845: -8, -17, -25), not pro rata: Moonfire's 375
            for r, want in ipairs({ 345, 311.25 }) do
                e.talent.moonglow.rank = r
                assert.is_near(want, ld.run(w.abilities.moonfire.spend, e), 1e-9)
            end
        end
    )

    it(
        "takes 1 s off Shifting Power's cooldown with the Howling Idol's aura (DB2 1291059 -1000 ms, wowsims's test)",
        function()
            local e = ld.env(w)
            e.talent = rank(2)
            assert.are.equal(8, ld.run(w.abilities.shifting_power.cooldown, e))
            e.buff = auras({ howling_idol = { up = true } })
            assert.are.equal(7, ld.run(w.abilities.shifting_power.cooldown, e))
        end
    )

    it("ends Primal Bite's cooldown on Berserk and gives it none under Berserk (DB2 417141)", function()
        local e = ld.env(w)
        assert.are.equal(6, ld.run(w.abilities.primal_bite.cooldown, e)) -- no Berserk: the 6 s stands
        ld.run(w.abilities.berserk.handler, e)
        ld.run(w.abilities.berserk.now, e)
        assert.are.same({ { "primal_bite", 0 }, { "primal_bite", 0 } }, e.cooldowns) -- the sim's and the belief's
        e.buff = auras({ berserk = { up = true } })
        assert.are.equal(0, ld.run(w.abilities.primal_bite.cooldown, e))
    end)

    it("puts Barkskin and Frenzied Regeneration under the defensives toggle", function()
        assert.are.same(
            { "defensives", "defensives" },
            { w.abilities.barkskin.toggle, w.abilities.frenzied_regeneration.toggle }
        )
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
                    assert.are.same({ gate, nil }, { gate:match("_form$") and a[k].form or a[k].buff, a[k].nobuff }, k)
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
                "natures_grasp",
            }) do
                assert.are.same({ nil, "feral_form" }, { a[k].form, a[k].nobuff }, k)
            end
            assert.are.same({ nil, nil }, { a.innervate.form, a.innervate.nobuff }) -- leaves the form (below)
            for _, k in ipairs({ "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form" }) do
                assert.are.same({ nil, k }, { a[k].form, a[k].nobuff }, k)
            end
            for _, k in ipairs({ "faerie_fire", "barkskin" }) do
                assert.are.same({ nil, nil }, { a[k].form, a[k].nobuff }, k)
            end
            local e = ld.env(w)
            assert.are.same(
                { "cat_form", 55, 0 },
                { ld.run(a.berserk.form, e), ld.run(a.faerie_fire.spend, e), ld.run(a.faerie_fire.cooldown, e) }
            )
            e.buff = auras({ bear_form = { up = true }, feral_form = { up = true } })
            assert.are.same(
                { "bear_form", 0, 6 },
                { ld.run(a.berserk.form, e), ld.run(a.faerie_fire.spend, e), ld.run(a.faerie_fire.cooldown, e) }
            )
        end
    )

    it("registers the DB2's 47 talent nodes and the three placeholders, and no rank aliases", function()
        local n, registered = 0, 0
        for key, t in pairs(TALENTS) do
            n = n + 1
            assert.are.same({ t[1], t[2] }, { w.talents[key][2], w.talents[key][3] }, key) -- the tree: below
        end
        for _ in pairs(w.talents) do
            registered = registered + 1
        end
        assert.are.same({ 50, 50 }, { n, registered })
    end)

    it("reads only registered talent keys, in the class file and every race file", function()
        local files = { "src/Hekili_Druid/Druid.lua" }
        local ls = assert(io.popen("ls src/Hekili_Shared/Races/*.lua"))
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
            for _, gate in pairs({ ld.run(a.form, e), ld.run(a.buff, e), a.nobuff, a.aura }) do
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

        it("adds the Wolfshead Helm's 5 energy and half Enrage's 10 rage under its aura (DB2 17768)", function()
            local e = ld.env(w)
            e.buff = auras({ wolfshead_helm = { up = true } })
            ld.run(w.abilities.shifting_power.now, e)
            ld.run(w.abilities.shifting_power.handler, e)
            ld.run(w.abilities.enrage.handler, e)
            assert.are.same({ { 45, "energy" }, { 45, "energy" }, { 15, "rage" } }, e.gained)
            assert.are.equal(17768, w.auras.wolfshead_helm.id)
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

        it('leaves any form but Moonkin on Innervate, as Classic\'s swap_form("") and wowsims/forever', function()
            for _, f in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                ld.run(w.abilities.innervate[f], e)
                assert.are.same({ "innervate" }, e.applied, f)
                local removed = table.concat(e.removed, " ")
                for _, form in ipairs({ "cat_form", "bear_form", "travel_form", "aquatic_form" }) do
                    assert.is_truthy(removed:find(form, 1, true), f .. " " .. form)
                end
                assert.is_falsy(removed:find("moonkin_form", 1, true), f) -- Moonkin Form stays up
            end
        end)

        it(
            "declares Primal Fury's rage as `onCrit` on the bear's strikes: 5 at 2/2, 2.5 at 1/2, in Bear Form",
            function()
                local bear = { maul = true, swipe_bear = true, lacerate = true, primal_bite = true }
                for key, a in pairs(w.abilities) do
                    assert.are.equal(bear[key] == true, type(a.onCrit) == "function", key)
                end
                for key in pairs(bear) do
                    local e = ld.env(w)
                    ld.run(w.abilities[key].onCrit, e) -- rank 0, no form
                    e.talent = rank(2)
                    ld.run(w.abilities[key].onCrit, e) -- no form
                    e.buff = auras({ bear_form = { up = true } })
                    ld.run(w.abilities[key].onCrit, e)
                    e.talent = rank(1)
                    ld.run(w.abilities[key].onCrit, e)
                    e.talent = rank(0)
                    ld.run(w.abilities[key].onCrit, e)
                    local got = {}
                    for _, g in ipairs(e.gained) do
                        if g[1] ~= 0 then
                            got[#got + 1] = g
                        end
                    end
                    assert.are.same({ { 5, "rage" }, { 2.5, "rage" } }, got, key)
                end
            end
        )

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
        "gains rage per white swing in Bear Form only, at the form's fixed 2.5 s x 4.5 (wowsims's two-hand factor), a crit "
            .. "2.5 s x 3.46 more and Primal Fury's 5; Enrage 2/s; decay 1.25",
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
            near(2.5 * 4.5, models.mainhand.value()) -- before a plain base read
            w.game.base = { 1.0, 0 } -- a Cat pull's base, stale after the shift (D4: the form's period, not the read)
            near(11.25, models.mainhand.value())
            near(8.65, models.mainhand.crit()) -- a white crit: one more base swing, without the two-hand factor
            local talent = w.state.talent
            w.state.talent = rank(2) -- Primal Fury ("Blood Frenzy", DB2 16958): 16959's 5 rage at 2/2
            near(13.65, models.mainhand.crit())
            w.state.talent = rank(1) -- 50% at 1/2 (wowsims's ladder): its expected 2.5
            near(11.15, models.mainhand.crit())
            w.state.talent = talent
            assert.are.same({ "enrage", 1, 2 }, { models.enrage.aura, models.enrage.interval, models.enrage.value })
            assert.is_nil(models.enrage.pausesDecay) -- unverified (checkpoint Q9)
            w.state.buff.enrage, w.state.query_time = { applied = 10 }, 13.4
            assert.are.equal(13, models.enrage.last())
            assert.are.equal(1.25, w.resources[1].meta.decay())
            assert.are.equal(1, w.resources[1].meta.decayInterval()) -- stepped, as the Warrior's
        end
    )

    it(
        "declares energy with no regen model, combo points with no maximum, mana's five-second rule, Classic's order",
        function()
            assert.are.same({ 3, 4, 1, 0 }, w.order)
            for _, pt in ipairs({ 4 }) do
                assert.are.same({ nil, nil }, { w.resources[pt].models, w.resources[pt].meta }, pt)
            end
            assert.are.same({ nil, { refundOnAvoid = 0.8 } }, { w.resources[3].models, w.resources[3].meta })
            -- wowsims/forever's logs: 2.2 mana a 0.1 s tick outside the rule, none inside it (Feral, Balance)
            assert.are.same({ spirit = 22, mp5 = 0 }, w.resources[0].meta.fsr)
            assert.is_nil(w.resources[1].meta.max)
        end
    )

    it("refunds 80% of an avoided ability's energy or rage where wowsims does, per ability", function()
        assert.are.same({ 0.8, 0.8 }, { w.resources[3].meta.refundOnAvoid, w.resources[1].meta.refundOnAvoid })
        local yes = {}
        for key, a in pairs(w.abilities) do
            if a.refundOnAvoid then
                yes[#yes + 1] = key
            end
        end
        table.sort(yes)
        assert.are.same({
            "bash",
            "claw",
            "cower",
            "lacerate",
            "maul",
            "pounce",
            "primal_bite",
            "rake",
            "ravage",
            "rip",
            "shred",
        }, yes)
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
        local src = assert(io.open("src/Hekili_Druid/Druid.lua")):read("*a")
        assert.is_nil(src:find("buff%.clearcasting")) -- the modifier, not each `spend`, prices it
    end)

    describe("the missable bleeds and the not-behind window", function()
        local function reset(t, debuffs)
            local e = ld.env(w)
            e.now, e.query_time = t, t
            e.debuff = auras(debuffs or {})
            ld.run(w.hooks.reset_precast, e)
            return e
        end

        it("declares its bleeds missable, which core drops on a miss (Engine/Schema/Spec.lua)", function()
            assert.are.same({ true, true, "pounce_bleed" }, {
                w.abilities.rake.missable,
                w.abilities.rip.missable,
                w.abilities.pounce.missable,
            })
            assert.is_nil(w.events.COMBAT_LOG_EVENT_UNFILTERED) -- no copy of its own
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

    it("refuses Shred in the not-behind window unless the behind setting says otherwise (Claw then)", function()
        local e = ld.env(w)
        local ok = function()
            return ld.run(w.abilities.shred.usable, e)
        end
        assert.is_true(ok())
        e.buff = auras({ not_behind = { up = true } })
        assert.is_false(ok())
        e.settings.behind = true
        assert.is_true(ok())
    end)

    it("registers the packs of APLs/packs.lua exactly as tools/make_pack.lua druid prints them", function()
        local printed = {}
        local pipe = assert(io.popen(LUA .. " tools/make_pack.lua druid"))
        for line in pipe:lines() do
            printed[#printed + 1] = { line:match("^(%d+) (.+)$") }
        end
        pipe:close()
        local manifest = dofile("src/Hekili_Druid/APLs/packs.lua")
        local names = manifest.packs
        assert.are.equal(#names, #w.packs)
        for i, name in ipairs(names) do
            assert.are.same({ name, tonumber(printed[i][1]), printed[i][2] }, w.packs[i])
        end
        assert.are.equal(w.class, manifest.class) -- the packs' class is the file's
    end)

    it("writes priorities that name only registered abilities, auras, talents, settings and lists", function()
        local packs = assert(loadfile("tools/make_pack.lua"))("lists", "druid")
        local secretToken = require("Game.State.helpers.load").module().VirtualState.AplSecretToken
        -- Hekili's `all`: Hekili_Shared/Shared/Items.lua's use_items; Hekili_Shared/Races' Night Elf racial
        local shared = { use_items = true, elunes_light = true }
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
    end)

    it("declares its class once (NewClass), no options, the setting Shred reads and Guardian's Roar upkeep", function()
        assert.are.equal("DRUID", w.class)
        local n = 0
        for _ in pairs(w.settings) do
            n = n + 1
        end
        local roar = w.settings.maintain_demoralizing_roar
        assert.are.same({ 2, false, false, true }, { n, w.settings.behind.default, roar.default, roar.option.sim })
        assert.is_nil(w.options)
    end)

    it("places each talent in its tree, the Forever-only placeholders at tree 0", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 3, 16, 16, 15 }, n)
    end)
end)

describe("Forever Druid's bleeds through the real engine's missable handling", function()
    local engine = require("Forever.helpers.engine")
    local env, spec, ME

    -- Each reset_precast hook of the Druid spec, run in a stand-in state at t with these debuffs; the keys removed.
    local function reset(t, debuffs)
        local removed = {}
        local e = setmetatable({
            now = t,
            query_time = t,
            debuff = setmetatable(debuffs, {
                __index = function()
                    return { up = false, applied = 0 }
                end,
            }),
            removeDebuff = function(unit, key)
                removed[#removed + 1] = unit .. ":" .. key
            end,
        }, { __index = env.state })
        for _, hook in ipairs(spec.hooks.reset_precast) do
            setfenv(hook, e)()
        end
        return table.concat(removed, ",")
    end

    local function row(t, sub, spellID)
        env.client.now = t
        for _, hook in ipairs(spec.hooks.COMBAT_LOG_EVENT_UNFILTERED) do
            hook(t, sub, false, ME, "", 0, 0, "Creature-1", "", 0, 0, spellID, "", 1, "DODGE")
        end
    end

    before_each(function()
        env = engine.load("DRUID")
        spec = env.class.kit
        ME = "Player-1"
        rawset(env.state, "GUID", ME)
    end)

    it("removes a missed Rake or Rip at the next reset, not a hit or a newer application", function()
        assert.are.same({}, env.loadErrors)
        row(10, "SPELL_MISSED", 1823) -- Rake rank 2, dodged
        assert.are.equal("target:rake", reset(11, { rake = { up = true, applied = 9.9 } }))
        assert.are.equal("", reset(13, { rake = { up = true, applied = 12 } })) -- reapplied since
        row(20, "SPELL_CAST_SUCCESS", 1079) -- a Rip that landed
        assert.are.equal("", reset(21, { rip = { up = true, applied = 20 } }))
        row(30, "SPELL_MISSED", 9827) -- Pounce: its bleed, not the stun
        assert.are.equal(
            "target:pounce_bleed",
            reset(31, { pounce_bleed = { up = true, applied = 29.9 }, pounce = { up = true, applied = 29.9 } })
        )
        row(40, "SPELL_MISSED", 1079)
        rawset(env.state, "GUID", "Player-2") -- another player's miss
        row(41, "SPELL_MISSED", 1822)
        assert.are.equal(
            "target:rip",
            reset(42, { rip = { up = true, applied = 39 }, rake = { up = true, applied = 39 } })
        )
    end)
end)

-- The wowsims.com packs as the specs' defaults (wowsims packs plan, P9): the hand-built lists retired (the focus tiers:
-- focus_roles_spec.lua).
describe("Forever Druid's wowsims.com defaults", function()
    it("makes each spec's wowsims.com pack its default and retires the hand-built lists", function()
        local w = ld.load()
        local package = {}
        for _, s in ipairs(w.def.specs) do
            package[s.key] = s.package
        end
        assert.are.same({
            balance = "Balance (wowsims.com)",
            feral = "Feral (wowsims.com)",
            guardian = "Guardian (wowsims.com)",
        }, { balance = package.balance, feral = package.feral, guardian = package.guardian })
        assert.are.same({ "Feral", "Guardian", "Balance" }, w.retired)
    end)
end)

-- The Druid's `now` handlers as VirtualState runs them: bound to Families/Now.lua's context (Hekili's verbs onto the
-- belief, nothing else reachable), on our own casts' success.
describe("Forever Druid in VirtualState's now context", function()
    local load = require("Game.State.helpers.load")
    local fake = require("Game.State.helpers.fake_api")
    local fs = require("Game.State.helpers.fake_spec")
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
        cast(768, 2) -- Cat Form: 684 mana (55% of the base mana at 60) of the fake's 100: none left
        assert.is_not_nil(VS.Aura("player", 768, 2.1))
        near(0, power(0, 2.1))
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
        near(11.25, power(1, 8))
        cast(5229, 9) -- Enrage: 10 now, 2 a second
        I.Settle(12)
        near(11.25 + 10 + 6, power(1, 12))
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

    it("gives Primal Fury's 5 rage at a bear strike's own crit with the talent at 2/2, none at 0/2 (GAP T)", function()
        I.Sources.Direct(VS.Obs.CombatStart, 1.5) -- in combat: no rage decay
        cast(5487, 2) -- Bear Form
        local function crit(t)
            cast(407995, t) -- Primal Bite
            local before = power(1, t + 0.05)
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 100, 1)
            ctl.Tick(t + 0.06)
            VS.Drain(t + 0.07)
            return power(1, t + 0.1) - before
        end
        assert.are.equal(0, crit(4))
        I.SetTalentRank(I.talents.bySpell[16958], 2)
        assert.are.equal(5, crit(6))
        assert.are.equal(0, I.nowErrors, tostring(I.nowError))
    end)

    it("opens each GCD at its kind's length across shifts, a hard cast's included (GCD kinds §1.6)", function()
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
