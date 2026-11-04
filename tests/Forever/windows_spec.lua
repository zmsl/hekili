-- tests/Forever/windows_spec.lua (re-pin design §3a, decision 11; plan Task 8a): RegisterWindow's and RegisterReaction's
-- checks at load and their plain records in Build(def) (Engine/Schema/Spec.lua, Tracked.lua). The belief's edges: tests/Game/State/windows_spec.lua.
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
        assert.has_error(function() -- spec 0's windows merge beside the spec's
            H.Hekili.Class.specs[0]:RegisterWindow("twice", { duration = 6 })
        end)
    end)
end)

describe("RegisterReaction", function()
    local H, kit
    before_each(function()
        H = boot()
        kit = H.Hekili.Class.kit
    end)

    it("hands a plain record to Build(def), never an ability (no index, no options row)", function()
        local f = function()
            openWindow("w") -- luacheck: ignore 113 (the `now` context's verb)
        end
        kit:RegisterReaction("test_reaction", { who = "target", outcome = "dodge", now = f })
        H.Hekili:SpecializationChanged()
        local def = H.ns.VirtualStateInternal.def
        local rec
        for k = 1, #def.reactions do
            if def.reactions[k].key == "test_reaction" then
                rec = def.reactions[k]
            end
        end
        assert.is_truthy(rec)
        assert.are.same({ "target", "dodge" }, { rec.who, rec.outcome })
        assert.are.equal("function", type(rec.now))
        assert.is_nil(getmetatable(rec))
        for a = 1, #def.abilities do
            assert.are_not.equal("test_reaction", def.abilities[a].key)
        end
        assert.is_nil(H.Hekili.Class.abilities.test_reaction)
        assert.is_truthy(H.Hekili.Class.reactions.test_reaction)
    end)

    it("raises at load on a second name, a bad who or outcome, or a now that is no function", function()
        local f = function() end
        kit:RegisterReaction("twice", { who = "player", outcome = "parry", now = f })
        assert.has_error(function()
            kit:RegisterReaction("twice", { who = "player", outcome = "parry", now = f })
        end)
        assert.has_error(function()
            kit:RegisterReaction("bad_who", { who = "pet", outcome = "parry", now = f })
        end)
        assert.has_error(function()
            kit:RegisterReaction("bad_outcome", { who = "player", outcome = "glance", now = f })
        end)
        assert.has_error(function()
            kit:RegisterReaction("bad_now", { who = "player", outcome = "parry" })
        end)
        assert.has_error(function() -- spec 0's reactions merge beside the spec's
            H.Hekili.Class.specs[0]:RegisterReaction("twice", { who = "player", outcome = "parry", now = f })
        end)
    end)
end)
