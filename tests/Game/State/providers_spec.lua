-- tests/Game/State/providers_spec.lua (providers spec §1-§3): the contracts, the Default providers, injection.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("providers", function()
    local api, ctl, ns, VS, I, saved

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
    end)
    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("resolves a missing or unknown name to default", function()
        I.Build(fs.def(fs.new(9)), 1)
        assert.are.equal("default", I.outcomes.name)
        assert.are.equal("default", I.presence.name)
        local d = fs.def(fs.new(9))
        d.providers = { outcomes = "nonesuch", presence = "nonesuch" }
        I.Build(d, 1)
        assert.are.same({ "default", "default" }, { I.outcomes.name, I.presence.name })
    end)

    it("the Default providers answer UNDECIDED and cover nothing", function()
        I.Build(fs.def(fs.new(9)), 1)
        local P, Q = I.outcomes, I.presence
        assert.are.same({ 0, 0 }, { P.SWING_DELAY, P.ROW_DELAY })
        assert.are.equal(I.UNDECIDED, P.SwingOutcome(1, 2))
        assert.are.equal(I.UNDECIDED, P.RowOwner(1, 1, 1, 10, "WOUND", 2))
        assert.is_nil(P.EnemyHitAt(1))
        assert.is_nil(P.Audit())
        assert.are.same({ 0, nil }, { Q.covered, Q.scope })
        assert.are.equal(I.UNDECIDED, Q.Presence(1, 1))
        assert.is_nil(VS.PresenceScope("player", I.auras.obj[1].key))
    end)

    it("swaps out of combat at once, in combat at combat end", function()
        I.OUTCOMES.probe = setmetatable({ name = "probe" }, { __index = I.OUTCOMES.default })
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        I.inCombat = true
        VS.SetProviders("probe", "default")
        assert.are.equal("default", I.outcomes.name)
        I.inCombat = false
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal("probe", I.outcomes.name)
    end)

    it("a dormant event is not registered with the client until woken", function()
        I.Build(fs.def(fs.new(9)), 1)
        local S = I.Sources
        S.On("TEST_DORMANT_EVENT", nil, function() end)
        S.Dormant("TEST_DORMANT_EVENT", true)
        VS.Start(api)
        assert.is_falsy(api.frame.events.TEST_DORMANT_EVENT)
        S.Dormant("TEST_DORMANT_EVENT", false)
        I.Events.Sync("TEST_DORMANT_EVENT")
        assert.is_truthy(api.frame.events.TEST_DORMANT_EVENT)
    end)

    it("only the router with the viewer switch on registers the Cooldown Manager's events", function()
        local d = fs.def(fs.new(9))
        d.providers = { presence = "router", viewer = false }
        I.Build(d, 1)
        VS.Start(api)
        assert.is_falsy(api.frame.events.COOLDOWN_VIEWER_DATA_LOADED)
        assert.is_falsy(api.frame.events.COOLDOWN_VIEWER_TABLE_HOTFIXED)
        d = fs.def(fs.new(9))
        d.providers = { presence = "router", viewer = true }
        I.Build(d, 1)
        assert.is_truthy(api.frame.events.COOLDOWN_VIEWER_DATA_LOADED)
        assert.is_truthy(api.frame.events.COOLDOWN_VIEWER_TABLE_HOTFIXED)
        I.Build(fs.def(fs.new(9)), 1)
        assert.is_falsy(api.frame.events.COOLDOWN_VIEWER_DATA_LOADED)
    end)
end)
