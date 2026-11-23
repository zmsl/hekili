-- tests/Forever/loop_frames_spec.lua (L1793): the loop feeds each event time as its own client frame, walking the
-- world event by event to the poll (loop.lua step, feed; headless.frame). Frost's mana is secret in combat, so the
-- belief reads it through the usability answers: a cast's spend, then the answers of the frames after it.
local loop = require("Game.harness.loop")

-- Frost, seeds 2 and 4 (the flush-only seed e7e1756bc put their floor over the truth on 25 and 50 polls), 180 s,
-- run A: ours drives, the oracle shadows. Each run: { run, after (polls following one of our spends), overs (of those,
-- the floor over the truth before that poll's press) }. Run once for the file.
local runs
local function frost()
    if runs then
        return runs
    end
    runs = {}
    local C = require("Forever.helpers.mage_world").Frost
    for _, seed in ipairs({ 2, 4 }) do
        local L = loop.new(C)
        local VS, pt = L.us.ns.VirtualState, L.power.type
        local r = { after = 0, overs = {} }
        local seen, spent = 0, false
        r.run = loop.run(L, seed, {
            duration = 180,
            on = function(run, steps, t)
                if spent and t >= loop.PULL then -- the first poll after our spend: the belief folded it, then answers
                    r.after = r.after + 1
                    local lo = VS.Power(pt, steps[1].base + t).lo
                    if lo > run.preTruth + loop.LO_EPS then
                        r.overs[#r.overs + 1] = ("seed %d t %.2f: lo %.2f truth %.2f"):format(seed, t, lo, run.preTruth)
                    end
                end
                spent = false
                local truth = run.W.truth
                for k = seen + 1, #truth do
                    local ev = truth[k]
                    spent = spent or (ev.src == run.us and ev.kind == "cast" and (ev.cost or 0) > 0)
                end
                seen = #truth
            end,
        }, { { H = L.us }, { H = L.oracle, plain = true } })
        assert.are.equal(0, r.run.errors)
        runs[#runs + 1] = r
    end
    return runs
end

describe("the loop's client frames (L1793)", function()
    -- the look-ahead the frame model exposed: the observer stamped an answer at a gain's time (usableDelay late) but
    -- read the world at the poll, so a proc the world applied later in the poll (Clearcasting at Frostbolt's landing)
    -- made Blizzard usable early; folded at its own time that answer pinned the floor at its full cost
    it("Frost, 2 seeds x 180 s: every usability answer reads the world as of its own time", function()
        for _, r in ipairs(frost()) do
            assert.is_true(r.run.ahead <= loop.TIE, ("answers read the world %.3f s ahead"):format(r.run.ahead))
        end
    end)

    -- a cast's spend and the resource reads after it: the spend folds in its own frame, the next frames' answers read
    -- the pool after it, and the poll's floor stays at or under the truth
    it("Frost, 2 seeds x 180 s: a spend pairs with the answers of the frames after it", function()
        local after, overs = 0, {}
        for _, r in ipairs(frost()) do
            after = after + r.after
            for _, s in ipairs(r.overs) do
                overs[#overs + 1] = s
            end
        end
        assert.is_true(after > 0, "no spend of ours")
        assert.are.same({}, overs)
    end)
end)
