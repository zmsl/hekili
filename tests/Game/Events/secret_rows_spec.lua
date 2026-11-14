-- tests/Game/Events/secret_rows_spec.lua (owner decision D1, 2026-11-08): on live UNIT_COMBAT's amount is secret and its
-- action, flag and school plain. Rows.lua routes an avoid by its kind and a crit by its kind, flag and school with the
-- amount unknown (never guessed); a plain wound with a secret amount, and a row with a secret flag or school, stay
-- counted as background (as before).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

local S = fake.SECRET

describe("rows with a secret amount (kind-only routing)", function()
    local api, ctl, ns, VS, I, T, X, L, saved, got, staged, stage, cleu

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        T, X, L = I.Tickets, I.Expect, I.Log
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        VS.Start(api)
        got = {}
        cleu = I.Events.CreateFrame("Frame")
        cleu:SetScript("OnEvent", function()
            got[#got + 1] = { ns.Facade.CombatLogGetCurrentEventInfo() }
        end)
        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        staged, stage = {}, I.Sources.Stage
        I.Sources.Stage = function(kind, t, a, b, c)
            staged[#staged + 1] = { kind, b, c, a }
            return stage(kind, t, a, b, c)
        end
    end)

    after_each(function()
        I.Sources.Stage = stage
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    local function count(kind, c)
        local n = 0
        for _, s in ipairs(staged) do
            n = n + ((s[1] == kind and (c == nil or s[3] == c)) and 1 or 0)
        end
        return n
    end

    local function ticket(kind)
        for j = 1, T.CAP do
            if T.state[j] ~= T.FREE and T.kind[j] == kind then
                return j
            end
        end
    end

    it("pays a cast its own DODGE by kind: Obs.Avoided and SPELL_MISSED, no background", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 10.01
        ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, 1)
        assert.are.same({ 1, 1, 0 }, { T.paid[X.FRAME], count(VS.Obs.Avoided), L.background })
        assert.are.same({ "SPELL_MISSED", fs.SPENDER_F, "DODGE" }, { got[#got][2], got[#got][12], got[#got][15] })
    end)

    -- live, a landed instant's own wound is unseen (a plain wound's amount is secret), so its ticket stays open through
    -- its landing window: a secret avoid past its own frame is most likely another's (secret arm, Feral: 15 of 16 false
    -- refunds were late, 3 of 143 right ones). A plain one keeps today's bands.
    it("gives an instant cast a secret avoid only in its own frame; a plain one in its landing window too", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 10.2 -- past the frame, inside the landing window
        ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, 1)
        assert.are.same({ 0, 0 }, { T.paid[X.FRAME], count(VS.Obs.Avoided) })
        ctl.now = 20
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_F)
        ctl.now = 20.2
        ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
        assert.are.same({ 1, 1 }, { T.paid[X.FRAME], count(VS.Obs.Avoided) })
    end)

    it("pays a cast its own crit by kind, flag and school: Obs.Crit, SPELL_DAMAGE with amount 0", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 10.01
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 4)
        assert.are.same({ 1, 1, 0, 0 }, { T.paid[X.FRAME], count(VS.Obs.Crit), L.background, L.fight.paid })
        assert.are.same({ "SPELL_DAMAGE", 4, 0, true }, { got[#got][2], got[#got][14], got[#got][15], got[#got][21] })
    end)

    it("keeps a crit of the wrong school off a declared ticket (the school still decides)", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 10.002
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 32)
        assert.are.same({ 0, 1 }, { T.paid[X.FRAME], T.foreign })
    end)

    it("accepts a secret crit past a learned amount band unranked, and teaches the band nothing", function()
        local a = I.ab.bySpell[fs.SPENDER_F]
        for _, v in ipairs({ 30, 32, 31 }) do
            T.Pay(T.OpenCast(1, a, fs.SPENDER_F, "Creature-1"), 1.01, false, v, "", true, 1)
        end
        local n, lo, hi = T.bandN[a], T.bandLo[a], T.bandHi[a]
        assert.is_true(n >= 3)
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 10.01
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 4)
        assert.are.same({ 4, 1, 0 }, { T.paid[X.FRAME], count(VS.Obs.Crit), T.bandRejected })
        assert.are.same({ n, lo, hi }, { T.bandN[a], T.bandLo[a], T.bandHi[a] })
    end)

    it("pays a schedule's crit tick past its tick band unknown, its last tick's amount kept", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S) -- a nature schedule (3 s ticks)
        ctl.now = 13.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 8) -- the first tick: band [5, 20]; next at 16.7
        local i = ticket(X.TICKS)
        ctl.now = 16.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 8)
        assert.are.same({ 2, 10, 0 }, { T.done[i], T.tickAmt[i], T.bandRejected })
    end)

    it("credits our white crit to its swing by timing alone, its crit with it; teaches no lag", function()
        ctl.now = 5
        ctl.damage = { 40, 50, 0, 0 } -- a known UnitDamage: only the secret amount makes the class unknown
        ctl.Fire("PLAYER_REGEN_ENABLED")
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        local i = T.lastSwing[1]
        local med = L.med[1]
        ctl.now = 10.474 -- the core band
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 1)
        assert.are.same({ 1, 1, 0 }, { count(VS.Obs.Swing, 1), count(VS.Obs.Swing, 3), L.background })
        assert.are.equal(1, L.credited[1])
        assert.are.equal(med, L.med[1])
        assert.are_not.equal(T.OPEN, T.state[i])
        assert.are.same({ "SWING_DAMAGE", 0, true }, { got[#got][2], got[#got][12], got[#got][18] })
    end)

    it("holds our swing's DODGE provisionally by kind, as a plain one", function()
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        local i = T.lastSwing[1]
        ctl.now = 10.474
        ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, 1)
        assert.are.same({ T.PROV, "DODGE", 0 }, { T.state[i], T.avoid[i], L.background })
    end)

    it("counts a plain wound with a secret amount as background: it may be WOUND 0 (a replaced swing)", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.now = 10.01
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 4)
        ctl.now = 10.474
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 1)
        assert.are.same({ 0, 0, 2 }, { T.paid[X.FRAME], L.credited[1], L.background })
    end)

    it("counts a row with a secret flag or school as background, as before", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 10.01
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", S, S, 4)
        ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, S)
        assert.are.same({ 0, 2, 0 }, { T.paid[X.FRAME], L.background, count(VS.Obs.Avoided) })
    end)

    -- L607 / L629 / L972 option A (Fable decision 2026-11-14): live, our landed white swing's row is a WOUND whose amount
    -- alone is secret. An avoid in a cast's own frame the MELEE tie gave a swing in flight goes back to the cast when a
    -- secret white wound then lands where that swing's landing is expected (the test that gave it the avoid: its core
    -- band, or a first swing's whole window): the swing landed. The wound itself pays nothing (L505). Here: what Rows
    -- stages and emits (the cast's Obs.Avoided at its anchor, its SPELL_MISSED, the swing's close); the undo and refund
    -- it runs: tests/Game/State/now_spec.lua.
    describe("a tied avoid given back by the swing's secret wound", function()
        local HK

        local function settle(t)
            ctl.Tick(t)
        end

        -- the staged Obs.Avoided's { ability, anchor, kind }, or nil
        local function avoidedAt()
            for _, s in ipairs(staged) do
                if s[1] == VS.Obs.Avoided then
                    return { s[4], s[2], s[3] }
                end
            end
        end

        local function cast5()
            return { I.ab.bySpell[fs.SPENDER_C], 5, HK.DODGE }
        end

        -- our main-hand swing at `at`, then spender_c at 5 and its own-frame secret DODGE, which the swing's band holds
        local function tie(at)
            ctl.now = at or 4.526 -- the main hand's landing lag is about 0.474 s
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            ctl.now = 5
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, 1)
            return i
        end

        local function wound(t)
            ctl.now = t
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 1)
        end

        local function missRow(id)
            for _, r in ipairs(got) do
                if r[2] == "SPELL_MISSED" and r[12] == id then
                    return r[15]
                end
            end
        end

        before_each(function()
            HK = I.HitKind
        end)

        it(
            "gives it back on the swing's wound in its core band: the cast's avoid, SPELL_MISSED, a no-row close",
            function()
                local i = tie()
                assert.are.same({ T.PROV, 0, 1 }, { T.state[i], count(VS.Obs.Avoided), L.tieHeld })
                wound(5.08) -- the swing's core band (0.474 +- 0.12), past the cast's own frame
                settle(5.1)
                assert.are.same({ 1, T.OPEN, "", 1 }, { count(VS.Obs.Avoided), T.state[i], T.avoid[i], L.tieBack })
                assert.are.same(cast5(), avoidedAt())
                assert.are.equal("DODGE", missRow(fs.SPENDER_C))
                assert.are.equal(1, L.background) -- the wound itself is still background: it pays nothing (L505)
                settle(6.2) -- past the swing's window
                assert.are.same({ 1, 0 }, { count(VS.Obs.SwingSettled, -1), count(VS.Obs.SwingSettled, HK.DODGE) })
            end
        )

        it("keeps the cast's own-frame avoid when the swing's secret wound came first (the reversed order)", function()
            ctl.now = 4.526
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            wound(4.95) -- in the swing's core band, before the cast
            ctl.now = 5
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, 1)
            settle(5.1)
            assert.are.same({ 1, T.OPEN, 1, 0 }, { count(VS.Obs.Avoided), T.state[i], L.tieBack, L.tieHeld })
            assert.are.same(cast5(), avoidedAt())
            assert.are.equal("DODGE", missRow(fs.SPENDER_C))
            settle(6.2)
            assert.are.same({ 1, 0 }, { count(VS.Obs.SwingSettled, -1), count(VS.Obs.SwingSettled, HK.DODGE) })
        end)

        it("keeps the tie with no wound: the debuff stays, the swing closes on its avoid", function()
            local i = tie()
            settle(6.2)
            assert.are.same({ 0, 1, 0 }, { count(VS.Obs.Avoided), count(VS.Obs.SwingSettled, HK.DODGE), L.tieBack })
            assert.is_nil(missRow(fs.SPENDER_C))
            assert.are_not.equal(T.OPEN, T.state[i])
        end)

        it("keeps the tie and drops the hold on a wound in the tied cast's own frame (the cast landed)", function()
            tie()
            wound(5.02) -- the cast's own frame: its hit
            wound(5.08) -- then a white wound in the swing's band: the hold is gone
            settle(6.2)
            assert.are.same({ 0, 0, 1 }, { count(VS.Obs.Avoided), L.tieBack, count(VS.Obs.SwingSettled, HK.DODGE) })
        end)

        it("gives nothing back for a wound both our hands' swings explain (dual wield)", function()
            ctl.now = 4.377
            ctl.Fire("PLAYER_SWING", 2.6, 1) -- the off hand: its core band (0.703 +- 0.04) holds 5.08 too
            tie()
            assert.are.equal(1, L.tieHeld)
            wound(5.08)
            settle(6.2)
            assert.are.same({ 0, 0 }, { count(VS.Obs.Avoided), L.tieBack })
        end)

        it("gives nothing back for a wound in a due tick band of our own physical schedule", function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-0", fs.SPENDER_S) -- first tick due 13.375 +- 0.475
            T.school[ticket(X.TICKS)] = 1 -- a bleed's (the fixture's schedule is nature)
            ctl.now = 12.926
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 13.4
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, 1)
            assert.are.equal(1, L.tieHeld)
            wound(13.48) -- the swing's core band and the tick's band
            settle(15)
            assert.are.same({ 0, 0 }, { count(VS.Obs.Avoided), L.tieBack })
        end)

        -- live, a non-crit tick's row is secret too, so no tick is paid and the schedule's own `done` never moves: the
        -- due tick is found by the schedule's phase at t
        it("gives nothing back for a wound at a later tick of our physical schedule, no tick paid", function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-0", fs.SPENDER_S) -- ticks due 13.375, 16.375, ...
            T.school[ticket(X.TICKS)] = 1
            ctl.now = 15.85
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 16.32
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, 1)
            assert.are.equal(1, L.tieHeld)
            wound(16.40) -- the swing's core band and the second tick's band
            settle(18)
            assert.are.same({ 0, 0 }, { count(VS.Obs.Avoided), L.tieBack })
        end)

        it("gives nothing back once the tied cast was paid (its crit landed in its own frame)", function()
            tie()
            ctl.now = 5.01
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 1) -- the cast's own crit: it landed
            wound(5.08)
            settle(6.2)
            assert.are.same({ 0, 0 }, { count(VS.Obs.Avoided), L.tieBack })
            assert.is_nil(missRow(fs.SPENDER_C))
        end)

        it("tests a first swing's landing by its whole window, the cast's ticket closed by then", function()
            ctl.now = 4.52
            ctl.Fire("PLAYER_ENTER_COMBAT")
            ctl.now = 4.526
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            assert.is_true(T.first[i])
            ctl.now = 5
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, 1)
            ctl.Tick(5.66) -- the cast's landing window (0.474 + 3 x 0.06) is over: its ticket closed
            assert.is_nil(ticket(X.FRAME))
            wound(5.7) -- 1.17 s after the first swing: past its core band, inside its window
            settle(5.8)
            assert.are.same({ 1, 1, T.OPEN }, { count(VS.Obs.Avoided), L.tieBack, T.state[i] })
            assert.are.same(cast5(), avoidedAt())
            assert.are.equal("DODGE", missRow(fs.SPENDER_C))
        end)

        it("gives nothing back on a later swing's wound past its core band", function()
            tie()
            wound(5.7) -- 1.17 s after a swing that is not the first: outside its landing test
            settle(6.2)
            assert.are.same({ 0, 0 }, { count(VS.Obs.Avoided), L.tieBack })
        end)

        it("leaves a plain-amount client unchanged: a wound outside the amount classes gives nothing back", function()
            ctl.damage = { 40, 50, 0, 0 }
            ctl.now = 3
            ctl.Fire("PLAYER_REGEN_ENABLED") -- UnitDamage read: the amount classes known
            ctl.now = 4.526
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 5
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            ctl.now = 5.08
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 900, 1) -- no amount class of ours: not the swing's own
            settle(6.2)
            assert.are.same({ 0, 0 }, { count(VS.Obs.Avoided), L.tieBack })
        end)

        it("gives nothing back with the internal switch off (I.tieWoundOff)", function()
            I.tieWoundOff = true
            tie()
            wound(5.08)
            settle(6.2)
            I.tieWoundOff = nil
            assert.are.same({ 0, 0 }, { count(VS.Obs.Avoided), L.tieBack })
        end)

        it("allocates nothing holding, giving back and dropping tied avoids", function()
            I.Sources.Stage = stage
            cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            local t0 = 10
            assert.are.equal(
                0,
                alloc.bytes(function()
                    t0 = t0 + 5
                    ctl.now = t0
                    ctl.Fire("PLAYER_SWING", 2.6, 0)
                    ctl.now = t0 + 0.474
                    ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
                    ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, 1)
                    ctl.now = t0 + 0.554
                    ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 1)
                    ctl.Tick(t0 + 2)
                    I.Sources.Flush()
                end, 200)
            )
        end)
    end)

    it("allocates nothing routing a secret avoid and a secret crit", function()
        I.Sources.Stage = stage
        cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- the spec's own recorder allocates
        ctl.now = 10
        assert.are.equal(
            0,
            alloc.bytes(function()
                ctl.now = ctl.now + 5
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
                ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", S, 1)
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_F)
                ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 4)
                I.Sources.Flush()
            end, 200)
        )
    end)
end)
