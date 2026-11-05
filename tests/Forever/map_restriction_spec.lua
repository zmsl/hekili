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
