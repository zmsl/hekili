-- tests/Game/harness/detect.lua (unit-registry spec §6.2): the detection suite's bands, kinds, runner and floors.
local scenarios = require("Game.harness.scenarios")
local drive = require("Game.harness.drive")
local metrics = require("Game.harness.metrics")
local fs = require("Game.State.helpers.fake_spec")
local ab = require("Game.harness.ab")

local M = {}

local function mix(n)
    local others = {}
    for i = 1, n do
        others[i] = ({ "melee", "melee", "caster", "pet", "ranged", "melee" })[i % 6 + 1] -- group_spec.lua's mix
    end
    return others
end

-- Other sources on our target (foreign outcomes per second as measured, spec §6.2). `group` (providers spec §4.2,
-- passed as the observer's knob): true where the others are our group members, whose hits tick the damage meter
-- (party, the raids); false where they are strangers, whose hits never tick it (busy: an open-world crowd). The DM
-- captures measured both: a party member's hits tick, a stranger's never (DM research §2).
M.BANDS = {
    solo = { others = {}, group = true },
    party = { others = { "melee", "caster" }, group = true },
    busy = { others = { "melee", "melee", "melee", "caster", "caster", "pet", "pet" }, group = false },
    raid12 = { others = mix(11), group = true },
    raid25 = { others = mix(24), group = true },
    raid40 = { others = mix(39), group = true },
}
M.GATED = { "solo", "party", "busy" }
M.MEASURED = { "raid12", "raid25", "raid40" }

-- Our presses: `kind` every `every` s from 2 s to `last`.
local function every(kind, step, last)
    local out = {}
    for t = 2, last, step do
        out[#out + 1] = { t, kind }
    end
    return out
end
local function strikes(step, last)
    local out = {}
    for t = 2, last, step do
        out[#out + 1] = { t, "STRIKE", 0, "queue" }
    end
    return out
end

local function with(base, extra) -- a kind's knobs over another's (M.run copies a kind with pairs)
    local o = {}
    for k, v in pairs(base) do
        o[k] = v
    end
    for k, v in pairs(extra) do
        o[k] = v
    end
    return o
end

-- Each kind's knobs (spec §6.2's table; K10-K19 in Task 13).
M.KINDS = {
    K1 = { duration = 60 },
    K2 = { duration = 60, presses = strikes(6, 58) },
    K3 = { duration = 60, noMelee = true, spells = every("instant", 2, 58) },
    K4 = { duration = 60, noMelee = true, spells = every("bolt", 2, 58), distances = { 5, 20, 30 } },
    K5 = {
        duration = 60,
        noMelee = true,
        spells = every("bolt", 2, 58),
        extraMobs = 1,
        switchTo = { { 10.8, 2 }, { 20.8, 1 }, { 30.8, 2 }, { 40.8, 1 } }, -- mid-cast: 0.8 s into a 1.5 s cast
    },
    K6 = { duration = 30, noMelee = false, spells = every("bolt", 2, 28), mobHealth = 400 },
    K7 = { duration = 60, noMelee = true, spells = every("bolt", 2, 58), churn = { 3, 0.5 } },
    K8 = { duration = 60, noMelee = true, spells = every("bolt", 2, 58), lockstep = 0.3 },
}
M.KINDS.K9 = { duration = 60, spells = every("instant", 2, 58), actionTargeting = true }
local function mixSpells(last)
    local out = {}
    for t = 2, last, 2 do
        out[#out + 1] = { t, ({ "instant", "bolt", "doti", "refused", "unmapped" })[(t / 2) % 5 + 1] }
    end
    return out
end
M.KINDS.K10 = {
    duration = 60,
    spells = every("bolt", 3, 57),
    sessionLag = true,
    firstLag = 1.0,
    enterCombat = true,
    jitter = 0.05,
    pushback = true,
}
-- K11 (death in flight, spec §6.2): a FOREIGN kill while our bolt flies; solo has no foreign source, so it is na there.
-- At 30 yd (no swings of ours) mobHealth 600 dies to the partners in 15-19 s (party) and 5-8 s (busy).
M.KINDS.K11 = {
    duration = 30,
    spells = every("bolt", 2, 28),
    mobHealth = 600,
    distances = { 30 },
    na = { solo = "no foreign source to kill the target" },
}
-- K11m: the melee case of K11, in reach and swinging: a partner kills while our swing is pending (its row after the
-- clear must pay its swing); bolts keep own > 0. Solo na as K11.
M.KINDS.K11m = with(M.KINDS.K11, { distances = { 5 } })
M.KINDS.K12 = {
    duration = 60,
    noMelee = true,
    extraMobs = 1,
    spells = every("doti", 4, 56),
    switchTo = { { 9, 2 }, { 17, 1 }, { 25, 2 }, { 33, 1 }, { 41, 2 }, { 49, 1 } },
}
-- K13 (spec §6.2): a partner anchored to our presses (the `twin` archetype: our cadence, its own outcome roll),
-- shifted 0 (K13), 0.1 (K13p1) and 0.5 s (K13p5)
M.KINDS.K13 = { duration = 60, noMelee = true, spells = every("bolt", 2, 58), twin = 0, distances = { 20 } }
M.KINDS.K13p1 = with(M.KINDS.K13, { twin = 0.1 })
M.KINDS.K13p5 = with(M.KINDS.K13, { twin = 0.5 })
M.KINDS.K14 = { duration = 60, twins = true }
-- K14p (spec §6.2 K14's second case): our pet hitting the target beside our twin hands; its rows stay foreign
M.KINDS.K14p = { duration = 60, twins = true, ourPet = true }
-- K14f (owner-confirmed 2026-10-22, a level-25 fast dual-wielder): two 1.5 s hands at 1.2 haste (a swing every
-- about 0.6 s on average across both hands); per-hand recall and the rage estimate's error against truth.
M.KINDS.K14f = { duration = 60, weapons = { { 40, 54, 1.5 }, { 40, 54, 1.5 } }, haste = 1.2, sessionLag = true }
M.KINDS.K15 = { duration = 60, noMelee = true, spells = mixSpells(58) }
M.KINDS.K16 = { duration = 300, spells = every("bolt", 2, 298) }
-- bolts in flight at the stop; every 2 s: a press every 1.5 s (the cast time) restarted the cast before its success
M.KINDS.K17 = { duration = 20, noMelee = true, spells = every("bolt", 2, 20) }
M.KINDS.K18 = { duration = 60, noMelee = true, extraMobs = 2, spells = every("aoe", 2, 58), splash = true }
-- K21 (owner ruling 2026-10-22): a nature projectile (14-18) and a nature schedule (ticks of 6 every 3 s after a
-- 0.5 s flight) on one GUID, their rows interleaved: the amount bands rank each row to its own ticket.
local k21 = every("bolt", 3, 57)
for _, t in ipairs({ 2.5, 17.5, 32.5, 47.5 }) do
    k21[#k21 + 1] = { t, "ticks" }
end
table.sort(k21, function(x, y)
    return x[1] < y[1]
end)
M.KINDS.K21 = { duration = 60, noMelee = true, spells = k21, distances = { 20 } }
M.KINDS.K19 = {
    duration = 60,
    extraMobs = 1,
    spells = every("doti", 6, 54),
    presses = strikes(6, 57),
    switchTo = { { 7.2, 2 }, { 9.5, 1 }, { 19.2, 2 }, { 21.5, 1 }, { 31.2, 2 }, { 33.5, 1 } },
}

-- K6's scope ends at PLAYER_REGEN_ENABLED (metrics.tickets), which the observer fires observer.COMBAT_END = 1 s after
-- the last kill. probe U14: time from the last kill to PLAYER_REGEN_ENABLED (spec §2.5's Rogue capture: about 0.52 s
-- after the killing swing; the strike capture: about 1.07 s after the killing row; kept at 1 s until measured).

-- The boot every detection fight uses: the expect abilities, 30 yd projectiles (fake_api's default range is 5 yd).
function M.boot(c)
    c.ctl.ranges[fs.SPENDER_P], c.ctl.ranges[fs.SPENDER_S] = { 0, 30 }, { 0, 30 }
    local def = fs.def(fs.new(9, false, false, true))
    def.providers = ab.providers()
    c.I.Build(def, 0.1)
    c.VS.Start(c.api)
end

--- `fights` fights of `kind` in `band` from seed `seed0`, each on a fresh VirtualState: their tally. `check(c, s)`, if
--- given, sees each fight's captures before they are restored (the invariant sweep).
function M.run(kind, band, fights, seed0, check)
    local m = metrics.newTickets()
    m.melee = metrics.new()
    m.melee.tk = m -- the melee tally's recovery and wash go to the cell's tally
    for f = 0, fights - 1 do
        local o = {}
        for k, v in pairs(M.KINDS[kind]) do
            o[k] = v
        end
        o.others, o.group = {}, M.BANDS[band].group
        for i, x in ipairs(M.BANDS[band].others) do
            o.others[i] = x
        end
        if o.lockstep then
            o.others[#o.others + 1], o.phase = "lockstep", o.lockstep
        end
        if o.twin then
            o.others[#o.others + 1], o.phase = "twin", o.twin
        end
        if o.splash then -- K18's partner: a melee whose swings also hit the mob beside our target
            o.others[#o.others + 1] = "splash"
        end
        if o.distances then
            o.distance = o.distances[f % #o.distances + 1]
        end
        local s, W = scenarios.stream(o, seed0 + f)
        local c = drive.boot({ boot = M.boot })
        drive.run(c, s)
        metrics.tickets(m, c, s, W)
        metrics.score(m.melee, c, s, W)
        if check then
            check(c, s)
        end
        drive.restore(c)
    end
    return m
end

local FILE = "tests/Game/harness/detect_floors.lua"

function M.floors()
    local f = loadfile(FILE)
    return f and f() or {}
end

-- The measured cell as a floor: recall and staged down to 0.01, the ceilings up to 0.1.
local function cell(m)
    local down = function(x)
        return math.floor(x * 100) / 100
    end
    local up = function(x)
        return math.ceil(x * 10) / 10
    end
    local mm = m.melee
    return {
        recall = down(metrics.recall(m)),
        melee = down(metrics.rate(mm, 1)),
        melee2 = down(metrics.rate(mm, 2)),
        -- the rage estimate's mean error (Task 9b), its size: an improvement toward 0 must never fail its ceiling
        rageErr = up(math.abs(mm.windows > 0 and mm.errSum / mm.windows or 0)),
        staged = down(metrics.staged(m)),
        false100 = up(metrics.false100(m)),
        leak100 = up(metrics.leak100(m)),
        lostDiff = math.abs(m.lostEngine + m.assumedEngine - m.lostTruth),
        residual = math.abs(m.outcomes - m.dispatched), -- negative: a double dispatch, as bad as a merge
        -- K6: own white rows after the kill's clear paid by their swing (before REGEN_ENABLED; metrics.tickets)
        postClear = down(m.postClear > 0 and m.postClearPaid / m.postClear or 1),
        -- attribution-recovery spec §5.2: the share of false credits recovered; own swaps' mean net rage error a fight
        -- a share like recall (a percent's integers read as spell IDs to tests/boundary_spec.lua)
        recovered = down(metrics.recovered100(m) / 100),
        wash = up(metrics.wash(m)),
    }
end

-- A note written above a kind's floors (detect_floors.lua): why a cell sits where it does.
M.NOTES = {
    K10 = "K10: melee recall does not hold under a session lag (spec §6.2's check; party 0.36, busy 0.18 against K1's"
        .. " 0.83 / 0.70). The session's landing median from [0.4, 1.0] s drives it (without it 0.86 / 0.73); the"
        .. " first-swing lag costs party 0.06; jitter, pushback and PLAYER_ENTER_COMBAT cost nothing. Measured, not"
        .. " a target (Task 13 finding; the melee scoring is probe U15's).",
    K13 = "K13: phase 0 solo's 17.8 divergent pairs per 100 own is the synthetic worst case (a twin in our very ms on"
        .. " every press), not an in-game rate; spec §4's union-belief trigger (> 1 per 100 paid) needs an in-game"
        .. " rate: probe U16, a party capture with a same-school caster on our target. Party and busy are floors (crowd"
        .. " cost dominates the per-pair cost).",
    K14p = "K14p: owner finding. The spec has our pet's rows stay foreign; our swing tickets take 8.8 / 6.6 / 3.2 per"
        .. " 100 of them (solo / party / busy) through the melee scoring, which cannot tell a pet's white hit on our"
        .. " target from ours (probe U15's family). Floored by the first clean run, not a target.",
    K11m = "K11m: post-clear rows paid by their swing are a floor, not every row: busy 6 of 7 (a 0.769 s tail lag scores"
        .. " below theta, K6's mechanism).",
}

--- With DETECT_WRITE=1, writes the cell's floor into detect_floors.lua (the first clean run).
function M.record(kind, band, m)
    if os.getenv("DETECT_WRITE") ~= "1" then
        return
    end
    local all = M.floors()
    all[kind] = all[kind] or {}
    all[kind][band] = cell(m)
    local kinds = {}
    for k in pairs(all) do
        kinds[#kinds + 1] = k
    end
    table.sort(kinds)
    local out = {
        "-- tests/Game/harness/detect_floors.lua: the detection suite's floors (unit-registry spec §6.2),",
        "-- written by the first clean run (DETECT_WRITE=1). Floors only move up; a lower one needs a named cause.",
        "-- 2026-10-23 (attribution-recovery spec decisions 46, 48-50): regenerated under the owner's ruling (recall over"
            .. " precision): recall up; false credit, leak, lostDiff and pet rows may rise.",
        "-- 2026-10-23 (decisions 51-52, owner ruling: expiry EV): regenerated with the expectation at a swing's lost"
            .. " close; rageErr down.",
        "-- Fix round 2 (avoidSeen): 9fd58600's floors were never merged; part of their drop rested on believed rage for"
            .. " swings avoided in truth (an error cancelling the under-count), which the avoidSeen fix removes.",
        "-- Task 5 (attribution-recovery decisions 54-56): recovered (floor, a share) and wash (ceiling) first set by this run.",
        "-- stylua: ignore",
        "return {",
    }
    for _, k in ipairs(kinds) do
        if M.NOTES[k] then
            out[#out + 1] = "    -- " .. M.NOTES[k]
        end
        out[#out + 1] = "    " .. k .. " = {"
        for _, b in ipairs({ "solo", "party", "busy" }) do
            local v = all[k][b]
            if v then
                out[#out + 1] = string.format(
                    "        %s = { recall = %.2f, melee = %.2f, melee2 = %.2f, rageErr = %.1f, staged = %.2f, false100 = %.1f, leak100 = %.1f, lostDiff = %d, residual = %d, postClear = %.2f, recovered = %.2f, wash = %.1f },",
                    b,
                    v.recall,
                    v.melee,
                    v.melee2,
                    v.rageErr,
                    v.staged,
                    v.false100,
                    v.leak100,
                    v.lostDiff,
                    v.residual,
                    v.postClear,
                    v.recovered or 0, -- a floor written before Task 5's cells: rewritten by its own kind's run
                    v.wash or 0
                )
            end
        end
        out[#out + 1] = "    },"
    end
    out[#out + 1] = "}"
    local fh = assert(io.open(FILE, "w"))
    fh:write(table.concat(out, "\n") .. "\n")
    fh:close()
end

--- Asserts the cell against its floor (no floor yet: the run must have been recorded first).
function M.check(kind, band, m)
    local fl = (M.floors()[kind] or {})[band]
    assert(fl, kind .. " " .. band .. ": no floor; run once with DETECT_WRITE=1")
    local v, line, at = cell(m), metrics.ticketLine(m), kind .. " " .. band -- ab.check prefixes "<at>: "
    ab.check(v.recall >= fl.recall, at, "recall below its floor: " .. line)
    ab.check(v.melee >= fl.melee, at, "melee recall below its floor: " .. line)
    ab.check(v.melee2 >= fl.melee2, at, "off-hand recall below its floor: " .. line)
    local mm = m.melee
    local signed = mm.windows > 0 and mm.errSum / mm.windows or 0
    ab.check(v.rageErr <= fl.rageErr, at, ("rage error %.1f above its ceiling: %s"):format(signed, line))
    ab.check(v.staged >= fl.staged, at, "staged below its floor: " .. line)
    ab.check(v.false100 <= fl.false100, at, "false credit above its ceiling: " .. line)
    ab.check(v.leak100 <= fl.leak100, at, "foreign leak above its ceiling: " .. line)
    ab.check(v.lostDiff <= fl.lostDiff, at, "lost reported off the truth: " .. line)
    ab.check(v.residual <= fl.residual, at, "dedupe residual above its ceiling: " .. line)
    ab.check(v.postClear >= fl.postClear, at, "post-clear rows below their floor: " .. line)
    ab.check(v.recovered >= (fl.recovered or 0), at, "recovery below its floor: " .. line)
    ab.check(v.wash <= (fl.wash or math.huge), at, "net wash above its ceiling: " .. line)
end

--- K17's /reload: the first half of a fight on one VirtualState, the rest on a fresh one (an empty registry while
--- rows keep arriving). Returns both drives and their streams.
function M.reload(kind, band, seed)
    local o = setmetatable({ others = M.BANDS[band].others }, { __index = M.KINDS[kind] })
    local s = scenarios.stream(o, seed)
    local half = { n = 0 }
    local rest = { n = 0 }
    for _, f in ipairs({ "t", "ev", "a1", "a2", "a3", "a4", "a5", "src", "hand", "swingT", "actor", "castT" }) do
        half[f], rest[f] = {}, {}
    end
    local mid = s.t[s.n] / 2
    for i = 1, s.n do
        local d = s.t[i] <= mid and half or rest
        d.n = d.n + 1
        for f in pairs(d) do
            if f ~= "n" then
                d[f][d.n] = s[f][i]
            end
        end
    end
    local c1 = drive.boot({ boot = M.boot })
    drive.run(c1, half)
    drive.restore(c1)
    local c2 = drive.boot({ boot = M.boot })
    drive.run(c2, rest)
    drive.restore(c2)
    return c1, c2, half, rest
end

--- K9's direct case: twins from two sources (equal payload, one ms, each on plate and target) and one hit on plate,
--- target and soft, fired at the registry; the rows it dispatched for each.
function M.twins()
    local c = drive.boot({ boot = M.boot })
    local ctl = c.ctl
    ctl.guid.nameplate1, ctl.guid.softenemy = "Creature-1", "Creature-1"
    local n0 = c.rowsOut
    ctl.now = 10
    for _ = 1, 2 do
        ctl.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 20, 1)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 20, 1)
    end
    local twins = c.rowsOut - n0
    ctl.now = 11
    ctl.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 21, 1)
    ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 21, 1)
    ctl.Fire("UNIT_COMBAT", "softenemy", "WOUND", "", 21, 1)
    local single = c.rowsOut - n0 - twins
    drive.restore(c)
    return { twins = twins, single = single }
end

return M
