-- tests/Forever/providers_option_spec.lua (providers plan, Tasks 4 and 7; border batch 3, E17): the experimental
-- damage-meter switch (profile.performance.damageMeter) and the Cooldown Manager switch (cooldownViewer) reach the
-- build's def.providers through Hekili:ProvidersChanged (the core's, Engine/Schema/Tracked.lua); the belief swaps at
-- its next drain out of combat, at the fight's end in combat, and never rebuilds (its records stay).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the providers options", function()
    local H, I, perf

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        I = H.ns.VirtualStateInternal
        perf = H.Hekili.DB.profile.performance
    end)

    local function drain()
        H.ns.VirtualState.Drain(H.ctl.now)
    end

    it("the setters write the profile and tell the core; the belief swaps at its next drain", function()
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        local key = H.Hekili.State.spec.key
        local args = H.Hekili.Options.args.packs.plugins.specializations[key].args.performance.args
        args.damageMeter.set(nil, true)
        args.cooldownViewer.set(nil, true)
        local pv = I.def.providers
        assert.are.same({ "meter", "router", true }, { pv.outcomes, pv.presence, pv.viewer })
        assert.are.same({ "default", false }, { I.outcomes.name, I.presenceViewer }) -- not before the drain
        drain()
        assert.are.same(
            { "meter", true, true, true },
            { I.outcomes.name, I.presenceViewer, perf.damageMeter, perf.cooldownViewer }
        )
    end)

    it("default off: the build injects the Default outcomes and the router with no leaf", function()
        assert.are.same(
            { "default", false, "router", false },
            { I.outcomes.name, perf.damageMeter, I.presence.name, I.presenceViewer }
        )
    end)

    it("on, out of combat: the meter at the next drain; in combat: at combat end", function()
        perf.damageMeter = true
        H.Hekili:ProvidersChanged()
        assert.are.equal("default", I.outcomes.name)
        drain()
        assert.are.equal("meter", I.outcomes.name)
        perf.damageMeter = false
        I.inCombat = true
        H.Hekili:ProvidersChanged()
        drain()
        assert.are.equal("meter", I.outcomes.name)
        I.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal("default", I.outcomes.name)
    end)

    it("a toggle back before the fight ends cancels the pending swap", function()
        I.inCombat = true
        perf.damageMeter = true
        H.Hekili:ProvidersChanged()
        drain()
        perf.damageMeter = false
        H.Hekili:ProvidersChanged()
        drain()
        I.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal("default", I.outcomes.name)
    end)

    it("a swap keeps the belief's records: no rebuild", function()
        local clears, clear = 0, I.ClearRecords
        I.ClearRecords = function()
            clears = clears + 1
            return clear()
        end
        perf.damageMeter = true
        H.Hekili:ProvidersChanged()
        drain()
        assert.are.same({ "meter", 0 }, { I.outcomes.name, clears })
    end)

    it(
        "the viewer switch gives the router its leaf at the next drain out of combat; in combat at combat end",
        function()
            assert.are.same({ "router", false, false }, { I.presence.name, perf.cooldownViewer, I.presenceViewer })
            perf.cooldownViewer = true
            H.Hekili:ProvidersChanged()
            drain()
            assert.is_true(I.presenceViewer)
            perf.cooldownViewer = false
            I.inCombat = true
            H.Hekili:ProvidersChanged()
            drain()
            assert.is_true(I.presenceViewer)
            I.inCombat = false
            H.Fire("PLAYER_REGEN_ENABLED")
            assert.are.equal("router", I.presence.name)
            assert.is_false(I.presenceViewer)
        end
    )
end)
