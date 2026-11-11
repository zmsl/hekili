-- tests/Game/API/display_reads_spec.lua (Modern display phase 1 plan, Task 1; spec §4, M3): tools/check_api_reads.sh
-- fails any file but UI/Truth.lua that reads the facade's display class, whose answers may be secret.
local function run(path)
    local p = assert(io.popen("bash tools/check_api_reads.sh " .. path .. " 2>&1; echo rc=$?"))
    local out = p:read("*a")
    p:close()
    return tonumber(out:match("rc=(%d+)%s*$")), out
end

describe("tools/check_api_reads.sh's display rule", function()
    it("fails a file outside UI/Truth.lua that reads Facade.Display, naming the line", function()
        local rc, out = run("tests/Game/API/fixtures/display_outside_truth.lua")
        assert.are.equal(1, rc, out)
        assert.is_truthy(out:find("display_outside_truth.lua:3:", 1, true), out)
    end)

    it("passes a file that reads only the facade's other classes", function()
        local rc, out = run("tests/Game/API/fixtures/display_clean.lua")
        assert.are.equal(0, rc, out)
    end)
end)

-- range plan R2: one range source; only the facade fetches LibRangeCheck (Facade.RangeLib, Facade.LibRangeCheck)
describe("tools/check_api_reads.sh's range library rule", function()
    it("fails a file outside Game/API/Facade.lua that fetches LibRangeCheck-3.0, naming the line", function()
        local rc, out = run("tests/Game/API/fixtures/range_lib_outside_facade.lua")
        assert.are.equal(1, rc, out)
        assert.is_truthy(out:find("range_lib_outside_facade.lua:3:", 1, true), out)
    end)
end)

describe("tools/check_api_reads.sh's _G rule", function()
    for _, name in ipairs({ "g_spaced_double", "g_spaced_single" }) do
        it("fails fixtures/" .. name .. ".lua, a spaced _G string key, on line 3", function()
            local rc, out = run("tests/Game/API/fixtures/" .. name .. ".lua")
            assert.are.equal(1, rc, out)
            assert.is_truthy(out:find(name .. ".lua:3:", 1, true), out)
        end)
    end
end)
