-- tests/Forever/wowsims_pin_spec.lua (wowsims packs plan, Task 2; check_wowsims_pin): every checked-in wowsims log
-- comes from the wowsims/forever commit tools/wowsims/export.lua pins, every recipe has its request and log, and the
-- exporter's pure parts (the talent string, the request) hold. Data: wowsims/forever (MIT).
local ex = assert(loadfile("tools/wowsims/export.lua"))()

local function exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
    end
    return f ~= nil
end

local function tmp(text)
    local path = os.tmpname()
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
    return path
end

describe("check_wowsims_pin", function()
    it("finds every recipe's log made at the pinned wowsims commit, beside its request", function()
        local pipe = assert(io.popen("ls tools/wowsims/specs"))
        for file in pipe:lines() do
            local spec = file:match("^(.+)%.lua$")
            if spec then
                assert.is_true(exists(ex.OUT .. spec .. ".json"), spec)
                local f = assert(io.open(ex.OUT .. spec .. ".log", "rb"), spec)
                local first = f:read("*l")
                f:close()
                assert.are.equal(ex.PIN, first:match("^# wowsims (%x+) "), spec)
                assert.are.equal(spec, first:match("^# wowsims %x+ (%S+) "), spec)
            end
        end
        pipe:close()
        assert.are.equal(40, #ex.PIN)
    end)

    it("decodes a talent string in its tree file's order: { spell, rank, tree }", function()
        local trees = {
            { talents = { { spellId = 11 }, { spellId = 12 } } },
            { talents = { { spellId = 21 } } },
            { talents = { { spellId = 31 }, { spellId = 32 } } },
        }
        assert.are.same({ { 11, 2, 1 }, { 21, 1, 2 }, { 32, 3, 3 } }, ex.talents("20-1-03", trees))
        assert.are.same({ { 12, 5, 1 } }, ex.talents("05", trees))
        assert.are.same({ { 31, 1, 3 } }, ex.talents("--1", trees))
    end)

    it("builds a seeded one-iteration debug request from a recipe's player, gear and APL", function()
        local gear = tmp('{"items":[{"id":1},{}]}')
        local apl = tmp('{"type":"TypeAPL","priorityList":[]}')
        local req = ex.request({
            name = "Tester",
            apl = apl,
            player = {
                race = "RaceOrc",
                class = "ClassWarrior",
                gear = gear,
                talentsString = "1-2-3",
                specKey = "dpsWarrior",
                options = { classOptions = { startingRage = 50 } },
                profession1 = "Engineering",
                profession2 = "Blacksmithing",
                reactionTimeMs = 100,
                distanceFromTarget = 25,
            },
        }, "")
        os.remove(gear)
        os.remove(apl)
        local p = req.raid.parties[1].players[1]
        assert.are.same({ "Tester", "RaceOrc", "1-2-3", 50, 1 }, {
            p.name,
            p.race,
            p.talentsString,
            p.dpsWarrior.options.classOptions.startingRage,
            p.equipment.items[1].id,
        })
        assert.are.equal("TypeAPL", p.rotation.type)
        assert.are.same({ 1, "101", true }, {
            req.simOptions.iterations,
            req.simOptions.randomSeed,
            req.simOptions.debug,
        })
        assert.are.same({ 180, 63 }, { req.encounter.duration, req.encounter.targets[1].level })
        assert.is_nil(req.raid.tanks) -- not a tank: no tank, no healing model
        assert.is_nil(p.healingModel)
    end)

    it("makes a tank recipe's player the raid's tank, healed by its healing model (the UI's tank defaults)", function()
        local gear = tmp('{"items":[]}')
        local model = { hps = 2200, cadenceSeconds = 0.4 }
        local req = ex.request({
            name = "Tank",
            tank = true,
            healingModel = model,
            player = { race = "RaceHuman", class = "ClassPaladin", gear = gear, specKey = "protectionPaladin" },
        }, "")
        os.remove(gear)
        assert.are.same({ { type = "Player", index = 0 } }, req.raid.tanks)
        assert.are.same(model, req.raid.parties[1].players[1].healingModel)
        local tanks = ex.recipe("paladin_protection")
        assert.are.same({ true, 2200 }, { tanks.tank, tanks.healingModel.hps })
    end)
end)
