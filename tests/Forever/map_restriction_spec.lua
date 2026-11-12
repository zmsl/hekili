-- tests/Forever/map_restriction_spec.lua: the Map addon restriction (the owner's FR-1 run, 2026-11-05) makes unit
-- identity secret: UnitGUID and UnitIsUnit answer secrets, and an event's GUID or name payload is secret. Engine/Sim/
-- Targets.lua's nameplate and flag handlers raised on it in game; a secret identity is unknown, never a key, a compare
-- or a truth test. The client's secret-key errors come from fake.strictKeys; a truth test can't be trapped in 5.1, so
-- its case asserts the outcome a secret read as "true" would miss.
local fake = require("Game.State.helpers.fake_api")
local headless = require("Game.harness.headless")

local SECRET = fake.SECRET

describe("Engine/Sim/Targets.lua under a secret unit identity", function()
    local H, npUnits, npGUIDs

    setup(function()
        H = headless.new()
        assert.are.same({}, H.loadErrors)
        npUnits, npGUIDs = fake.strictKeys(H.Hekili.npUnits), fake.strictKeys(H.Hekili.npGUIDs)
    end)

    before_each(function()
        for k in pairs(npUnits) do
            npUnits[k] = nil
        end
        for k in pairs(npGUIDs) do
            npGUIDs[k] = nil
        end
        for i = #H.errors, 1, -1 do
            H.errors[i] = nil
        end
        local ctl = H.ctl
        ctl.guid.nameplate1, ctl.exists.nameplate1 = "Creature-p1", true
        ctl.friendly.nameplate1, ctl.unitIs.nameplate1 = nil, nil
    end)

    local function clean()
        assert.are.same({}, H.errors)
        assert.are.equal(0, fake.secretsIn(npUnits))
        assert.are.equal(0, fake.secretsIn(npGUIDs))
    end

    it("NAME_PLATE_UNIT_ADDED with a secret GUID keys nothing", function()
        H.ctl.guid.nameplate1 = SECRET
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        clean()
        assert.is_nil(npGUIDs.nameplate1)
    end)

    it("NAME_PLATE_UNIT_REMOVED with a secret GUID drops the plate it stored while plain", function()
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        assert.are.equal("nameplate1", npUnits["Creature-p1"])
        H.ctl.guid.nameplate1 = SECRET
        H.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        clean()
        assert.is_nil(npUnits["Creature-p1"])
        assert.is_nil(npGUIDs.nameplate1)
    end)

    it("NAME_PLATE_UNIT_REMOVED with a secret GUID and nothing stored raises nothing", function()
        H.ctl.guid.nameplate1 = SECRET
        H.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        clean()
    end)

    it("UNIT_FLAGS: a secret UnitIsUnit is unknown, not the player; a friendly plate is dropped", function()
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.ctl.friendly.nameplate1, H.ctl.unitIs.nameplate1 = true, SECRET
        H.Fire("UNIT_FLAGS", "nameplate1")
        clean()
        assert.is_nil(npUnits["Creature-p1"])
        assert.is_nil(npGUIDs.nameplate1)
    end)

    it("UNIT_FLAGS: a friendly plate whose GUID turned secret is dropped by the GUID stored while plain", function()
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        H.ctl.friendly.nameplate1, H.ctl.guid.nameplate1 = true, SECRET
        H.Fire("UNIT_FLAGS", "nameplate1")
        clean()
        assert.is_nil(npUnits["Creature-p1"])
        assert.is_nil(npGUIDs.nameplate1)
    end)

    it("UNIT_FLAGS: a friendly unit with a secret GUID and none stored raises nothing", function()
        H.ctl.friendly.nameplate1, H.ctl.guid.nameplate1 = true, SECRET
        H.Fire("UNIT_FLAGS", "nameplate1")
        clean()
    end)
end)

-- The sweep's engine sites (the report's table): with the facade answering a secret identity as nil, nothing
-- concatenates or formats that nil.
describe("the engine's identity reads under a secret identity", function()
    local ww = require("Forever.helpers.warrior_world")
    local H

    setup(function()
        -- both plate CVars on (Targets.lua's showNPs), set before the Facade resolves GetCVar (target_debug_alloc_spec)
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

    it("target.unit names an unknown target instead of concatenating its secret GUID", function()
        local S = H.Hekili.State
        H.ctl.guid.target = SECRET
        local ok, err = pcall(function()
            S.args.cycle_target = 1
            assert.are.equal("cycle", S.target.unit)
            S.args.cycle_target = nil
            S.args.target = "x"
            assert.are.equal("unknown", S.target.unit)
            S.args.target = nil
            assert.are.equal("unknown", S.target.unit)
        end)
        S.args.cycle_target, S.args.target = nil, nil
        H.ctl.guid.target = "Creature-1"
        assert(ok, err)
    end)

    it("the nameplate log writes a plate whose name is secret", function()
        for i = 1, 3 do
            local unit = "nameplate" .. i
            H.ctl.guid[unit], H.ctl.exists[unit], H.ctl.names[unit] = "Creature-p" .. i, true, SECRET
            H.Fire("NAME_PLATE_UNIT_ADDED", unit)
        end
        H.ctl.names.target = SECRET
        H.Hekili.ActiveDebug, H.Hekili.TargetDebug = true, nil
        local ok, err = pcall(H.ns.getNumberTargets, true)
        H.Hekili.ActiveDebug = false
        H.ctl.names.target = nil
        assert(ok, err)
        assert.is_truthy(tostring(H.Hekili.TargetDebug):find("nameplate1", 1, true))
    end)
end)

-- The owner's dungeon symptom (Ragefire Chasm, 2026-11-05: Map restriction, target GUID and name secret, in combat):
-- Hekili seemed broken and took no snapshot. The update loop and the snapshot run through with every identity read
-- secret: the target, its target, the plates, their names, and UnitIsUnit between tokens.
describe("Update and a snapshot in combat with every unit identity secret", function()
    local ww = require("Forever.helpers.warrior_world")
    local H

    setup(function()
        local new = fake.new
        fake.new = function(...)
            local api, ctl = new(...)
            api.GetCVar = function() -- nameplates on, so the plate count runs
                return "1"
            end
            return api, ctl
        end
        local ok, h = pcall(headless.new, { character = ww.character(), pack = ww.PACK })
        fake.new = new
        assert(ok, h)
        H = h
        assert.are.same({}, H.loadErrors)
        H.Hekili.Engine.settings.screenshot = false -- the harness has no Screenshot()
        fake.strictKeys(H.Hekili.npUnits)
        fake.strictKeys(H.Hekili.npGUIDs)
    end)

    it("raises nothing and stores a non-empty snapshot", function()
        local ctl = H.ctl
        ctl.inRange.target, ctl.level.target = true, 60
        for _, u in ipairs({ "target", "targettarget", "focus", "softenemy", "softinteract" }) do
            ctl.guid[u], ctl.names[u], ctl.unitIs[u] = SECRET, SECRET, SECRET
        end
        ctl.exists.targettarget = true
        for i = 1, 4 do
            local u = "nameplate" .. i
            ctl.guid[u], ctl.names[u], ctl.unitIs[u], ctl.exists[u] = SECRET, SECRET, SECRET, true
            ctl.unitIs[u .. "target"] = SECRET
            H.Fire("NAME_PLATE_UNIT_ADDED", u)
        end
        H.Fire("PLAYER_TARGET_CHANGED")
        ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        H.Fire("PLAYER_ENTER_COMBAT")
        local t = ctl.now
        for k = 1, 20 do
            local ok, err = headless.cycle(H, t + 0.2 * k)
            assert(ok, err)
            H.Fire("UNIT_COMBAT", "target", "WOUND", "", SECRET, 1)
            H.Fire("UNIT_COMBAT", "player", "WOUND", "", SECRET, 1)
            H.Fire("UNIT_TARGET", "nameplate1")
            H.Fire("UNIT_FLAGS", "nameplate2")
        end
        local before = #H.ns.snapshots
        H.Hekili:MakeSnapshot()
        assert.are.same({}, H.errors)
        assert.is_true(#H.ns.snapshots > before, "no snapshot stored")
        local log = H.ns.snapshots[#H.ns.snapshots].log
        assert.is_true(type(log) == "string" and #log > 100, "empty snapshot")
        assert.are.equal(0, fake.secretsIn(H.Hekili.npUnits) + fake.secretsIn(H.Hekili.npGUIDs))
    end)
end)

-- T1 (plate count plan v2 §3, tasks 3-5): under the Map restriction no plate has a GUID, so Engine/Sim/Targets.lua keeps
-- the plate tokens (npTokens) and counts the attackable ones by the reads measured plain on plate tokens in a dungeon
-- in combat (UnitExists, UnitCanAttack, UnitIsUnit("target", plate)); every other read is guarded (an assumed read,
-- tests/Forever/fixtures/dungeon_map_reads.lua). The target is counted once. Each count is the forced one after the
-- plate count's one-update hold has settled (map_world.count).
describe("the plate enemy count under the Map restriction (T1)", function()
    local mw = require("Forever.helpers.map_world")
    local ww = require("Forever.helpers.warrior_world")
    local READS = dofile("tests/Forever/fixtures/dungeon_map_reads.lua")
    local Hs = {}

    -- One instance a world, its stores strict (a secret key raises), reset between cases.
    local function world(w)
        local H = Hs[w]
        if not H then
            H = mw.new(w)
            fake.strictKeys(H.Hekili.npUnits)
            fake.strictKeys(H.Hekili.npGUIDs)
            fake.strictKeys(H.Hekili.npTokens)
            fake.strictKeys(H.ns.dumpNameplateInfo())
            Hs[w] = H
        end
        H.world = w
        local ctl = H.ctl
        for k = 1, 12 do
            local u = "nameplate" .. k
            if ctl.exists[u] then
                mw.unplate(H, k)
            end
            ctl.friendly[u], ctl.dead[u], ctl.isPlayer[u], ctl.inParty[u], ctl.inRaid[u] = nil, nil, nil, nil, nil
            ctl.actionInRange[u], ctl.distance[u], ctl.unitIs[u], ctl.unitCombat[u] = nil, nil, nil, nil
        end
        ctl.dead.target, ctl.isPlayer.target = nil, nil
        ctl.pvp, ctl.groupMembers, ctl.rangeLib = nil, nil, nil
        mw.platesShown(ctl, true)
        mw.target(H, nil)
        local spec = H.Hekili.Engine.settings.specs[ww.SPEC]
        spec.nameplates, spec.petbased, spec.nameplateRange = true, false, nil
        H.Hekili.PetBasedTargetDetectionIsReady = nil
        for i = #H.errors, 1, -1 do
            H.errors[i] = nil
        end
        mw.count(H)
        return H, ctl, spec
    end

    local function clean(H)
        assert.are.same({}, H.errors)
        local secrets = 0
        for _, t in ipairs({ H.Hekili.npUnits, H.Hekili.npGUIDs, H.Hekili.npTokens, H.ns.dumpNameplateInfo() }) do
            secrets = secrets + fake.secretsIn(t)
        end
        assert.are.equal(0, secrets)
    end
    local function plates(H, n, from)
        for k = from or 1, n do
            mw.plate(H, k)
        end
    end
    local function count(H)
        local ok, n = pcall(mw.count, H)
        assert(ok, n)
        clean(H)
        return n
    end

    it("3 hostile plates with the target among them count 3; a target with no plate adds 1; no plates: 1", function()
        local H = world("B")
        assert.are.equal(1, count(H))
        mw.target(H, 0)
        assert.are.equal(1, count(H), "a target and no plates")
        plates(H, 3)
        mw.target(H, 2)
        assert.are.equal(3, count(H))
        assert.is_nil(H.Hekili.npGUIDs.nameplate2)
        assert.is_true(H.Hekili.npTokens.nameplate2)
        mw.target(H, 0)
        assert.are.equal(4, count(H), "the target's mob has no plate")
    end)

    it("plates off or the spec's Count Nameplates off: 1", function()
        local H, ctl, spec = world("B")
        plates(H, 3)
        mw.target(H, 1)
        mw.platesShown(ctl, false)
        assert.are.equal(1, count(H))
        mw.platesShown(ctl, true)
        spec.nameplates = false
        assert.are.equal(1, count(H))
    end)

    it("a friendly plate is not counted; UNIT_FLAGS turning one friendly drops its token", function()
        local H, ctl = world("B")
        ctl.friendly.nameplate3 = true
        plates(H, 3)
        mw.target(H, 1)
        assert.is_nil(H.Hekili.npTokens.nameplate3)
        assert.are.equal(2, count(H))
        ctl.friendly.nameplate2 = true
        H.Fire("UNIT_FLAGS", "nameplate2")
        assert.is_nil(H.Hekili.npTokens.nameplate2)
        assert.are.equal(1, count(H))
    end)

    it("a plainly dead plate, a player's plate and a party member's plate are not counted", function()
        local H, ctl = world("B")
        plates(H, 5)
        mw.target(H, 1)
        ctl.dead.nameplate2, ctl.isPlayer.nameplate3 = true, true
        ctl.groupMembers, ctl.inParty.nameplate4 = 2, true
        assert.are.equal(2, count(H))
    end)

    it("a secret target compare adds no target while plates count; with no countable plate the target is 1", function()
        local H, ctl = world("B")
        plates(H, 3)
        mw.target(H, 0)
        ctl.unitIs.target = SECRET
        for k = 1, 3 do
            ctl.unitIs["nameplate" .. k] = SECRET
        end
        assert.are.equal(3, count(H), "the target may be one of the plates: not added")
        for k = 1, 3 do
            ctl.dead["nameplate" .. k] = true
        end
        assert.are.equal(1, count(H))
    end)

    it("every assumed read secret (pessimistic): still N, no error", function()
        local H, ctl, spec = world("B")
        plates(H, 4)
        mw.target(H, 1)
        ctl.groupMembers, ctl.pvp = 2, SECRET
        spec.petbased = true
        H.Hekili.PetBasedTargetDetectionIsReady = function()
            return true
        end
        for k = 1, 4 do
            local u = "nameplate" .. k
            ctl.dead[u], ctl.isPlayer[u], ctl.inParty[u], ctl.actionInRange[u] = SECRET, SECRET, SECRET, SECRET
        end
        ctl.dead.target, ctl.isPlayer.target = SECRET, SECRET
        local assumed = 0
        for _, r in ipairs(READS) do
            assumed = assumed + (r.status == "assumed" and 1 or 0)
        end
        assert.is_true(assumed >= 6, "the fixture lists the assumed reads")
        assert.are.equal(4, count(H))
        mw.target(H, 0)
        assert.are.equal(5, count(H), "the target with no plate, its assumed reads secret")
    end)

    it("REMOVED drops a plate while UnitExists stays true; removed and re-added in one update counts it", function()
        local H, ctl = world("B")
        plates(H, 3)
        mw.target(H, 1)
        assert.are.equal(3, count(H))
        H.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3") -- the token still exists during the event
        assert.is_true(ctl.exists.nameplate3)
        assert.are.equal(2, count(H))
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
        H.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        assert.are.equal(3, count(H))
    end)

    it("2 GUID plates and 2 token plates, the target one of the token plates: 4", function()
        local H, ctl = world("B")
        for k = 1, 2 do
            local u = "nameplate" .. k
            ctl.exists[u], ctl.guid[u], ctl.level[u] = true, "Creature-p" .. k, 60
            H.Fire("NAME_PLATE_UNIT_ADDED", u)
        end
        plates(H, 4, 3)
        mw.target(H, 3)
        assert.are.equal("Creature-p1", H.Hekili.npGUIDs.nameplate1)
        assert.is_true(H.Hekili.npTokens.nameplate3)
        assert.are.equal(4, count(H))
    end)

    it("plates stored while plain, then every identity read secret with no event: still N, no error", function()
        local H, ctl = world("A")
        plates(H, 3)
        mw.target(H, 2)
        assert.are.equal(3, count(H))
        for _, u in ipairs({ "target", "nameplate1", "nameplate2", "nameplate3" }) do
            ctl.guid[u], ctl.names[u], ctl.unitIs[u] = SECRET, SECRET, SECRET
        end
        assert.are.equal(3, count(H))
    end)

    it("ADDED on a token stored under an old GUID, now secret: the old GUID's entry goes, the token is kept", function()
        local H, ctl = world("A")
        plates(H, 1)
        assert.are.equal("nameplate1", H.Hekili.npUnits["Creature-p1"])
        ctl.guid.nameplate1 = SECRET
        H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        clean(H)
        assert.is_nil(H.Hekili.npUnits["Creature-p1"])
        assert.is_nil(H.Hekili.npGUIDs.nameplate1)
        assert.is_true(H.Hekili.npTokens.nameplate1)
    end)

    it("a token plate past the Enemy Range Radius is left out; unknown, secret or raising keeps it", function()
        local H, ctl, spec = world("B")
        plates(H, 3)
        mw.target(H, 1)
        spec.nameplateRange = 10
        ctl.distance.nameplate3 = 30
        assert.are.equal(2, count(H), "30 yd past a 10 yd radius")
        ctl.distance.nameplate3 = SECRET
        assert.are.equal(3, count(H), "secret")
        ctl.distance.nameplate3, ctl.rangeLib = nil, "raise"
        assert.are.equal(3, count(H), "raising")
        ctl.rangeLib = "none"
        assert.are.equal(3, count(H), "silent")
    end)

    -- caster range (L644, branch caster-range) on token plates: past 10 yd a plate counts only while plainly in combat
    -- (UnitAffectingCombat on plates plain under forced Map: owner 2026-11-12, 109 of 120 ticks plain, 0 secret)
    it("a ranged radius: past 10 yd a token plate counts only while plainly in combat; within 10 yd always", function()
        local H, ctl, spec = world("B")
        plates(H, 4)
        mw.target(H, 1)
        spec.nameplateRange = 40
        ctl.distance.nameplate2, ctl.distance.nameplate3, ctl.distance.nameplate4 = 30, 30, 5
        ctl.unitCombat.nameplate2, ctl.unitCombat.nameplate3 = true, false
        ctl.unitCombat.nameplate4 = false
        assert.are.equal(3, count(H), "the target, the far engaged plate, the near idle one")
        ctl.unitCombat.nameplate2 = SECRET
        assert.are.equal(2, count(H), "a secret combat answer past 10 yd: not counted")
        ctl.unitCombat.nameplate2, ctl.distance.nameplate2 = true, nil
        assert.are.equal(3, count(H), "unknown range, engaged: counted")
        ctl.unitCombat.nameplate2 = false
        assert.are.equal(2, count(H), "unknown range, idle: not counted")
        spec.nameplateRange = nil -- the default 10 yd radius: no combat read
        ctl.distance.nameplate2, ctl.distance.nameplate3 = nil, nil
        assert.are.equal(4, count(H))
    end)

    it("world C (in combat, the target's auras raising, health secret): the same counts, no error", function()
        local H = world("C")
        plates(H, 3)
        mw.target(H, 1)
        assert.are.equal(3, count(H))
        mw.target(H, 0)
        assert.are.equal(4, count(H))
    end)

    -- task 4: plates already up at a /reload fire no ADDED (assumed until probe P14, L77).
    it(
        "PLAYER_ENTERING_WORLD on a reload finds the plates already up; their ADDED afterwards changes nothing",
        function()
            local H, ctl = world("B")
            for k = 1, 3 do
                local u = "nameplate" .. k
                ctl.exists[u], ctl.guid[u], ctl.names[u], ctl.level[u] = true, SECRET, SECRET, 60
            end
            mw.target(H, 1)
            assert.are.equal(1, count(H), "no ADDED: nothing known")
            H.Fire("PLAYER_ENTERING_WORLD", false, true)
            assert.are.equal(3, count(H))
            for k = 1, 3 do
                H.Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. k)
            end
            assert.are.equal(3, count(H))
        end
    )

    -- task 5: each scenario both worlds express counts the same through the GUID path (A) and the token path (B).
    it("A/B parity: the GUID path and the token path agree", function()
        local scenarios = {
            function(H)
                plates(H, 3)
                mw.target(H, 2)
            end,
            function(H)
                plates(H, 3)
                mw.target(H, 0)
            end,
            function(H)
                mw.target(H, 0)
            end,
            function(H, ctl)
                plates(H, 4)
                mw.target(H, 1)
                ctl.dead.nameplate2, ctl.isPlayer.nameplate3 = true, true
            end,
            function(H)
                plates(H, 5)
                mw.target(H, 5)
                mw.unplate(H, 4)
            end,
            function(H, ctl)
                ctl.friendly.nameplate2 = true
                plates(H, 3)
                mw.target(H, 1)
            end,
        }
        for i, s in ipairs(scenarios) do
            local got = {}
            for _, w in ipairs({ "A", "B" }) do
                local H, ctl = world(w)
                s(H, ctl)
                got[w] = count(H)
            end
            assert.are.equal(got.A, got.B, "scenario " .. i)
        end
    end)
end)
