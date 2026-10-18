-- tests/Forever/helpers/arms_gate.lua: the headless Arms gates (headless loop design §5.2; as built: the plan's
-- Deviations 7-8, 14-15), shared by loop_warrior_spec.lua (fights 1-3, the 20 and the party report) and
-- loop_warrior_late_spec.lua (fights 4-6). Measured on the plan's replay:
-- 6 fights (`make check`, one run before the split): agreement 0.953, react median 0 / p90 1 / never 0.073, cost
-- refusals 17.1 per 100 (the oracle's 16.4), DPS A/B 0.999 (reported), never-reacts 0.073 (reported), CPU mean 2.95 ms.
-- The two halves' lines at the split: docs/dev/layout.md.
-- 20 fights (`make test-loop`): agreement 0.966, react median 0 / p90 0 / never 0.060, cost refusals 16.5 per 100
-- attempts (the oracle's own 15.8), DPS A/B 0.993, GCD idle 0.742 / 0.739, Sunder Armor up 0.95 / 0.95, flicker
-- 0.69/min, CPU mean 2.70 ms.
local pack_gate = require("Forever.helpers.pack_gate")
local ww = require("Forever.helpers.warrior_world")

local M = {}

-- Report-only: full-rage time (rage never reaches full in these fights) and Demoralizing Shout uptime (the Arms
-- priority keeps it off by default).
M.REPORTED = { demoralizing_shout = true }

-- The engine and the first icon, gated at any fight count (helpers/pack_gate.lua).
M.gate = pack_gate.gate

--- `n` fights on a fresh boot (seeds `seed0` + 1 ..), the `Arms solo:` line printed (`label` appended), gated.
--- DPS A/B (per fight its sd is about 0.11) and never-reacts are reported under 20 fights, not gated.
function M.solo(n, seed0, label)
    return pack_gate.solo("Arms", ww, n, seed0, label)
end

return M
