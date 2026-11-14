-- tests/Forever/enus_text_spec.lua (localization plan, Task 1; spec §8): the English a player sees is byte-identical
-- to the merge base. The golden tests/Forever/fixtures/enus_text.txt was written once at 1ef1a63b, before any L[...],
-- by this spec with ENUS_GOLDEN=update (tests/Forever/helpers/enus_text.lua is the dump); every later commit must
-- reproduce it byte for byte. ENUS_GOLDEN=update rewrites it for an intended English change: say why in the commit.
local enus = require("Forever.helpers.enus_text")

local PATH = "tests/Forever/fixtures/enus_text.txt"
local MAX_DIFF = 40

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
        if want ~= text then -- every differing line (capped), not only the first
            local a, b, diff = lines(want), lines(text), {}
            for i = 1, math.max(#a, #b) do
                if a[i] ~= b[i] then
                    diff[#diff + 1] = ("line %d\n  golden: %s\n  now:    %s"):format(i, tostring(a[i]), tostring(b[i]))
                end
            end
            local shown = {}
            for i = 1, math.min(#diff, MAX_DIFF) do
                shown[i] = diff[i]
            end
            if #diff == 0 then
                assert.are.equal(want, text) -- a difference no line shows (a trailing newline)
            end
            error(
                ("%d differing line(s)%s:\n%s"):format(
                    #diff,
                    #diff > MAX_DIFF and (", first %d shown"):format(MAX_DIFF) or "",
                    table.concat(shown, "\n")
                ),
                0
            )
        end
        assert.are.equal(want, text)
    end)
end)
