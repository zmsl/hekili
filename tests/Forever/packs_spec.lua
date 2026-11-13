-- tests/Forever/packs_spec.lua: every `if=` in src/Hekili_*/APLs/*.simc names its auras in full. Hekili's state resolves `up`,
-- `remains` and the like only inside buff/debuff/cooldown/... tables; a bare `up` is an undefined key, so `!up` is
-- always true. And every entry whose ability is registered `gcd = "off"` carries use_off_gcd=1 (Hekili holds an entry
-- without it until the GCD ends), while no on-GCD ability does.

local BARE = { up = true, down = true, remains = true, ticking = true, refreshable = true, react = true, stack = true }

describe("Forever priorities", function()
    it("use no bare aura alias (up, down, remains, ticking, refreshable, react, stack) in a condition", function()
        local hits = {}
        local pipe = assert(io.popen("ls src/Hekili_*/APLs/*.simc"))
        for file in pipe:lines() do
            local n = 0
            for line in io.lines(file) do
                n = n + 1
                local criteria = line:match("if=(.*)$")
                if criteria then
                    for at, word in criteria:gmatch("()([%a_][%w_]*)") do
                        if BARE[word] and criteria:sub(at - 1, at - 1) ~= "." then
                            hits[#hits + 1] = file .. ":" .. n .. ": " .. word
                        end
                    end
                end
            end
        end
        pipe:close()
        assert.are.same({}, hits)
    end)

    -- Per-enemy time to die is never known on Forever (option D): `max_ttd` would make cycle_enemies 1 (State.lua's
    -- GetNumTTDsAfter answers every enemy) and spell_targets 0, `min_ttd` would gate on a number that never comes. No
    -- content addon may declare either.
    it("declare no min_ttd or max_ttd on any ability (time to die is never known on Forever)", function()
        local hits = {}
        local pipe = assert(io.popen("find src/Hekili_* -name '*.lua' | sort"))
        for file in pipe:lines() do
            local n = 0
            for line in io.lines(file) do
                n = n + 1
                if line:gsub("%-%-.*$", ""):match("m[ai][xn]_ttd%s*=") then
                    hits[#hits + 1] = file .. ":" .. n
                end
            end
        end
        pipe:close()
        assert.are.same({}, hits)
    end)

    -- the class files' recording loads (the Rogue's through load_druid)
    local LOADS = {
        warrior = function()
            return require("Forever.helpers.load_warrior").load()
        end,
        druid = function()
            return require("Forever.helpers.load_druid").load()
        end,
        rogue = function()
            return require("Forever.helpers.load_druid").load(nil, "src/Hekili_Rogue/Rogue.lua", "ROGUE")
        end,
        paladin = function()
            return require("Forever.helpers.load_druid").load(nil, "src/Hekili_Paladin/Paladin.lua", "PALADIN")
        end,
        shaman = function()
            return require("Forever.helpers.load_druid").load(nil, "src/Hekili_Shaman/Shaman.lua", "SHAMAN")
        end,
        hunter = function()
            return require("Forever.helpers.load_druid").load(nil, "src/Hekili_Hunter/Hunter.lua", "HUNTER")
        end,
    }
    for class, load in pairs(LOADS) do
        it("flag use_off_gcd=1 on exactly the off-GCD abilities (" .. class .. ")", function()
            local abilities = load().abilities
            local hits = {}
            for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", class)) do
                for list, entries in pairs(p.lists) do
                    for i, e in ipairs(entries) do
                        local a = abilities[e.action] -- nil for call_action_list, use_items and the like
                        if a and (a.gcd == "off") ~= (e.use_off_gcd == 1) then
                            hits[#hits + 1] = p.name .. " " .. list .. "[" .. i .. "]: " .. e.action
                        end
                    end
                end
            end
            table.sort(hits)
            assert.are.same({}, hits)
        end)
    end
    for class, load in pairs(LOADS) do
        it("registers every setting a priority reads on that priority's spec (" .. class .. ")", function()
            local w = load()
            local hits = {}
            for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", class)) do
                local key = type(p.spec) == "string" and p.spec:match(":(.+)$") -- nil: a pseudo-spec manifest
                for name in p.simc:gmatch("settings%.([%w_]+)") do
                    local s = w.settings[name]
                    local on = s ~= nil and (not s.specs or not key)
                    for _, k in ipairs(s and s.specs or {}) do
                        on = on or k == key
                    end
                    if not on then
                        hits[#hits + 1] = p.name .. ": settings." .. name
                    end
                end
            end
            table.sort(hits)
            assert.are.same({}, hits)
        end)
    end
    -- re-pin plan Task 7 (S1, R12): a spec opts into the Movement toggle (its NewClass entry's `movement = true`, what
    -- Registry.MovementSpec answers) exactly when one of its packs reads toggle.movement
    for _, class in ipairs({ "druid", "hunter", "mage", "paladin", "priest", "rogue", "shaman", "warlock", "warrior" }) do
        it("opts a spec into Movement exactly when its pack reads toggle.movement (" .. class .. ")", function()
            local Class = class:sub(1, 1):upper() .. class:sub(2)
            local w = LOADS[class] and LOADS[class]()
                or require("Forever.helpers.load_druid").load(
                    nil,
                    "src/Hekili_" .. Class .. "/" .. Class .. ".lua",
                    class:upper()
                )
            local reads = {}
            for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", class)) do
                local key = type(p.spec) == "string" and p.spec:match(":(.+)$")
                if key and p.simc:find("toggle.movement", 1, true) then
                    reads[key] = true
                end
            end
            local hits = {}
            for _, s in ipairs(w.def.specs) do
                if (s.movement == true) ~= (reads[s.key] == true) then
                    hits[#hits + 1] = s.key
                end
            end
            assert.are.same({}, hits)
        end)
    end
end)
