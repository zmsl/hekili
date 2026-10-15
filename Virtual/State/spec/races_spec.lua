-- Virtual/State/spec/races_spec.lua (event-facade spec §12b): race packs. Races.lua's `Hekili:NewRace` and the Gnome's
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
        for _, file in ipairs({ "Gnome", "NightElf", "Tauren" }) do -- every race file runs, as Hekili.toc loads them
            assert(loadfile("Forever/Races/" .. file .. ".lua"))("Hekili", ns)
        end
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

    it("registers Elune's Light and its aura for a Night Elf, War Stomp for a Tauren, and neither elsewhere", function()
        load("NightElf")
        local light = all.abilities.elunes_light
        assert.are.same({ 1259799, 0, 180, "off", "cooldowns" }, { light.id, light.cast, light.cooldown, light.gcd, light.toggle })
        assert.are.same({ 1259799, 15 }, { all.auras.elunes_light.id, all.auras.elunes_light.duration })
        assert.is_nil(all.abilities.war_stomp)
        assert.are.same({ maxMods = {}, costMods = {} }, ns.raceMods) -- no resource or cost modifier
        load("Tauren")
        local stomp = all.abilities.war_stomp
        assert.are.same({ 20549, 0.5, 120, "off" }, { stomp.id, stomp.cast, stomp.cooldown, stomp.gcd })
        assert.are.same({ 20549, 2 }, { all.auras.war_stomp.id, all.auras.war_stomp.duration })
        assert.is_nil(all.abilities.elunes_light)
        for _, a in ipairs({ light, stomp }) do
            assert.is_function(a.now)
            assert.are_not.equal(a.handler, a.now) -- two closures: one shared would be refused
        end
        load("Gnome")
        assert.is_not_nil(all.abilities.eureka)
        assert.is_nil(all.abilities.elunes_light or all.abilities.war_stomp)
    end)

    it("takes a class file's spec:RegisterCostMod (Classes.lua) into the same list, for any race", function()
        load("Human")
        -- the mixin's entry as Classes.lua declares it, compiled with this `ns` as its upvalue
        local src = assert(io.open("Classes.lua")):read("*a")
        local entry = assert(src:match("\n(    RegisterCostMod = function%( self, def %).-\n    end,)\n"))
        local mixin = assert(loadstring("local ns = ...\nreturn {\n" .. entry .. "\n}"))(ns)
        local def = { aura = "clearcasting", pct = -1, charges = 1, spells = { 5221 } }
        mixin:RegisterCostMod(def)
        assert.are.equal(def, ns.raceMods.costMods[1]) -- the list Adapter.lua forwards to the belief
        local shred = ability("shred", { id = 5221, copy = { 6800 }, spend = 60, spendType = "energy" })
        local claw = ability("claw", { id = 1082, spend = 45, spendType = "energy" })
        state.buff.clearcasting = { up = true, count = 1 }
        assert.are.same({ 0, 45 }, { shred.spend, claw.spend })
        ns.costMods.Spend(shred.baseSpend, "shred")
        assert.is_false(state.buff.clearcasting.up)
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

-- The race packs' `now` handlers as VirtualState runs them: bound to Families/Now.lua's context, on our own casts.
describe("race packs in VirtualState's now context", function()
    local vload = require("Virtual.State.spec.helpers.load")
    local fake = require("Virtual.State.spec.helpers.fake_api")
    local fs = require("Virtual.State.spec.helpers.fake_spec")
    local saved

    before_each(function()
        saved = {}
        for _, k in ipairs({ "Hekili", "GetTime", "UnitGUID", "CreateFrame", "issecretvalue", "debugprofilestop" }) do
            saved[k] = rawget(_G, k) or false
        end
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        fs.clock = nil
    end)

    -- What the race files register into `all` for the player's race `token` (Races.lua against a stand-in Hekili).
    local function registrations(token)
        local all = { abilities = {}, auras = {} }
        function all:RegisterAbility(key, def)
            self.abilities[key] = def
        end
        function all:RegisterAura(key, def)
            self.auras[key] = def
        end
        _G.Hekili = { State = { race_token = token }, Class = { specs = { [0] = all } } }
        local rns = {}
        assert(loadfile("Races.lua"))("Hekili", rns)
        for _, file in ipairs({ "Gnome", "NightElf", "Tauren" }) do
            assert(loadfile("Forever/Races/" .. file .. ".lua"))("Hekili", rns)
        end
        return all
    end

    for _, case in ipairs({
        { "Gnome", "eureka", 1259813, "player" },
        { "NightElf", "elunes_light", 1259799, "player" },
        { "Tauren", "war_stomp", 20549, "target" },
    }) do
        local token, key, id, unit = case[1], case[2], case[3], case[4]
        it("runs the " .. token .. "'s `now` (" .. key .. ") in the context without an error", function()
            local all = registrations(token)
            local a, aura = all.abilities[key], all.auras[key]
            local api, ctl = fake.new()
            ctl.now = 1
            _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue = api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
            _G.debugprofilestop = function()
                return 0
            end
            local ns = vload.module()
            local VS, I = ns.VirtualState, ns.VirtualStateInternal
            local h = fs.new(9)
            h.Class.abilities[key] = {
                key = key,
                id = a.id,
                copy = a.copy,
                cast = 0,
                cooldown = a.cooldown,
                gcd = a.gcd,
                charges = 1,
                recharge = 0,
                funcs = { now = a.now, handler = a.handler },
            }
            h.Class.auras[key] = { key = key, id = aura.id, copy = aura.copy, duration = aura.duration, max_stack = aura.max_stack }
            fs.clock = api.GetTime
            ns.spendResources = fs.spend
            ns.ResourceRegenerates = function()
                return false
            end
            vload.adapter(ns, h)
            VS.Start(api)
            VS.SpecChanged()
            ctl.Tick(1)
            ctl.now = 5
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
            ctl.Tick(5.01)
            VS.Drain(5.02)
            assert.are.same({ 0, 1 }, { I.nowErrors, I.nowRuns }, tostring(I.nowError))
            assert.is_not_nil(VS.Aura(unit, id, 5.1))
        end)
    end
end)
