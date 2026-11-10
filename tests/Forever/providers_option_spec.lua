-- tests/Forever/providers_option_spec.lua (providers plan, Tasks 4 and 7; cdm-default plan Task 6, decision 107): the
-- Cooldown Manager is always on and the damage meter is never the Outcomes provider; neither has an option and a saved
-- value of either is ignored. Hekili.cdmOff (debug-only, undocumented in the panel) turns the viewer off for the
-- session through Hekili:ProvidersChanged (the core's, Engine/Schema/Tracked.lua); the belief swaps at its next drain
-- out of combat, at the fight's end in combat, and never rebuilds (its records stay).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the providers, always on (no option)", function()
    local H, I, perf

    local function drain()
        H.ns.VirtualState.Drain(H.ctl.now)
    end

    local function boot(dev, saved)
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        H.Hekili.IsDev = dev
        I = H.ns.VirtualStateInternal
        perf = H.Hekili.DB.profile.performance
        for k, v in pairs(saved or {}) do
            perf[k] = v -- a profile saved by an older build
        end
        H.Hekili:ProvidersChanged()
        drain()
    end

    local function perfArgs()
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        local key = H.Hekili.State.spec.key
        return H.Hekili.Options.args.packs.plugins.specializations[key].args.performance.args
    end

    it("providersOf gives viewer true in a release build with any saved value", function()
        for _, dev in ipairs({ false, true }) do
            for _, saved in ipairs({ true, false }) do
                boot(dev or nil, { cooldownViewer = saved })
                assert.is_true(I.def.providers.viewer, tostring(dev) .. "/" .. tostring(saved))
                assert.are.same({ "router", true }, { I.presence.name, I.presenceViewer })
            end
        end
    end)

    it("no Cooldown Manager option exists in the options table", function()
        boot(true)
        local args = perfArgs()
        assert.is_nil(args.cooldownViewer)
        assert.is_nil(H.Hekili.DB.defaults.profile.performance.cooldownViewer)
    end)

    it("a saved performance.cooldownViewer = false is ignored", function()
        boot(nil, { cooldownViewer = false })
        assert.are.same({ true, true, false }, { I.def.providers.viewer, I.presenceViewer, perf.cooldownViewer })
    end)

    it("no damage meter option exists in the options table", function()
        boot(true)
        local args = perfArgs()
        assert.is_nil(args.damageMeter)
        assert.is_nil(H.Hekili.DB.defaults.profile.performance.damageMeter)
    end)

    it("a saved performance.damageMeter = true is ignored without an error", function()
        for _, dev in ipairs({ true, false }) do
            boot(dev or nil, { damageMeter = true })
            assert.are.same(
                { "default", "default", true },
                { I.def.providers.outcomes, I.outcomes.name, perf.damageMeter }
            )
            assert.are.same({}, H.errors)
        end
    end)

    -- the rate switches coalesceCooldown and narrowUnitAura, removed with their code paths (owner 2026-11-10)
    it("a saved coalesceCooldown or narrowUnitAura is ignored: no option, every event runs at once", function()
        for _, dev in ipairs({ true, false }) do
            boot(dev or nil, { coalesceCooldown = true, narrowUnitAura = true })
            local args, defaults = perfArgs(), H.Hekili.DB.defaults.profile.performance
            for _, name in ipairs({ "coalesceCooldown", "narrowUnitAura" }) do
                assert.is_nil(args[name], name)
                assert.is_nil(defaults[name], name)
                assert.is_nil(I.def.providers[name], name)
            end
            assert.is_nil(args.experimentalHeader)
            assert.is_nil(I.Sources.UNITS.UNIT_AURA) -- UNIT_AURA stays registered for every unit
            local C, read, reads = I.api.C_Spell, I.api.C_Spell.GetSpellCooldown, 0
            C.GetSpellCooldown = function(spell)
                reads = reads + 1
                return read(spell)
            end
            H.Fire("SPELL_UPDATE_COOLDOWN") -- the boot's edges
            reads = 0
            H.Fire("SPELL_UPDATE_COOLDOWN")
            local one = reads
            assert.is_true(one > 0)
            H.Fire("SPELL_UPDATE_COOLDOWN")
            H.Fire("SPELL_UPDATE_COOLDOWN")
            assert.are.equal(3 * one, reads) -- each event walks at once; the frame's OnUpdate walks none
            local frame = I.Events.frame
            frame.__scripts.OnUpdate(frame, 0.016)
            assert.are.equal(3 * one, reads)
            assert.are.same({}, H.errors)
        end
    end)

    it(
        "Hekili.cdmOff = true then ProvidersChanged gives viewer false (out of combat at once, else at combat end)",
        function()
            boot(nil)
            assert.is_true(I.presenceViewer)
            H.Hekili.cdmOff = true
            H.Hekili:ProvidersChanged()
            assert.is_false(I.def.providers.viewer)
            drain()
            assert.are.same({ "router", false }, { I.presence.name, I.presenceViewer })
            H.Hekili.cdmOff = nil
            I.inCombat = true
            H.Hekili:ProvidersChanged()
            drain()
            assert.is_false(I.presenceViewer) -- in combat: waits for the fight's end
            I.inCombat = false
            H.Fire("PLAYER_REGEN_ENABLED")
            assert.are.same({ "router", true }, { I.presence.name, I.presenceViewer })
        end
    )

    it("a toggle back before the fight ends cancels the pending swap", function()
        boot(nil)
        I.inCombat = true
        H.Hekili.cdmOff = true
        H.Hekili:ProvidersChanged()
        drain()
        H.Hekili.cdmOff = nil
        H.Hekili:ProvidersChanged()
        drain()
        I.inCombat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(I.presenceViewer)
    end)

    it("a swap keeps the belief's records: no rebuild", function()
        boot(nil)
        local clears, clear = 0, I.ClearRecords
        I.ClearRecords = function()
            clears = clears + 1
            return clear()
        end
        H.Hekili.cdmOff = true
        H.Hekili:ProvidersChanged()
        drain()
        assert.are.same({ false, 0 }, { I.presenceViewer, clears })
    end)
end)
