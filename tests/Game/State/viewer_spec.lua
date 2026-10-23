-- tests/Game/State/viewer_spec.lua: the Cooldown Manager presence leaf (providers spec §2.4, decisions 77-79), against
-- the viewer fakes (fake_api.lua: ctl.viewer, ctl.ViewerItem, ctl.ViewerShow).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("the CooldownViewer presence leaf", function()
    local I, ctl, d

    before_each(function()
        local api
        api, ctl = fake.new()
        ctl.now = 1
        -- aura 1 (SPENDER_A) by its spell ID, a BuffIcon item on the player; aura 2 by a linked ID, an item on the target.
        -- Both hidden: a down item reads no auraDataUnit (CDV_FRAME 5609); `unit` is what ViewerShow gives it when up.
        ctl.viewer.sets[2] = { 501, 502 }
        ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
        ctl.viewer.infos[502] = { spellID = 9999, linkedSpellIDs = { fs.SPENDER_C_R2 } }
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 501).unit = "player"
        ctl.ViewerItem("BuffIconCooldownViewer", 2, 502).unit = "target"
        local ns = load.module()
        local VS = ns.VirtualState
        I = ns.VirtualStateInternal
        -- shortcut: stands in for Task 1's provider resolution in I.Build; Task 1 replaces it with `d.providers` alone
        local build = I.Build
        I.Build = function(def, ...)
            build(def, ...)
            if I.presence then
                I.presence.Deactivate()
            end
            I.presence = nil
            if def.providers and def.providers.presence == "viewer" then
                I.presence = I.PRESENCE.viewer
                I.presence.Activate(api, ctl.now, def)
            end
        end
        d = fs.def(fs.new(9))
        d.providers = { presence = "viewer" }
        I.Build(d, 1)
        VS.Start(api)
    end)

    it("maps by spell, override and linked IDs; covers what it maps", function()
        local Q = I.presence
        assert.are.equal("viewer", Q.name)
        assert.are.equal("self", Q.scope)
        assert.are.equal(2, Q.covered)
        assert.are.equal(I.DOWN, Q.Presence(1, 1))
        assert.are.equal(I.UNDECIDED, Q.Presence(3, 1))
    end)

    it("reads presence at the hook: secret id is up, nil is down; a change only", function()
        local edges = {}
        I.presence.onEdge = function(j, u, up, t)
            edges[#edges + 1] = { j, u, up }
        end
        ctl.combat = true
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true)
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true) -- a layout refresh: no change, no edge
        assert.are.same({ { 1, 1, true } }, edges)
        assert.are.equal(I.UP, I.presence.Presence(1, 1))
    end)

    it("maps by override ID too", function()
        ctl.viewer.infos[501] = { spellID = 9998, overrideSpellID = fs.SPENDER_A }
        I.Build(d, 1)
        assert.are.equal(2, I.presence.covered)
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true)
        assert.are.equal(I.UP, I.presence.Presence(1, 1))
    end)

    it("a down item reads no unit: the edge goes to the unit remembered from the up read", function()
        local item = ctl.viewer.items.BuffIconCooldownViewer[2]
        local edges = {}
        I.presence.onEdge = function(j, u, up)
            edges[#edges + 1] = { j, u, up }
        end
        ctl.ViewerShow(item, true)
        ctl.ViewerShow(item, false)
        assert.is_nil(item.auraDataUnit)
        assert.are.same({ { 2, 2, true }, { 2, 2, false } }, edges)
        assert.are.equal(I.DOWN, I.presence.Presence(2, 2))
    end)

    it("an Essential or Utility item is no presence source (always shown, CV §2): its aura is undecided", function()
        local items = ctl.viewer.items
        items.BuffIconCooldownViewer[2] = nil -- aura 2 now has only an Essential item
        local essential = ctl.ViewerItem("EssentialCooldownViewer", 1, 502)
        I.Build(d, 1)
        assert.are.equal(1, I.presence.covered)
        assert.is_nil(essential.hooks.OnShow)
        assert.are.equal(I.UNDECIDED, I.presence.Presence(2, 2))
    end)

    it("a hide with the aura still up is no edge (layout refresh, CDM-S)", function()
        local item = ctl.viewer.items.BuffIconCooldownViewer[1]
        ctl.ViewerShow(item, true)
        local n = 0
        I.presence.onEdge = function()
            n = n + 1
        end
        item.auraInstanceID = fake.SECRET
        item.hooks.OnHide[1](item)
        assert.are.equal(0, n)
    end)

    it("reads nothing and hooks nothing with the Cooldown Manager unavailable", function()
        ctl.viewer.available = false
        local fresh = ctl.ViewerItem("BuffIconCooldownViewer", 3, 501)
        I.Build(d, 1) -- re-activate
        assert.are.equal(0, I.presence.covered)
        assert.is_nil(fresh.hooks.OnShow)
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
    end)

    it("deactivated, its hooks return at once", function()
        local Q = I.presence
        local n = 0
        Q.onEdge = function()
            n = n + 1
        end
        local d2 = fs.def(fs.new(9))
        I.Build(d2, 1) -- default presence
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true)
        assert.are.equal(0, n)
        assert.are.equal(0, Q.covered)
        assert.are.equal(I.UNDECIDED, Q.Presence(1, 1))
    end)
end)
