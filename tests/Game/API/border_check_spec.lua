-- tests/Game/API/border_check_spec.lua (audit 2026-11-02 item 12): tools/check_border.sh on a Game/ stand-in fails
-- every way a belief file can reach the core, ns spelled any way but the three approved names included.
local function run(path)
    local p = assert(io.popen("bash tools/check_border.sh " .. (path or "") .. " 2>&1; echo rc=$?"))
    local out = p:read("*a")
    p:close()
    return tonumber(out:match("rc=(%d+)%s*$")), out
end

describe("tools/check_border.sh", function()
    for _, name in ipairs({ "hook", "bracket", "spaced", "class", "rawget" }) do
        it("fails fixtures/border/" .. name .. ".lua on line 3", function()
            local rc, out = run("tests/Game/API/fixtures/border/" .. name .. ".lua")
            assert.are.equal(1, rc, out)
            assert.is_truthy(out:find(name .. ".lua:3:", 1, true), out)
        end)
    end

    it("passes the real tree", function()
        local rc, out = run()
        assert.are.equal(0, rc, out)
        assert.is_truthy(out:match("^ok:[^\n]*Facade%.Window[^\n]*Facade%.DebuffCount"), out) -- the owner's two belief reads
    end)
end)
