-- tests/Game/harness/detect_floors.lua: the detection suite's floors (unit-registry spec §6.2),
-- written by the first clean run (DETECT_WRITE=1). Floors only move up; a lower one needs a named cause.
-- stylua: ignore
return {
    K1 = {
        solo = { recall = 1.00, melee = 0.98, melee2 = 0.97, rageErr = 15.8, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 0.83, melee2 = 0.97, rageErr = 19.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 0.70, melee2 = 0.85, rageErr = 22.9, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    -- K10: melee recall does not hold under a session lag (spec §6.2's check; party 0.36, busy 0.18 against K1's 0.83 / 0.70). The session's landing median from [0.4, 1.0] s drives it (without it 0.86 / 0.73); the first-swing lag costs party 0.06; jitter, pushback and PLAYER_ENTER_COMBAT cost nothing. Measured, not a target (Task 13 finding; the melee scoring is probe U15's).
    K10 = {
        solo = { recall = 0.85, melee = 0.97, melee2 = 0.97, rageErr = 15.7, staged = 0.73, false100 = 10.7, leak100 = 3.7, lostDiff = 15, residual = 0, postClear = 1.00 },
        party = { recall = 0.55, melee = 0.35, melee2 = 0.96, rageErr = 31.6, staged = 0.53, false100 = 40.0, leak100 = 6.3, lostDiff = 32, residual = 0, postClear = 1.00 },
        busy = { recall = 0.15, melee = 0.17, melee2 = 0.81, rageErr = 36.4, staged = 0.07, false100 = 81.8, leak100 = 5.0, lostDiff = 51, residual = 1, postClear = 1.00 },
    },
    K11 = {
        party = { recall = 0.80, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.80, false100 = 15.1, leak100 = 6.0, lostDiff = 7, residual = 0, postClear = 1.00 },
        busy = { recall = 0.37, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.60, false100 = 65.6, leak100 = 4.9, lostDiff = 1, residual = 0, postClear = 1.00 },
    },
    K11m = {
        party = { recall = 0.79, melee = 0.85, melee2 = 1.00, rageErr = 5.9, staged = 0.60, false100 = 20.3, leak100 = 4.5, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.74, melee = 0.80, melee2 = 0.87, rageErr = 2.5, staged = 0.66, false100 = 31.1, leak100 = 2.3, lostDiff = 0, residual = 0, postClear = 0.85 },
    },
    K12 = {
        solo = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K13 = {
        solo = { recall = 0.82, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.50, false100 = 17.8, leak100 = 26.5, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.70, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.51, false100 = 27.9, leak100 = 10.0, lostDiff = 17, residual = 0, postClear = 1.00 },
        busy = { recall = 0.23, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.16, false100 = 72.6, leak100 = 7.4, lostDiff = 84, residual = 0, postClear = 1.00 },
    },
    K13p1 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.76, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.75, false100 = 21.1, leak100 = 6.8, lostDiff = 20, residual = 0, postClear = 1.00 },
        busy = { recall = 0.24, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.21, false100 = 72.2, leak100 = 7.6, lostDiff = 65, residual = 0, postClear = 1.00 },
    },
    K13p5 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.80, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.74, false100 = 17.6, leak100 = 5.7, lostDiff = 15, residual = 0, postClear = 1.00 },
        busy = { recall = 0.24, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.23, false100 = 72.5, leak100 = 7.7, lostDiff = 57, residual = 0, postClear = 1.00 },
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
    K14p = {
        solo = { recall = 1.00, melee = 0.89, melee2 = 0.89, rageErr = 19.7, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 0.87, melee2 = 0.86, rageErr = 21.7, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 0.84, melee2 = 0.84, rageErr = 22.2, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K15 = {
        solo = { recall = 0.97, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.93, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.94, false100 = 3.9, leak100 = 2.3, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.86, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.74, false100 = 11.1, leak100 = 1.7, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K17 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.77, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.86, false100 = 18.9, leak100 = 9.3, lostDiff = 9, residual = 0, postClear = 1.00 },
        busy = { recall = 0.38, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.45, false100 = 54.8, leak100 = 6.4, lostDiff = 26, residual = 0, postClear = 1.00 },
    },
    K18 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K19 = {
        solo = { recall = 0.97, melee = 0.98, melee2 = 0.97, rageErr = 32.5, staged = 0.98, false100 = 0.2, leak100 = 0.0, lostDiff = 1, residual = 0, postClear = 1.00 },
        party = { recall = 0.97, melee = 0.82, melee2 = 0.95, rageErr = 34.8, staged = 0.98, false100 = 0.3, leak100 = 0.1, lostDiff = 1, residual = 0, postClear = 1.00 },
        busy = { recall = 0.97, melee = 0.76, melee2 = 0.86, rageErr = 33.7, staged = 0.96, false100 = 0.6, leak100 = 0.1, lostDiff = 3, residual = 0, postClear = 1.00 },
    },
    K2 = {
        solo = { recall = 1.00, melee = 0.98, melee2 = 0.97, rageErr = 34.3, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.99, melee = 0.83, melee2 = 0.96, rageErr = 35.1, staged = 0.96, false100 = 0.6, leak100 = 0.1, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.99, melee = 0.73, melee2 = 0.83, rageErr = 34.9, staged = 0.93, false100 = 1.0, leak100 = 0.1, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K21 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.62, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.50, false100 = 32.4, leak100 = 9.8, lostDiff = 31, residual = 0, postClear = 1.00 },
        busy = { recall = 0.21, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.19, false100 = 74.9, leak100 = 5.6, lostDiff = 58, residual = 0, postClear = 1.00 },
    },
    K3 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K4 = {
        solo = { recall = 0.98, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.77, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.77, false100 = 19.8, leak100 = 9.7, lostDiff = 19, residual = 0, postClear = 1.00 },
        busy = { recall = 0.40, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.41, false100 = 54.9, leak100 = 6.6, lostDiff = 58, residual = 0, postClear = 1.00 },
    },
    K5 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.82, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.83, false100 = 16.7, leak100 = 8.4, lostDiff = 8, residual = 0, postClear = 1.00 },
        busy = { recall = 0.50, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.48, false100 = 45.0, leak100 = 5.6, lostDiff = 48, residual = 0, postClear = 1.00 },
    },
    K6 = {
        solo = { recall = 0.96, melee = 1.00, melee2 = 0.98, rageErr = 6.0, staged = 1.00, false100 = 3.2, leak100 = 1.4, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.77, melee = 0.88, melee2 = 0.97, rageErr = 3.6, staged = 0.57, false100 = 28.0, leak100 = 4.9, lostDiff = 1, residual = 0, postClear = 0.90 },
        busy = { recall = 0.75, melee = 0.66, melee2 = 0.75, rageErr = 2.3, staged = 1.00, false100 = 50.0, leak100 = 1.1, lostDiff = 0, residual = 0, postClear = 0.84 },
    },
    K7 = {
        solo = { recall = 1.00, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.73, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.77, false100 = 23.9, leak100 = 11.8, lostDiff = 18, residual = 0, postClear = 1.00 },
        busy = { recall = 0.26, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.25, false100 = 70.6, leak100 = 8.6, lostDiff = 51, residual = 0, postClear = 1.00 },
    },
    K8 = {
        solo = { recall = 0.21, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.17, false100 = 73.6, leak100 = 45.4, lostDiff = 96, residual = 0, postClear = 1.00 },
        party = { recall = 0.15, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.15, false100 = 82.1, leak100 = 20.5, lostDiff = 93, residual = 0, postClear = 1.00 },
        busy = { recall = 0.08, melee = 1.00, melee2 = 1.00, rageErr = 0.0, staged = 0.09, false100 = 90.4, leak100 = 8.8, lostDiff = 81, residual = 0, postClear = 1.00 },
    },
    K9 = {
        solo = { recall = 0.99, melee = 0.98, melee2 = 0.98, rageErr = 15.8, staged = 0.96, false100 = 0.0, leak100 = 0.0, lostDiff = 4, residual = 0, postClear = 1.00 },
        party = { recall = 0.99, melee = 0.83, melee2 = 0.97, rageErr = 18.8, staged = 0.97, false100 = 0.0, leak100 = 0.0, lostDiff = 2, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 0.73, melee2 = 0.89, rageErr = 19.7, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
}
