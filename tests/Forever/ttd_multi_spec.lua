-- tests/Forever/ttd_multi_spec.lua (lane h-hw, multi-target time to die: tests only): harness worlds with several enemy
-- lives. scenarios.world's `mobHealths` gives each mob its own health, `drains` (a party member's damage on a mob that
-- is not our target) makes the lives differ, and the fight's truth is the last death (W.killAt; world.lua W.livesLeft).
-- Each fight writes a record-only `ttdm` row (loop.ttdmRow): the error of the core's fight_remains against that truth and
-- of target.time_to_die against the target's own death. No floors here: the integration branch floors the rows. The
-- worlds carry no boss tokens (fake_lhv is held to the real library, which has none).
--   W1 one long life + two adds; W2 the same, our target swapping to the adds and back; W3 two long lives;
--   W4 a trash pack of 15/25/40/60 s; W5 the library off (today's answers: 3600); W6 a plate token reused at once.
local loop = require("Game.harness.loop")
local ab = require("Game.harness.ab")
local ww = require("Forever.helpers.warrior_world")

local UNKNOWN = 3600

-- One fight of `o` on a fresh boot: the ttdm row's line, the run and the instance.
local function fight(o, arm, seed)
    local L, rows = loop.new(ww), {}
    local record, check = ab.record, ab.check
    ab.record = function(label, line)
        rows[label] = line
    end
    ab.check = function(ok, label, line) -- every row kept; only the bands row goes unjudged: its target containment is
        -- not modelled across a death and a retarget (est 0 against the next mob's band), an open limit (h-hw review Minor 1)
        rows[label] = line
        if label ~= "bands" then
            assert(ok, label .. ": " .. tostring(line))
        end
    end
    o.arm, o.trace = arm, false
    local ok, run = pcall(loop.run, L, seed, o, { { H = L.us } })
    ab.record, ab.check = record, check
    assert(ok, run)
    assert.are.same({ 0, 0 }, { run.errors, run.raises })
    return rows.ttdm, run, L
end

-- Our damage a second on the first mob (the calibration fight the ttd arm's oracle uses).
local rateMemo
local function ourRate()
    rateMemo = rateMemo or loop.truthRate(loop.new(ww).content, { duration = 60, arm = "ttd" }).A
    return rateMemo
end

-- lives: seconds each mob lives; the first is ours (its health from our rate), the others drained by the group.
local function world(lives)
    local rate = ourRate()
    local o = { mobHealths = {}, drains = {}, duration = 150 }
    for i, life in ipairs(lives) do
        if i == 1 then
            o.mobHealths[1] = rate * life
        else
            local dps = 100
            o.mobHealths[i] = dps * life
            o.drains[#o.drains + 1] = { mob = i, dps = dps }
        end
    end
    return o
end

local function figures(row)
    local live = {}
    for n in row:gmatch(" live (%d+) scored") do
        live[#live + 1] = tonumber(n)
    end
    return live
end

describe("multi-life worlds (record-only) #slow", function()
    local function record(name, build, arm, expectLast)
        it(name, function()
            local o = build()
            local row, run = fight(o, arm or "ttd", 5)
            assert.is_string(row)
            print("ttdm " .. name .. ": " .. row)
            assert.is_true(run.ttdm[1] ~= nil, "polls recorded")
            assert.is_truthy(run.W.killAt, "every life ended: " .. row)
            local last = run.W.killAt - loop.PULL
            assert.is_true(last > 0, row) -- the last death ends the fight (our rate is a mean: the nominal life is only near)
            return row
        end)
    end

    -- W1: one long life, the player on it, and two adds that live 20 s each
    record("W1 long life plus adds", function()
        local o = world({ 120, 20, 20 })
        o.drains[1].from, o.drains[2].from = 20, 60 -- the adds arrive at 20 s and 60 s of the fight
        return o
    end, nil, 120)

    -- W2: the same, our target swaps to each add for its life and back
    record("W2 swap to adds and back", function()
        local o = world({ 120, 20, 20 })
        o.drains[1].from, o.drains[2].from = 20, 60
        o.switchTo = { { loop.PULL + 22, 2 }, { loop.PULL + 44, 1 }, { loop.PULL + 62, 3 }, { loop.PULL + 84, 1 } }
        return o
    end, nil, 120)

    -- W3: two long lives at different rates
    record("W3 two long lives", function()
        return world({ 90, 150 })
    end, nil, 150)

    -- W4: a trash pack, mobs of 15/25/40/60 s
    record("W4 trash pack", function()
        return world({ 15, 25, 40, 60 })
    end, nil, 60)

    -- W5: library off (no bands, no library): fight_remains and target.time_to_die read today's 3600 every poll
    it("W5 library off reads today's answers", function()
        local row, run = fight(world({ 15, 25, 40, 60 }), "lib-absent", 5)
        print("ttdm W5 library off: " .. row)
        for k, p in ipairs(run.ttdm) do
            assert.are.equal(UNKNOWN, p[1], "fight_remains at poll " .. k)
            assert.are.equal(UNKNOWN, p[2], "target.time_to_die at poll " .. k)
        end
        assert.are.same({ 0, 0 }, figures(row))
    end)

    -- W6: a plate removed and its token named at once by another mob (no life carried to it)
    it("W6 a plate token reused at once", function()
        local o = world({ 60, 25, 40 })
        local reused
        o.on = function(_, steps, t)
            local H = steps[1].H
            local rig, ctl = H.ctl.ttdRig, H.ctl
            if t >= loop.PULL + 30 and not reused and rig then
                reused = true
                local f = rig.lib.frame
                local tok = "nameplate2"
                f.__scripts.OnEvent(f, "NAME_PLATE_UNIT_REMOVED", tok)
                ctl.lhv:Push("health", tok, nil, nil, nil, ctl.now)
                ctl.guid[tok] = "Creature-reused"
                ctl.lhv:Prime(tok, ctl.now)
                ctl.lhv:Push("health", tok, nil, 800, 1000, ctl.now)
                f.__scripts.OnEvent(f, "NAME_PLATE_UNIT_ADDED", tok)
            end
        end
        local row, run = fight(o, "ttd", 5)
        print("ttdm W6 token reused: " .. row)
        assert.is_true(reused, "the reuse ran")
        assert.is_true(run.ttdm[1] ~= nil)
    end)
end)
