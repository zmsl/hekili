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
