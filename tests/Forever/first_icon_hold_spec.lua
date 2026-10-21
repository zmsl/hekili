-- tests/Forever/first_icon_hold_spec.lua: the first icon is held on a near tie (Engine/Sim/Core.lua heldFirst,
-- the owner's no-jitter rule). Berserker Rage over Bloodrage, both waiting on their cooldowns: the higher-priority one
-- shown last refresh keeps the slot while the lower one is ready less than 0.1 s sooner; upstream's 0.05 s pad
-- applies otherwise. A challenger ready within 0.1 s keeps upstream's pad: Protection's replay decision at 112.54 s
-- (tests/Forever/wowsims_paladin_spec.lua) covers it.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the first icon on a near tie", function()
    local H, t, out

    local function cycle()
        t = t + 0.2
        H.ctl.now = t
        assert(headless.cycle(H, t))
        return out.count > 0 and out.recs[1].actionName or false
    end

    -- the client's cooldown answer for `key`: `left` seconds to go at the next refresh
    local function cd(key, left)
        local now = t + 0.2
        H.ctl.cooldown[H.Hekili.Class.abilities[key].id] =
            { isActive = true, isOnGCD = false, startTime = now + left - 60, duration = 60 }
    end

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        t = H.ctl.now
        out = H.Hekili.Engine.Output.Primary
        H.Hekili.DB.profile.packs[ww.PACK].lists = {
            default = {
                { enabled = true, action = "berserker_rage" },
                { enabled = true, action = "bloodrage", use_off_gcd = 1 },
            },
        }
        H.Hekili:LoadScripts()
        H.ctl.form = ww.FORM.berserker_stance -- Berserker Rage's stance; neither costs rage
        H.Fire("UPDATE_SHAPESHIFT_FORM")
        H.Fire("PLAYER_REGEN_DISABLED")
    end)

    it("holds the shown higher-priority icon until the other is ready 0.1 s sooner", function()
        cd("berserker_rage", 4.0)
        cd("bloodrage", 5.0)
        assert.are.equal("berserker_rage", cycle())
        cd("berserker_rage", 5.0)
        cd("bloodrage", 4.93) -- 0.07 s sooner: upstream's pad would swap, the hold keeps Berserker Rage
        assert.are.equal("berserker_rage", cycle())
        cd("berserker_rage", 5.0)
        cd("bloodrage", 4.7) -- 0.3 s sooner: Bloodrage takes the slot
        assert.are.equal("bloodrage", cycle())
        assert.are.same({}, H.errors)
    end)

    it("keeps upstream's 0.05 s pad when the higher-priority icon was not the one shown", function()
        cd("berserker_rage", 5.0)
        cd("bloodrage", 4.0)
        assert.are.equal("bloodrage", cycle())
        cd("berserker_rage", 5.0)
        cd("bloodrage", 4.9)
        assert.are.equal("bloodrage", cycle())
        assert.are.same({}, H.errors)
    end)
end)
