-- tests/Game/harness/tooltip_secret_spec.lua (central fix 33): on Forever a spell tooltip's line text is secret in
-- combat, so Engine/Sim/Utils.lua's tooltip scan reads a secret line as no match (never indexing or comparing it) and
-- IsSpellDisabled leaves an answer computed over a secret line uncached, so a later plain read can still fill it.
local headless = require("Game.harness.headless")
local fake = require("Game.State.helpers.fake_api")

describe("the tooltip scan on secret line text", function()
    local H, ns, DISABLED

    setup(function()
        H = headless.new()
        ns = H.ns
        DISABLED = H.env.SPELL_FAILED_NOT_HERE
    end)

    it("reads a secret leftText as not disabled, without error, and caches nothing", function()
        H.ctl.tooltips[9001] = { lines = { { leftText = "Spell" }, { leftText = fake.SECRET } } }
        assert.is_false(ns.IsSpellDisabled(9001))
        assert.is_false(ns.FindStringInTooltip(DISABLED, 9001, "spell", false, true))
        -- uncached: the same spell read out of combat now finds the text
        H.ctl.tooltips[9001] = { lines = { { leftText = "Spell" }, { leftText = DISABLED } } }
        assert.is_true(ns.IsSpellDisabled(9001))
    end)

    it("still finds the disabled text on plain lines and caches it", function()
        H.ctl.tooltips[9002] = { lines = { { leftText = "Spell" }, { leftText = DISABLED } } }
        assert.is_true(ns.IsSpellDisabled(9002))
        H.ctl.tooltips[9002] = { lines = { { leftText = "Spell" } } }
        assert.is_true(ns.IsSpellDisabled(9002)) -- the cached answer
    end)
end)
