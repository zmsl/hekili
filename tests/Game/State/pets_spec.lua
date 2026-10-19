-- tests/Game/State/pets_spec.lua (class-completion C1): the Pets family. The pet unit is observed from UNIT_PET and a
-- poll of UnitExists / UnitIsDead("pet") (plain, through Plain); our summon's `now` (`summonPet`) models it up until the
-- first observation after it, or for the cast window when none comes. A guardian (a pet registered with a `cap`) is
-- counted per summon, each with its own expiry, the oldest giving way at the cap. Hekili reads both through the facade
-- (UnitExists / UnitIsDead of "pet") and `pet.<key>.count`.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local headless = require("Game.harness.headless")

local SUMMON, GUARD = 6301, 6302

describe("the pets family", function()
    local ns, VS, I, api, ctl, h, saved

    local function register(key, id, now)
        local t = { id = id, key = key, funcs = { now = now }, cast = 0, cooldown = 0, charges = 1, recharge = 0 }
        h.Class.abilities[key], h.Class.abilities[id] = t, t
    end

    -- VS.Pet's three facts: exists, dead, modelled
    local function pet(t)
        local e, d, m = VS.Pet(t)
        return { e, d, m }
    end

    local function cast(id, t)
        ctl.now = t
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
        ctl.Tick(t + 0.01)
        VS.Drain(t + 0.02)
    end

    -- UNIT_PET at t, then the drain
    local function unitPet(t)
        ctl.now = t
        ctl.Fire("UNIT_PET", "player")
        ctl.Tick(t + 0.01)
        VS.Drain(t + 0.02)
    end

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        saved = {}
        for _, k in ipairs({ "GetTime", "UnitGUID", "UnitExists", "UnitIsDead", "CreateFrame", "issecretvalue" }) do
            saved[k] = rawget(_G, k) or false
        end
        _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue =
            api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
        _G.UnitExists, _G.UnitIsDead = api.UnitExists, api.UnitIsDead
        saved.debugprofilestop = rawget(_G, "debugprofilestop") or false
        _G.debugprofilestop = function()
            return 0
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        h = fs.new(9)
        fs.clock = api.GetTime
        ns.spendResources = fs.spend
        ns.ResourceRegenerates = function()
            return false
        end
        load.adapter(ns, h)
        h.Class.pets.guardian_a = { token = "guardian_a", cap = 2, duration = 18 }
        h.Class.pets.guardian_alias = h.Class.pets.guardian_a -- an alias (RegisterPet's copies) is not a second pet
        register("summon_a", SUMMON, function()
            summonPet("pet_a", 3600)
        end)
        register("summon_b", GUARD, function()
            summonPet("guardian_a", 18)
        end)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        fs.clock = nil
    end)

    local function start()
        VS.Start(api)
        VS.SpecChanged()
        ctl.Tick(1)
        VS.Drain(1)
    end

    it("models our summon up until the first observation after it, which then answers", function()
        start()
        assert.are.same({ false, false, false }, pet(10)) -- the poll's first read: no pet
        cast(SUMMON, 20)
        assert.are.same({ true, false, true }, pet(20.1)) -- exists, dead, modelled
        assert.is_true(ns.Facade.UnitExists("pet")) -- the game has no pet unit yet; the summon answers
        assert.is_false(ns.Facade.UnitIsDead("pet"))
        ctl.exists.pet = true
        unitPet(20.2)
        assert.are.same({ true, false, false }, pet(20.3))
        assert.are.same({ true, false, false }, pet(30)) -- observed: no window
        assert.are.equal("observed", select(4, VS.Pet(30)).basis)
    end)

    it("yields to the first observation even when it shows no pet", function()
        start()
        cast(SUMMON, 20)
        unitPet(20.1) -- the game's UNIT_PET with no pet unit (the summon failed, or a pet left)
        assert.are.same({ false, false, false }, pet(20.2))
        assert.is_false(ns.Facade.UnitExists("pet"))
    end)

    it("puts a summon whose pet never appears down after the cast window", function()
        start()
        cast(SUMMON, 20)
        assert.are.same({ true, false, true }, pet(20 + I.CAST_GRACE))
        ctl.now = 20 + I.CAST_GRACE + 0.01
        VS.Drain(ctl.now) -- the poll reads no pet, as before the summon: no news
        assert.are.same({ false, false, false }, pet(ctl.now))
        assert.is_false(ns.Facade.UnitExists("pet"))
    end)

    it("observes a pet's death from the poll, and a secret read is no news", function()
        ctl.exists.pet = true
        start()
        assert.are.same({ true, false, false }, pet(2))
        ctl.dead.pet = true
        ctl.now = 30
        VS.Drain(30)
        assert.are.same({ true, true, false }, pet(30))
        assert.is_true(ns.Facade.UnitIsDead("pet")) -- the raw plain read
        ctl.exists.pet = fake.SECRET
        unitPet(31)
        assert.are.same({ true, true, false }, pet(31.1)) -- unchanged
        assert.is_true(ns.Facade.UnitExists("pet")) -- the belief's, never the secret
        assert.is_false(api.issecretvalue(ns.Facade.UnitExists("pet")))
    end)

    it("counts 3 guardians against a cap of 2, each with its own expiry", function()
        start()
        cast(GUARD, 10)
        cast(GUARD, 12)
        assert.are.same({ 2, 30 }, { VS.PetCount("guardian_a", 12.1) })
        cast(GUARD, 14) -- the third: the oldest (10's) gives way
        assert.are.same({ 2, 32 }, { VS.PetCount("guardian_a", 14.1) })
        assert.are.same({ 1, 32 }, { VS.PetCount("guardian_a", 30.5) }) -- 12's expired at 30
        assert.are.same({ 0, 0 }, { VS.PetCount("guardian_a", 32.5) })
        assert.are.same({ 0, 0 }, { VS.PetCount("guardian_alias", 14.1) }) -- one pet, under its token
        assert.are.same({ false, false, false }, pet(14.1)) -- guardians never model the pet unit
        assert.are.same({ 0, 0 }, { VS.PetCount("pet_a", 14.1) }) -- untracked
    end)

    it("allocates nothing across 1000 UNIT_PETs, polls, summons and facade reads", function()
        local alloc = require("Game.State.helpers.alloc")
        start()
        function h:ForceUpdate() end -- the fake records each call; Hekili's own only sets fields
        local t = 50
        local bytes = alloc.bytes(function()
            t = t + 1
            ctl.exists.pet = not ctl.exists.pet
            unitPet(t)
            cast(GUARD, t + 0.3)
            cast(SUMMON, t + 0.5)
            local _ = ns.Facade.UnitExists("pet"), ns.Facade.UnitIsDead("pet"), VS.PetCount("guardian_a", t)
        end, 1000)
        assert.are.equal(0, bytes)
    end)
end)

describe("the simulation's pet reads", function()
    it("answers pet.up from the modelled summon and pet.<key>.count from the guardians", function()
        local H = headless.new()
        local VS, I = H.ns.VirtualState, H.ns.VirtualStateInternal
        H.Hekili.Class.pets.guardian_a = { token = "guardian_a", cap = 2, duration = 18 }
        VS.SpecChanged()
        local t, S = H.ctl.now, H.Hekili.State
        S.reset("AOE") -- partial: a class-neutral boot has no spec, whose state tables a full reset walks
        assert.is_false(S.pet.up)
        assert.are.equal(0, S.pet.guardian_a.count)
        for _ = 1, 3 do
            I.PetModel("guardian_a", 18, t, VS.Obs.CastSuccess)
        end
        I.PetModel("pet_a", 3600, t, VS.Obs.CastSuccess)
        S.reset("AOE") -- partial: a class-neutral boot has no spec, whose state tables a full reset walks
        assert.is_true(S.pet.up)
        assert.are.equal(2, S.pet.guardian_a.count)
        assert.are.same({}, H.errors)
    end)
end)
