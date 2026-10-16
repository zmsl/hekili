-- tests/Virtual/harness/fixtures_spec.lua (harness design §3.5): every pasted log is a fixture, and the model's
-- defaults are fitted on the solo dual-wield logs (log 2, G5): the landing lags, the off hand's two references, the
-- avoid and crit rates, the amount envelope; and on every log, the order the client fires the tokens of one outcome. A
-- fit outside tolerance fails, and the defaults are retuned in the same change.
local drive = require("Virtual.harness.drive")
local observer = require("Virtual.harness.observer")
local behaviours = require("Virtual.harness.behaviours")
local entities = require("Virtual.harness.entities")

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
    local BANDS =
        { log2 = { w[1][1], w[1][2], w[2][1], w[2][2] }, log5 = require("Virtual.harness.fixtures.log5").damage }
    for _, name in ipairs({ "log2", "log5" }) do
        it("fits the observer's and behaviours' defaults to " .. name, function()
            local f = fit(require("Virtual.harness.fixtures." .. name), BANDS[name])
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
            local rows, groups = require("Virtual.harness.fixtures." .. name).rows, 0
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
