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

    -- An ability's `onCrit` is a direct hit's (wowsims's crit procs never fire on a periodic tick), as `landed` is: a
    -- schedule's or a channel's tick crit stages no Obs.Crit, paid at its row or final; a direct crit still does.
    it("stages no Obs.Crit for a schedule's tick crit, plain or secret; a direct crit still stages it", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S)
        ctl.now = 13.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 8)
        local i = ticket(X.TICKS)
        ctl.now = 16.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 20, 8)
        ctl.now = 19.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 8)
        assert.are.same({ 3, 0 }, { T.done[i], count(VS.Obs.Crit) })
        ctl.now = 40
        I.Sources.Flush()
        assert.are.equal(0, count(VS.Obs.Crit))
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_F)
        ctl.now = 40.01
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 4)
        assert.are.equal(1, count(VS.Obs.Crit))
    end)

    -- (ledger L1415 as reworded L1418) A crit row in band for a recast's direct hit and the old schedule's tick of the
    -- same ability, in the same instant and school, may be either: one runs the `onCrit`, the other nothing. It credits
    -- no crit (an under-credit is a briefly late spell, an over-credit an unaffordable one shown); the direct cast still
    -- landed either way.
    it("stages no Obs.Crit for a crit ambiguous between a recast's direct hit and the old tick; still lands", function()
        local m = I.ab.bySpell[fs.SPENDER_M]
        I.ab.onCrit[m] = function() end
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
        ctl.now = 10.002
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 9, 64)
        ctl.now = 13
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 4, 64)
        ctl.now = 15.998
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_M)
        local landed, divergent = count(VS.Obs.Landed), T.divergent
        ctl.now = 16 -- the old schedule's second tick and the recast's direct hit, one a crit
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 64)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 64)
        ctl.now = 40
        I.Sources.Flush()
        assert.are.same({ 0, 1, 1 }, { count(VS.Obs.Crit), count(VS.Obs.Landed) - landed, T.divergent - divergent })
    end)

    -- Another ability's tick in band makes a direct crit ambiguous (a Fire spell's crit beside a Fire DoT's tick): two
    -- abilities of one school, one ticking, the other's direct crit. No Obs.Crit and no landing (it may be the tick's); divergent counted.
    it("stages no Obs.Crit for a direct crit beside another ability's tick of the same school", function()
        local m, f = I.ab.bySpell[fs.SPENDER_M], I.ab.bySpell[fs.SPENDER_F]
        I.ab.onCrit[f], I.ab.school[f] = function() end, I.ab.school[m]
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
        ctl.now = 10.002
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 9, 64)
        ctl.now = 13
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 4, 64)
        ctl.now = 15.998
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_F)
        local landed, divergent = count(VS.Obs.Landed), T.divergent
        ctl.now = 16 -- the ticking ability's third tick and the other's direct hit, a crit
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 64)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 64)
        ctl.now = 40
        I.Sources.Flush()
        assert.are.same({ 0, 0, 1 }, { count(VS.Obs.Crit), count(VS.Obs.Landed) - landed, T.divergent - divergent })
    end)

    -- A projectile's own schedule (composed at its success, widened by the flight until its direct row) is no rival
    -- for that direct row: its debuff, and so its ticks, start there.
    it("stages a travelling cast's own direct crit though its own composed schedule is in band", function()
        local p = I.ab.bySpell[fs.SPENDER_P]
        I.ab.onCrit[p], I.ab.rMax[p] = function() end, 30
        ctl.now = 1
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-0", fs.SPENDER_P)
        ctl.now = 1.8 -- a clean hit: the flight's lag learned (0.8 s), its band now narrow around it
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 40, 8)
        I.ab.ticking[p], I.ab.tickAura[p] = true, { tick_time = 2, duration = 8 }
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        assert.is_truthy(ticket(X.TICKS)) -- its band 10 + 2 -+ (0.1 + the flight's hard window) holds 10.8
        ctl.now = 10.8
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 8)
        ctl.now = 40
        I.Sources.Flush()
        assert.are.same({ 1, 0 }, { count(VS.Obs.Crit), T.divergent })
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
