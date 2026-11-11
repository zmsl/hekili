-- tests/Forever/range_library_spec.lua (range plan R2, round 2): the vendored LibRangeCheck-3.0 itself answers the
-- target's range in the headless client (fake_api's spellbook, interact and item checks against the world distance),
-- read through the facade's RangeLib. A Hunter's minimum-range shots give it an 8 yd edge; a melee kit's edge at 5 yd.
-- Here, not in tests/Game: the boundary rule keeps class content out of the harness core.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local dlw = require("Forever.helpers.druid_loop_world")

local function boot(character, pack)
    local H = headless.new({ character = character, pack = pack })
    assert.are.same({}, H.loadErrors)
    H.ctl.level.target = 60
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(headless.cycle(H, H.ctl.now + 0.2))
    return H
end

-- The facade's RangeLib for the target at `yd` (a second past the last read: the library caches 0.1 s).
local function at(H, yd)
    H.ctl.distance.target = yd
    H.ctl.now = H.ctl.now + 1
    return { H.ns.Facade.RangeLib("target") }
end

describe("LibRangeCheck-3.0 in the headless client", function()
    for _, c in ipairs({
        { "Warrior", ww.character(), ww.PACK },
        { "Druid", dlw.Feral.character(), dlw.Feral.PACK },
    }) do
        it("puts a " .. c[1] .. " target at 3 yd within 5 yd and one at 7 yd past it", function()
            local H = boot(c[2], c[3])
            local three, seven = at(H, 3), at(H, 7)
            assert.is_true(
                three[2] ~= nil and three[2] <= 5,
                ("3 yd: %s-%s"):format(tostring(three[1]), tostring(three[2]))
            )
            assert.is_true(
                seven[1] ~= nil and seven[1] >= 5,
                ("7 yd: %s-%s"):format(tostring(seven[1]), tostring(seven[2]))
            )
            assert.are.same({}, H.errors)
        end)
    end
end)
