-- tests/Game/State/router_spec.lua: the Presence router (providers spec §2.5, decisions 88-90), against the viewer
-- fakes and the Task 5 fixture (viewer_spec.lua).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("the Presence router", function()
    local VS, I, ctl, api, d

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        ctl.viewer.sets[2] = { 501, 502 }
        ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
        ctl.viewer.infos[502] = { spellID = 9999, linkedSpellIDs = { fs.SPENDER_C_R2 } }
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 501).unit = "player"
        ctl.ViewerItem("BuffIconCooldownViewer", 2, 502).unit = "target"
        local ns = load.module()
        VS = ns.VirtualState
        I = ns.VirtualStateInternal
        -- shortcut: stands in for Task 1's provider resolution in I.Build; Task 1 replaces it with `d.providers` alone
        local build = I.Build
        I.Build = function(def, ...)
            build(def, ...)
            if I.presence then
                I.presence.Deactivate()
            end
            I.presence = nil
            local pv = def.providers
            if pv and (pv.presence == "viewer" or pv.presence == "router") then
                I.presence = I.PRESENCE[pv.presence]
                I.presence.Activate(api, ctl.now, def, { viewer = pv.viewer == true })
            end
        end
        d = fs.def(fs.new(9))
        d.auras[3], d.auraIds[3] = { key = "spender_m", id = fs.SPENDER_M }, { fs.SPENDER_M } -- aura 3: not in a set
        d.providers = { presence = "router", viewer = true }
        I.Build(d, 1)
        VS.Start(api)
    end)

    it("a tracked aura is answered by the viewer leaf", function()
        local R = I.presence
        assert.are.equal("router", R.name)
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true)
        assert.are.equal(I.UP, R.Presence(1, 1))
    end)

    it("an untracked aura answers UNDECIDED (the modelled timer)", function()
        assert.are.equal(I.UNDECIDED, I.presence.Presence(3, 1))
    end)

    it("switch off: every aura UNDECIDED, covered 0, no hook installed, no getter read", function()
        local calls = 0
        local get = api.C_CooldownViewer.GetCooldownViewerCategorySet
        api.C_CooldownViewer.GetCooldownViewerCategorySet = function(...)
            calls = calls + 1
            return get(...)
        end
        local d2 = fs.def(fs.new(9))
        d2.providers = { presence = "router", viewer = false }
        I.Build(d2, 1)
        assert.are.same({ 0, 0 }, { I.presence.covered, calls })
        for j = 1, I.auras.nAura do
            assert.are.equal(I.UNDECIDED, I.presence.Presence(j, 1))
        end
    end)

    it("with the Cooldown Manager unavailable every aura is UNDECIDED", function()
        ctl.viewer.available = false
        I.Build(d, 1)
        assert.are.equal(0, I.presence.covered)
        for j = 1, I.auras.nAura do
            assert.is_false(I.presence.tracked[j])
            assert.are.equal(I.UNDECIDED, I.presence.Presence(j, 1))
        end
    end)

    it("rebuilds on the viewer's set-change event out of combat only", function()
        ctl.viewer.sets[2][#ctl.viewer.sets[2] + 1] = 503 -- spender_m's cooldown now tracked
        ctl.viewer.infos[503] = { cooldownID = 503, spellID = fs.SPENDER_M, linkedSpellIDs = {} }
        I.inCombat = true
        ctl.Fire("COOLDOWN_VIEWER_DATA_LOADED")
        local jm = I.auras.bySpell[fs.SPENDER_M]
        assert.is_false(I.presence.tracked[jm])
        I.inCombat = false
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(I.presence.tracked[jm])
    end)

    it("activated in combat, reads nothing until combat ends", function()
        local calls = 0
        local get = api.C_CooldownViewer.GetCooldownViewerCategorySet
        api.C_CooldownViewer.GetCooldownViewerCategorySet = function(...)
            calls = calls + 1
            return get(...)
        end
        I.inCombat = true
        I.Build(d, 1)
        assert.are.same({ 0, 0 }, { I.presence.covered, calls })
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
        assert.is_true(I.presence.tracked[1]) -- the map stands until the deferred build (no mid-fight path change)
        I.inCombat = false
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(2, I.presence.covered)
        assert.are.equal(I.DOWN, I.presence.Presence(1, 1))
    end)

    it("passes only tracked edges on and counts them", function()
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true)
        assert.are.equal(1, I.presenceEdges.up)
    end)

    it("prints one audit line per tracked aura and unit; none with the switch off", function()
        local snap = VS.Snapshot()
        assert.is_truthy(snap:find("presence spender_a unit=- path=viewer facts=0 disagree=0", 1, true))
        assert.is_truthy(snap:find("presence spender_c unit=- path=viewer facts=0 disagree=0", 1, true))
        assert.is_falsy(snap:find("unit=target path=viewer facts=0", 1, true)) -- one line per aura without facts
        assert.is_falsy(snap:find("presence spender_m", 1, true)) -- untracked and no fact: no line
        I.presenceFacts[1] = 2 -- a fact on the player: that unit's line replaces the aura's line
        snap = VS.Snapshot()
        assert.is_truthy(snap:find("presence spender_a unit=player path=viewer facts=2 disagree=0", 1, true))
        assert.is_falsy(snap:find("presence spender_a unit=-", 1, true))
        assert.is_falsy(snap:find("presence spender_a unit=target", 1, true))
        local d2 = fs.def(fs.new(9))
        d2.providers = { presence = "router", viewer = false }
        I.Build(d2, 1)
        assert.is_falsy(VS.Snapshot():find("presence ", 1, true))
    end)

    it("zeroes the edge and fact counters at each fight's start", function()
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true)
        I.presenceFacts[1] = 3
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.are.same({ 0, 0, 0 }, { I.presenceEdges.up, I.presenceEdges.down, I.presenceFacts[1] })
    end)

    it("a self-scoped DOWN on the target is no answer and no edge (others' debuffs may be up)", function()
        local item = ctl.viewer.items.BuffIconCooldownViewer[2]
        local n = 0
        I.presence.onEdge = function(_, _, up)
            n = n + 1
            assert.is_true(up)
        end
        assert.are.equal("self", I.presence.scope)
        assert.are.equal(I.UNDECIDED, I.presence.Presence(2, 2))
        ctl.ViewerShow(item, true)
        assert.are.equal(I.UP, I.presence.Presence(2, 2))
        ctl.ViewerShow(item, false)
        assert.are.equal(I.UNDECIDED, I.presence.Presence(2, 2))
        assert.are.same({ 1, 1, 0 }, { n, I.presenceEdges.up, I.presenceEdges.down })
    end)
end)
