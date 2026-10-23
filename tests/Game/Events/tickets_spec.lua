-- tests/Game/Events/tickets_spec.lua (unit-registry spec §3): the ticket pool's lifecycle. One ticket per commit
-- (swing, success mapped or not, a hard cast at its START); payment in expected-closure order on the row's GUID;
-- closes and their counters; the conservation identity.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("the ticket pool", function()
    local api, ctl, ns, VS, I, T, X, U, saved, got, cleu

    local function sum()
        local n = 0
        for _, v in pairs(T.closed) do
            n = n + v
        end
        for i = 1, T.CAP do
            n = n + (T.state[i] ~= T.FREE and 1 or 0)
        end
        return n
    end

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        T, X, U = I.Tickets, I.Expect, I.Units
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        VS.Start(api)
        got = {}
        cleu = I.Events.CreateFrame("Frame")
        cleu:SetScript("OnEvent", function()
            local r = { ns.Facade.CombatLogGetCurrentEventInfo() }
            got[#got + 1] = r
        end)
        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("opens one ticket per commit: a swing, a mapped success, an unmapped one; NONE closes at once", function()
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 999999)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", fs.SPENDER_N)
        assert.are.equal(4, T.opened)
        assert.are.equal(1, T.closed.none)
        assert.are.equal(T.opened, sum())
    end)

    it("pays a row on the ticket's own GUID only; another GUID's row is foreign", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.guid.nameplate2 = "Creature-2"
        ctl.now = 10.01
        ctl.Fire("UNIT_COMBAT", "nameplate2", "WOUND", "", 30, 4)
        assert.are.equal(1, T.foreign)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 4)
        assert.are.equal(1, T.paid[X.FRAME])
        assert.are.same({ "SPELL_DAMAGE", "Creature-1", fs.SPENDER_F, 4, 30 }, {
            got[#got][2],
            got[#got][8],
            got[#got][12],
            got[#got][14],
            got[#got][15],
        })
    end)

    it("counts our AoE's side hits in one frame as aoeOther after the target's row paid the frame (K18)", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.guid.nameplate2, ctl.guid.nameplate3 = "Creature-2", "Creature-3"
        ctl.now = 10.01
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 4)
        ctl.Fire("UNIT_COMBAT", "nameplate2", "WOUND", "", 33, 4)
        ctl.Fire("UNIT_COMBAT", "nameplate3", "WOUND", "", 35, 4)
        assert.are.same({ 1, 2, 2 }, { T.paid[X.FRAME], T.foreign, T.aoeOther })
        ctl.now = 10.2 -- past the frame: a side hit is plain foreign
        ctl.Fire("UNIT_COMBAT", "nameplate2", "WOUND", "", 31, 4)
        assert.are.same({ 3, 2 }, { T.foreign, T.aoeOther })
    end)

    it("pays the least expected closure first: the older of two frames", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        local first = T.Arm("none", 0) -- no committed ticket: 0
        assert.are.equal(0, first)
        ctl.now = 10.02
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_F)
        ctl.now = 10.03
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 4)
        local open = 0
        for i = 1, T.CAP do
            if T.state[i] == T.OPEN and T.kind[i] == X.FRAME then
                open = open + 1
                assert.are.equal(10.02, T.at[i])
            end
        end
        assert.are.equal(1, open)
    end)

    it("refuses a WOUND of another school on a declared ticket", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 10.002
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 4, 32) -- a life-steal proc in the strike's frame
        assert.are.equal(0, T.paid[X.FRAME])
        assert.are.equal(1, T.foreign)
    end)

    it("closes by expiry: lost for a declared school, expired for ANY, unpinned with no pin", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_C)
        ctl.guid.target = nil
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", fs.SPENDER_F)
        ctl.Tick(12)
        assert.are.same({ 1, 1, 1 }, { T.closed.lost, T.closed.expired, T.closed.unpinned })
        assert.are.equal(1, T.lost[X.FRAME])
        assert.are.equal(T.opened, sum())
    end)

    it("commits a cast at SENT, arms it at its success, and drops it uncounted on FAILED", function()
        ctl.casting = { 10000, 11500 }
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-5", fs.SPENDER_C)
        assert.are.equal(1, T.opened) -- committed at SENT (spec decision 10), before its START
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-5", fs.SPENDER_C)
        local i = 0
        for j = 1, T.CAP do
            if T.state[j] == T.COMMITTED then
                i = j
            end
        end
        assert.is_true(i > 0)
        ctl.now = 11.5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", fs.SPENDER_C)
        assert.are.same({ T.OPEN, 11.5 }, { T.state[i], T.at[i] })
        ctl.now = 12
        ctl.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-6", fs.SPENDER_C)
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-6", fs.SPENDER_C)
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-6", fs.SPENDER_C)
        assert.are.equal(1, T.closed.stopped)
    end)

    it("lets an unmapped success's window absorb an avoid past a cast's frame as nobody's", function()
        ctl.now = 4
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 999999)
        ctl.now = 5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 5.4
        ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
        assert.are.equal(1, T.absorbed)
        assert.are.equal(0, T.paid[X.FRAME])
    end)

    it("claims for the registry a row an open ticket on a unit still owes", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        local u = U.Uid(1)
        assert.is_true(T.Claims(u, "WOUND", 4))
        assert.is_true(T.Claims(u, "MISS", 1))
        assert.is_false(T.Claims(u, "WOUND", 8))
    end)

    it("carries the row's school on a default type's SPELL_DAMAGE (ANY names none)", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 32)
        assert.are.same({ "SPELL_DAMAGE", 32, 32 }, { got[#got][2], got[#got][14], got[#got][17] })
    end)

    it("an avoid two casts could own, one the latest, is divergent: paid to the older, no row", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
        ctl.now = 10.1
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_C)
        local n = #got
        ctl.now = 10.3
        ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
        assert.are.equal(1, T.divergent)
        assert.are.equal(1, T.paid[X.FRAME])
        for k = n + 1, #got do
            assert.are_not.equal("SPELL_MISSED", got[k][2])
        end
        for i = 1, T.CAP do
            if T.state[i] == T.OPEN then
                assert.are.equal(10.1, T.at[i]) -- the older one paid
            end
        end
    end)

    it("a crit two casts of one ability could own is not divergent (the same state either way)", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
        ctl.now = 10.02
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_C)
        ctl.now = 10.03
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 60, 32)
        assert.are.equal(0, T.divergent)
        assert.are.equal(1, T.paid[X.FRAME])
    end)

    it("closes at combat end without the registry's hold counts (a reset unit's tickets too)", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
        ctl.guid.target = nil
        ctl.Fire("PLAYER_TARGET_CHANGED") -- the unit keeps no token: combat end resets it, holds zeroed, first
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(1, T.closed.ended)
        assert.are.equal(T.opened, sum())
    end)

    it("closes every open ticket at combat end, counted once", function()
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(2, T.closed.ended)
        assert.are.equal(T.opened, sum())
    end)

    describe("the pending swing (single owner)", function()
        it("is the hand's latest open swing within min(landing window, 1 s), until its credit", function()
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            assert.are.equal(10, T.SwingPending(1, 10.3))
            assert.are.equal(0, T.SwingPending(2, 10.3))
            assert.are.equal(0, T.SwingPending(1, 10 + T.PendingWindow(1) + 0.01))
            ctl.now = 10.47
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1) -- credited
            assert.are.equal(0, T.SwingPending(1, 10.5))
        end)

        it("does not make a retraction's re-open the hand's latest swing", function()
            local i = T.OpenSwing(20, 1, "Creature-1", 1.5, 0, false, true)
            assert.are.equal(T.OPEN, T.state[i])
            assert.are.equal(0, T.SwingPending(1, 20.1))
        end)

        it("swallows the main-hand swing after a strike whose success came first", function()
            ctl.now = 30
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_B)
            ctl.now = 30.1
            ctl.Fire("PLAYER_SWING", 2.6, 0) -- the strike's own swing: no swing ticket
            for j = 1, T.CAP do
                assert.is_false(T.state[j] ~= T.FREE and T.kind[j] == X.MELEE, "a swing ticket for the strike's swing")
            end
            assert.are.equal(30.1, T.SwingPending(1, 30.2)) -- pending through its window, as pendT held it
            assert.are.equal(0, T.SwingPending(1, 30.1 + T.PendingWindow(1) + 0.01))
            ctl.now = 32.8
            ctl.Fire("PLAYER_SWING", 2.6, 0) -- the next one is a swing again
            assert.are.equal(32.8, T.SwingPending(1, 32.9))
        end)

        it("swallows it even when the strike's own row came first in that frame", function()
            ctl.now = 30
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_B)
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 40, 1) -- the strike's row: its ticket paid
            ctl.now = 30.01
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            for j = 1, T.CAP do
                assert.is_false(T.state[j] ~= T.FREE and T.kind[j] == X.MELEE, "a swing ticket for the strike's swing")
            end
        end)
    end)

    it("pays a projectile's landing in its hard window and learns the GUID's lag from it", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
        ctl.casting = { 10000, 11500 }
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-1", fs.SPENDER_P)
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 11.5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 13.0
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 8)
        assert.are.equal(1, T.paid[X.FLIGHT])
        local r = T.LagOf("Creature-1", 20)
        assert.is_true(r > 0 and math.abs(T.lagE[r] - 1.5) < 1e-9)
        assert.are.same({ "SPELL_DAMAGE", 11.5, 8, true }, { got[#got][2], got[#got][1], got[#got][14], got[#got][21] })
    end)

    it("pays two projectiles of one queue in cast order (FIFO by expected closure)", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
        T.Learn("Creature-1", 20, 1.5, 9)
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 10.6
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_P)
        ctl.now = 11.5
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 15, 8)
        ctl.now = 12.1
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 16, 8)
        local t1, t2 = got[#got - 1][1], got[#got][1]
        assert.are.same({ 10, 10.6 }, { t1, t2 })
    end)

    it("pays a row past a learned ticket's widened band inside its hard window: Overdue (decision 46)", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 40 -- H = 2.15
        T.Learn("Creature-1", 20, 1.5, 9) -- d = 2.5 s at the 10 s anchor: widened band [10.313, 11.9375]
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        local a, r = I.ab.bySpell[fs.SPENDER_P], T.LagOf("Creature-1", 20)
        local bandN, lagN = T.bandN[a], T.lagN[r]
        ctl.now = 12.0 -- past the widened band, inside the hard window (12.15)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 15, 8)
        assert.are.equal(0, T.foreign)
        assert.are.same({ "SPELL_DAMAGE", 10 }, { got[#got][2], got[#got][1] })
        -- an Overdue payment teaches neither the lag nor the amount band (spec §1.1: only once final)
        assert.are.same({ 1.5, lagN, bandN }, { T.lagE[r], T.lagN[r], T.bandN[a] })
    end)

    it("never pays an early row at pass (d): under a learned ticket's widened band stays foreign", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30 -- H = 1.65
        T.Learn("Creature-1", 20, 1.5, 9) -- widened band [10.313, 11.65]
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 10.2 -- early: before the expected tolerance, inside the hard window
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 15, 8)
        assert.are.equal(1, T.foreign)
    end)

    it("never hands a cast at pass (d) an avoid the MELEE tie took for a swing the LR then rejects", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 40 -- H = 2.15
        T.Learn("Creature-1", 20, 1.5, 9) -- narrow band [11.35, 11.65], widened [10.313, 11.9375]
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 11.326
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        for c = 1, 8 do
            I.Log.bg[c] = 50 -- a crowd: the LR stays below its bar
        end
        ctl.now = 11.8 -- the flight's pass (b) and pass (d) both hold it; the swing's core band too (lag 0.474)
        ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
        assert.are.same({ 1, 0 }, { T.foreign, T.paid[X.FLIGHT] })
    end)

    -- Decision 53 as amended 2026-10-23 (Task 4): the crowd gate refuses; a refused flight closes lost at its hard
    -- window's end, with no expectation (the expiry EV is a swing's only)
    for _, row in ipairs({ { "WOUND", 15, 8 }, { "DODGE", 0, 1 } }) do
        it(
            "the crowd gate refuses an early " .. row[1] .. ": foreign, the flight closes lost (decision 53 amended)",
            function()
                I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30 -- H = 1.65: hard window to 11.65
                T.Learn("Creature-1", 20, 1.5, 9) -- bound edge 10.313; crowded edge 11.5 - 0.875 = 10.625
                ctl.now = 10
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
                local i = 0
                for j = 1, T.CAP do
                    i = (T.state[j] == T.OPEN and T.kind[j] == X.FLIGHT) and j or i
                end
                T.Foreign(T.uid[i], 8, 9.5) -- another nature source on the unit within CROWD
                ctl.now = 10.45 -- inside the bound, under the crowded edge: refused
                ctl.Fire("UNIT_COMBAT", "target", row[1], "", row[2], row[3])
                assert.are.same({ 1, T.OPEN }, { T.foreign, T.state[i] })
                ctl.Tick(11.7)
                assert.are.same({ 0, 1, 0 }, { T.state[i], T.closed.lost, T.closed.assumed })
                assert.are.same({ 1, 0 }, { T.lost[X.FLIGHT], T.paid[X.FLIGHT] })
                assert.are.equal(T.opened, sum())
            end
        )
    end

    it("prints the recovery counters on the Snapshot line", function()
        local line = VS.Snapshot() -- Game/State/Snapshot.lua: every OnSnapshot line, joined
        assert.is_truthy(line:find("tentative=%d+ replaced=%d+ assumed=%d+ confirmed=%d+ refunded=%d+"))
    end)

    it(
        "leaves a white wound the swing LR rejects foreign: an open swing has no Overdue (decision 46 amended)",
        function()
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            for c = 1, 8 do
                I.Log.bg[c] = 50 -- a crowd: every background rate high, so the LR stays below its bar
            end
            ctl.now = 11.2 -- 1.2 s: past the core band, inside the 1.5 s window
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            assert.are.equal(1, T.foreign) -- another player's white hit on our mob: the swing reaches pass (d) only ASSUMED
        end
    )

    it("leaves a tick outside every schedule band foreign: no Overdue for ticks (decision 47)", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
        ctl.now = 10.01
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 9, 64) -- the direct hit
        ctl.now = 11.5 -- between the application and the first tick (13 +- 0.1)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 4, 64)
        assert.are.equal(1, T.foreign)
    end)

    it("counts a cast whose avoid an unmapped window absorbed past its frame as expired, never lost", function()
        ctl.now = 4
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 999999)
        ctl.now = 5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 5.4
        ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
        assert.are.equal(1, T.absorbed)
        ctl.Tick(8)
        assert.are.same({ 0, 0, 2 }, { T.closed.lost, T.lost[X.FRAME], T.closed.expired })
        assert.are.equal(T.opened, sum())
    end)

    it("counts an excused cast on a dead unit as dead, not expired", function()
        ctl.now = 4
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 999999)
        ctl.now = 5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 5.4
        ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
        ctl.Fire("UNIT_DIED", "Creature-1")
        ctl.Tick(8)
        assert.are.same({ 0, 1, 1 }, { T.closed.lost, T.closed.dead, T.closed.expired })
    end)

    it("leaves a projectile's own avoid in its hard window to it, an unmapped window open or not", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
        ctl.now = 9.5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 999999)
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 11.4
        ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
        assert.are.same({ 0, 1 }, { T.absorbed, T.paid[X.FLIGHT] })
    end)

    describe("replaceable payments (attribution-recovery decision 48)", function()
        local staged, stage

        before_each(function()
            staged, stage = {}, I.Sources.Stage
            I.Sources.Stage = function(kind, t, a, b, c)
                staged[#staged + 1] = { kind, b, c, a }
                return stage(kind, t, a, b, c)
            end
        end)

        after_each(function()
            I.Sources.Stage = stage
        end)

        local function count(kind, c)
            local n = 0
            for _, s in ipairs(staged) do
                n = n + ((s[1] == kind and (c == nil or s[3] == c)) and 1 or 0)
            end
            return n
        end

        it("a dodge in the swing's core band replaces a wound credited before it; the rage is taken back", function()
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            ctl.now = 10.2 -- before the core band (0.474 +- 0.12): credited by the LR, provisionally
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            assert.are.equal(T.TENT, T.state[i])
            assert.are.equal(1, count(VS.Obs.Swing, 1))
            ctl.now = 10.47 -- our own DODGE, in the core band
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            assert.are.same({ 1, 1 }, { T.replaced, T.foreign })
            assert.are.equal(1, count(VS.Obs.Swing, 6))
            assert.are.same({ T.PROV, "DODGE" }, { T.state[i], T.avoid[i] })
        end)

        it("holds a provisional spell payment's crit and drops it on replacement by the cast's own avoid", function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
            T.Learn("Creature-1", 20, 1.5, 9) -- narrow band [11.35, 11.65] for the 10 s cast
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
            ctl.now = 10.6 -- the widened band, before the narrow one: provisional
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 8)
            assert.are.equal(0, count(VS.Obs.Crit))
            ctl.now = 11.5
            ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
            assert.are.same({ 1, 1 }, { T.replaced, T.foreign })
            assert.are.same({ 0, 1 }, { count(VS.Obs.Crit), count(VS.Obs.Avoided) })
            assert.are.equal(1, T.paid[X.FLIGHT])
        end)

        it("stages a held crit once the narrow band passes with no replacement, and teaches then", function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
            T.Learn("Creature-1", 20, 1.5, 9)
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
            ctl.now = 10.6
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 8)
            local r = T.LagOf("Creature-1", 20)
            assert.is_true(math.abs(T.lagE[r] - 1.5) < 1e-9) -- not taught while provisional
            ctl.Tick(11.7) -- past the narrow band's end (11.65): final
            assert.are.same({ 1, 1 }, { count(VS.Obs.Crit), T.paid[X.FLIGHT] })
            assert.is_true(math.abs(T.lagE[r] - 0.6) < 1e-9)
            assert.are.equal(T.opened, sum())
        end)

        it(
            "EARLY variant (off by default): an early row pays provisionally; the narrow-band row replaces it",
            function()
                I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
                T.Learn("Creature-1", 20, 1.5, 9) -- narrow band [11.35, 11.65], widened from 10.313
                T.EARLY = true
                ctl.now = 10
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
                ctl.now = 10.2 -- before the widened band: pass 5
                ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 15, 8)
                local early = T.foreign
                ctl.now = 11.5
                ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 16, 8)
                T.EARLY = false
                assert.are.same({ 0, 1, 1, 1 }, { early, T.replaced, T.foreign, T.paid[X.FLIGHT] })
            end
        )

        local function swingsOf(hand, c)
            local n = 0
            for _, s in ipairs(staged) do
                n = n + ((s[1] == VS.Obs.Swing and s[3] == c and s[4] == hand) and 1 or 0)
            end
            return n
        end

        it("re-offers the displaced wound to the open off-hand swing: our own swap is no foreign row (Fury)", function()
            ctl.now = 9
            ctl.damage = { 28, 32, 10, 12 } -- read at the combat end: 30 is the main hand's, never the off hand's
            ctl.Fire("PLAYER_REGEN_ENABLED")
            ctl.now = 9.3
            ctl.Fire("PLAYER_SWING", 2.6, 1)
            ctl.now = 9.88
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local main = T.lastSwing[1]
            ctl.now = 10.003 -- the off hand's median lag; 0.123 s after the main swing: the LR credits the main, early
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            assert.are.same({ T.TENT, 0 }, { T.state[main], swingsOf(2, 1) })
            ctl.now = 10.354 -- the main swing's own MISS, in its core band
            ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
            assert.are.same({ 0, 1, 1 }, { T.foreign, T.replaced, swingsOf(2, 1) })
            assert.are.same({ T.PROV, "MISS" }, { T.state[main], T.avoid[main] })
        end)

        it("makes a swing credit a spend already measured final instead of replacing it (spec 2.3)", function()
            local R = I.res
            local slot = R.slotOf[fs.RAGE]
            ctl.now = 150 -- after the fake client's start (100): the fold is in order
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            ctl.now = 150.2
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            I.Sources.Flush()
            I.Fold(150.2)
            assert.is_false(I.CreditFixed(T.rec[i]))
            R.spends[slot] = R.spends[slot] + 1 -- a spend of ours from the slot: the pool is measured
            ctl.now = 150.47
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            assert.are.same({ 0, 0, 1 }, { T.replaced, T.state[i], T.paid[X.MELEE] })
            assert.are.equal(0, count(VS.Obs.Swing, 6))
        end)

        it("pays an off-hand replacement in the main reference's core band final at once", function()
            ctl.now = 7
            ctl.damage = { 28, 32, 28, 32 }
            ctl.Fire("PLAYER_REGEN_ENABLED")
            ctl.now = 8
            ctl.Fire("PLAYER_SWING", 1.2, 0) -- its window closes before the rows (1.2 s)
            ctl.now = 9.2
            ctl.Fire("PLAYER_SWING", 1.5, 1) -- main reference 8: core band 9.686 +- 0.04; its own 9.903 +- 0.04
            local off = T.lastSwing[2]
            ctl.now = 9.4 -- early: credited provisionally
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            assert.are.equal(T.TENT, T.state[off])
            ctl.now = 9.686 -- the main reference's core band only
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 31, 1)
            assert.are.same({ 1, 0 }, { T.replaced, T.state[off] }) -- final: closed paid, not TENT again
        end)

        it("pays a pass (a) row final at once: no TENT", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
            ctl.now = 10.01
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 4)
            assert.are.same({ 1, 1 }, { T.paid[X.FRAME], count(VS.Obs.Crit) })
        end)
    end)

    describe("assumed outcomes, expiry EV (attribution-recovery decision 51 as ruled 2026-10-23)", function()
        local staged, stage

        before_each(function()
            staged, stage = {}, I.Sources.Stage
            I.Sources.Stage = function(kind, t, a, b, c)
                staged[#staged + 1] = { kind, b, c }
                return stage(kind, t, a, b, c)
            end
            for c = 1, 8 do
                I.Log.bg[c] = 50 -- a crowd: late rows stay below the LR bar and reach the shadow through Overdue
            end
        end)

        after_each(function()
            I.Sources.Stage = stage
        end)

        local function count(c)
            local n = 0
            for _, s in ipairs(staged) do
                n = n + ((s[1] == VS.Obs.Swing and s[3] == c) and 1 or 0)
            end
            return n
        end

        local function assumedSwing() -- a provider's HIT (T.Assume) before its row
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            T.Assume(i, 10.7)
            return i
        end

        it("stages the expectation at a swing's lost close; no shadow before it", function()
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            ctl.Tick(10 + T.PendingWindow(1) + 0.01)
            assert.are.same({ T.OPEN, 0 }, { T.state[i], count(5) })
            ctl.Tick(11.6)
            assert.are.same({ 1, 1 }, { T.closed.lost, count(5) })
        end)

        it(
            "stages nothing at a lost close when a white avoid nobody took fell in the window (maybe its own)",
            function()
                ctl.now = 10
                ctl.Fire("PLAYER_SWING", 2.6, 0)
                ctl.now = 11.2
                ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1) -- below the LR bar in the crowd: foreign
                ctl.Tick(11.6)
                assert.are.same({ 1, 1, 0 }, { T.foreign, T.closed.lost, count(5) })
            end
        )

        it("stages nothing at a retraction's re-open's lost close", function()
            ctl.now = 10
            T.OpenSwing(10, 1, "Creature-1", 1.5, 0, false, true)
            ctl.Tick(11.6)
            assert.are.same({ 1, 0 }, { T.closed.lost, count(5) })
        end)

        it("assumes an open swing at once through T.Assume (a provider's HIT), once", function()
            local i = assumedSwing()
            T.Assume(i, 10.8)
            assert.are.same({ T.ASSUMED, 1 }, { T.state[i], count(5) })
        end)

        it("confirms a late hit on an assumed swing: the assumption's record becomes the credit", function()
            local i = assumedSwing()
            ctl.now = 11.2
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            assert.are.same({ 1, 0, 1 }, { count(7), count(6), T.closed.confirmed })
            assert.are.equal(0, T.state[i])
        end)

        it("refunds a late dodge on an assumed swing: closed refunded at the window's end", function()
            assumedSwing()
            ctl.now = 11.2
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            assert.are.equal(1, count(6))
            ctl.Tick(11.6)
            assert.are.equal(1, T.closed.refunded)
        end)

        it("lets an assumption stand when no row comes: closed assumed, never lost", function()
            assumedSwing()
            ctl.Tick(11.6)
            assert.are.same({ 1, 0, 1 }, { T.closed.assumed, T.lost[X.MELEE], count(5) })
            assert.are.equal(T.opened, sum())
        end)
    end)

    describe("TICKS", function()
        local function wound(t, amount, sch)
            ctl.now = t
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", amount, sch)
        end

        it("opens the direct ticket and the ticks of an instant with ticks; pays each tick on schedule", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64) -- the direct hit re-anchors the schedule
            for _, t in ipairs({ 13.038, 16.022, 19.072, 21.969 }) do
                wound(t, 4, 64)
            end
            assert.are.same({ 1, 1 }, { T.paid[X.FRAME], T.paid[X.TICKS] })
            assert.are.same({ "SPELL_PERIODIC_DAMAGE", 21.969 }, { got[#got][2], got[#got][1] })
        end)

        it("leaves a tick outside every band foreign", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64)
            wound(11.5, 4, 64)
            assert.are.equal(1, T.foreign)
        end)

        it("closes the old schedule as refreshed on a recast; the new one pays", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64)
            wound(13.0, 4, 64)
            ctl.now = 14
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_M)
            wound(14.002, 8, 64)
            assert.are.equal(1, T.closed.refreshed)
            wound(17.01, 4, 64)
            local paidTicks = 0
            for i = 1, T.CAP do
                if T.state[i] ~= T.FREE and T.kind[i] == X.TICKS then
                    paidTicks = T.done[i]
                end
            end
            assert.are.equal(1, paidTicks)
            assert.are.equal(0, T.lost[X.TICKS])
        end)

        it("closes a dead unit's ticks as closedDead, ours when we killed it, never lost", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64)
            ctl.Fire("PARTY_KILL", "Player-1", "Creature-1")
            ctl.Fire("UNIT_DIED", "Creature-1")
            assert.are.same({ 1, 1, 0 }, { T.closed.dead, T.ours, T.lost[X.TICKS] })
        end)

        it(
            "anchors a ticks-only flight at half the flight with a widened band, then snaps to the first tick",
            function()
                I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30 -- 30 / 40: a 0.75 s flight at most
                ctl.now = 10
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S)
                wound(13.7, 6, 8) -- 3 s after a 0.7 s flight: inside 10.375 + 3 +- (0.1 + 0.375)
                local i
                for j = 1, T.CAP do
                    if T.state[j] ~= T.FREE and T.kind[j] == X.TICKS then
                        i = j
                    end
                end
                assert.are.same({ 1, 0 }, { T.done[i], T.wide[i] })
                assert.is_true(math.abs(T.anchor[i] - 10.7) < 1e-9)
            end
        )

        it("closes a ticks-only ticket with nothing owed when its application is avoided at range", function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S)
            ctl.now = 10.7
            ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
            assert.are.same({ 1, 0 }, { T.paid[X.TICKS], T.lost[X.TICKS] })
        end)

        it("closes a schedule on an early removal of its debuff, not at its modelled expiry", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64)
            T.AuraGone(fs.SPENDER_M, "Creature-1", 22.002) -- the duration: the last tick still owed
            assert.are.equal(0, T.closed.signal)
            T.AuraGone(fs.SPENDER_M, "Creature-1", 15) -- removed early (a handler's removeDebuff)
            assert.are.equal(1, T.closed.signal)
        end)

        it("finds the schedule by its aura's spell ID, not its cast's", function()
            T.tickAuraId[I.ab.bySpell[fs.SPENDER_M]] = 99001 -- an aura whose ID differs from its cast's
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64)
            T.AuraGone(fs.SPENDER_M, "Creature-1", 15)
            assert.are.equal(0, T.closed.signal)
            T.AuraGone(99001, "Creature-1", 15)
            assert.are.equal(1, T.closed.signal)
        end)

        it("leaves the old schedule open when a recast's direct row is an avoid", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64)
            wound(13.0, 4, 64)
            ctl.now = 14
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_M)
            ctl.now = 14.002
            ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
            assert.are.same({ 0, 1 }, { T.closed.refreshed, T.closed.signal })
            wound(16.0, 4, 64) -- the old schedule's second tick
            assert.are.equal(0, T.foreign)
        end)

        it("refreshes an alone schedule at the recast's first tick, and at its old expiry before that", function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S)
            wound(13.7, 6, 8)
            ctl.now = 15
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_S)
            assert.are.equal(0, T.closed.refreshed) -- not confirmed yet
            wound(18.1, 6, 8) -- the recast's first tick (its old tick at 16.7 never came)
            assert.are.same({ 1, 0 }, { T.closed.refreshed, T.lost[X.TICKS] })
            for _, t in ipairs({ 21.1, 24.1 }) do
                wound(t, 6, 8)
            end
            ctl.now = 25 -- recast near the end: the new first tick is due 28.4, the old last (30.1) never comes
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", fs.SPENDER_S)
            wound(27.1, 6, 8) -- the old schedule's fourth tick
            ctl.Tick(30.3)
            assert.are.same({ 2, 0 }, { T.closed.refreshed, T.lost[X.TICKS] })
        end)
    end)

    it("pays a tick in a learned schedule's and a banded projectile's bands to the schedule (owner ruling)", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
        for _, v in ipairs({ 14, 16, 15 }) do -- the nature projectile's band: [0.6 x 14.1, 1.6 x 15.95]; its lag 1.5 s
            T.Pay(T.OpenCast(1, I.ab.bySpell[fs.SPENDER_P], fs.SPENDER_P, "Creature-1"), 2.5, false, v, "", true, 3)
        end
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S) -- a nature schedule (3 s ticks)
        ctl.now = 13.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 6, 8) -- its first tick: no tick band yet; snaps to 10.7
        ctl.now = 15.2
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_P) -- due at 16.7 +- 0.15
        ctl.now = 16.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 7, 8) -- the second tick, also in the projectile's narrow band
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 15, 8) -- the projectile's own landing, the same ms
        local ticks
        for j = 1, T.CAP do
            if T.state[j] ~= T.FREE and T.kind[j] == X.TICKS then
                ticks = j
            end
        end
        assert.are.same({ 2, 7, 4 }, { T.done[ticks], T.tickAmt[ticks], T.paid[X.FLIGHT] })
    end)

    it(
        "ranks a banded direct ticket before a nearer tick in both bands; a tick-only row pays the tick (K21)",
        function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
            for _, v in ipairs({ 14, 16, 15 }) do -- the nature projectile's band: [0.6 x 14.1, 1.6 x 15.95]; its lag 1.5 s
                T.Pay(T.OpenCast(1, I.ab.bySpell[fs.SPENDER_P], fs.SPENDER_P, "Creature-1"), 2.5, false, v, "", true, 3)
            end
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S) -- a nature schedule (3 s ticks)
            ctl.now = 13.7
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 8) -- its first tick: the tick band [5, 20]; next at 16.7
            ctl.now = 15.25
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_P) -- due at 16.75 +- 0.15
            local ticks
            for j = 1, T.CAP do
                if T.state[j] ~= T.FREE and T.kind[j] == X.TICKS then
                    ticks = j
                end
            end
            ctl.now = 16.72
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 12, 8) -- in both bands, the tick's closure nearer
            assert.are.same({ 4, 1 }, { T.paid[X.FLIGHT], T.done[ticks] })
            ctl.now = 16.73
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 6, 8) -- in the tick's band only
            assert.are.same({ 2, 6 }, { T.done[ticks], T.tickAmt[ticks] })
        end
    )

    it("CHANNEL (untested in game, U9): pays a tick per period and closes on its stop", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_H)
        for _, t in ipairs({ 11.02, 11.98, 13.1 }) do
            ctl.now = t
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 5, 64)
        end
        ctl.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-1", fs.SPENDER_H)
        assert.are.same({ 1, 0 }, { T.closed.signal, T.foreign })
    end)
end)
