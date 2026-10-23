-- tests/Game/harness/detect.lua (unit-registry spec §6.2): the detection suite's bands, kinds, runner and floors.
local scenarios = require("Game.harness.scenarios")
local drive = require("Game.harness.drive")
local metrics = require("Game.harness.metrics")
local fs = require("Game.State.helpers.fake_spec")

local M = {}

local function mix(n)
    local others = {}
    for i = 1, n do
        others[i] = ({ "melee", "melee", "caster", "pet", "ranged", "melee" })[i % 6 + 1] -- group_spec.lua's mix
    end
    return others
end

-- Other sources on our target (foreign outcomes per second as measured, spec §6.2).
M.BANDS = {
    solo = { others = {} },
    party = { others = { "melee", "caster" } },
    busy = { others = { "melee", "melee", "melee", "caster", "caster", "pet", "pet" } },
    raid12 = { others = mix(11) },
    raid25 = { others = mix(24) },
    raid40 = { others = mix(39) },
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

-- K6's scope ends at PLAYER_REGEN_ENABLED (metrics.tickets), which the observer fires observer.COMBAT_END = 1 s after
-- the last kill. probe U14: time from the last kill to PLAYER_REGEN_ENABLED (spec §2.5's Rogue capture: about 0.52 s
-- after the killing swing; the strike capture: about 1.07 s after the killing row; kept at 1 s until measured).

-- The boot every detection fight uses: the expect abilities, 30 yd projectiles (fake_api's default range is 5 yd).
function M.boot(c)
    c.ctl.ranges[fs.SPENDER_P], c.ctl.ranges[fs.SPENDER_S] = { 0, 30 }, { 0, 30 }
    c.I.Build(fs.def(fs.new(9, false, false, true)), 0.1)
    c.VS.Start(c.api)
end

--- `fights` fights of `kind` in `band` from seed `seed0`, each on a fresh VirtualState: their tally.
function M.run(kind, band, fights, seed0)
    local m = metrics.newTickets()
    m.melee = metrics.new()
    for f = 0, fights - 1 do
        local o = {}
        for k, v in pairs(M.KINDS[kind]) do
            o[k] = v
        end
        o.others = {}
        for i, x in ipairs(M.BANDS[band].others) do
            o.others[i] = x
        end
        if o.lockstep then
            o.others[#o.others + 1], o.phase = "lockstep", o.lockstep
        end
        if o.distances then
            o.distance = o.distances[f % #o.distances + 1]
        end
        local s, W = scenarios.stream(o, seed0 + f)
        local c = drive.boot({ boot = M.boot })
        drive.run(c, s)
        metrics.tickets(m, c, s, W)
        metrics.score(m.melee, c, s, W)
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
        lostDiff = math.abs(m.lostEngine - m.lostTruth),
        residual = math.abs(m.outcomes - m.dispatched), -- negative: a double dispatch, as bad as a merge
        -- K6: own white rows after the kill's clear paid by their swing (before REGEN_ENABLED; metrics.tickets)
        postClear = down(m.postClear > 0 and m.postClearPaid / m.postClear or 1),
    }
end

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
        "-- stylua: ignore",
        "return {",
    }
    for _, k in ipairs(kinds) do
        out[#out + 1] = "    " .. k .. " = {"
        for _, b in ipairs({ "solo", "party", "busy" }) do
            local v = all[k][b]
            if v then
                out[#out + 1] = string.format(
                    "        %s = { recall = %.2f, melee = %.2f, melee2 = %.2f, rageErr = %.1f, staged = %.2f, false100 = %.1f, leak100 = %.1f, lostDiff = %d, residual = %d, postClear = %.2f },",
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
                    v.postClear
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
    local v, line = cell(m), metrics.ticketLine(m)
    assert(v.recall >= fl.recall, kind .. " " .. band .. " recall below its floor: " .. line)
    assert(v.melee >= fl.melee, kind .. " " .. band .. " melee recall below its floor: " .. line)
    assert(v.melee2 >= fl.melee2, kind .. " " .. band .. " off-hand recall below its floor: " .. line)
    local mm = m.melee
    local signed = mm.windows > 0 and mm.errSum / mm.windows or 0
    assert(v.rageErr <= fl.rageErr, ("%s %s rage error %.1f above its ceiling: %s"):format(kind, band, signed, line))
    assert(v.staged >= fl.staged, kind .. " " .. band .. " staged below its floor: " .. line)
    assert(v.false100 <= fl.false100, kind .. " " .. band .. " false credit above its ceiling: " .. line)
    assert(v.leak100 <= fl.leak100, kind .. " " .. band .. " foreign leak above its ceiling: " .. line)
    assert(v.lostDiff <= fl.lostDiff, kind .. " " .. band .. " lost reported off the truth: " .. line)
    assert(v.residual <= fl.residual, kind .. " " .. band .. " dedupe residual above its ceiling: " .. line)
    assert(v.postClear >= fl.postClear, kind .. " " .. band .. " post-clear rows below their floor: " .. line)
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
