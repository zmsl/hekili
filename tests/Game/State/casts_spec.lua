-- tests/Game/State/casts_spec.lua: cooldowns, charges and the GCD (spec §6.2, §7.5). Golden scenario 3 (TDF
-- tests/model/belief_spec.lua:401): cooldowns snap to the game's ready flags.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("casts and cooldowns", function()
    local VS, I, S, Obs, api, ctl, h
    local REND = 3

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        h = fs.new(9)
        h.Class.abilities.spender_c.cooldown = 30
        I.Build(fs.def(h), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    it("snaps cooldowns to the game's ready flags", function()
        I.CooldownModel(REND, 40, 30, 10, Obs.CastSuccess) -- 30 s cooldown in the model
        S.Direct(Obs.Cooldown, 20, REND, 1) -- but the game says it's ready (something reset it)
        I.Fold(20, false)
        I.Settle(20)
        assert.are.equal(20, VS.Cooldown(fs.SPENDER_C, 20).est)
        assert.are.equal("pinned", VS.Cooldown(fs.SPENDER_C, 20).basis)
        S.Direct(Obs.Cooldown, 21, REND, 0) -- and now it isn't, while the model thinks it is
        I.Fold(21, false)
        I.Settle(21)
        assert.are.equal(21 + I.CD_PROBE, VS.Cooldown(fs.SPENDER_C, 21).est)
        assert.are.equal(VS.Cooldown(fs.SPENDER_C_R2, 21), VS.Cooldown(fs.SPENDER_C, 21)) -- every rank ID is the ability
        assert.is_nil(VS.Cooldown(424242, 21))
    end)

    it("learns the real length from the ready edge after our cast", function()
        assert.are.equal(30, VS.CooldownLength(fs.SPENDER_C)) -- the spec's cooldown first
        I.CooldownModel(REND, 40, 30, 10, Obs.CastSuccess)
        S.Direct(Obs.Cooldown, 10.1, REND, 0)
        S.Direct(Obs.Cooldown, 38, REND, 1)
        I.Fold(38, false)
        assert.are.equal(28, VS.CooldownLength(fs.SPENDER_C)) -- within max(1 s, 10%) of the registered 30
    end)

    it("keeps the registered length when the ready edge is out of tolerance", function()
        I.CooldownModel(REND, 40, 30, 10, Obs.CastSuccess)
        S.Direct(Obs.Cooldown, 10.1, REND, 0)
        S.Direct(Obs.Cooldown, 154, REND, 1) -- a flag that also tracks a kill window: 144 s
        I.Fold(154, false)
        assert.are.equal(30, VS.CooldownLength(fs.SPENDER_C))
    end)

    it("learns a GCD only from a falling edge within [1.0, 1.51) s", function()
        -- a spell-kind cast opens each one (an ownerless GCD teaches nothing), so the window alone rejects
        for _, e in ipairs({ { 100, 101.4 }, { 110, 114.38 }, { 120, 122 }, { 130, 131.85 } }) do -- chained GCDs merge into one edge
            S.Direct(Obs.CastSuccess, e[1], REND)
            S.Direct(Obs.Cooldown, e[1], 0, 1, 1)
            I.Fold(e[1], false)
            assert.are.equal(REND, I.gcdOwner)
            S.Direct(Obs.Cooldown, e[2], 0, 0, 1) -- 122: two chained 1.0 s GCDs; 131.85: a fall seen late
        end
        I.Fold(132, false)
        assert.is_true(math.abs(I.gcdLearned[1] - 1.4) < 0.002) -- the earlier, plausible one stands
    end)

    it("names an ability with a second power cost in Snapshot", function()
        I.ab.multiCost[REND] = true
        local line = "ability spender_c qid=1003 cost=10 read=0 len=30.00 flag=-1 multi=true\n"
        assert.is_truthy(VS.Snapshot():find(line, 1, true))
    end)

    it("logs a Cooldown only on a plain flag edge, and the GCD's edges, on the urgent lane", function()
        h.forced = {}
        I.urgent = function(e)
            h.forced[#h.forced + 1] = e
        end
        ctl.cooldown[fs.SPENDER_C] = { isActive = true, isOnGCD = false }
        ctl.cooldown[29515] = { isActive = true, isOnGCD = false }
        ctl.now = 5
        ctl.Fire("SPELL_UPDATE_COOLDOWN")
        ctl.Fire("SPELL_UPDATE_COOLDOWN")
        ctl.Tick(5)
        local n = 0
        for i = 1, I.log.n do
            if I.ObsLog.At(I.log, i).kind == Obs.Cooldown then
                n = n + 1
            end
        end
        assert.are.equal(4, n) -- shout, strike ready; spender_c not; the GCD up (a second event repeats nothing)
        assert.are.same({ "VS_COOLDOWN" }, h.forced)
        ctl.cooldown[fs.SPENDER_C] = { isActive = fake.SECRET, isOnGCD = false }
        ctl.Fire("SPELL_UPDATE_COOLDOWN") -- a secret flag is no news
        assert.are.equal(4, n + I.Sources.stN)
    end)

    it(
        "fixes the GCD's start and duration at the rising edge, quantised so they survive Hekili's round trip",
        function()
            S.Direct(Obs.CastSuccess, 1000.1, REND)
            S.Direct(Obs.Cooldown, 1000.123456, 0, 1, 1)
            I.Fold(1000.2, false)
            local s, d = VS.GcdInfo(1000.2)
            assert.are.equal(s, (s + d) - d)
            assert.are.equal(s * 1024, math.floor(s * 1024))
            assert.are.same({ s, d }, { VS.GcdInfo(1000.9) }) -- unchanged between edges
            S.Direct(Obs.Cooldown, 1001.6, 0, 0, 1)
            I.Fold(1001.6, false)
            assert.are.same({ 0, 0 }, { VS.GcdInfo(1001.6) })
            assert.is_true(math.abs(I.gcdLearned[1] - 1.477) < 0.002) -- learned from the falling edge
            for _ = 1, 2000 do
                local t = math.random() * 1e6
                local q = I.Quantise(t)
                local dq = I.Quantise(1.5 * math.random())
                assert.are.equal(q, (q + dq) - dq)
            end
        end
    )

    it("evaluates a function cost (a talent that lowers it) and uses it for the ladder", function()
        local rank = 2
        h.Class.abilities.spender_b.spend = function()
            return 15 - rank -- Improved spender_b: -1 a rank
        end
        assert.are.equal(13, I.CostOf(2))
        rank = 3
        assert.are.equal(12, I.CostOf(2))
        assert.are.equal(10, I.CostOf(3)) -- a number cost
    end)

    it("FAILED with another castGUID changes nothing", function()
        h.forced = {}
        I.urgent = function(e)
            h.forced[#h.forced + 1] = e
        end
        ctl.casting = { 2000, 4000 }
        ctl.now = 2
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-A", fs.SPENDER_C)
        S.Flush()
        I.Fold(2, false)
        assert.are.equal(REND, I.castAb)
        local n, forced = I.log.n + S.stN, #h.forced
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-B", fs.SPENDER_C) -- a second press: "another action..."
        S.Flush()
        I.Fold(2.5, false)
        assert.are.equal(REND, I.castAb)
        assert.are.equal(n, I.log.n + S.stN)
        assert.are.equal(forced, #h.forced)
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-A", fs.SPENDER_C) -- the cast in progress
        S.Flush()
        I.Fold(3, false)
        assert.are.equal(0, I.castAb)
    end)

    it("models charges and recharges them by time; a spell without charges has none", function()
        assert.is_nil(VS.Charges(fs.SPENDER_C, 1))
    end)
end)

-- The GCD by kind (GCD kinds design §1.2): its length from the ability that opened it, an opener on either side of the
-- rising edge, learning per kind, and the read guard that keeps GcdInfo's numbers fixed between edges (spec §7.5).
describe("the GCD by kind", function()
    local VS, I, S, Obs, api, ctl
    local SPELL, OFF, TOTEM, FIXED = 3, 2, 4, 5 -- spender_c, spender_b (off the GCD), spender_t, spender_u (0.8 s)

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        I.Build(fs.def(fs.new(9, true)), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    local function success(a, t)
        S.Direct(Obs.CastSuccess, t, a)
    end
    local function edge(t, up)
        S.Direct(Obs.Cooldown, t, 0, up and 1 or 0, 1)
    end
    local function info(t)
        I.Fold(t, false)
        return { VS.GcdInfo(t) }
    end
    local function near(want, got)
        assert.is_true(math.abs(want - got) < 0.002, tostring(got))
    end

    it("opens a totem-kind GCD of 1.0 s with the success after the edge and before it (same t)", function()
        edge(10, true)
        success(TOTEM, 10) -- the edge first: the success claims it (provisional: the spell kind's 1.5)
        assert.are.same({ 10, 1 }, info(10.05))
        assert.are.equal(TOTEM, I.gcdOwner)
        edge(11, false)
        success(TOTEM, 20) -- the success first
        edge(20, true)
        assert.are.same({ 20, 1 }, info(20.05))
        assert.are.equal(TOTEM, I.gcdOwner)
        edge(21, false)
        edge(30.65, true) -- off the 2^-10 grid: the quantised start (30.650390625) is later than the edge
        success(TOTEM, 30.65)
        assert.are.same({ I.Quantise(30.65), 1 }, info(30.7))
        assert.are.equal(TOTEM, I.gcdOwner)
    end)

    it("opens a spell-kind GCD of 1.5 / spell haste, never melee haste (melee 1.3: 1.5; spell 20%: 1.25)", function()
        S.Direct(Obs.Haste, 9, 0, 1.3, 1) -- melee (Flurry): attack speed only
        success(SPELL, 10)
        edge(10.03, true)
        near(1.5, info(10.1)[2])
        assert.are.equal(SPELL, I.gcdOwner)
        S.Direct(Obs.Haste, 19, 0, 20, 2) -- UnitSpellHaste 20 %
        success(SPELL, 20)
        near(1.25, info(20.1)[2])
        S.Direct(Obs.Haste, 29, 0, 100, 2) -- floored at 1.0
        success(SPELL, 30)
        near(1.0, info(30.1)[2])
    end)

    it("lets a hard cast in progress own the edge at its start, after a totem-kind GCD", function()
        success(TOTEM, 5)
        edge(5, true)
        edge(6, false)
        S.Direct(Obs.CastStart, 10, SPELL, 11.5)
        edge(10.02, true)
        near(1.5, info(10.1)[2])
        assert.are.equal(SPELL, I.gcdOwner)
    end)

    it("lets a declared gcdTime (0.8) win, and never learns from it", function()
        success(FIXED, 10)
        edge(10, true)
        near(0.8, info(10.1)[2])
        edge(11.3, false) -- inside the spell window: only the gcdTime guard keeps it from teaching
        I.Fold(11.4, false)
        assert.are.same({ 0, 0 }, I.gcdLearned)
    end)

    it("learns per kind: a totem GCD falling at +1.02 and a spell GCD at +1.43 set the next of each kind", function()
        success(TOTEM, 10)
        edge(10, true)
        edge(11.02, false)
        success(SPELL, 20)
        edge(20, true)
        edge(21.43, false)
        success(TOTEM, 30)
        edge(30, true)
        near(1.02, info(30.1)[2])
        edge(31.02, false)
        success(SPELL, 40)
        edge(40, true)
        near(1.43, info(40.1)[2])
        assert.is_truthy(VS.Snapshot():find("learned=1.4297/1.0195 owner=spender_c", 1, true))
    end)

    it("takes the last opener's kind for an ownerless edge, and learns nothing from it", function()
        success(TOTEM, 10)
        edge(10, true)
        edge(11, false)
        edge(20, true) -- no cast near it
        assert.are.same({ 20, 1 }, info(20.1))
        assert.are.equal(0, I.gcdOwner)
        edge(21.1, false) -- inside the totem window: only the missing owner keeps it from teaching
        I.Fold(21.5, false)
        assert.are.same({ 0, 1 }, I.gcdLearned)
    end)

    it(
        "keeps the duration after GcdInfo's first answer when the opener's success comes later, and still learns its kind",
        function()
            edge(10, true)
            assert.are.same({ 10, 1.5 }, info(10.01)) -- read: the provisional spell kind's
            success(TOTEM, 10.05)
            assert.are.same({ 10, 1.5 }, info(10.1)) -- unchanged between edges
            assert.are.equal(TOTEM, I.gcdOwner)
            edge(11.03, false)
            I.Fold(11.1, false)
            near(1.03, I.gcdLearned[2])
        end
    )

    it("never lets a pending success later than the edge by more than GCD_EDGE open it", function()
        success(SPELL, 10.5) -- logged ahead of the edge (an out-of-order log)
        edge(10, true)
        info(10.6)
        assert.are.equal(0, I.gcdOwner)
    end)

    it("pins the GCD at an on-GCD success that no rising edge follows (in game: rend, then overpower; here a totem press)", function()
        success(SPELL, 10) -- rend: its success and rising edge
        edge(10, true)
        assert.are.same({ 10, 1.5 }, info(10.1))
        -- its GCD ends with no SPELL_UPDATE_COOLDOWN, so the flag stays up and the next press shows no edge
        success(TOTEM, 12.1)
        assert.are.same({ I.Quantise(12.1), 1 }, info(12.5))
        assert.are.equal(TOTEM, I.gcdOwner)
        assert.are.same({ 0, 0 }, info(13.2)) -- over at its own length
    end)

    it("re-fixes a success-pinned GCD at a rising edge within GCD_EDGE after it", function()
        success(TOTEM, 10)
        assert.are.same({ 10, 1 }, info(10.01)) -- pinned at the success before the edge
        edge(10.05, true)
        assert.are.same({ I.Quantise(10.05), 1 }, info(10.1))
        assert.are.equal(TOTEM, I.gcdOwner)
        edge(11.05, false)
        I.Fold(11.1, false)
        near(1.0, I.gcdLearned[2])
    end)

    it("never lets an off-GCD success inside the window open the GCD", function()
        success(OFF, 10)
        edge(10.02, true)
        success(OFF, 10.05)
        info(10.1)
        assert.are.equal(0, I.gcdOwner)
    end)

    it("rejects a totem-kind fall of 2.0 s (two chained GCDs) and of 0.85 s", function()
        success(TOTEM, 10)
        edge(10, true)
        edge(12, false)
        success(TOTEM, 20)
        edge(20, true)
        edge(20.85, false)
        I.Fold(21, false)
        assert.are.same({ 0, 0 }, I.gcdLearned)
    end)
end)
