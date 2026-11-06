-- tests/Game/harness/swing_recheck_spec.lua: the engine's recheck times for a hand's wrapping swing clock (R61).
-- A line's failed condition is rechecked at the times scripts:BuildRecheck compiles (Scripts.lua
-- ConvertTimeComparison), all read at the line's ready time; the engine takes the first time at which the condition
-- holds (Core.lua's recheck loop). A two-sided near-swing guard `X<=X_speed-g&X>=h` is false for h before a swing and
-- g after it; a ready time in the pre-swing half must find the guard's window end (swing + g), not only swing + 0.01,
-- where the since-swing half is still false.
local headless = require("Game.harness.headless")

describe("a wrapping swing clock's recheck times (Scripts.lua ConvertTimeComparison)", function()
    local Sc
    local SPEED = 3.0

    local H
    setup(function()
        H = headless.new({}).Hekili
        Sc = H.Scripts
    end)

    -- The clock at `t` s after a read of `r0`: counts down, wraps back to SPEED at 0.
    local function clock(r0, t)
        if t < r0 then
            return r0 - t
        end
        return SPEED - ((t - r0) % SPEED)
    end

    -- The compiled recheck times of `cond`, read with the clocks at `env`'s values; positive ones, ascending.
    local function times(cond, env)
        local rs = assert(Sc:BuildRecheck(cond), cond)
        env.safenum = function(x)
            return type(x) == "number" and x or 0
        end
        local out = { setfenv(assert(loadstring("return " .. rs)), env)() }
        local pos = {}
        for _, x in ipairs(out) do
            if x > 0 then
                pos[#pos + 1] = x
            end
        end
        table.sort(pos)
        return pos
    end

    local function near(want, got)
        assert.is_true(got ~= nil and math.abs(want - got) < 1e-9, tostring(got))
    end

    it("finds a near-swing guard's window end when the ready time falls in the pre-swing half", function()
        local function guard(r)
            return r <= SPEED - 0.1 and r >= 0.1
        end
        for _, r0 in ipairs({ 0.05, 0.09, 0.01 }) do
            assert.is_false(guard(r0)) -- ready inside the guard's pre-swing half
            local first
            for _, t in
                ipairs(times("mainhand_remains<=mainhand_speed-0.1&mainhand_remains>=0.1", {
                    mainhand_remains = r0,
                    mainhand_speed = SPEED,
                }))
            do
                if guard(clock(r0, t)) then
                    first = t
                    break
                end
            end
            -- the swing (r0), the guard's since-swing half (0.1), the wrap's 0.01 margin
            near(r0 + 0.1 + 0.01, first)
        end
    end)

    it(
        "finds the window end from the since-swing half too (the threshold's own expression, not its first term)",
        function()
            local function guard(r)
                return r <= SPEED - 0.1 and r >= 0.1
            end
            for _, r0 in ipairs({ SPEED - 0.05, SPEED - 0.01 }) do
                assert.is_false(guard(r0)) -- ready just after a swing
                local first
                for _, t in
                    ipairs(times("mainhand_remains<=mainhand_speed-0.1&mainhand_remains>=0.1", {
                        mainhand_remains = r0,
                        mainhand_speed = SPEED,
                    }))
                do
                    if guard(clock(r0, t)) then
                        first = t
                        break
                    end
                end
                near(r0 - (SPEED - 0.1) + 0.01, first)
            end
        end
    )

    it("derives the window end from the guard's own threshold, each hand's own period", function()
        -- a 0.3 s since-swing half on the ranged clock: holds again 0.3 s past its wrap
        local got = times("ranged_remains<ranged_speed-0.3", { ranged_remains = 0.2, ranged_speed = 2.5 })
        near(0.2 + 0.3 + 0.01, got[#got])
        got = times("offhand_remains<=offhand_speed-0.2", { offhand_remains = 0.4, offhand_speed = 1.8 })
        near(0.4 + 0.2 + 0.01, got[#got])
    end)

    it("retries every other swing-clock comparison exactly as before", function()
        local env = { ranged_remains = 1.2, ranged_speed = 2.9, mainhand_remains = 0.4, mainhand_speed = 2.6 }
        local function only(want, cond)
            local got = times(cond, env)
            assert.are.equal(1, #got, cond)
            near(want, got[1])
        end
        only(1.21, "ranged_remains>ranged_speed-0.1") -- `>`/`>=`: 0.01 past the wrap
        only(1.21, "ranged_remains>=ranged_speed-0.1")
        only(0.41, "mainhand_remains>mainhand_speed-0.2")
        only(0.41, "mainhand_remains>=0.1")
        only(0.41, "mainhand_remains>=mainhand_speed-(0+0.3)")
        only(0.41, "mainhand_remains>1.5")
        only(1.21, "ranged_remains>=max(0,0.2)")
        -- `<` before the wrap: its first time as before (0.7, plus the strict comparison's 0.01)
        near(0.71, times("ranged_remains<0.5", env)[1])
        -- two moving clocks (true now): no window end to derive, nothing to recheck
        assert.are.same({}, times("mainhand_remains<ranged_remains", env))
        -- the clock on the right: as before
        env.buff = { x = { remains = 5 } }
        only(4.61, "buff.x.remains<mainhand_remains")
    end)
    it("compiles the two-time recheck with no engine error (the Hunter packs' `clock<x` lines)", function()
        local errs = {}
        local orig = H.Error
        H.Error = function(_, msg)
            msg = tostring(msg)
            -- the bare harness also emits one-time "Unknown key" errors; only a compile failure counts
            if msg:find("Unable to compile", 1, true) then
                errs[#errs + 1] = msg
            end
        end
        local ok, rs = pcall(function()
            return {
                Sc:BuildRecheck("mainhand_remains<mainhand_speed-0.5"),
                Sc:BuildRecheck("ranged_remains<=0"),
            }
        end)
        H.Error = orig
        assert(ok, rs)
        assert.are.same({}, errs)
        for _, r in ipairs(rs) do
            assert.is_truthy(r:find(", ", 1, true), r) -- both times survive
        end
    end)
end)
