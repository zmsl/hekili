-- tests/Forever/prepull_spec.lua: pre-pull lines guard against recasting (owner ruling 2026-10-21). The engine keeps
-- no schedule and no per-episode state: a precombat line is a plain priority line out of combat, shown while its
-- written guard (tools/wowsims/apl.lua rule 1) and its ability's readiness allow it, and never in combat.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("a pre-pull list out of combat", function()
    local H, t, out

    local function cycle()
        t = t + 0.2
        H.ctl.now = t
        assert(headless.cycle(H, t))
        local r = out.count > 0 and out.recs[1]
        return r and r.time <= 0 and r.actionName or false -- shown now (a later wait is the guard's own release)
    end

    local function id(key)
        return H.Hekili.Class.abilities[key].id
    end

    local function cast(key)
        t = t + 1.6
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. key, id(key))
    end

    local function lists(precombat)
        H.Hekili.DB.profile.packs[ww.PACK].lists = { precombat = precombat, default = {} }
        H.Hekili:LoadScripts()
    end

    -- Bloodrage's aura on the player from `on` (10 s), or gone.
    local function buff(on)
        local aura = H.Hekili.Class.auras.bloodrage.id
        H.ctl.auras.player.HELPFUL[1] = on and { spellId = aura, expirationTime = on + 10, applications = 1 } or nil
        H.Fire("UNIT_AURA", "player")
    end

    -- The client's cooldown answer for `key`: running from `start` for `duration` s, or ready (nil).
    local function cooldown(key, start, duration)
        H.ctl.cooldown[id(key)] = start and { isActive = true, isOnGCD = false, startTime = start, duration = duration }
            or nil
    end

    local function to(at)
        t = at - 0.2
        return cycle()
    end

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK }) -- in Battle Stance
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        t = H.ctl.now
        out = H.Hekili.Engine.Output.Primary
        cycle()
    end)

    it("offers a buff line until its buff is up, hides it while up, and offers it again once it expires", function()
        lists({ { enabled = true, action = "bloodrage", use_off_gcd = 1, criteria = "!buff.bloodrage.up" } })
        assert.are.equal("bloodrage", cycle())
        assert.are.equal("bloodrage", cycle()) -- no schedule: still offered while unmet
        cast("bloodrage")
        local t0 = t
        buff(t0)
        assert.is_false(to(t0 + 1))
        assert.is_false(to(t0 + 9))
        buff(false)
        assert.are.equal("bloodrage", to(t0 + 11)) -- the cooldown is the client's: ready (no answer)
        assert.are.same({}, H.errors)
    end)

    it("offers an unguarded line whenever it is ready (Bloodrage: cooldown only)", function()
        lists({ { enabled = true, action = "bloodrage", use_off_gcd = 1 } })
        assert.are.equal("bloodrage", cycle())
        cast("bloodrage")
        local t0 = t
        buff(t0)
        cooldown("bloodrage", t0, 60)
        assert.is_false(to(t0 + 1))
        assert.is_false(to(t0 + 30))
        buff(false)
        cooldown("bloodrage")
        assert.are.equal("bloodrage", to(t0 + 61))
        assert.are.equal("bloodrage", cycle()) -- ready: offered again, no once-per-episode memory
        assert.are.same({}, H.errors)
    end)

    it("ignores a saved priority's stale prepull_at: no once-per-episode schedule", function()
        lists({ { enabled = true, action = "bloodrage", use_off_gcd = 1, prepull_at = 10 } })
        assert.are.equal("bloodrage", cycle())
        cast("bloodrage")
        assert.are.equal("bloodrage", cycle()) -- ready again (the client's answer): offered again
        assert.are.same({}, H.errors)
    end)

    it("offers Charge only while it is usable: out of melee range", function()
        lists({ { enabled = true, action = "charge", use_off_gcd = 1 } })
        assert.is_false(cycle()) -- in melee range
        H.ctl.inRange.target = false
        assert.are.equal("charge", cycle())
        assert.are.same({}, H.errors)
    end)

    it("offers nothing from the pre-pull list in combat", function()
        lists({ { enabled = true, action = "bloodrage", use_off_gcd = 1, criteria = "!buff.bloodrage.up" } })
        assert.are.equal("bloodrage", cycle())
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.is_false(cycle())
        assert.are.same({}, H.errors)
    end)
end)
