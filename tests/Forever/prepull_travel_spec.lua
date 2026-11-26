-- tests/Forever/prepull_travel_spec.lua (L504): a pre-pull hardcast with travel, through the real engine. In game the
-- cast succeeds out of combat and the player stays out of combat until the bolt lands, so the precombat list is walked
-- again in that window: an unguarded Shadow Bolt line shows itself again and hides the next pre-pull line (wowsims
-- starts Corruption at -0.1 s while the bolt is in flight). Rule 1's travel guard hides the line from the cast's
-- success until its travel time has passed, then releases it with no combat event (a miss never blanks the opener).
-- The kit's Shadow Bolt is no engine projectile (no `impact`), so `in_flight` would never answer.
local headless = require("Game.harness.headless")
local w = require("Forever.helpers.warlock_world")

describe("a pre-pull hardcast with travel (L504)", function()
    local H, t, out

    local function cycle(dt)
        t = t + (dt or 0.2)
        H.ctl.now = t
        assert(headless.cycle(H, t))
        return out.count > 0 and out.recs[1].actionName or false
    end

    local function lists(bolt)
        local P = H.Hekili.DB.profile.packs["Shadow Brand (wowsims.com)"]
        P.lists = {
            precombat = {
                { enabled = true, action = "shadow_bolt", criteria = bolt },
                { enabled = true, action = "corruption", criteria = "!debuff.corruption.up" },
            },
            default = {},
        }
        H.Hekili:LoadScripts()
        H.Hekili:ReviewPacks()
    end

    -- the bolt's 2.45 s hardcast (the GCD it starts at the cast's start is over at its success), then a cycle `dt` after
    -- the success
    local function bolt(dt)
        t = t + 1
        H.ctl.now = t
        H.ctl.casting = { t * 1000, (t + 2.45) * 1000 }
        H.Fire("UNIT_SPELLCAST_START", "player", "Cast-sb", 25307)
        t = t + 2.45
        H.ctl.now = t
        H.ctl.casting = nil
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-sb", 25307)
        return cycle(dt)
    end

    before_each(function()
        H = headless.new({ character = w.ShadowBrand.character(), pack = "Shadow Brand (wowsims.com)" })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target, H.ctl.distance.target = true, 60, 28 -- a caster pull
        H.Fire("PLAYER_TARGET_CHANGED")
        t = H.ctl.now
        out = H.Hekili.Engine.Output.Primary
        cycle()
    end)

    it("unguarded, shows Shadow Bolt again while it flies (the bug)", function()
        lists(nil)
        assert.are.equal("shadow_bolt", cycle())
        assert.are.equal("shadow_bolt", bolt(0.2))
        assert.are.same({}, H.errors)
    end)

    it("guarded, shows the next pre-pull line while the bolt flies, then releases with no combat event", function()
        lists("action.shadow_bolt.time_since>action.shadow_bolt.travel_time")
        assert.are.equal("shadow_bolt", cycle()) -- never cast: the guard holds nothing
        local travel = H.Hekili.State.action.shadow_bolt.travel_time
        assert.is_true(travel > 0.4, tostring(travel))
        assert.are.equal("corruption", bolt(0.2))
        assert.are.equal("shadow_bolt", cycle(travel)) -- landed (or missed) and still out of combat
        assert.are.same({}, H.errors)
    end)
end)
