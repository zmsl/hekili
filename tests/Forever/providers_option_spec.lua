-- tests/Forever/providers_option_spec.lua (providers plan, Tasks 4 and 7): the experimental damage-meter switch
-- (profile.performance.damageMeter) and the Cooldown Manager switch (cooldownViewer) reach the build's def.providers
-- and Hekili:ProvidersChanged (Options' own, calling Hekili.Virtual.State.SetProviders: audit E17); a change in
-- combat waits for the fight's end (VS.SetProviders).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the providers options", function()
    it(
        "the setters apply the toggles through Hekili.Virtual.State.SetProviders, not through the belief's glue",
        function()
            local H = headless.new({ character = ww.character(), pack = ww.PACK })
            local I = H.ns.VirtualStateInternal
            H.Hekili:EmbedSpecOptions()
            H.Hekili:EmbedPackOptions()
            local key = H.Hekili.State.spec.key
            local args = H.Hekili.Options.args.packs.plugins.specializations[key].args.performance.args
            args.damageMeter.set(nil, true)
            args.cooldownViewer.set(nil, true)
            assert.are.same({ "meter", true, true, true }, {
                I.outcomes.name,
                I.presenceViewer,
                H.Hekili.DB.profile.performance.damageMeter,
                H.Hekili.DB.profile.performance.cooldownViewer,
            })
            local src = assert(io.open("src/Hekili/Game/State/Adapter.lua")):read("*a")
            assert.is_nil(src:find("ProvidersChanged", 1, true))
        end
    )

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

    it("the viewer switch gives the router its leaf, out of combat at once; in combat at combat end", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        local I = H.ns.VirtualStateInternal
        assert.are.same(
            { "router", false, false },
            { I.presence.name, H.Hekili.DB.profile.performance.cooldownViewer, I.presenceViewer }
        )
        H.Hekili.DB.profile.performance.cooldownViewer = true
        H.Hekili:ProvidersChanged()
        assert.is_true(I.presenceViewer)
        H.Hekili.DB.profile.performance.cooldownViewer = false
        I.inCombat = true
        H.Hekili:ProvidersChanged()
        assert.is_true(I.presenceViewer)
        I.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal("router", I.presence.name)
        assert.is_false(I.presenceViewer)
    end)
end)
