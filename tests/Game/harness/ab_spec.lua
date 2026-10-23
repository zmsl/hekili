-- tests/Game/harness/ab_spec.lua (providers spec §4): the A/B arm and the measured shapes.
local ab = require("Game.harness.ab")
local scenarios = require("Game.harness.scenarios")

describe("the A/B harness", function()
    it("the default arm asserts, a provider arm records", function()
        assert.has_error(function()
            ab.check(false, "x", "line", "default")
        end)
        assert.has_no.errors(function()
            ab.check(false, "x", "line", "meter")
        end)
    end)

    local function count(s, ev)
        local n = 0
        for i = 1, s.n do
            n = n + (s.ev[i] == ev and 1 or 0)
        end
        return n
    end

    it("meter shapes only add events: the rest of the stream is today's", function()
        local o = { duration = 30 }
        local base = scenarios.stream(o, 7)
        o.meter = true
        local with = scenarios.stream(o, 7)
        assert.is_true(count(with, "DAMAGE_METER_COMBAT_SESSION_UPDATED") > 0)
        local j = 0
        for i = 1, with.n do
            if with.ev[i] ~= "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
                j = j + 1
                assert.are.same({ base.t[j], base.ev[j], base.a1[j] }, { with.t[i], with.ev[i], with.a1[i] })
            end
        end
        assert.are.equal(base.n, j)
    end)

    it("a hit swing of ours groups 0-11 ms after PLAYER_SWING; an avoid never", function()
        local s, W = scenarios.stream({ duration = 60, meter = true }, 11)
        for _, ev in ipairs(W.truth) do
            if ev.kind == "swing" and ev.ours then
                local got = false
                for i = 1, s.n do
                    if s.ev[i] == "DAMAGE_METER_COMBAT_SESSION_UPDATED" and s.a1[i] == 0 then
                        local d = s.t[i] - ev.t
                        got = got or (d >= 0 and d <= 0.011 + 1e-9) -- float: t + 11 / 1000 - t can exceed 0.011
                    end
                end
                assert.are.equal(ev.act == "WOUND", got)
            end
        end
    end)
end)
