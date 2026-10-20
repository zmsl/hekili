-- tests/Forever/helpers/arms_gate.lua: the headless Arms gates (headless loop design §5.2; as built: the plan's
-- Deviations 7-8, 14-15), shared by loop_warrior_spec.lua (fights 1-3, the 20 and the party report) and
-- loop_warrior_late_spec.lua (fights 4-6). Arms (wowsims.com), re-measured after the swap (lane fix, trunk 824901c4):
-- seeds 1-3 agreement 0.973, never 0.018, cost refusals 17.0 per 100 (the oracle's 16.2), DPS A/B 0.982; seeds 4-6
-- 0.985, never 0.049, cost 16.1 (15.8), DPS A/B 0.998.
-- 20 fights (`make test-loop`): agreement 0.964, react median 0 / p90 0 / never 0.035, cost refusals 16.2 per 100
-- attempts (the oracle's own 15.1), DPS A/B 0.982, GCD idle 0.540 / 0.530, Sunder Armor up 0.95 / 0.95, flicker
-- 1.38/min (oracle 0.94), CPU mean 3.12 ms. The thresholds below were set on the retired hand-built list and hold.
-- The lines: docs/dev/layout.md.
local pack_gate = require("Forever.helpers.pack_gate")
local ww = require("Forever.helpers.warrior_world")

local M = {}

-- Report-only: full-rage time (rage never reaches full in these fights) and Demoralizing Shout uptime (Arms
-- (wowsims.com) never casts it).
M.REPORTED = { demoralizing_shout = true }

-- The engine and the first icon, gated at any fight count (helpers/pack_gate.lua).
M.gate = pack_gate.gate

--- `n` fights on a fresh boot (seeds `seed0` + 1 ..), the `Arms solo:` line printed (`label` appended), gated.
--- DPS A/B (per fight its sd is about 0.11) and never-reacts are reported under 20 fights, not gated.
function M.solo(n, seed0, label)
    return pack_gate.solo("Arms", ww, n, seed0, label)
end

return M
