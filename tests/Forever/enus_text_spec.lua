-- tests/Forever/enus_text_spec.lua (localization plan, Task 1; spec §8): the English a player sees is byte-identical
-- to the merge base. The golden tests/Forever/fixtures/enus_text.txt was written once at 1ef1a63b, before any L[...],
-- by this spec with ENUS_GOLDEN=update (tests/Forever/helpers/enus_text.lua is the dump); every later commit must
-- reproduce it byte for byte. ENUS_GOLDEN=update rewrites it for an intended English change: say why in the commit.
local enus = require("Forever.helpers.enus_text")

local PATH = "tests/Forever/fixtures/enus_text.txt"

local function lines(s)
    local out = {}
    for l in s:gmatch("([^\n]*)\n") do
        out[#out + 1] = l
    end
    return out
end

describe("the English text a player sees", function()
    it("is byte-identical to the golden written at the merge base", function()
        local text = table.concat(enus.dump(), "\n") .. "\n"
        if os.getenv("ENUS_GOLDEN") == "update" then
            local f = assert(io.open(PATH, "wb"))
            f:write(text)
            f:close()
        end
        local f = assert(io.open(PATH, "rb"), "no golden: write it at the merge base (localization plan, Task 1)")
        local want = f:read("*a")
        f:close()
        if want ~= text then -- name the first line that differs, not all of them
            local a, b = lines(want), lines(text)
            for i = 1, math.max(#a, #b) do
                assert.are.equal(a[i], b[i], "golden line " .. i)
            end
        end
        assert.are.equal(want, text)
    end)
end)
