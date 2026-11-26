-- tests/Forever/floors_tool_spec.lua: tools/floors.lua (refactor lane 4, L1827), on made-up logs and dumps.
local floors = require("tools.floors")

local function log(arm, rows)
    local out = { "gate: arm " .. arm .. " from 10:00:00" }
    for _, r in ipairs(rows) do
        out[#out + 1] = "== " .. r[1] .. " (rc=0)"
        out[#out + 1] = r[2]
            .. " solo: fights=20 agreement "
            .. r[3]
            .. " (100 ticks); ready while short 0; "
            .. "held while ready "
            .. r[4]
            .. "; refused per 100 [casting 1.0 (oracle 1.0)], episodes 0.00/min; "
            .. "flicker "
            .. r[5]
            .. "/min (oracle 0.00); retracted 0.00/min (oracle 0.00)"
            .. (r[6] and " [" .. r[6] .. "]" or "")
    end
    return table.concat(out, "\n")
end

describe("tools/floors.lua", function()
    it("lists the untraced floor fields of the three tables", function()
        local G = {
            FLICKER = { A = { heldReady = 3, flicker = 0.1, cause = { heldReady = "untraced", flicker = "L1" } } },
            ARM_FLOORS = { shipped = { B = { loOver = 2, cause = { loOver = "untraced" } } }, bands = {} },
        }
        assert.are.same({ "FLICKER\tA\theldReady\t3", "shipped\tB\tloOver\t2" }, floors.untraced(G))
    end)

    it("names the gate rows that moved, per arm and tagged line, with their spec file", function()
        local base = log("default", {
            { "a_spec.lua", "Feral", "0.990", 296, "0.00" },
            { "b_spec.lua", "Feral", "0.990", 40, "0.00", "seeds 1-3" },
            { "c_spec.lua", "Gone", "0.990", 1, "0.00" },
        })
        local head = log("default", {
            { "a_spec.lua", "Feral", "0.990", 301, "0.02" },
            { "b_spec.lua", "Feral", "0.990", 40, "0.00", "seeds 1-3" },
        }) .. "\n" .. log("shipped", { { "a_spec.lua", "Feral", "0.990", 296, "0.00" } })
        assert.are.same({
            "default\tFeral\theldReady 296 -> 301; flicker 0.00 -> 0.02\ta_spec.lua",
            "shipped\tFeral\thead only\ta_spec.lua",
            "default\tGone\tbase only\tc_spec.lua",
        }, floors.moved(base, head))
    end)

    local function dump(rows)
        local out = {}
        for _, r in ipairs(rows) do
            out[#out + 1] = table.concat(r, "\t")
        end
        return floors.dump(table.concat(out, "\n"))
    end
    local T = function(seed, n, ours, est, truth)
        return { "T", seed, n, "0.200", ours, ours, "false", "1.0000", est, "2.0000", truth }
    end

    it("finds each fight's first differing tick and says what differs first", function()
        local A = dump({
            T(1, 1, "a", "1.5000", "9"),
            T(1, 2, "a", "1.5000", "9"),
            { "F", 1, "100.0000", 2, 0, 0, 0, 0, 2 },
            T(2, 1, "a", "1.5000", "9"),
            { "F", 2, "200.0000", 1, 0, 0, 0, 0, 1 },
        })
        local B = dump({
            T(1, 1, "a", "1.5000", "9"),
            T(1, 2, "a", "1.6000", "9"),
            { "F", 1, "100.0000", 2, 0, 0, 0, 0, 2 },
            T(2, 1, "b", "1.5000", "9"),
            { "F", 2, "201.0000", 1, 0, 0, 0, 0, 1 },
        })
        local i, kinds = floors.first(A.T["1"], B.T["1"])
        assert.are.same({ 2, { "belief:est" } }, { i, kinds })
        local out = floors.diverge(A, B)
        assert.are.equal("first divergence: seed 1", out[1])
        assert.matches("^seed 1: first divergence at tick 2, belief:est$", out[2])
        local s2
        for _, l in ipairs(out) do
            s2 = s2 or l:match("^seed 2: .*")
        end
        assert.matches("boot clock moved", s2)
        assert.matches("icon:ours icon:theirs$", s2)
        assert.are.same({ 2, { "length" } }, { floors.first(A.T["1"], { A.T["1"][1] }) }) -- a shorter fight
        assert.are.equal("no divergence: every fight's in-combat ticks are the same", floors.diverge(A, A)[1])
    end)
end)
