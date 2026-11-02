-- tests/Forever/narrow_aura_spec.lua (perf phase 2, item 2.3): with performance.narrowUnitAura on, UNIT_AURA stops
-- being an all-unit client registration: the belief asks only for the units it walks (I.auras.index), applied at a
-- drain out of combat. UNIT_TARGET stays general: Attackers.lua reads target, focus and every nameplate.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("UNIT_AURA narrowing", function()
    local H, I, perf, calls

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        I, perf = H.ns.VirtualStateInternal, H.Hekili.DB.profile.performance
        calls = {}
        local frame = I.Events.frame
        local reg, regUnit = frame.RegisterEvent, frame.RegisterUnitEvent
        rawset(frame, "RegisterEvent", function(self, e)
            calls[#calls + 1] = e .. " general"
            return reg(self, e)
        end)
        rawset(frame, "RegisterUnitEvent", function(self, e, u1, u2)
            calls[#calls + 1] = e .. " " .. tostring(u1) .. " " .. tostring(u2)
            return regUnit(self, e, u1, u2)
        end)
    end)

    local function drain()
        H.ns.VirtualState.Drain(H.ctl.now)
    end

    local function switch(on)
        perf.narrowUnitAura = on
        H.Hekili:ProvidersChanged()
        drain()
    end

    it("the units the belief reads are player and target, and one source walks them", function()
        assert.are.same({ player = 1, target = 2 }, I.auras.index)
        assert.are.equal(1, #I.Sources.HANDLERS.UNIT_AURA)
    end)

    it("is off by default: no client call, the event stays general", function()
        assert.is_false(perf.narrowUnitAura)
        drain()
        assert.is_nil(I.Sources.UNITS.UNIT_AURA)
        assert.are.same({}, calls)
    end)

    it("on: registers for the two units once; off: general again", function()
        switch(true)
        assert.are.same({ "UNIT_AURA player target" }, calls)
        drain()
        assert.are.equal(1, #calls)
        switch(false)
        assert.are.same({ "UNIT_AURA player target", "UNIT_AURA general" }, calls)
    end)

    it("waits for the end of a fight", function()
        I.inCombat = true
        switch(true)
        assert.are.same({}, calls)
        I.inCombat = false
        drain()
        assert.are.same({ "UNIT_AURA player target" }, calls)
    end)

    it("a general subscriber keeps it general", function()
        switch(true)
        calls = {}
        I.Events.Subscribe({}, "UNIT_AURA")
        assert.are.same({ "UNIT_AURA general" }, calls)
    end)

    it("the player's and target's events still reach the walk and the core", function()
        switch(true)
        local f = H.ns.EngineFrame
        f.criticalUpdate = false
        H.Fire("UNIT_AURA", "player")
        assert.is_true(f.criticalUpdate)
    end)

    it("the option writes the profile and reaches the build's providers", function()
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        local key = H.Hekili.State.spec.key
        local args = H.Hekili.Options.args.packs.plugins.specializations[key].args.performance.args
        local pv = I.def.providers
        assert.is_false(args.narrowUnitAura.get())
        assert.is_false(pv.narrowUnitAura)
        args.narrowUnitAura.set(nil, true)
        assert.is_true(perf.narrowUnitAura)
        assert.is_true(pv.narrowUnitAura)
    end)
end)
