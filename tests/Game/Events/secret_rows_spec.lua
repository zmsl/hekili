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

    -- (ledger L1442) Live, every plain tick's amount is secret, so no tick is paid: the band follows the owed tick
    -- nearest the row by elapsed time, not the first unseen one. The two shapes above with the old schedule's rows
    -- all secret, an instant's schedule anchored at its cast: its second tick at 16 is still in band, so the recast's
    -- or the other ability's direct crit there is ambiguous.
    it("keeps a schedule's later ticks in band though its earlier rows were secret (17.33, all secret)", function()
        local m = I.ab.bySpell[fs.SPENDER_M]
        I.ab.onCrit[m] = function() end
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
        ctl.now = 10.002
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 64)
        ctl.now = 13
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 64)
        ctl.now = 15.998
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_M)
        local landed, divergent = count(VS.Obs.Landed), T.divergent
        ctl.now = 16
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 64)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 64)
        ctl.now = 40
        I.Sources.Flush()
        assert.are.same({ 0, 1, 1 }, { count(VS.Obs.Crit), count(VS.Obs.Landed) - landed, T.divergent - divergent })
    end)

    it(
        "keeps another ability's later ticks in band though its earlier rows were secret (an instant anchored at its cast)",
        function()
            local m, f = I.ab.bySpell[fs.SPENDER_M], I.ab.bySpell[fs.SPENDER_F]
            I.ab.onCrit[f], I.ab.school[f] = function() end, I.ab.school[m]
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            ctl.now = 10.002
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 64)
            ctl.now = 13
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 64)
            ctl.now = 15.998
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_F)
            local landed, divergent = count(VS.Obs.Landed), T.divergent
            ctl.now = 16
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 64)
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 64)
            ctl.now = 40
            I.Sources.Flush()
            assert.are.same({ 0, 0, 1 }, { count(VS.Obs.Crit), count(VS.Obs.Landed) - landed, T.divergent - divergent })
        end
    )

    -- Two travelling spells of one school, the ticking one's schedule composed at its success (ledger L1503, the
    -- e4ef Fire log's shapes, its times): the flight's lag already learned.
    local function flights()
        local p, f = I.ab.bySpell[fs.SPENDER_P], I.ab.bySpell[fs.SPENDER_F]
        I.ab.onCrit[p], I.ab.rMax[p] = function() end, 30
        I.ab.onCrit[f], I.ab.school[f], I.ab.rMax[f] = function() end, I.ab.school[p], 30
        I.ab.expKind[f], I.ab.velocity[f] = X.FLIGHT, I.ab.velocity[p]
        ctl.now = 1
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-0", fs.SPENDER_P)
        ctl.now = 1.83 -- a clean hit: the lag learned (0.83 s)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 40, 8)
        I.ab.ticking[p], I.ab.tickAura[p] = true, { tick_time = 3, duration = 12 }
    end

    -- e4ef 17.33: the old schedule anchored by its own direct crit (8.33), its ticks at 11.33 and 14.33 unseen; the
    -- recast's direct crit at 17.33 meets the old schedule's slot 3: ambiguous, no crit credited, the recast landed.
    it("leaves a recast's direct crit on an anchored flight schedule's later tick ambiguous (17.33)", function()
        flights()
        ctl.now = 7.5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        local i = ticket(X.TICKS)
        ctl.now = 8.33
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 8)
        assert.are.same({ 8.33, 0 }, { T.anchor[i], T.wide[i] })
        ctl.now = 11.33
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 8)
        ctl.now = 14.33
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 8)
        local crits = count(VS.Obs.Crit)
        assert.are.equal(1, crits) -- the 8.33 direct crit's own
        ctl.now = 16.5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_P)
        local divergent, paid = T.divergent, T.paid[X.FLIGHT]
        ctl.now = 17.33
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 8)
        ctl.now = 40
        I.Sources.Flush()
        assert.are.same({ 0, 1, 1 }, { count(VS.Obs.Crit) - crits, T.divergent - divergent, T.paid[X.FLIGHT] - paid })
    end)

    -- KNOWN RESIDUAL (review D1, e4ef secret arm 1139.83 = log 98.33): the old schedule's direct row (89.33) was a
    -- plain hit, unseen, so its schedule never anchors (wide > 0) and only its first tick is in band. Its slot-3 crit
    -- at 98.33 goes to the other spell's open flight (cast 97.00, its own row at 97.83 unseen): a false crit credit.
    -- Pinned as today's behaviour; D1 (compose a flight's schedule from the learned lag) turns it red.
    it("credits an unanchored schedule's later tick crit to another open flight (known residual, D1)", function()
        flights()
        ctl.now = 88.5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        local i = ticket(X.TICKS)
        for _, t in ipairs({ 89.33, 92.33, 95.33 }) do
            ctl.now = t
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 8)
        end
        assert.is_true(T.wide[i] > 0)
        ctl.now = 97
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_F)
        ctl.now = 97.83
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 8)
        local divergent = T.divergent
        assert.is_true(T.state[i] >= T.OPEN) -- the old schedule still open, unanchored
        ctl.now = 98.33
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 8)
        ctl.now = 120
        I.Sources.Flush()
        assert.are.same({ 1, 0 }, { count(VS.Obs.Crit), T.divergent - divergent })
    end)

    -- A paid tick past unseen ones pays its own index: the schedule's next band is the tick after it, so a second row
    -- in the same instant is not that tick again (one row per tick).
    it("pays a later tick by its index past unseen ones: done jumps, the count kept", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S) -- a nature schedule (3 s ticks)
        ctl.now = 13.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 8) -- the first tick: the schedule snaps (anchor 10.7)
        local i = ticket(X.TICKS)
        local total = T.done[i] + T.owed[i]
        ctl.now = 16.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 8) -- tick 2 secret: background
        ctl.now = 19.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 8) -- tick 3, a crit
        assert.are.same({ 3, total }, { T.done[i], T.done[i] + T.owed[i] })
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 8) -- the same instant again: not tick 3 twice
        assert.are.equal(3, T.done[i])
    end)

    -- A plain row keeps the next owed tick (decision 47): with amounts plain a missing tick is truly missing (taken by
    -- another ticket, or a first row that was not ours snapped the schedule off phase: the detect sweep's mixed seed 1,
    -- a partner's lockstep rows), so a later slot's row is not taken.
    it("keeps a plain row's band on the next owed tick past a missing one", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S)
        ctl.now = 13.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 8) -- tick 1 (anchor 10.7); tick 2 at 16.7 never comes
        local i = ticket(X.TICKS)
        ctl.now = 19.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 8)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 20, 8)
        assert.are.same({ 1, 0 }, { T.done[i], T.bandRejected })
    end)

    -- A recast (its direct row secret, so nothing refreshed the old schedule) at the old one's first tick: a crit in
    -- that instant may be the old tick (it pays it: done 1), and that first paid tick confirms the old application over
    -- older ones only, so the newer schedule stays open.
    local function recast()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
        local old = ticket(X.TICKS)
        ctl.now = 13
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_M)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", S, 64)
        local new
        for j = 1, T.CAP do
            if j ~= old and T.state[j] ~= T.FREE and T.kind[j] == X.TICKS then
                new = j
            end
        end
        return old, new
    end

    it("closes no newer schedule of the ability when an older one pays its first tick", function()
        local old, new = recast()
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 64)
        assert.are.same({ 1, true }, { T.done[old], T.state[new] >= T.OPEN })
    end)

    -- A secret row's tick past its schedule's next owed one ranks last (T.Pick): it makes the row ambiguous but takes
    -- it from no other candidate. The newer schedule's tick, in phase with the old schedule's slot 2, is the newer one's.
    it("gives an old schedule's later slot no row another candidate holds: the newer schedule's tick", function()
        local old, new = recast()
        ctl.now = 16
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 64)
        assert.are.same({ 0, 1 }, { T.done[old], T.done[new] })
    end)

    -- (detect sweep K19, secret arm) A recast on the old schedule's last slot: the crit in that instant goes to the
    -- recast's direct ticket, as before (the old tick only makes it ambiguous: divergent counted).
    it("pays a recast's direct crit to its cast, not the old schedule's later slot in the same instant", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
        local old = ticket(X.TICKS)
        ctl.now = 22 -- the old schedule's slot 4 (13, 16, 19 secret, unseen)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_M)
        local paid = T.paid[X.FRAME]
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", S, 64)
        assert.are.same({ 0, 1 }, { T.done[old], T.paid[X.FRAME] - paid })
    end)

    -- While a flight's schedule has no anchor (its direct row unseen, wide > 0) its band stays on its next owed tick:
    -- by elapsed time its overlapping bands would hold nearly every row of its school.
    it("keeps an unanchored flight schedule's band on its next owed tick", function()
        local p = I.ab.bySpell[fs.SPENDER_P]
        I.ab.rMax[p], I.ab.ticking[p], I.ab.tickAura[p] = 30, true, { tick_time = 2, duration = 8 }
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        local i = ticket(X.TICKS)
        assert.are.same(
            { 1, 1, 1 },
            { I.Kinds.TickN(i, 12, true), I.Kinds.TickN(i, 16, true), I.Kinds.TickN(i, 18, true) }
        )
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
