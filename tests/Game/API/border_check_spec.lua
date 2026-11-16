-- tests/Game/API/border_check_spec.lua (audit 2026-11-02 item 12): tools/check_border.sh on a Game/ stand-in fails
-- every way a belief file can reach the core, ns spelled any way but the three approved names included; on a core
-- stand-in (its second argument) it accepts exactly the approved calls, WindowOp the one new (windows design v6 §5.6).
local function run(path, core)
    local p =
        assert(io.popen("bash tools/check_border.sh " .. (path or "") .. " " .. (core or "") .. " 2>&1; echo rc=$?"))
    local out = p:read("*a")
    p:close()
    return tonumber(out:match("rc=(%d+)%s*$")), out
end

local FIXTURES = "tests/Game/API/fixtures/border/"

describe("tools/check_border.sh", function()
    for _, name in ipairs({ "hook", "bracket", "spaced", "class", "rawget" }) do
        it("fails fixtures/border/" .. name .. ".lua on line 3", function()
            local rc, out = run(FIXTURES .. name .. ".lua")
            assert.are.equal(1, rc, out)
            assert.is_truthy(out:find(name .. ".lua:3:", 1, true), out)
        end)
    end

    it("passes the real tree", function()
        local rc, out = run()
        assert.are.equal(0, rc, out)
        assert.is_truthy(out:match("^ok:[^\n]*Facade%.Window[^\n]*Facade%.DebuffCount"), out) -- the owner's two belief reads
        assert.is_truthy(out:match("^ok:[^\n]*WindowOp"), out)
    end)

    it("accepts the core's Drain, Build, SetLog and WindowOp, and nothing else", function()
        local rc, out = run("src/Hekili/Game", FIXTURES .. "core_ok.lua")
        assert.are.equal(0, rc, out)
        for _, name in ipairs({ "core_near", "core_window" }) do
            rc, out = run("src/Hekili/Game", FIXTURES .. name .. ".lua")
            assert.are.equal(1, rc, out)
            assert.is_truthy(out:find(name .. ".lua:3:", 1, true), out)
        end
    end)
end)
