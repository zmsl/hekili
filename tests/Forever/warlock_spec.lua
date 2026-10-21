-- tests/Forever/warlock_spec.lua: the Forever Warlock class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb; the live talent tree, the talents' per-rank values, the shard reagents and the starting regen
-- from wowsims/forever's data and logs), loaded headless through the recording stand-in (helpers/load_druid.lua with
-- Warlock.lua): the specs, the kit, the talents, mana, the Soul Shards, the cast times and costs, the DoTs, Banes and
-- Curses, Life Tap, the channels, the demon; and the class through the real engine (headless.lua): every `now` in
-- VirtualState's context, a summon's demon in the belief. What Hekili does with the rest is verified in game
-- (docs/dev/layout.md).
local ld = require("Forever.helpers.load_druid")
local headless = require("Game.harness.headless")

local FILE = "src/Hekili_Warlock/Warlock.lua"

-- key = { spell IDs in rank order, the top rank's mana cost, cooldown, gcd }, from the DB2 (`wowdb spell <name>`): the
-- cooldown is the larger of RecoveryTime and CategoryRecoveryTime; a percent-of-base cost (PowerCostPct) as the
-- fraction the class file declares.
local KIT = {
    shadow_bolt = { { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 }, 380, 0, "spell" },
    immolate = { { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 }, 380, 0, "spell" },
    corruption = { { 172, 6222, 6223, 7648, 11671, 11672, 25311 }, 340, 0, "spell" },
    bane_of_agony = { { 980, 1014, 6217, 11711, 11712, 11713 }, 215, 0, "spell" },
    bane_of_doom = { { 603 }, 300, 60, "spell" },
    curse_of_the_elements = { { 440892, 1311676, 1311677, 1311680 }, 200, 0, "spell" },
    curse_of_recklessness = { { 704, 7658, 7659, 11717 }, 115, 0, "spell" },
    curse_of_weakness = { { 702, 1108, 6205, 7646, 11707, 11708 }, 175, 0, "spell" },
    siphon_life = { { 18265, 18879, 18880, 18881 }, 365, 0, "spell" },
    drain_life = { { 689, 699, 709, 7651, 11699, 11700 }, 300, 0, "spell" },
    drain_soul = { { 1120, 8288, 8289, 11675 }, 290, 0, "spell" },
    wrack = { { 1316697 }, 200, 0, "spell" },
    rain_of_fire = { { 5740, 6219, 11677, 11678 }, 1185, 0, "spell" },
    hellfire = { { 1949, 11683, 11684 }, 1300, 0, "spell" },
    death_coil = { { 6789, 17925, 17926 }, 600, 120, "spell" },
    conflagrate = { { 1293817, 1293818, 17962, 18930, 18931, 18932 }, 255, 10, "spell" },
    shadowburn = { { 17877, 18867, 18868, 18869, 18870, 18871 }, 365, 15, "spell" },
    searing_pain = { { 5676, 17919, 17920, 17921, 17922, 17923 }, 168, 0, "spell" },
    incinerate = { { 412758, 1293812, 1293813 }, 325, 0, "spell" },
    soul_fire = { { 6353, 17924 }, 335, 60, "spell" },
    life_tap = { { 1454, 1455, 1456, 11687, 11688, 11689 }, 0, 0, "spell" },
    amplify_curse = { { 18288 }, 0, 180, "off" },
    summon_imp = { { 688 }, 0.8, 0, "spell" },
    summon_voidwalker = { { 697 }, 1, 0, "spell" },
    summon_succubus = { { 712 }, 1, 0, "spell" },
    summon_incubus = { { 713 }, 1, 0, "spell" },
    summon_felhunter = { { 691 }, 1, 0, "spell" },
    -- no cost, cooldown or GCD row (DB2; wowsims: "no cast time, cost or cooldown")
    demonic_sacrifice = { { 18788 }, 0, 0, "off" },
}

local function idsOf(a)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
        out[#out + 1] = id
    end
    return out
end

-- `buff` with the keys in `up` up, each { up, stack }.
local function buffs(up)
    return setmetatable({}, {
        __index = function(_, k)
            local n = up[k]
            return { up = n ~= nil, stack = n or 0, remains = n and 10 or 0 }
        end,
    })
end

local function near(x)
    return math.floor(x * 10000 + 0.5) / 10000
end

describe("Forever Warlock", function()
    local w

    before_each(function()
        w = ld.load(nil, FILE, "WARLOCK")
    end)

    -- An env with the kit's state helpers: min, max, the talents in `ranks`, Spirit `spirit` (UnitStat's second).
    local function env(ranks, spirit)
        local e = ld.env(w)
        e.min, e.max, e.haste = math.min, math.max, 1
        for k, r in pairs(ranks or {}) do
            e.talent[k] = { rank = r, enabled = r > 0 }
        end
        function e.stat(name, arg)
            assert(name == "UnitStat" and arg == 5)
            return 0, spirit or 0
        end
        return e
    end

    it("declares Affliction, Demonology and Destruction on trees 1-3 with their wowsims.com packs", function()
        assert.are.equal("WARLOCK", w.class)
        local out = {}
        for _, s in ipairs(w.def.specs) do
            out[#out + 1] = { s.key, s.tree, s.role, s.ranged, s.unsupported or false, s.package or false }
        end
        assert.are.same({
            { "affliction", 1, "attack", true, false, "Affliction (wowsims.com)" },
            { "demonology", 2, "attack", true, false, "Demonology (wowsims.com)" },
            { "destruction", 3, "attack", true, false, "Destruction (wowsims.com)" },
        }, out)
    end)

    it("registers the kit with the DB2's ranks, top-rank costs, cooldowns and GCDs", function()
        local n = 0
        for key, a in pairs(w.abilities) do
            n = n + 1
            local want = assert(KIT[key], "unexpected ability " .. key)
            local ids = want[1]
            for _, id in ipairs(ids) do
                w.game.known[id] = false
            end
            w.game.known[ids[#ids]] = true
            local e = env()
            assert.are.same(ids, idsOf(a), key)
            assert.are.same(
                { want[2], want[3], want[4] },
                { ld.run(a.spend, e) or 0, ld.run(a.cooldown, e), a.gcd },
                key
            )
            assert.are.equal("function", type(a.known), key)
        end
        assert.are.equal(28, n)
        assert.are.equal("cooldowns", w.abilities.amplify_curse.toggle)
        for _, key in ipairs({
            "summon_imp",
            "summon_voidwalker",
            "summon_succubus",
            "summon_incubus",
            "summon_felhunter",
        }) do
            assert.is_true(w.abilities[key].spendBase, key) -- a fraction of base mana, the 1 too
        end
    end)

    it("places wowsims's live tree: 17 Affliction, 19 Demonology and 16 Destruction nodes", function()
        local n = { 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ 17, 19, 16 }, n)
        assert.are.same({ 1, 1316697, 1 }, w.talents.wrack)
        assert.are.same({ 2, 440870, 2 }, w.talents.decimation)
        assert.are.same({ 3, 1293817, 1 }, w.talents.conflagrate)
        assert.are.same({ 3, 17778, 3 }, w.talents.cataclysm)
    end)

    it("declares mana under the five-second rule, base 1373, from wowsims's logs", function()
        assert.are.same({ 0 }, w.order)
        local r = w.resources[0]
        assert.are.same({ spirit = 33.88, mp5 = 10.4 }, r.meta.fsr)
        assert.are.equal(1373, r.meta.base)
    end)

    it(
        "counts the Soul Shards in the bags; the shard spells refuse without one, Soul Fire not under Decimation",
        function()
            local e = env()
            assert.are.equal(0, ld.run(w.exprs.soul_shards, e))
            w.game.bags[6265] = 3
            assert.are.equal(3, ld.run(w.exprs.soul_shards, e))
            -- the bag count read in both layers: the belief's `now` context has no `soul_shards` (env() sets none)
            for _, key in ipairs({ "shadowburn", "soul_fire", "summon_voidwalker", "summon_felhunter" }) do
                e = env()
                w.game.bags[6265] = 0
                assert.are.same({ false, "no soul shard" }, { ld.run(w.abilities[key].usable, e) }, key)
                w.game.bags[6265] = 1
                assert.is_true((ld.run(w.abilities[key].usable, e)), key)
            end
            e = env()
            w.game.bags[6265], e.buff = 0, buffs({ decimation = 1 })
            assert.is_true((ld.run(w.abilities.soul_fire.usable, e)))
            assert.is_true((ld.run(w.abilities.summon_imp.usable, env())))
        end
    )

    it("times the casts: Bane, Improved Corruption, Shadow Trance, Decimation and Master Summoner", function()
        local A = w.abilities
        w.game.known[25307] = true
        local e = env()
        assert.are.same({ 3, 2, 2, 2.5, 1.5, 6, 10 }, {
            ld.run(A.shadow_bolt.cast, e),
            ld.run(A.immolate.cast, e),
            ld.run(A.corruption.cast, e),
            ld.run(A.incinerate.cast, e),
            ld.run(A.searing_pain.cast, e),
            ld.run(A.soul_fire.cast, e),
            ld.run(A.summon_succubus.cast, e),
        })
        -- wowsims's logs: 2.5 / 1.5 / 2.0 at Bane 5/5, Corruption 0.8 at 3/5, Soul Fire 2.4 at 5/5 and Decimation 2/2
        e = env({ bane = 5, improved_corruption = 3, decimation = 2, master_summoner = 2 })
        e.buff = buffs({ decimation = 1 })
        assert.are.same({ 2.5, 1.5, 0.8, 2, 2.4, 6 }, {
            near(ld.run(A.shadow_bolt.cast, e)),
            near(ld.run(A.immolate.cast, e)),
            near(ld.run(A.corruption.cast, e)),
            near(ld.run(A.incinerate.cast, e)),
            near(ld.run(A.soul_fire.cast, e)),
            ld.run(A.summon_imp.cast, e),
        })
        e = env({ improved_corruption = 5 })
        e.buff = buffs({ shadow_trance = 1 })
        assert.are.same({ 0, 0 }, { ld.run(A.shadow_bolt.cast, e), ld.run(A.corruption.cast, e) })
        e.haste = 0.8
        e.buff = buffs({})
        assert.are.equal(2.4, near(ld.run(A.shadow_bolt.cast, e)))
        -- Soul Fire's cooldown: -45% a rank of Decimation (60, 33, 6)
        local out = {}
        for r = 0, 2 do
            out[#out + 1] = near(ld.run(A.soul_fire.cooldown, env({ decimation = r })))
        end
        assert.are.same({ 60, 33, 6 }, out)
    end)

    it("prices the Destruction spells less Cataclysm and the summons less Master Summoner", function()
        for _, id in ipairs({ 25307, 1293813, 18932, 18871, 25309, 25311 }) do
            w.game.known[id] = true
        end
        local A = w.abilities
        local e = env({ cataclysm = 3 })
        -- wowsims's destro log: 342, 292.5, 229.5, 328.5, 342
        assert.are.same({ 342, 292.5, 229.5, 328.5, 342 }, {
            near(ld.run(A.shadow_bolt.spend, e)),
            near(ld.run(A.incinerate.spend, e)),
            near(ld.run(A.conflagrate.spend, e)),
            near(ld.run(A.shadowburn.spend, e)),
            near(ld.run(A.immolate.spend, e)),
        })
        assert.are.equal(340, ld.run(A.corruption.spend, e)) -- outside the mask
        e = env({ master_summoner = 2 })
        assert.are.same(
            { 0.48, 0.6 },
            { near(ld.run(A.summon_imp.spend, e)), near(ld.run(A.summon_succubus.spend, e)) }
        )
    end)

    it("keeps one Curse and one Bane on the target, Amplify Curse spent by Agony and Weakness", function()
        local A = w.abilities
        for _, case in ipairs({
            { "curse_of_the_elements", { "curse_of_recklessness", "curse_of_weakness" } },
            { "curse_of_recklessness", { "curse_of_the_elements", "curse_of_weakness" } },
            { "curse_of_weakness", { "curse_of_the_elements", "curse_of_recklessness", "amplify_curse" } },
            { "bane_of_agony", { "bane_of_doom", "amplify_curse" } },
            { "bane_of_doom", { "bane_of_agony" } },
            { "corruption", {} },
            { "immolate", {} },
            { "siphon_life", {} },
        }) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = env()
                ld.run(A[case[1]][field], e)
                assert.are.same({ { case[1] }, case[2] }, { e.applied, e.removed }, case[1] .. " " .. field)
            end
            assert.is_true(A[case[1]].missable, case[1])
        end
        local a = w.auras
        assert.are.same({ 440892, 300, 704, 120, 702, 120, 980, 24, 603, 60, 348, 15, 18265, 30 }, {
            a.curse_of_the_elements.id,
            a.curse_of_the_elements.duration,
            a.curse_of_recklessness.id,
            a.curse_of_recklessness.duration,
            a.curse_of_weakness.id,
            a.curse_of_weakness.duration,
            a.bane_of_agony.id,
            a.bane_of_agony.duration,
            a.bane_of_doom.id,
            a.bane_of_doom.duration,
            a.immolate.id,
            a.immolate.duration,
            a.siphon_life.id,
            a.siphon_life.duration,
        })
        -- Corruption's duration by its known rank: 12, 15, then 18
        local out = {}
        for _, id in ipairs({ 172, 6222, 25311 }) do
            w.game.known[172], w.game.known[6222], w.game.known[25311] = false, false, false
            w.game.known[id] = true
            out[#out + 1] = ld.run(a.corruption.duration, env())
        end
        assert.are.same({ 12, 15, 18 }, out)
        for _, field in ipairs({ "now", "handler" }) do
            local e = env()
            ld.run(A.amplify_curse[field], e)
            assert.are.same({ "amplify_curse" }, e.applied, field)
        end
    end)

    it(
        "spends Shadow Trance on Shadow Bolt; Conflagrate needs and consumes Immolate unless Shadow and Flame 5/5",
        function()
            local A = w.abilities
            for _, field in ipairs({ "now", "handler" }) do
                local e = env()
                e.buff = buffs({ shadow_trance = 1 })
                ld.run(A.shadow_bolt[field], e)
                assert.are.same({ "shadow_trance" }, e.removed, field)
                e = env()
                ld.run(A.shadow_bolt[field], e)
                assert.are.same({}, e.removed, field)
                e = env({ shadow_and_flame = 4 })
                ld.run(A.conflagrate[field], e)
                assert.are.same({ "immolate" }, e.removed, field)
                e = env({ shadow_and_flame = 5 })
                ld.run(A.conflagrate[field], e)
                assert.are.same({}, e.removed, field)
            end
            local e = env()
            assert.are.same({ false, "no immolate" }, { ld.run(A.conflagrate.usable, e) })
            e.debuff = buffs({ immolate = 1 })
            assert.is_true((ld.run(A.conflagrate.usable, e)))
        end
    )

    it("brands the target from Searing Pain, 2 charges a rank of Demonic Brand", function()
        local sp = w.abilities.searing_pain
        for _, field in ipairs({ "now", "handler" }) do
            local e = env()
            ld.run(sp[field], e)
            assert.are.same({}, e.applied, field)
            e = env({ demonic_brand = 3 })
            ld.run(sp[field], e)
            assert.are.same({ { "demonic_brand" }, 6 }, { e.applied, e.stacks.demonic_brand }, field)
        end
        assert.are.equal("demonic_brand", sp.missable)
        local a = w.auras.demonic_brand
        assert.are.same({ 1293696, 10, 6 }, { a.id, a.duration, a.max_stack })
    end)

    -- Improved Shadow Bolt (DB2 17793): a Shadow Bolt crit puts Shadow Vulnerability (17794, 12 s) on the target, as
    -- wowsims's logs show; the belief's own crit (Families/Now.lua `onCrit`) is the only way to see it.
    it("marks the target with Shadow Vulnerability on a Shadow Bolt crit, with Improved Shadow Bolt", function()
        local crit = w.abilities.shadow_bolt.onCrit
        for key, a in pairs(w.abilities) do
            assert.are.equal(key == "shadow_bolt", type(a.onCrit) == "function", key)
        end
        local e = env()
        ld.run(crit, e)
        assert.are.same({}, e.applied)
        e = env({ improved_shadow_bolt = 5 })
        ld.run(crit, e)
        assert.are.same({ "shadow_vulnerability" }, e.applied)
        local a = w.auras.shadow_vulnerability
        assert.are.same({ 17794, 12, 1 }, { a.id, a.duration, a.max_stack })
    end)

    it("taps its rank's points, the level gain and Spirit into mana, x Improved Life Tap", function()
        local lt = w.abilities.life_tap
        w.game.known[11689] = true
        for _, field in ipairs({ "now", "handler" }) do
            local e = env({ improved_life_tap = 2 }, 221)
            ld.run(lt[field], e)
            assert.are.same({ { 774, "mana" } }, e.gained, field) -- wowsims's logs: (424 + 221) x 1.2
        end
        w.game.known[11689], w.game.known[1454] = false, true
        local e = env(nil, 0)
        e.level = 10
        ld.run(lt.now, e)
        assert.are.same({ { 24, "mana" } }, e.gained) -- rank 1 at 10: 20 + 4 levels above 6
        e = env(nil, 0)
        e.level = 30
        ld.run(lt.now, e)
        assert.are.same({ { 30, "mana" } }, e.gained) -- the gain stops ten levels above
        assert.is_nil(lt.spend)
    end)

    it("channels Drain Life, Drain Soul, Wrack, Rain of Fire and Hellfire, unhasted; Wrack's debuff", function()
        local out = {}
        for _, key in ipairs({ "drain_life", "drain_soul", "wrack", "rain_of_fire", "hellfire" }) do
            local a = w.abilities[key]
            out[#out + 1] = { key, a.channeled, a.cast, a.tick_time }
            assert.is_nil(a.handler, key) -- a channel's handler never runs in Hekili's simulation
        end
        assert.are.same({
            { "drain_life", true, 5, 1 },
            { "drain_soul", true, 15, 3 },
            { "wrack", true, 6, 1 },
            { "rain_of_fire", true, 8, 2 },
            { "hellfire", true, 15, 1 },
        }, out)
        for _, field in ipairs({ "now", "start" }) do
            local e = env()
            ld.run(w.abilities.wrack[field], e)
            assert.are.same({ "wrack" }, e.applied, field)
        end
        assert.are.same({ 1316697, 6 }, { w.auras.wrack.id, w.auras.wrack.duration })
    end)

    it(
        "summons the demon, ending Demonic Sacrifice's effect (the sacrificed demon's only, with Demonic Pact)",
        function()
            assert.are.same({ 416, 1860, 1863, 185317, 417 }, {
                w.pets.imp.id,
                w.pets.voidwalker.id,
                w.pets.succubus.id,
                w.pets.incubus.id,
                w.pets.felhunter.id,
            })
            for key in pairs(w.pets) do
                assert.are.same({ "summon_" .. key, 3600 }, { w.pets[key].spell, w.pets[key].duration }, key)
            end
            local function run(field, ranks, out)
                local e = env(ranks)
                if out then -- the simulation's `pet`: demon `out` up
                    e.pet = setmetatable({}, {
                        __index = function(_, k)
                            return { up = k == out }
                        end,
                    })
                end
                e.summoned = {}
                function e.summonPet(key)
                    table.insert(e.summoned, key)
                end
                function e.dismissPet(key)
                    table.insert(e.summoned, "-" .. key)
                end
                ld.run(w.abilities.summon_imp[field], e)
                return e
            end
            for _, field in ipairs({ "now", "handler" }) do
                local e = run(field)
                assert.are.same(
                    { { "imp" }, { "burning_shadow", "fel_stamina", "touch_of_fire", "fel_energy" } },
                    { e.summoned, e.removed },
                    field
                )
                e = run(field, { demonic_pact = 1 })
                assert.are.same({ { "imp" }, { "burning_shadow" } }, { e.summoned, e.removed }, field)
                -- the simulation dismisses only the demon out first (wowsims summon.go: the same demon included)
                assert.are.same({ "-succubus", "imp" }, run(field, nil, "succubus").summoned, field)
                assert.are.same({ "-imp", "imp" }, run(field, nil, "imp").summoned, field)
            end
            assert.are.same({ 18789, 18790, 18791, 18792 }, {
                w.auras.burning_shadow.id,
                w.auras.fel_stamina.id,
                w.auras.touch_of_fire.id,
                w.auras.fel_energy.id,
            })
            assert.are.same(
                { "burning_shadow", "fel_stamina", "touch_of_fire", "fel_energy" },
                w.auras.demonic_sacrifice.alias
            )
        end
    )

    -- wowsims talents_demonology.go applyDemonicSacrifice: the demon out dismissed, the previous effect ended, the
    -- sacrificed demon's effect up until a summon cancels it.
    it("sacrifices the demon out for its effect, ending any other; refused with no demon", function()
        local ds = w.abilities.demonic_sacrifice
        assert.are.same({ 18788, 0, "off" }, { ds.id, ld.run(ds.cast, env()), ds.gcd })
        assert.is_nil(ds.spend)
        -- the simulation's `pet`: the demons by key, the Succubus out
        local function sim(out)
            local e = env()
            e.pet = setmetatable({}, {
                __index = function(_, k)
                    return { up = k == out }
                end,
            })
            e.dismissed = {}
            function e.dismissPet(key)
                table.insert(e.dismissed, key)
            end
            return e
        end
        assert.are.same({ false, "no demon" }, { ld.run(ds.usable, sim(nil)) })
        assert.is_true((ld.run(ds.usable, sim("succubus"))))
        assert.is_true((ld.run(ds.usable, env()))) -- the belief's `now` context: no `pet`, the client's usable decides
        local e = sim("succubus")
        ld.run(ds.handler, e)
        assert.are.same({
            { "succubus" },
            { "burning_shadow", "fel_stamina", "touch_of_fire", "fel_energy" },
            { "touch_of_fire" },
        }, { e.dismissed, e.removed, e.applied })
        -- the belief: the pet unit down, the effects ended; the new one is the aura walk's (no demon key here)
        e = env()
        e.dismissed = {}
        function e.dismissPet(key)
            table.insert(e.dismissed, key)
        end
        ld.run(ds.now, e)
        assert.are.same(
            { { "demon" }, { "burning_shadow", "fel_stamina", "touch_of_fire", "fel_energy" }, {} },
            { e.dismissed, e.removed, e.applied }
        )
    end)

    it("refuses each spell while an interrupt has its school locked out", function()
        local SCHOOL = {
            shadow_bolt = "shadow",
            corruption = "shadow",
            bane_of_agony = "shadow",
            curse_of_the_elements = "shadow",
            wrack = "shadow",
            drain_soul = "shadow",
            death_coil = "shadow",
            life_tap = "shadow",
            immolate = "fire",
            incinerate = "fire",
            searing_pain = "fire",
            rain_of_fire = "fire",
            hellfire = "fire",
        }
        for key, school in pairs(SCHOOL) do
            local e = env()
            assert.is_true((ld.run(w.abilities[key].usable, e)), key)
            e["locked_out_" .. school] = true
            assert.is_false((ld.run(w.abilities[key].usable, e)), key)
        end
        for key, school in pairs({ shadowburn = "shadow", soul_fire = "fire", conflagrate = "fire" }) do
            local e = env()
            w.game.bags[6265], e.debuff = 1, buffs({ immolate = 1 })
            assert.is_true((ld.run(w.abilities[key].usable, e)), key)
            e["locked_out_" .. school] = true
            assert.is_false((ld.run(w.abilities[key].usable, e)), key)
        end
    end)
end)

-- Through the real engine (headless.lua): a Warlock who knows the whole kit.
describe("Forever Warlock through the engine", function()
    local function character()
        local w = ld.load(nil, FILE, "WARLOCK")
        local known = {}
        for _, a in pairs(w.abilities) do
            for _, id in ipairs(idsOf(a)) do
                known[#known + 1] = id
            end
        end
        return {
            class = "WARLOCK",
            classID = 9,
            specID = 1490,
            level = 60,
            known = known,
            talents = {},
            power = { type = 0, token = "MANA", max = 6000, value = 6000 },
            speed = { 2 },
        },
            w
    end

    it(
        "loads the kit on our spec ids and runs every declared `now` in VirtualState's context without an error",
        function()
            local H = headless.new({ character = character() })
            assert.are.same({}, H.loadErrors)
            local specs = H.Hekili.Class.specs
            assert.are.same(
                { "affliction", "demonology", "destruction" },
                { specs[100091].key, specs[100092].key, specs[100093].key }
            )
            local _, w = character()
            local I = H.ns.VirtualStateInternal
            local runs0, t, n = I.nowRuns, H.ctl.now, 0
            for _, a in pairs(w.abilities) do
                if a.now then
                    t, n = t + 1, n + 1
                    H.ctl.now = t
                    H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, a.id)
                    assert.is_true(headless.cycle(H, t + 0.1))
                    H.ns.VirtualState.Drain(t + 0.1) -- no priority yet: Hekili.Update idles before its drain
                end
            end
            assert.are.same({ 0, n }, { I.nowErrors, I.nowRuns - runs0 }, tostring(I.nowError))
            assert.are.same({}, H.errors)
        end
    )

    -- A `now` must pass a function-duration aura's duration (Families/Now.lua writes nothing without one): Corruption's
    -- rank-dependent 18 s lands in the belief at the cast, as the instant DoTs' do.
    it("lands each DoT, Bane and Curse cast's debuff in the belief, Corruption's at its rank's duration", function()
        local H = headless.new({ character = character() })
        local VS = H.ns.VirtualState
        local t = H.ctl.now + 1
        assert.is_true(headless.cycle(H, t))
        VS.Drain(t)
        local cases = {
            { "corruption", 25311, 172, 18 },
            { "immolate", 25309, 348, 15 },
            { "bane_of_agony", 11713, 980, 24 },
            { "siphon_life", 18881, 18265, 30 },
        }
        for i, c in ipairs(cases) do
            t = t + 1
            H.ctl.now = t
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. i, c[2])
            assert.is_true(headless.cycle(H, t + 0.1))
            VS.Drain(t + 0.1)
            local a = VS.Aura("target", c[3], t + 0.1)
            assert.is_truthy(a, c[1])
            assert.are.equal(t + c[4], a.est, c[1])
        end
        assert.are.same({}, H.errors)
    end)

    -- C1: a summon models the demon up until the pet unit's first observation (UNIT_PET), which overrides it.
    it("models the summoned demon up in the belief until the pet unit is observed", function()
        local H = headless.new({ character = character() })
        local VS = H.ns.VirtualState
        local t = H.ctl.now + 1
        assert.is_true(headless.cycle(H, t)) -- the pet poll's first read (no demon), as at login
        VS.Drain(t)
        assert.is_false((VS.Pet(t)))
        t = t + 1
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 712)
        assert.is_true(headless.cycle(H, t + 0.1))
        VS.Drain(t + 0.1)
        local up, _, model = VS.Pet(t + 0.1)
        assert.are.same({ true, true }, { up, model })
        H.ctl.exists.pet = true
        H.ctl.now = t + 0.5
        H.Fire("UNIT_PET", "player")
        assert.is_true(headless.cycle(H, t + 0.6))
        VS.Drain(t + 0.6)
        up, _, model = VS.Pet(t + 0.6)
        assert.are.same({ true, false }, { up, model })
        assert.are.same({}, H.errors)
    end)
end)

-- The priorities: the wowsims.com packs (generated from wowsims/forever's builds by `make wowsims-packs`).
describe("Forever Warlock priorities", function()
    it("keeps the class file's generated blocks in step with APLs/, each spec's package its pack", function()
        local mp = assert(loadfile("tools/make_pack.lua"))("lib")
        local f = assert(io.open(FILE))
        local src = f:read("*a")
        f:close()
        assert.are.equal(src, (mp.sync(src, mp.load("warlock"))))
        local names = {}
        for _, p in ipairs(ld.load(nil, FILE, "WARLOCK").packs) do
            names[#names + 1] = p[1]
        end
        assert.are.same({
            "Affliction (wowsims.com)",
            "Demonology (wowsims.com)",
            "Destruction (wowsims.com)",
            "SM Ruin (wowsims.com)",
            "Shadow Brand (wowsims.com)",
        }, names)
    end)

    -- rule 16: wowsims's Curses option as a choice, every build's (and the harness's) Elements
    it("registers the assigned curse as a choice for every spec, Elements in game and in the harness", function()
        local s = ld.load(nil, FILE, "WARLOCK").settings.assigned_curse
        local keys = {}
        for k in pairs(s.option.values) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        assert.are.same(
            { "elements", "select", "elements", { "elements", "nocurse", "recklessness", "weakness" } },
            { s.default, s.option.type, s.option.sim, keys }
        )
        assert.is_nil(s.specs)
    end)

    it("names only registered abilities and auras", function()
        local cls = ld.load(nil, FILE, "WARLOCK")
        local kinds = { buff = cls.auras, debuff = cls.auras, cooldown = cls.abilities, action = cls.abilities }
        -- Hekili's `all`: Hekili_Shared's use_items, the racials and Demonic Rune
        local shared = {
            use_items = true,
            call_action_list = true,
            blood_fury = true,
            berserking = true,
            eureka = true,
            demonic_rune = true,
        }
        for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", "warlock")) do
            for list, entries in pairs(p.lists) do
                for i, e in ipairs(entries) do
                    local where = p.name .. " " .. list .. " " .. i
                    assert.is_true(cls.abilities[e.action] ~= nil or shared[e.action], where)
                    for kind, key in (e.criteria or ""):gmatch("(%a+)%.([%w_]+)") do
                        if kinds[kind] then
                            assert.is_true(kinds[kind][key] ~= nil or shared[key], where .. ": " .. key)
                        end
                    end
                end
            end
        end
    end)
end)
