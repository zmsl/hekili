-- tests/Forever/dev_switches_spec.lua: the four experimental provider switches (damageMeter, cooldownViewer,
-- coalesceCooldown, narrowUnitAura) are dev-build only. A non-dev build (Hekili.IsDev unset) hides them in Options and
-- ignores a saved value: def.providers sees each off. The harness loads as a dev build (the TOC's @project-version@).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local NAMES = { "damageMeter", "cooldownViewer", "coalesceCooldown", "narrowUnitAura" }

describe("the dev-only switches", function()
    local H, pv, perf

    local function setup(dev)
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        H.Hekili.IsDev = dev
        pv = H.ns.VirtualStateInternal.def.providers
        perf = H.Hekili.DB.profile.performance
        for _, name in ipairs(NAMES) do
            perf[name] = true -- a profile saved by an older release, or a dev build
        end
        H.Hekili:ProvidersChanged()
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        local key = H.Hekili.State.spec.key
        return H.Hekili.Options.args.packs.plugins.specializations[key].args.performance.args
    end

    local function seen()
        return { pv.outcomes, pv.viewer, pv.coalesceCooldown, pv.narrowUnitAura }
    end

    it("a non-dev build hides all four and treats a saved true as off, without rewriting it", function()
        local args = setup(nil)
        for _, name in ipairs(NAMES) do
            assert.is_true(args[name].hidden, name)
            assert.is_true(perf[name], name)
        end
        assert.are.same({ "default", false, false, false }, seen())
        assert.is_falsy(args.experimentalHeader.hidden)
        assert.is_falsy(args.steadyIcons.hidden)
    end)

    it("a dev build shows them and honours them", function()
        local args = setup(true)
        for _, name in ipairs(NAMES) do
            assert.is_false(args[name].hidden, name)
        end
        assert.are.same({ "meter", true, true, true }, seen())
    end)
end)
