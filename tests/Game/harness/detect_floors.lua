-- tests/Game/harness/detect_floors.lua: the detection suite's floors (unit-registry spec §6.2),
-- written by the first clean run (DETECT_WRITE=1). Floors only move up; a lower one needs a named cause.
-- 2026-10-23 (attribution-recovery spec decisions 46, 48-50): regenerated under the owner's ruling (recall over precision): recall up; false credit, leak, lostDiff and pet rows may rise.
-- 2026-10-23 (decisions 51-52, owner ruling: expiry EV): regenerated with the expectation at a swing's lost close; rageErr down.
-- Fix round 2 (avoidSeen): 9fd58600's floors were never merged; part of their drop rested on believed rage for swings avoided in truth (an error cancelling the under-count), which the avoidSeen fix removes.
-- Task 5 (attribution-recovery decisions 54-56): recovered (floor, a share) and wash (ceiling) first set by this run.
-- Parry-haste spec decision 63: the world models parry haste; its swing reschedule reorders every seeded fight, so every floor that failed in any seed set (1-20 / 21-40 / 41-60), or improved in all three, is re-set to the worst of the three. Twins-drift cells K14/K14p: one hand pulled.
-- stylua: ignore
return {
    K1 = {
        solo = { recall = 1.00, melee = 0.98, melee2 = 0.98, rageErr = 15.6, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 1.8 },
        party = { recall = 1.00, melee = 0.81, melee2 = 0.96, rageErr = 17.4, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 1.4 },
        busy = { recall = 1.00, melee = 0.69, melee2 = 0.85, rageErr = 19.7, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 0.5 },
    },
    -- K10: melee recall does not hold under a session lag (spec §6.2's check; party 0.36, busy 0.18 against K1's 0.83 / 0.70). The session's landing median from [0.4, 1.0] s drives it (without it 0.86 / 0.73); the first-swing lag costs party 0.06; jitter, pushback and PLAYER_ENTER_COMBAT cost nothing. Measured, not a target (Task 13 finding; the melee scoring is probe U15's).
    K10 = {
        solo = { recall = 0.95, melee = 0.96, melee2 = 0.96, rageErr = 15.1, staged = 0.88, false100 = 4.5, leak100 = 1.6, lostDiff = 3, residual = 0, postClear = 1.00, recovered = 0.00, wash = 2.7 },
        party = { recall = 0.92, melee = 0.38, melee2 = 0.95, rageErr = 24.2, staged = 0.86, false100 = 7.7, leak100 = 1.4, lostDiff = 1, residual = 0, postClear = 1.00, recovered = 0.13, wash = 1.8 },
        busy = { recall = 0.69, melee = 0.17, melee2 = 0.84, rageErr = 29.5, staged = 0.72, false100 = 29.4, leak100 = 2.1, lostDiff = 5, residual = 0, postClear = 1.00, recovered = 0.16, wash = 0.0 },
    },
    K11 = {
        party = { recall = 0.89, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.86, false100 = 11.2, leak100 = 4.7, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.66, wash = 0.0 },
        busy = { recall = 0.36, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.50, false100 = 71.5, leak100 = 5.1, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.36, wash = 0.0 },
    },
    -- K11m: post-clear rows paid by their swing are a floor, not every row: busy 6 of 7 (a 0.769 s tail lag scores below theta, K6's mechanism).
    K11m = {
        party = { recall = 0.88, melee = 0.86, melee2 = 0.98, rageErr = 6.1, staged = 0.80, false100 = 12.0, leak100 = 2.7, lostDiff = 1, residual = 0, postClear = 0.88, recovered = 0.41, wash = 0.0 },
        busy = { recall = 0.75, melee = 0.80, melee2 = 0.76, rageErr = 2.9, staged = 0.33, false100 = 27.6, leak100 = 2.1, lostDiff = 0, residual = 0, postClear = 0.90, recovered = 0.07, wash = 0.0 },
    },
    K12 = {
        solo = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        busy = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
    },
    -- K13: phase 0 solo's 17.8 divergent pairs per 100 own is the synthetic worst case (a twin in our very ms on every press), not an in-game rate; spec §4's union-belief trigger (> 1 per 100 paid) needs an in-game rate: probe U16, a party capture with a same-school caster on our target. Party and busy are floors (crowd cost dominates the per-pair cost).
    K13 = {
        solo = { recall = 0.82, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.49, false100 = 17.8, leak100 = 26.5, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.47, wash = 0.0 },
        party = { recall = 0.83, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.53, false100 = 16.9, leak100 = 6.3, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.41, wash = 0.0 },
        busy = { recall = 0.64, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.42, false100 = 35.1, leak100 = 4.3, lostDiff = 4, residual = 0, postClear = 1.00, recovered = 0.53, wash = 0.0 },
    },
    K13p1 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.95, false100 = 2.6, leak100 = 0.9, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.46, wash = 0.0 },
        busy = { recall = 0.72, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.71, false100 = 26.5, leak100 = 3.1, lostDiff = 4, residual = 0, postClear = 1.00, recovered = 0.52, wash = 0.0 },
    },
    K13p5 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 0.98, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.96, false100 = 1.8, leak100 = 0.6, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.50, wash = 0.0 },
        busy = { recall = 0.75, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.74, false100 = 23.7, leak100 = 2.8, lostDiff = 9, residual = 0, postClear = 1.00, recovered = 0.67, wash = 0.0 },
    },
    K14 = {
        solo = { recall = 1.00, melee = 0.95, melee2 = 0.96, rageErr = 20.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 1.8 },
        party = { recall = 1.00, melee = 0.93, melee2 = 0.93, rageErr = 19.1, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 1.8 },
        busy = { recall = 1.00, melee = 0.81, melee2 = 0.87, rageErr = 22.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 1.8 },
    },
    K14f = {
        solo = { recall = 1.00, melee = 0.64, melee2 = 0.70, rageErr = 33.9, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 42.8 },
        party = { recall = 1.00, melee = 0.40, melee2 = 0.69, rageErr = 41.8, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 39.2 },
        busy = { recall = 1.00, melee = 0.18, melee2 = 0.63, rageErr = 48.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 60.3 },
    },
    -- K14p: owner finding. The spec has our pet's rows stay foreign; our swing tickets take 8.8 / 6.6 / 3.2 per 100 of them (solo / party / busy) through the melee scoring, which cannot tell a pet's white hit on our target from ours (probe U15's family). Floored by the first clean run, not a target.
    K14p = {
        solo = { recall = 1.00, melee = 0.86, melee2 = 0.92, rageErr = 19.9, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 1.8 },
        party = { recall = 1.00, melee = 0.86, melee2 = 0.91, rageErr = 20.3, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 1.4 },
        busy = { recall = 1.00, melee = 0.79, melee2 = 0.87, rageErr = 21.8, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 1.8 },
    },
    K15 = {
        solo = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 0.96, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.95, false100 = 0.9, leak100 = 0.6, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 0.0 },
        busy = { recall = 0.93, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.93, false100 = 3.8, leak100 = 0.6, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.40, wash = 0.0 },
    },
    K17 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 0.96, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.89, false100 = 4.0, leak100 = 2.2, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.66, wash = 0.0 },
        busy = { recall = 0.76, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.80, false100 = 22.5, leak100 = 3.1, lostDiff = 3, residual = 0, postClear = 1.00, recovered = 0.50, wash = 0.0 },
    },
    K18 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        busy = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
    },
    K19 = {
        solo = { recall = 0.97, melee = 0.98, melee2 = 0.97, rageErr = 34.7, staged = 0.96, false100 = 0.7, leak100 = 0.1, lostDiff = 5, residual = 0, postClear = 1.00, recovered = 0.83, wash = 0.0 },
        party = { recall = 0.97, melee = 0.80, melee2 = 0.94, rageErr = 34.4, staged = 0.96, false100 = 0.5, leak100 = 0.1, lostDiff = 5, residual = 0, postClear = 1.00, recovered = 0.08, wash = 1.4 },
        busy = { recall = 0.97, melee = 0.70, melee2 = 0.84, rageErr = 35.4, staged = 0.98, false100 = 0.5, leak100 = 0.1, lostDiff = 2, residual = 0, postClear = 1.00, recovered = 0.00, wash = 0.0 },
    },
    K2 = {
        solo = { recall = 0.99, melee = 0.98, melee2 = 0.97, rageErr = 35.2, staged = 0.90, false100 = 1.0, leak100 = 0.2, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.50, wash = 1.4 },
        party = { recall = 0.99, melee = 0.81, melee2 = 0.96, rageErr = 35.5, staged = 0.96, false100 = 0.5, leak100 = 0.1, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 0.5 },
        busy = { recall = 0.99, melee = 0.71, melee2 = 0.84, rageErr = 36.3, staged = 0.96, false100 = 0.5, leak100 = 0.1, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 0.5 },
    },
    K21 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.96, false100 = 2.9, leak100 = 1.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.33, wash = 0.0 },
        busy = { recall = 0.71, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.73, false100 = 28.2, leak100 = 2.5, lostDiff = 1, residual = 0, postClear = 1.00, recovered = 0.62, wash = 0.0 },
    },
    K3 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        busy = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
    },
    K4 = {
        solo = { recall = 0.98, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.98, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 0.96, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.95, false100 = 2.5, leak100 = 1.3, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.57, wash = 0.0 },
        busy = { recall = 0.76, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.75, false100 = 22.3, leak100 = 3.0, lostDiff = 4, residual = 0, postClear = 1.00, recovered = 0.46, wash = 0.0 },
    },
    K5 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 0.98, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.96, false100 = 1.6, leak100 = 0.8, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 0.0 },
        busy = { recall = 0.84, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.88, false100 = 11.7, leak100 = 1.6, lostDiff = 23, residual = 0, postClear = 1.00, recovered = 0.50, wash = 0.0 },
    },
    K6 = {
        solo = { recall = 0.96, melee = 1.00, melee2 = 0.98, rageErr = 7.1, staged = 0.92, false100 = 3.1, leak100 = 1.4, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 0.0 },
        party = { recall = 0.92, melee = 0.87, melee2 = 0.90, rageErr = 3.4, staged = 0.83, false100 = 17.4, leak100 = 3.3, lostDiff = 0, residual = 0, postClear = 0.90, recovered = 0.00, wash = 0.0 },
        busy = { recall = 0.66, melee = 0.70, melee2 = 0.81, rageErr = 2.2, staged = 1.00, false100 = 66.7, leak100 = 1.5, lostDiff = 0, residual = 0, postClear = 0.84, recovered = 0.00, wash = 0.0 },
    },
    K7 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 1.00, wash = 0.0 },
        party = { recall = 0.98, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.96, false100 = 1.9, leak100 = 1.0, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.00, wash = 0.0 },
        busy = { recall = 0.81, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.79, false100 = 18.1, leak100 = 2.5, lostDiff = 4, residual = 0, postClear = 1.00, recovered = 0.55, wash = 0.0 },
    },
    K8 = {
        solo = { recall = 0.72, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.68, false100 = 27.1, leak100 = 20.8, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.92, wash = 0.0 },
        party = { recall = 0.66, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.62, false100 = 33.8, leak100 = 10.2, lostDiff = 0, residual = 0, postClear = 1.00, recovered = 0.92, wash = 0.0 },
        busy = { recall = 0.47, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.42, false100 = 52.9, leak100 = 6.1, lostDiff = 1, residual = 0, postClear = 1.00, recovered = 0.79, wash = 0.0 },
    },
    K9 = {
        solo = { recall = 0.99, melee = 0.97, melee2 = 0.98, rageErr = 16.1, staged = 0.97, false100 = 0.0, leak100 = 0.0, lostDiff = 3, residual = 0, postClear = 1.00, recovered = 1.00, wash = 1.4 },
        party = { recall = 0.99, melee = 0.82, melee2 = 0.96, rageErr = 17.3, staged = 0.96, false100 = 0.0, leak100 = 0.0, lostDiff = 4, residual = 0, postClear = 1.00, recovered = 0.00, wash = 0.5 },
        busy = { recall = 0.99, melee = 0.71, melee2 = 0.84, rageErr = 19.8, staged = 0.97, false100 = 0.2, leak100 = 0.1, lostDiff = 2, residual = 0, postClear = 1.00, recovered = 0.00, wash = 0.0 },
    },
}
