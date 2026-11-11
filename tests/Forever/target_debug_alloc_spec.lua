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

    it("keeps the log, a line per plate, while debug is on", function()
        plates(15)
        H.Hekili.ActiveDebug = true
        H.Hekili.TargetDebug = nil
        H.ns.getNumberTargets(true)
        assert.is_truthy(tostring(H.Hekili.TargetDebug):find("Nameplates are enabled", 1, true))
        assert.is_true(select(2, H.Hekili.TargetDebug:gsub("nameplate", "")) > 0, "no plate line in the log")
    end)
end)
