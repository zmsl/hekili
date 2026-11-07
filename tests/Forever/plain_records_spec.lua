-- tests/Forever/plain_records_spec.lua (border batch 4, the owner's design 2026-11-01): at every pack, the build's `def`
-- is plain records (no metatable anywhere in it, recursively: never a live Hekili table), and every function field the
-- belief evaluates (Families/Casts.lua I.Eval's callers) runs in the belief's `now` context without raising.
local loop = require("Game.harness.loop")
local sameKeys = require("Forever.helpers.gear_keys")

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

-- Test only (luac's listing): the global names a function reads, its nested functions' included (the ones defined
-- inside its lines). A global the belief's context lacks reads nil there, while the core's `state` may answer it; a
-- branch the run test did not take can still read it, so this reads the code, not a run.
local LUAC, listings = ".lua/bin/luac -l -p ", {}
local function globalsOf(f)
    local info = debug.getinfo(f, "S")
    local src = info.what == "Lua" and info.source:match("^@(.+)$")
    if not src then
        return {}
    end
    local fns = listings[src]
    if not fns then
        fns = {}
        local p = assert(io.popen(LUAC .. src))
        local cur
        for line in p:lines() do
            local a, b = line:match("^%a+ <[^>]-:(%d+),(%d+)>")
            if a then
                cur = { tonumber(a), tonumber(b) }
                fns[#fns + 1] = cur
            elseif cur then
                cur[#cur + 1] = line:match("GETGLOBAL%s.-; (.+)$")
            end
        end
        p:close()
        listings[src] = fns
    end
    local names = {}
    for _, fn in ipairs(fns) do
        if fn[1] > 0 and fn[1] >= info.linedefined and fn[2] <= info.lastlinedefined then
            for i = 3, #fn do
                names[fn[i]] = true
            end
        end
    end
    return names
end

-- The globals a belief-run function reads that the belief's context lacks, today: each a deferral candidate of gear
-- Task 5 (gear-task-5-report.md). A new one fails; a fixed one must leave this list.
-- Hekili_Shared Races/NightElf.lua: Shadowmeld's gate reads the core's boss / solo / moving; nil in the belief, which
-- answers "requires boss fight" there (deferral D1).
local SHADOWMELD = { "shadowmeld.usable reads boss", "shadowmeld.usable reads moving", "shadowmeld.usable reads solo" }
local function with(...)
    local out = {}
    for _, list in ipairs({ SHADOWMELD, ... }) do
        for _, v in ipairs(list) do
            out[#out + 1] = v
        end
    end
    table.sort(out)
    return out
end
-- locked_out_<school> (Hekili_Shared Shared/Auras.lua): the core's interrupt lockouts; absent in the belief by the
-- packs' design ("never locked", Mage.lua / Priest.lua / Warlock.lua unlocked()); deferral D2.
local function locked(...)
    local out = {}
    for _, pair in ipairs({ ... }) do
        out[#out + 1] = pair[1] .. ".usable reads locked_out_" .. pair[2]
    end
    return out
end
local KNOWN_MISSING = {
    ["warrior_world"] = with(),
    ["rogue_world Combat"] = with(),
    ["hunter_world BeastMastery"] = with(),
    ["shaman_world Enhancement"] = with(),
    ["druid_loop_world Feral"] = with(),
    -- removeStack: the `now`s share Mage.lua casts(spends)'s closure, whose stack branch runs only with `spends` (the
    -- handlers'): dead in the belief (Mage.lua's own note, D3)
    ["mage_world Arcane"] = with(
        {
            "arcane_blast.now reads removeStack",
            "arcane_wrath.now reads removeStack",
            "fireball.now reads removeStack",
            "frostbolt.now reads removeStack",
            "frostfire_bolt.now reads removeStack",
            "pyroblast.now reads removeStack",
            "scorch.now reads removeStack",
        },
        locked(
            { "arcane_blast", "arcane" },
            { "arcane_missiles", "arcane" },
            { "arcane_wrath", "arcane" },
            { "counterspell", "arcane" },
            { "evocation", "arcane" },
            { "fire_blast", "fire" },
            { "fireball", "fire" },
            { "frostbolt", "frost" },
            { "frostfire_bolt", "fire" },
            { "frostfire_bolt", "frost" },
            { "pyroblast", "fire" },
            { "scorch", "fire" }
        )
    ),
    -- seal_up: a RegisterStateExpr of the core's. Judgement is `ladder = false` (the belief never runs it); Swift
    -- Judgement's runs and answers nil, so the belief never reads its short answer as mana (D4)
    ["paladin_world Retribution"] = with({ "judgement.usable reads seal_up", "swift_judgement.usable reads seal_up" }),
    ["priest_world Smite"] = with(
        locked(
            { "dark_sacrifice", "shadow" },
            { "devouring_plague", "shadow" },
            { "holy_fire", "holy" },
            { "holy_nova", "holy" },
            { "mind_blast", "shadow" },
            { "mind_flay", "shadow" },
            { "penance", "holy" },
            { "shadow_word_death", "shadow" },
            { "shadow_word_pain", "shadow" },
            { "smite", "holy" },
            { "starshards", "arcane" },
            { "vampiric_embrace", "shadow" }
        )
    ),
    -- pet: the simulation's demon; the belief's context has none by the pack's design (Warlock.lua demonic_sacrifice, D5)
    ["warlock_world Affliction"] = with(
        {
            "demonic_sacrifice.now reads pet",
            "demonic_sacrifice.usable reads pet",
            "summon_felhunter.now reads pet",
            "summon_imp.now reads pet",
            "summon_incubus.now reads pet",
            "summon_succubus.now reads pet",
            "summon_voidwalker.now reads pet",
        },
        locked(
            { "bane_of_agony", "shadow" },
            { "bane_of_doom", "shadow" },
            { "conflagrate", "fire" },
            { "corruption", "shadow" },
            { "curse_of_recklessness", "shadow" },
            { "curse_of_the_elements", "shadow" },
            { "curse_of_weakness", "shadow" },
            { "death_coil", "shadow" },
            { "drain_life", "shadow" },
            { "drain_soul", "shadow" },
            { "hellfire", "fire" },
            { "immolate", "fire" },
            { "incinerate", "fire" },
            { "life_tap", "shadow" },
            { "rain_of_fire", "fire" },
            { "searing_pain", "fire" },
            { "shadow_bolt", "shadow" },
            { "shadowburn", "fire" },
            { "shadowburn", "shadow" },
            { "siphon_life", "shadow" },
            { "soul_fire", "fire" },
            { "soul_fire", "shadow" },
            { "summon_felhunter", "fire" },
            { "summon_felhunter", "shadow" },
            { "summon_imp", "shadow" },
            { "summon_incubus", "fire" },
            { "summon_incubus", "shadow" },
            { "summon_succubus", "fire" },
            { "summon_succubus", "shadow" },
            { "summon_voidwalker", "fire" },
            { "summon_voidwalker", "shadow" },
            { "wrack", "shadow" }
        )
    ),
}

-- The auras with a function field the belief leaves out of def (no spell id): the belief never evaluates them (its
-- `now` verbs return at an untracked key, Families/Now.lua aura()), so they may read the core's `state` (the Engine
-- writes them alone). A new one must be added here on purpose.
local ENGINE_ONLY = {
    -- the strikes queued on the next swing, timed from the core's state.mainhand_remains / mainhand_speed, no id
    ["warrior_world"] = { "cleave.duration", "heroic_strike.duration" },
    ["hunter_world BeastMastery"] = { "raptor_strike.duration" },
    ["druid_loop_world Feral"] = { "maul.duration" },
}

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
        local I, def, H, ns
        setup(function()
            local world = require(w[1])
            local L = loop.new(w[2] and world[w[2]] or world)
            ns = L.us.ns
            I, H = ns.VirtualStateInternal, L.us.Hekili
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

        it(name .. ": every global a belief-run function reads is in the belief's context", function()
            local hits, seen = {}, {}
            eachField(def, function(rec, field, path)
                local f = rec and rec[field]
                if type(f) == "function" and not seen[f] then
                    seen[f] = true
                    for g in pairs(globalsOf(f)) do
                        if I.nowCtx[g] == nil then
                            hits[#hits + 1] = path .. "." .. field .. " reads " .. g
                        end
                    end
                end
            end)
            table.sort(hits)
            assert.are.same(assert(KNOWN_MISSING[name], name), hits)
        end)

        it(name .. ": an aura function the belief does not track is listed as the core's alone", function()
            local tracked, only = {}, {}
            for j = 1, #def.auras do
                tracked[def.auras[j].key] = true
            end
            for k, a in pairs(H.Class.auras) do
                local funcs = type(a) == "table" and a.key == k and not tracked[k] and rawget(a, "funcs")
                for _, field in ipairs(funcs and AURA or {}) do
                    if type(funcs[field]) == "function" then
                        only[#only + 1] = k .. "." .. field
                    end
                end
            end
            table.sort(only)
            assert.are.same(ENGINE_ONLY[name] or {}, only)
        end)

        -- a cost modifier's `aura` and `unless` (CN11) are aura keys the belief resolves at the build (Modifiers.lua):
        -- each a tracked aura, the record Tracked.lua's plain() copy of the core's declaration
        it(name .. ": every cost modifier's aura and `unless` name a tracked aura, in a plain copy", function()
            local tracked, missing, src = {}, {}, ns.raceMods.costMods
            for j = 1, #def.auras do
                tracked[def.auras[j].key] = true
            end
            for r = 1, #def.resources do
                local list = def.resources[r].costMods or {}
                assert.are.equal(#src, #list)
                for k = 1, #list do
                    local m = list[k]
                    assert.are_not.equal(src[k], m)
                    assert.are.same({ src[k].aura, src[k].unless }, { m.aura, m.unless })
                    for _, key in ipairs({ m.aura, m.unless or m.aura }) do
                        if not tracked[key] then
                            missing[#missing + 1] = def.resources[r].key .. ".costMods[" .. k .. "] " .. tostring(key)
                        end
                    end
                end
            end
            assert.are.same({}, missing)
        end)

        it(name .. ": the gear keys are the same on both sides", function()
            sameKeys(H.Class, def, I)
        end)
    end
end)
