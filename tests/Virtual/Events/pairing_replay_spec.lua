-- tests/Virtual/Events/pairing_replay_spec.lua (event-facade spec §3, pairing): log 2 of
-- docs/research/2026-10-16-swing-outcome-pairing.md (the harness fixture tests/Virtual/harness/fixtures/log2.lua)
-- replayed through the real Rows.lua, with the weapon damage the character had (main 36-50, off 24-32). Every
-- outcome on the target is fed once as the token "target" (a few were recorded only under softinteract or nameplate1),
-- as in game Rows.lua reads only "target", which dedupes the tokens.
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")
local alloc = require("Virtual.State.helpers.alloc")
local fs = require("Virtual.State.helpers.fake_spec")
local drive = require("Virtual.harness.drive")

-- One row per outcome on the target, fed as "target" (harness/drive.lua's dedupe of the fixture's token rows).
local LOG = drive.fixtureStream(require("Virtual.harness.fixtures.log2"), 0, true)

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
            elseif kind == Swing and c == 1 then
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
                got[#got + 1] = { ev, a12, a13, a15, a21 }
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

    it("pairs log 2's wounds with their own hand's swing, within the hand's window", function()
        start(36, 50, 24, 32)
        replay(10)
        assert.are.same({ 36, 33 }, { stats.main, stats.off }) -- the 34 and 31 hits plus the 4 orphans of the doc
        assert.is_true(stats.mainOk >= 30, "main hand paired: " .. stats.mainOk)
        assert.is_true(stats.offOk >= 28, "off hand paired: " .. stats.offOk)
        assert.are.same({ 8, 8 }, { stats.crits, stats.critOk })
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
            fire(10, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.STRIKE)
            fire(10.001, "UNIT_COMBAT", "target", "WOUND", "", 77, 1)
            fire(20, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.STRIKE) -- log 1's order
            fire(20, "UNIT_COMBAT", "target", "WOUND", "", 0, 1)
            fire(20, "PLAYER_SWING", 2.2, 0)
            fire(20.001, "UNIT_COMBAT", "target", "WOUND", "", 84, 1)
            ctl.Tick(25)
            assert.are.same({
                { "SPELL_CAST_SUCCESS" },
                { "SPELL_DAMAGE", fs.STRIKE, "", 77 },
                { "SPELL_CAST_SUCCESS" },
                { "SPELL_DAMAGE", fs.STRIKE, "", 84 },
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
            fire(10.2, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND) -- stands in for Overpower
            fire(10.2, "UNIT_COMBAT", "target", "WOUND", "", 45, 1) -- the strike's damage, inside the main range
            assert.are.same({ "SPELL_CAST_SUCCESS", "SPELL_DAMAGE", 45 }, { got[1][1], got[2][1], got[2][4] })
            assert.are.equal(0, landed[1])
            fire(10.45, "UNIT_COMBAT", "target", "WOUND", "", 44, 1) -- the white swing's own wound
            assert.are.same({ "SWING_DAMAGE", 44, false }, { got[3][1], got[3][2], got[3][5] })
            assert.are.equal(1, landed[1])
        end)

        it("pays a swing whose wound is outside the cached ranges when the form changed since the read", function()
            ctl.form = 1 -- Bear Form: the cache holds the caster's weapon damage
            fire(10, "PLAYER_SWING", 2.5, 0)
            fire(10.45, "UNIT_COMBAT", "target", "WOUND", "", 120, 1)
            assert.are.same({ "SWING_DAMAGE", 120, 1 }, { got[1][1], got[1][2], landed[1] })
        end)

        it("treats the cache as stale after 3 white wounds in a row fit no range (a damage buff)", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.2, "UNIT_COMBAT", "target", "WOUND", "", 120, 1)
            fire(10.3, "UNIT_COMBAT", "target", "WOUND", "", 120, 1)
            assert.are.same({ 0, 0 }, { #got, landed[1] })
            fire(10.4, "UNIT_COMBAT", "target", "WOUND", "", 120, 1)
            fire(12.2, "PLAYER_SWING", 2.2, 0)
            fire(12.6, "UNIT_COMBAT", "target", "WOUND", "", 121, 1)
            assert.are.same(
                { "SWING_DAMAGE", 120, "SWING_DAMAGE", 121, 2 },
                { got[1][1], got[1][2], got[2][1], got[2][2], landed[1] }
            )
        end)

        it("drops a wound that fits neither hand (a Rend tick), and the swing takes the next that fits", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.3, "UNIT_COMBAT", "target", "WOUND", "", 13, 1)
            assert.are.equal(0, #got)
            fire(10.45, "UNIT_COMBAT", "target", "WOUND", "", 45, 1)
            assert.are.same({ "SWING_DAMAGE", 45, false }, { got[1][1], got[1][2], got[1][5] })
        end)

        it("gives a wound to the hand whose exact range holds it, else the older pending swing", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.2, "PLAYER_SWING", 2.5, 1)
            fire(10.6, "UNIT_COMBAT", "target", "WOUND", "", 30, 1) -- loosely both hands', exactly the off hand's
            fire(20, "PLAYER_SWING", 2.5, 1)
            fire(20.2, "PLAYER_SWING", 2.2, 0)
            fire(20.6, "UNIT_COMBAT", "target", "WOUND", "", 34, 1) -- loosely both (21.6-55, 14.4-35.2), exactly neither
            assert.are.same(
                { "SWING_DAMAGE", 30, true, "SWING_DAMAGE", 34, true },
                { got[1][1], got[1][2], got[1][5], got[3][1], got[3][2], got[3][5] }
            )
        end)

        it("pairs an avoid with the older of two pending swings", function()
            fire(10, "PLAYER_SWING", 2.2, 0)
            fire(10.1, "PLAYER_SWING", 2.5, 1)
            fire(10.4, "UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            fire(30, "PLAYER_SWING", 2.5, 1)
            fire(30.1, "PLAYER_SWING", 2.2, 0)
            fire(30.4, "UNIT_COMBAT", "target", "PARRY", "", 0, 1)
            assert.are.same(
                { "SWING_MISSED", "DODGE", false, "SWING_MISSED", "PARRY", true },
                { got[1][1], got[1][2], got[1][3], got[3][1], got[3][2], got[3][3] }
            )
        end)
    end)

    it("pairs a wound with the oldest pending swing of either hand before the first UnitDamage read", function()
        start(0, 0, 0, 0)
        record = true
        ctl.Tick(10)
        ctl.Fire("PLAYER_SWING", 2.5, 1)
        ctl.Tick(10.2)
        ctl.Fire("PLAYER_SWING", 2.2, 0)
        ctl.Tick(10.6)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 45, 1) -- a main-hand amount, but no range to tell
        assert.are.same({ "SWING_DAMAGE", 45, true }, { got[1][1], got[1][2], got[1][5] })
    end)
end)
