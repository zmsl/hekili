-- tools/check_cooldown_viewer.lua (providers spec §2.4, decision 81): a coverage report, never a failure. For each
-- class pack, the auras the Cooldown Manager tracks (answered by the fact) and the ones it does not (the modelled timer),
-- from tools/data/cooldownviewer/<CLASS>.lua. Loads packs as tools/check_spell_data.lua does.
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path
local loader = require("Forever.helpers.load_druid")
local warrior = require("Forever.helpers.load_warrior")

local CLASSES = { "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior" }
for _, class in ipairs(CLASSES) do
    local f = loadfile("tools/data/cooldownviewer/" .. class:upper() .. ".lua")
    local okF, fix = pcall(f or error)
    if not f then
        print(class .. "\tno fixture")
    elseif not okF or type(fix) ~= "table" then
        print(class .. "\tunreadable fixture")
    else
        local ids = {}
        for _, e in pairs(fix) do
            ids[e[2] or 0], ids[e[3] or 0] = true, true -- e[3] may be nil: no list built around it
            for _, sid in ipairs(e[4] or {}) do
                ids[sid] = true
            end
        end
        local w = class == "Warrior" and warrior.load()
            or loader.load(nil, "src/Hekili_" .. class .. "/" .. class .. ".lua", class:upper())
        local keys = {}
        for key, a in pairs(w.auras) do
            if type(key) == "string" and type(a) == "table" then -- the recording loaders merge auras by key, no `key` field
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)
        local n, hit = 0, 0
        for _, key in ipairs(keys) do
            local a = w.auras[key]
            local list = { a.id }
            for _, c in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
                list[#list + 1] = c
            end
            local tracked = false
            for _, sid in ipairs(list) do
                tracked = tracked or (type(sid) == "number" and ids[sid] == true)
            end
            n, hit = n + 1, hit + (tracked and 1 or 0)
            print(class .. "\t" .. key .. "\t" .. (tracked and "viewer" or "model"))
        end
        print(class .. "\tcoverage\t" .. hit .. "/" .. n)
    end
end
os.exit(0)
