-- tests/Forever/packs_spec.lua: every `if=` in tools/packs/*.lua names its auras in full. Hekili's state resolves `up`,
-- `remains` and the like only inside buff/debuff/cooldown/... tables; a bare `up` is an undefined key, so `!up` is
-- always true.

local BARE = { up = true, down = true, remains = true, ticking = true, refreshable = true, react = true, stack = true }

describe("Forever priorities", function()
    it("use no bare aura alias (up, down, remains, ticking, refreshable, react, stack) in a condition", function()
        local hits = {}
        local pipe = assert(io.popen("ls tools/packs/*.lua"))
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
end)
