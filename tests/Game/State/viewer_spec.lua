-- tests/Game/State/viewer_spec.lua: the Cooldown Manager leaf. The map and the collect (cdm-default spec §3.1-§3.2,
-- plan Task 3a) against the any-layout fake; the providers-spec hook block (§2.4, decisions 77-79) kept until Task 3b's
-- sweep replaces it (~/src/hekili-central-needs/cdm-3a.md §2).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

describe("the CooldownViewer leaf's hook block (until Task 3b)", function()
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
        d = fs.def(fs.new(9))
        d.providers = { presence = "viewer" }
        I.Build(d, 1)
        VS.Start(api)
    end)

    it("covers the aura viewers' mapped items", function()
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
        ctl.ViewerRemove("BuffIconCooldownViewer", items.BuffIconCooldownViewer[2]) -- aura 2: only an Essential item
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

-- The map and the collect (cdm-default spec §3.1-§3.2, decisions 97-98, 101; plan Task 3a), against the any-layout fake
-- (fake_api.lua: ctl.viewer, ViewerItem, ViewerChild, ViewerAcquire, ViewerRemove).
describe("the CooldownViewer leaf: the map (cdm-default §3.1)", function()
    local VS, I, ctl, api, d, Q

    -- auras 1-2 are fs.def's (spender_a, spender_c and its rank 2); 3-5 are added here: SPENDER_M, SPENDER_S, SPENDER_H
    local function start()
        local ns = load.module()
        VS = ns.VirtualState
        I = ns.VirtualStateInternal
        d = fs.def(fs.new(9))
        for _, id in ipairs({ fs.SPENDER_M, fs.SPENDER_S, fs.SPENDER_H }) do
            local n = #d.auras + 1
            d.auras[n], d.auraIds[n] = { key = "aura_" .. id, id = id }, { id }
        end
        d.providers = { presence = "router", viewer = true }
        I.Build(d, 1)
        VS.Start(api)
        Q = I.PRESENCE.viewer
    end
    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
    end)

    it(
        "maps by spellID, overrideSpellID, overrideTooltipSpellID, linkedSpellIDs and GetOverrideSpell;"
            .. " never the singular linkedSpellID",
        function()
            ctl.viewer.sets[0] = { 601, 602, 603 }
            ctl.viewer.sets[2] = { 604, 605, 606 }
            ctl.viewer.infos[601] = { spellID = fs.SPENDER_A }
            ctl.viewer.infos[602] = { overrideSpellID = fs.SPENDER_C_R2 } -- any rank
            ctl.viewer.infos[603] = { overrideTooltipSpellID = fs.SPENDER_M }
            ctl.viewer.infos[604] = { spellID = 9999, linkedSpellIDs = { fs.SPENDER_S } } -- links only: 9999 ignored
            ctl.viewer.infos[605] = { spellID = 9998 }
            ctl.overrides[9998] = fs.SPENDER_H -- GetOverrideSpell names aura 5; the untracked base makes it ambiguous
            ctl.viewer.infos[606] = { spellID = 9997, linkedSpellID = fs.SPENDER_A } -- the singular: never read
            start()
            assert.are.equal(1, Q.map[601])
            assert.are.equal(2, Q.map[602])
            assert.are.equal(3, Q.map[603])
            assert.are.equal(4, Q.map[604])
            assert.is_true(Q.map[605] < 0)
            assert.are.same({ 5 }, Q.amb[-Q.map[605]])
            assert.is_nil(Q.map[606])
            for j = 1, 5 do
                assert.is_true(Q.Mappable(j), j)
                assert.is_true(I.presence.tracked[j], j) -- the router's tracked set reads the leaf
            end
        end
    )

    it("GetOverrideSpell's answer is a candidate (an untracked base beside it: ambiguous)", function()
        ctl.viewer.sets[0] = { 601 }
        ctl.viewer.infos[601] = { spellID = 9996 }
        start()
        assert.is_nil(Q.map[601])
        assert.is_false(Q.Mappable(1))
        ctl.overrides[9996] = fs.SPENDER_A
        I.Build(d, 1) -- a rebuild (a spec change re-activates the leaf)
        assert.is_true(Q.map[601] < 0)
        assert.are.same({ 1 }, Q.amb[-Q.map[601]])
        assert.is_true(Q.Mappable(1))
    end)

    it("maps unlearned entries (allowUnlearned)", function()
        ctl.viewer.unlearned[1] = { 701 }
        ctl.viewer.infos[701] = { spellID = fs.SPENDER_A }
        start()
        assert.are.equal(1, Q.map[701])
        assert.is_true(Q.Mappable(1))
    end)

    it("Omen-like: linked proc tracked, passive untracked: UP counts for the proc", function()
        ctl.viewer.sets[3] = { 801 }
        ctl.viewer.infos[801] = { spellID = 9990, linkedSpellIDs = { fs.SPENDER_A } }
        start()
        assert.are.equal(1, Q.map[801]) -- one j: unambiguous, so its UP counts for aura 1
    end)

    it(
        "Eclipse-like: two linked procs, the pack tracks one: ambiguous (maps to the tracked one), UP counts for none",
        function()
            ctl.viewer.sets[3] = { 802 }
            ctl.viewer.infos[802] = { spellID = 9991, linkedSpellIDs = { fs.SPENDER_A, 9992 } }
            start()
            local m = Q.map[802]
            assert.is_true(m < 0)
            assert.are.same({ 1 }, Q.amb[-m])
            assert.is_true(Q.Mappable(1))
            assert.is_false(Q.Mappable(2))
        end
    )

    it("an item naming two pack auras is ambiguous: maps to both, UP for neither", function()
        ctl.viewer.sets[0] = { 803 }
        ctl.viewer.infos[803] = { spellID = fs.SPENDER_A, overrideSpellID = fs.SPENDER_C }
        start()
        local m = Q.map[803]
        assert.is_true(m < 0)
        local js = Q.amb[-m]
        table.sort(js)
        assert.are.same({ 1, 2 }, js)
        assert.is_true(Q.Mappable(1))
        assert.is_true(Q.Mappable(2))
    end)

    it("a NEW pack aura added to the fake viewer with no code change is mapped", function()
        ctl.viewer.sets[2] = { 901 }
        ctl.viewer.infos[901] = { spellID = 424242 }
        local ns = load.module()
        I = ns.VirtualStateInternal
        d = fs.def(fs.new(9))
        local n = #d.auras + 1
        d.auras[n], d.auraIds[n] = { key = "brand_new", id = 424242 }, { 424242 }
        d.providers = { presence = "router", viewer = true }
        I.Build(d, 1)
        ns.VirtualState.Start(api)
        Q = I.PRESENCE.viewer
        assert.are.equal(n, Q.map[901])
        assert.is_true(Q.Mappable(n))
        assert.is_true(I.presence.tracked[n])
    end)

    it("nothing is mappable with the Cooldown Manager unavailable, or for the Default provider", function()
        ctl.viewer.sets[0] = { 601 }
        ctl.viewer.infos[601] = { spellID = fs.SPENDER_A }
        ctl.viewer.available = false
        start()
        assert.is_false(Q.Mappable(1))
        assert.is_false(I.PRESENCE.default.Mappable(1))
    end)

    it("rebuilds on COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED out of combat; in combat at combat end", function()
        ctl.viewer.sets[0] = { 601 }
        ctl.viewer.infos[601] = { spellID = 9996 }
        start()
        assert.is_false(Q.Mappable(1))
        ctl.combat = true
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.overrides[9996] = fs.SPENDER_A
        ctl.viewer.infos[601] = { spellID = fs.SPENDER_A }
        ctl.Fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
        assert.is_false(Q.Mappable(1)) -- the map changes only out of combat
        ctl.combat = false
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(Q.Mappable(1))
        ctl.viewer.infos[602] = { spellID = fs.SPENDER_C }
        ctl.viewer.sets[0][2] = 602
        ctl.Fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
        assert.is_true(Q.Mappable(2))
    end)
end)

