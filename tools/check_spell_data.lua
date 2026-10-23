-- tools/check_spell_data.lua (unit-registry spec §5.5): prints every class pack's abilities that start combat or
-- declare `expects`, one tab-separated line each (class, key, ids, velocity, school, tick_time, startsCombat,
-- expects), for tools/check_spell_data.py; tick_time is the ticking aura's (resolved `cycle or aura or key`, as the
-- simulation does; `fn` for a function; empty when the ability does not tick). Loads each pack through the recording
-- loader the specs use.
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path
local loader = require("Forever.helpers.load_druid")
local warrior = require("Forever.helpers.load_warrior")

local CLASSES = { "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior" }
for _, class in ipairs(CLASSES) do
    local w = class == "Warrior" and warrior.load()
        or loader.load(nil, "src/Hekili_" .. class .. "/" .. class .. ".lua", class:upper())
    local keys = {}
    for key, d in pairs(w.abilities) do
        if type(key) == "string" and type(d) == "table" and (d.startsCombat or d.expects) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local d = w.abilities[key]
        local ids = { type(d.id) == "number" and d.id or nil }
        for _, c in ipairs(type(d.copy) == "table" and d.copy or { d.copy }) do
            if type(c) == "number" then
                ids[#ids + 1] = c
            end
        end
        local function s(v)
            return v == nil and "" or tostring(v)
        end
        local au = w.auras[d.cycle or d.aura or key]
        local tick = ""
        if type(au) == "table" and (d.expects == "ticks" or d.expects == "channel" or au.dot == "debuff") then
            tick = type(au.tick_time) == "function" and "fn" or s(au.tick_time)
        end
        print(table.concat({
            class,
            key,
            table.concat(ids, ","),
            s(d.velocity),
            s(d.school),
            tick,
            d.startsCombat and "1" or "0",
            s(d.expects),
        }, "\t"))
    end
end
