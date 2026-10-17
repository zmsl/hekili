-- tests/Forever/registry_spec.lua (restructure plan, Task 5): Engine.Registry's views and the pack editor's
-- Engine.Evaluate, stock Hekili headless as Arms.
local headless = require("Virtual.harness.headless")
local ww = require("Forever.helpers.warrior_world")

-- The pack editor's inline sequence before Task 5 (Options.lua's criteria/value/value_else/strict_if `arg`), verbatim
-- but for its upvalues: the reference Engine.Evaluate must match.
local function inline(Hekili, pack, list, action, mod)
    local state, scripts = Hekili.State, Hekili.Scripts
    local results = {}
    state.reset("Primary", true)
    local apack = rawget(Hekili.DB.profile.packs, pack)
    for name, alist in pairs(apack.lists) do
        state.this_list = name
        for i, entry in ipairs(alist) do
            if name ~= list or i ~= action then
                if entry.action == "variable" and entry.var_name then
                    state:RegisterVariable(entry.var_name, pack .. ":" .. name .. ":" .. i, name)
                end
            end
        end
    end
    local entry = apack and apack.lists[list]
    entry = entry and entry[action]
    state.this_action = entry.action
    state.this_list = list
    local scriptID = pack .. ":" .. list .. ":" .. action
    state.scriptID = scriptID
    scripts:StoreValues(results, scriptID, mod)
    return results, list, action
end

describe("Engine.Registry (headless Arms)", function()
    local H

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert(headless.cycle(H, H.ctl.now + 0.2))
    end)

    it("views return the engine's live tables", function()
        local R, class = H.Hekili.Engine.Registry, H.Hekili.Class
        assert.are.equal(class.abilities, R.Abilities())
        assert.are.equal(class.specs, R.Specs())
        assert.are.equal(class.potionList, R.PotionList())
        assert.are.equal(class.file, R.ClassFile())
        assert.are.equal(class.specs[ww.SPEC].settings, R.Settings(ww.SPEC))
        assert.are.equal(H.ns.VirtualStateInternal.GCD_SPELL, R.GCD_SPELL)
        assert.are.equal(ww.SPEC, H.Hekili.Engine.Output.status.specID)
    end)

    it("Evaluate returns the inline sequence's results, list and action", function()
        local pack = rawget(H.Hekili.DB.profile.packs, ww.PACK)
        local list, action
        for name, alist in pairs(pack.lists) do
            for i, entry in ipairs(alist) do
                local node = H.Hekili.Scripts.DB[ww.PACK .. ":" .. name .. ":" .. i]
                if not list and entry.criteria and entry.criteria ~= "" and node and next(node.Elements) then
                    list, action = name, i
                end
            end
        end
        assert.is_string(list)
        for _, mod in ipairs({ false, "value", "value_else", "strict_if" }) do
            mod = mod or nil
            local want, wl, wa = inline(H.Hekili, ww.PACK, list, action, mod)
            local got, gl, ga = H.Hekili.Engine.Evaluate(ww.PACK, list, action, mod, {})
            assert.are.same(want, got)
            assert.are.equal(wl, gl)
            assert.are.equal(wa, ga)
            if not mod then
                assert.is_not_nil(next(got), "no condition values for " .. list .. ":" .. action)
            end
        end
        assert.are.same({}, H.errors)
        assert.are.same({}, headless.unexpected(H, "run"))
    end)
end)
