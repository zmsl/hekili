-- tests/Forever/range_library_spec.lua (range plan R2, round 2): the vendored LibRangeCheck-3.0 itself answers the
-- target's range in the headless client (fake_api's spellbook, interact and item checks against the world distance),
-- read through the facade's RangeLib. A Hunter's minimum-range shots give it an 8 yd edge; a melee kit's edge at 5 yd.
-- Here, not in tests/Game: the boundary rule keeps class content out of the harness core.
local headless = require("Game.harness.headless")
local hw = require("Forever.helpers.hunter_world")
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

    -- Hekili Forever's library patch (upstream PR pending): a minimum-range spell (Auto Shot 8-35) adds a "within
    -- minRange" checker, so the library marks 8 yd beside its 5 and 10 yd items.
    for _, name in ipairs({ "BeastMastery", "Marksmanship", "Survival" }) do
        it("gives a " .. name .. " Hunter's target an 8 yd edge from Auto Shot's minimum range", function()
            local C = hw[name]
            local H = boot(C.character(), C.PACK)
            local three, six, nine = at(H, 3), at(H, 6), at(H, 9)
            assert.are.same({ 0, 5 }, three)
            assert.are.same({ 5, 8 }, six)
            assert.are.same({ 8, 10 }, nine)
            assert.are.same({}, H.errors)
        end)
    end

    it("adds the within-minRange checker to both checker lists, true only on a definite out-of-range answer", function()
        local C = hw.BeastMastery
        local H = boot(C.character(), C.PACK)
        local lib = H.env.LibStub("LibRangeCheck-3.0")
        at(H, 6) -- a read builds the checker lists (the library's init)
        local function inner(list)
            for _, rc in ipairs(list) do
                if rc.range == 8 and rc.minRange == nil and rc.info:find("^spell:75:") then
                    return rc.checker
                end
            end
        end
        local check = inner(lib.harmRC)
        assert.is_function(check)
        assert.are.equal(check, inner(lib.harmRCInCombat))
        H.ctl.distance.target = 6
        assert.is_truthy(check("target"))
        H.ctl.distance.target = 9
        assert.is_falsy(check("target"))
        H.ctl.distance.target = 40 -- past Auto Shot's 35: out of range there too, but past the reach checker
        assert.is_falsy(check("target"))
        H.ctl.distance.target = 6
        H.ctl.ranges[75] = { 8, 0 } -- the spell answers nil (no range check, e.g. no ranged weapon): not within
        assert.is_falsy(check("target"))
    end)
end)
