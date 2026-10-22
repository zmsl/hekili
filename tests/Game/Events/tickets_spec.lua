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
end)
