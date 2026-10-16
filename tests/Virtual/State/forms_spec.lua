-- tests/Virtual/State/forms_spec.lua: the forms source (Sources/Forms.lua). Stances are shapeshift forms, not walked
-- auras: the plain form reads put the active form's tracked player aura up with no expiry and the others down, at the
-- first poll after build and on UPDATE_SHAPESHIFT_FORM; a later aura walk that does not list it leaves it up.
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")

local FORM_A, FORM_B, OTHER = 2457, 2458, 6673

local function def(ids)
    local auras, auraIds = {}, {}
    for i = 1, #ids do
        auras[i], auraIds[i] = { key = "a" .. ids[i], id = ids[i] }, { ids[i] }
    end
    return {
        abilities = {},
        abilityIds = {},
        abilitySlot = {},
        resources = {},
        auras = auras,
        auraIds = auraIds,
        talents = {},
        units = { "player", "target" },
    }
end

describe("forms", function()
    local VS, I, S, api, ctl

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S = I.Sources
        ctl.forms = { FORM_A, FORM_B }
        ctl.form = 1
    end)

    local function start(ids)
        ctl.now = 1
        I.Build(def(ids), 1)
        VS.Start(api)
    end

    local function poll(t)
        ctl.now = t
        ctl.Tick(t)
        S.RunPolls(t)
        I.Fold(t)
        I.Settle(t)
    end

    it("puts the active form's aura up with no expiry and the others down at the first poll", function()
        start({ FORM_A, FORM_B, OTHER })
        poll(10)
        local rec, stacks, applied = VS.Aura("player", FORM_A, 10)
        assert.are.same({ math.huge, 1, 10, "observed" }, { rec.est, stacks, applied, rec.basis })
        assert.is_nil(VS.Aura("player", FORM_B, 10))
        assert.is_nil(VS.Aura("player", OTHER, 10))
    end)

    it("moves the aura on a form change", function()
        start({ FORM_A, FORM_B })
        poll(10)
        ctl.form = 2
        ctl.now = 11
        ctl.Fire("UPDATE_SHAPESHIFT_FORM")
        poll(11)
        assert.is_nil(VS.Aura("player", FORM_A, 11))
        assert.are.equal(math.huge, VS.Aura("player", FORM_B, 11).est)
        ctl.form = 0
        ctl.now = 12
        ctl.Fire("UPDATE_SHAPESHIFT_FORM")
        poll(12)
        assert.is_nil(VS.Aura("player", FORM_A, 12))
        assert.is_nil(VS.Aura("player", FORM_B, 12))
    end)

    it("keeps the form aura up through a full aura walk that does not list it", function()
        start({ FORM_A, FORM_B, OTHER })
        poll(10)
        local inst = select(4, VS.Aura("player", FORM_A, 10))
        ctl.now = 11
        ctl.auras.player.HELPFUL[1] = { spellId = OTHER, expirationTime = 0, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        poll(11)
        assert.are.equal(inst, select(4, VS.Aura("player", FORM_A, 11)))
        ctl.auras.player.HELPFUL[1] = nil
        ctl.Fire("UNIT_AURA", "player")
        poll(12)
        assert.is_nil(VS.Aura("player", OTHER, 12)) -- a walked aura still goes down
        assert.are.equal(inst, select(4, VS.Aura("player", FORM_A, 12)))
    end)

    it("agrees with a walk that lists the form aura (a form that is also a buff)", function()
        start({ FORM_A, FORM_B })
        ctl.now = 10
        ctl.auras.player.HELPFUL[1] = { spellId = FORM_A, expirationTime = 0, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        poll(10)
        local rec, stacks, _, inst = VS.Aura("player", FORM_A, 10)
        assert.are.same({ math.huge, 1 }, { rec.est, stacks })
        ctl.now = 11
        ctl.Fire("UPDATE_SHAPESHIFT_FORM")
        poll(11)
        assert.are.equal(inst, select(4, VS.Aura("player", FORM_A, 11)))
    end)

    it("does nothing for a class with no tracked form aura", function()
        start({ OTHER })
        local gen = VS.AuraGen("player")
        poll(10)
        ctl.Fire("UPDATE_SHAPESHIFT_FORM")
        poll(11)
        assert.are.equal(gen, VS.AuraGen("player"))
        assert.are.equal(0, I.log.n)
    end)
end)
