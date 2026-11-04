-- tests/Forever/windows_spec.lua (re-pin design §3a, decision 11; plan Task 8a): RegisterWindow's checks at load and
-- its plain record in Build(def) (Engine/Schema/Spec.lua, Tracked.lua). The belief's edges: tests/Game/State/windows_spec.lua.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local function boot()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    return H
end

describe("RegisterWindow", function()
    local H, kit
    before_each(function()
        H = boot()
        kit = H.Hekili.Class.kit
    end)

    -- two abilities the belief tracks (the build's first two: the class's, sorted; passives come after them)
    local function steps()
        local def = H.ns.VirtualStateInternal.def
        return { def.abilities[2].key, def.abilities[1].key }
    end

    it("hands a plain record to Build(def), steps as ability indexes", function()
        local keys = steps()
        local ev = function()
            return false
        end
        kit:RegisterWindow("test_window", { evaluator = ev, duration = 6, steps = keys, strict = true })
        H.Hekili:SpecializationChanged()
        local def = H.ns.VirtualStateInternal.def
        local rec
        for w = 1, #def.windows do
            if def.windows[w].key == "test_window" then
                rec = def.windows[w]
            end
        end
        assert.is_truthy(rec)
        assert.are.equal(6, rec.duration)
        assert.are.equal("stay", rec.on_deviation)
        assert.is_true(rec.strict)
        assert.is_false(rec.loop)
        for k, key in ipairs(keys) do
            assert.are.equal(key, def.abilities[rec.steps[k]].key)
        end
        assert.is_nil(getmetatable(rec))
    end)

    it("raises at load on a second name, a bad field or an unregistered step key", function()
        kit:RegisterWindow("twice", { duration = 6 })
        assert.has_error(function()
            kit:RegisterWindow("twice", { duration = 6 })
        end)
        assert.has_error(function()
            kit:RegisterWindow("no_duration", {})
        end)
        assert.has_error(function()
            kit:RegisterWindow("bad_eval", { duration = 6, evaluator = 1 })
        end)
        assert.has_error(function()
            kit:RegisterWindow("bad_dev", { duration = 6, steps = steps(), on_deviation = "wander" })
        end)
        assert.has_error(function()
            kit:RegisterWindow("bad_step", { duration = 6, steps = { "no_such_ability" } })
        end)
    end)
end)
