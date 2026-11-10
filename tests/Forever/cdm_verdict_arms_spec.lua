-- tests/Forever/cdm_verdict_arms_spec.lua (CDM verdict spec §5): the verdict's harness arms resolve on the Arms loop
-- world: their world knobs reach the fight (avoided presses, target swaps with a frame reshuffle each), the *-novd arm
-- turns the belief's verdict off on the driver only, and each fight writes its layout and edgestats lines.
local loop = require("Game.harness.loop")
local ab = require("Game.harness.ab")
local ww = require("Forever.helpers.warrior_world")
local dlw = require("Forever.helpers.druid_loop_world")

local function fight(arm, seed, L)
    L = L or loop.new(ww)
    local lines, check = {}, ab.check
    ab.check = function(ok, label, line) -- the lines a provider arm writes to .ab/<arm>.tsv
        lines[label] = line
        return check(ok, label, line, "default")
    end
    local ok, run = pcall(loop.run, L, seed, { duration = 40, arm = arm }, { { H = L.us } })
    ab.check = check
    assert(ok, run)
    assert.are.same({ 0, 0 }, { run.errors, run.raises })
    return run, L.us, lines
end

describe("the CDM verdict's harness arms #slow", function()
    it("viewer-swap: our target cycles every 4-8 s, every swap reshuffles the frames; edgestats on", function()
        local run, H, lines = fight("viewer-swap", 3)
        local swaps = 0
        for _, ev in ipairs(run.W.truth) do
            swaps = swaps + (ev.kind == "target" and 1 or 0)
        end
        assert.is_true(swaps >= 4, "target events " .. swaps)
        assert.is_true(#run.W.ents >= 4) -- us and three mobs
        assert.is_true(H.ctl.viewer.reshuffle)
        assert.is_true(H.ctl.viewer.reshuffleN - 3 >= swaps - 1, "reshuffles " .. (H.ctl.viewer.reshuffleN - 3))
        assert.is_nil(H.ns.VirtualStateInternal.verdictOff)
        assert.is_truthy(lines.layout)
        assert.is_truthy(lines.edge and lines.edge:match("staleUp %d"), tostring(lines.edge))
    end)

    -- the client's "target" auras follow each swap (observer relist); before it the Feral smoke read self-check 4235
    it("viewer-swap: the oracle's self-check holds under swaps (Feral, rake and rip on the target)", function()
        for _, arm in ipairs({ "viewer-swap", "viewer-swap-dark" }) do
            local L = loop.new(dlw.Feral)
            local ok, run = pcall(loop.run, L, 1, { duration = 40, arm = arm }, {
                { H = L.us },
                { H = L.oracle, plain = true },
            })
            assert(ok, run)
            assert.are.same({}, run.selfCheck, arm)
        end
    end)

    -- the truth check (loop.verdictTruth) on the retarget gap: Marksmanship's pre-pull Hunter's Mark (0.2 s) falls
    -- between the prepull's read (0.1 s) and its retarget (0.205 s); the retarget re-reads it, so the item stays lit and
    -- the verdict does not close it at the pull of fight 3 (before the observer fix: verdicts 0/1 wrong 0/1)
    it("viewer-reshuffle: a pre-pull debuff stays lit over the prepull's retarget, no wrong close", function()
        local hw = require("Forever.helpers.hunter_world")
        local function layout(arm)
            local L, line, check = loop.new(hw.Marksmanship), nil, ab.check
            ab.check = function(ok, label, l)
                line = label == "layout" and l or line
                return check(ok, label, l, "default")
            end
            -- three fights on one boot as the gate: the item is proven over the first two (no verdict before)
            local ok, err = pcall(loop.tally, L, 3, { arm = arm })
            ab.check = check
            assert(ok, err)
            return line
        end
        local line = layout("viewer-reshuffle")
        assert.is_truthy(line:match(" verdicts 0/0 strikes 0/0 wrong 0/0$"), line)
        assert.is_nil(layout("viewer-buffs"):match(" wrong ")) -- a non-verdict arm's line is as before
    end)

    it("viewer-nonland: the mobs avoid our hits by the arm's table, no press aura applied on an avoid", function()
        local run, H, lines = fight("viewer-nonland", 1)
        assert.is_false(run.W.auraOnAvoid)
        assert.are.equal(ab.ARMS["viewer-nonland"].world.mobAvoid, run.us.target.avoid)
        assert.is_false(H.ctl.viewer.reshuffle)
        assert.is_truthy(lines.edge)
    end)

    it("viewer-late: a share of the viewer's lights lands late; the -novd twin draws the same world", function()
        local run = fight("viewer-late", 2)
        local late = run.W.lateN or 0
        assert.is_true(late > 0, "late lights " .. late)
        assert.are.equal(late, fight("viewer-late-novd", 2).W.lateN) -- the twins' seeds are the same
    end)

    it("viewer-recast: an avoided uptime press is pressed again at the next free GCD", function()
        local run = fight("viewer-recast", 6) -- seed 6: three sunders avoided in 40 s
        assert.is_true(run.recasts > 0, "recasts " .. run.recasts)
        assert.are.equal(0, fight("viewer-nonland", 6).recasts) -- the knob's alone
    end)

    it("viewer-swap-dark: the reshuffle leaves re-pointed frames dark for a poll; viewer-swap stays atomic", function()
        local _, H = fight("viewer-swap-dark", 3)
        assert.is_true(H.ctl.viewer.reshuffleDark)
        local _, H2 = fight("viewer-swap", 3)
        assert.is_false(H2.ctl.viewer.reshuffleDark)
    end)

    it("a -novd arm sets the belief's verdictOff on the driver; the next fight's arm clears it", function()
        local L = loop.new(ww)
        local _, H = fight("viewer-reshuffle-novd", 1, L)
        assert.is_true(H.ns.VirtualStateInternal.verdictOff)
        assert.is_true(H.ctl.viewer.reshuffle)
        fight("viewer-reshuffle", 2, L) -- the same boot, the verdict on again
        assert.is_nil(H.ns.VirtualStateInternal.verdictOff)
        assert.is_true(H.ctl.viewer.reshuffle)
    end)
end)
