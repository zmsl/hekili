-- tests/Game/harness/loop_spec.lua (class-completion plan, Task 1): the loop is class-neutral. A stub content of a
-- non-rage power (type 3, no pack) drives two fights, and its per-hit gains reach the observer as that power.
local loop = require("Game.harness.loop")

local PT, TOKEN = 3, "ENERGY"

describe("the headless loop, class-neutral", function()
    it(
        "drives two fights of a stub energy world: content.gain answers for its power, the observer reports it",
        function()
            local asked = {}
            local stub = {
                character = function()
                    return { level = 60, power = { type = PT, token = TOKEN, max = 100 } }
                end,
                resolve = function()
                    return {}
                end,
                usable = function()
                    return {}
                end,
                uptime = function()
                    return {}
                end,
                gain = function(pt, hand)
                    asked[pt] = true
                    return hand == 1 and 5 or 0
                end,
                WORLD = { level = 60, max = 100, mobHealth = 1e9 },
            }
            local L = loop.new(stub)
            local seen = { fights = {}, power = 0, tokens = 0 }
            local m = loop.tally(L, 2, {
                duration = 12,
                on = function(run, steps)
                    seen.fights[run.W] = true
                    seen.pt, seen.truth = run.us.pt, run.us.power
                    local s = steps[#steps].obs.s -- the oracle's secret-free client
                    for i = 1, s.n do
                        if s.ev[i] == "@power" and s.a1[i] == PT then
                            seen.power = math.max(seen.power, s.a2[i])
                        elseif s.ev[i] == "UNIT_POWER_FREQUENT" and s.a2[i] == TOKEN then
                            seen.tokens = seen.tokens + 1
                        end
                    end
                end,
            })
            assert.are.equal(2, m.fights)
            local worlds = 0
            for _ in pairs(seen.fights) do
                worlds = worlds + 1
            end
            assert.are.equal(4, worlds) -- run A and run B of each fight
            assert.are.same({ [PT] = true }, asked)
            assert.are.equal(PT, seen.pt)
            assert.is_true(seen.truth > 0 and seen.power > 0 and seen.tokens > 0)
            assert.are.equal(0, m.focus) -- no pack, no flagged record
        end
    )
end)

describe("the headless loop's replay injection (o.replay)", function()
    local scenarios = require("Game.harness.scenarios")
    it("presses nothing, cycles at each decision and scores only the on-GCD ones", function()
        local stub = {
            character = function()
                return { level = 60, power = { type = 1, token = "RAGE", max = 100 } }
            end,
            resolve = function()
                error("no press in a replay")
            end,
            usable = function()
                return {}
            end,
            uptime = function()
                return {}
            end,
            gain = function()
                return 0
            end,
            WORLD = { level = 60, max = 100, mobHealth = 1e9 },
        }
        local L = loop.new(stub)
        local R = {
            pull = 3,
            duration = 6,
            decisions = {
                { t = 3.3, key = "a", gcd = true },
                { t = 3.5, key = "b", gcd = false },
                { t = 4.1, key = "c", gcd = true },
            },
        }
        function R.world(wo, seed)
            return scenarios.world(wo, seed)
        end
        function R.next(t)
            for _, d in ipairs(R.decisions) do
                if d.t > t then
                    return d.key
                end
            end
            return false
        end
        local m = loop.replay(L, R)
        assert.are.same({ 2, 0 }, { m.dec.both, m.dec.agree }) -- no pack: our on-GCD icon is false at both
        assert.are.equal(0, m.attempts)
        local r = loop.summary(m)
        assert.are.equal(0, r.decisions)
        assert.is_truthy(loop.line(m):find("; decisions on-GCD 0.000 (2)", 1, true))
        assert.is_nil(loop.summary(loop.tally(L, 1, { duration = 6 })).decisions) -- the normal tally: unchanged
    end)
end)
