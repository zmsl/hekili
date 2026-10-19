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
end)
