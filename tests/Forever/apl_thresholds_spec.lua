-- tests/Forever/apl_thresholds_spec.lua (LibHiddenValues integration design 3.1-3.4, lane B7 part 1): the compiler's
-- harvest of APL thresholds. ns.AplThresholds (Engine/Sim/AplThresholds.lua) turns a condition's comparisons of a known
-- token with a number literal into { key, kind, n } records; Hekili:LoadScript keeps them on the script (`Bands`),
-- scripts:PackBands unions them over a priority, and the active priority's go to the belief's def as
-- def.bandPoints[powerType] = { points, deficit, pct } at a new def.bandGen. Over the point cap a resource sends no
-- points and the priority's editor shows a warning line. Nothing in the belief reads them yet (part 2).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local RAGE = 1 -- Enum.PowerType.Rage
local RES = { energy = true, mana = true, rage = true }

local H, scan

local function boot()
    H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    scan = H.ns.AplThresholds
end

-- the records of `cond` as { key, kind, n } rows
local function rows(cond)
    local out = {}
    local n = scan(cond, RES, out)
    assert.are.equal(#out, n)
    local r = {}
    for i, rec in ipairs(out) do
        r[i] = { rec.key, rec.kind, rec.n }
    end
    return r
end

local OPS = {
    [">="] = function(a, b)
        return a >= b
    end,
    [">"] = function(a, b)
        return a > b
    end,
    ["<"] = function(a, b)
        return a < b
    end,
    ["<="] = function(a, b)
        return a <= b
    end,
    ["="] = function(a, b)
        return a == b
    end,
    ["!="] = function(a, b)
        return a ~= b
    end,
}
local FLIP = { [">="] = "<=", [">"] = "<", ["<"] = ">", ["<="] = ">=", ["="] = "=", ["!="] = "!=" }

describe("the APL threshold harvest", function()
    setup(boot)

    describe("ns.AplThresholds: strings to records", function()
        it("points: <res>, .current, .actual, by the operator rule", function()
            assert.are.same({ { "rage", "points", 40 } }, rows("rage>=40"))
            assert.are.same({ { "rage", "points", 40 } }, rows("rage.current<40"))
            assert.are.same({ { "rage", "points", 41 } }, rows("rage.actual>40"))
            assert.are.same({ { "rage", "points", 41 } }, rows("rage<=40"))
            assert.are.same({ { "mana", "points", 500 }, { "mana", "points", 501 } }, rows("mana=500"))
            assert.are.same({ { "mana", "points", 500 }, { "mana", "points", 501 } }, rows("mana!=500"))
        end)

        it("a fractional literal: ceil, under every ordering operator; = and != never bound a whole value", function()
            for _, op in ipairs({ ">=", ">", "<", "<=" }) do
                assert.are.same({ { "energy", "points", 41 } }, rows("energy" .. op .. "40.5"), op)
            end
            assert.are.same({}, rows("energy=40.5"))
            assert.are.same({}, rows("energy!=40.5"))
        end)

        it("<number><op><token> reads as the token compared the other way", function()
            assert.are.same({ { "rage", "points", 40 } }, rows("40<=rage"))
            assert.are.same({ { "rage", "points", 41 } }, rows("40<rage"))
            assert.are.same({ { "rage", "deficit", 19 } }, rows("20<=rage.deficit"))
        end)

        it("a comparison always true or never true sends nothing", function()
            assert.are.same({}, rows("rage>=0"))
            assert.are.same({}, rows("rage.deficit>=0"))
            assert.are.same({ { "rage", "points", 1 } }, rows("rage=0")) -- `=0` is "not at least 1"
        end)

        it("deficit: n with the point max - n, the operator rule mirrored", function()
            assert.are.same({ { "energy", "deficit", 29 } }, rows("energy.deficit>=30"))
            assert.are.same({ { "energy", "deficit", 30 } }, rows("energy.deficit>30"))
            assert.are.same({ { "energy", "deficit", 29 } }, rows("energy.deficit<30"))
            assert.are.same({ { "energy", "deficit", 30 } }, rows("energy.deficit<=30"))
            assert.are.same({ { "energy", "deficit", 29 }, { "energy", "deficit", 30 } }, rows("energy.deficit=30"))
            assert.are.same({ { "energy", "deficit", 30 } }, rows("energy.deficit>30.5"))
            assert.are.same({ { "energy", "deficit", 0 } }, rows("energy.deficit>0")) -- at max
        end)

        it("pct: <res>.pct and .percent, the literal as written", function()
            assert.are.same({ { "mana", "pct", 35 } }, rows("mana.pct<35"))
            assert.are.same({ { "mana", "pct", 33.3 } }, rows("mana.percent>=33.3"))
        end)

        it("health: the player's and the target's percent, and target.time_to_pct_<N>", function()
            assert.are.same({ { "health", "pct", 35 } }, rows("health.pct<35"))
            assert.are.same({ { "health", "pct", 50 } }, rows("health.percent>50"))
            assert.are.same({ { "target.health", "pct", 20 } }, rows("target.health.pct<20"))
            assert.are.same({ { "target.health", "pct", 20 } }, rows("target.health.percent<=20"))
            assert.are.same({ { "target.health", "pct", 20.5 } }, rows("target.health_pct<20.5"))
            assert.are.same({ { "target.health", "pct", 35 } }, rows("target.time_to_pct_35>2"))
        end)

        it("aura records for lane C4: stacks and seconds left, the literal as written", function()
            assert.are.same({ { "buff.aura_a.stack", "aura", 3 } }, rows("buff.aura_a.stack>=3"))
            assert.are.same({ { "debuff.aura_b.stack", "aura", 5 } }, rows("debuff.aura_b.stack<5"))
            assert.are.same({ { "buff.aura_a.remains", "aura", 2.5 } }, rows("buff.aura_a.remains<2.5"))
            assert.are.same({ { "debuff.aura_b.remains", "aura", 4 } }, rows("4>debuff.aura_b.remains"))
            assert.are.same({ { "dot.aura_c.remains", "aura", 3 } }, rows("dot.aura_c.remains<=3"))
        end)

        it("every leaf: & and | at any depth, a leading ! and outer parentheses stripped, spaces ignored", function()
            assert.are.same({
                { "energy", "points", 40 },
                { "mana", "pct", 35.5 },
                { "rage", "points", 21 },
                { "health", "pct", 20 },
            }, rows("!(energy>=40|buff.aura_a.up)&((mana.pct<35.5))&rage>20|!(health.pct < 20)"))
            assert.are.same({ { "energy", "points", 40 } }, rows(" energy >= 40 "))
        end)

        it("whole names only, and never an expression", function()
            for _, c in ipairs({
                "pet.health.pct<50",
                "pet.energy>=40",
                "energyx>=40",
                "focus>=40", -- not one of the resources passed
                "energy>=action.spender_a.cost+10",
                "energy+energy.regen*gcd>60",
                "energy>=40+x",
                "energy.max>100",
                "energy.regen>10",
                "energy.time_to_max<2",
                "variable.energy_ok>5",
                "health>5000", -- bare health: no points on health
                "health.current<5",
                "target.health.current<5",
                "cooldown.spell_a.remains<2",
                "buff.aura_a.up",
                "min:target.health.pct", -- a target_if: no comparison
                "energy>=",
                "energy>=4e",
                "",
            }) do
                assert.are.same({}, rows(c), c)
            end
            local out = {}
            assert.are.equal(0, scan(nil, RES, out))
            assert.are.equal(0, scan(42, RES, out))
            assert.are.same({}, out)
        end)

        it("appends to `out` and returns the count it added", function()
            local out = { "kept" }
            assert.are.equal(2, scan("rage>=10&mana.pct<5", RES, out))
            assert.are.equal(3, #out)
            assert.are.equal("kept", out[1])
        end)

        -- every comparison of a power value x in 0..max is a function of the bars' answers x >= p (deficit: p = max - n):
        -- two values with the same answers compare alike, so the bars decide the condition exactly
        it("exact: every operator, both orders, whole and fractional literals, points and deficit", function()
            local MAX = 20
            for _, kind in ipairs({ "points", "deficit" }) do
                for op, f in pairs(OPS) do
                    for _, N in ipairs({ 0, 1, 5, 5.5, 19, 20 }) do
                        local tok = kind == "points" and "rage" or "rage.deficit"
                        for _, cond in ipairs({ tok .. op .. N, N .. FLIP[op] .. tok }) do
                            local out = {}
                            scan(cond, RES, out)
                            local bars = {}
                            for _, r in ipairs(out) do
                                assert.are.equal(kind, r.kind, cond)
                                bars[#bars + 1] = kind == "points" and r.n or MAX - r.n
                            end
                            local seen = {}
                            for x = 0, MAX do
                                local key = ""
                                for _, p in ipairs(bars) do
                                    key = key .. (x >= p and "1" or "0")
                                end
                                local v = kind == "points" and x or MAX - x
                                local truth = f(v, N)
                                if seen[key] == nil then
                                    seen[key] = truth
                                end
                                assert.are.equal(seen[key], truth, cond .. " at " .. x)
                            end
                        end
                    end
                end
            end
        end)
    end)
end)
