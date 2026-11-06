-- tests/Forever/loop_warrior_party_spec.lua: the Arms party report (#party), a file of its own so it runs in its own
-- process beside the 20-fight Arms gate; split out of loop_warrior_spec.lua, which keeps the boot, mapping and world
-- checks and the Arms gates.
local loop = require("Game.harness.loop")
local ww = require("Forever.helpers.warrior_world")

-- The party report (§5.2): reported, engine health gated; `make test-party`, not `make check` (D2).
describe("the headless Arms party report #party", function()
    it("Arms in a party of 5, a melee and a caster on our target, 10 fights: reported", function()
        local m = loop.tally(loop.new(ww), 10, { others = { "melee", "caster" } })
        print("\nArms party: " .. loop.line(m))
        assert.are.same({ 0, 0, 0 }, { m.errors, m.raises, m.selfCheck })
        assert.are.same({}, m.misses)
    end)
end)
