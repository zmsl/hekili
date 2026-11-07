-- tests/Game/State/fake_viewer_spec.lua: the any-layout Cooldown Manager fake (fake_api.lua), pinned capability by
-- capability, and that the default fake still has no viewer layout (the default arm stays viewer-off).
local fake = require("Game.State.helpers.fake_api")
local SECRET = fake.SECRET
local ICON, ESS = "BuffIconCooldownViewer", "EssentialCooldownViewer"

describe("the any-layout Cooldown Manager fake", function()
    local api, ctl

    before_each(function()
        api, ctl = fake.new()
    end)

    local function viewer(name)
        return api[name]
    end

    it("starts empty and visible: no set, no item, nothing hooked", function()
        for _, name in ipairs(fake.VIEWERS) do
            assert.are.equal(0, viewer(name):GetNumChildren())
            assert.is_true(viewer(name):IsVisible())
        end
        assert.are.same({}, ctl.viewer.sets[2])
        assert.are.same({}, ctl.viewer.hookCalls)
        assert.is_nil(ctl.viewer.items[ICON][1])
    end)

    it("models unconfigured slots and non-item children", function()
        local slot = ctl.ViewerItem(ICON, 1, nil)
        local child = ctl.ViewerChild(ICON)
        local item = ctl.ViewerItem(ICON, 2, 501)
        assert.is_nil(slot.cooldownID)
        assert.is_nil(child.cooldownID)
        assert.is_nil(child.layoutIndex)
        assert.are.equal(3, viewer(ICON):GetNumChildren())
        local a, b, c = viewer(ICON):GetChildren()
        assert.are.same({ slot, child, item }, { a, b, c })
        local frames = viewer(ICON):GetItemFrames()
        assert.are.same({ slot, item }, frames)
    end)

    it("IsVisible follows its own flag and the parent's", function()
        ctl.viewer.shown[ESS] = false
        assert.is_false(viewer(ESS):IsVisible())
        assert.is_true(viewer(ICON):IsVisible())
        ctl.viewer.shown[ESS] = nil
        ctl.viewer.parentShown = false
        assert.is_false(viewer(ESS):IsVisible())
        assert.is_false(viewer(ICON):IsVisible())
    end)

    it("the pool grows, in combat too", function()
        ctl.ViewerItem(ICON, 1, 501)
        ctl.combat = true
        local n = ctl.ViewerAcquire(ICON, 502)
        assert.are.equal(2, viewer(ICON):GetNumChildren())
        assert.are.same({ 2, 502 }, { n.layoutIndex, n.cooldownID })
    end)

    it("ViewerAura clears a held aura first, then sets (secret id; secret or plain spell)", function()
        local item = ctl.ViewerItem(ICON, 1, 501)
        ctl.ViewerAura(item, "target", 77)
        assert.are.same(
            { SECRET, "target", SECRET, true },
            { item.auraInstanceID, item.auraDataUnit, item.auraSpellID, item.shown }
        )
        assert.are.same({ "set" }, item.writes)
        ctl.ViewerAura(item, "player", 77)
        assert.are.same({ "set", "clear", "set" }, item.writes)
        assert.are.equal("player", item.auraDataUnit)
        ctl.viewer.plainSpell = true
        ctl.ViewerAura(item, "player", 77)
        assert.are.equal(77, item.auraSpellID)
        ctl.ViewerClear(item)
        assert.are.same(
            { nil, nil, nil, false },
            { item.auraInstanceID, item.auraDataUnit, item.auraSpellID, item.shown }
        )
    end)

    it("ViewerRelease: cooldownID first, then the aura clear, then layoutIndex", function()
        local item = ctl.ViewerItem(ICON, 1, 501)
        ctl.ViewerAura(item, "player", 77)
        ctl.ViewerRelease(item)
        assert.are.same({ "set", "cooldownID", "clear", "layoutIndex" }, item.writes)
        assert.is_nil(item.cooldownID)
        assert.is_nil(item.layoutIndex)
        assert.is_nil(item.auraInstanceID)
    end)

    it("ViewerRepoint sets the cooldownID, then refreshes a held aura (clear, set)", function()
        local item = ctl.ViewerItem(ICON, 1, 501)
        ctl.ViewerRepoint(item, 502)
        assert.are.same({ "cooldownID" }, item.writes)
        ctl.ViewerAura(item, "player", 77)
        ctl.ViewerRepoint(item, 503)
        assert.are.equal(503, item.cooldownID)
        assert.are.same({ "cooldownID", "set", "cooldownID", "clear", "set" }, item.writes)
        assert.are.equal("player", item.auraDataUnit)
    end)

    it("GetCooldownViewerCategorySet adds the unlearned entries only when asked", function()
        ctl.viewer.sets[2] = { 501 }
        ctl.viewer.unlearned[2] = { 509 }
        assert.are.same({ 501 }, api.C_CooldownViewer.GetCooldownViewerCategorySet(2))
        assert.are.same({ 501 }, api.C_CooldownViewer.GetCooldownViewerCategorySet(2, false))
        assert.are.same({ 501, 509 }, api.C_CooldownViewer.GetCooldownViewerCategorySet(2, true))
        assert.are.same({}, api.C_CooldownViewer.GetCooldownViewerCategorySet(0, true))
    end)

    it(
        "infos carry the override, tooltip, linked and secret-singular fields; GetOverrideSpell reads ctl.overrides",
        function()
            ctl.viewer.infos[501] = {
                spellID = 1,
                overrideSpellID = 2,
                overrideTooltipSpellID = 3,
                linkedSpellIDs = { 4, 5 },
                linkedSpellID = SECRET,
                hasAura = true,
                selfAura = true,
            }
            local i = api.C_CooldownViewer.GetCooldownViewerCooldownInfo(501)
            assert.is_true(api.issecretvalue(i.linkedSpellID))
            assert.are.same(
                { 2, 3, 4, 5 },
                { i.overrideSpellID, i.overrideTooltipSpellID, i.linkedSpellIDs[1], i.linkedSpellIDs[2] }
            )
            assert.are.equal(9, api.C_Spell.GetOverrideSpell(9))
            ctl.overrides[9] = 10
            assert.are.equal(10, api.C_Spell.GetOverrideSpell(9))
        end
    )

    describe("ViewerAuraBySpell", function()
        before_each(function()
            ctl.viewer.infos[501] = { spellID = 1001 }
            ctl.viewer.infos[502] = { spellID = 9, linkedSpellIDs = { 1001 } }
            ctl.viewer.infos[503] = { spellID = 1004 } -- lists rank 2
            ctl.viewer.infos[504] = { spellID = 7, overrideTooltipSpellID = 1001 }
        end)

        it("lights every configured item in any viewer that names the spell, several per spell", function()
            local a = ctl.ViewerItem(ICON, 1, 501)
            local b = ctl.ViewerItem(ESS, 1, 502)
            local c = ctl.ViewerItem(ESS, 2, 504)
            local other = ctl.ViewerItem(ICON, 2, 503)
            local slot = ctl.ViewerItem(ICON, 3, nil)
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            assert.are.same({ SECRET, SECRET, SECRET }, { a.auraInstanceID, b.auraInstanceID, c.auraInstanceID })
            assert.is_nil(other.auraInstanceID)
            assert.is_nil(slot.auraInstanceID)
            ctl.ViewerAuraBySpell("player", 1001, false, "player")
            assert.is_nil(a.auraInstanceID)
            assert.is_nil(c.auraInstanceID)
        end)

        it("a partner's copy of the aura lights nothing", function()
            local a = ctl.ViewerItem(ICON, 1, 501)
            ctl.ViewerAuraBySpell("player", 1001, true, "party1")
            assert.is_nil(a.auraInstanceID)
        end)

        it("an item listing rank 2 stays silent for a rank 3 aura (F12)", function()
            local item = ctl.ViewerItem(ICON, 1, 503)
            ctl.ViewerAuraBySpell("player", 1005, true, "player")
            assert.is_nil(item.auraInstanceID)
            ctl.ViewerAuraBySpell("player", 1004, true, "player")
            assert.are.equal(SECRET, item.auraInstanceID)
        end)

        it("a target item lights for the target's aura only", function()
            local t = ctl.ViewerItem(ICON, 1, 501)
            t.unit = "target"
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            assert.is_nil(t.auraInstanceID)
            ctl.ViewerAuraBySpell("target", 1001, true, "player")
            assert.are.same({ SECRET, "target" }, { t.auraInstanceID, t.auraDataUnit })
        end)

        it("a silent item exists but never lights", function()
            local item = ctl.ViewerItem(ICON, 1, 501)
            item.silent = true
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            assert.is_nil(item.auraInstanceID)
            assert.are.equal(1, viewer(ICON):GetNumChildren())
        end)

        it("an item that appears mid-fight lights at the next apply; a released one never does", function()
            ctl.combat = true
            local late = ctl.ViewerAcquire(ICON, 501)
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            assert.are.equal(SECRET, late.auraInstanceID)
            ctl.ViewerRelease(late)
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            assert.is_nil(late.auraInstanceID)
        end)

        it("lag lights the item one poll after, not in the same call", function()
            ctl.viewer.lag = true
            local item = ctl.ViewerItem(ICON, 1, 501)
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            assert.is_nil(item.auraInstanceID)
            ctl.Tick(101)
            assert.are.equal(SECRET, item.auraInstanceID)
            ctl.ViewerAuraBySpell("player", 1001, false, "player") -- removal stays immediate
            assert.is_nil(item.auraInstanceID)
        end)

        it("under lag a held item's refresh stays held: clear and set move together at the next Tick", function()
            local item = ctl.ViewerItem(ICON, 1, 501)
            ctl.ViewerAura(item, "player", 1001)
            ctl.viewer.lag = true
            ctl.viewer.shown[ICON] = nil
            ctl.ViewerAuraBySpell("player", 1001, true, "player") -- the refresh
            assert.are.equal(SECRET, item.auraInstanceID) -- never nil in between
            assert.are.same({ "set" }, item.writes)
            ctl.Tick(101)
            assert.are.same({ "set", "clear", "set" }, item.writes)
            assert.are.equal(SECRET, item.auraInstanceID)
        end)

        it("an acquire is a new frame each time; a removal drops the frame from GetItemFrames", function()
            local a = ctl.ViewerAcquire(ICON, 501)
            ctl.ViewerRemove(ICON, a)
            assert.are.same({}, viewer(ICON):GetItemFrames())
            assert.are.equal(0, viewer(ICON):GetNumChildren())
            assert.is_nil(a.cooldownID)
            local b = ctl.ViewerAcquire(ICON, 501)
            assert.are_not.equal(a, b)
            assert.are.same({ b }, viewer(ICON):GetItemFrames())
        end)

        it("a re-added item lights at once for a still-running application, unless silent or lagged", function()
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            local b = ctl.ViewerAcquire(ICON, 501)
            assert.are.equal(SECRET, b.auraInstanceID)
            local s = ctl.ViewerAcquire(ICON, 501, true)
            assert.is_nil(s.auraInstanceID)
            ctl.viewer.lag = true
            local l = ctl.ViewerAcquire(ICON, 501)
            assert.is_nil(l.auraInstanceID)
            ctl.Tick(101)
            assert.are.equal(SECRET, l.auraInstanceID)
            ctl.ViewerAuraBySpell("player", 1001, false, "player")
            local after = ctl.ViewerAcquire(ICON, 501)
            ctl.Tick(102)
            assert.is_nil(after.auraInstanceID) -- the aura ended: nothing to light
        end)
    end)

    it("HookScript on items and hooksecurefunc record their calls", function()
        local item = ctl.ViewerItem(ICON, 1, 501)
        local fn = function() end
        item:HookScript("OnShow", fn)
        api.hooksecurefunc(item, "Show", fn)
        assert.are.equal(2, #ctl.viewer.hookCalls)
        assert.are.same({ item, "OnShow" }, ctl.viewer.hookCalls[1])
        assert.are.equal(item, ctl.viewer.hookCalls[2][1])
    end)

    it("the legacy ViewerShow still works and a fresh fake has no viewer layout (default arm: viewer off)", function()
        local item = ctl.ViewerItem(ICON, 1, 501)
        item.unit = "player"
        ctl.ViewerShow(item, true)
        assert.are.same({ SECRET, "player" }, { item.auraInstanceID, item.auraDataUnit })
        ctl.ViewerShow(item, false)
        assert.is_nil(item.auraInstanceID)
        local _, fresh = fake.new()
        assert.are.same({ {}, {}, {}, {} }, {
            fresh.viewer.items[fake.VIEWERS[1]],
            fresh.viewer.items[fake.VIEWERS[2]],
            fresh.viewer.items[fake.VIEWERS[3]],
            fresh.viewer.items[fake.VIEWERS[4]],
        })
    end)
end)
