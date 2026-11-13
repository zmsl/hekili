-- tests/Forever/target_debug_alloc_spec.lua: ns.getNumberTargets( true ) builds the nameplate log (Hekili.TargetDebug,
-- read by Snapshot.lua's "detected_targets") only while a debug pass is on (Hekili.ActiveDebug). With plates on and
-- debug off it allocates nothing per plate; with debug on the log carries a line per plate.
local fake = require("Game.State.helpers.fake_api")
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("Engine/Sim/Targets.lua's nameplate log", function()
    local H

    before_each(function()
        -- both plate CVars on (Targets.lua's showNPs), set on the fake client before the Facade resolves GetCVar
        local new = fake.new
        fake.new = function(...)
            local api, ctl = new(...)
            api.GetCVar = function()
                return "1"
            end
            return api, ctl
        end
        local ok, h = pcall(headless.new, { character = ww.character(), pack = ww.PACK })
        fake.new = new
        assert(ok, h)
        H = h
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert(headless.cycle(H, H.ctl.now + 0.2))
    end)

    local function plates(n)
        for i = 1, n do
            local unit = "nameplate" .. i
            -- 3 yd: a position, so LibRangeCheck runs its checks for the plate (no position answers unknown at once)
            H.ctl.guid[unit], H.ctl.exists[unit], H.ctl.distance[unit] = "Creature-p" .. i, true, 3
            H.Fire("NAME_PLATE_UNIT_ADDED", unit)
        end
    end

    -- Bytes of one forced count with the collector stopped, after a warm-up call; each call past LibRangeCheck's 0.1 s
    -- cache, so the library checks every plate again.
    local function bytes()
        H.ctl.now = H.ctl.now + 0.2
        H.ns.getNumberTargets(true)
        collectgarbage("collect")
        collectgarbage("stop")
        H.ctl.now = H.ctl.now + 0.2
        local b = collectgarbage("count")
        H.ns.getNumberTargets(true)
        local d = (collectgarbage("count") - b) * 1024
        collectgarbage("restart")
        return d
    end

    it("allocates nothing per count at 0, 5 and 15 plates while debug is off", function()
        local got = {}
        H.Hekili.ActiveDebug = false
        for _, n in ipairs({ 0, 5, 15 }) do
            plates(n - (n == 15 and 5 or 0))
            got[#got + 1] = bytes()
        end
        print("bytes per count at 0/5/15 plates: " .. table.concat(got, "/"))
        assert.are.same({ 0, 0, 0 }, got, "bytes per count at 0/5/15 plates")
    end)

    -- range plan R2: the plates' range reads go through the facade row; counts and bytes as at the base (982b7d2f0)
    it("counts 0, 5 and 15 plain-GUID plates as before, allocating nothing per count", function()
        local counts, got = {}, {}
        H.Hekili.ActiveDebug = false
        local calls = H.ctl.rangeLibCalls
        for _, n in ipairs({ 0, 5, 15 }) do
            plates(n) -- re-adding a plate already up changes nothing
            counts[#counts + 1] = H.ns.getNumberTargets(true)
            got[#got + 1] = bytes()
        end
        print("counts at 0/5/15 plates: " .. table.concat(counts, "/"))
        assert.are.same({ 1, 6, 16 }, counts)
        assert.is_true(H.ctl.rangeLibCalls >= calls + 20 * 3, "the library checked the plates") -- 5 + 15, 3 counts each
        assert.are.same({ 0, 0, 0 }, got, "bytes per count at 0/5/15 plates")
    end)

    -- caster range (L644): the engaged rule beyond 10 yd (a radius of 40, as a ranged spec's default) reads each far
    -- plate's combat answer and allocates nothing, in combat or out
    it("counts 15 far plates by their combat answer, allocating nothing per count", function()
        H.Hekili.ActiveDebug = false
        H.Hekili.DB.profile.specs[ww.SPEC].nameplateRange = 40
        plates(15)
        local counts, got = {}, {}
        for _, engaged in ipairs({ true, false }) do
            for i = 1, 15 do
                H.ctl.distance["nameplate" .. i], H.ctl.unitCombat["nameplate" .. i] = 30, engaged
            end
            counts[#counts + 1] = H.ns.getNumberTargets(true)
            got[#got + 1] = bytes()
        end
        assert.are.same({ 16, 1 }, counts)
        assert.are.same({ 0, 0 }, got, "bytes per count at 15 far plates, in combat and out")
    end)

    it("keeps the log, a line per plate, while debug is on", function()
        plates(15)
        H.Hekili.ActiveDebug = true
        H.Hekili.TargetDebug = nil
        H.ns.getNumberTargets(true)
        assert.is_truthy(tostring(H.Hekili.TargetDebug):find("Nameplates are enabled", 1, true))
        assert.is_true(select(2, H.Hekili.TargetDebug:gsub("nameplate", "")) > 0, "no plate line in the log")
    end)

    -- T1: under the Map restriction the plates are kept by token; a count and each plate handler allocate nothing.
    it("allocates nothing per count at 0, 5 and 15 token plates (Map), nor per plate event", function()
        local got, counts = {}, {}
        H.Hekili.ActiveDebug = false
        H.ctl.guid.target, H.ctl.unitIs.target = fake.SECRET, "nameplate1"
        local function tokens(from, n)
            for i = from, n do
                local unit = "nameplate" .. i
                H.ctl.guid[unit], H.ctl.exists[unit], H.ctl.distance[unit] = fake.SECRET, true, 3
                H.Fire("NAME_PLATE_UNIT_ADDED", unit)
            end
        end
        for _, n in ipairs({ 0, 5, 15 }) do
            tokens(1, n)
            counts[#counts + 1] = H.ns.getNumberTargets(true)
            got[#got + 1] = bytes()
        end
        print("token counts at 0/5/15 plates: " .. table.concat(counts, "/") .. "; bytes " .. table.concat(got, "/"))
        assert.are.same({ 1, 5, 15 }, counts)
        assert.are.same({ 0, 0, 0 }, got, "bytes per count at 0/5/15 token plates")
        -- a REMOVED, an ADDED and a friendly flag on token plates, the second round measured (the first warms up)
        local function events()
            H.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate6")
            H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate6")
            H.Fire("UNIT_FLAGS", "nameplate8")
        end
        H.ctl.friendly.nameplate8 = true
        events()
        collectgarbage("collect")
        collectgarbage("stop")
        local b = collectgarbage("count")
        events()
        local d = (collectgarbage("count") - b) * 1024
        collectgarbage("restart")
        H.ctl.friendly.nameplate8 = nil
        assert.is_nil(H.Hekili.npTokens.nameplate8)
        assert.are.equal(0, d, "bytes per plate event")
    end)

    -- integ/dot review M2: token plates past 10 yd with a ranged radius reach the engaged rule's combat read; a count
    -- allocates nothing, in combat or out (the target's plate is exempt, so out of combat counts 1)
    it("counts 15 far token plates (Map) by their combat answer, allocating nothing per count", function()
        H.Hekili.ActiveDebug = false
        H.Hekili.DB.profile.specs[ww.SPEC].nameplateRange = 40
        H.ctl.guid.target, H.ctl.unitIs.target = fake.SECRET, "nameplate1"
        for i = 1, 15 do
            local unit = "nameplate" .. i
            H.ctl.guid[unit], H.ctl.exists[unit], H.ctl.distance[unit] = fake.SECRET, true, 30
            H.Fire("NAME_PLATE_UNIT_ADDED", unit)
        end
        local counts, got = {}, {}
        for _, engaged in ipairs({ true, false }) do
            for i = 1, 15 do
                H.ctl.unitCombat["nameplate" .. i] = engaged
            end
            H.ns.getNumberTargets(true) -- a fall is held one update (T1)
            counts[#counts + 1] = H.ns.getNumberTargets(true)
            got[#got + 1] = bytes()
        end
        assert.are.same({ 15, 1 }, counts)
        assert.are.same({ 0, 0 }, got, "bytes per count at 15 far token plates, in combat and out")
    end)
end)
