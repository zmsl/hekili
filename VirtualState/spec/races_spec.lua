-- VirtualState/spec/races_spec.lua (event-facade spec §12b): race packs. Races.lua's `Hekili:NewRace` and the Gnome's
-- pack (Forever/Races/Gnome.lua), loaded headless against a stand-in for Hekili: inert for another race, registered for
-- the Gnome; and the simulation's half of the cost modifier on abilities built as RegisterAbility builds them.

describe("race packs", function()
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

    local function load(token, seed)
        state = {
            race_token = token,
            buff = setmetatable({}, {
                __index = function()
                    return { up = false, count = 0 }
                end,
            }),
            removeStack = removeStack,
        }
        all = { abilities = seed or {}, auras = {} } -- `seed`: what Classes.lua's `all` already registered
        -- as Classes.lua's RegisterAbility/RegisterAura: the entry under its key, its id and every `copy` alias
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
        hekili = { State = state, Class = { specs = { [0] = all }, abilities = {} } }
        _G.Hekili = hekili
        ns = {}
        assert(loadfile("Races.lua"))("Hekili", ns)
        assert(loadfile("Forever/Races/Gnome.lua"))("Hekili", ns)
    end

    -- An ability as Classes.lua's RegisterAbility builds it: function fields in `funcs`, called on access, wrapped.
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

    it("is inert for another race: nothing registered, no modifier", function()
        load("Human")
        assert.are.same({}, all.abilities)
        assert.are.same({}, all.auras)
        assert.are.same({ maxMods = {}, costMods = {} }, ns.raceMods)
    end)

    it("registers Eureka!, its aura and both modifiers for a Gnome, into the shared spec (the race wins a clash)", function()
        local stock = { id = 1 }
        load("Gnome", { eureka = stock, [1] = stock }) -- a stock `all` registration under the same key
        assert.are.equal(1259813, all.abilities.eureka.id) -- the race file loads later and wins
        assert.are.equal(all.abilities.eureka, all.abilities[1259817]) -- a `copy` alias
        assert.are.equal(3, all.auras.eureka.max_stack)
        assert.is_function(all.abilities.eureka.now)
        assert.are.same({ { pct = 0.05 } }, ns.raceMods.maxMods)
        assert.are.same({ "eureka", -0.10, 3, 17 }, {
            ns.raceMods.costMods[1].aura,
            ns.raceMods.costMods[1].pct,
            ns.raceMods.costMods[1].charges,
            #ns.raceMods.costMods[1].spells,
        })
    end)

    it("writes the race's abilities and auras over the class's after Classes.lua's merge, aliases too", function()
        load("Gnome")
        local own = { id = 2 }
        local class = { abilities = { eureka = own, [1259812] = own, [1] = own }, auras = { eureka = { id = 2 } } }
        ns.applyRace(class)
        assert.are.same({ 1259813, 1259813 }, { class.abilities.eureka.id, class.auras.eureka.id })
        local race = class.abilities.eureka -- every key the race registered, its id and `copy` aliases, wins too
        assert.are.same({ race, race, race, own }, {
            class.abilities[1259813],
            class.abilities[1259812],
            class.abilities[1259823],
            class.abilities[1],
        })
        assert.are.equal(class.auras.eureka, class.auras[1259817])
        load("Human")
        class = { abilities = { eureka = { id = 2 } }, auras = {} }
        ns.applyRace(class)
        assert.are.equal(2, class.abilities.eureka.id) -- inert for another race
    end)

    it("covers every ability without `spells`, and spends a charge on a cast made free (pct = -1)", function()
        load("Gnome")
        ns.raceMods.costMods[1] = { aura = "eureka", pct = -1, charges = 1 }
        local rend = ability("rend", { id = 772, spend = 10, spendType = "rage" })
        state.buff.eureka = { up = true, count = 1 }
        assert.are.equal(0, rend.spend)
        ns.costMods.Spend(rend.baseSpend, "rend") -- ns.spendResources passes the declared cost
        assert.is_false(state.buff.eureka.up)
        assert.are.equal(10, rend.spend)
    end)

    it("applies pct to a fraction-of-maximum cost", function()
        load("Gnome")
        local strike = ability("heroic_strike", { id = 78, spend = 0.2, spendType = "rage" })
        state.buff.eureka = { up = true, count = 3 }
        assert.is_true(math.abs(strike.spend - 0.18) < 1e-9)
    end)

    it("prices Heroic Strike at 13.5 with Eureka! up in the simulation, three casts remove it; Rend stays 10", function()
        load("Gnome")
        local heroic_strike = ability("heroic_strike", { id = 78, copy = { 284, 285 }, spend = 15, spendType = "rage" })
        local rend = ability("rend", { id = 772, spend = 10, spendType = "rage" })
        local cleave = ability("cleave", { id = 99999, copy = { 845 }, spend = function() return 20, "rage" end })
        assert.are.equal(15, heroic_strike.spend)
        state.buff.eureka = { up = true, count = 3 }
        assert.are.same({ 13.5, 10, 18 }, { heroic_strike.spend, rend.spend, cleave.spend }) -- cleave by a copy rank
        assert.are.equal(15, heroic_strike.baseSpend) -- the belief reads the declared cost
        ns.costMods.Spend(rend.baseSpend, "rend") -- out of scope: no charge
        assert.are.equal(3, state.buff.eureka.count)
        for k = 1, 3 do
            ns.costMods.Spend(heroic_strike.baseSpend, "heroic_strike") -- ns.spendResources' call
            if k < 3 then
                assert.are.equal(3 - k, state.buff.eureka.count)
            end
        end
        assert.is_false(state.buff.eureka.up)
        assert.are.equal(15, heroic_strike.spend)
    end)

    it("ignores a listed spell the class does not register", function()
        load("Gnome")
        local shout = ability("battle_shout", { id = 6673, spend = 10 })
        state.buff.eureka = { up = true, count = 3 }
        assert.has_no.errors(function()
            ns.costMods.Spend(shout.baseSpend, "battle_shout")
            ns.costMods.Spend(5, "not_an_ability")
        end)
        assert.are.equal(10, shout.spend)
        assert.are.equal(3, state.buff.eureka.count)
    end)
end)
