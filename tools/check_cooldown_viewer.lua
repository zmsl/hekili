-- tools/check_cooldown_viewer.lua (providers spec §2.4, decision 81): a coverage report, never a failure. For each
-- class pack, the auras the Cooldown Manager tracks (answered by the fact) and the ones it does not (the modelled timer),
-- from tools/data/cooldownviewer/<CLASS>.lua. Only the aura categories (2 BuffIcon, 3 BuffBar) count as covered: the
-- Essential and Utility items are always shown (CV §2), so they carry no edges; every category's hits are printed.
-- Loads packs as tools/check_spell_data.lua does.
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
        local ids = {} -- [category][spellID] = true
        for c = 0, 8 do
            ids[c] = {}
        end
        for _, e in pairs(fix) do
            local set = ids[e[1]]
            set[e[2] or 0], set[e[3] or 0] = true, true -- e[3] may be nil: no list built around it
            for _, sid in ipairs(e[4] or {}) do
                set[sid] = true
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
        local n, hit, perCat = 0, 0, {}
        for c = 0, 8 do
            perCat[c] = 0
        end
        for _, key in ipairs(keys) do
            local a = w.auras[key]
            local list = { a.id }
            for _, c in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
                list[#list + 1] = c
            end
            local cats = {}
            for c = 0, 8 do
                local found = false
                for _, sid in ipairs(list) do
                    found = found or (type(sid) == "number" and ids[c][sid] == true)
                end
                if found then
                    perCat[c], cats[#cats + 1] = perCat[c] + 1, c
                end
            end
            local tracked = false
            for _, c in ipairs(cats) do
                tracked = tracked or c == 2 or c == 3
            end
            n, hit = n + 1, hit + (tracked and 1 or 0)
            print(class .. "\t" .. key .. "\t" .. (tracked and "viewer" or "model") .. "\t" .. table.concat(cats, ","))
        end
        for c = 0, 8 do
            if perCat[c] > 0 then
                print(class .. "\tcategory " .. c .. "\t" .. perCat[c] .. "/" .. n)
            end
        end
        print(class .. "\tcoverage\t" .. hit .. "/" .. n .. " (categories 2 and 3)")
    end
end
os.exit(0)
