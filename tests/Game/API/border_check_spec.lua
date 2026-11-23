-- tests/Game/API/border_check_spec.lua (audit 2026-11-02 item 12): tools/check_border.sh on a Game/ stand-in fails
-- every way a belief file can reach the core, ns spelled any way but ns.Facade, ns.VirtualState and
-- ns.VirtualStateInternal included; with a core stand-in (its second argument, scanned with the real core) it accepts
-- exactly the four approved calls Drain, Build, SetLog and WindowOp (WindowOp: windows design v6 §5.6), and a stand-in
-- path that matches no file fails. Facade.TargetID (L1734): BORDER_STATE stands in for State.lua (its two reads inside
-- landsElsewhere only), BORDER_PACKS for the root the pack scan walks.
local function run(path, core, env)
    local p = assert(
        io.popen(
            (env or "") .. " bash tools/check_border.sh " .. (path or "") .. " " .. (core or "") .. " 2>&1; echo rc=$?"
        )
    )
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
        assert.is_truthy(out:match("^ok:[^\n]*Facade%.TargetID[^\n]*State%.lua"), out) -- L1734: its one reader
    end)

    it("accepts the core's Drain, Build, SetLog and WindowOp, and nothing else", function()
        local rc, out = run("src/Hekili/Game", FIXTURES .. "core_ok.lua")
        assert.are.equal(0, rc, out)
        for _, name in ipairs({ "core_near", "core_window", "core_targetid" }) do
            rc, out = run("src/Hekili/Game", FIXTURES .. name .. ".lua")
            assert.are.equal(1, rc, out)
            assert.is_truthy(out:find(name .. ".lua:3:", 1, true), out)
        end
    end)

    it("fails a pack naming Facade.TargetID, through the pack scan (Hekili.Client is ns.Facade)", function()
        local rc, out = run("src/Hekili/Game", nil, "BORDER_PACKS=" .. FIXTURES .. "packs")
        assert.are.equal(1, rc, out)
        assert.is_truthy(out:find("Hekili_Fixture/pack_targetid.lua:3:", 1, true), out)
    end)

    describe("State.lua's two Facade.TargetID reads", function()
        local real = assert(io.open("src/Hekili/Engine/Sim/State.lua")):read("*a")
        local function copy(text)
            local path = os.tmpname()
            local f = assert(io.open(path, "w"))
            f:write(text)
            f:close()
            return path
        end
        -- Replace the one plain-text occurrence of `from` by `to`.
        local function swap(text, from, to)
            local i, j = text:find(from, 1, true)
            assert.is_truthy(i, from)
            assert.is_nil(text:find(from, j + 1, true), from)
            return text:sub(1, i - 1) .. to .. text:sub(j + 1)
        end

        it("pass in landsElsewhere, an unchanged copy standing in", function()
            local path = copy(real)
            local rc, out = run(nil, nil, "BORDER_STATE=" .. path)
            os.remove(path)
            assert.are.equal(0, rc, out)
        end)

        it("fail when one moves out of landsElsewhere, still two (into ResetQueues)", function()
            local text = swap(real, "castPin.id ~= Facade.TargetID()", "castPin.id ~= castPin.now")
            text = swap(text, "e.target = r.target\n", "e.target = r.target or Facade.TargetID()\n")
            local path = copy(text)
            local rc, out = run(nil, nil, "BORDER_STATE=" .. path)
            os.remove(path)
            assert.are.equal(1, rc, out)
            assert.is_truthy(out:find("e.target = r.target or Facade.TargetID()", 1, true), out)
        end)

        it("fail when one inside landsElsewhere feeds the GUID field, still two (m1)", function()
            local text = swap(real, "castPin.id ~= Facade.TargetID()", "castPin.id ~= e.target")
            text = swap(
                text,
                "local g = e.target\n",
                "e.target = e.target or Facade.TargetID()\n        local g = e.target\n"
            )
            local path = copy(text)
            local rc, out = run(nil, nil, "BORDER_STATE=" .. path)
            os.remove(path)
            assert.are.equal(1, rc, out)
            assert.is_truthy(out:find("e.target = e.target or Facade.TargetID()", 1, true), out)
        end)
    end)

    it("fails a core stand-in path that matches no file", function()
        local rc, out = run("src/Hekili/Game", FIXTURES .. "missing")
        assert.are.equal(1, rc, out)
        assert.is_truthy(out:find("missing", 1, true), out)
    end)
end)
