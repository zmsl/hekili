-- tools/bench_ta_floor.lua: make bench-ta's rows/s floor; it only moves up, except with a named cause.
-- Measured on the dev machine 2026-10-25, quiet (load avg ~1.4 of 16 cores), six runs back to back under the gate lock:
-- 79932, 81470, 80989, 81303, 79500, 82220 (median ~81100). The old floor (97000) was never reachable on the dev
-- machine; re-based to its quiet median. (An earlier set under load from other lanes measured 73195-78306.)
return { rowsPerSec = 81000 }
