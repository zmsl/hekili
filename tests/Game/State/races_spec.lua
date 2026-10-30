-- tests/Game/State/races_spec.lua (event-facade spec §12b): Engine/Schema/Races.lua's rules with a fake race defined here,
-- headless against a stand-in for Hekili: `Hekili:NewRace` registers another race's abilities unknown and registers into the shared
-- `all` for its own (over `all`'s entry), ns.applyRace writes the race's keys over the class's, and the simulation's half
-- of a cost modifier on abilities built as RegisterAbility builds them. The real race files: tests/Forever/races_spec.lua.

describe("Engine/Schema/Races.lua", function()
    local ns, hekili, state, all, saved

    -- Hekili's state.removeStack (State.lua:857-868), on the fake buff table.
    local function removeStack(aura, stacks)
        stacks = stacks or 1
        local b = state.buff[aura]
        if b.count > stacks then
            b.count = math.max(1, b.count - stacks)
        else
            state.buff[aura] = nil
        end
    end

    -- Loads Engine/Schema/Races.lua for a player of race `token` with `all` already holding `seed`, then runs the fake race
    -- "Fake": ability and aura `racial_a` (1001, `copy` 1002), +5% maximum resources, and `mod` (default: -10% on
    -- spell 1011 while racial_a is up, 3 charges) as its cost modifier.
    local function load(token, seed, mod)
        state = {
            race_token = token,
            buff = setmetatable({}, {
                __index = function()
                    return { up = false, count = 0 }
                end,
            }),
            removeStack = removeStack,
        }
        all = { abilities = seed or {}, auras = {} }
        -- as Engine/Schema/Spec.lua's RegisterAbility/RegisterAura: the entry under its key, its id and every `copy` alias
        local function register(t, key, def)
            t[key] = def
            if def.id then
                t[def.id] = def
            end
            for _, c in ipairs(type(def.copy) == "table" and def.copy or { def.copy }) do
                t[c] = def
            end
        end
        function all:RegisterAbility(key, def)
            register(self.abilities, key, def)
        end
        function all:RegisterAura(key, def)
            register(self.auras, key, def)
        end
        hekili = { State = state, Class = { specs = { [0] = all }, abilities = {}, file = "CLASS_A" } }
        _G.Hekili = hekili
        ns = {}
        assert(loadfile("src/Hekili/Engine/Schema/Races.lua"))("Hekili", ns)
        local race = hekili:NewRace("Fake")
        race:RegisterAbility("racial_a", { id = 1001, copy = { 1002 }, cooldown = 120 })
        race:RegisterAura("racial_a", { id = 1001, copy = { 1002 }, duration = 15, max_stack = 3 })
        race:RegisterResourceMod({ max = 0.05 })
        race:RegisterCostMod(mod or { aura = "racial_a", pct = -0.10, charges = 3, spells = { 1011 } })
        race:RegisterRegenMod({ resource = "pool_a", aura = "racial_a", mult = 2 })
    end

    -- An ability as Engine/Schema/Spec.lua's RegisterAbility builds it: function fields in `funcs`, called on access, wrapped.
    local function ability(key, data)
        local a = setmetatable({ funcs = {} }, {
            __index = function(t, k)
                if t.funcs[k] then
                    return t.funcs[k]()
                end
            end,
        })
        a.key = key
        for k, v in pairs(data) do
            if type(v) == "function" then
                a.funcs[k] = v
            else
                a[k] = v
            end
        end
        ns.costMods.Wrap(a)
        hekili.Class.abilities[key] = a
        return a
    end

    before_each(function()
        saved = rawget(_G, "Hekili") or false
    end)

    after_each(function()
        _G.Hekili = saved or nil
    end)

    it("goes live by race ID (UnitRace's third return) whatever the token, and only for that ID", function()
        load("Other")
        state.race_id = 95
        local race = hekili:NewRace("Unconfirmed", 95)
        race:RegisterRegenMod({ resource = "pool_a", aura = "racial_a", mult = 2 })
        race:RegisterRegenMod({ aura = "racial_a", mult = 2 }) -- no resource key: dropped
        assert.is_true(race.live)
        assert.are.same({ { resource = "pool_a", aura = "racial_a", mult = 2 } }, ns.raceMods.regenMods)
        assert.is_false(hekili:NewRace("Unconfirmed", 96).live) -- another race's ID
        assert.is_false(hekili:NewRace("Unconfirmed").live) -- no ID, another token
    end)

    it("registers another race's ability unknown and unlisted, its aura, no modifier", function()
        load("Other")
        local a = all.abilities.racial_a
        assert.are.same({ false, true, a, a }, { a.known, a.unlisted, all.abilities[1001], all.abilities[1002] })
        assert.are.equal(15, all.auras.racial_a.duration)
        local class = { abilities = {}, auras = {} }
        ns.applyRace(class) -- nothing owned: the class keeps its own
        assert.are.same({ abilities = {}, auras = {} }, class)
        assert.are.same({ maxMods = {}, costMods = {}, regenMods = {} }, ns.raceMods)
        assert.are.equal(ns.raceMods, hekili.RaceMods) -- the table read in game
    end)

    it(
        "registers its abilities, auras and modifiers into the shared spec for its race (the race wins a clash)",
        function()
            local stock = { id = 1 }
            load("Fake", { racial_a = stock, [1] = stock })
            assert.are.equal(1001, all.abilities.racial_a.id)
            assert.are.equal(all.abilities.racial_a, all.abilities[1002]) -- a `copy` alias
            assert.are.equal(3, all.auras.racial_a.max_stack)
            assert.are.same({ { pct = 0.05 } }, ns.raceMods.maxMods)
            assert.are.same({ { resource = "pool_a", aura = "racial_a", mult = 2 } }, ns.raceMods.regenMods)
            assert.are.same({ "racial_a", -0.10, 3, 1 }, {
                ns.raceMods.costMods[1].aura,
                ns.raceMods.costMods[1].pct,
                ns.raceMods.costMods[1].charges,
                #ns.raceMods.costMods[1].spells,
            })
        end
    )

    it(
        "writes the race's abilities and auras over the class's after Engine/Schema/Spec.lua's merge, aliases too",
        function()
            load("Fake")
            local own = { id = 2 }
            local class = { abilities = { racial_a = own, [1002] = own, [1] = own }, auras = { racial_a = { id = 2 } } }
            ns.applyRace(class)
            assert.are.same({ 1001, 1001 }, { class.abilities.racial_a.id, class.auras.racial_a.id })
            local race = class.abilities.racial_a -- every key the race registered, its id and `copy` aliases, wins too
            assert.are.same({ race, race, own }, { class.abilities[1001], class.abilities[1002], class.abilities[1] })
            assert.are.equal(class.auras.racial_a, class.auras[1002])
            load("Other")
            class = { abilities = { racial_a = { id = 2 } }, auras = {} }
            ns.applyRace(class)
            assert.are.equal(2, class.abilities.racial_a.id) -- inert for another race
        end
    )

    it("prices a listed spell (by id or a `copy` rank) through the modifier while its aura is up", function()
        load("Fake")
        local a = ability("spender_a", { id = 1011, spend = 15, spendType = "resource_a" })
        local b = ability("spender_b", { id = 1012, spend = 10, spendType = "resource_a" })
        local c = ability("spender_c", {
            id = 1013,
            copy = { 1011 },
            spend = function()
                return 20, "resource_a"
            end,
        })
        assert.are.equal(15, a.spend)
        state.buff.racial_a = { up = true, count = 3 }
        assert.are.same({ 13.5, 10, 18 }, { a.spend, b.spend, c.spend }) -- c by a copy rank
        assert.are.equal(15, a.baseSpend) -- the belief reads the declared cost
        ns.costMods.Spend(b.baseSpend, "spender_b") -- out of scope: no charge
        assert.are.equal(3, state.buff.racial_a.count)
        for k = 1, 3 do
            ns.costMods.Spend(a.baseSpend, "spender_a") -- ns.spendResources' call
            if k < 3 then
                assert.are.equal(3 - k, state.buff.racial_a.count)
            end
        end
        assert.is_false(state.buff.racial_a.up)
        assert.are.equal(15, a.spend)
    end)

    it("applies pct to a fraction-of-maximum cost", function()
        load("Fake")
        local a = ability("spender_a", { id = 1011, spend = 0.2, spendType = "resource_a" })
        state.buff.racial_a = { up = true, count = 3 }
        assert.is_true(math.abs(a.spend - 0.18) < 1e-9)
    end)

    it("covers every ability without `spells`, and spends a charge on a cast made free (pct = -1)", function()
        load("Fake", nil, { aura = "racial_a", pct = -1, charges = 1 })
        local a = ability("spender_b", { id = 1012, spend = 10, spendType = "resource_a" })
        state.buff.racial_a = { up = true, count = 1 }
        assert.are.equal(0, a.spend)
        ns.costMods.Spend(a.baseSpend, "spender_b") -- ns.spendResources passes the declared cost
        assert.is_false(state.buff.racial_a.up)
        assert.are.equal(10, a.spend)
    end)

    it("ignores a listed spell the class does not register, and a key it does not know", function()
        load("Fake")
        local a = ability("spender_b", { id = 1012, spend = 10 })
        state.buff.racial_a = { up = true, count = 3 }
        assert.has_no.errors(function()
            ns.costMods.Spend(a.baseSpend, "spender_b")
            ns.costMods.Spend(5, "not_an_ability")
        end)
        assert.are.equal(10, a.spend)
        assert.are.equal(3, state.buff.racial_a.count)
    end)

    it("takes a class file's spec:RegisterCostMod (Engine/Schema/Spec.lua) into the same list, for any race", function()
        load("Other")
        -- the mixin's entry as Engine/Schema/Spec.lua declares it, compiled with this `ns` as its upvalue
        local src = assert(io.open("src/Hekili/Engine/Schema/Spec.lua")):read("*a")
        local entry = assert(src:match("\n(    RegisterCostMod = function%( self, def %).-\n    end,)\n"))
        local mixin = assert(loadstring("local ns = ...\nreturn {\n" .. entry .. "\n}"))(ns)
        local def = { aura = "proc_a", pct = -1, charges = 1, spells = { 1021 } }
        mixin:RegisterCostMod(def)
        assert.are.equal(def, ns.raceMods.costMods[1]) -- the list Adapter.lua forwards to the belief
        local a = ability("spender_a", { id = 1021, copy = { 1022 }, spend = 60, spendType = "resource_b" })
        local b = ability("spender_b", { id = 1023, spend = 45, spendType = "resource_b" })
        state.buff.proc_a = { up = true, count = 1 }
        assert.are.same({ 0, 45 }, { a.spend, b.spend })
        ns.costMods.Spend(a.baseSpend, "spender_a")
        assert.is_false(state.buff.proc_a.up)
    end)
end)
