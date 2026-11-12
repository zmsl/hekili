-- tests/Forever/caster_range_spec.lua (caster range, L644; fable-decision-caster-range.md): the plate count's engaged
-- rule (Engine/Sim/Targets.lua's GUID plate loop). A ranged spec counts plates out to its 30 yd default, but beyond
-- 10 yd a plate counts only while UnitAffectingCombat answers a plain true; inside 10 yd, and the target, as before.
-- A melee spec (10 yd default) is unchanged. Plain-GUID plates, as tests/Forever/target_debug_alloc_spec.lua.
local fake = require("Game.State.helpers.fake_api")
local headless = require("Game.harness.headless")
local SECRET = fake.SECRET

-- An instance with both plate CVars on (Targets.lua's showNPs), set on the fake client before the Facade resolves
-- GetCVar, its target selected.
local function boot(C)
    local new = fake.new
    fake.new = function(...)
        local api, ctl = new(...)
        api.GetCVar = function()
            return "1"
        end
        return api, ctl
    end
    local ok, H = pcall(headless.new, { character = C.character(), pack = C.PACK })
    fake.new = new
    assert(ok, H)
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(headless.cycle(H, H.ctl.now + 0.2))
    return H
end

-- nameplate1 is the target; nameplate2.. are other mobs, each { yards (false: no position, range unknown), combat }.
local function plates(H, list)
    local ctl = H.ctl
    ctl.guid.nameplate1, ctl.exists.nameplate1, ctl.unitIs.nameplate1 = ctl.guid.target, true, "target"
    ctl.distance.nameplate1, ctl.unitCombat.nameplate1 = 30, false
    H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    for i, p in ipairs(list) do
        local unit = "nameplate" .. (i + 1)
        ctl.guid[unit], ctl.exists[unit] = "Creature-p" .. i, true
        ctl.distance[unit] = p[1] or nil
        ctl.unitCombat[unit] = p[2]
        H.Fire("NAME_PLATE_UNIT_ADDED", unit)
    end
end

-- One forced count, past LibRangeCheck's 0.1 s cache.
local function count(H)
    H.ctl.now = H.ctl.now + 0.2
    return H.ns.getNumberTargets(true)
end

describe("caster range: a ranged spec's plate count (Destruction, 30 yd default)", function()
    local wl = require("Forever.helpers.warlock_world")
    local H

    before_each(function()
        H = boot(wl.Destruction)
        assert.are.equal(30, H.Hekili.DB.profile.specs[wl.Destruction.SPEC].nameplateRange)
    end)

    it("counts the target only while the far plates are out of combat", function()
        plates(H, { { 30, false }, { 30, false } })
        assert.are.equal(1, count(H))
    end)

    it("counts far plates in combat, one by one", function()
        plates(H, { { 30, true }, { 30, true } })
        assert.are.equal(3, count(H))
        H.ctl.unitCombat.nameplate3 = false
        assert.are.equal(2, count(H))
    end)

    it("does not count far plates whose combat answer is secret, without an error", function()
        plates(H, { { 30, SECRET }, { 30, SECRET } })
        assert.are.equal(1, count(H))
        assert.are.same({}, H.errors)
    end)

    it("does not count a plate in combat beyond the radius", function()
        plates(H, { { 45, true } })
        assert.are.equal(1, count(H))
    end)

    it("counts a plate within 10 yd out of combat, as before", function()
        plates(H, { { 8, false } })
        assert.are.equal(2, count(H))
    end)

    it("counts a plate of unknown range only while it is in combat", function()
        plates(H, { { false, false } })
        assert.are.equal(1, count(H))
        H.ctl.unitCombat.nameplate2 = true
        assert.are.equal(2, count(H))
    end)

    it("says why a far plate is left out in the debug log", function()
        plates(H, { { 30, false } })
        H.Hekili.ActiveDebug, H.Hekili.TargetDebug = true, nil
        count(H)
        H.Hekili.ActiveDebug = false
        assert.is_truthy(tostring(H.Hekili.TargetDebug):find("Excluded: not in combat beyond 10 yd", 1, true))
    end)
end)

describe("caster range: a melee spec's plate count (10 yd default), unchanged", function()
    local ww = require("Forever.helpers.warrior_world")

    it("counts near plates out of combat and no far plate in combat", function()
        local H = boot({ character = ww.character, PACK = ww.PACK })
        assert.is_nil(H.Hekili.DB.profile.specs[ww.SPEC].nameplateRange)
        plates(H, { { 8, false }, { 8, false } })
        H.ctl.distance.nameplate1 = 8
        assert.are.equal(3, count(H))
        for i = 1, 3 do
            H.ctl.distance["nameplate" .. i], H.ctl.unitCombat["nameplate" .. i] = 30, true
        end
        assert.are.equal(1, count(H))
    end)
end)
