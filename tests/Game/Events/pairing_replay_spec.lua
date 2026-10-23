-- tests/Game/Events/pairing_replay_spec.lua (event-facade spec §3, pairing): log 2 of
-- docs/research/2026-10-16-swing-outcome-pairing.md (the harness fixture tests/Game/harness/fixtures/log2.lua)
-- replayed through the real Rows.lua, with the weapon damage the character had (main 36-50, off 24-32). Every
-- outcome on the target is fed once as the token "target" (a few were recorded only under softinteract or nameplate1),
-- as in game Rows.lua reads only "target", which dedupes the tokens.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local alloc = require("Game.State.helpers.alloc")
local fs = require("Game.State.helpers.fake_spec")
local drive = require("Game.harness.drive")

-- One row per outcome on the target, fed as "target" (harness/drive.lua's dedupe of the fixture's token rows).
local LOG = drive.fixtureStream(require("Game.harness.fixtures.log2"), 0, true)

describe("swing/outcome pairing", function()
    local api, ctl, VS, I, L, saved, got, record
    local lastHand, lastAmount, lastLag, crits, landed = 0, 0, 0, { 0, 0 }, { 0, 0 }

    -- Boots with UnitDamage's returns (min and max main, min and max off; zeros: no cache yet).
    local function start(minMain, maxMain, minOff, maxOff)
        api, ctl = fake.new()
        api.UnitDamage = function()
            return minMain, maxMain, minOff, maxOff, 0, 0, 1
        end
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        L = I.Log
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        local S, Swing = I.Sources, VS.Obs.Swing
        local stage = S.Stage
        S.Stage = function(kind, t, a, b, c)
            if kind == Swing and c == 3 then
                crits[a] = crits[a] + 1
            elseif kind == Swing and (c == 1 or c == 7) then -- c = 7: an assumed swing's hit confirmed
                landed[a] = landed[a] + 1
            end
            return stage(kind, t, a, b, c)
        end
        local GetInfo = ns.Facade.CombatLogGetCurrentEventInfo
        got, record, crits[1], crits[2], landed[1], landed[2] = {}, false, 0, 0, 0, 0
        local sink = I.Events.CreateFrame("Frame")
        sink:SetScript("OnEvent", function()
            local t, ev, _, _, _, _, _, _, _, _, _, a12, a13, _, a15, _, _, _, _, _, a21 = GetInfo()
            if ev == "SWING_DAMAGE" and a12 > 0 then
                lastHand, lastAmount, lastLag = a21 and 2 or 1, a12, ctl.now - t
            end
            if record then
                got[#got + 1] = { ev, a12, a13, a15, a21, t }
            end
        end)
        sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    -- One replay of the log from `base` seconds; counts each wound by the hand its amount names (a crit halved,
    -- above 33 the main hand) and whether a SWING_DAMAGE of that hand and amount came of it. Allocates nothing.
    local stats = { main = 0, off = 0, mainOk = 0, offOk = 0, critOk = 0, crits = 0, late = 0 }
    local function replay(base)
        for key in pairs(stats) do
            stats[key] = 0
        end
        for k = 1, LOG.n do
            local now = base + LOG.t[k]
            local kind = LOG.ev[k]
            ctl.Tick(now)
            if kind == "PLAYER_SWING" then
                ctl.Fire("PLAYER_SWING", LOG.a1[k], LOG.a2[k])
            elseif kind == "UNIT_SPELLCAST_SUCCEEDED" then
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", LOG.a3[k])
            elseif kind == "UNIT_COMBAT" then
                local act, flag, amount = LOG.a2[k], LOG.a3[k], LOG.a4[k]
                lastAmount = 0
                local c1, c2 = crits[1], crits[2]
                ctl.Fire("UNIT_COMBAT", "target", act, flag, amount, 1)
                if act == "WOUND" and amount > 0 then
                    local hand = (flag == "CRITICAL" and amount / 2 or amount) > 33 and 1 or 2
                    local ok = lastAmount == amount and lastHand == hand
                    if hand == 1 then
                        stats.main, stats.mainOk = stats.main + 1, stats.mainOk + (ok and 1 or 0)
                    else
                        stats.off, stats.offOk = stats.off + 1, stats.offOk + (ok and 1 or 0)
                    end
                    if lastAmount > 0 and lastLag > L.PAIR_WINDOW_MS[lastHand] / 1000 then
                        stats.late = stats.late + 1
                    end
                    if flag == "CRITICAL" then
                        stats.crits = stats.crits + 1
                        local okCrit = crits[hand] == (hand == 1 and c1 or c2) + 1
                            and crits[3 - hand] == (hand == 1 and c2 or c1)
                        stats.critOk = stats.critOk + (okCrit and 1 or 0)
                    end
                end
            end
        end
        ctl.Tick(base + 130)
    end

    it("credits log 2's wounds to their own hand's swing, within the hand's window (harness design §3.4)", function()
        start(36, 50, 24, 32)
        replay(10)
        assert.are.same({ 36, 33 }, { stats.main, stats.off }) -- the 34 and 31 hits plus the 4 orphans of the doc
        assert.is_true(stats.mainOk >= 34, "main hand paired: " .. stats.mainOk)
        assert.is_true(stats.offOk >= 31, "off hand paired: " .. stats.offOk)
        -- the last crit (52 at 116581: 369 ms after the main swing, 103 ms after the off swing) scores as the main
        -- hand's by its lag, though its amount is the off hand's
        assert.are.same({ 8, 7 }, { stats.crits, stats.critOk })
        assert.are.equal(0, stats.late)
    end)

    it("allocates nothing replaying the log", function()
        start(36, 50, 24, 32)
        local bytes = alloc.bytes(function(i)
            replay(i * 200)
            I.Sources.Flush()
        end, 5)
        assert.are.equal(0, bytes)
    end)

    describe("one frame at a time", function()
        before_each(function()
            start(36, 50, 24, 32)
            record = true
        end)

        local function fire(t, event, ...)
            ctl.Tick(t)
            ctl.Fire(event, ...)
        end

        it("gives an on-next-swing strike its own wound and drops the frame's WOUND 0, in either order", function()
            fire(10, "PLAYER_SWING", 2.2, 0) -- the brief's order: swing, WOUND 0, success, the strike's wound
            fire(10, "UNIT_COMBAT", "target", "WOUND", "", 0, 1)
            fire(10, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_B)
            fire(10.001, "UNIT_COMBAT", "target", "WOUND", "", 77, 1)
            fire(20, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_B) -- log 1's order
            fire(20, "UNIT_COMBAT", "target", "WOUND", "", 0, 1)
            fire(20, "PLAYER_SWING", 2.2, 0)
            fire(20.001, "UNIT_COMBAT", "target", "WOUND", "", 84, 1)
            ctl.Tick(25)
            assert.are.same({
                { "SPELL_CAST_SUCCESS" },
                { "SPELL_DAMAGE", fs.SPENDER_B, "", 77 },
                { "SPELL_CAST_SUCCESS" },
                { "SPELL_DAMAGE", fs.SPENDER_B, "", 84 },
            }, {
                { got[1][1] },
                { got[2][1], got[2][2], got[2][3], got[2][4] },
                { got[3][1] },
                { got[4][1], got[4][2], got[4][3], got[4][4] },
            })
            assert.are.equal(4, #got)
        end)

        it("gives a wound in our cast's frame to the cast, though it fits a pending swing (Overpower)", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.2, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C) -- stands in for Overpower
            fire(10.2, "UNIT_COMBAT", "target", "WOUND", "", 45, 1) -- the strike's damage, inside the main range
            assert.are.same({ "SPELL_CAST_SUCCESS", "SPELL_DAMAGE", 45 }, { got[1][1], got[2][1], got[2][4] })
            assert.are.equal(0, landed[1])
            fire(10.45, "UNIT_COMBAT", "target", "WOUND", "", 44, 1) -- the white swing's own wound
            assert.are.same({ "SWING_DAMAGE", 44, false }, { got[3][1], got[3][2], got[3][5] })
            assert.are.equal(1, landed[1])
        end)

        it("credits a wound outside the cached ranges by timing alone when the form changed since the read", function()
            ctl.form = 1 -- a form whose weapon damage the cache never read
            fire(10, "PLAYER_SWING", 2.5, 0)
            fire(10.45, "UNIT_COMBAT", "target", "WOUND", "", 120, 1)
            assert.are.same({ "SWING_DAMAGE", 120, 1 }, { got[1][1], got[1][2], landed[1] })
        end)

        it(
            "credits an above-range wound in the core band solo, and rejects it once that class's background is up",
            function()
                fire(10, "PLAYER_SWING", 2.2, 0)
                fire(10.47, "UNIT_COMBAT", "target", "WOUND", "", 70, 1) -- above the main hand's 50 (a buff since the read)
                assert.are.same({ "SWING_DAMAGE", 70, 1 }, { got[1][1], got[1][2], landed[1] })
                fire(12, "PLAYER_REGEN_DISABLED")
                for k = 1, 10 do -- in combat with nothing of ours pending: background
                    fire(12 + k, "UNIT_COMBAT", "target", "WOUND", "", 70, 1)
                end
                fire(23, "PLAYER_SWING", 2.2, 0)
                fire(23.47, "UNIT_COMBAT", "target", "WOUND", "", 70, 1)
                assert.are.same({ 1, 11 }, { landed[1], L.background })
            end
        )

        it("drops a wound that fits neither hand (a DoT tick), and the swing takes the next that fits", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.3, "UNIT_COMBAT", "target", "WOUND", "", 13, 1)
            assert.are.equal(0, #got)
            fire(10.45, "UNIT_COMBAT", "target", "WOUND", "", 45, 1)
            assert.are.same({ "SWING_DAMAGE", 45, false }, { got[1][1], got[1][2], got[1][5] })
        end)

        it(
            "gives a wound to the hand whose exact range holds it when both lags fit, else to the better-timed swing",
            function()
                fire(9.77, "PLAYER_SWING", 2.5, 1)
                fire(10, "PLAYER_SWING", 2.2, 0)
                fire(10.473, "UNIT_COMBAT", "target", "WOUND", "", 30, 1) -- loosely both hands', exactly the off hand's
                fire(20, "PLAYER_SWING", 2.5, 1)
                fire(20.2, "PLAYER_SWING", 2.2, 0)
                fire(20.703, "UNIT_COMBAT", "target", "WOUND", "", 34, 1) -- loosely both, exactly neither: the off hand's lag
                assert.are.same(
                    { "SWING_DAMAGE", 30, true, "SWING_DAMAGE", 34, true },
                    { got[1][1], got[1][2], got[1][5], got[3][1], got[3][2], got[3][5] }
                )
            end
        )

        it("credits the off hand 0.703 s after its own swing or 1.686 s after the main swing before it", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.3, "PLAYER_SWING", 2.5, 1)
            fire(11.686, "UNIT_COMBAT", "target", "WOUND", "", 28, 1) -- 1.386 s after its own: the main reference
            fire(20, "PLAYER_SWING", 2.5, 1)
            fire(20.703, "UNIT_COMBAT", "target", "WOUND", "", 29, 1)
            assert.are.same({ 28, true, 29, true }, { got[2][2], got[2][5], got[3][2], got[3][5] }) -- got[1]: main's 0
            assert.are.same({ 0, 2 }, landed)
        end)

        it(
            "makes a glancing 4 at 7 ms and a MISS at 53 ms background, and credits our 50 at 369 ms (G's frame)",
            function()
                fire(10, "PLAYER_SWING", 2.2, 0)
                fire(10.007, "UNIT_COMBAT", "target", "WOUND", "GLANCING", 4, 1)
                fire(10.053, "UNIT_COMBAT", "target", "MISS", "", 0, 1)
                fire(10.369, "UNIT_COMBAT", "target", "WOUND", "", 50, 1)
                ctl.Tick(12)
                assert.are.same({ { "SWING_DAMAGE", 50, 0, 0, false, 10 } }, got)
            end
        )

        it("drops another player's strike frame (a WOUND 0, its damage 1 ms later, no success of ours)", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.2, "UNIT_COMBAT", "target", "WOUND", "", 0, 1)
            fire(10.201, "UNIT_COMBAT", "target", "WOUND", "", 40, 1)
            assert.are.same({ 0, 0 }, { #got, landed[1] }) -- the swing is still pending
            fire(10.47, "UNIT_COMBAT", "target", "WOUND", "", 44, 1)
            assert.are.same({ "SWING_DAMAGE", 44, 1 }, { got[1][1], got[1][2], landed[1] })
        end)

        it("gives no swing a wound of another school inside its range (a party caster's spell)", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.47, "UNIT_COMBAT", "target", "WOUND", "", 40, 8)
            ctl.Tick(12)
            assert.are.same({ "SWING_DAMAGE", 0, 0 }, { got[1][1], got[1][2], landed[1] }) -- the window closed unpaired
        end)

        it("makes a wound with a secret amount, flag or school no candidate, only counted (final review #1)", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.47, "UNIT_COMBAT", "target", "WOUND", "", fake.SECRET, 1)
            fire(10.47, "UNIT_COMBAT", "target", "WOUND", fake.SECRET, 44, 1)
            fire(10.47, "UNIT_COMBAT", "target", "WOUND", "", 44, fake.SECRET)
            assert.are.same({ 0, 3 }, { #got, L.background })
            fire(10.5, "UNIT_COMBAT", "target", "WOUND", "", 44, 1)
            assert.are.same({ "SWING_DAMAGE", 44, 1 }, { got[1][1], got[1][2], landed[1] })
        end)

        it("counts only white outcomes into the background: no class for a school-8 wound or a RESIST", function()
            fire(12, "PLAYER_REGEN_DISABLED") -- in combat, nothing of ours pending: a quiet window (no decay at one t)
            local before = { unpack(L.bg) }
            fire(12, "UNIT_COMBAT", "target", "WOUND", "", 40, 8) -- a caster's spell in the main hand's exact range
            fire(12, "UNIT_COMBAT", "target", "RESIST", "", 0, 1) -- a cast-only miss, not a swing's avoid
            assert.are.same(before, L.bg)
            assert.are.equal(2, L.background) -- still counted as unclaimed
            fire(12, "UNIT_COMBAT", "target", "WOUND", "", 40, 1)
            fire(12, "UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            assert.are.same(
                { 1, 1, 1 }, -- main exact, the avoid class, white any amount
                { L.bg[1] - before[1], L.bg[7] - before[7], L.bg[8] - before[8] }
            )
        end)

        it("credits an avoid provisionally, and the swing goes to the hand's wound that scores higher", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.4, "UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            fire(10.47, "UNIT_COMBAT", "target", "WOUND", "", 44, 1)
            ctl.Tick(12)
            assert.are.same({ { "SWING_DAMAGE", 44, 0, 0, false, 10 } }, got) -- no SWING_MISSED
            assert.are.same({ 1, 1 }, { landed[1], L.avoidsBack })
        end)

        it("keeps an avoid nothing beats: SWING_MISSED when the window closes, back-dated to the swing", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.47, "UNIT_COMBAT", "target", "PARRY", "", 0, 1)
            ctl.Tick(11.45)
            assert.are.equal(0, #got)
            ctl.Tick(11.55)
            assert.are.same({ { "SWING_MISSED", "PARRY", false, false, nil, 10 } }, got)
        end)

        it("makes an avoid at neither hand's lag background", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.05, "UNIT_COMBAT", "target", "DODGE", "", 0, 1) -- the same-ms avoids of log 2
            ctl.Tick(12)
            assert.are.same({ "SWING_DAMAGE", 0 }, { got[1][1], got[1][2] })
        end)

        it("moves the main lag's median and spread toward a stream of 520 ms lags, not on tail credits", function()
            for k = 0, 39 do
                fire(10 + 2.2 * k, "PLAYER_SWING", 2.2, 0)
                fire(10.52 + 2.2 * k, "UNIT_COMBAT", "target", "WOUND", "", 44, 1)
            end
            assert.is_true(math.abs(L.med[1] - 0.52) <= 0.006 and L.spr[1] < 0.03, L.med[1] .. " " .. L.spr[1])
            local med, spr = L.med[1], L.spr[1]
            fire(200, "PLAYER_SWING", 2.2, 0)
            fire(201.2, "UNIT_COMBAT", "target", "WOUND", "", 44, 1) -- in the tail: credited, not learned
            assert.are.same({ 41, med, spr }, { landed[1], L.med[1], L.spr[1] })
        end)
    end)

    it("credits a wound by timing alone before the first UnitDamage read", function()
        start(0, 0, 0, 0)
        record = true
        ctl.Tick(10)
        ctl.Fire("PLAYER_SWING", 2.5, 1)
        ctl.Tick(10.2)
        ctl.Fire("PLAYER_SWING", 2.2, 0)
        ctl.Tick(10.62)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 45, 1) -- no range to tell: the main hand's lag
        assert.are.same({ "SWING_DAMAGE", 45, false }, { got[1][1], got[1][2], got[1][5] })
    end)
end)
