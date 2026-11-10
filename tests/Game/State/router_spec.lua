-- tests/Game/State/router_spec.lua: the Presence router (providers spec §2.5, decisions 88-90), against the viewer
-- fakes and the Task 5 fixture (viewer_spec.lua). The leaf reads its items by a sweep at poll 15 (cdm-default §3.2):
-- the fake's ctl.ViewerAura / ViewerClear set the item, R.Sweep reads it.
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
        d = fs.def(fs.new(9))
        d.auras[3], d.auraIds[3] = { key = "spender_m", id = fs.SPENDER_M }, { fs.SPENDER_M } -- aura 3: not in a set
        d.providers = { presence = "router", viewer = true }
        I.Build(d, 1)
        VS.Start(api)
    end)

    it("a tracked aura is answered by the viewer leaf", function()
        local R = I.presence
        assert.are.equal("router", R.name)
        ctl.ViewerAura(ctl.viewer.items.BuffIconCooldownViewer[1], "player")
        R.Sweep(2)
        assert.are.equal(I.UP, R.Presence(1, 1))
        assert.are.equal("self", VS.PresenceScope("player", I.auras.obj[1].key)) -- the pack-facing read (decision 77)
    end)

    it("an untracked aura answers UNDECIDED (the modelled timer)", function()
        assert.are.equal(I.UNDECIDED, I.presence.Presence(3, 1))
    end)

    it("switch off: every aura UNDECIDED, covered 0, no getter read, the sweep a no-op", function()
        local calls = 0
        local get = api.C_CooldownViewer.GetCooldownViewerCategorySet
        api.C_CooldownViewer.GetCooldownViewerCategorySet = function(...)
            calls = calls + 1
            return get(...)
        end
        local d2 = fs.def(fs.new(9))
        d2.providers = { presence = "router", viewer = false }
        I.Build(d2, 1)
        ctl.ViewerAura(ctl.viewer.items.BuffIconCooldownViewer[1], "player")
        I.presence.Sweep(2)
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
        ctl.ViewerAura(ctl.viewer.items.BuffIconCooldownViewer[1], "player")
        ctl.ViewerAura(ctl.viewer.items.BuffIconCooldownViewer[2], "target")
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(2, I.presence.covered)
        assert.are.equal(I.UP, I.presence.Presence(1, 1))
    end)

    it("passes only tracked edges on and counts them", function()
        ctl.ViewerAura(ctl.viewer.items.BuffIconCooldownViewer[1], "player")
        I.presence.Sweep(2)
        assert.are.equal(1, I.presenceEdges.up)
    end)

    it("prints one line per tracked aura and unit, and the summary; with the switch off only the summary", function()
        local snap = VS.Snapshot()
        assert.is_truthy(snap:find("presence spender_a unit=- fact=unknown", 1, true))
        assert.is_truthy(snap:find("presence spender_c unit=- fact=unknown", 1, true))
        assert.is_falsy(snap:find("presence spender_m", 1, true)) -- untracked and no fact: no line
        I.presenceFacts[1] = 2 -- a fact on the player: that unit's line replaces the aura's line (out of combat a plain walk decides)
        snap = VS.Snapshot()
        assert.is_truthy(snap:find("presence spender_a unit=player fact=unknown from=walk n=0 via=- ", 1, true))
        assert.is_falsy(snap:find("presence spender_a unit=-", 1, true))
        assert.is_falsy(snap:find("presence spender_a unit=target", 1, true))
        assert.is_truthy(snap:find("presence covered=0/2 unmapped=0 ambiguous=0 overflow=0 leaf=on", 1, true))
        local d2 = fs.def(fs.new(9))
        d2.providers = { presence = "router", viewer = false }
        I.Build(d2, 1)
        snap = VS.Snapshot()
        assert.is_truthy(snap:find("presence covered=0/0 unmapped=0 ambiguous=0 overflow=0 leaf=off(debug)", 1, true))
        assert.is_falsy(snap:find("presence spender_", 1, true))
    end)

    it("zeroes the edge and fact counters at each fight's start", function()
        ctl.ViewerAura(ctl.viewer.items.BuffIconCooldownViewer[1], "player")
        I.presence.Sweep(2)
        I.presenceFacts[1] = 3
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.are.same({ 0, 0, 0 }, { I.presenceEdges.up, I.presenceEdges.down, I.presenceFacts[1] })
    end)

    it("a target DOWN is an answer and an edge (decision 111 amended: the CDM's 'now' state has precedence)", function()
        local item = ctl.viewer.items.BuffIconCooldownViewer[2]
        local ups, downs = 0, 0
        I.presence.onEdge = function(_, _, up)
            if up then
                ups = ups + 1
            else
                downs = downs + 1
            end
        end
        assert.are.equal(I.UNDECIDED, I.presence.Presence(2, 2))
        ctl.ViewerAura(item, "target")
        I.presence.Sweep(2)
        assert.are.equal(I.UP, I.presence.Presence(2, 2))
        I.auras.exp0[2][2], I.auras.applied[2][2] = 1e6, 2 -- the record the item was seen holding (seen rule)
        ctl.ViewerClear(item)
        I.presence.Sweep(3)
        assert.are.equal(I.DOWN, I.presence.Presence(2, 2))
        assert.are.same({ 1, 1, 1, 1 }, { ups, downs, I.presenceEdges.up, I.presenceEdges.down })
    end)

    it("an aura index past the set (an in-combat rebuild shrank it) is skipped, never a self-off (4a m5)", function()
        local item = ctl.viewer.items.BuffIconCooldownViewer[2] -- aura 2 on the target
        local Q = I.PRESENCE.viewer
        ctl.Fire("PLAYER_REGEN_DISABLED") -- in combat: Sources/Auras.lua's apply reads the record (no walk wins)
        ctl.ViewerAura(item, "target")
        I.presence.Sweep(2)
        I.auras.exp0[2][2], I.auras.applied[2][2] = 1e6, 2
        I.presence.Sweep(2.5)
        local U = I.auras
        U.nAura = 1 -- the set shrank under the leaf's old map: aura 2's arrays are gone
        U.exp0[2][2], U.applied[2][2], U.exp0[1][2], U.applied[1][2] = nil, nil, nil, nil
        ctl.ViewerClear(item) -- silent: the seen gate would read the gone record
        I.presence.Sweep(3)
        ctl.ViewerAura(item, "target") -- an UP edge: Sources/Auras.lua's apply would read it
        I.presence.Sweep(3.2)
        ctl.ViewerRelease(item) -- UNKNOWN: the router's lost check would read it too
        I.presence.Sweep(3.5)
        assert.are.equal(0, Q.errors)
        assert.are.equal(Q, I.presence.Leaf()) -- the leaf is still on: no self-off dropped it
    end)
