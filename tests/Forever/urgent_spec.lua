-- tests/Forever/urgent_spec.lua (border batch 2 Part C, E14): the cycles the belief's urgent lane used to ask for
-- (Hekili:ForceUpdate with a layer-named reason) now come from Hekili's own handlers of client-shaped events: the
-- SPELL_UPDATE_USABLE / SPELL_UPDATE_COOLDOWN with the belief's edge flag as their eighth slot (a tracked ability's
-- flag flipped, Game/Events/EventFacade.lua), PLAYER_SWING, and the combat log's SPELL_MISSED of our refused cast and
-- SWING_DAMAGE of our landed swing (Engine/Sim/Events.lua).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("Hekili's own handlers force the cycles the urgent lane used to (E14)", function()
    local H, f, ctl, L, id

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        f, ctl, L = H.ns.EngineFrame, H.ctl, H.ns.VirtualStateInternal.Log
        local A = H.ns.VirtualStateInternal.ab -- a tracked ability on a slot: the id the usability source queries
        for a = 1, A.n do
            if A.slot[a] > 0 then
                id = A.qid[a]
                break
            end
        end
        assert.is_number(id)
        ctl.inRange.target, ctl.level.target = true, 60
        ctl.guid.target = "Creature-9"
        H.Fire("PLAYER_TARGET_CHANGED")
        f.criticalUpdate = false
    end)

    local function forced()
        local v = f.criticalUpdate
        f.criticalUpdate = false
        return v
    end

    it("a usability event forces only when a tracked ability's flag flipped", function()
        H.Fire("SPELL_UPDATE_USABLE")
        forced() -- the first event after the boot may carry the boot's edges
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_false(forced()) -- nothing flipped: no edge flag, nothing forced
        local u = ctl.usable[id]
        ctl.usable[id] = { not (u and u[1]), false }
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_true(forced())
    end)

    it("a cooldown event forces only when a tracked ability's flag flipped", function()
        H.Fire("SPELL_UPDATE_COOLDOWN")
        forced()
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.is_false(forced())
        ctl.cooldown[id] = { isActive = true, isOnGCD = false }
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.is_true(forced())
    end)

    it("a charges event forces on a flag flip, and leaves none for the cooldown event after it", function()
        H.Fire("SPELL_UPDATE_CHARGES")
        forced()
        H.Fire("SPELL_UPDATE_CHARGES")
        assert.is_false(forced()) -- no flip, no edge
        ctl.cooldown[id] = { isActive = true, isOnGCD = false }
        H.Fire("SPELL_UPDATE_CHARGES")
        assert.is_true(forced())
        ctl.cooldown[id] = { isActive = false, isOnGCD = false }
        H.Fire("SPELL_UPDATE_CHARGES")
        forced()
        ctl.cooldown[id] = { isActive = true, isOnGCD = false }
        H.Fire("SPELL_UPDATE_CHARGES") -- the flip is consumed here ...
        H.Fire("SPELL_UPDATE_COOLDOWN") -- ... and this one sees none, but the charges event already forced
        assert.is_true(forced())
    end)

    it(
        "a presence provider's edge forces only past the plain walk, and only when it differs from the belief",
        function()
            local I = H.ns.VirtualStateInternal
            local t = ctl.now
            assert.is_true(I.auras.n >= 1 and I.auras.exp0[1][1] <= t) -- aura 1 is believed down
            I.presence.onEdge(1, 1, true, t)
            assert.is_false(forced()) -- a clean walk answers for the player: the edge is not news
            ctl.auras.player.HELPFUL[1] = require("Game.State.helpers.fake_api").SECRET
            H.Fire("UNIT_AURA", "player") -- a secret entry: the walk is incomplete
            forced()
            I.presence.onEdge(1, 1, false, t)
            assert.is_false(forced()) -- agrees with the belief
            I.presence.onEdge(1, 1, true, t)
            assert.is_true(forced())
        end
    )

    it("the swing timer's event forces", function()
        H.Fire("PLAYER_SWING", 2.6, 0)
        assert.is_true(forced())
    end)

    it("our refused cast's SPELL_MISSED row forces; a resisted one, or another unit's, does not", function()
        local t, me, mf, hf = ctl.now, L.player, L.PLAYER_FLAGS, L.HOSTILE_FLAGS
        id = ww.IDS.battle_shout[1] -- any registered ability's id
        assert.is_true(me ~= "")
        L.Miss(t, "missed", me, mf, "Creature-9", hf, id, 1, "RESIST")
        L.Deliver()
        assert.is_false(forced())
        L.Miss(t, "missed", "Creature-7", hf, "Creature-9", hf, id, 1, "DODGE")
        L.Deliver()
        assert.is_false(forced())
        L.Miss(t, "missed", me, mf, "Creature-9", hf, id, 1, "DODGE")
        L.Deliver()
        assert.is_true(forced())
    end)

    it("our landed swing's row forces; a missed swing's does not", function()
        local t, me, mf, hf = ctl.now, L.player, L.PLAYER_FLAGS, L.HOSTILE_FLAGS
        L.Miss(t, "missed", me, mf, "Creature-9", hf, nil, 1, "DODGE", false)
        L.Deliver()
        assert.is_false(forced())
        L.Swing(t, "swing", me, mf, "Creature-9", hf, 0, "HIT", false)
        L.Deliver()
        assert.is_false(forced()) -- unpaid: the swing timer's own row, not a landed swing
        L.Swing(t, "swing", me, mf, "Creature-9", hf, 100, "HIT", false)
        L.Deliver()
        assert.is_true(forced())
    end)
end)
