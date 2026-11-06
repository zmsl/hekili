-- tests/Forever/druid_harness_spec.lua (GCD kinds design §4, D9): the Druid in the combat harness, through the real
-- VirtualState and Rows.lua, its content from tests/Forever/helpers/druid_world.lua: solo bear (the rage model), solo
-- cat (energy secret, combo points plain), the shift fight (the stale caches, GCD kinds across shifts, resources on
-- entry), the Furor variants and Enrage's decay pause. The gates in make check (#slow) run a tenth of the design's
-- fights; the design's counts run behind make test-druid (#druid, druid_harness_gates_a_spec.lua and _b_spec.lua).
-- The gates: helpers/druid_harness_gates.lua. Each gate prints its tally line, which is also its failure message.
local dw = require("Forever.helpers.druid_world")
local GATES = require("Forever.helpers.druid_harness_gates").GATES

describe("the shift fight's usability answers", function()
    it("answers the Cat spenders short in Cat after a Bear section (seed 1: the 61.05 Cat entry)", function()
        dw.fights("shift", 1, {}, function(f)
            local W, s, R = f.W, f.s, f.R
            local spenders = {}
            for _, key in ipairs({ "claw", "shred", "rake", "rip", "ferocious_bite", "shifting_power" }) do
                spenders[dw.press(key, R).spell] = true
            end
            local entry, leave -- the second Cat entry and the next shift
            for _, ev in ipairs(W.truth) do
                if ev.kind == "form" and ev.form == dw.CAT and ev.t > 31 and not entry then
                    entry = ev.t
                elseif ev.kind == "form" and entry and not leave then
                    leave = ev.t
                end
            end
            assert.is_true(math.abs(entry - 61.05) < 1e-6, tostring(entry))
            local short = 0
            for i = 1, s.n do
                if s.ev[i] == "@usable" and spenders[s.a1[i]] and s.a2[i] == 2 then
                    short = short + ((s.t[i] >= entry and s.t[i] < leave) and 1 or 0)
                end
            end
            assert.is_true(short > 0)
        end)
    end)
end)

describe("Druid harness scenarios, a tenth of the fights (GCD kinds design §4.6) #slow", function()
    for _, name in ipairs({ "bear", "cat", "regenAfter", "reload", "shift", "furor", "decay" }) do
        it(name, function()
            GATES[name](0.1)
        end)
    end
end)
