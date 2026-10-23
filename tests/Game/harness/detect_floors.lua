-- tests/Game/harness/detect_floors.lua: the detection suite's floors (unit-registry spec §6.2),
-- written by the first clean run (DETECT_WRITE=1). Floors only move up; a lower one needs a named cause.
-- 2026-10-23 (attribution-recovery spec decision 46): regenerated under the owner's ruling (recall over precision): recall up; false credit, leak, lostDiff and pet rows may rise.
-- stylua: ignore
return {
    K1 = {
        solo = { recall = 1.00, melee = 0.98, melee2 = 0.97, rageErr = 15.8, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 0.83, melee2 = 0.97, rageErr = 19.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 0.70, melee2 = 0.85, rageErr = 22.9, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    -- K10: melee recall does not hold under a session lag (spec §6.2's check; party 0.36, busy 0.18 against K1's 0.83 / 0.70). The session's landing median from [0.4, 1.0] s drives it (without it 0.86 / 0.73); the first-swing lag costs party 0.06; jitter, pushback and PLAYER_ENTER_COMBAT cost nothing. Measured, not a target (Task 13 finding; the melee scoring is probe U15's).
    K10 = {
        solo = { recall = 0.88, melee = 0.97, melee2 = 0.97, rageErr = 15.7, staged = 0.78, false100 = 10.7, leak100 = 3.8, lostDiff = 5, residual = 0, postClear = 1.00 },
        party = { recall = 0.64, melee = 0.35, melee2 = 0.96, rageErr = 31.6, staged = 0.61, false100 = 35.7, leak100 = 6.1, lostDiff = 1, residual = 0, postClear = 1.00 },
        busy = { recall = 0.25, melee = 0.17, melee2 = 0.81, rageErr = 36.4, staged = 0.11, false100 = 73.8, leak100 = 5.2, lostDiff = 7, residual = 1, postClear = 1.00 },
    },
    K11 = {
        party = { recall = 0.85, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.84, false100 = 14.3, leak100 = 6.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.44, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.60, false100 = 61.3, leak100 = 4.9, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    -- K11m: post-clear rows paid by their swing are a floor, not every row: busy 6 of 7 (a 0.769 s tail lag scores below theta, K6's mechanism).
    K11m = {
        party = { recall = 0.79, melee = 0.85, melee2 = 1.00, rageErr = 5.9, staged = 0.60, false100 = 20.3, leak100 = 4.5, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.74, melee = 0.80, melee2 = 0.87, rageErr = 2.5, staged = 0.66, false100 = 31.1, leak100 = 2.3, lostDiff = 0, residual = 0, postClear = 0.85 },
    },
    K12 = {
        solo = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    -- K13: phase 0 solo's 17.8 divergent pairs per 100 own is the synthetic worst case (a twin in our very ms on every press), not an in-game rate; spec §4's union-belief trigger (> 1 per 100 paid) needs an in-game rate: probe U16, a party capture with a same-school caster on our target. Party and busy are floors (crowd cost dominates the per-pair cost).
    K13 = {
        solo = { recall = 0.82, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.50, false100 = 17.8, leak100 = 26.5, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.72, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.53, false100 = 27.5, leak100 = 10.2, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.29, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.22, false100 = 69.9, leak100 = 8.3, lostDiff = 6, residual = 0, postClear = 1.00 },
    },
    K13p1 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.79, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.80, false100 = 20.4, leak100 = 6.8, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.30, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.26, false100 = 69.2, leak100 = 8.2, lostDiff = 3, residual = 0, postClear = 1.00 },
    },
    K13p5 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.82, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.75, false100 = 17.1, leak100 = 5.7, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.29, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.28, false100 = 70.3, leak100 = 8.3, lostDiff = 5, residual = 0, postClear = 1.00 },
    },
    K14 = {
        solo = { recall = 1.00, melee = 0.98, melee2 = 0.96, rageErr = 19.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 0.95, melee2 = 0.93, rageErr = 19.7, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 0.84, melee2 = 0.84, rageErr = 22.7, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K14f = {
        solo = { recall = 1.00, melee = 0.67, melee2 = 0.73, rageErr = 36.8, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 0.30, melee2 = 0.68, rageErr = 52.5, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 0.17, melee2 = 0.66, rageErr = 58.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    -- K14p: owner finding. The spec has our pet's rows stay foreign; our swing tickets take 8.8 / 6.6 / 3.2 per 100 of them (solo / party / busy) through the melee scoring, which cannot tell a pet's white hit on our target from ours (probe U15's family). Floored by the first clean run, not a target.
    K14p = {
        solo = { recall = 1.00, melee = 0.89, melee2 = 0.89, rageErr = 19.7, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 0.87, melee2 = 0.86, rageErr = 21.7, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 0.84, melee2 = 0.84, rageErr = 22.2, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K15 = {
        solo = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.93, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.94, false100 = 3.8, leak100 = 2.2, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.86, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.74, false100 = 11.0, leak100 = 1.7, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K17 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.83, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.91, false100 = 17.0, leak100 = 8.9, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.48, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.59, false100 = 51.3, leak100 = 7.0, lostDiff = 3, residual = 0, postClear = 1.00 },
    },
    K18 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K19 = {
        solo = { recall = 0.97, melee = 0.98, melee2 = 0.97, rageErr = 32.5, staged = 0.98, false100 = 0.2, leak100 = 0.0, lostDiff = 1, residual = 0, postClear = 1.00 },
        party = { recall = 0.97, melee = 0.82, melee2 = 0.95, rageErr = 34.8, staged = 0.98, false100 = 0.3, leak100 = 0.1, lostDiff = 1, residual = 0, postClear = 1.00 },
        busy = { recall = 0.97, melee = 0.76, melee2 = 0.86, rageErr = 33.7, staged = 0.96, false100 = 0.5, leak100 = 0.0, lostDiff = 3, residual = 0, postClear = 1.00 },
    },
    K2 = {
        solo = { recall = 1.00, melee = 0.98, melee2 = 0.97, rageErr = 34.3, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.99, melee = 0.83, melee2 = 0.96, rageErr = 35.1, staged = 0.96, false100 = 0.5, leak100 = 0.1, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.99, melee = 0.73, melee2 = 0.83, rageErr = 34.9, staged = 0.93, false100 = 1.0, leak100 = 0.1, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K21 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.70, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.64, false100 = 29.3, leak100 = 9.6, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.33, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.30, false100 = 66.1, leak100 = 5.9, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K3 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K4 = {
        solo = { recall = 0.98, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.80, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.79, false100 = 19.1, leak100 = 9.7, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.46, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.43, false100 = 53.1, leak100 = 7.1, lostDiff = 4, residual = 0, postClear = 1.00 },
    },
    K5 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.84, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.84, false100 = 15.7, leak100 = 8.1, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.54, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.50, false100 = 44.5, leak100 = 5.9, lostDiff = 9, residual = 0, postClear = 1.00 },
    },
    K6 = {
        solo = { recall = 0.96, melee = 1.00, melee2 = 0.98, rageErr = 6.0, staged = 1.00, false100 = 3.2, leak100 = 1.4, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.80, melee = 0.88, melee2 = 0.97, rageErr = 3.6, staged = 0.57, false100 = 27.3, leak100 = 4.9, lostDiff = 0, residual = 0, postClear = 0.90 },
        busy = { recall = 0.75, melee = 0.66, melee2 = 0.75, rageErr = 2.3, staged = 1.00, false100 = 50.0, leak100 = 1.1, lostDiff = 0, residual = 0, postClear = 0.84 },
    },
    K7 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.77, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.78, false100 = 22.6, leak100 = 11.6, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.31, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.26, false100 = 67.9, leak100 = 9.1, lostDiff = 7, residual = 0, postClear = 1.00 },
    },
    K8 = {
        solo = { recall = 0.39, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.38, false100 = 60.7, leak100 = 46.5, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.29, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.29, false100 = 70.7, leak100 = 21.3, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.17, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.18, false100 = 82.8, leak100 = 9.4, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K9 = {
        solo = { recall = 0.99, melee = 0.98, melee2 = 0.98, rageErr = 15.8, staged = 0.96, false100 = 0.0, leak100 = 0.0, lostDiff = 4, residual = 0, postClear = 1.00 },
        party = { recall = 0.99, melee = 0.83, melee2 = 0.97, rageErr = 18.8, staged = 0.97, false100 = 0.0, leak100 = 0.0, lostDiff = 2, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 0.73, melee2 = 0.89, rageErr = 19.7, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
}
