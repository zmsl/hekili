-- tests/Game/State/viewer_spec.lua: the Cooldown Manager leaf. The map and the collect (cdm-default spec §3.1-§3.2,
-- plan Task 3a) against the any-layout fake; the providers-spec hook block (§2.4, decisions 77-79) kept until Task 3b's
-- sweep replaces it (~/src/hekili-central-needs/cdm-3a.md §2).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

-- The sweep (cdm-default spec §3.2, decisions 95-96, 100, 102; plan Task 3b): every slot read by rawget at poll 15,
-- counted per thing (aura j, unit u) as nLive, nUp, nNone, nStale, tUp, tNone, against the any-layout fake. Until
-- Task 3c's seen rule, a silent mapped slot counts as NONE for its last held unit (the player if it held none).
describe("the CooldownViewer leaf: the sweep (cdm-default §3.2)", function()
    local VS, I, ctl, api, d, Q
    local A, C = fs.SPENDER_A, fs.SPENDER_C_R2 -- aura 1 (spender_a), aura 2 (spender_c, by its rank 2)

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        ctl.viewer.sets[0] = { 501 }
        ctl.viewer.sets[2] = { 502, 503 }
        ctl.viewer.infos[501] = { spellID = A } -- a cooldown entry (Essential) for aura 1
        ctl.viewer.infos[502] = { spellID = A } -- a Buff icon entry for aura 1
        ctl.viewer.infos[503] = { spellID = 9999, linkedSpellIDs = { C } } -- aura 2, by a link
        ctl.viewer.infos[504] = { spellID = 9998 } -- unmapped
    end)
    local function start()
        local ns = load.module()
        VS = ns.VirtualState
        I = ns.VirtualStateInternal
        d = fs.def(fs.new(9))
        d.providers = { presence = "router", viewer = true }
        I.Build(d, 1)
        VS.Start(api)
        Q = I.PRESENCE.viewer
    end
    local function sweep(t)
        ctl.now = t
        I.presence.Sweep(t)
    end
    local function counts(j, u)
        return { Q.Counts(j, u) }
    end
    local function up(spell, unit)
        ctl.ViewerAuraBySpell(unit or "player", spell, true, "player")
    end
    local function down(spell, unit)
        ctl.ViewerAuraBySpell(unit or "player", spell, false, "player")
    end

    it(
        "a cooldown entry (Essential) holding an aura is UP evidence; a Buff icon entry for the same aura agrees",
        function()
            ctl.ViewerItem("EssentialCooldownViewer", 1, 501)
            ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            start()
            assert.are.same({ 2, 0, 2, 0, 0, 1 }, counts(1, 1)) -- read at activation: both silent
            up(A)
            sweep(2)
            assert.are.same({ 2, 2, 0, 0, 2, 1 }, counts(1, 1))
            assert.are.equal(I.UP, I.presence.Presence(1, 1))
            assert.are.equal(1, I.presence.covered)
            up(A) -- the Essential entry alone: still UP evidence (F6)
            ctl.ViewerClear(ctl.viewer.items.BuffIconCooldownViewer[1])
            sweep(3)
            assert.are.same({ 2, 1, 1, 0, 2, 3 }, counts(1, 1)) -- until Task 3c a silent slot is NONE: the UP is older
            assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
        end
    )

    it("no item in any viewer: counts all zero", function()
        start()
        up(A)
        sweep(2)
        for u = 1, 2 do
            for j = 1, 2 do
                assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(j, u))
            end
        end
        assert.are.equal(0, I.presence.covered)
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
    end)

    it("an unconfigured slot, a non-item child, an unmapped id and a secret cooldownID are not live", function()
        local items = {
            ctl.ViewerItem("EssentialCooldownViewer", 1, nil),
            ctl.ViewerChild("EssentialCooldownViewer"),
            ctl.ViewerItem("EssentialCooldownViewer", 2, 504),
            ctl.ViewerItem("UtilityCooldownViewer", 1, fake.SECRET),
            ctl.ViewerItem("UtilityCooldownViewer", fake.SECRET, 501), -- a secret layoutIndex
        }
        start()
        for _, item in ipairs(items) do
            item.auraInstanceID, item.auraDataUnit = fake.SECRET, "player" -- every one holds an aura
        end
        sweep(2)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.equal(0, I.presence.covered)
        ctl.ViewerAura(ctl.ViewerAcquire("BuffIconCooldownViewer", 502), "player") -- control: a configured item
        sweep(3)
        assert.are.same({ 1, 1, 0, 0, 3, 0 }, counts(1, 1))
    end)

    it("a held slot for the other unit, or with a secret unit, is not live for this unit", function()
        local a = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        local b = ctl.ViewerItem("BuffIconCooldownViewer", 2, 502)
        local c = ctl.ViewerItem("BuffIconCooldownViewer", 3, 502)
        start()
        ctl.ViewerAura(a, "target")
        ctl.ViewerAura(b, fake.SECRET)
        ctl.ViewerAura(c, "focus")
        sweep(2)
        assert.are.same({ 0, 0, 0, 0, 0, 1 }, counts(1, 1)) -- (tNone stays the latest begin: activation)
        assert.are.same({ 1, 1, 0, 0, 2, 0 }, counts(1, 2)) -- a's UP is for the target only
        ctl.ViewerAura(c, "player") -- control: plain "player"
        sweep(3)
        assert.are.same({ 1, 1, 0, 0, 3, 1 }, counts(1, 1))
    end)

    it(
        "a viewer that is not visible (itself or its parent) makes its slots stale; visible again they count,"
            .. " with tUp/tNone at that poll",
        function()
            ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            ctl.ViewerItem("BuffBarCooldownViewer", 1, 502)
            ctl.viewer.shown.BuffBarCooldownViewer = false
            start()
            up(A)
            sweep(2)
            assert.are.same({ 1, 1, 0, 1, 2, 1 }, counts(1, 1)) -- the hidden bar's slot: stale
            ctl.viewer.parentShown = false -- Alt-Z: every viewer hidden
            sweep(3)
            assert.are.same({ 0, 0, 0, 2, 2, 1 }, counts(1, 1))
            assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
            assert.are.equal(0, I.presence.covered)
            ctl.viewer.parentShown = true
            ctl.viewer.shown.BuffBarCooldownViewer = nil
            down(A)
            sweep(4)
            assert.are.same({ 2, 0, 2, 0, 2, 4 }, counts(1, 1)) -- they count again, from this poll
            assert.are.equal(I.DOWN, I.presence.Presence(1, 1))
        end
    )

    it("the refresh pair (clear then set in one call) is never seen as NONE", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        up(A)
        sweep(2)
        local edges = {}
        Q.onEdge = function(j, u, isUp)
            edges[#edges + 1] = { j, u, isUp }
        end
        local n = #item.writes
        up(A) -- our refresh: the client clears, then sets, in one call
        assert.are.same({ "clear", "set" }, { item.writes[n + 1], item.writes[n + 2] })
        sweep(3)
        assert.are.same({ 1, 1, 0, 0, 2, 1 }, counts(1, 1)) -- no NONE, and no new UP begin either
        assert.are.same({}, edges)
    end)

    it("a release, held or not, drops the slot (no NONE)", function()
        local a = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        local b = ctl.ViewerItem("BuffIconCooldownViewer", 2, 503)
        start()
        up(A)
        sweep(2)
        assert.are.same({ 1, 1, 0, 0, 2, 1 }, counts(1, 1))
        assert.are.same({ 1, 0, 1, 0, 0, 1 }, counts(2, 1)) -- b silent: NONE (until Task 3c)
        ctl.ViewerRelease(a) -- held: cooldownID nil first, then the clear
        ctl.ViewerRelease(b) -- silent
        sweep(3)
        assert.are.same({ 0, 0, 0, 0, 2, 1 }, counts(1, 1))
        assert.are.same({ 0, 0, 0, 0, 0, 1 }, counts(2, 1))
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1)) -- UNKNOWN, never DOWN
        assert.are.equal(I.UNDECIDED, I.presence.Presence(2, 1))
        assert.are.equal(0, I.presence.covered)
    end)

    it("a re-point moves the slot's evidence from the old aura to the new", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        up(A)
        sweep(2)
        ctl.ViewerRepoint(item, 503) -- now aura 2: the refresh finds no aura 2 on us, the item clears
        sweep(3)
        assert.are.same({ 0, 0, 0, 0, 2, 1 }, counts(1, 1))
        assert.are.same({ 1, 0, 1, 0, 0, 3 }, counts(2, 1))
        up(C)
        sweep(4)
        assert.are.same({ 1, 1, 0, 0, 4, 3 }, counts(2, 1))
        assert.are.equal(I.UP, I.presence.Presence(2, 1))
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
    end)

    it("items appearing (in combat, lit at once) and disappearing move the counts; a silent item is NONE", function()
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        ctl.combat = true
        ctl.Fire("PLAYER_REGEN_DISABLED")
        up(A)
        sweep(2)
        local b = ctl.ViewerAcquire("EssentialCooldownViewer", 501) -- the pool grows: lit at once (F13)
        sweep(3)
        assert.is_not_nil(Q.slotOf[b])
        assert.are.same({ 2, 2, 0, 0, 3, 1 }, counts(1, 1))
        local s = ctl.ViewerAcquire("UtilityCooldownViewer", 501, true) -- a silent item (F12)
        sweep(4)
        assert.are.same({ 3, 2, 1, 0, 3, 4 }, counts(1, 1)) -- until Task 3c the silent item answers NONE
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1)) -- its NONE is the fresher
        ctl.ViewerRemove("UtilityCooldownViewer", s)
        sweep(5)
        assert.are.same({ 2, 2, 0, 0, 3, 4 }, counts(1, 1))
        assert.are.equal(I.UP, I.presence.Presence(1, 1))
    end)

    it("target items answer for the target; a target NONE is no answer through the router", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 503)
        item.unit = "target"
        start()
        up(C, "target")
        sweep(2)
        assert.are.same({ 1, 1, 0, 0, 2, 0 }, counts(2, 2))
        assert.are.equal(I.UP, I.presence.Presence(2, 2))
        down(C, "target")
        sweep(3)
        assert.are.same({ 1, 0, 1, 0, 2, 3 }, counts(2, 2)) -- its last held unit
        assert.are.equal(I.DOWN, Q.Presence(2, 2))
        assert.are.equal(I.UNDECIDED, I.presence.Presence(2, 2)) -- the router's self-scope rule
    end)

    it("an ambiguous item counts for no aura", function()
        ctl.viewer.infos[502] = { spellID = A, overrideSpellID = fs.SPENDER_C }
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        assert.is_true(Q.map[502] < 0)
        ctl.ViewerAura(ctl.viewer.items.BuffIconCooldownViewer[1], "player")
        sweep(2)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(2, 1))
    end)

    it("fires onEdge on a reduced UP or DOWN change only (UNKNOWN fires none)", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        local edges = {}
        Q.onEdge = function(j, u, isUp, t)
            edges[#edges + 1] = { j, u, isUp, t }
        end
        up(A)
        sweep(2)
        sweep(2.1) -- no change, no edge
        down(A)
        sweep(3)
        ctl.ViewerRelease(item) -- UNKNOWN: no edge
        sweep(4)
        assert.are.same({ { 1, 1, true, 2 }, { 1, 1, false, 3 } }, edges)
    end)

    it("reads IsVisible and GetNumChildren once per viewer per sweep; growth is collected by the sweep", function()
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        local vis, num = 0, 0
        for _, name in ipairs(fake.VIEWERS) do
            local v = api[name]
            local isVisible, getNum = v.IsVisible, v.GetNumChildren
            v.IsVisible = function(...)
                vis = vis + 1
                return isVisible(...)
            end
            v.GetNumChildren = function(...)
                num = num + 1
                return getNum(...)
            end
        end
        local b = ctl.ViewerAcquire("EssentialCooldownViewer", 501)
        sweep(2)
        assert.are.same({ 4, 4 }, { vis, num })
        assert.is_not_nil(Q.slotOf[b])
    end)

    it("poll 15 sweeps before its covered guard; a raise in the sweep does not break the poll", function()
        start()
        assert.are.equal(0, I.presence.covered)
        ctl.ViewerAura(ctl.ViewerAcquire("BuffIconCooldownViewer", 502), "player")
        ctl.now = 2
        I.Sources.RunPolls(2)
        assert.are.equal(1, I.presence.covered)
        assert.are.equal(I.UP, I.presence.Presence(1, 1))
        api.BuffIconCooldownViewer.IsVisible = function()
            error("forbidden")
        end
        ctl.now = 3
        assert.has_no.errors(function()
            I.Sources.RunPolls(3)
        end)
        assert.are.equal(I.UP, I.presence.Presence(1, 1)) -- the failed sweep moved nothing
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

    it("no HookScript and no hooksecurefunc call is made", function()
        -- every path of the leaf: activation (before_each), a rebuild, combat, in-combat growth, sweeps with every kind
        -- of change, a target change, combat end, a re-activation
        ctl.Fire("COOLDOWN_VIEWER_DATA_LOADED")
        inCombat()
        local b = ctl.ViewerAcquire("BuffIconCooldownViewer", 502)
        ctl.ViewerAcquire("EssentialCooldownViewer", 501)
        Q.Collect()
        ctl.ViewerAuraBySpell("player", fs.SPENDER_A, true, "player")
        I.presence.Sweep(2)
        ctl.ViewerRepoint(b, 501)
        ctl.ViewerRelease(ctl.viewer.items.BuffIconCooldownViewer[1])
        ctl.Fire("PLAYER_TARGET_CHANGED")
        I.Sources.RunPolls(3)
        ctl.ViewerAuraBySpell("player", fs.SPENDER_A, false, "player")
        I.presence.Sweep(4)
        ctl.combat = false
        ctl.Fire("PLAYER_REGEN_ENABLED")
        I.Build(d, 1)
        I.presence.Sweep(5)
        assert.are.same({}, ctl.viewer.hookCalls)
        for _, name in ipairs(fake.VIEWERS) do
            for _, c in ipairs(ctl.viewer.items[name]) do
                assert.is_nil(c.hooks and next(c.hooks))
            end
        end
    end)
end)
