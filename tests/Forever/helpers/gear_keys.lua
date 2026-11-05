-- tests/Forever/helpers/gear_keys.lua (gear-aware spec §10.5): the gear keys are the same on both sides. The core's
-- `class.gear` and `class.setBonuses` keys, the build's `def.gear` keys and the belief's raw `I.setBonus` keys (minus
-- the derived `<key>_<n>pc`) are one set; no key is both a gear set and a set bonus (the core's bonus loop would
-- overwrite it); every bonus reads a tracked aura. Used by plain_records_spec (every class world) and
-- gear_parity_spec (a declared instance).
local assert = require("luassert")

return function(class, def, I)
    local core, bel, isGear = {}, {}, {}
    for k in pairs(class.gear or {}) do
        core[#core + 1], isGear[k] = k, true
    end
    for k in pairs(class.setBonuses or {}) do
        assert.is_nil(isGear[k], "a key both a gear set and a set bonus: " .. k)
        core[#core + 1] = k
    end
    local derived = {}
    for _, d in ipairs(def.gear) do
        bel[#bel + 1] = d.key
        for n = 1, #(d.items or {}) do
            derived[d.key .. "_" .. n .. "pc"] = true
        end
        if d.aura then -- a bonus reads its tracked aura (the core's virtual read and the belief's)
            local tracked = false
            for j = 1, #def.auraIds do
                for _, id in ipairs(def.auraIds[j]) do
                    tracked = tracked or id == d.aura
                end
            end
            assert.is_true(tracked, "set bonus " .. d.key .. "'s aura " .. d.aura .. " is not a tracked aura")
        end
    end
    table.sort(core)
    table.sort(bel)
    assert.are.same(core, bel)
    local raw, declared = {}, {}
    for _, k in ipairs(bel) do
        declared[k] = true
    end
    for k in pairs(I.setBonus) do
        if declared[k] or not derived[k] then
            raw[#raw + 1] = k
        end
    end
    table.sort(raw)
    assert.are.same(bel, raw) -- every declared key raw in the belief, and no other key but a derived one
end
