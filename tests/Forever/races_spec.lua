-- tests/Forever/races_spec.lua (event-facade spec §12b): the race packs. Every race file Hekili.toc lists
-- (Forever/Races/*.lua), loaded through Engine/Schema/Races.lua headless against a stand-in for Hekili: inert for another race,
-- registered for its own, over `all`'s stale entries, and its cost modifier's numbers in the simulation. Engine/Schema/Races.lua's
-- own rules, with a fake race, are tests/Virtual/State/races_spec.lua.

-- Every race file Hekili.toc lists, in its order, and the race token (UnitRace's second return) each answers to.
local TOKEN = { Undead = "Scourge" } -- a file named otherwise than its token
local RACES = {}
for line in io.lines("src/Hekili/Hekili.toc") do
    local file = line:match("^Forever\\Races\\(%w+)%.lua")
    if file then
        RACES[#RACES + 1] = { file = file, token = TOKEN[file] or file }
    end
end

-- Runs every race file, as Hekili.toc loads them.
local function loadRaces(rns)
    for _, r in ipairs(RACES) do
        assert(loadfile("src/Hekili/Forever/Races/" .. r.file .. ".lua"))("Hekili", rns)
    end
end

-- By race file: the ability keys it registers for its own token, and its resource and cost modifiers' counts (for a
-- Warrior).
local OWN = {
    Gnome = { { "escape_artist", "eureka" }, 1, 1 },
    NightElf = { { "elunes_light", "shadowmeld" }, 0, 0 },
    Tauren = { { "war_stomp" }, 0, 0 },
    Human = { { "perception", "will_to_survive" }, 0, 0 },
    Dwarf = { { "stoneform" }, 0, 0 },
    Orc = { { "blood_fury", "shatter_curse" }, 0, 0 },
    Troll = { { "berserking", "rapid_regeneration" }, 0, 0 },
    Undead = { { "cannibalize", "will_of_the_forsaken" }, 0, 0 },
}

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

    local function load(token, seed, class)
        state = {
            race_token = token,
            buff = setmetatable({}, {
                __index = function()
                    return { up = false, count = 0 }
                end,
            }),
            removeStack = removeStack,
        }
        all = { abilities = seed or {}, auras = {} } -- `seed`: what Engine/Schema/Spec.lua's `all` already registered
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
        -- Engine/Schema/Spec.lua sets class.file before any race file runs
        hekili = { State = state, Class = { specs = { [0] = all }, abilities = {}, file = class or "WARRIOR" } }
        _G.Hekili = hekili
        ns = {}
        assert(loadfile("src/Hekili/Engine/Schema/Races.lua"))("Hekili", ns)
        loadRaces(ns)
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

    it("is inert for another race: nothing registered, no modifier", function()
        load("BloodElf")
        assert.are.same({}, all.abilities)
        assert.are.same({}, all.auras)
        assert.are.same({ maxMods = {}, costMods = {} }, ns.raceMods)
    end)

    it(
        "registers Eureka!, its aura and both modifiers for a Gnome, into the shared spec (the race wins a clash)",
        function()
            local stock = { id = 1 }
            load("Gnome", { eureka = stock, [1] = stock }) -- a stock `all` registration under the same key
            assert.are.equal(1259813, all.abilities.eureka.id) -- the race file loads later and wins
            assert.are.equal(all.abilities.eureka, all.abilities[1259817]) -- a `copy` alias
            assert.are.equal(3, all.auras.eureka.max_stack)
            assert.is_function(all.abilities.eureka.now)
            assert.are.same({ { pct = 0.05 } }, ns.raceMods.maxMods)
            assert.are.same({ "eureka", -0.10, 3, 18 }, {
                ns.raceMods.costMods[1].aura,
                ns.raceMods.costMods[1].pct,
                ns.raceMods.costMods[1].charges,
                #ns.raceMods.costMods[1].spells,
            })
        end
    )

    it(
        "prices Heroic Strike at 13.5 with Eureka! up in the simulation, three casts remove it; Rend stays 10",
        function()
            load("Gnome")
            local heroic_strike =
                ability("heroic_strike", { id = 78, copy = { 284, 285 }, spend = 15, spendType = "rage" })
            local rend = ability("rend", { id = 772, spend = 10, spendType = "rage" })
            local cleave = ability("cleave", {
                id = 99999,
                copy = { 845 },
                spend = function()
                    return 20, "rage"
                end,
            })
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
        end
    )

    it("registers Elune's Light and its aura for a Night Elf, War Stomp for a Tauren, and neither elsewhere", function()
        load("NightElf")
        local light = all.abilities.elunes_light
        assert.are.same(
            { 1259799, 0, 180, "off", "cooldowns" },
            { light.id, light.cast, light.cooldown, light.gcd, light.toggle }
        )
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

    it(
        "lists Hekili.toc's race files after the class files, each registering only its own keys and modifiers",
        function()
            local n, lastClass, firstRace = 0, 0, math.huge
            for line in io.lines("src/Hekili/Hekili.toc") do
                n = n + 1
                if line:match("^Forever\\Classes\\") then
                    lastClass = n
                elseif line:match("^Forever\\Races\\") then
                    firstRace = math.min(firstRace, n)
                end
            end
            assert.is_true(lastClass < firstRace)
            local files, want = {}, {}
            for _, r in ipairs(RACES) do
                files[#files + 1] = r.file
                load(r.token)
                local keys = {}
                for k in pairs(all.abilities) do
                    if type(k) == "string" then
                        keys[#keys + 1] = k
                    end
                end
                table.sort(keys)
                local own = OWN[r.file] or {}
                local mods = hekili.RaceMods -- the table read in game (Engine/Schema/Races.lua)
                assert.are.same(own, { keys, #mods.maxMods, #mods.costMods }, r.file)
            end
            for file in pairs(OWN) do
                want[#want + 1] = file
            end
            table.sort(files)
            table.sort(want)
            assert.are.same(want, files) -- every race file is in Hekili.toc
        end
    )

    it(
        "scopes Eureka! by the loaded class: 18 Warrior, 10 Rogue, 16 Mage, 13 Warlock, 16 Priest, none for a Druid",
        function()
            for class, n in pairs({ WARRIOR = 18, ROGUE = 10, MAGE = 16, WARLOCK = 13, PRIEST = 16 }) do
                load("Gnome", nil, class)
                assert.are.same({ 1, n }, { #ns.raceMods.costMods, #ns.raceMods.costMods[1].spells }, class)
            end
            load("Gnome", nil, "MAGE")
            local blast = ability("arcane_blast", { id = 400574, spend = 0.15, spendType = "mana" })
            state.buff.eureka = { up = true, count = 3 }
            assert.is_true(math.abs(blast.spend - 0.135) < 1e-9) -- a percent cost (ManaCost 0 in SpellPower) is in scope
            load("Gnome", nil, "DRUID")
            assert.are.same({ 1, 0 }, { #ns.raceMods.maxMods, #ns.raceMods.costMods })
        end
    )

    it("registers Escape Artist on the GCD, and Shadowmeld 20580 over `all`'s stale 58984", function()
        load("Gnome")
        local ea = all.abilities.escape_artist
        assert.are.same({ 20589, 120, "spell", "defensives" }, { ea.id, ea.cooldown, ea.gcd, ea.toggle })
        assert.are.same({ 20589, 3 }, { all.auras.escape_artist.id, all.auras.escape_artist.duration })
        local stock = { id = 58984, cooldown = 120 }
        load("NightElf", { shadowmeld = stock, [58984] = stock })
        local meld = all.abilities.shadowmeld
        assert.are.same({ 20580, 10, "off" }, { meld.id, meld.cooldown, meld.gcd })
        assert.is_function(meld.usable) -- `all`'s boss-or-group and not-moving gate, kept
        assert.are.same({ 20580, 3600 }, { all.auras.shadowmeld.id, all.auras.shadowmeld.duration })
        local class = { abilities = { shadowmeld = stock }, auras = { shadowmeld = { id = 58984 } } }
        ns.applyRace(class)
        assert.are.same({ 20580, 20580 }, { class.abilities.shadowmeld.id, class.auras.shadowmeld.id })
    end)

    it(
        "registers Will to Survive 1259718 and Stoneform 20594 (180 s, on the GCD) over `all`'s stale entries",
        function()
            local wts, stone = { id = 59752, gcd = "off" }, { id = 20594, cooldown = 120, gcd = "off" }
            load("Human", { will_to_survive = wts, [59752] = wts })
            local w = all.abilities.will_to_survive
            assert.are.same({ 1259718, 180, "spell", "defensives" }, { w.id, w.cooldown, w.gcd, w.toggle })
            assert.is_nil(w.handler or w.now) -- a stun removal: nothing to model beyond its cooldown and GCD
            assert.are.same(
                { 20600, 180, "spell" },
                { all.abilities.perception.id, all.abilities.perception.cooldown, all.abilities.perception.gcd }
            )
            assert.are.same({ 20600, 20 }, { all.auras.perception.id, all.auras.perception.duration })
            load("Dwarf", { stoneform = stone, [20594] = stone })
            local s = all.abilities.stoneform
            assert.are.same({ 20594, 180, "spell", "defensives" }, { s.id, s.cooldown, s.gcd, s.toggle })
            assert.are.same({ 20594, 8 }, { all.auras.stoneform.id, all.auras.stoneform.duration }) -- not 65116
            local class = { abilities = { stoneform = stone }, auras = { stoneform = { id = 65116 } } }
            ns.applyRace(class)
            assert.are.same({ 180, 20594 }, { class.abilities.stoneform.cooldown, class.auras.stoneform.id })
        end
    )

    it("registers Blood Fury 20572 for every class and Berserking 20554 over `all`'s stale entries", function()
        local fury = { id = function() end, copy = { 33702, 20572, 33697 } }
        for _, class in ipairs({ "WARRIOR", "MAGE", "SHAMAN", "DRUID" }) do
            load("Orc", { blood_fury = fury, [33702] = fury, [20572] = fury, [33697] = fury }, class)
            local b = all.abilities.blood_fury
            assert.are.same({ 20572, 120, "off", "cooldowns" }, { b.id, b.cooldown, b.gcd, b.toggle }, class)
            assert.are.equal(b, all.abilities[20572])
        end
        assert.are.same({ 20572, 15 }, { all.auras.blood_fury.id, all.auras.blood_fury.duration })
        local sc = all.abilities.shatter_curse
        assert.are.same({ 1299026, 180, "spell", "defensives" }, { sc.id, sc.cooldown, sc.gcd, sc.toggle })
        assert.are.same({ 1299026, 8 }, { all.auras.shatter_curse.id, all.auras.shatter_curse.duration })
        local zerk = { id = 26297 }
        load("Troll", { berserking = zerk, [26297] = zerk })
        local z = all.abilities.berserking
        assert.are.same({ 20554, 180, "off", "cooldowns" }, { z.id, z.cooldown, z.gcd, z.toggle })
        assert.are.same({ 20554, 10 }, { all.auras.berserking.id, all.auras.berserking.duration })
        local rr = all.abilities.rapid_regeneration
        assert.are.same({ 1260270, 180, "off", "defensives" }, { rr.id, rr.cooldown, rr.gcd, rr.toggle })
        assert.are.same({ true, 6, true }, { rr.channeled, rr.cast, rr.fixedCast }) -- a 6 s self-channel (DB2)
        assert.are.same({ 1260270, 6 }, { all.auras.rapid_regeneration.id, all.auras.rapid_regeneration.duration })
        local class = { abilities = { berserking = zerk }, auras = { berserking = { id = 26297 } } }
        ns.applyRace(class)
        assert.are.same({ 20554, 20554 }, { class.abilities.berserking.id, class.auras.berserking.id })
    end)

    it("registers Will of the Forsaken and Cannibalize for the Scourge token, not for `Undead`", function()
        load("Undead")
        assert.is_nil(all.abilities.cannibalize)
        load("Scourge")
        local w, c = all.abilities.will_of_the_forsaken, all.abilities.cannibalize
        assert.are.same({ 7744, 120, "spell", "defensives" }, { w.id, w.cooldown, w.gcd, w.toggle })
        assert.is_nil(w.handler or w.now) -- nothing to model beyond its cooldown and GCD
        assert.are.same({ 20577, 120, "spell", "defensives" }, { c.id, c.cooldown, c.gcd, c.toggle })
        assert.are.same({ true, 10, true }, { c.channeled, c.cast, c.fixedCast }) -- 20578's 10 s self-channel (DB2)
        assert.are.same({ 20578, 10 }, { all.auras.cannibalize.id, all.auras.cannibalize.duration }) -- the heal's aura
    end)
end)

-- The race packs' `now` handlers as VirtualState runs them: bound to Families/Now.lua's context, on our own casts.
describe("race packs in VirtualState's now context", function()
    local vload = require("Virtual.State.helpers.load")
    local fake = require("Virtual.State.helpers.fake_api")
    local fs = require("Virtual.State.helpers.fake_spec")
    local alloc = require("Virtual.State.helpers.alloc")
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

    -- What the race files register into `all` for the player's race `token` (Engine/Schema/Races.lua against a stand-in Hekili).
    local function registrations(token)
        local all = { abilities = {}, auras = {} }
        function all:RegisterAbility(key, def)
            self.abilities[key] = def
        end
        function all:RegisterAura(key, def)
            self.auras[key] = def
        end
        _G.Hekili = { State = { race_token = token }, Class = { specs = { [0] = all }, file = "WARRIOR" } }
        local rns = {}
        assert(loadfile("src/Hekili/Engine/Schema/Races.lua"))("Hekili", rns)
        loadRaces(rns)
        return all
    end

    -- One cast of race ability `key` (its aura: the same key) in a fresh VirtualState: 0 errors, 1 run, the aura believed
    -- up; then 1000 more allocate nothing.
    local function cast(all, key)
        local a, aura = all.abilities[key], all.auras[key]
        local api, ctl = fake.new()
        ctl.now = 1
        _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue =
            api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
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
        h.Class.auras[key] =
            { key = key, id = aura.id, copy = aura.copy, duration = aura.duration, max_stack = aura.max_stack }
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
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", a.id)
        ctl.Tick(5.01)
        VS.Drain(5.02)
        assert.are.same({ 0, 1 }, { I.nowErrors, I.nowRuns }, key .. ": " .. tostring(I.nowError))
        assert.is_not_nil(VS.Aura("player", aura.id, 5.1) or VS.Aura("target", aura.id, 5.1), key)
        function h:ForceUpdate() end -- the fake records each call; Hekili's own only sets fields
        local t = 5
        assert.are.equal(
            0,
            alloc.bytes(function() -- the same cast again, each past the cooldown
                t = t + 200
                ctl.now = t
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", a.id)
                ctl.Tick(t + 0.01)
                VS.Drain(t + 0.02)
            end, 1000),
            key
        )
    end

    it(
        "gives every channelled racial a `start` and no `handler` (Hekili's simulation runs a channel's `start`)",
        function()
            for _, r in ipairs(RACES) do
                for key, a in pairs(registrations(r.token).abilities) do
                    if a.channeled then
                        assert.is_function(a.start, key)
                        assert.is_nil(a.handler, key)
                    end
                end
            end
        end
    )

    for _, r in ipairs(RACES) do
        it("runs every `now` the " .. r.token .. " registers in the context without an error", function()
            local all, n = registrations(r.token), 0
            for key, a in pairs(all.abilities) do
                if a.now then
                    assert.are_not.equal(a.handler, a.now, key) -- two closures: one shared would be refused
                    cast(all, key)
                    n = n + 1
                end
            end
            assert.is_true(n > 0)
        end)
    end
end)
