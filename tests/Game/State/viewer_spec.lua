-- tests/Game/State/viewer_spec.lua: the Cooldown Manager leaf. The map and the collect (cdm-default spec §3.1-§3.2,
-- plan Task 3a) against the any-layout fake; the providers-spec hook block (§2.4, decisions 77-79) kept until Task 3b's
-- sweep replaces it (~/src/hekili-central-needs/cdm-3a.md §2).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

-- The sweep (cdm-default spec §3.2, decisions 95-96, 100, 102; plan Task 3b): every slot read by rawget at poll 15,
-- counted per thing (aura j, unit u) as nLive, nUp, nNone, nStale, tUp, tNone, against the any-layout fake. A silent
-- slot is NONE only under Task 3c's seen rule (spec §2.2a): rec() opens the record a silence may close.
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
    local function counts(j, u) -- the first six (nDark, the 7th, is read by dark())
        local a, b, c, d6, e, f = Q.Counts(j, u)
        return { a, b, c, d6, e, f }
    end
    local function up(spell, unit)
        ctl.ViewerAuraBySpell(unit or "player", spell, true, "player")
    end
    local function down(spell, unit)
        ctl.ViewerAuraBySpell(unit or "player", spell, false, "player")
    end
    local function rec(j, u, applied) -- the belief's record of aura j on unit u: up since `applied`
        I.auras.exp0[u][j], I.auras.applied[u][j] = 1e6, applied
    end

    it(
        "a cooldown entry (Essential) holding an aura is UP evidence; a Buff icon entry for the same aura agrees",
        function()
            ctl.ViewerItem("EssentialCooldownViewer", 1, 501)
            ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            start()
            assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1)) -- read at activation: both silent, never seen holding
            up(A)
            sweep(2)
            assert.are.same({ 2, 2, 0, 0, 2, 0 }, counts(1, 1))
            assert.are.equal(I.UP, I.presence.Presence(1, 1))
            assert.are.equal(1, I.presence.covered)
            rec(1, 1, 2)
            up(A) -- the Essential entry alone: still UP evidence (F6)
            ctl.ViewerClear(ctl.viewer.items.BuffIconCooldownViewer[1])
            sweep(3)
            assert.are.same({ 2, 1, 1, 0, 2, 3 }, counts(1, 1)) -- the Buff icon held this application: its NONE is newer
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
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.same({ 1, 1, 0, 0, 2, 0 }, counts(1, 2)) -- a's UP is for the target only
        ctl.ViewerAura(c, "player") -- control: plain "player"
        sweep(3)
        assert.are.same({ 1, 1, 0, 0, 3, 0 }, counts(1, 1))
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
            assert.are.same({ 1, 1, 0, 1, 2, 0 }, counts(1, 1)) -- the hidden bar's slot: stale
            ctl.viewer.parentShown = false -- Alt-Z: every viewer hidden
            sweep(3)
            assert.are.same({ 0, 0, 0, 2, 0, 0 }, counts(1, 1))
            assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
            assert.are.equal(0, I.presence.covered)
            ctl.viewer.parentShown = true
            ctl.viewer.shown.BuffBarCooldownViewer = nil
            up(A)
            sweep(4)
            assert.are.same({ 2, 2, 0, 0, 4, 0 }, counts(1, 1)) -- they count again, from this poll
            rec(1, 1, 2)
            down(A)
            sweep(5)
            assert.are.same({ 2, 0, 2, 0, 0, 5 }, counts(1, 1))
            assert.are.equal(I.DOWN, I.presence.Presence(1, 1))
        end
    )

    it("the refresh pair (clear then set in one call) is never seen as NONE", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        up(A)
        sweep(2)
        local edges = {}
        I.presence.onEdge = function(j, u, isUp)
            edges[#edges + 1] = { j, u, isUp }
        end
        local n = #item.writes
        up(A) -- our refresh: the client clears, then sets, in one call
        assert.are.same({ "clear", "set" }, { item.writes[n + 1], item.writes[n + 2] })
        sweep(3)
        assert.are.same({ 1, 1, 0, 0, 2, 0 }, counts(1, 1)) -- no NONE, and no new UP begin either
        assert.are.same({}, edges)
    end)

    it("a release, held or not, drops the slot (no NONE)", function()
        local a = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        local b = ctl.ViewerItem("BuffIconCooldownViewer", 2, 503)
        start()
        up(A)
        ctl.ViewerAura(b, "player")
        sweep(2)
        rec(1, 1, 2)
        rec(2, 1, 2)
        ctl.ViewerClear(b)
        sweep(2.5)
        assert.are.same({ 1, 1, 0, 0, 2, 0 }, counts(1, 1))
        assert.are.same({ 1, 0, 1, 0, 0, 2.5 }, counts(2, 1)) -- b silent after holding this application: NONE
        ctl.ViewerRelease(a) -- held: cooldownID nil first, then the clear
        ctl.ViewerRelease(b) -- silent
        sweep(3)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(2, 1))
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1)) -- UNKNOWN, never DOWN
        assert.are.equal(I.UNDECIDED, I.presence.Presence(2, 1))
        assert.are.equal(0, I.presence.covered)
    end)

    it("a re-point moves the slot's evidence from the old aura to the new", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        up(A)
        sweep(2)
        rec(2, 1, 1)
        ctl.ViewerRepoint(item, 503) -- now aura 2: the refresh finds no aura 2 on us, the item clears
        sweep(3)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(2, 1)) -- a re-point resets the slot: never seen holding aura 2
        up(C)
        sweep(4)
        assert.are.same({ 1, 1, 0, 0, 4, 0 }, counts(2, 1))
        assert.are.equal(I.UP, I.presence.Presence(2, 1))
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
    end)

    it(
        "items appearing (in combat, lit at once) and disappearing move the counts; a never-lit item is not live",
        function()
            ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            start()
            ctl.combat = true
            ctl.Fire("PLAYER_REGEN_DISABLED")
            up(A)
            sweep(2)
            local b = ctl.ViewerAcquire("EssentialCooldownViewer", 501) -- the pool grows: lit at once (F13)
            sweep(3)
            assert.is_not_nil(Q.slotOf[b])
            assert.are.same({ 2, 2, 0, 0, 3, 0 }, counts(1, 1))
            rec(1, 1, 2)
            local s = ctl.ViewerAcquire("UtilityCooldownViewer", 501, true) -- a silent item (F12)
            sweep(4)
            assert.are.same({ 2, 2, 0, 0, 3, 0 }, counts(1, 1)) -- it never held this application: not live
            assert.are.equal(I.UP, I.presence.Presence(1, 1))
            ctl.ViewerRemove("UtilityCooldownViewer", s)
            sweep(5)
            assert.are.same({ 2, 2, 0, 0, 3, 0 }, counts(1, 1))
            assert.are.equal(I.UP, I.presence.Presence(1, 1))
        end
    )

    it(
        "target items answer for the target; a target NONE is a DOWN through the router (decision 111 amended)",
        function()
            local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 503)
            item.unit = "target"
            start()
            up(C, "target")
            sweep(2)
            assert.are.same({ 1, 1, 0, 0, 2, 0 }, counts(2, 2))
            assert.are.equal(I.UP, I.presence.Presence(2, 2))
            rec(2, 2, 2)
            down(C, "target")
            sweep(3)
            assert.are.same({ 1, 0, 1, 0, 0, 3 }, counts(2, 2)) -- its last held unit
            assert.are.equal(I.DOWN, (I.ReduceFact(Q.Counts(2, 2)))) -- the reduced fact ...
            assert.are.equal(I.DOWN, I.presence.Presence(2, 2)) -- ... is the answer (Sources/Auras.lua closes only ours)
        end
    )

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

    it("tUp and tNone are the latest begin of a LIVE slot: a later UP that left gives no UP", function()
        local a = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        local b = ctl.ViewerItem("BuffIconCooldownViewer", 2, 502)
        local c = ctl.ViewerItem("BuffIconCooldownViewer", 3, 502)
        start()
        ctl.ViewerAura(a, "player")
        ctl.ViewerAura(b, "player")
        sweep(2)
        rec(1, 1, 2)
        ctl.ViewerClear(b) -- b answers NONE from 3
        sweep(3)
        ctl.ViewerAura(c, "player") -- c answers UP from 4 ...
        sweep(4)
        ctl.ViewerRelease(c) -- ... and leaves
        sweep(5)
        assert.are.same({ 2, 1, 1, 0, 2, 3 }, counts(1, 1)) -- live: a UP since 2, b NONE since 3
        local st, agree = I.ReduceFact(Q.Counts(1, 1))
        assert.are.same({ I.UNDECIDED, false }, { st, agree })
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
    end)

    it("a later NONE that left does not block an older live UP", function()
        local a = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        local b = ctl.ViewerItem("BuffIconCooldownViewer", 2, 502)
        local c = ctl.ViewerItem("BuffIconCooldownViewer", 3, 502)
        start()
        ctl.ViewerAura(b, "player")
        sweep(1.2)
        rec(1, 1, 1.2)
        ctl.ViewerClear(b) -- b answers NONE from 1.5
        sweep(1.5)
        ctl.ViewerAura(a, "player")
        ctl.ViewerAura(c, "player")
        sweep(2)
        ctl.ViewerClear(c) -- c answers NONE from 3 ...
        sweep(3)
        ctl.ViewerRelease(c) -- ... and leaves
        sweep(4)
        assert.are.same({ 2, 1, 1, 0, 2, 1.5 }, counts(1, 1)) -- live: a UP since 2, b NONE since 1.5
        local st, agree = I.ReduceFact(Q.Counts(1, 1))
        assert.are.same({ I.UP, false }, { st, agree })
        assert.are.equal(I.UP, I.presence.Presence(1, 1))
    end)

    it("fires onEdge on a reduced UP or DOWN change only (UNKNOWN fires none)", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        local edges = {}
        I.presence.onEdge = function(j, u, isUp, t)
            edges[#edges + 1] = { j, u, isUp, t }
        end
        up(A)
        sweep(2)
        sweep(2.1) -- no change, no edge
        rec(1, 1, 2)
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

    it("poll 15 sweeps before its covered guard", function()
        start()
        assert.are.equal(0, I.presence.covered)
        ctl.ViewerAura(ctl.ViewerAcquire("BuffIconCooldownViewer", 502), "player")
        ctl.now = 2
        I.Sources.RunPolls(2)
        assert.are.equal(1, I.presence.covered)
        assert.are.equal(I.UP, I.presence.Presence(1, 1))
    end)

    -- Task 3c (spec §3.5, decision 107; 3b review I-3): a raise must not freeze the last answer and re-apply it.
    it("an error in the sweep turns the leaf off for the session with one def.error line", function()
        local lines = {}
        start()
        I.def.error = function(fmt, ...)
            lines[#lines + 1] = string.format(fmt, ...)
        end
        ctl.ViewerAura(ctl.ViewerAcquire("BuffIconCooldownViewer", 502), "player")
        ctl.now = 2
        I.Sources.RunPolls(2)
        assert.are.equal(I.UP, I.presence.Presence(1, 1)) -- control: on and answering
        local isVisible = api.BuffIconCooldownViewer.IsVisible
        api.BuffIconCooldownViewer.IsVisible = function()
            error("forbidden")
        end
        ctl.now = 3
        assert.has_no.errors(function()
            I.Sources.RunPolls(3)
        end)
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1)) -- not the frozen UP
        assert.are.equal(0, I.presence.covered)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.equal(1, #lines)
        assert.is_truthy(lines[1]:find("Cooldown Manager", 1, true), lines[1])
        assert.are.equal(1, Q.errors)
        ctl.now = 4
        I.Sources.RunPolls(4) -- off: no second line
        assert.are.equal(1, #lines)
        api.BuffIconCooldownViewer.IsVisible = isVisible
        I.Build(d, 5) -- a rebuild does not turn it back on: off for the session
        ctl.now = 5
        I.Sources.RunPolls(5)
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
        assert.are.equal(0, I.presence.covered)
        assert.are.equal(1, #lines)
    end)

    -- Task 3c, the seen rule per slot (spec §2.2a, decision 115): a silent slot closes only an application it was
    -- seen holding. Each "not live" case has its positive control.
    it("sSeen[s] is written at every sweep the slot is held for u, not only on a change", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        local s = Q.slotOf[item]
        up(A)
        sweep(2)
        assert.are.equal(2, Q.seen[s])
        rec(1, 1, 2)
        sweep(3) -- no reading change
        assert.are.equal(3, Q.seen[s])
        rec(1, 1, 3.2) -- our refresh while the item stays held moves applied
        up(A)
        sweep(3.5)
        assert.are.equal(3.5, Q.seen[s])
        down(A)
        sweep(4)
        assert.are.same({ 1, 0, 1, 0, 0, 4 }, counts(1, 1)) -- seen holding this application (3.5 >= 3.2): live
    end)

    it(
        "a silent item for an application it never held is not live; control: lit this application, then silent",
        function()
            local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            start()
            rec(1, 1, 2) -- our cast at 2; the item never lights
            sweep(3)
            assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
            assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
            ctl.ViewerAura(item, "player") -- control
            sweep(4)
            ctl.ViewerClear(item)
            sweep(5)
            assert.are.same({ 1, 0, 1, 0, 0, 5 }, counts(1, 1))
            assert.are.equal(I.DOWN, I.presence.Presence(1, 1))
        end
    )

    it(
        "a never-lit cooldown entry (Essential, Utility) does not close a cast self-buff (L279); control: a lit one does",
        function()
            ctl.viewer.sets[1] = { 505 }
            ctl.viewer.infos[505] = { spellID = A } -- a Utility entry for aura 1
            local e = ctl.ViewerItem("EssentialCooldownViewer", 1, 501)
            ctl.ViewerItem("UtilityCooldownViewer", 1, 505)
            start()
            ctl.combat = true
            ctl.Fire("PLAYER_REGEN_DISABLED")
            rec(1, 1, 2) -- our cast: the entries never show the aura
            for t = 2, 4, 0.5 do
                sweep(t)
                assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
                assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
            end
            ctl.ViewerAura(e, "player") -- control: the Essential entry lights this application, then goes silent
            sweep(5)
            ctl.ViewerClear(e)
            sweep(6)
            assert.are.same({ 1, 0, 1, 0, 0, 6 }, counts(1, 1))
            assert.are.equal(I.DOWN, I.presence.Presence(1, 1))
        end
    )

    it("our new cast moves applied past sSeen: the silent item is not live until it lights again (I-B)", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        ctl.ViewerAura(item, "player")
        sweep(2)
        rec(1, 1, 2)
        ctl.ViewerClear(item)
        sweep(3)
        assert.are.same({ 1, 0, 1, 0, 0, 3 }, counts(1, 1))
        rec(1, 1, 4) -- our new cast, before the client's UNIT_AURA lights the item
        sweep(4.1)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
        ctl.ViewerAura(item, "player") -- control: it lights, then its silence is live
        sweep(5)
        ctl.ViewerClear(item)
        sweep(6)
        assert.are.same({ 1, 0, 1, 0, 0, 6 }, counts(1, 1))
    end)

    it("two items for one aura, B never lit: B is never live; A released mid-application: UNKNOWN, not DOWN", function()
        local a = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        ctl.ViewerItem("EssentialCooldownViewer", 1, 501).silent = true -- B
        start()
        up(A)
        sweep(2)
        assert.are.same({ 1, 1, 0, 0, 2, 0 }, counts(1, 1))
        assert.are.same({ I.UP, true }, { I.ReduceFact(Q.Counts(1, 1)) })
        rec(1, 1, 2)
        rec(1, 1, 3) -- our refresh while A is held: no flip
        up(A)
        sweep(3)
        assert.are.same({ 1, 1, 0, 0, 2, 0 }, counts(1, 1))
        assert.are.same({ I.UP, true }, { I.ReduceFact(Q.Counts(1, 1)) })
        ctl.ViewerRelease(a)
        sweep(4)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
    end)

    it("two items for one aura, B never lit; control: A stays and goes silent: live as NONE", function()
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        ctl.ViewerItem("EssentialCooldownViewer", 1, 501).silent = true
        start()
        up(A)
        sweep(2)
        rec(1, 1, 2)
        down(A)
        sweep(3)
        assert.are.same({ 1, 0, 1, 0, 0, 3 }, counts(1, 1))
        assert.are.equal(I.DOWN, I.presence.Presence(1, 1))
    end)

    it("re-point resets the slot: to another aura, back, and to another cooldownID of the same aura", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        up(A)
        sweep(2)
        rec(1, 1, 2)
        rec(2, 1, 2)
        ctl.ViewerRepoint(item, 503) -- aura 2: the refresh finds none, the item clears
        sweep(3)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(2, 1))
        item.silent = true -- (CDM Task 8: a re-point's refresh now lights an aura that is up; silent keeps it dark here)
        ctl.ViewerRepoint(item, 502) -- back to aura 1, silent: not live until it lights again
        item.silent = nil
        sweep(4)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        ctl.ViewerAura(item, "player", A)
        sweep(5)
        ctl.ViewerClear(item)
        sweep(5.5)
        assert.are.same({ 1, 0, 1, 0, 0, 5.5 }, counts(1, 1)) -- lit again, then silent: live
        item.silent = true
        ctl.ViewerRepoint(item, 501) -- another cooldownID, the same aura (sCd moves, sJ does not)
        item.silent = nil
        sweep(6)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        ctl.ViewerAura(item, "player", A) -- control: it lights the aura, then goes silent: live
        sweep(7)
        ctl.ViewerClear(item)
        sweep(8)
        assert.are.same({ 1, 0, 1, 0, 0, 8 }, counts(1, 1))
    end)

    it(
        "a held slot with a secret or nil unit, or another plain unit, then silent, is not live for either unit;"
            .. " control: held for the target, then silent, is live for the target only",
        function()
            local a = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            local b = ctl.ViewerItem("BuffIconCooldownViewer", 2, 502)
            local c = ctl.ViewerItem("BuffIconCooldownViewer", 3, 502)
            local e = ctl.ViewerItem("BuffIconCooldownViewer", 4, 502)
            start()
            for _, item in ipairs({ a, b, c }) do
                ctl.ViewerAura(item, "player") -- each first seen holding for the player ...
            end
            sweep(1.5)
            rec(1, 1, 1.5)
            rec(1, 2, 1.5)
            ctl.ViewerAura(a, fake.SECRET) -- ... then held for no unit we track: a reset
            ctl.ViewerAura(b, nil)
            ctl.ViewerAura(c, "focus")
            ctl.ViewerAura(e, "target")
            sweep(2)
            for _, item in ipairs({ a, b, c, e }) do
                ctl.ViewerClear(item)
            end
            sweep(3)
            assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
            assert.are.same({ 1, 0, 1, 0, 0, 3 }, counts(1, 2)) -- e alone
        end
    )

    it("a reset of a slot counted as NONE (target switch, cooldownID change) un-counts it first", function()
        local tItem = ctl.ViewerItem("BuffIconCooldownViewer", 1, 503)
        tItem.unit = "target"
        local pItem = ctl.ViewerItem("BuffIconCooldownViewer", 2, 502)
        start()
        up(C, "target")
        up(A)
        sweep(2)
        rec(2, 2, 2)
        rec(1, 1, 2)
        down(C, "target")
        down(A)
        sweep(3)
        assert.are.same({ 1, 0, 1, 0, 0, 3 }, counts(2, 2))
        assert.are.same({ 1, 0, 1, 0, 0, 3 }, counts(1, 1))
        ctl.now = 4
        ctl.Fire("PLAYER_TARGET_CHANGED")
        local n = counts(2, 2) -- un-counted at the reset, before any sweep (tUp/tNone follow at the next reduce)
        assert.are.same({ 0, 0, 0, 0 }, { n[1], n[2], n[3], n[4] })
        ctl.ViewerRepoint(pItem, 501)
        sweep(4.1)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(2, 2))
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.equal(0, I.presence.covered)
    end)

    it("an ambiguous slot, held then silent, is never live; control: an unambiguous slot is", function()
        ctl.viewer.sets[2] = { 502, 503, 506 }
        ctl.viewer.infos[506] = { spellID = A, overrideSpellID = fs.SPENDER_C } -- names aura 1 and aura 2
        local amb = ctl.ViewerItem("BuffIconCooldownViewer", 1, 506)
        local one = ctl.ViewerItem("BuffIconCooldownViewer", 2, 502)
        start()
        ctl.ViewerAura(amb, "player")
        sweep(2)
        rec(1, 1, 2)
        rec(2, 1, 2)
        ctl.ViewerClear(amb)
        sweep(3)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(2, 1))
        ctl.ViewerAura(one, "player")
        sweep(4)
        ctl.ViewerClear(one)
        sweep(5)
        assert.are.same({ 1, 0, 1, 0, 0, 5 }, counts(1, 1))
    end)

    it("a rebuild resets every slot's sSeen", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        ctl.ViewerAura(item, "player")
        sweep(2)
        rec(1, 1, 2)
        ctl.ViewerClear(item)
        sweep(3)
        assert.are.same({ 1, 0, 1, 0, 0, 3 }, counts(1, 1))
        I.Build(d, 4) -- a rebuild: the map anew
        rec(1, 1, 2)
        sweep(5)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        ctl.ViewerAura(item, "player") -- control
        sweep(6)
        ctl.ViewerClear(item)
        sweep(7)
        assert.are.same({ 1, 0, 1, 0, 0, 7 }, counts(1, 1))
    end)

    it("a target switch resets the target-held slots' sSeen: not live for the new target until lit", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 503)
        item.unit = "target"
        start()
        up(C, "target")
        sweep(2)
        ctl.now = 3
        ctl.Fire("PLAYER_TARGET_CHANGED")
        rec(2, 2, 1) -- the new target's remembered application, older than the item's last light
        down(C, "target")
        sweep(3.1)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(2, 2))
        up(C, "target") -- control: lit for the new target, then silent: live
        sweep(4)
        down(C, "target")
        sweep(5)
        assert.are.same({ 1, 0, 1, 0, 0, 5 }, counts(2, 2))
    end)

    -- 3c review F1: sSeen pairs with the unit it was seen for; a held unit change (even while stale) starts it over.
    it("seen for the target, held for the player while hidden, then silent: not live for the player", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        rec(1, 1, 1) -- our player application
        ctl.ViewerAura(item, "target")
        sweep(2) -- seen holding for the target only
        ctl.viewer.shown.BuffIconCooldownViewer = false
        ctl.ViewerAura(item, "player")
        sweep(3) -- hidden: stale for the player, no sSeen write
        ctl.viewer.shown.BuffIconCooldownViewer = nil
        ctl.ViewerClear(item)
        sweep(4)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
    end)

    it(
        "control: seen for the target, then held for the player while visible, then silent: live for the player",
        function()
            local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            start()
            rec(1, 1, 1)
            ctl.ViewerAura(item, "target")
            sweep(2)
            ctl.ViewerAura(item, "player")
            sweep(3)
            ctl.ViewerClear(item)
            sweep(4)
            assert.are.same({ 1, 0, 1, 0, 0, 4 }, counts(1, 1))
        end
    )

    it(
        "a player slot lighting for the new target in the switch's frame does not lend its sSeen to the target",
        function()
            local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            start()
            ctl.ViewerAura(item, "player")
            sweep(2)
            rec(1, 1, 2)
            rec(1, 2, 1) -- the new target's application, older than the player light
            ctl.ViewerClear(item)
            sweep(2.5) -- a player NONE slot: marked settling at the switch
            ctl.now = 3
            ctl.Fire("PLAYER_TARGET_CHANGED")
            ctl.ViewerAura(item, "target")
            sweep(3) -- the switch's own frame: held for the target while settling, stale, no sSeen write
            ctl.ViewerClear(item)
            sweep(3.1) -- settled, silent
            assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 2))
        end
    )

    it("the sSeen > 0 term: a slot never seen visible does not close a record whose applied is 0", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        ctl.viewer.shown.BuffIconCooldownViewer = false
        start()
        rec(1, 1, 0)
        ctl.ViewerAura(item, "player")
        sweep(2) -- hidden: stale, never seen
        ctl.viewer.shown.BuffIconCooldownViewer = nil
        ctl.ViewerClear(item)
        sweep(3)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
    end)

    it("a record that closed makes its silent slots not live at the next sweep", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        ctl.ViewerAura(item, "player")
        sweep(2)
        rec(1, 1, 2)
        ctl.ViewerClear(item)
        sweep(3)
        assert.are.same({ 1, 0, 1, 0, 0, 3 }, counts(1, 1)) -- control: live while the record is up
        I.auras.exp0[1][1], I.auras.applied[1][1] = 0, 0 -- the record closes
        sweep(3.5)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1))
    end)

    -- Task 3c, the target settle (spec §3.4, decision 103).
    it(
        "target change: target and NONE slots are stale in the switch's frame; the next frame's sweep is a change",
        function()
            local tItem = ctl.ViewerItem("BuffIconCooldownViewer", 1, 503)
            tItem.unit = "target"
            local p1 = ctl.ViewerItem("BuffIconCooldownViewer", 2, 502)
            local p2 = ctl.ViewerItem("BuffIconCooldownViewer", 3, 502)
            start()
            up(C, "target")
            ctl.ViewerAura(p1, "player")
            ctl.ViewerAura(p2, "player")
            sweep(2)
            rec(1, 1, 2)
            ctl.ViewerClear(p1)
            ctl.ViewerClear(p2)
            sweep(2.5)
            assert.are.same({ 1, 1, 0, 0, 2, 0 }, counts(2, 2))
            assert.are.same({ 2, 0, 2, 0, 0, 2.5 }, counts(1, 1))
            local edges = {}
            I.presence.onEdge = function(j, u, isUp)
                edges[#edges + 1] = { j, u, isUp }
            end
            ctl.now = 3
            ctl.Fire("PLAYER_TARGET_CHANGED") -- the target item still shows the old mob's light
            sweep(3) -- the switch's own frame (t == the switch's t)
            assert.are.same({ 0, 0, 0, 1, 0, 0 }, counts(2, 2))
            assert.are.same({ 2, 0, 2, 0, 0, 2.5 }, counts(1, 1)) -- a player answer does not settle (§2.2)
            assert.are.equal(I.UNDECIDED, I.presence.Presence(2, 2))
            ctl.ViewerAura(p2, "target") -- a NONE slot lights for the new target in the same frame: settling
            sweep(3)
            assert.are.same({ 0, 0, 0, 1, 0, 0 }, counts(1, 2))
            assert.are.same({ 1, 0, 1, 0, 0, 2.5 }, counts(1, 1))
            sweep(3.001) -- the next frame: settled, each a change at this poll
            assert.are.same({ 1, 1, 0, 0, 3.001, 0 }, counts(2, 2))
            assert.are.same({ 1, 1, 0, 0, 3.001, 0 }, counts(1, 2))
            assert.are.same({ 1, 0, 1, 0, 0, 2.5 }, counts(1, 1))
            assert.are.equal(I.UP, I.presence.Presence(2, 2))
            assert.are.same({ { 2, 2, true }, { 1, 2, true } }, edges) -- no second player DOWN edge
        end
    )

    -- L299 (owner 2026-11-08, CDM-O): the settle is the switch's own frame (the belief clock t, constant in a frame).
    local function lit(tItem) -- the target item lit for mob A at 2; the switch at 3; edges recorded from then on
        start()
        up(C, "target")
        sweep(2)
        rec(2, 2, 2)
        assert.are.same({ 1, 1, 0, 0, 2, 0 }, counts(2, 2))
        local edges = {}
        I.presence.onEdge = function(j, u, isUp)
            edges[#edges + 1] = { j, u, isUp }
        end
        ctl.now = 3
        ctl.Fire("PLAYER_TARGET_CHANGED")
        return edges
    end

    it("a target answer read in the switch's frame (t == the switch's t) is stale: no UP, no DOWN", function()
        local tItem = ctl.ViewerItem("BuffIconCooldownViewer", 1, 503)
        tItem.unit = "target"
        local edges = lit(tItem)
        sweep(3) -- f=0: the item still shows mob A's light
        assert.are.same({ 0, 0, 0, 1, 0, 0 }, counts(2, 2))
        assert.are.equal(I.UNDECIDED, I.presence.Presence(2, 2))
        ctl.ViewerClear(tItem) -- and silent in the same frame: no DOWN either
        sweep(3)
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(2, 2))
        assert.are.equal(I.UNDECIDED, I.presence.Presence(2, 2))
        assert.are.same({}, edges)
    end)

    it("the first sweep after the switch's frame is trusted: a real UP lit after the switch applies", function()
        local tItem = ctl.ViewerItem("BuffIconCooldownViewer", 1, 503)
        tItem.unit = "target"
        local edges = lit(tItem)
        sweep(3) -- f=0: stale
        assert.are.same({ 0, 0, 0, 1, 0, 0 }, counts(2, 2))
        sweep(3.001) -- f=1 (~6 ms in CDM-O): mob B carries the debuff too, the item shows it
        assert.are.same({ 1, 1, 0, 0, 3.001, 0 }, counts(2, 2))
        assert.are.equal(I.UP, I.presence.Presence(2, 2))
        assert.are.same({ { 2, 2, true } }, edges)
        assert.are.equal(3.001, Q.seen[1]) -- a trusted light writes the seen rule's time
    end)

    it("a switch and a re-light inside the same frame stay stale until the next frame", function()
        local tItem = ctl.ViewerItem("BuffIconCooldownViewer", 1, 503)
        tItem.unit = "target"
        local edges = lit(tItem)
        ctl.ViewerClear(tItem)
        sweep(3) -- f=0: cleared
        ctl.ViewerAura(tItem, "target") -- and re-lit in the same frame
        sweep(3)
        assert.are.same({ 0, 0, 0, 1, 0, 0 }, counts(2, 2))
        assert.are.equal(0, Q.seen[1]) -- stale: no sSeen write
        assert.are.same({}, edges)
        sweep(3.001)
        assert.are.same({ 1, 1, 0, 0, 3.001, 0 }, counts(2, 2))
        assert.are.same({ { 2, 2, true } }, edges)
    end)

    it("a switch with no sweep for 0.5 s: the first sweep after it is trusted", function()
        local tItem = ctl.ViewerItem("BuffIconCooldownViewer", 1, 503)
        tItem.unit = "target"
        local edges = lit(tItem)
        ctl.ViewerClear(tItem)
        ctl.ViewerAura(tItem, "target") -- mob B's light, shown from the next frame
        sweep(3.5)
        assert.are.same({ 1, 1, 0, 0, 3.5, 0 }, counts(2, 2))
        assert.are.same({ { 2, 2, true } }, edges)
        ctl.ViewerClear(tItem) -- control: seen after the switch, then silent, it is live (NONE)
        sweep(4)
        assert.are.same({ 1, 0, 1, 0, 0, 4 }, counts(2, 2))
    end)

    -- The verdict's leaf side (cdm-verdict §2.1-§2.5, decisions 117-118, 121-122).
    local function dark(j, u)
        return (select(7, Q.Counts(j, u)))
    end
    local function since(j, u) -- the latest start of a dark slot of the thing (review M2), 0 none
        return (select(8, Q.Counts(j, u)))
    end

    it(
        "proof: a lit sweep of a visible viewer proves the cooldownID, with its unit; a hidden one proves nothing",
        function()
            ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            ctl.viewer.shown.BuffIconCooldownViewer = false
            start()
            assert.is_true(Q.NeverLit(1))
            up(A, "target")
            sweep(2)
            assert.is_false(Q.proven[502])
            ctl.viewer.shown.BuffIconCooldownViewer = nil
            sweep(3)
            assert.is_true(Q.proven[502])
            assert.are.equal(2, Q.provenU[502])
            assert.is_false(Q.NeverLit(1))
            assert.is_true(Q.NeverLit(2)) -- 503 maps aura 2, never lit
            assert.is_false(Q.proven[501]) -- per cooldownID, never per aura
        end
    )

    it(
        "the dark (review M2): from the first monitored dark sweep, with its start; never live; for the unit the"
            .. " item last lit for; a light, a hidden sweep and a held sweep for no unit restart it",
        function()
            ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            start()
            up(A, "target")
            sweep(2)
            assert.are.same({ 0, 0 }, { dark(1, 2), since(1, 2) })
            down(A, "target")
            sweep(3)
            assert.are.same({ 1, 3 }, { dark(1, 2), since(1, 2) })
            sweep(4)
            assert.are.same({ 1, 3 }, { dark(1, 2), since(1, 2) }) -- continuous: the start stands
            assert.are.same({ 0, 0 }, { dark(1, 1), since(1, 1) })
            assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 2)) -- not live: no record, so no NONE either
            assert.are.equal(0, I.presence.covered)
            up(A, "target") -- a light restarts it
            sweep(5)
            assert.are.same({ 0, 0 }, { dark(1, 2), since(1, 2) })
            down(A, "target")
            sweep(6)
            assert.are.same({ 1, 6 }, { dark(1, 2), since(1, 2) })
            ctl.viewer.shown.BuffIconCooldownViewer = false -- not monitored: restarts
            sweep(7)
            assert.are.same({ 0, 0 }, { dark(1, 2), since(1, 2) })
            ctl.viewer.shown.BuffIconCooldownViewer = nil
            sweep(8)
            sweep(9)
            assert.are.same({ 1, 8 }, { dark(1, 2), since(1, 2) })
            local item = ctl.viewer.items.BuffIconCooldownViewer[1]
            item.auraInstanceID, item.auraDataUnit = fake.SECRET, "focus" -- held for no unit we track: restarts
            sweep(10)
            assert.are.same({ 0, 0 }, { dark(1, 2), since(1, 2) })
        end
    )

    it("the dark's start is the LATEST among the thing's dark slots (review M2)", function()
        local x = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        local y = ctl.ViewerItem("EssentialCooldownViewer", 1, 501) -- another cooldownID of the same aura
        start()
        ctl.ViewerAura(x, "player", A)
        ctl.ViewerAura(y, "player", A)
        sweep(2)
        ctl.ViewerClear(x)
        sweep(3)
        assert.are.same({ 1, 3 }, { dark(1, 1), since(1, 1) })
        ctl.ViewerClear(y)
        sweep(5)
        assert.are.same({ 2, 5 }, { dark(1, 1), since(1, 1) }) -- y has been watched dark since 5 only
        ctl.ViewerAura(y, "player", A)
        sweep(6)
        assert.are.same({ 1, 3 }, { dark(1, 1), since(1, 1) }) -- y left: x's start is the latest again
    end)

    it("an unproven item is never dark", function()
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        for t = 2, 5 do
            sweep(t)
            assert.are.equal(0, dark(1, 1))
            assert.are.equal(0, dark(1, 2))
        end
    end)

    it("a re-point: the frame starts with no seen memory (review S1) and its dark starts over", function()
        local x = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        local y = ctl.ViewerItem("EssentialCooldownViewer", 1, 501)
        start()
        ctl.ViewerAura(x, "player", A)
        sweep(2)
        rec(1, 1, 2)
        ctl.ViewerClear(x)
        sweep(3)
        sweep(4)
        assert.are.equal(1, dark(1, 1))
        assert.are.same({ 1, 0, 1, 0, 0, 3 }, counts(1, 1))
        Q.repoints = 0
        x.silent, y.silent = true, true -- the reshuffle swaps the two frames' items, both dark
        ctl.ViewerRepoint(x, 501)
        ctl.ViewerRepoint(y, 502)
        sweep(5)
        assert.are.equal(2, Q.repoints)
        assert.are.same({ 0, 0 }, { Q.seen[Q.slotOf[x]], Q.seen[Q.slotOf[y]] }) -- nothing moves with the item
        assert.are.same({ 0, 0, 0, 0, 0, 0 }, counts(1, 1)) -- so y answers no NONE for what x was seen holding
        assert.is_nil(Q.seenCd)
    end)

    it("review m5: ForgetEdges (the viewer's data reloaded) restarts every dark count", function()
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        up(A)
        sweep(2)
        down(A)
        sweep(3)
        sweep(4)
        assert.are.equal(1, dark(1, 1))
        Q.ForgetEdges()
        assert.are.equal(0, dark(1, 1))
        sweep(5)
        assert.are.same({ 1, 5 }, { dark(1, 1), since(1, 1) }) -- dark again, since 5
    end)

    it("a target swap zeroes the target's dark counts, then settles", function()
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        start()
        up(A, "target")
        sweep(2)
        down(A, "target")
        sweep(3)
        sweep(4)
        assert.are.same({ 1, 3 }, { dark(1, 2), since(1, 2) })
        ctl.now = 4.5
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.are.equal(0, dark(1, 2))
        sweep(4.5) -- the swap's own frame: settling
        assert.are.equal(0, dark(1, 2))
        sweep(5)
        assert.are.same({ 1, 5 }, { dark(1, 2), since(1, 2) }) -- dark for mob B since the first sweep after the settle
        assert.is_true(Q.proven[502]) -- the proof stays (per cooldownID, per build)
    end)

    it("strikes: two drop the proof of every item lit for (j, u), and it cannot be re-proven this build", function()
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
        ctl.ViewerItem("EssentialCooldownViewer", 1, 501).silent = true -- not lit: never struck
        start()
        up(A)
        sweep(2)
        Q.Strike(1, 2) -- another unit: nothing
        assert.are.equal(0, Q.strikes[502])
        Q.Strike(1, 1)
        assert.are.same({ 1, true, 0 }, { Q.strikes[502], Q.proven[502], Q.struck })
        Q.Strike(1, 1)
        assert.are.same({ 2, false, 1 }, { Q.strikes[502], Q.proven[502], Q.struck })
        assert.are.equal(0, Q.strikes[501])
        sweep(3) -- still lit: no re-proof
        assert.is_false(Q.proven[502])
        ctl.ViewerClear(item)
        for t = 4, 6 do
            sweep(t)
            assert.are.equal(0, dark(1, 1))
        end
        Q.Activate(api, 7, d) -- a new build: proof and strikes start over
        assert.are.same({ 0, 0 }, { Q.strikes[502], Q.struck })
    end)

    it(
        "silent verdicts (review M3): two for the thing an item is dark for suspend its proof; a visible light"
            .. " re-proves it and zeroes the count; a struck item stays retired",
        function()
            ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            start()
            up(A)
            sweep(2)
            Q.Silent(1, 1) -- lit, not dark: nothing
            assert.are.equal(0, Q.silent[502])
            down(A)
            sweep(3)
            assert.are.equal(1, dark(1, 1))
            Q.Silent(1, 2) -- another unit: nothing
            assert.are.equal(0, Q.silent[502])
            Q.Silent(1, 1)
            assert.are.same({ 1, true, 0 }, { Q.silent[502], Q.proven[502], Q.suspended })
            Q.Silent(1, 1)
            assert.are.same({ 2, false, 1 }, { Q.silent[502], Q.proven[502], Q.suspended })
            assert.are.equal(0, Q.silent[501]) -- per cooldownID
            sweep(4)
            assert.are.equal(0, dark(1, 1)) -- suspended: no proof, never dark
            assert.is_false(Q.NeverLit(1)) -- but it did light: not "mapped, never lit"
            up(A)
            sweep(5)
            assert.are.same({ 0, true, 1 }, { Q.silent[502], Q.proven[502], Q.suspended })
            down(A)
            sweep(6)
            assert.are.same({ 1, 6 }, { dark(1, 1), since(1, 1) })
            Q.Silent(1, 1)
            up(A) -- a light between two silent verdicts: the count starts over
            sweep(7)
            assert.are.equal(0, Q.silent[502])
            Q.Strike(1, 1)
            Q.Strike(1, 1) -- retired for the build (§2.5)
            down(A)
            sweep(8)
            up(A)
            sweep(9)
            assert.are.same({ false, 1, 1 }, { Q.proven[502], Q.struck, Q.suspended }) -- a light does not undo strikes
            Q.Activate(api, 10, d) -- a new build: the counts start over
            assert.are.same({ 0, 0 }, { Q.silent[502], Q.suspended })
        end
    )

    it("builds are counted per session (review S2): one per build, never reset by a fight", function()
        start()
        local n = Q.builds
        assert.is_true(n >= 1)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        Q.Activate(api, 5, d)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.are.equal(n + 1, Q.builds)
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

    it(
        "a secret candidate (spellID, override, linked element, GetOverrideSpell's answer) never raises: ambiguous or unmapped",
        function()
            ctl.viewer.sets[0] = { 610, 611, 612, 613 }
            ctl.viewer.infos[610] = { spellID = fake.SECRET } -- nothing tracked: unmapped
            ctl.viewer.infos[611] = { spellID = fs.SPENDER_A, overrideSpellID = fake.SECRET }
            ctl.viewer.infos[612] = { spellID = 9000, linkedSpellIDs = { fake.SECRET, fs.SPENDER_A } }
            ctl.viewer.infos[613] = { spellID = fs.SPENDER_C }
            ctl.overrides[fs.SPENDER_C] = fake.SECRET
            start()
            assert.is_nil(Q.map[610])
            for _, id in ipairs({ 611, 612 }) do
                assert.is_true(Q.map[id] < 0, id)
                assert.are.same({ 1 }, Q.amb[-Q.map[id]])
            end
            assert.is_true(Q.map[613] < 0)
            assert.are.same({ 2 }, Q.amb[-Q.map[613]])
        end
    )

    it("an item with links and a tracked base spell maps by the links only", function()
        ctl.viewer.sets[0] = { 620 }
        ctl.viewer.infos[620] = { spellID = fs.SPENDER_C, linkedSpellIDs = { fs.SPENDER_A } }
        start()
        assert.are.equal(1, Q.map[620])
        assert.is_false(Q.Mappable(2))
    end)

    it("a raising GetOverrideSpell is caught: the item maps by its own IDs", function()
        ctl.viewer.sets[0] = { 630 }
        ctl.viewer.infos[630] = { spellID = fs.SPENDER_A }
        api.C_Spell.GetOverrideSpell = function()
            error("no override")
        end
        start()
        assert.are.equal(1, Q.map[630])
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
