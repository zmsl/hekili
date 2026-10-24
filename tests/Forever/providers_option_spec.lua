-- tests/Forever/providers_option_spec.lua (providers plan, Task 4): the experimental damage-meter switch
-- (profile.performance.damageMeter) reaches the build's def.providers and Hekili:ProvidersChanged; a change in combat
-- waits for the fight's end (VS.SetProviders).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the providers options", function()
    it("default off: the build injects the Default outcomes and the router with no leaf", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        local I = H.ns.VirtualStateInternal
        assert.are.same(
            { "default", false, "router", false },
            { I.outcomes.name, H.Hekili.DB.profile.performance.damageMeter, I.presence.name, I.presenceViewer }
        )
    end)

    it("on, out of combat: the meter at once; in combat: at combat end", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        local I = H.ns.VirtualStateInternal
        H.Hekili.DB.profile.performance.damageMeter = true
        H.Hekili:ProvidersChanged()
        assert.are.equal("meter", I.outcomes.name)
        H.Hekili.DB.profile.performance.damageMeter = false
        I.inCombat = true
        H.Hekili:ProvidersChanged()
        assert.are.equal("meter", I.outcomes.name)
        I.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal("default", I.outcomes.name)
    end)
end)
