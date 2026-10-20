-- tests/Forever/trees_spec.lua (per-spec plan, docs/superpowers/plans/2026-10-19-forever-specs.md): the pure rules of
-- src/Hekili/Engine/Schema/Trees.lua (ids, points per talent tree, the active-spec pick, share keys), and
-- Hekili:NewClass on the engine headless (tests/Forever/helpers/engine.lua).

local function trees()
    local ns = {}
    assert(loadfile("src/Hekili/Engine/Schema/Trees.lua"))("Hekili", ns)
    return ns
end

-- A kit as NewClass builds it, without the engine: { key, tree, unsupported } per spec.
local function kit(list, talents)
    local k = { token = "TEST", trees = {}, specs = {}, talents = talents }
    for i, d in ipairs(list) do
        local s = { id = 100050 + i, key = d[1], name = d[1], tree = d[2], unsupported = d[3], options = {} }
        k.trees[i], k.specs[d[1]] = s, s
    end
    return k
end
local TALENTS = { a = { 1, 101, 5 }, b = { 2, 201, 5 }, c = { 3, 301, 5 }, d = { 0, 401, 1 } }
local K = kit({ { "one", 1 }, { "two", 2 }, { "two_b", 2 }, { "heal", 3, true } }, TALENTS)
local function ranks(r)
    return function(t)
        return r[t[2]] or 0
    end
end

