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
local ABILITY = { "cooldown", "spend", "gcdTime", "usable", "now", "onCrit" }
local AURA = { "duration", "tick_time", "base_tick_time" }
local RESOURCE = { "max", "decay", "decayInterval", "swingValue", "swingOff", "swingCrit", "swingOffCrit", "taken" }
local ENTRY = { "spirit", "mp5", "share", "value", "mult", "when" }
local WINDOW = { "evaluator" } -- a window's (Families/Windows.lua), run once per Drain in the same context
local REACTION = { "now" } -- a reaction's (RegisterReaction, Families/Now.lua), run at a settled outcome

-- Every field the belief evaluates, by `visit(rec, field, path)`.
local function eachField(def, visit)
    for a = 1, #def.abilities do
        for _, field in ipairs(ABILITY) do
            visit(def.abilities[a], field, tostring(def.abilities[a].key))
        end
    end
    for w = 1, #def.windows do
        for _, field in ipairs(WINDOW) do
            visit(def.windows[w], field, "window " .. tostring(def.windows[w].key))
        end
    end
    for k = 1, #(def.reactions or {}) do
        for _, field in ipairs(REACTION) do
            visit(def.reactions[k], field, "reaction " .. tostring(def.reactions[k].key))
        end
    end
    for j = 1, #def.auras do
        for _, field in ipairs(AURA) do
            visit(def.auras[j], field, "aura " .. tostring(def.auras[j].key))
        end
    end
    for r = 1, #def.resources do
        local d = def.resources[r]
        for _, field in ipairs(RESOURCE) do
            visit(d, field, d.key)
        end
        for _, list in ipairs({ "mult", "auraRegen", "maxMods", "costMods" }) do
            for k = 1, d[list] and #d[list] or 0 do
                for _, field in ipairs(ENTRY) do
                    visit(d[list][k], field, d.key .. "." .. list .. "[" .. k .. "]")
                end
            end
        end
        for _, field in ipairs(ENTRY) do
            visit(d.fsr, field, d.key .. ".fsr")
        end
    end
end

-- The core's tables and functions a belief function must not reach (`state`, `Hekili`, `class` and what `state` holds
-- directly: `state.swings`, a function of its own), and where the walk stops: the facade, the border's sanctioned read,
-- and Lua's own libraries, either of which `state` may also list.
local function fencesOf(Hekili)
    local bad, stop = { [Hekili] = "Hekili", [Hekili.State] = "state", [Hekili.Class] = "class" }, {}
    for k, v in pairs(Hekili.State) do
        if type(v) == "table" or type(v) == "function" then
            bad[v] = bad[v] or ("state." .. tostring(k))
        end
    end
    local libs = { _G, math, string, table, Hekili.Client }
    for _, v in pairs(Hekili.Client) do
        if type(v) == "table" then
            libs[#libs + 1] = v -- a namespace (Facade.C_Item)
        end
    end
    for _, lib in ipairs(libs) do
        stop[lib] = true
        for _, v in pairs(lib) do
            if type(v) == "function" then
                stop[v] = true
            end
        end
    end
    return bad, stop
end

-- Test only: debug.getupvalue is not in the client. It sees what a function captured, not whether a path reads it, and
-- it misses a global read inside a helper (a helper's environment is the file's): a capture is a failure anyway.
local function reaches(v, path, bad, stop, seen, hits)
    local t = type(v)
    if (t ~= "function" and t ~= "table") or stop[v] or seen[v] then
        return
    end
    if bad[v] then
        hits[#hits + 1] = path .. " reaches " .. bad[v]
        return
    end
    seen[v] = true
    if t == "function" then
        local i, name, up = 1, debug.getupvalue(v, 1)
        while name do
            reaches(up, path .. " > " .. name, bad, stop, seen, hits)
            i = i + 1
            name, up = debug.getupvalue(v, i)
        end
    else
        for k, x in pairs(v) do
            reaches(x, path .. "." .. tostring(k), bad, stop, seen, hits)
        end
    end
end

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
        local I, def, H
        setup(function()
            local world = require(w[1])
            local L = loop.new(w[2] and world[w[2]] or world)
            I, H = L.us.ns.VirtualStateInternal, L.us.Hekili
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
            eachField(def, try)
            assert.are.same({}, raised)
            assert.are.equal(errors0, I.nowErrors)
        end)

        it(name .. ": no function the belief evaluates reaches state, Hekili or class", function()
            local bad, stop = fencesOf(H)
            local hits, seen = {}, {}
            eachField(def, function(rec, field, path)
                local f = rec and rec[field]
                if type(f) == "function" and not seen[f] then
                    seen[f] = true
                    reaches(f, path .. "." .. field, bad, stop, {}, hits)
                end
            end)
            table.sort(hits)
            assert.are.same({}, hits)
        end)
    end
end)