end)

describe("the Presence router at VS.Start (a /reload in combat)", function()
    local VS, I, ctl, api, d

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        ctl.viewer.sets[2] = { 501 }
        ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
        ctl.ViewerItem("BuffIconCooldownViewer", 1, 501).unit = "player"
        local ns = load.module()
        VS = ns.VirtualState
        I = ns.VirtualStateInternal
        d = fs.def(fs.new(9))
        d.providers = { presence = "router", viewer = true }
    end)

    it("in combat, builds nothing until PLAYER_REGEN_ENABLED", function()
        ctl.combat = true
        I.Build(d, 1)
        VS.Start(api)
        assert.are.equal(0, I.presence.covered)
        for j = 1, I.auras.nAura do
            assert.is_false(I.presence.tracked[j])
        end
        assert.are.equal(I.UNDECIDED, I.presence.Presence(1, 1))
        ctl.combat = false
        ctl.ViewerAura(ctl.viewer.items.BuffIconCooldownViewer[1], "player")
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(I.presence.tracked[1])
        assert.are.equal(1, I.presence.covered) -- built and read at once (the activation's sweep)
        assert.are.equal(I.UP, I.presence.Presence(1, 1))
    end)

    it("out of combat, builds at Start", function()
        ctl.combat = false
        ctl.ViewerAura(ctl.viewer.items.BuffIconCooldownViewer[1], "player")
        I.Build(d, 1)
        VS.Start(api)
        assert.is_true(I.presence.tracked[1])
        assert.are.equal(1, I.presence.covered)
        assert.are.equal(I.UP, I.presence.Presence(1, 1))
    end)
end)