describe("Trees.lua", function()
    local T = trees()

    it("numbers a class's kit and specs 100000 + class id x 10 + slot", function()
        assert.are.equal(100010, T.TreeSpecID(1, 0))
        assert.are.equal(100042, T.TreeSpecID(4, 2))
        assert.are.equal(100114, T.TreeSpecID(11, 4))
    end)

    it("sums ranks per tree, tree 0 nowhere, into one reused table", function()
        local p = T.TreePoints(TALENTS, ranks({ [101] = 3, [201] = 5, [401] = 1 }))
        assert.are.same({ 3, 5, 0 }, p)
        assert.are.equal(p, T.TreePoints(TALENTS, ranks({})))
        assert.are.same({ 0, 0, 0 }, p)
    end)

    it("names a dominant tree only for a unique maximum above zero", function()
        assert.is_nil(T.DominantTree({ 0, 0, 0 }))
        assert.are.equal(2, T.DominantTree({ 3, 5, 0 }))
        assert.is_nil(T.DominantTree({ 5, 5, 0 }))
        assert.are.equal(3, T.DominantTree({ 0, 0, 1 }))
    end)

    describe("PickSpec", function()
        it("takes the spec chosen for the dominant tree, whatever tree that spec is on", function()
            local s, source, tree = T.PickSpec(K, { [1] = "two_b" }, ranks({ [101] = 31 }))
            assert.are.same({ "two_b", "stored", 1 }, { s.key, source, tree })
        end)
        it("takes the first spec of a dominant tree with no choice, a healing tree too", function()
            local s, source = T.PickSpec(K, { [1] = "two_b" }, ranks({ [201] = 5, [101] = 1 }))
            assert.are.same({ "two", "dominant" }, { s.key, source })
            assert.are.equal("heal", (T.PickSpec(K, nil, ranks({ [301] = 5 }))).key)
        end)
        it("ignores a chosen key the kit does not have", function()
            local s, source = T.PickSpec(K, { [2] = "gone" }, ranks({ [201] = 5 }))
            assert.are.same({ "two", "dominant" }, { s.key, source })
        end)
        it("keeps the last dominant tree's choice through a tie or no points", function()
            local s, source, tree = T.PickSpec(K, { [2] = "two_b", last = 2 }, ranks({ [101] = 2, [201] = 2 }))
            assert.are.same({ "two_b", "stored" }, { s.key, source })
            assert.is_nil(tree)
            assert.are.equal("two", (T.PickSpec(K, { last = 2 }, ranks({}))).key)
            assert.are.equal("two_b", (T.PickSpec(K, { [0] = "two_b" }, ranks({}))).key) -- chosen before any point
        end)
        it("reads a legacy scalar choice as stored until it is migrated", function()
            local s, source = T.PickSpec(K, "two_b", ranks({ [101] = 31 }))
            assert.are.same({ "two_b", "stored" }, { s.key, source })
        end)
        it("falls back to the first supported spec with no points (level < 10) or a tie and no tree seen", function()
            local s, source = T.PickSpec(K, nil, ranks({}))
            assert.are.same({ "one", "default" }, { s.key, source })
            s, source = T.PickSpec(K, {}, ranks({ [101] = 2, [201] = 2 }))
            assert.are.same({ "one", "default" }, { s.key, source })
            local H = kit({ { "heal", 1, true }, { "dps", 2 } }, TALENTS)
            assert.are.equal("dps", (T.PickSpec(H, nil, ranks({}))).key)
        end)
    end)

    it("has no talent hint any more (a talent swap switches the spec)", function()
        assert.is_nil(T.SpecHint)
    end)

    it("carries a spec as TOKEN:key in shares and reads it back", function()
        local two = K.trees[2]
        two.kit = K
        assert.are.equal("TEST:two", T.SpecShareKey(two))
        assert.is_nil(T.SpecShareKey(K))
        assert.is_nil(T.SpecShareKey(nil))
        local by = { ["TEST:two"] = 100052 }
        assert.are.equal(100052, T.SpecFromShare("TEST:two", by, 1491, K, two))
        assert.are.equal("OTHER:x", T.SpecFromShare("OTHER:x", by, 1491, K, two)) -- another class's: kept
        assert.are.equal(two.id, T.SpecFromShare(1491, by, 1491, K, two)) -- the legacy pseudo-spec: the active spec
        -- the active spec unsupported (a healing tree): the first supported spec, as MigrateTrees
        assert.are.equal(K.specs.one.id, T.SpecFromShare(1491, by, 1491, K, K.specs.heal))
        assert.are.equal(100052, T.SpecFromShare(100052, by, 1491, K, two))
        assert.is_nil(T.SpecFromShare(nil, by, 1491, K, two))
        local packs = { A = { spec = "TEST:two" }, B = { spec = "OTHER:x" }, C = { spec = 7 } }
        T.ResolvePackSpecs(packs, by)
        assert.are.same({ 100052, "OTHER:x", 7 }, { packs.A.spec, packs.B.spec, packs.C.spec })
    end)

    describe("MigrateTrees", function()
        local function fresh()
            local specs = {
                [1491] = {
                    enabled = true,
                    aoe = 3,
                    package = "Mine",
                    settings = { hs_threshold = 55, ww_min_enemies = 4 },
                    abilities = { rend = { disabled = true } },
                },
            }
            for _, s in ipairs(K.trees) do
                specs[s.id] = { settings = {} }
                s.options.package = s.unsupported and nil or (s.key:gsub("^%l", string.upper))
            end
            local packs = { Mine = { spec = 1491, builtIn = false }, One = { spec = 100051, builtIn = true } }
            return specs, packs, {}
        end

        it(
            "copies every legacy field to each supported spec, keeps the legacy table, and keeps a custom choice",
            function()
                local specs, packs, done = fresh()
                local active = K.specs.two
                assert.is_true(T.MigrateTrees(specs, packs, done, K, 1491, active))
                for _, key in ipairs({ "one", "two", "two_b" }) do
                    local s = specs[K.specs[key].id]
                    assert.are.same(
                        { 3, 55, 4, true },
                        { s.aoe, s.settings.hs_threshold, s.settings.ww_min_enemies, s.abilities.rend.disabled }
                    )
                end
                assert.are_not.equal(specs[1491].settings, specs[K.specs.one.id].settings) -- deep copies
                assert.is_nil(specs[K.specs.heal.id].aoe) -- a spec with no priorities keeps its defaults
                assert.are.same({ "One", "Mine", "Two_b" }, {
                    specs[K.specs.one.id].package,
                    specs[active.id].package, -- the user's custom pick stays on the active spec
                    specs[K.specs.two_b.id].package,
                })
                assert.are.equal(active.id, packs.Mine.spec)
                assert.are.equal(100051, packs.One.spec)
                assert.are.equal(55, specs[1491].settings.hs_threshold) -- kept for one release
                assert.is_true(done.TEST)
            end
        )

        it("runs once: a second pass changes nothing the user changed since", function()
            local specs, packs, done = fresh()
            T.MigrateTrees(specs, packs, done, K, 1491, K.specs.one)
            specs[K.specs.one.id].settings.hs_threshold = 60
            assert.is_false(T.MigrateTrees(specs, packs, done, K, 1491, K.specs.one))
            assert.are.equal(60, specs[K.specs.one.id].settings.hs_threshold)
        end)

        it("maps a built-in legacy choice 1:1 by spec and marks a class with no legacy profile as done", function()
            local specs, packs, done = fresh()
            specs[1491].package = "One"
            T.MigrateTrees(specs, packs, done, K, 1491, K.specs.two)
            assert.are.same({ "One", "Two" }, { specs[K.specs.one.id].package, specs[K.specs.two.id].package })
            local none = {}
            assert.is_true(T.MigrateTrees({}, {}, none, K, 1483, K.specs.one))
            assert.is_true(none.TEST)
        end)

        it("lands a custom choice on the first supported spec when the login picked an unsupported one", function()
            local specs, packs, done = fresh()
            T.MigrateTrees(specs, packs, done, K, 1491, K.specs.heal)
            assert.are.equal("Mine", specs[K.specs.one.id].package)
            assert.are.equal(K.specs.one.id, packs.Mine.spec)
            assert.is_nil(specs[K.specs.heal.id].package)
        end)

        it("merges value by value, so a spec's defaults the legacy table never saved stay", function()
            local specs, packs, done = fresh()
            local one = specs[K.specs.one.id]
            one.settings.sunder = true
            one.abilities = { strike = { clash = 0 } }
            local settings = one.settings
            T.MigrateTrees(specs, packs, done, K, 1491, K.specs.one)
            assert.are.equal(settings, one.settings)
            assert.are.same({ true, 55, 0, true }, {
                one.settings.sunder,
                one.settings.hs_threshold,
                one.abilities.strike.clash,
                one.abilities.rend.disabled,
            })
        end)
    end)
end)

