-- tests/Forever/spell_data_spec.lua: Hekili:ContinueOnSpellLoad (Engine/Sim/Events.lua) hears SPELL_DATA_LOAD_RESULT:
-- a waiting callback gets the load's own answer once, and the login pass answers only for spells already loaded.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

describe("waiting for spell data", function()
    local H
    local uncached = {}

    setup(function()
        local new = fake.new -- the facade binds C_Spell at load
        fake.new = function(...)
            local api, ctl = new(...)
            api.C_Spell.IsSpellDataCached = function(id)
                return not uncached[id]
            end
            return api, ctl
        end
        local ok, h = pcall(headless.new, { character = ww.character(), pack = ww.PACK })
        fake.new = new
        assert(ok, h)
        H = h
        assert.are.same({}, H.loadErrors)
    end)

    -- Asks for an uncached spell; the list fills with what the callback is given.
    local function wait(id)
        local got = {}
        uncached[id] = true
        H.Hekili:ContinueOnSpellLoad(id, function(success)
            got[#got + 1] = success
        end)
        assert.are.same({}, got)
        return got
    end

    it("a loaded spell answers true once", function()
        local got = wait(900001)
        uncached[900001] = nil
        H.Fire("SPELL_DATA_LOAD_RESULT", 900001, true)
        H.Fire("SPELL_DATA_LOAD_RESULT", 900001, true)
        assert.are.same({ true }, got)
    end)

    it("a failed load answers false", function()
        local got = wait(900002)
        H.Fire("SPELL_DATA_LOAD_RESULT", 900002, false)
        assert.are.same({ false }, got)
    end)

    it("another request is heard after the queue emptied", function()
        local first = wait(900003)
        H.Fire("SPELL_DATA_LOAD_RESULT", 900003, true)
        local second = wait(900004)
        H.Fire("SPELL_DATA_LOAD_RESULT", 900004, true)
        assert.are.same({ { true }, { true } }, { first, second })
    end)

    it("the login pass leaves a spell still loading to its event", function()
        local got = wait(900005)
        H.ns.StartEventHandler()
        assert.are.same({}, got)
        H.Fire("SPELL_DATA_LOAD_RESULT", 900005, true)
        assert.are.same({ true }, got)
    end)

    it("the login pass answers a spell loaded before it, once", function()
        local got = wait(900006)
        uncached[900006] = nil
        H.ns.StartEventHandler()
        H.Fire("SPELL_DATA_LOAD_RESULT", 900006, true)
        assert.are.same({ true }, got)
    end)
end)
