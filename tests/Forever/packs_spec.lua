-- tests/Forever/packs_spec.lua: every `if=` in tools/packs/*/*.simc names its auras in full. Hekili's state resolves `up`,
-- `remains` and the like only inside buff/debuff/cooldown/... tables; a bare `up` is an undefined key, so `!up` is
-- always true. And every entry whose ability is registered `gcd = "off"` carries use_off_gcd=1 (Hekili holds an entry
-- without it until the GCD ends), while no on-GCD ability does.

local BARE = { up = true, down = true, remains = true, ticking = true, refreshable = true, react = true, stack = true }

describe("Forever priorities", function()
    it("use no bare aura alias (up, down, remains, ticking, refreshable, react, stack) in a condition", function()
        local hits = {}
        local pipe = assert(io.popen("ls tools/packs/*/*.simc"))
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

    for class, loader in pairs({ warrior = "load_warrior", druid = "load_druid" }) do
        it("flag use_off_gcd=1 on exactly the off-GCD abilities (" .. class .. ")", function()
            local abilities = require("Forever.helpers." .. loader).load().abilities
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
end)
