-- tests/Game/State/forms_spec.lua: the forms source (Sources/Forms.lua). Stances are shapeshift forms, not walked
-- auras: the plain form reads put the active form's tracked player aura up with no expiry and the others down, at the
-- first poll after build and on UPDATE_SHAPESHIFT_FORM; a later aura walk that does not list it leaves it up.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")

local FORM_A, FORM_B, OTHER = 2457, 2458, 1099

local function def(ids)
    local auras, auraIds = {}, {}
    for i = 1, #ids do
        auras[i], auraIds[i] = { key = "a" .. ids[i], id = ids[i] }, { ids[i] }
    end
    return {
        abilities = { { key = "stance" } }, -- the stance cast (ability 1)
        abilityIds = { { FORM_B } },
        abilitySlot = { 0 },
        resources = {},
        auras = auras,
        auraIds = auraIds,
        talents = {},
        units = { "player", "target" },
    }
end

describe("forms", function()
    local VS, I, S, Obs, api, ctl, warnings

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        warnings = {}
        ns.Error = function(msg, ...) -- Utils.lua's error channel, stubbed
            warnings[#warnings + 1] = string.format(msg, ...)
        end
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
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

    it(
        "reads the form after a stance cast folded in the same frame (the cast's modelled expiry does not stick)",
        function()
            start({ FORM_A, FORM_B })
            poll(10)
            I.On(Obs.CastSuccess, function(_, t) -- the stance's `now` applyBuff: a modelled 3600 s expiry
                I.AuraModel(1, 2, t, t + 3600, 1, t, Obs.CastSuccess, false)
            end)
            ctl.now, ctl.form = 11, 2
            S.Stage(Obs.CastSuccess, 11, 1) -- staged, as Sources/Casts.lua does
            ctl.Fire("UPDATE_SHAPESHIFT_FORM") -- the same frame
            poll(11)
            assert.are.equal(math.huge, VS.Aura("player", FORM_B, 11).est)
            assert.is_nil(VS.Aura("player", FORM_A, 11))
        end
    )

    it("forgets the form marks on a rebuild: a non-form aura at a form's old index goes down on a walk", function()
        start({ FORM_A, OTHER })
        poll(10)
        I.Build(def({ OTHER, FORM_B }), 10) -- OTHER now has FORM_A's index; no form is active
        ctl.form = 0
        ctl.auras.player.HELPFUL[1] = { spellId = OTHER, expirationTime = 0, applications = 0 }
        ctl.now = 11
        ctl.Fire("UNIT_AURA", "player")
        poll(11)
        assert.is_not_nil(VS.Aura("player", OTHER, 11))
        ctl.auras.player.HELPFUL[1] = nil
        ctl.Fire("UNIT_AURA", "player")
        poll(12)
        assert.is_nil(VS.Aura("player", OTHER, 12))
    end)

    it("leaves the target's walk alone: a target aura at a form's index still goes down", function()
        start({ FORM_A, OTHER })
        poll(10)
        ctl.now = 11
        ctl.auras.target.HELPFUL[1] = { spellId = FORM_A, expirationTime = 0, applications = 0 }
        ctl.Fire("UNIT_AURA", "target")
        poll(11)
        assert.is_not_nil(VS.Aura("target", FORM_A, 11))
        ctl.auras.target.HELPFUL[1] = nil
        ctl.Fire("UNIT_AURA", "target")
        poll(12)
        assert.is_nil(VS.Aura("target", FORM_A, 12))
    end)

    it("hands the form auras back to the walk when a form read is not plain", function()
        start({ FORM_A, FORM_B })
        poll(10)
        ctl.form = fake.SECRET
        ctl.now = 11
        ctl.Fire("UPDATE_SHAPESHIFT_FORM")
        poll(11)
        assert.is_not_nil(VS.Aura("player", FORM_A, 11)) -- a secret read changes nothing by itself
        ctl.Fire("UNIT_AURA", "player") -- a clean walk without it: down
        poll(12)
        assert.is_nil(VS.Aura("player", FORM_A, 12))
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

    it("warns once per build about a client form whose spell matches no registered aura", function()
        start({ FORM_A })
        poll(10)
        assert.are.same(
            { "Forever: shapeshift form 2 (spell 2458) matches no registered aura; the belief cannot see this form" },
            warnings
        )
        ctl.Fire("UPDATE_SHAPESHIFT_FORM")
        poll(11)
        assert.are.equal(1, #warnings) -- the same build: no repeat
        I.Build(def({ FORM_A }), 11)
        poll(12)
        assert.are.equal(2, #warnings)
    end)

    it("does not warn when every client form is registered", function()
        start({ FORM_A, FORM_B })
        poll(10)
        assert.are.same({}, warnings)
    end)
end)
