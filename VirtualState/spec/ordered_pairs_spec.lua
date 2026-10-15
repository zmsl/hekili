-- VirtualState/spec/ordered_pairs_spec.lua
-- Hekili's ns.orderedPairs (Utils.lua): iterating a table whose __newindex wraps assigned tables (State.lua's
-- mt_talents) must not leave a metatable on the shared index list, or every later loop yields a phantom numeric key.
local load = require("VirtualState.spec.helpers.load")

describe("ns.orderedPairs", function()
    it("yields no phantom key after iterating a table whose __newindex wraps assigned tables", function()
        local ns = load.module()
        local savedHekili, savedLibStub = rawget(_G, "Hekili"), rawget(_G, "LibStub")
        _G.Hekili = { Class = {}, State = {} }
        _G.LibStub = function()
            return {}
        end
        assert(loadfile("Utils.lua"))("Hekili", ns)
        _G.Hekili, _G.LibStub = savedHekili, savedLibStub

        -- mt_talents' __newindex and mt_default_talent's __index, as State.lua has them
        local mtDefault = {
            __index = function(_, k)
                return k
            end,
        }
        local talents = setmetatable({}, {
            __newindex = function(t, k, v)
                if type(v) == "table" then
                    rawset(t, k, setmetatable(v, mtDefault))
                    return
                end
                rawset(t, k, v)
            end,
        })
        rawset(talents, "x", { enabled = true })
        for _ in ns.orderedPairs(talents) do
        end

        local plain = {}
        for i = 1, 20 do
            plain[string.format("k%02d", i)] = i
        end
        local n = 0
        for k, v in ns.orderedPairs(plain) do
            n = n + 1
            assert.are.equal(plain[k], v)
            assert.is_not_nil(v)
        end
        assert.are.equal(20, n)
        assert.is_nil(rawget(plain, "__orderedIndex"))
    end)
end)
