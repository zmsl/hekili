-- tests/Game/harness/detect_floors.lua: the detection suite's floors (unit-registry spec §6.2),
-- written by the first clean run (DETECT_WRITE=1). Floors only move up; a lower one needs a named cause.
-- stylua: ignore
return {
    K1 = {
        solo = { recall = 1.00, melee = 0.98, melee2 = 0.97, rageErr = -15.7, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 1.00, melee = 0.83, melee2 = 0.97, rageErr = -18.9, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 0.70, melee2 = 0.85, rageErr = -22.8, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
    K2 = {
        solo = { recall = 1.00, melee = 0.98, melee2 = 0.97, rageErr = -34.2, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.99, melee = 0.83, melee2 = 0.96, rageErr = -35.0, staged = 0.96, false100 = 0.6, leak100 = 0.1, lostDiff = 0, residual = 0, postClear = 1.00 },
        busy = { recall = 0.99, melee = 0.73, melee2 = 0.83, rageErr = -34.8, staged = 0.93, false100 = 1.0, leak100 = 0.1, lostDiff = 0, residual = 0, postClear = 1.00 },
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
        solo = { recall = 0.98, melee = 1.00, melee2 = 0.98, rageErr = -6.0, staged = 1.00, false100 = 1.1, leak100 = 0.5, lostDiff = 0, residual = 0, postClear = 1.00 },
        party = { recall = 0.77, melee = 0.88, melee2 = 0.97, rageErr = -3.5, staged = 0.57, false100 = 28.0, leak100 = 4.9, lostDiff = 1, residual = 0, postClear = 0.90 },
        busy = { recall = 0.75, melee = 0.66, melee2 = 0.75, rageErr = -2.2, staged = 1.00, false100 = 50.0, leak100 = 1.1, lostDiff = 0, residual = 0, postClear = 0.84 },
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
        solo = { recall = 0.99, melee = 0.98, melee2 = 0.98, rageErr = -15.7, staged = 0.95, false100 = 0.0, leak100 = 0.0, lostDiff = 5, residual = 0, postClear = 1.00 },
        party = { recall = 0.99, melee = 0.83, melee2 = 0.97, rageErr = -18.7, staged = 0.96, false100 = 0.0, leak100 = 0.0, lostDiff = 3, residual = 0, postClear = 1.00 },
        busy = { recall = 1.00, melee = 0.73, melee2 = 0.89, rageErr = -19.6, staged = 1.00, false100 = 0.0, leak100 = 0.0, lostDiff = 0, residual = 0, postClear = 1.00 },
    },
}
