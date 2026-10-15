-- Virtual/State/spec/player_spec.lua: VS.Start on a client that lacks a CR_* constant, and a start hook that raises
-- (CHECKPOINT 2: Forever defines no CR_CRIT_TAKEN_SPELL, and the raise aborted every later start hook).
local load = require("Virtual.State.spec.helpers.load")
local fake = require("Virtual.State.spec.helpers.fake_api")
local fs = require("Virtual.State.spec.helpers.fake_spec")
local alloc = require("Virtual.State.spec.helpers.alloc")

describe("player start", function()
    local VS, I, S, api

    before_each(function()
        api = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S = I.Sources
        I.Build(fs.def(fs.new(9)), 1)
    end)

    it("Start survives a missing CR_* constant", function()
        api.CR_CRIT_TAKEN_SPELL = nil
        api.GetCombatRating = function(cr)
            assert(cr ~= nil, "Usage: GetCombatRating(ratingIndex)")
            return cr * 10
        end
        assert.has_no.errors(function()
            VS.Start(api)
        end)
        assert.equal("partial", S.status["stats CR_* constants"])
        assert.equal(180, (VS.Stat("GetCombatRating", api.CR_HASTE_MELEE)))
        assert.equal("readable", S.status.UnitSpellHaste)
        assert.equal("readable", S.status.UnitAttackSpeed) -- Swing.lua's start hook, registered after Player's
    end)

    it("keeps the start reads across the first build (PLAYER_LOGIN before PLAYER_ENTERING_WORLD)", function()
        local ctl = api.ctl
        ctl.speed[1], ctl.spellHaste = 2.6, 7
        VS.Start(api)
        I.Build(fs.def(fs.new(9)), 100) -- SpecChanged clears the log, the stage and the records
        S.Flush()
        I.Fold(100, false)
        local sp = VS.SwingSpeed(1, 100)
        assert.are.same({ 2.6, "observed" }, { sp.est, sp.basis })
        local h = VS.SpellHaste(100)
        assert.are.same({ 7, "observed" }, { h.est, h.basis })
    end)

    it("re-reads the stats out of combat when the weapon damage, attack power or level changes", function()
        local ctl = api.ctl
        local damage = { 40, 60, 15, 25, 0, 0, 1 }
        api.UnitDamage = function()
            return damage[1], damage[2], damage[3], damage[4], damage[5], damage[6], damage[7]
        end
        VS.Start(api)
        assert.are.same({ 40, 60, 15, 25, 0, 0, 1 }, { VS.Stat("UnitDamage") })
        damage[1], damage[2] = 44, 66 -- Battle Shout before a pull
        ctl.Fire("UNIT_ATTACK_POWER", "player")
        assert.are.same({ 44, 66, 15, 25, 0, 0, 1 }, { VS.Stat("UnitDamage") })
        damage[1] = 50
        ctl.Fire("UNIT_DAMAGE", "target") -- another unit: no read
        assert.are.equal(44, (VS.Stat("UnitDamage")))
        ctl.Fire("UNIT_DAMAGE", "player")
        assert.are.equal(50, (VS.Stat("UnitDamage")))
        damage[1] = 52
        ctl.Fire("PLAYER_LEVEL_UP", 23)
        assert.are.equal(52, (VS.Stat("UnitDamage")))
        ctl.Fire("PLAYER_REGEN_DISABLED")
        damage[1] = 70 -- a weapon swap in combat: secret then, so stale until combat ends
        ctl.Fire("UNIT_DAMAGE", "player")
        assert.are.equal(52, (VS.Stat("UnitDamage")))
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(70, (VS.Stat("UnitDamage")))
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(0, alloc.bytes(function()
            ctl.Fire("UNIT_DAMAGE", "player")
        end, 2000))
    end)

    it("notes complete when every CR_* constant resolves", function()
        VS.Start(api)
        assert.equal("complete", S.status["stats CR_* constants"])
    end)

    it("Start isolates a start hook that raises", function()
        local seen
        api.geterrorhandler = function()
            return function(err)
                seen = err
            end
        end
        local after = false
        S.OnStart(function()
            error("boom")
        end)
        S.OnStart(function()
            after = true
        end)
        assert.has_no.errors(function()
            VS.Start(api)
        end)
        assert.equal("error", S.status.start)
        assert.truthy(seen and seen:find("boom"))
        assert.is_true(after)
    end)
end)
