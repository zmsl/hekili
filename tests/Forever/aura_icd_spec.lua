-- tests/Forever/aura_icd_spec.lua (central fix 2, gap 6): a proc aura's internal cooldown. A RegisterAura `icd`
-- (seconds) is measured from the aura's last application: `buff.<x>.icd_remains` counts it down as the sim advances
-- and `icd_ready` is true at 0; an aura without one, or never applied, is ready (an unknown ICD never blocks).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("a proc aura's internal cooldown", function()
    local H, st, aura

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        st = H.Hekili.State
        aura = H.Hekili.Class.auras.battle_shout
        st.reset("Primary", true)
    end)

    after_each(function()
        aura.icd = nil
    end)

    it("an aura without one reads ready, applied or not", function()
        local b = st.buff.battle_shout
        assert.are.same({ 0, true }, { b.icd_remains, b.icd_ready })
        st.applyBuff("battle_shout", 120)
        assert.are.same({ 0, true }, { b.icd_remains, b.icd_ready })
    end)

    it(
        "an aura declaring one: ready until applied, then counts down from the application as the sim advances",
        function()
            aura.icd = 10
            local b = st.buff.battle_shout
            assert.are.same({ 0, true }, { b.icd_remains, b.icd_ready })
            st.applyBuff("battle_shout", 3)
            assert.are.same({ 10, false }, { b.icd_remains, b.icd_ready })
            st.advance(4) -- the aura fades at 3: the ICD runs on from its application
            assert.is_false(b.up)
            assert.is_true(math.abs(b.icd_remains - 6) < 1e-6)
            st.removeBuff("battle_shout") -- a consumer's removal, twice: removing a down aura keeps its last application
            st.removeBuff("battle_shout")
            assert.is_false(b.icd_ready)
            st.advance(6)
            assert.are.same({ 0, true }, { b.icd_remains, b.icd_ready })
        end
    )

    -- The client shows the aura expiring at `expires` (nil: gone) at t; the state is reset at t + 0.1.
    local function at(t, expires)
        H.ctl.now = t
        H.ctl.auras.player.HELPFUL[1] = expires and { spellId = aura.id, expirationTime = expires, applications = 0 }
            or nil
        H.Fire("UNIT_AURA", "player")
        assert(headless.cycle(H, t + 0.1))
        st.reset("Primary", true)
        return st.buff.battle_shout.icd_remains
    end

    -- `icd` declared, then the belief rebuilt from the spec (Adapter's VS.SpecChanged reads it at build).
    local function declare()
        aura.icd = 10
        H.ns.VirtualState.SpecChanged()
    end

    it("from the client: an aura already up at the first clean walk (a reload) has an unknown gain: ready", function()
        declare()
        local t = H.ctl.now + 1
        assert.are.equal(0, at(t, t + 12))
        assert.are.same({}, H.errors)
    end)

    it("from the client: a plain read's application starts it, a refresh (a re-proc) restarts it", function()
        declare()
        local t = H.ctl.now + 1
        assert.are.equal(0, at(t - 0.5, nil)) -- the first clean walk: nothing up
        assert.is_true(math.abs(at(t, t + 120) - 9.9) < 0.05)
        assert.is_true(math.abs(at(t + 5, t + 125) - 9.9) < 0.05) -- refreshed at t + 5: 10 s from then
        assert.is_true(math.abs(at(t + 6, t + 125) - 8.9) < 0.05)
        assert.are.same({}, H.errors)
    end)
end)
