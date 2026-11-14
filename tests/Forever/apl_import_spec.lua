-- tests/Forever/apl_import_spec.lua: the in-game priority importer (Options.lua ImportSimcAPL, ParseActionList) takes
-- every character a line holds (the XOR operator `^` included) and splits a line's options only at commas outside
-- parentheses, so min(a,b) and max(a,b) stay in their condition. And every shipped pack survives a round trip: its
-- source text as the Source tab shows it, re-imported as the tab's Import button does, gives the pack's own entries,
-- and every line compiles.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local function boot()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    return H
end

local function bare(s)
    return (s:gsub("%s", ""))
end

describe("the priority importer", function()
    local H
    setup(function()
        H = boot()
    end)

    it("keeps a line's ^ and everything after it, as one entry", function()
        local out = H.Hekili:ParseActionList("actions+=/slam,if=buff.a.up^action.slam.ready=1\n")
        assert.are.equal(1, #out)
        assert.are.equal("buff.a.up^action.slam.ready=1", bare(out[1].criteria))
        local lists = H.Hekili:ImportSimcAPL(nil, nil, "actions=slam,if=buff.a.up^action.slam.ready=1\n")
        assert.are.equal(1, #lists.default)
        assert.are.equal("buff.a.up^action.slam.ready=1", bare(lists.default[1].criteria))
    end)

    it("splits a line only at commas outside parentheses", function()
        local out = H.Hekili:ParseActionList("actions+=/slam,use_off_gcd=1,if=min(rage,energy)>max(1,2),focus=2\n")
        assert.are.equal(1, #out)
        assert.are.equal("slam", out[1].action)
        assert.are.equal(1, out[1].use_off_gcd)
        assert.are.equal(2, out[1].focus)
        assert.are.equal("min(rage,energy)>max(1,2)", bare(out[1].criteria))
    end)
end)

-- a character per class: the world helper's content for one of its packs (every pack of the class loads with it)
local WORLDS = {
    DRUID = { "Forever.helpers.druid_loop_world", "Feral" },
    HUNTER = { "Forever.helpers.hunter_world", "Survival" },
    MAGE = { "Forever.helpers.mage_world", "Arcane" },
    PALADIN = { "Forever.helpers.paladin_world", "Retribution" },
    PRIEST = { "Forever.helpers.priest_world", "Shadow" },
    ROGUE = { "Forever.helpers.rogue_world", "Combat" },
    SHAMAN = { "Forever.helpers.shaman_world", "Enhancement" },
    WARLOCK = { "Forever.helpers.warlock_world", "Affliction" },
    WARRIOR = { "Forever.helpers.warrior_world" },
}

-- the compile errors of every loaded script: its conditions (syntax or the pcall at the booted spec) and its modifiers
local function scriptErrors(H, names)
    local DB, out = H.Hekili.Scripts.DB, {}
    for name in pairs(names) do
        for list, entries in pairs(H.Hekili.DB.profile.packs[name].lists) do
            for i in ipairs(entries) do
                local id = name .. ":" .. list .. ":" .. i
                local s = DB[id]
                if not s then
                    out[#out + 1] = id .. ": not loaded"
                else
                    if s.Error then
                        out[#out + 1] = id .. ": " .. s.Error
                    end
                    for k, v in pairs(s.Modifiers or {}) do
                        if type(k) == "string" and k:sub(1, 6) == "error:" then
                            out[#out + 1] = id .. " " .. k .. ": " .. tostring(v)
                        end
                    end
                end
            end
        end
    end
    table.sort(out)
    return out
end

describe("every shipped pack's Source tab text", function()
    it("re-imports to the pack's own entries, every line compiling", function()
        local manifest, seen = {}, {}
        local pipe = assert(io.popen("ls src/Hekili_*/APLs/packs.lua"))
        for file in pipe:lines() do
            local def = dofile(file)
            for _, name in ipairs(def.packs) do
                manifest[name] = def.class
            end
        end
        pipe:close()

        local hits = {}
        for class, w in pairs(WORLDS) do
            local M = require(w[1])
            local C = w[2] and M[w[2]] or M
            local H = headless.new({ character = C.character(), pack = C.PACK })
            assert.are.same({}, H.loadErrors)
            local names = {}
            for name, p in pairs(H.Hekili.DB.profile.packs) do
                if manifest[name] == class then
                    names[name] = true
                end
            end
            H.Hekili:LoadScripts()
            local before = scriptErrors(H, names)
            for name in pairs(names) do
                seen[name] = true
                local p = H.Hekili.DB.profile.packs[name]
                -- the Source tab's text is the pack's `profile` (GetPackOption returns it as is); Import strips `"`
                assert.is_string(p.profile, name)
                local got = H.Hekili:ImportSimcAPL(nil, nil, (p.profile:gsub('"', "")))
                for list, entries in pairs(got) do
                    local want = p.lists[list]
                    if not want then -- only the importer's placeholder for an absent precombat or default list
                        for i, e in ipairs(entries) do
                            if e.action ~= "wait" or e.enabled ~= false then
                                hits[#hits + 1] = name
                                    .. " "
                                    .. list
                                    .. "["
                                    .. i
                                    .. "]: an extra entry "
                                    .. tostring(e.action)
                            end
                        end
                    end
                end
                for list, entries in pairs(p.lists) do
                    local g = got[list] or {}
                    if #g ~= #entries then
                        hits[#hits + 1] = name .. " " .. list .. ": " .. #g .. " entries, want " .. #entries
                    end
                    for i, e in ipairs(entries) do
                        local ge = g[i] or {}
                        for k, v in pairs(e) do
                            local a, b = tostring(v), tostring(ge[k])
                            if k == "criteria" then -- the importer spaces a condition out (SpaceOut)
                                a, b = bare(a), bare(b)
                            end
                            if a ~= b then
                                hits[#hits + 1] = name
                                    .. " "
                                    .. list
                                    .. "["
                                    .. i
                                    .. "]."
                                    .. k
                                    .. ": "
                                    .. b
                                    .. ", want "
                                    .. a
                            end
                        end
                        for k, v in pairs(ge) do
                            if e[k] == nil then
                                hits[#hits + 1] = name
                                    .. " "
                                    .. list
                                    .. "["
                                    .. i
                                    .. "]."
                                    .. k
                                    .. ": extra "
                                    .. tostring(v)
                            end
                        end
                    end
                end
                p.lists = got
            end
            H.Hekili:LoadScripts()
            assert.are.same({}, before)
            for _, e in ipairs(scriptErrors(H, names)) do
                hits[#hits + 1] = e
            end
        end
        for name in pairs(manifest) do
            if not seen[name] then
                hits[#hits + 1] = name .. ": not round-tripped (no world boots its class)"
            end
        end
        table.sort(hits)
        assert.are.same({}, hits)
    end)
end)