describe("Hekili:NewClass (the engine headless)", function()
    local engine = require("Forever.helpers.engine")
    local DEF = {
        specs = {
            { key = "one", name = "One", tree = 1, icon = 11, role = "attack", package = "One" },
            { key = "two", name = "Two", tree = 2, icon = 12, role = "tank", package = "Two", ranged = true },
            { key = "heal", name = "Heal", tree = 3, icon = 13, role = "healer", unsupported = true },
        },
    }
    local function names(settings)
        local out = {}
        for i, s in ipairs(settings) do
            out[i] = s.name
        end
        return out
    end

    it("registers the kit at slot 0 and a spec per entry, each spec reading the kit's registrations", function()
        local env = engine.load("WARRIOR")
        local kit = env.Hekili:NewClass("WARRIOR", DEF)
        assert.are.equal(100010, kit.id)
        assert.are.equal(kit, env.class.kit)
        local one, two, heal = kit.specs.one, kit.specs.two, kit.specs.heal
        assert.are.same({ 100011, 100012, 100013 }, { one.id, two.id, heal.id })
        assert.are.same({ one, two, heal }, kit.trees)
        assert.are.equal(two, env.class.specs[100012])
        assert.are.equal(kit.abilities, two.abilities)
        assert.are.equal(kit.talents, heal.talents)
        assert.are_not.equal(kit.settings, two.settings)
        assert.are.same(
            { "Two", 12, "tank", 2, false },
            { two.options.package, two.texture, two.role, two.tree, two.melee }
        )
        assert.is_false(heal.options.enabled)
        assert.is_nil(one.options.enabled)
        assert.are.equal(100012, env.class.specByShare["WARRIOR:two"])
        assert.is_nil(env.Hekili:NewClass("DRUID", DEF)) -- not the player's class
    end)

    it("fans a kit setting out to the supported specs or the named ones, each with its own option table", function()
        local env = engine.load("WARRIOR")
        local kit = env.Hekili:NewClass("WARRIOR", DEF)
        local opt = { type = "range", name = "N", min = 0, max = 9 }
        kit:RegisterSetting("n_shared", 3, opt)
        kit:RegisterSetting("n_two", 4, { type = "toggle", name = "T" }, "two")
        local one, two, heal = kit.specs.one, kit.specs.two, kit.specs.heal
        assert.are.same({ "n_shared" }, names(one.settings))
        assert.are.same({ "n_shared", "n_two" }, names(two.settings))
        assert.are.same({}, names(heal.settings))
        assert.are_not.equal(one.settings[1].info, two.settings[1].info)
        assert.is_nil(opt.get) -- the caller's table is copied, not filled
        assert.has_error(function()
            kit:RegisterSetting("x", 1, {}, "nope")
        end)
    end)

    it("applies kit options to every spec but keeps each spec's package", function()
        local env = engine.load("WARRIOR")
        local kit = env.Hekili:NewClass("WARRIOR", DEF)
        kit:RegisterOptions({ potion = "p", package = "Other" })
        assert.are.same({ "p", "One" }, { kit.specs.one.options.potion, kit.specs.one.options.package })
        assert.is_nil(kit.specs.heal.options.package)
    end)
end)
