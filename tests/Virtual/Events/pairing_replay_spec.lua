-- tests/Virtual/Events/pairing_replay_spec.lua (event-facade spec §3, pairing): log 2 of
-- docs/research/2026-10-16-swing-outcome-pairing.md replayed through the real Rows.lua, with the weapon damage the
-- character had (main 36-50, off 24-32). Every UNIT_COMBAT row is fed as the token "target": the log is already
-- deduplicated (one row per outcome, a few kept under softinteract or nameplate1), and in game Rows.lua reads only
-- "target", which dedupes the tokens.
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")
local alloc = require("Virtual.State.helpers.alloc")
local fs = require("Virtual.State.helpers.fake_spec")

-- ms since the first event, then: "S" PLAYER_SWING duration swingType; "U" UNIT_COMBAT action flag amount;
-- "C" our UNIT_SPELLCAST_SUCCEEDED spellID (Charge: not an ability of the fake spec, so it pairs with nothing).
-- stylua: ignore
local LOG = {
    { 0, "C", 100 }, { 998, "S", 2.2, 0 }, { 1296, "S", 2.5, 1 }, { 1472, "U", "WOUND", "", 40 },
    { 2695, "U", "WOUND", "", 31 }, { 3158, "S", 2.2, 0 }, { 3612, "U", "WOUND", "", 41 }, { 3775, "S", 2.5, 1 },
    { 4844, "U", "WOUND", "", 30 }, { 5404, "S", 2.2, 0 }, { 5841, "U", "WOUND", "", 43 }, { 6289, "S", 2.5, 1 },
    { 7091, "U", "WOUND", "", 31 }, { 7556, "S", 2.2, 0 }, { 7992, "U", "WOUND", "", 49 }, { 8788, "S", 2.5, 1 },
    { 9491, "U", "DODGE", "", 0 }, { 9788, "S", 2.2, 0 }, { 10308, "U", "WOUND", "", 49 }, { 11221, "S", 2.5, 1 },
    { 11924, "U", "WOUND", "", 28 }, { 11988, "S", 2.2, 0 }, { 12122, "U", "WOUND", "CRITICAL", 91 },
    { 17786, "C", 100 }, { 18518, "S", 2.5, 1 }, { 18785, "S", 2.2, 0 }, { 19221, "U", "WOUND", "", 30 },
    { 19221, "U", "MISS", "", 0 }, { 21085, "S", 2.2, 0 }, { 21085, "S", 2.5, 1 }, { 21521, "U", "WOUND", "", 45 },
    { 22771, "U", "WOUND", "", 25 }, { 23251, "S", 2.2, 0 }, { 23635, "S", 2.5, 1 },
    { 23788, "U", "WOUND", "BLOCK_REDUCED", 48 }, { 24938, "U", "WOUND", "", 26 }, { 25401, "S", 2.2, 0 },
    { 25938, "U", "WOUND", "", 42 }, { 26118, "S", 2.5, 1 }, { 27088, "U", "WOUND", "CRITICAL", 56 },
    { 27685, "S", 2.2, 0 }, { 28138, "U", "WOUND", "", 39 }, { 28635, "S", 2.5, 1 },
    { 29371, "U", "WOUND", "", 25 }, { 29835, "S", 2.2, 0 }, { 30271, "U", "WOUND", "", 48 },
    { 31051, "S", 2.5, 1 }, { 31755, "U", "WOUND", "", 31 }, { 32069, "S", 2.2, 0 },
    { 32505, "U", "WOUND", "", 43 }, { 33651, "S", 2.5, 1 }, { 38086, "C", 100 }, { 38935, "S", 2.5, 1 },
    { 39086, "S", 2.2, 0 }, { 39638, "U", "WOUND", "", 29 }, { 39638, "U", "WOUND", "", 49 },
    { 41368, "S", 2.2, 0 }, { 41369, "S", 2.5, 1 }, { 41905, "U", "WOUND", "", 48 },
    { 43055, "U", "WOUND", "", 28 }, { 43585, "S", 2.2, 0 }, { 43935, "S", 2.5, 1 },
    { 44122, "U", "WOUND", "", 50 }, { 45272, "U", "WOUND", "", 30 }, { 45785, "S", 2.2, 0 },
    { 46323, "U", "WOUND", "", 45 }, { 46452, "S", 2.5, 1 }, { 47472, "U", "WOUND", "", 27 },
    { 48002, "S", 2.2, 0 }, { 48522, "U", "WOUND", "CRITICAL", 97 }, { 48885, "S", 2.5, 1 },
    { 49689, "U", "WOUND", "", 30 }, { 50202, "S", 2.2, 0 }, { 50638, "U", "WOUND", "", 45 },
    { 51452, "S", 2.5, 1 }, { 52146, "U", "WOUND", "CRITICAL", 48 }, { 58607, "C", 100 }, { 59592, "S", 2.5, 1 },
    { 59891, "S", 2.2, 0 }, { 59891, "U", "MISS", "", 0 }, { 60294, "U", "WOUND", "", 28 },
    { 61095, "U", "WOUND", "", 48 }, { 62091, "S", 2.2, 0 }, { 62091, "S", 2.5, 1 },
    { 62628, "U", "WOUND", "", 49 }, { 63777, "U", "WOUND", "", 26 }, { 64291, "S", 2.2, 0 },
    { 64641, "S", 2.5, 1 }, { 64728, "U", "WOUND", "CRITICAL", 100 }, { 65978, "U", "WOUND", "", 28 },
    { 66508, "S", 2.2, 0 }, { 66944, "U", "WOUND", "", 38 }, { 67141, "S", 2.5, 1 },
    { 68194, "U", "WOUND", "", 26 }, { 68708, "S", 2.2, 0 }, { 69178, "U", "WOUND", "", 50 },
    { 69641, "S", 2.5, 1 }, { 70395, "U", "WOUND", "", 31 }, { 70909, "S", 2.2, 0 },
    { 71433, "U", "WOUND", "", 41 }, { 74361, "C", 100 }, { 75361, "S", 2.2, 0 }, { 75611, "S", 2.5, 1 },
    { 75897, "U", "WOUND", "", 42 }, { 76694, "S", 2.2, 0 }, { 77048, "U", "WOUND", "", 29 },
    { 77781, "U", "MISS", "", 0 }, { 78061, "S", 2.5, 1 }, { 78862, "S", 2.2, 0 }, { 79014, "U", "WOUND", "", 27 },
    { 79731, "U", "WOUND", "CRITICAL", 89 }, { 80628, "S", 2.5, 1 }, { 81111, "S", 2.2, 0 },
    { 81331, "U", "WOUND", "", 30 }, { 82048, "U", "MISS", "", 0 }, { 83128, "S", 2.5, 1 }, { 83311, "S", 2.2, 0 },
    { 83831, "U", "WOUND", "", 27 }, { 84548, "U", "WOUND", "", 49 }, { 85511, "S", 2.2, 0 },
    { 85611, "S", 2.5, 1 }, { 85611, "U", "MISS", "", 0 }, { 85948, "U", "PARRY", "", 0 },
    { 87198, "U", "WOUND", "", 27 }, { 87728, "S", 2.2, 0 }, { 88128, "S", 2.5, 1 }, { 88247, "U", "PARRY", "", 0 },
    { 89415, "U", "WOUND", "", 31 }, { 89928, "S", 2.2, 0 }, { 90381, "U", "WOUND", "", 45 },
    { 90611, "S", 2.5, 1 }, { 91614, "U", "WOUND", "", 28 }, { 92128, "S", 2.2, 0 },
    { 92582, "U", "WOUND", "", 47 }, { 95362, "C", 100 }, { 96178, "S", 2.2, 0 }, { 96495, "S", 2.5, 1 },
    { 96715, "U", "WOUND", "", 41 }, { 97864, "U", "DODGE", "", 0 }, { 98462, "S", 2.2, 0 },
    { 98915, "U", "WOUND", "", 39 }, { 98995, "S", 2.5, 1 }, { 99778, "S", 2.2, 0 },
    { 100148, "U", "PARRY", "", 0 }, { 100882, "U", "MISS", "", 0 }, { 101512, "S", 2.5, 1 },
    { 101928, "S", 2.2, 0 }, { 102215, "U", "DODGE", "", 0 }, { 102934, "U", "MISS", "", 0 },
    { 103962, "S", 2.5, 1 }, { 104128, "S", 2.2, 0 }, { 104665, "U", "WOUND", "CRITICAL", 55 },
    { 105415, "U", "WOUND", "", 39 }, { 106379, "S", 2.2, 0 }, { 106512, "S", 2.5, 1 },
    { 106833, "U", "WOUND", "", 47 }, { 108065, "U", "MISS", "", 0 }, { 108595, "S", 2.2, 0 },
    { 109012, "S", 2.5, 1 }, { 109132, "U", "WOUND", "", 41 }, { 110282, "U", "WOUND", "", 31 },
    { 110795, "S", 2.2, 0 }, { 110796, "U", "MISS", "", 0 }, { 111232, "U", "WOUND", "", 50 },
    { 111512, "S", 2.5, 1 }, { 112482, "U", "WOUND", "", 30 }, { 113012, "S", 2.2, 0 },
    { 113447, "U", "WOUND", "", 42 }, { 114012, "S", 2.5, 1 }, { 114714, "U", "WOUND", "", 29 },
    { 116212, "S", 2.2, 0 }, { 116478, "S", 2.5, 1 }, { 116581, "U", "WOUND", "CRITICAL", 52 },
    { 116734, "U", "MISS", "", 0 },
}

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
        for k = 1, #LOG do
            local r = LOG[k]
            local now = base + r[1] / 1000
            ctl.Tick(now)
            local kind = r[2]
            if kind == "S" then
                ctl.Fire("PLAYER_SWING", r[3], r[4])
            elseif kind == "C" then
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", r[3])
            else
                local act, flag, amount = r[3], r[4], r[5]
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
