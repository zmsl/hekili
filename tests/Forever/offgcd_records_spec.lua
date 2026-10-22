-- tests/Forever/offgcd_records_spec.lua (central fix 34): the on-GCD plan stays in the queue behind off-GCD picks. The
-- owner's level 25 Fury snapshot held three records (numIcons 3) of instants at 0.00: an on-GCD pick, then two off-GCD
-- ones (Bloodrage, Heroic Strike) superseding the next on-GCD pick at +GCD, which never showed. Core now keeps
-- recording past numIcons (at most 2 more) until the records hold two on-GCD picks.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local function run(list)
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(headless.cycle(H, H.ctl.now + 0.2))
    H.Hekili.DB.profile.packs[ww.PACK].lists = { default = list }
    H.Hekili:LoadScripts()
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
    H.ctl.combat = true
    H.Fire("PLAYER_REGEN_DISABLED")
    assert(headless.cycle(H, H.ctl.now + 0.2))
    assert.are.same({}, H.errors)
    assert.are.equal(3, H.Hekili.DB.profile.displays.Primary.numIcons)
    local out, names = H.Hekili.Engine.Output.Primary, {}
    for i = 1, out.count do
        names[i] = out.recs[i].actionName
    end
    return out, names
end

describe("the queue behind off-GCD picks", function()
    it("records the on-GCD pick after two off-GCD ones past numIcons", function()
        local out, names = run({
            { enabled = true, action = "sunder_armor" },
            { enabled = true, action = "bloodrage", use_off_gcd = 1 },
            { enabled = true, action = "heroic_strike", use_off_gcd = 1 },
        })
        -- Bloodrage takes the first slot beside Sunder at 0.00; Heroic Strike then supersedes the next Sunder
        assert.are.same({ "bloodrage", "sunder_armor", "heroic_strike", "sunder_armor" }, names)
        assert.is_true(out.recs[4].time > 1, "the on-GCD pick waits out the GCD")
    end)

    it("keeps numIcons records when every pick is on the GCD", function()
        local _, names = run({ { enabled = true, action = "sunder_armor" } })
        assert.are.same({ "sunder_armor", "sunder_armor", "sunder_armor" }, names)
    end)
end)
