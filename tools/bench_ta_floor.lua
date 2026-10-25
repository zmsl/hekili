-- tools/bench_ta_floor.lua: make bench-ta's rows/s floor; it only moves up, except with a named cause.
-- Measured on the dev machine 2026-10-25, five runs back to back under the gate lock: 73919, 78306, 73195, 73718,
-- 75582 (median 73919; load avg ~9 of 16 cores from other lanes' test-fast). The old floor (97000) was never
-- reachable on the dev machine; re-based to its median.
return { rowsPerSec = 73000 }