-- Task 4a (cdm-default §2.3-§2.4, decisions 92-94): the router hosts one reduced fact per aura and unit, from the leaf's
-- counts through I.ReduceFact; onEdge comes from the router on a reduced change. Items for aura 1: a and b (Buff icon,
-- cooldownID 501); aura 2: c (cooldownID 502).
describe("the Presence router's reduced facts (Task 4a)", function()
    local VS, I, ctl, api, d, R, Q
    local a, b

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        ctl.viewer.sets[2] = { 501, 502 }
        ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
        ctl.viewer.infos[502] = { spellID = 9999, linkedSpellIDs = { fs.SPENDER_C_R2 } }
        a = ctl.ViewerItem("BuffIconCooldownViewer", 1, 501)
        b = ctl.ViewerItem("BuffIconCooldownViewer", 2, 501)
        local ns = load.module()
        VS = ns.VirtualState
        I = ns.VirtualStateInternal
        d = fs.def(fs.new(9))
        d.providers = { presence = "router", viewer = true }
        I.Build(d, 1)
        VS.Start(api)
        R, Q = I.presence, I.PRESENCE.viewer
    end)
    local function sweep(t)
        ctl.now = t
        R.Sweep(t)
    end
    local function rec(j, u, applied) -- the belief's record: up since `applied` (the seen rule's gate)
        I.auras.exp0[u][j], I.auras.applied[u][j] = 1e6, applied
    end

    it("the reduced state per (aura, unit) from the leaf's counts through I.ReduceFact", function()
        local function same(j, u)
            local st, agree = I.ReduceFact(Q.Counts(j, u))
            local k = (u - 1) * I.AURA_UNIT + j
            assert.are.same({ st, agree, (Q.Counts(j, u)) }, { R.fact.state[k], R.fact.agree[k], R.fact.n[k] })
        end
        same(1, 1)
        ctl.ViewerAura(a, "player")
        sweep(2)
        same(1, 1)
        assert.are.equal(I.UP, R.fact.state[1])
        rec(1, 1, 2)
        ctl.ViewerAura(b, "player")
        sweep(2.5)
        ctl.ViewerClear(b) -- b held this application, then silent: a live NONE newer than a's UP
        sweep(3)
        same(1, 1)
        assert.are.same({ I.UNDECIDED, false, 2 }, { R.fact.state[1], R.fact.agree[1], R.fact.n[1] })
        ctl.ViewerClear(a)
        sweep(4)
        same(1, 1)
        assert.are.equal(I.DOWN, R.fact.state[1])
        assert.are.equal(I.DOWN, R.Presence(1, 1))
    end)

    it(
        "fact.pdark and pdarkT (cdm-verdict §2.3): a proven dark with none lit and its start, no state change",
        function()
            ctl.viewer.sets[2][3], ctl.viewer.infos[503] = 503, { spellID = fs.SPENDER_A }
            b.cooldownID = 503 -- one frame per cooldownID, as the client keeps them (proof is per cooldownID)
            R.Activate(api, 1.5, d, { viewer = true })
            local edges = 0
            R.onEdge = function()
                edges = edges + 1
            end
            ctl.ViewerAura(a, "player")
            sweep(2)
            assert.are.same({ false, 0 }, { R.fact.pdark[1], R.fact.pdarkT[1] })
            ctl.ViewerClear(a)
            sweep(3)
            assert.are.same({ true, 3 }, { R.fact.pdark[1], R.fact.pdarkT[1] }) -- from the first monitored dark sweep
            local st, ft = R.fact.state[1], R.fact.t[1]
            edges = 0
            sweep(4)
            assert.are.same({ true, 3 }, { R.fact.pdark[1], R.fact.pdarkT[1] })
            assert.are.same({ st, ft, 0 }, { R.fact.state[1], R.fact.t[1], edges }) -- no state, no fact.t, no edge
            ctl.ViewerAura(b, "player") -- b lit: nUp > 0, a still dark
            sweep(5)
            assert.are.equal(1, select(7, Q.Counts(1, 1)))
            assert.is_false(R.fact.pdark[1])
            ctl.ViewerClear(b)
            sweep(6)
            assert.are.same({ true, 6 }, { R.fact.pdark[1], R.fact.pdarkT[1] }) -- the latest start: b's
            sweep(7)
            assert.is_true(R.fact.pdark[1])
            ctl.Fire("PLAYER_TARGET_CHANGED") -- a player item: its pdark stands
            assert.is_true(R.fact.pdark[1])
            R.Activate(api, 8, d, { viewer = true }) -- a rebuild clears it
            assert.are.same({ false, 0 }, { R.fact.pdark[1], R.fact.pdarkT[1] })
        end
    )

    it("R.Strike and R.Silent forward to the leaf while it has one", function()
        local got = {}
        local strike, silent = Q.Strike, Q.Silent
        Q.Strike = function(j, u)
            got[#got + 1] = { "strike", j, u }
        end
        Q.Silent = function(j, u)
            got[#got + 1] = { "silent", j, u }
        end
        R.Strike(1, 2)
        R.Silent(2, 2)
        R.Deactivate(9)
        R.Strike(2, 1)
        R.Silent(2, 1)
        Q.Strike, Q.Silent = strike, silent
        assert.are.same({ { "strike", 1, 2 }, { "silent", 2, 2 } }, got)
    end)

    it("the highest standing with nLive > 0 decides: the leaf (1) with live evidence, none (0) without", function()
        assert.are.same({ 0, 0 }, { R.fact.from[1], R.fact.n[1] })
        ctl.ViewerAura(a, "player")
        sweep(2)
        assert.are.same({ 1, 1 }, { R.fact.from[1], R.fact.n[1] })
        ctl.ViewerRelease(a)
        sweep(3)
        assert.are.same({ 0, 0 }, { R.fact.from[1], R.fact.n[1] })
        assert.are.equal(I.UNDECIDED, R.Presence(1, 1))
    end)

    it("onEdge fires on a reduced change only, from the router", function()
        local edges = {}
        R.onEdge = function(j, u, up, t)
            edges[#edges + 1] = { j, u, up, t }
        end
        ctl.ViewerAura(a, "player")
        sweep(2)
        sweep(2.1) -- no change
        ctl.ViewerAura(b, "player") -- a second UP: counts move, the state does not
        sweep(2.2)
        rec(1, 1, 2)
        ctl.ViewerClear(a)
        ctl.ViewerClear(b)
        sweep(3)
        ctl.ViewerRelease(a) -- one slot gone, the other still NONE: DOWN stays, no edge
        sweep(3.5)
        ctl.ViewerRelease(b) -- UNKNOWN: no edge
        sweep(4)
        assert.are.same({ { 1, 1, true, 2 }, { 1, 1, false, 3 } }, edges)
        assert.is_nil(Q.onEdge) -- the leaf sends no edges (the 3b bridge is gone)
        assert.is_nil(Q.Presence)
    end)

    it("disagree counts transitions to disagreement, not polls (M8)", function()
        local c = ctl.ViewerItem("BuffIconCooldownViewer", 3, 501)
        I.Build(d, 1) -- collect c
        ctl.ViewerAura(b, "player")
        ctl.ViewerAura(c, "player")
        sweep(2)
        rec(1, 1, 2)
        ctl.ViewerClear(b) -- b NONE since 3
        sweep(3)
        ctl.ViewerAura(a, "player") -- a UP since 4 (fresher): UP, agree false
        sweep(4)
        assert.are.same({ I.UP, false, 1 }, { R.fact.state[1], R.fact.agree[1], R.disagree[1] })
        sweep(4.1)
        sweep(4.2)
        assert.are.equal(1, R.disagree[1]) -- still disagreeing: not a new transition
        ctl.ViewerAura(b, "player") -- all UP: agree again
        sweep(5)
        assert.is_true(R.fact.agree[1])
        ctl.ViewerClear(b)
        sweep(6) -- b's NONE is now newer: UNKNOWN, agree false: the second transition
        assert.are.same({ I.UNDECIDED, false, 2 }, { R.fact.state[1], R.fact.agree[1], R.disagree[1] })
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.are.equal(0, R.disagree[1]) -- per fight
    end)

    it("lost counts a fact gone UNKNOWN while its record is up; control: the record closed is not lost", function()
        ctl.ViewerAura(a, "player")
        sweep(2)
        rec(1, 1, 2)
        ctl.ViewerRelease(a) -- the item leaves mid-application: the record is up
        sweep(3)
        assert.are.equal(I.UNDECIDED, R.fact.state[1])
        assert.are.equal(1, R.lost[1])
        ctl.ViewerAura(ctl.ViewerAcquire("BuffIconCooldownViewer", 501), "player")
        sweep(4)
        assert.are.equal(I.UP, R.fact.state[1])
        I.auras.exp0[1][1] = 4.5 -- control: the record closed (a normal aura end)
        ctl.ViewerRelease(ctl.viewer.items.BuffIconCooldownViewer[3])
        sweep(5)
        assert.are.equal(I.UNDECIDED, R.fact.state[1])
        assert.are.equal(1, R.lost[1])
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.are.equal(0, R.lost[1]) -- per fight
    end)

    it("fact.t is the last UNKNOWN/DOWN->UP time (I3)", function()
        assert.are.equal(0, R.fact.t[1])
        ctl.ViewerAura(a, "player")
        sweep(2)
        assert.are.equal(2, R.fact.t[1])
        sweep(3) -- UP stays: unchanged
        ctl.ViewerAura(b, "player")
        sweep(3.5)
        assert.are.equal(2, R.fact.t[1])
        rec(1, 1, 2)
        ctl.ViewerClear(a)
        ctl.ViewerClear(b)
        sweep(4)
        assert.are.equal(I.DOWN, R.fact.state[1])
        ctl.ViewerAura(a, "player")
        sweep(5) -- DOWN -> UP
        assert.are.equal(5, R.fact.t[1])
        ctl.ViewerRelease(a)
        ctl.ViewerRelease(b)
        sweep(6) -- UP -> UNKNOWN: t stays
        assert.are.equal(5, R.fact.t[1])
        ctl.ViewerAura(ctl.ViewerAcquire("BuffIconCooldownViewer", 501), "player")
        sweep(7) -- UNKNOWN -> UP
        assert.are.equal(7, R.fact.t[1])
    end)

    it("rebuild events in combat wait for combat end; evidence changes apply at once (decision 99)", function()
        ctl.viewer.sets[2][#ctl.viewer.sets[2] + 1] = 503
        ctl.viewer.infos[503] = { spellID = fs.SPENDER_M }
        d.auras[3], d.auraIds[3] = { key = "spender_m", id = fs.SPENDER_M }, { fs.SPENDER_M }
        I.Build(d, 1)
        local m = ctl.ViewerItem("BuffIconCooldownViewer", 3, 503)
        ctl.viewer.sets[2][3] = nil -- spender_m untracked until the set changes
        I.Build(d, 1)
        assert.is_false(R.tracked[3])
        I.inCombat = true
        ctl.viewer.sets[2][3] = 503
        ctl.Fire("COOLDOWN_VIEWER_DATA_LOADED")
        assert.is_false(R.tracked[3]) -- waits
        ctl.ViewerAura(a, "player")
        sweep(2)
        assert.are.equal(I.UP, R.Presence(1, 1)) -- evidence: at once
        I.inCombat = false
        ctl.ViewerAura(m, "player")
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(R.tracked[3])
        assert.are.equal(I.UP, R.Presence(3, 1))
    end)

    it("activated with zero items, an item collected later is counted and followed", function()
        ctl.ViewerRelease(a)
        ctl.ViewerRelease(b)
        local api2, ctl2 = fake.new()
        ctl2.now = 1
        ctl2.viewer.sets[2] = { 501 }
        ctl2.viewer.infos[501] = { spellID = fs.SPENDER_A }
        local ns = load.module()
        local I2 = ns.VirtualStateInternal
        local d2 = fs.def(fs.new(9))
        d2.providers = { presence = "router", viewer = true }
        I2.Build(d2, 1)
        ns.VirtualState.Start(api2)
        assert.are.equal(0, I2.PRESENCE.viewer.nSlots)
        assert.are.equal(0, I2.presence.covered)
        local item = ctl2.ViewerAcquire("BuffIconCooldownViewer", 501)
        ctl2.ViewerAura(item, "player")
        ctl2.now = 2
        I2.Sources.RunPolls(2) -- poll 15 sweeps before its covered == 0 guard
        assert.are.equal(1, I2.presence.covered)
        assert.are.equal(I2.UP, I2.presence.Presence(1, 1))
        I2.auras.exp0[1][1], I2.auras.applied[1][1] = 1e6, 2
        ctl2.ViewerClear(item)
        ctl2.now = 3
        I2.Sources.RunPolls(3) -- followed: its silence for this application is DOWN
        assert.are.equal(I2.DOWN, I2.presence.Presence(1, 1))
    end)

    it("a raise in the router's reduction or onEdge is a self-off: one def.error line, all reset at once", function()
        local lines = {}
        I.def.error = function(fmt, ...)
            lines[#lines + 1] = string.format(fmt, ...)
        end
        ctl.ViewerAura(a, "player")
        sweep(2)
        assert.are.equal(I.UP, R.Presence(1, 1)) -- control: on and answering
        R.onEdge = function()
            error("consumer")
        end
        rec(1, 1, 2)
        ctl.ViewerClear(a) -- DOWN: an edge, which raises
        assert.has_no.errors(function()
            sweep(3)
        end)
        assert.are.equal(1, #lines)
        assert.are.equal(1, Q.errors)
        assert.is_false(Q.Mappable(1))
        assert.is_false(R.tracked[1]) -- at once, not at the next activation
        assert.is_false(R.tracked[2])
        assert.are.equal(I.UNDECIDED, R.fact.state[1])
        assert.are.equal(I.UNDECIDED, R.Presence(1, 1))
        assert.are.equal(0, R.covered)
        ctl.ViewerAura(a, "player")
        sweep(4) -- off: a no-op, no second line
        assert.are.equal(1, #lines)
        assert.are.equal(I.UNDECIDED, R.Presence(1, 1))
    end)

    it("after a sweep raise the router's tracked set is cleared at once", function()
        ctl.ViewerAura(a, "player")
        sweep(2)
        assert.is_true(R.tracked[1])
        api.BuffIconCooldownViewer.IsVisible = function()
            error("forbidden")
        end
        sweep(3)
        assert.is_false(R.tracked[1])
        assert.are.equal(I.UNDECIDED, R.fact.state[1])
        assert.are.equal(0, R.covered)
    end)
end)
