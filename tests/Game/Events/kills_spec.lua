-- tests/Game/Events/kills_spec.lua (unit-registry spec §2.5, §3.3.2, §3.6): a kill's rows and closes, from the
-- 2026-10-22 kill-events capture's order: the killing swing and PARTY_KILL in one ms, UNIT_DIED and PLAYER_TARGET_DIED
-- 2 ms later, the target cleared 2 ms after that, a new target 20 ms later, and the killing WOUND 456 ms after the
-- swing on softinteract alone (the corpse); and the first swing of a combat.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("kills and the first swing", function()
    local api, ctl, ns, VS, I, T, X, saved, got

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        T, X = I.Tickets, I.Expect
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        VS.Start(api)
        got = {}
        local f = I.Events.CreateFrame("Frame")
        f:SetScript("OnEvent", function()
            got[#got + 1] = { ns.Facade.CombatLogGetCurrentEventInfo() }
        end)
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("pays the white killing blow that lands on softinteract after the clear", function()
        ctl.now = 4.364
        ctl.Fire("PLAYER_SWING", 1.6, 0)
        ctl.Fire("PARTY_KILL", "Player-1", "Creature-1")
        ctl.now = 4.366
        ctl.Fire("UNIT_DIED", "Creature-1")
        ctl.Fire("PLAYER_TARGET_DIED")
        ctl.guid.target = nil
        ctl.now = 4.368
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.guid.target = "Creature-2"
        ctl.now = 4.388
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.guid.softinteract = "Creature-1"
        ctl.now = 4.82
        ctl.Fire("UNIT_COMBAT", "softinteract", "WOUND", "", 5, 1)
        assert.are.equal(1, T.paid[X.MELEE])
        local r = got[#got]
        assert.are.same({ "SWING_DAMAGE", 4.364, "Creature-1", 5 }, { r[2], r[1], r[8], r[12] })
    end)

    it("closes a projectile's ticket on a unit another source killed as closedDead, not lost, not ours", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 10.5
        ctl.Fire("UNIT_DIED", "Creature-1")
        ctl.Tick(12)
        assert.are.same({ 1, 0, 0 }, { T.closed.dead, T.lost[X.FLIGHT], T.ours })
    end)

    it("marks the first swing after PLAYER_ENTER_COMBAT, which explains an avoid anywhere in its window", function()
        ctl.now = 9.5
        ctl.Fire("PLAYER_ENTER_COMBAT")
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        local i
        for j = 1, T.CAP do
            if T.state[j] ~= T.FREE and T.kind[j] == X.MELEE then
                i = j
            end
        end
        assert.is_true(T.first[i])
        ctl.now = 10.9
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 10.91
        ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1) -- in the cast's frame, 0.91 s after the first swing
        for _, r in ipairs(got) do
            assert.is_false(r[2] == "SPELL_MISSED", "the first swing's lag spans its window: the swing's avoid")
        end
        ctl.now = 13
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        for j = 1, T.CAP do
            if T.state[j] ~= T.FREE and T.kind[j] == X.MELEE and T.at[j] == 13 then
                assert.is_false(T.first[j])
            end
        end
        -- a credited first swing teaches no lag (its one-sample lag is no measurement, spec §3.3.2)
        local L = I.Log
        ctl.now = 20
        ctl.damage = { 4, 6, 2, 3 } -- read at the combat end: the wound's amount class is known (exact main)
        ctl.Fire("PLAYER_REGEN_ENABLED")
        ctl.Fire("PLAYER_ENTER_COMBAT")
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        local med, spr, credited = L.med[1], L.spr[1], L.credited[1]
        ctl.now = 20 + med + spr / 2 -- inside the learning gate: any other clean credit would move the median
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 5, 1)
        assert.are.equal(credited + 1, L.credited[1])
        assert.are.same({ med, spr }, { L.med[1], L.spr[1] })
    end)

    it("marks both hands' swings the client sent in the same ms before PLAYER_ENTER_COMBAT, and only those", function()
        ctl.now = 30
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Fire("PLAYER_SWING", 2.6, 1)
        ctl.now = 30.005
        ctl.Fire("PLAYER_ENTER_COMBAT")
        local n = 0
        for j = 1, T.CAP do
            if T.state[j] ~= T.FREE and T.kind[j] == X.MELEE then
                assert.is_true(T.first[j])
                n = n + 1
            end
        end
        assert.are.equal(2, n)
        ctl.now = 32.6
        ctl.Fire("PLAYER_SWING", 2.6, 0) -- marked already: the next swing is no first swing
        for j = 1, T.CAP do
            if T.state[j] ~= T.FREE and T.kind[j] == X.MELEE and T.at[j] == 32.6 then
                assert.is_false(T.first[j])
            end
        end
    end)

    it(
        "holds a SENT with no outcome (a cancelled queued strike) 60 s, then stops it; FAILED_QUIET stops at once",
        function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-7", fs.SPENDER_F)
            ctl.guid.target = nil
            ctl.now = 10.01
            ctl.Fire("PLAYER_TARGET_CHANGED")
            ctl.Tick(69)
            local i = 0
            for j = 1, T.CAP do
                if T.state[j] == T.COMMITTED then
                    i = j
                end
            end
            assert.is_true(i > 0, "still committed at 59 s")
            local u = I.Units.Find("Creature-1")
            assert.is_true(u > 0 and I.Units.uState[u] ~= I.Units.GONE, "its unit still held, not gone")
            ctl.Tick(70.1)
            assert.are.same({ T.FREE, 1 }, { T.state[i], T.closed.stopped })
            ctl.guid.target = "Creature-2"
            ctl.now = 71
            ctl.Fire("PLAYER_TARGET_CHANGED")
            ctl.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-8", fs.SPENDER_F)
            ctl.Fire("UNIT_SPELLCAST_FAILED_QUIET", "player", "Cast-8", fs.SPENDER_F)
            assert.are.equal(2, T.closed.stopped)
            for j = 1, T.CAP do
                assert.are_not.equal(T.COMMITTED, T.state[j])
            end
        end
    )
end)
