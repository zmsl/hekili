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

    it("the pool grows: an acquire is a new child at a fresh layout index", function()
        ctl.ViewerItem(ICON, 1, 501)
        local n = ctl.ViewerAcquire(ICON, 502)
        assert.are.equal(2, viewer(ICON):GetNumChildren())
        assert.are.same({ 2, 502 }, { n.layoutIndex, n.cooldownID })
        ctl.ViewerRemove(ICON, viewer(ICON):GetItemFrames()[1])
        assert.are.equal(3, ctl.ViewerAcquire(ICON, 503).layoutIndex) -- never a repeat of the live index 2
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

        it("under lag an apply and its removal inside one poll light nothing", function()
            ctl.viewer.lag = true
            local item = ctl.ViewerItem(ICON, 1, 501)
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            ctl.ViewerAuraBySpell("player", 1001, false, "player")
            ctl.Tick(101)
            assert.is_nil(item.auraInstanceID)
        end)

        it("an info with links is dark for its base spell and lit by the link only (F4)", function()
            local item = ctl.ViewerItem(ICON, 1, 502) -- spellID 9, linked 1001
            ctl.ViewerAuraBySpell("player", 9, true, "player")
            assert.is_nil(item.auraInstanceID)
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            assert.are.equal(SECRET, item.auraInstanceID)
        end)

        it("GetOverrideSpell applies to the override and tooltip IDs too", function()
            ctl.viewer.infos[510] = { spellID = 1, overrideSpellID = 2, overrideTooltipSpellID = 3 }
            ctl.overrides[2], ctl.overrides[3] = 22, 33
            local item = ctl.ViewerItem(ICON, 1, 510)
            ctl.ViewerAuraBySpell("player", 33, true, "player")
            assert.are.equal(SECRET, item.auraInstanceID)
            ctl.ViewerAuraBySpell("player", 22, true, "player")
            assert.are.equal(SECRET, item.auraInstanceID)
        end)

        it("ViewerFlush lights a pending item without a Tick", function()
            ctl.viewer.lag = true
            local item = ctl.ViewerItem(ICON, 1, 501)
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            assert.is_nil(item.auraInstanceID)
            ctl.ViewerFlush()
            assert.are.equal(SECRET, item.auraInstanceID)
        end)

        it("a re-point of a held item clears it when the new cooldownID does not name the aura", function()
            local item = ctl.ViewerItem(ICON, 1, 501)
            ctl.ViewerAuraBySpell("player", 1001, true, "player")
            ctl.viewer.infos[520] = { spellID = 5555 }
            ctl.ViewerRepoint(item, 520)
            assert.is_nil(item.auraInstanceID)
            ctl.ViewerAura(item, "player", 1001)
            ctl.ViewerRepoint(item, 502) -- links 1001: still named, refreshed
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

    -- CDM Task 8 (the loops' layouts): the harness turns the write log off (L279: it grew one entry per light, unbounded
    -- over a 20-fight boot); an item with no target aura unit (BV:483-485); a released frame back from the pool; the
    -- fight-start reset.
    it("ctl.viewer.log = false records no write; the order tests' default keeps the log", function()
        local item = ctl.ViewerItem(ICON, 1, 501)
        ctl.ViewerAura(item, "player", 77)
        assert.are.same({ "set" }, item.writes)
        ctl.viewer.log = false
        for _ = 1, 50 do
            ctl.ViewerAura(item, "player", 77)
            ctl.ViewerClear(item)
        end
        ctl.ViewerRelease(item)
        assert.are.same({ "set" }, item.writes)
        assert.is_nil(item.cooldownID)
    end)

    it(
        "an item flagged noUnit lights with auraDataUnit nil (a stress flag: the client always records the unit)",
        function()
            ctl.viewer.infos[501] = { spellID = 77 }
            local item = ctl.ViewerItem(ESS, 1, 501)
            item.noUnit = true
            ctl.ViewerAuraBySpell("target", 77, true, "player")
            assert.are.same({ SECRET, nil }, { item.auraInstanceID, item.auraDataUnit })
            ctl.ViewerAuraBySpell("target", 77, false, "player")
            assert.is_nil(item.auraInstanceID)
        end
    )

    it("ViewerAcquire with a released frame reuses it (the pool) and lights it like a new one", function()
        ctl.viewer.infos[501] = { spellID = 77 }
        ctl.ViewerAuraBySpell("player", 77, true, "player")
        local item = ctl.ViewerItem(ICON, 1, 501)
        ctl.ViewerRelease(item)
        local back = ctl.ViewerAcquire(ICON, 501, nil, item)
        assert.are.equal(item, back)
        assert.are.equal(1, viewer(ICON):GetNumChildren())
        assert.are.same({ 501, 1, SECRET, "player" }, { -- index 1: no live child holds it
            back.cooldownID,
            back.layoutIndex,
            back.auraInstanceID,
            back.auraDataUnit,
        })
    end)

    it("ViewerReset clears every item's aura, the applied auras and the pending lights; frames stay", function()
        ctl.viewer.infos[501] = { spellID = 77 }
        local a = ctl.ViewerItem(ICON, 1, 501)
        local b = ctl.ViewerItem(ESS, 1, 501)
        ctl.ViewerAuraBySpell("player", 77, true, "player")
        ctl.viewer.lag = 1
        ctl.ViewerAuraBySpell("target", 77, true, "player")
        ctl.ViewerReset()
        local got = { a.auraInstanceID, b.auraInstanceID, #ctl.viewer.applied, #ctl.viewer.pending }
        assert.are.same({ nil, nil, 0, 0 }, got)
        assert.are.same({ 501, 501 }, { a.cooldownID, b.cooldownID })
        assert.are.equal(1, viewer(ICON):GetNumChildren())
    end)

    it("a re-point's refresh finds an aura its new entry names that is up (silent: none; lag: at the Tick)", function()
        ctl.viewer.infos[501] = { spellID = 77 }
        ctl.viewer.infos[502] = { spellID = 78 }
        ctl.ViewerAuraBySpell("target", 78, true, "player") -- up before the re-point, no item for it yet
        local item = ctl.ViewerItem(ICON, 1, 501)
        ctl.ViewerAuraBySpell("player", 77, true, "player")
        ctl.ViewerRepoint(item, 502)
        assert.are.same({ SECRET, "target", 78 }, { item.auraInstanceID, item.auraDataUnit, item.litBy })
        local quiet = ctl.ViewerItem(ICON, 2, 501)
        quiet.silent = true
        ctl.ViewerRepoint(quiet, 502)
        assert.is_nil(quiet.auraInstanceID)
        local late = ctl.ViewerItem(ICON, 3, 501)
        ctl.viewer.lag = 1
        ctl.ViewerRepoint(late, 502)
        assert.is_nil(late.auraInstanceID)
        ctl.Tick()
        assert.are.equal(SECRET, late.auraInstanceID)
    end)

    it("a re-point's refresh scans the player's auras before the target's, as the client (review m4)", function()
        ctl.viewer.infos[501] = { spellID = 76 }
        ctl.viewer.infos[502] = { spellID = 77 }
        ctl.ViewerAuraBySpell("target", 77, true, "player") -- applied first
        ctl.ViewerAuraBySpell("player", 77, true, "player")
        local item = ctl.ViewerItem(ICON, 1, 501)
        ctl.ViewerRepoint(item, 502)
        assert.are.same({ SECRET, "player" }, { item.auraInstanceID, item.auraDataUnit })
    end)

    it("ViewerRetarget: our target changed: every item held for the target clears, a player item stays", function()
        ctl.viewer.infos[501] = { spellID = 77 }
        ctl.viewer.infos[502] = { spellID = 78 }
        local t = ctl.ViewerItem(ICON, 1, 501)
        local n = ctl.ViewerItem(ESS, 1, 501)
        n.noUnit = true -- held for the target with its unit unread: clears too
        local p = ctl.ViewerItem(ICON, 2, 502)
        ctl.ViewerAuraBySpell("target", 77, true, "player")
        ctl.ViewerAuraBySpell("player", 78, true, "player")
        ctl.ViewerRetarget()
        assert.are.same({ nil, nil, SECRET }, { t.auraInstanceID, n.auraInstanceID, p.auraInstanceID })
        assert.are.same({ { "player", 78 } }, ctl.viewer.applied)
        local a = ctl.ViewerAcquire(ICON, 501) -- mob A's debuff is no longer up on the target: nothing to light
        assert.is_nil(a.auraInstanceID)
    end)

    it("ViewerReshuffle: items move frames, keeping lit state, flags and layoutIndex", function()
        for id = 501, 504 do
            ctl.viewer.infos[id] = { spellID = id - 400 }
        end
        local f = {
            ctl.ViewerItem(ICON, 1, 501),
            ctl.ViewerItem(ICON, 2, 502),
            ctl.ViewerItem(ICON, 3, 503),
            ctl.ViewerItem(ICON, 4, nil), -- unconfigured: stays
        }
        f[3].silent = true
        local e = ctl.ViewerItem(ESS, 1, 504)
        ctl.ViewerAuraBySpell("player", 101, true, "player")
        ctl.viewer.lag = 1
        ctl.ViewerAuraBySpell("target", 102, true, "player") -- pending: lands on 502's frame, wherever it moves
        ctl.ViewerReshuffle(1)
        local by = {}
        for i = 1, 3 do
            assert.are_not.equal(500 + i, f[i].cooldownID) -- never the identity
            by[f[i].cooldownID] = f[i]
            assert.are.equal(f[i].cooldownID - 500, f[i].layoutIndex) -- the item's index moves with it
        end
        assert.are.same({ nil, 4 }, { f[4].cooldownID, f[4].layoutIndex })
        assert.are.same({ 504, 1 }, { e.cooldownID, e.layoutIndex }) -- one item: nowhere to move
        assert.are.same({ SECRET, "player", 101 }, { by[501].auraInstanceID, by[501].auraDataUnit, by[501].litBy })
        assert.is_nil(by[502].auraInstanceID)
        assert.is_true(by[503].silent)
        ctl.ViewerFlush()
        assert.are.same({ SECRET, "target" }, { by[502].auraInstanceID, by[502].auraDataUnit })
        ctl.ViewerReshuffle(2) -- another counter, another permutation; still a bijection
        local seen = {}
        for i = 1, 3 do
            seen[f[i].cooldownID] = true
        end
        assert.are.same({ [501] = true, [502] = true, [503] = true }, seen)
    end)

    it("reshuffleDark: a moved lit item reads dark on its new frame until the next flush, then re-lights", function()
        for id = 501, 503 do
            ctl.viewer.infos[id] = { spellID = id - 400 }
        end
        local f = { ctl.ViewerItem(ICON, 1, 501), ctl.ViewerItem(ICON, 2, 502), ctl.ViewerItem(ICON, 3, 503) }
        ctl.ViewerAuraBySpell("player", 101, true, "player")
        ctl.ViewerAuraBySpell("target", 102, true, "player")
        ctl.viewer.reshuffleDark = true
        ctl.ViewerReshuffle(1)
        local by = {}
        for i = 1, 3 do
            by[f[i].cooldownID] = f[i]
            assert.is_nil(f[i].auraInstanceID) -- every frame dark for one flush
        end
        ctl.ViewerAuraBySpell("target", 102, false, "player") -- gone before the flush: stays dark
        ctl.ViewerFlush()
        assert.are.same({ SECRET, "player", 101 }, { by[501].auraInstanceID, by[501].auraDataUnit, by[501].litBy })
        assert.is_nil(by[502].auraInstanceID)
        assert.is_nil(by[503].auraInstanceID)
        ctl.viewer.reshuffleDark = false -- the default: atomic, the lit item stays lit
        ctl.ViewerReshuffle(2)
        local lit = 0
        for i = 1, 3 do
            lit = lit + (f[i].auraInstanceID ~= nil and 1 or 0)
        end
        assert.are.equal(1, lit)
    end)

    it("ViewerRetarget reshuffles every viewer when ctl.viewer.reshuffle is set (the full UNIT_AURA update)", function()
        ctl.viewer.infos[501] = { spellID = 101 }
        ctl.viewer.infos[502] = { spellID = 102 }
        local a, b = ctl.ViewerItem(ICON, 1, 501), ctl.ViewerItem(ICON, 2, 502)
        ctl.ViewerAuraBySpell("player", 101, true, "player")
        ctl.ViewerAuraBySpell("target", 102, true, "player")
        ctl.ViewerRetarget()
        assert.are.same({ 501, 502 }, { a.cooldownID, b.cooldownID }) -- off by default
        ctl.viewer.reshuffle = true
        ctl.ViewerRetarget()
        assert.are.same({ 502, 501 }, { a.cooldownID, b.cooldownID })
        assert.are.same({ nil, SECRET }, { a.auraInstanceID, b.auraInstanceID }) -- the player item stays lit
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
