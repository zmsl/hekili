-- tests/Game/State/reactions_spec.lua (re-pin design §3a "Reactions", decision 11; plan Task 8a): RegisterReaction's
-- `now` functions, run by a settled outcome in the `now` context (Families/Now.lua) at the outcome row's time, never
-- by the cast fold. Incoming (victim-side UNIT_COMBAT), our casts (paySpell, T.onFinal), our white swings (T.onExpire
-- while the provisional avoid is held). The registration's load checks: tests/Forever/windows_spec.lua.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

describe("reactions", function()
    local api, ctl, ns, VS, I, T, X, h, saved, runs

    -- the record Spec.lua's RegisterReaction stores (Engine/Schema/Spec.lua); each counts its runs in runs[key] and
    -- opens the window of its own name
    local function reaction(key, who, outcome)
        runs[key] = 0
        return {
            key = key,
            who = who,
            outcome = outcome,
            now = function()
                runs[key] = runs[key] + 1
                openWindow(key)
            end,
        }
    end

    local function window(key, t)
        t = t or {}
        t.key, t.duration, t.on_deviation = key, t.duration or 6, t.on_deviation or "stay"
        return t
    end

    -- the tracked set (fs.def, as tickets_spec) with reactions and their windows, one per reaction name
    local function build(reactions, windows)
        local def = fs.def(h)
        def.reactions, def.windows = reactions, windows or {}
        for _, r in ipairs(reactions) do
            def.windows[#def.windows + 1] = window(r.key)
        end
        I.Build(def, 1)
        I.nowErrors = 0 -- the fixture's malformed spender_q (`expects = "bogus"`) counts one at the build
        VS.Start(api)
        I.ObsLog.Clear(I.log)
    end

    local function W(name)
        return { ns.Facade.Window(name) }
    end

    local function drain(t)
        ctl.Tick(t)
        VS.Drain(t)
    end

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        saved = {}
        for _, k in ipairs({ "GetTime", "UnitGUID", "CreateFrame", "issecretvalue", "debugprofilestop" }) do
            saved[k] = rawget(_G, k) or false
        end
        _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue =
            api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
        _G.debugprofilestop = function()
            return 0
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        T, X = I.Tickets, I.Expect
        h = fs.new(9, false, false, true)
        h.Class.abilities.spender_m.school = "physical"
        runs = {}
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    describe('who = "player" (victim-side UNIT_COMBAT)', function()
        it("a PARRY on us runs the parry reaction; its window counts from the row, folded 0.4 s later", function()
            build({ reaction("parried", "player", "parry"), reaction("dodged", "player", "dodge") })
            ctl.now = 5
            ctl.Fire("UNIT_COMBAT", "player", "PARRY", "", 0, 1)
            drain(5.4)
            assert.are.same({ 1, 0 }, { runs.parried, runs.dodged })
            assert.are.same({ true, 5, 11, 0, 0 }, W("parried"))
            assert.is_false(W("dodged")[1])
        end)

        it(
            "block covers BLOCK and BLOCKED; a CRITICAL wound runs the crit reaction; a plain wound runs none",
            function()
                build({ reaction("blocked", "player", "block"), reaction("critted", "player", "crit") })
                ctl.now = 5
                ctl.Fire("UNIT_COMBAT", "player", "BLOCK", "", 0, 1)
                ctl.Fire("UNIT_COMBAT", "player", "WOUND", "BLOCK_REDUCED", 40, 1)
                ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 40, 1)
                drain(5.1)
                assert.are.same({ 2, 0 }, { runs.blocked, runs.critted })
                ctl.now = 6
                ctl.Fire("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 80, 1)
                drain(6.1)
                assert.are.same({ 2, 1 }, { runs.blocked, runs.critted })
                assert.are.same({ true, 6, 12, 0, 0 }, W("critted"))
                assert.are.equal(0, I.nowErrors)
            end
        )
    end)

    describe('who = "target", our casts', function()
        it("a DODGE paid final to our cast's ticket runs the dodge reaction at the row", function()
            build({ reaction("dodged", "target", "dodge"), reaction("missed", "target", "miss") })
            ctl.now = 5
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            drain(5.4)
            assert.are.same({ 1, 0 }, { runs.dodged, runs.missed })
            assert.are.same({ true, 5, 11, 0, 0 }, W("dodged"))
        end)

        it("a crit paid final to our cast runs the target's crit reaction before the ability's onCrit", function()
            build({ reaction("critted", "target", "crit") })
            ctl.now = 5
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 100, 1)
            drain(5.1)
            assert.are.equal(1, runs.critted)
        end)

        it("a TENT avoid runs nothing until T.onFinal, then once, at the row's time", function()
            build({ reaction("missed", "target", "miss") })
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
            T.Learn("Creature-1", 20, 1.5, 9) -- narrow band [11.35, 11.65] for the 10 s cast
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
            ctl.now = 10.6 -- the widened band, before the narrow one: provisional
            ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 8)
            drain(10.7)
            assert.are.equal(1, T.nTent)
            assert.are.equal(0, runs.missed)
            drain(11.7) -- past the narrow band's end (11.65): final
            drain(11.8)
            assert.are.equal(1, runs.missed)
            assert.are.same({ true, 10.6, 16.6, 0, 0 }, W("missed"))
        end)

        it("a TENT crit displaced at T.onReplace never runs; the avoid that replaced it runs once", function()
            build({ reaction("critted", "target", "crit"), reaction("missed", "target", "miss") })
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
            T.Learn("Creature-1", 20, 1.5, 9)
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
            ctl.now = 10.6
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 8)
            drain(10.7)
            ctl.now = 11.5
            ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
            assert.are.same({ 1, 1 }, { T.replaced, T.foreign })
            drain(11.6)
            drain(14)
            assert.are.same({ 0, 1 }, { runs.critted, runs.missed })
            assert.are.equal(11.5, W("missed")[2])
        end)

        -- gap AS (tickets_spec's Rend 163.54 case): the MELEE tie first gives the dodge to the swing in flight, the
        -- swing's own wound gives it back to the cast through paySpell
        it(
            "an avoid the MELEE tie gave a swing and gap AS gave back runs the cast's reaction once, no swing's",
            function()
                build({ reaction("dodged", "target", "dodge") })
                ctl.now = 163.13
                ctl.Fire("PLAYER_SWING", 2.6, 0)
                local sw = T.lastSwing[1]
                ctl.now = 163.54
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
                ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
                assert.are.equal(T.PROV, T.state[sw]) -- MELEE wins the tie, for now
                drain(163.56)
                assert.are.equal(0, runs.dodged)
                ctl.now = 163.604
                ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
                drain(163.62)
                assert.are.equal(1, runs.dodged)
                assert.are.equal(163.54, W("dodged")[2])
                drain(166) -- every window closed: the swing's close holds no avoid
                drain(166.1)
                assert.are.equal(1, runs.dodged)
            end
        )
    end)

    describe('who = "target", our white swings', function()
        it("a swing's DODGE runs only at its window's close (T.onExpire), at the row's time", function()
            build({ reaction("dodged", "target", "dodge") })
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            ctl.now = 10.47 -- in the core band
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            drain(10.5)
            assert.are.same({ T.PROV, 0 }, { T.state[i], runs.dodged })
            drain(12) -- past the swing's window
            drain(12.1)
            assert.are.same({ 0, 1 }, { T.state[i], runs.dodged })
            assert.are.same({ true, 10.47, 16.47, 0, 0 }, W("dodged"))
        end)

        it("a held avoid stages nothing at T.onExpire unless its ticket is still provisional", function()
            build({ reaction("dodged", "target", "dodge") })
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            ctl.now = 10.47
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            drain(10.5)
            assert.are.equal(T.PROV, T.state[i])
            T.state[i] = T.TENT -- no longer provisional, its avoid field still set
            T.onExpire(i, 10.6)
            drain(10.7)
            assert.are.equal(0, runs.dodged)
        end)

        it("a swing's crit credited final runs the crit reaction once; a provisional one only at its final", function()
            build({ reaction("critted", "target", "crit") })
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 10.47 -- the core band: final at once
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 1)
            drain(10.5)
            assert.are.equal(1, runs.critted)
            ctl.now = 20
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            ctl.now = 20.2 -- before the core band: provisional (TENT)
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 1)
            drain(20.25)
            assert.are.same({ T.TENT, 1 }, { T.state[i], runs.critted })
            drain(22)
            drain(22.1)
            assert.are.equal(2, runs.critted)
            assert.are.equal(20.2, W("critted")[2])
        end)
    end)

    -- aura audit C3: outcome "land" (a white swing of ours that landed: a settled wound, or a swing that closed with no
    -- row at all, as live, where a non-crit hit's row is secret and only avoids are plain), optional hand
    describe('outcome "land" (who = "target")', function()
        it("runs at a settled wound and at a swing closing with no row; never at an avoid", function()
            build({ reaction("landed", "target", "land"), reaction("swung", "target", "swing") })
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 10.47 -- the core band: final at once
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            drain(10.5)
            assert.are.same({ 1, 1 }, { runs.landed, runs.swung })
            assert.are.equal(10, W("landed")[2]) -- at the swing's own time, not its row's (10.47)
            ctl.now = 20
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 20.47
            ctl.Fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1)
            drain(20.5)
            drain(22)
            drain(22.1)
            assert.are.same({ 1, 2 }, { runs.landed, runs.swung }) -- avoided: no land
            ctl.now = 30
            ctl.Fire("PLAYER_SWING", 2.6, 0) -- no row (live: its amount secret, the row background)
            drain(30.5)
            assert.are.equal(1, runs.landed)
            drain(32)
            drain(32.1)
            assert.are.same({ 2, 2 }, { runs.landed, runs.swung }) -- landed, presumed; "swing" still needs a row
            assert.are.equal(30, W("landed")[2]) -- at the swing's own time
            assert.are.equal(0, I.nowErrors)
        end)

        -- A landed swing's effects follow the auras up when it swung: a buff applied between the swing and its row
        -- (0.47 s later) reads down, one that fell in between reads up with the stacks it had.
        it("reads the auras as of the swing's time, not its row's", function()
            local seen = {}
            local r = reaction("landed", "target", "land")
            r.now = function()
                seen[#seen + 1] = { now, buff.spender_a.up, buff.spender_c.up, buff.spender_c.stack }
                addStack("spender_c")
            end
            build({ r })
            local A, C, cast = I.auras.bySpell[fs.SPENDER_A], I.auras.bySpell[fs.SPENDER_C], VS.Obs.CastSuccess
            I.AuraModel(1, C, 5, 25, 2, 5, cast)
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            drain(10.1)
            I.AuraModel(1, A, 10.2, 130, 1, 10.2, cast) -- after the swing, before its row
            I.AuraModel(1, C, 0, 0, 0, 10.2, cast)
            ctl.now = 10.47 -- the core band: final at once
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            drain(10.5)
            assert.are.same({ { 10, false, true, 2 } }, seen)
            assert.are.same({ 10, 25 }, { I.auras.applied[1][C], I.auras.exp0[1][C] }) -- written at the swing's time
            assert.are.equal(0, I.nowErrors)
        end)

        it("hand filters by the swing's hand", function()
            local main, off = reaction("main_land", "target", "land"), reaction("off_land", "target", "land")
            main.hand, off.hand = "main", "off"
            build({ main, off })
            local S, Obs, K = I.Sources, VS.Obs, I.HitKind
            S.Direct(Obs.SwingSettled, 5, 1, 4.9, K.WOUND)
            VS.Drain(5.1)
            S.Direct(Obs.SwingSettled, 6, 2, 5.9, -1) -- closed with no row (0 is an avoid of an unmapped kind)
            VS.Drain(6.1)
            S.Direct(Obs.SwingSettled, 7, 2, 6.9, K.DODGE)
            VS.Drain(7.1)
            assert.are.same({ 1, 1 }, { runs.main_land, runs.off_land })
        end)
    end)

    -- Task 8a-4 (owner 2026-11-04): outcome "swing" (every white swing of ours at its settled outcome, optional hand),
    -- and "deflect" / "evade" through the same settled-only paths
    describe('outcome "swing" (who = "target")', function()
        local function hand(key, which)
            local r = reaction(key, "target", "swing")
            r.hand = which
            return r
        end

        it("runs once per settled swing: final, provisional at its final, avoided at its close", function()
            build({ reaction("swung", "target", "swing"), reaction("critted", "target", "crit") })
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 10.47 -- the core band: final at once
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 1)
            drain(10.5)
            assert.are.same({ 1, 1 }, { runs.swung, runs.critted })
            assert.are.equal(10.47, W("swung")[2])
            ctl.now = 20
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            ctl.now = 20.2 -- before the core band: provisional (TENT)
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            drain(20.25)
            assert.are.same({ T.TENT, 1 }, { T.state[i], runs.swung })
            drain(22)
            drain(22.1)
            assert.are.equal(2, runs.swung)
            assert.are.equal(20.2, W("swung")[2])
            ctl.now = 30
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 30.47
            ctl.Fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1)
            drain(30.5)
            assert.are.equal(2, runs.swung) -- provisional: a later wound could give it back
            drain(32)
            drain(32.1)
            assert.are.same({ 3, 1 }, { runs.swung, runs.critted })
            assert.are.equal(30.47, W("swung")[2])
            assert.are.equal(0, I.nowErrors)
        end)

        -- one-event-feed plan Step 1 (Task 8a-6): the verdict's retraction re-opens the swing for the rage model only;
        -- the re-open's row paid again settles nothing twice
        it("runs once across a verdict's retraction and its re-open paid again", function()
            build({ reaction("swung", "target", "swing") })
            local id
            local S, stage = I.Sources, I.Sources.Stage
            S.Stage = function(kind, t, a, b, c)
                if kind == VS.Obs.Swing and c == 1 then
                    id = b
                end
                return stage(kind, t, a, b, c)
            end
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 10.36 -- the core band: final
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            drain(10.38)
            assert.are.equal(1, runs.swung)
            assert.is_true(I.CreditVerdict(id, false, 10.4, true))
            ctl.now = 10.55
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 31, 1)
            drain(10.6)
            drain(13)
            S.Stage = stage
            assert.are.equal(1, runs.swung)
        end)

        it("hand filters by the hand the belief attributed the swing to (Obs.SwingSettled's a)", function()
            build({ hand("main_sw", "main"), hand("off_sw", "off"), reaction("any_sw", "target", "swing") })
            local S, Obs, K = I.Sources, VS.Obs, I.HitKind
            S.Direct(Obs.SwingSettled, 5, 1, 4.9, K.WOUND)
            VS.Drain(5.1)
            assert.are.same({ 1, 0, 1 }, { runs.main_sw, runs.off_sw, runs.any_sw })
            S.Direct(Obs.SwingSettled, 6, 2, 5.9, K.DODGE)
            VS.Drain(6.1)
            assert.are.same({ 1, 1, 2 }, { runs.main_sw, runs.off_sw, runs.any_sw })
            assert.are.equal(6, W("off_sw")[2])
        end)

        -- gap AS (the Rend 163.54 case above): the swing's tied dodge goes back to the cast; the swing landed
        it("never runs on a provisional avoid later given back; the swing runs once, at its own wound", function()
            build({ reaction("swung", "target", "swing"), reaction("dodged", "target", "dodge") })
            ctl.now = 163.13
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 163.54
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            drain(163.56)
            assert.are.same({ 0, 0 }, { runs.swung, runs.dodged })
            ctl.now = 163.604
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            drain(163.62)
            drain(166)
            drain(166.1)
            assert.are.same({ 1, 1 }, { runs.swung, runs.dodged })
            assert.are.equal(163.604, W("swung")[2])
        end)

        it("touches no cast history, ticket, GCD, step or strict window", function()
            local on = false
            build({ reaction("swung", "target", "swing") }, {
                window("stepped", {
                    steps = { 1, 2 },
                    evaluator = function()
                        return on
                    end,
                }),
                window("strict", {
                    steps = { 1, 2 },
                    strict = true,
                    evaluator = function()
                        return on
                    end,
                }),
            })
            ctl.now = 5
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            drain(5.1)
            on = true
            drain(5.2)
            ctl.now = 5.3
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local casts, lastT, opened, gcd = I.castsRun, I.lastCastT, T.opened, VS.Gcd(5.9).est
            local owner, kind, cd = I.gcdOwner, I.gcdKindLast, VS.Cooldown(fs.SPENDER_C, 5.9).est
            local stepped, strict = W("stepped"), W("strict")
            ctl.now = 5.77
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            drain(5.8)
            assert.are.equal(1, runs.swung)
            assert.are.same({ casts, lastT, opened, gcd }, { I.castsRun, I.lastCastT, T.opened, VS.Gcd(5.9).est })
            assert.are.same({ owner, kind, cd }, { I.gcdOwner, I.gcdKindLast, VS.Cooldown(fs.SPENDER_C, 5.9).est })
            assert.are.same(stepped, W("stepped"))
            assert.are.same(strict, W("strict"))
        end)

        it("allocates nothing across 1000 Drains settling a swing each", function()
            build({ hand("main_sw", "main"), reaction("any_sw", "target", "swing") })
            local t = 5
            local bytes = alloc.bytes(function()
                t = t + 3
                ctl.now = t
                ctl.Fire("PLAYER_SWING", 2.6, 0)
                ctl.now = t + 0.47
                ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
                drain(t + 0.5)
            end, 1000)
            assert.are.equal(0, bytes)
            assert.are.equal(0, I.nowErrors)
            assert.is_true(runs.main_sw >= 500 and runs.any_sw == runs.main_sw, tostring(runs.main_sw))
        end)
    end)

    describe('outcomes "deflect" and "evade"', function()
        it("on us (victim-side UNIT_COMBAT): each runs its own reaction", function()
            build({ reaction("deflected", "player", "deflect"), reaction("evaded", "player", "evade") })
            ctl.now = 5
            ctl.Fire("UNIT_COMBAT", "player", "DEFLECT", "", 0, 1)
            drain(5.1)
            assert.are.same({ 1, 0 }, { runs.deflected, runs.evaded })
            ctl.now = 6
            ctl.Fire("UNIT_COMBAT", "player", "EVADE", "", 0, 1)
            drain(6.1)
            assert.are.same({ 1, 1 }, { runs.deflected, runs.evaded })
            assert.are.equal(6, W("evaded")[2])
        end)

        it("our cast deflected runs the reaction at the row; no undo or refund (not an avoid that refuses)", function()
            build({ reaction("deflected", "target", "deflect"), reaction("dodged", "target", "dodge") })
            local avoids = I.avoidsRun
            ctl.now = 5
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.Fire("UNIT_COMBAT", "target", "DEFLECT", "", 0, 1)
            drain(5.4)
            assert.are.same({ 1, 0, avoids }, { runs.deflected, runs.dodged, I.avoidsRun })
            assert.are.equal(5, W("deflected")[2])
        end)

        it("our swing evaded runs only at its window's close, with the swing reaction", function()
            build({ reaction("evaded", "target", "evade"), reaction("swung", "target", "swing") })
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 10.47
            ctl.Fire("UNIT_COMBAT", "target", "EVADE", "", 0, 1)
            drain(10.5)
            assert.are.same({ 0, 0 }, { runs.evaded, runs.swung })
            drain(12)
            drain(12.1)
            assert.are.same({ 1, 1 }, { runs.evaded, runs.swung })
            assert.are.equal(10.47, W("evaded")[2])
        end)
    end)

    it("touches no cast history, ticket, GCD, step or strict window", function()
        local on = false
        build({ reaction("parried", "player", "parry") }, {
            window("stepped", {
                steps = { 1, 2 },
                evaluator = function()
                    return on
                end,
            }),
            window("strict", {
                steps = { 1, 2 },
                strict = true,
                evaluator = function()
                    return on
                end,
            }),
        })
        ctl.now = 5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
        drain(5.1)
        on = true
        drain(5.2)
        local casts, lastT, opened, gcd = I.castsRun, I.lastCastT, T.opened, VS.Gcd(5.3).est
        -- the belief's prev_gcd (the GCD's owner and kind: the core's prev_gcd is its own, from its events) and a cooldown
        local owner, kind, cd = I.gcdOwner, I.gcdKindLast, VS.Cooldown(fs.SPENDER_C, 5.3).est
        assert.is_true(owner > 0)
        local stepped, strict = W("stepped"), W("strict")
        assert.are.same({ true, 1 }, { stepped[1], stepped[5] })
        ctl.now = 5.3
        ctl.Fire("UNIT_COMBAT", "player", "PARRY", "", 0, 1)
        drain(5.4)
        assert.are.equal(1, runs.parried)
        assert.are.same({ casts, lastT, opened, gcd }, { I.castsRun, I.lastCastT, T.opened, VS.Gcd(5.3).est })
        assert.are.same({ owner, kind, cd }, { I.gcdOwner, I.gcdKindLast, VS.Cooldown(fs.SPENDER_C, 5.3).est })
        assert.are.same(stepped, W("stepped"))
        assert.are.same(strict, W("strict"))
        for a = 1, I.ab.n do
            assert.are_not.equal("parried", I.ab.key[a])
        end
    end)

    it("allocates nothing across 1000 Drains firing a reaction each", function()
        build({ reaction("parried", "player", "parry"), reaction("critted", "player", "crit") })
        local t = 5
        local bytes = alloc.bytes(function(i)
            t = t + 0.3
            ctl.now = t
            if i % 2 == 0 then
                ctl.Fire("UNIT_COMBAT", "player", "PARRY", "", 0, 1)
            else
                ctl.Fire("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 50, 1)
            end
            drain(t + 0.01)
        end, 1000)
        assert.are.equal(0, bytes)
        assert.are.equal(0, I.nowErrors)
        assert.is_true(runs.parried >= 500 and runs.critted >= 500)
    end)

    it("allocates nothing across 1000 Drains firing a target-side reaction each (our cast dodged)", function()
        build({ reaction("dodged", "target", "dodge") })
        local t = 5
        local bytes = alloc.bytes(function()
            t = t + 2
            ctl.now = t
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C)
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            drain(t + 0.4)
        end, 1000)
        assert.are.equal(0, bytes)
        assert.are.equal(0, I.nowErrors)
        assert.is_true(runs.dodged >= 500, tostring(runs.dodged))
    end)
end)
