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

    -- the 8 yd checker, in each of the library's harm lists
    local function inner(list)
        for _, rc in ipairs(list) do
            if rc.range == 8 and rc.minRange == nil and rc.info:find("^spell:75:") then
                return rc.checker
            end
        end
    end

    it(
        "adds the within-minRange checker to both checker lists; a spell with no answer defers to the next-larger",
        function()
            local C = hw.BeastMastery
            local H = boot(C.character(), C.PACK)
            local lib = H.env.LibStub("LibRangeCheck-3.0")
            at(H, 6) -- a read builds the checker lists (the library's init)
            for _, list in ipairs({ lib.harmRC, lib.harmRCInCombat }) do
                local check = inner(list)
                assert.is_function(check)
                H.ctl.ranges[75] = { 8, 35 }
                H.ctl.distance.target = 6
                assert.is_truthy(check("target"))
                H.ctl.distance.target = 9
                assert.is_falsy(check("target"))
                H.ctl.distance.target = 40 -- past Auto Shot's 35: out of range there too, but past the reach checker
                assert.is_falsy(check("target"))
                H.ctl.ranges[75] = { 8, 0 } -- the spell answers nil (no range check, e.g. no ranged weapon)
                local larger -- the next-larger checker in this list (harmRC: the 10 yd item; in combat: Auto Shot's)
                for i = #list, 1, -1 do
                    if list[i].range > 8 then
                        larger = list[i].checker
                        break
                    end
                end
                for _, yd in ipairs({ 3, 9, 12, 30, 40 }) do
                    H.ctl.distance.target = yd
                    assert.are.equal(not larger("target"), not check("target"), yd .. " yd: not the next-larger's")
                end
            end
        end
    )

    -- getRangeWithCheckerList binary-searches the list: within a smaller range must imply within every larger one
    it("keeps every harm list monotone whether Auto Shot answers in range, out of range or nothing", function()
        local C = hw.BeastMastery
        local H = boot(C.character(), C.PACK)
        local lib = H.env.LibStub("LibRangeCheck-3.0")
        at(H, 6)
        for _, r in ipairs({ { 8, 35 }, { 8, 0 } }) do
            H.ctl.ranges[75] = r
            for _, list in ipairs({ lib.harmRC, lib.harmRCInCombat }) do
                for yd = 0, 40, 0.5 do
                    H.ctl.distance.target = yd
                    local seenFalse
                    for i = 1, #list do -- largest range first
                        local within = list[i].checker("target") and true or false
                        assert.is_false(
                            within and seenFalse == true,
                            ("%s yd, Auto Shot %d-%d: %s within after a smaller miss"):format(
                                yd,
                                r[1],
                                r[2],
                                list[i].info
                            )
                        )
                        seenFalse = seenFalse or not within
                    end
                end
            end
        end
    end)

    it("reads a Hunter whose Auto Shot cannot check (no ranged weapon) as in melee at 3 yd", function()
        local C = hw.Survival
        local H = boot(C.character(), C.PACK)
        at(H, 20)
        H.ctl.ranges[75] = { 8, 0 }
        assert.are.same({ 0, 5 }, at(H, 3))
        local six, nine = at(H, 6), at(H, 9)
        assert.is_true(six[1] == 5 and six[2] >= 8, ("6 yd: %s-%s"):format(tostring(six[1]), tostring(six[2])))
        assert.is_true(nine[1] == 5 and nine[2] >= 8, ("9 yd: %s-%s"):format(tostring(nine[1]), tostring(nine[2])))
        assert.are.same({}, H.errors)
    end)
end)
