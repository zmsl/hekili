-- tests/Forever/plain_records_spec.lua (border batch 4, the owner's design 2026-11-01): at every pack, the build's `def`
-- is plain records (no metatable anywhere in it, recursively: never a live Hekili table), and every function field the
-- belief evaluates (Families/Casts.lua I.Eval's callers) runs in the belief's `now` context without raising.
local loop = require("Game.harness.loop")

local WORLDS = {
    { "Forever.helpers.warrior_world" },
    { "Forever.helpers.rogue_world", "Combat" },
    { "Forever.helpers.mage_world", "Arcane" },
    { "Forever.helpers.hunter_world", "BeastMastery" },
    { "Forever.helpers.paladin_world", "Retribution" },
    { "Forever.helpers.priest_world", "Smite" },
    { "Forever.helpers.shaman_world", "Enhancement" },
    { "Forever.helpers.warlock_world", "Affliction" },
    { "Forever.helpers.druid_loop_world", "Feral" },
}
-- the function fields the belief evaluates, by record kind (Casts.lua, Resources.lua, Expect.lua)
local ABILITY = { "cooldown", "spend", "gcdTime", "usable" }
local AURA = { "duration", "tick_time", "base_tick_time" }
local RESOURCE = { "max", "decay", "decayInterval" }
local ENTRY = { "spirit", "mp5", "share", "value", "mult", "when" }

local function metatabled(v, path, seen, hits)
    if type(v) ~= "table" or seen[v] then
        return
    end
    seen[v] = true
    if getmetatable(v) ~= nil then
        hits[#hits + 1] = path
    end
    for k, x in pairs(v) do
        metatabled(x, path .. "." .. tostring(k), seen, hits)
    end
end

describe("the build's plain records at every pack #slow", function()
    for _, w in ipairs(WORLDS) do
        local name = w[1]:match("[^.]+$") .. (w[2] and (" " .. w[2]) or "")
        local I, def
        setup(function()
            local world = require(w[1])
            local L = loop.new(w[2] and world[w[2]] or world)
            I = L.us.ns.VirtualStateInternal
            def = I.def
        end)

        it(name .. ": nothing in def has a metatable", function()
            local hits = {}
            metatabled(def, "def", {}, hits)
            assert.are.same({}, hits)
            assert.is_true(#def.abilities > 0 and #def.auras > 0 and #def.resources > 0)
        end)

        it(name .. ": every function field runs in the belief's context", function()
            local errors0, t, raised = I.nowErrors, I.clock, {}
            local function try(rec, field, path)
                local f = rec and rec[field]
                if type(f) == "function" then
                    local _, ok = I.Eval(f, t)
                    if not ok then
                        raised[#raised + 1] = path .. "." .. field .. ": " .. tostring(I.nowError)
                    end
                end
            end
            for a = 1, #def.abilities do
                for _, field in ipairs(ABILITY) do
                    try(def.abilities[a], field, tostring(def.abilities[a].key))
                end
            end
            for j = 1, #def.auras do
                for _, field in ipairs(AURA) do
                    try(def.auras[j], field, "aura " .. tostring(def.auras[j].key))
                end
            end
            for r = 1, #def.resources do
                local d = def.resources[r]
                for _, field in ipairs(RESOURCE) do
                    try(d, field, d.key)
                end
                for _, list in ipairs({ "mult", "auraRegen", "maxMods" }) do
                    for k = 1, d[list] and #d[list] or 0 do
                        for _, field in ipairs(ENTRY) do
                            try(d[list][k], field, d.key .. "." .. list .. "[" .. k .. "]")
                        end
                    end
                end
                for _, field in ipairs(ENTRY) do
                    try(d.fsr, field, d.key .. ".fsr")
                end
            end
            assert.are.same({}, raised)
            assert.are.equal(errors0, I.nowErrors)
        end)
    end
end)
