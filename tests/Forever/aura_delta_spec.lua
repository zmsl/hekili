-- tests/Forever/aura_delta_spec.lua (border batch 1, item 2; audit E2): an own-cast aura reaches Hekili's aura scrape
-- in the same Update, through Hekili's own UNIT_AURA handler (Engine/Sim/Events.lua) fed the believed delta by the
-- event facade inside Drain, not by Adapter.lua writing `state.player.updated`. Arms casts Battle Shout with no client
-- UNIT_AURA following (the belief moved alone); the next cycle's reset must already see the buff up.
local headless = require("Game.harness.headless")
local fake = require("Game.State.helpers.fake_api")
local ww = require("Forever.helpers.warrior_world")

local BATTLE_SHOUT = 6673
local REND = 11574 -- the highest rank the kit knows

describe("an own-cast aura and Hekili's scrape", function()
    it("is up at the very next cycle's reset, with no client UNIT_AURA", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target = true
        H.Fire("UNIT_AURA", "player")
        H.Fire("SPELL_UPDATE_COOLDOWN")
        H.Fire("UPDATE_SHAPESHIFT_FORM")
        local hooks = H.Hekili.Class.hooks
        hooks.reset_precast = hooks.reset_precast or {}
        local seen = {} -- the buff as each reset of the cycle saw it
        table.insert(hooks.reset_precast, function()
            seen[#seen + 1] = H.Hekili.State.buff.battle_shout.up
        end)
        H.ctl.now = H.ctl.now + 1
        assert(headless.cycle(H, H.ctl.now))
        assert.is_true(#seen > 0 and seen[1] == false, "the buff must start down")
        seen = {}
        H.ctl.now = H.ctl.now + 1
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", BATTLE_SHOUT)
        assert(headless.cycle(H, H.ctl.now))
        assert.is_true(#seen > 0, "the cycle reset")
        assert.is_true(seen[1], "the cycle after the cast read the buff stale")
        assert.are.same({}, H.errors)
    end)

    -- Item 3: in combat the target's real UNIT_AURA is delivered to nobody (its payload is secret), so the believed
    -- delta is the only way an own-cast debuff reaches the APL; the real event must not be needed and must not break it.
    it("a target debuff is up at the next cycle's reset in combat, the real target event dropped", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        H.Fire("UNIT_AURA", "player")
        H.Fire("UNIT_AURA", "target")
        H.Fire("SPELL_UPDATE_COOLDOWN")
        H.Fire("UPDATE_SHAPESHIFT_FORM")
        local hooks = H.Hekili.Class.hooks
        hooks.reset_precast = hooks.reset_precast or {}
        local seen = {}
        table.insert(hooks.reset_precast, function()
            seen[#seen + 1] = H.Hekili.State.debuff.rend.up
        end)
        H.ctl.combat, H.ctl.auraError.target = true, true -- the target's walk raises in combat, as on Forever
        H.Fire("PLAYER_REGEN_DISABLED")
        H.ctl.now = H.ctl.now + 1
        assert(headless.cycle(H, H.ctl.now))
        assert.is_true(#seen > 0 and seen[1] == false, "the debuff must start down")
        seen = {}
        H.ctl.now = H.ctl.now + 1
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", REND)
        H.Fire("UNIT_AURA", "target", fake.SECRET) -- the real event, delivered to nobody
        assert(headless.cycle(H, H.ctl.now))
        assert.is_true(#seen > 0, "the cycle reset")
        assert.is_true(seen[1], "the cycle after the cast read the debuff stale")
        assert.are.same({}, H.errors)
    end)
end)
