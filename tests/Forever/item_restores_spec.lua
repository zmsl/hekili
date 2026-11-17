-- tests/Forever/item_restores_spec.lua (item-restores-09): an on-use mana gem's restore is the belief's as any self-mana
-- effect: the replay emits the use spell of the rank the log used (tests/Game/harness/replay.lua) and the ability's
-- `now` credits that rank's average (Hekili_Shared/Shared/Consumables.lua; the roll's mid +- spread). On the Arcane
-- wowsims log, the belief's jump over each mana gem use (its last read at the use to its first read 0.2 s later) matches
-- the truth's jump within the gem's roll spread (100 at most) and the belief's own regen over the gap.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.mage_world")
local loop = require("Game.harness.loop")
local replay = require("Game.harness.replay")

local SPEC = "mage_arcane"
local GEMS = { [8008] = true, [8007] = true, [5513] = true, [5514] = true }
-- 100: the largest gem spread (Mana Ruby); 30: the regen the belief adds over the gap (under 30 mana at 0.2 s)
local TOLERANCE = 100 + 30

describe("an on-use mana gem's restore #slow", function()
    it("moves the belief as it moves the truth at each logged use, within the roll's spread", function()
        local C = ws.logged(
            ws.content(W.Arcane, {
                pack = "Arcane (wowsims.com)",
                level = 60,
                talents = ws.header(SPEC).talents,
                learn = ws.learn("MAGE"),
                race = ws.race(SPEC),
            }),
            SPEC
        )
        local L = loop.new(C)
        local text = ws.log(SPEC)
        local uses = {}
        for ts, id in text:gmatch("%[([%d%.]+)%] %[[^%]]+%] Completed cast {ItemID: (%d+)}") do
            if GEMS[tonumber(id)] then
                uses[#uses + 1] = { at = tonumber(ts) }
            end
        end
        assert.is_true(#uses > 0, "the log carries a mana gem use")
        local R = replay.new(text, L.oracle, ws.replayOptions(C, SPEC))
        loop.replay(L, R, {
            on = function(run, steps, t)
                local s = t - R.pull
                local est
                for _, u in ipairs(uses) do
                    if s <= u.at + 1e-6 and s >= u.at - 0.3 then
                        est = est or steps[1].H.ns.VirtualState.Power(L.power.type, steps[1].base + t).est
                        u.before = { est, run.us.power }
                    elseif s >= u.at + 0.2 - 1e-6 and s <= u.at + 0.5 and not u.after then
                        est = est or steps[1].H.ns.VirtualState.Power(L.power.type, steps[1].base + t).est
                        u.after = { est, run.us.power }
                    end
                end
            end,
        })
        for _, u in ipairs(uses) do
            assert.is_truthy(u.before and u.after, ("the use at %.2f s was read"):format(u.at))
            local believed, truth = u.after[1] - u.before[1], u.after[2] - u.before[2]
            assert.is_true(
                math.abs(believed - truth) <= TOLERANCE,
                ("gem use at %.2f s: belief %+.1f, truth %+.1f"):format(u.at, believed, truth)
            )
        end
    end)
end)
