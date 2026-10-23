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
        -- uncached: once combat ends (the memo cleared) the same spell read on plain lines finds the text
        ns.ClearSecretTooltipMemo()
        H.ctl.tooltips[9001] = { lines = { { leftText = "Spell" }, { leftText = DISABLED } } }
        assert.is_true(ns.IsSpellDisabled(9001))
    end)

    it("scans forward too: a plain matching line is a hit, a nil leftText is no match", function()
        H.ctl.tooltips[9003] = { lines = { { leftText = DISABLED }, { leftText = "Spell" } } }
        assert.is_true(ns.FindStringInTooltip(DISABLED, 9003, "spell", false, true))
        H.ctl.tooltips[9004] = { lines = { {}, { leftText = "Spell" } } }
        assert.is_false(ns.FindStringInTooltip(DISABLED, 9004, "spell", false, true))
    end)

    it("reads a secret tooltip once per combat, then reads and caches a plain one after the clear", function()
        local store, calls = H.ctl.tooltips, 0
        H.ctl.tooltips = setmetatable({}, {
            __index = function(_, id)
                calls = calls + 1
                return store[id]
            end,
        })
        store[9011] = { lines = { { leftText = "Spell" }, { leftText = fake.SECRET } } }
        assert.is_false(ns.IsSpellDisabled(9011))
        assert.is_false(ns.IsSpellDisabled(9011))
        assert.are.equal(1, calls)
        ns.ClearSecretTooltipMemo()
        store[9011] = { lines = { { leftText = "Spell" } } }
        assert.is_false(ns.IsSpellDisabled(9011))
        assert.is_false(ns.IsSpellDisabled(9011))
        assert.are.equal(2, calls) -- read again after the clear, then cached
        H.ctl.tooltips = store
    end)

    it("caches a plain-line hit even when another line was secret", function()
        H.ctl.tooltips[9006] = { lines = { { leftText = fake.SECRET }, { leftText = DISABLED } } }
        assert.is_true(ns.IsSpellDisabled(9006))
        H.ctl.tooltips[9006] = nil
        assert.is_true(ns.IsSpellDisabled(9006)) -- the cached answer
    end)

    it("still finds the disabled text on plain lines and caches it", function()
        H.ctl.tooltips[9002] = { lines = { { leftText = "Spell" }, { leftText = DISABLED } } }
        assert.is_true(ns.IsSpellDisabled(9002))
        H.ctl.tooltips[9002] = { lines = { { leftText = "Spell" } } }
        assert.is_true(ns.IsSpellDisabled(9002)) -- the cached answer
    end)
end)
