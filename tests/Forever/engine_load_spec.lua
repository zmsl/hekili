-- tests/Forever/engine_load_spec.lua
-- Every Forever content file loads through Hekili's REAL Engine/Spec.lua (tests/Forever/helpers/engine.lua), once per
-- class file and race file Hekili.toc lists (each class file registers only for its class, each race file only for
-- its race): no file's main chunk raises, every `item` resolves at registration under setfenv( f, state ), and every
-- function-valued ability field runs once under the stub state through the ability's own __index. shared_spec.lua's
-- stand-in `all` only stores defs; this is the spec that catches a function reading a name `state` lacks (a bare
-- `state` in Forever/Shared/Consumables.lua once aborted that file in game).
local engine = require("Forever.helpers.engine")

local CLASSES, RACES, RACE_LINES = {}, {}, 0
for line in io.lines("src/Hekili/Hekili.toc") do
    if line:match("^Forever\\Races\\") then
        RACE_LINES = RACE_LINES + 1
    end
    local kind, file = line:match("^Forever\\(%w+)\\(%w+)%.lua")
    if kind == "Classes" then
        CLASSES[#CLASSES + 1] = file:upper()
    elseif kind == "Races" then
        local f = assert(io.open("src/Hekili/Forever/Races/" .. file .. ".lua"))
        RACES[#RACES + 1] = assert(f:read("*a"):match('NewRace%("(%w+)"%)'), file)
        f:close()
    end
end

-- Abilities whose `item` is nil until the player chooses one (Consumables.lua: no Forever potion is registered).
local NO_ITEM_YET = { potion = true }

-- Every distinct ability of every spec the load registered, with its key.
local function abilities(env)
    local out, seen = {}, {}
    for _, spec in pairs(env.class.specs) do
        for _, a in pairs(spec.abilities) do
            if not seen[a] and rawget(a, "funcs") then
                seen[a] = true
                out[#out + 1] = a
            end
        end
    end
    return out
end

describe("Forever content through the real Engine/Spec.lua", function()
    it("answers Constants.lua's ns.ResourceIsPoints: point resources true, pooled ones false", function()
        local is = engine.load(CLASSES[1]).ns.ResourceIsPoints
        for _, k in ipairs({ "combo_points", "runes", "soul_shards", "holy_power", "chi", "arcane_charges", "essence" }) do
            assert.is_true(is(k), k)
        end
        for _, k in ipairs({ "rage", "energy", "mana", "focus", "runic_power" }) do
            assert.is_false(is(k), k)
        end
    end)

    it("lists the class and race files Hekili.toc loads", function()
        assert.is_true(#CLASSES >= 2)
        assert.are.equal(RACE_LINES, #RACES) -- every race line parsed, its NewRace token found
    end)

    for _, classToken in ipairs(CLASSES) do
        for _, race in ipairs(RACES) do
            describe(classToken .. " " .. race, function()
                local env = engine.load(classToken, race)

                it("loads every file without an error", function()
                    assert.are.same({}, env.loadErrors)
                    assert.are.same({}, env.errors)
                end)

                it("registers the class's specialization", function()
                    local n = 0
                    for id in pairs(env.class.specs) do
                        if id ~= 0 then
                            n = n + 1
                        end
                    end
                    assert.are.equal(1, n)
                end)

                it("resolves every ability's item at registration (the Healthstone: 5512, the bags empty)", function()
                    local hs = env.class.specs[0].abilities.healthstone
                    assert.are.equal("[Item 5512]", rawget(hs, "link"))
                    assert.are.equal(5512, hs.item)
                    for _, a in ipairs(abilities(env)) do
                        if (rawget(a.funcs, "item") or rawget(a, "item")) and not NO_ITEM_YET[a.key] then
                            assert(rawget(a, "link") == "[Item " .. tostring(a.item) .. "]", a.key)
                            assert.are.equal("number", type(a.item), a.key)
                        end
                    end
                end)

                it("runs every function-valued ability field under state", function()
                    local failed = {}
                    for _, a in ipairs(abilities(env)) do
                        local keys = {}
                        for k in pairs(a.funcs) do
                            keys[#keys + 1] = k
                        end
                        for k, v in pairs(a) do
                            if type(v) == "function" and k ~= "onLoad" then
                                keys[#keys + 1] = k
                            end
                        end
                        for _, k in ipairs(keys) do
                            local ok, err = pcall(function()
                                local v = a[k] -- funcs[k]() through Spec.lua's __index; a protected field is the function
                                if type(v) == "function" then
                                    v()
                                end
                            end)
                            if not ok then
                                failed[#failed + 1] = a.key .. "." .. k .. ": " .. tostring(err)
                            end
                        end
                    end
                    table.sort(failed)
                    assert.are.same({}, failed)
                end)

                it("runs every ability's meta functions under state", function()
                    local failed = {}
                    for _, a in ipairs(abilities(env)) do
                        for k, f in pairs(rawget(a, "meta") or {}) do -- Spec.lua's RegisterAbility setfenv's them
                            if type(f) == "function" then
                                local ok, err = pcall(f)
                                if not ok then
                                    failed[#failed + 1] = a.key .. ".meta." .. k .. ": " .. tostring(err)
                                end
                            end
                        end
                    end
                    table.sort(failed)
                    assert.are.same({}, failed)
                end)
            end)
        end
    end
end)

describe("the engine's threat table (tank design §2)", function()
    local env, threat

    before_each(function()
        env = engine.load("WARRIOR")
        threat = env.class.stateTables.threat
    end)

    it("reads the situation, whether the target attacks us or someone else, and the loose hostiles", function()
        local c = env.client
        assert.are.same({ 0, false, false }, { threat.situation, threat.on_me, threat.lost }) -- no target
        c.threat, c.exists.targettarget, c.isUnit.targettarget, c.canAttack = 3, true, true, true
        assert.are.same({ 3, true, false }, { threat.situation, threat.on_me, threat.lost })
        c.threat, c.isUnit.targettarget = 1, false
        assert.are.same({ 1, false, true }, { threat.situation, threat.on_me, threat.lost })
        assert.are.equal(0, threat.loose) -- VirtualState.LooseEnemies: no hostile seen
        assert.is_nil(threat.other)
    end)

    it("reads a secret answer as 0 or false, never as lost", function()
        local c = env.client
        c.threat, c.exists.targettarget, c.isUnit.targettarget, c.canAttack = c.SECRET, true, c.SECRET, true
        assert.are.same({ 0, false, false }, { threat.situation, threat.on_me, threat.lost })
        c.exists.targettarget, c.isUnit.targettarget = c.SECRET, false
        assert.is_false(threat.lost)
    end)

    it("never reads a friendly target, or a secret UnitCanAttack, as attacking us or lost", function()
        local c = env.client
        c.exists.targettarget, c.isUnit.targettarget, c.canAttack = true, false, false -- a friend's target is someone else
        assert.are.same({ false, false }, { threat.on_me, threat.lost })
        c.isUnit.targettarget = true
        assert.is_false(threat.on_me)
        c.canAttack, c.isUnit.targettarget = c.SECRET, false
        assert.are.same({ false, false }, { threat.on_me, threat.lost })
        c.canAttack = true
        assert.is_true(threat.lost)
    end)
end)

-- Hekili's own GCD in the simulation (GCD kinds design §1.4, core edit E10), from the whole addon headless
-- (tests/Virtual/harness/headless.lua) as a level 60 Druid in Cat Form, its power energy.
describe("the simulation's GCD by kind in energy (core edit E10)", function()
    local headless = require("Virtual.harness.headless")

    it("prices a spell-kind press at 1.5 x haste and a totem-kind one at 1.0; gcd.max stays the typical 1.0", function()
        local H = headless.new({
            character = {
                class = "DRUID",
                classID = 11,
                specID = 1499,
                level = 60,
                known = { 768, 5487, 5221 },
                power = { type = 3, token = "ENERGY", max = 100 },
            },
        })
        assert.are.same({}, H.loadErrors)
        local S = H.Hekili.State
        S.this_action = "bear_form"
        assert.are.equal(1.5 * S.haste, S.gcd.execute)
        S.this_action = "shred"
        assert.are.equal(1, S.gcd.execute)
        assert.are.equal(1, S.gcd.max) -- no ability context: the clause E10 keeps
    end)
end)