describe("the CooldownViewer leaf: the collect (cdm-default §3.2)", function()
    local VS, I, ctl, api, d, Q
    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        ctl.viewer.sets[0] = { 501 }
        ctl.viewer.sets[2] = { 502 }
        ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
        ctl.viewer.infos[502] = { spellID = fs.SPENDER_A }
        -- several items per spell across viewers, an unconfigured slot, a non-item child, a hidden viewer
        ctl.ViewerItem("EssentialCooldownViewer", 1, 501)
        ctl.ViewerItem("EssentialCooldownViewer", 2, nil)
        ctl.ViewerChild("EssentialCooldownViewer")
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        ctl.ViewerItem("BuffBarCooldownViewer", 1, 502)
        ctl.viewer.shown.BuffBarCooldownViewer = false
        local ns = load.module()
        VS = ns.VirtualState
        I = ns.VirtualStateInternal
        d = fs.def(fs.new(9))
        d.providers = { presence = "router", viewer = true }
        I.Build(d, 1)
        VS.Start(api)
        Q = I.PRESENCE.viewer
    end)
    local function inCombat()
        ctl.combat = true
        ctl.Fire("PLAYER_REGEN_DISABLED")
    end
    local function all()
        local n = 0
        for _, name in ipairs(fake.VIEWERS) do
            for _, c in ipairs(ctl.viewer.items[name]) do
                assert.is_not_nil(Q.slotOf[c])
                n = n + 1
            end
        end
        return n
    end

    it(
        "the collect keeps every child once, items and non-items; past MAX_SLOTS a child is ignored and counted (overflow)",
        function()
            assert.are.equal(5, all()) -- the hidden viewer's children too: visibility is a sweep-time rule
            assert.are.equal(5, Q.nSlots)
            local seen = {}
            for _, name in ipairs(fake.VIEWERS) do
                for _, c in ipairs(ctl.viewer.items[name]) do
                    assert.is_nil(seen[Q.slotOf[c]])
                    seen[Q.slotOf[c]] = true
                end
            end
            I.Build(d, 1) -- a rebuild collects again: still once each
            assert.are.equal(5, Q.nSlots)
            assert.are.equal(0, Q.overflow)
            for _ = 1, Q.MAX_SLOTS - 5 + 2 do
                ctl.ViewerChild("UtilityCooldownViewer")
            end
            I.Build(d, 1)
            assert.are.equal(128, Q.MAX_SLOTS)
            assert.are.equal(Q.MAX_SLOTS, Q.nSlots)
            assert.are.equal(2, Q.overflow)
            I.Build(d, 1) -- counted once per child, not once per collect
            assert.are.equal(2, Q.overflow)
            inCombat()
            ctl.ViewerAcquire("UtilityCooldownViewer", 501)
            Q.Collect()
            assert.are.equal(Q.MAX_SLOTS, Q.nSlots)
            assert.are.equal(3, Q.overflow)
        end
    )

    it(
        "collects at activation, rebuild and PLAYER_REGEN_ENABLED; in combat only on GetNumChildren growth,"
            .. " the new indices only, allocating no table",
        function()
            local v = api.UtilityCooldownViewer
            local getChildren, calls = v.GetChildren, 0
            v.GetChildren = function(...)
                calls = calls + 1
                return getChildren(...)
            end
            -- rebuild: an item added out of combat is collected by the rebuild event
            local a = ctl.ViewerItem("UtilityCooldownViewer", 1, 501)
            ctl.Fire("COOLDOWN_VIEWER_DATA_LOADED")
            assert.is_not_nil(Q.slotOf[a])
            inCombat()
            -- no growth: no GetChildren call, no allocation
            calls = 0
            local ok, bytes = pcall(alloc.bytes, function()
                Q.Collect()
            end, 1000)
            assert.is_true(ok, tostring(bytes))
            assert.are.equal(0, bytes)
            assert.are.equal(0, calls)
            -- growth in combat: the new index only (one GetChildren per new child), the new frame a new slot
            local function bytesOf(fn)
                collectgarbage("collect")
                collectgarbage("stop")
                local before = collectgarbage("count")
                fn()
                local after = collectgarbage("count")
                collectgarbage("restart")
                return (after - before) * 1024
            end
            local b = ctl.ViewerAcquire("UtilityCooldownViewer", 501)
            calls = 0
            local grew = bytesOf(Q.Collect)
            assert.are.equal(1, calls)
            assert.is_not_nil(Q.slotOf[b])
            assert.is_true(grew < 1024, "only the frame-to-slot entry (a weak-map insert, maybe a rehash): " .. grew)
            -- growth onto a frame it already holds: the walk itself allocates nothing (no table of children)
            local list = ctl.viewer.items.UtilityCooldownViewer
            for round = 1, 2 do
                table.remove(list) -- b leaves the child list ...
                Q.Collect() -- ... the count drops ...
                list[#list + 1] = b -- ... and the same frame comes back: growth, a known frame
                local again = bytesOf(Q.Collect)
                if round == 2 then -- the first round may grow Lua's own stack once
                    assert.are.equal(0, again)
                end
            end
            -- a removal seen, then a re-add as a NEW frame table: a new slot, the old one never reused
            local old = Q.slotOf[b]
            ctl.ViewerRemove("UtilityCooldownViewer", b)
            Q.Collect()
            local c = ctl.ViewerAcquire("UtilityCooldownViewer", 501)
            Q.Collect()
            assert.is_not_nil(Q.slotOf[c])
            assert.are_not.equal(old, Q.slotOf[c])
            assert.are.equal(old, Q.slotOf[b]) -- the dropped frame keeps its slot (it is just never live: §2.2)
            -- grown in combat with no Collect call: PLAYER_REGEN_ENABLED collects it
            local e = ctl.ViewerAcquire("EssentialCooldownViewer", 501)
            assert.is_nil(Q.slotOf[e])
            ctl.combat = false
            ctl.Fire("PLAYER_REGEN_ENABLED")
            assert.is_not_nil(Q.slotOf[e])
        end
    )

    it(
        "no hooksecurefunc; the collect, combat end and the cooldown viewers add no HookScript (cdm-3a.md §2)",
        function()
            local before = #ctl.viewer.hookCalls
            inCombat()
            local b = ctl.ViewerAcquire("BuffIconCooldownViewer", 502)
            ctl.ViewerAcquire("EssentialCooldownViewer", 501)
            Q.Collect()
            ctl.combat = false
            ctl.Fire("PLAYER_REGEN_ENABLED")
            assert.are.equal(before, #ctl.viewer.hookCalls) -- the collect and combat end hook nothing
            assert.is_nil(next(b.hooks))
            I.Build(d, 1)
            for _, call in ipairs(ctl.viewer.hookCalls) do -- only the legacy block's HookScript, on aura viewer items
                assert.is_true(call[2] == "OnShow" or call[2] == "OnHide")
                assert.is_true(Q.slotOf[call[1]] ~= nil)
            end
            for _, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer" }) do
                for _, c in ipairs(ctl.viewer.items[name]) do
                    assert.is_nil(c.hooks and next(c.hooks))
                end
            end
        end
    )
end)
