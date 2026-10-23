-- tests/Game/harness/fixtures_spec.lua (harness design §3.5): every pasted log is a fixture, and the model's
-- defaults are fitted on the solo dual-wield logs (log 2, G5): the landing lags, the off hand's two references, the
-- avoid and crit rates, the amount envelope; and on every log, the order the client fires the tokens of one outcome. A
-- fit outside tolerance fails, and the defaults are retuned in the same change.
local drive = require("Game.harness.drive")
local observer = require("Game.harness.observer")
local behaviours = require("Game.harness.behaviours")
local entities = require("Game.harness.entities")

local K, RATES = observer.DEFAULTS, behaviours.RATES
local CORE = { 0.43, 0.56 } -- the main hand's measured band (log 2's 435-552, G5's 436-556)

-- The log's own statistics: one row per outcome on the target; a white wound's hand by amount (a crit halved), the
-- lags of each hand, the off hand's reference (own swing within 30 ms of 0.703 s, the latest main swing at or before it
-- within 30 ms of 1.686 s, the main hit's frame, else the tail).
local function fit(fix, d)
    local s = drive.fixtureStream(fix, 10, true)
    local split = (d[4] + d[1]) / 2
    local f =
        { main = {}, own = {}, mref = {}, off = 0, frame = 0, swings = 0, avoids = 0, wounds = 0, crits = 0, out = 0 }
    local last, mainBefore, lastMainWound = { 0, 0 }, 0, -1
    for i = 1, s.n do
        local ev, t = s.ev[i], s.t[i]
        if ev == "PLAYER_SWING" then
            local h = s.a2[i] + 1
            last[h], f.swings = t, f.swings + 1
            if h == 2 then
                mainBefore = last[1]
            end
        elseif ev == "UNIT_COMBAT" and s.a5[i] == 1 then
            local act, flag, amount = s.a2[i], s.a3[i], s.a4[i]
            local a = flag == "CRITICAL" and amount / 2 or amount
            if act == "WOUND" and a >= 0.6 * d[3] then
                f.wounds, f.crits = f.wounds + 1, f.crits + (flag == "CRITICAL" and 1 or 0)
                local h = a > split and 1 or 2
                local lo, hi = d[2 * h - 1], d[2 * h]
                if a < (flag == "BLOCK_REDUCED" and 0 or lo) or a > hi then
                    f.out = f.out + 1
                end
                if h == 1 then
                    f.main[#f.main + 1], lastMainWound = t - last[1], t
                else
                    f.off = f.off + 1
                    if math.abs(t - last[2] - K.off.own) <= 0.03 then
                        f.own[#f.own + 1] = t - last[2]
                    elseif math.abs(t - mainBefore - K.off.main) <= 0.03 then
                        f.mref[#f.mref + 1] = t - mainBefore
                    elseif math.abs(t - lastMainWound) <= 0.0015 then
                        f.frame = f.frame + 1
                    end
                end
            elseif act == "MISS" or act == "DODGE" or act == "PARRY" then
                f.avoids = f.avoids + 1
            end
        end
    end
    return f
end

local function median(list)
    table.sort(list)
    return list[math.floor((#list + 1) / 2)]
end

local function near(want, got, tol, what)
    assert.is_true(math.abs(want - got) <= tol, ("%s: want %.3f +- %.3f, got %.3f"):format(what, want, tol, got))
end

describe("the fixtures and the model's fit", function()
    -- The amount bands the model swings with for each log: log 2 is the scenarios' default profile (level 22).
    -- shortcut: G5's gear has no model profile, so its bands are the session's own; add one when a scenario needs it.
    local w = entities.weapons(22)
    local BANDS = { log2 = { w[1][1], w[1][2], w[2][1], w[2][2] }, log5 = require("Game.harness.fixtures.log5").damage }
    for _, name in ipairs({ "log2", "log5" }) do
        it("fits the observer's and behaviours' defaults to " .. name, function()
            local f = fit(require("Game.harness.fixtures." .. name), BANDS[name])
            near(K.main.med, median(f.main), 0.025, "main median")
            local core = 0
            for _, lag in ipairs(f.main) do
                core = core + ((lag >= CORE[1] and lag <= CORE[2]) and 1 or 0)
            end
            near(1 - K.main.tail, core / #f.main, 0.10, "main core share")
            near(K.off.own, median(f.own), 0.015, "off own-reference median")
            near(K.off.main, median(f.mref), 0.015, "off main-reference median")
            near(K.off.pOwn, #f.own / f.off, 0.15, "off own-reference share")
            near(K.off.pMain, #f.mref / f.off, 0.15, "off main-reference share")
            assert.is_true((f.off - #f.own - #f.mref - f.frame) / f.off <= 0.15, "off tail share")
            near(RATES.miss + RATES.dodge + RATES.parry, f.avoids / f.swings, 0.06, "avoid rate")
            near(RATES.crit, f.crits / f.wounds, 0.05, "crit share")
            assert.are.equal(0, f.out) -- every white wound inside the configured ranges
        end)
    end

    it("fires the tokens of one outcome in the observer's order, in every log", function()
        for _, name in ipairs({ "log1", "log2", "log3", "log5" }) do
            local rows, groups = require("Game.harness.fixtures." .. name).rows, 0
            local prev
            for _, r in ipairs(rows) do
                if r[2] == "U" then
                    local same = prev
                        and r[1] - prev[1] <= 1
                        and r[4] == prev[4]
                        and r[5] == prev[5]
                        and r[6] == prev[6]
                    if same and r[3] ~= prev[3] then
                        assert.is_true(
                            observer.rank(prev[3]) <= observer.rank(r[3]),
                            ("%s at %d: %s before %s"):format(name, r[1], prev[3], r[3])
                        )
                        groups = groups + 1
                    end
                    prev = r
                end
            end
            assert.is_true(groups > 10, name)
        end
    end)
end)

describe("the fixtures replayed through Rows.lua", function()
    -- Replays fixture `name` (its token rows as recorded, or one row per outcome as "target" when `dedupe`).
    local function replay(name, dedupe)
        local fix = require("Game.harness.fixtures." .. name)
        local s = drive.fixtureStream(fix, 10, dedupe)
        local c = drive.boot()
        drive.run(c, s)
        drive.restore(c)
        return c, s
    end

    -- The stream index of the target's `act` of `amount` at `ms`.
    local function at(s, ms, act, amount)
        for i = 1, s.n do
            local hit = s.ev[i] == "UNIT_COMBAT" and s.a1[i] == "target" and s.a2[i] == act and s.a4[i] == amount
            if hit and math.abs(s.t[i] - 10 - ms / 1000) < 1e-6 then
                return i
            end
        end
        error(("no target %s %d at %d"):format(act, amount, ms))
    end

    it(
        "log 1: the strike frames' wounds are the casts', the DoT tick background, the crit 90 the main hand's",
        function()
            local c, s = replay("log1")
            assert.are.same({ 0, 0 }, { c.crHand[at(s, 4331, "WOUND", 77)], c.crHand[at(s, 6532, "WOUND", 84)] })
            assert.are.equal(2, c.rows.spell) -- SPELL_DAMAGE 77 and 84
            assert.are.equal(0, c.crHand[at(s, 5847, "WOUND", 13)])
            local crit = at(s, 2463, "WOUND", 90)
            assert.are.same({ 1, 12.110 }, { c.crHand[crit], c.crAt[crit] }) -- 353 ms after the main swing (P's reading)
            assert.is_true(c.crHand[at(s, 2463, "WOUND", 30)] ~= 1) -- background, or the off hand's (1.692 s after main)
        end
    )

    it("log 3: our 50 credited to the main hand; the partner's glancing, miss and strike frames background", function()
        local c, s = replay("log3")
        local ours = at(s, 165485, "WOUND", 50)
        assert.are.same({ 1, 175.116 }, { c.crHand[ours], c.crAt[ours] })
        assert.are.same({ 0, 0 }, { c.crHand[at(s, 165124, "WOUND", 4)], c.crHand[at(s, 165169, "MISS", 0)] })
        for i = 1, s.n do
            if s.t[i] >= 10 + 160.779 and s.ev[i] == "UNIT_COMBAT" and s.a5[i] ~= 1 then
                assert.are.equal(0, c.crHand[i]) -- the partner's school-8 spells
            elseif s.t[i] >= 10 + 174.816 and s.t[i] <= 10 + 205.518 then
                assert.are.equal(0, c.crHand[i]) -- segment C: we idle, his strike frames on nameplate2 included
            end
        end
    end)

    it("log 5 (G5): the main hand's 22 wounds, >= 18 of the off hand's 20, never the on-swing proc", function()
        local c, s = replay("log5", true)
        local main, off = 0, 0
        for i = 1, s.n do
            if s.ev[i] == "UNIT_COMBAT" and s.a2[i] == "WOUND" and s.a4[i] > 0 and c.crHand[i] > 0 then
                local a = s.a3[i] == "CRITICAL" and s.a4[i] / 2 or s.a4[i]
                assert.are.equal(1, s.a5[i]) -- the school-32 proc is no swing's
                local hand = a > 38 and 1 or 2
                main, off =
                    main + (hand == 1 and c.crHand[i] == 1 and 1 or 0),
                    off + (hand == 2 and c.crHand[i] == 2 and 1 or 0)
            end
        end
        assert.is_true(main == 22 and off >= 18, ("main %d/22 off %d/20"):format(main, off))
    end)
end)

describe("tools/vslog_fixture.lua", function()
    it("turns a /vslog dump into the fixture's rows, our spells and secrets named as the fixtures do", function()
        local dump = table.concat({
            "<pasted_content>",
            "     0 UNIT_SPELLCA player Cast-3-4615-1-2-100-7FFD244B25 100 nil nil",
            "   771 PLAYER_SWING 2.2000000476837 0 nil nil nil",
            "  1297 UNIT_COMBAT player PARRY  0 1",
            "  2463 UNIT_COMBAT target WOUND CRITICAL 90 1",
            "  4330 UNIT_SPELLCA player Cast-3-4615-1-2-4242-4C4F5AEFDD 4242 nil nil",
            " 49873 UNIT_SPELLCA party1 S S CastBar-9296D9AA6601D8FE nil",
            "vslog n=6 dropped=0",
        }, "\n")
        local rows = assert(loadfile("tools/vslog_fixture.lua"))("rows", dump, { ["4242"] = "STRIKE" })
        -- the payload decoder (unit-registry spec §6.3): castBar nil nil decodes as FAILED; a cast with no castGUID
        -- (another unit's secret cast) is not ours and is skipped
        local cast = "Cast-3-4615-1-2-100-7FFD244B25"
        assert.are.same({
            { 0, "SC", "FAILED", "player", cast, "OTHER", false, false },
            { 771, "S", 2.2, 0 },
            { 1297, "U", "player", "PARRY", "", 0, 1 },
            { 2463, "U", "target", "WOUND", "CRITICAL", 90, 1 },
            { 4330, "SC", "FAILED", "player", "Cast-3-4615-1-2-4242-4C4F5AEFDD", "STRIKE", false, false },
        }, rows)
        local log1 = require("Game.harness.fixtures.log1").rows -- its swing and outcome rows parse as before
        assert.are.same({ log1[2], log1[5] }, { rows[2], rows[3] })
    end)
end)
