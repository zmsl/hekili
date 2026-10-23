-- tests/Game/harness/detect_sweep_spec.lua (unit-registry spec §6.2's invariant sweep, #slow): every detection kind in
-- every band (gated and measured), K17's /reload, and seeds over lag x jitter x density x partner phase, asserting on
-- every fight, whatever the score: a row pays at most one ticket; no ticket is paid past what it owed (T.overpaid);
-- every opened ticket is closed once or still open (conservation over every close of §3.6); no payment crosses GUIDs;
-- no outcome is dispatched twice and every dispatch lands on a row; no TICKS payment shifts its schedule by more than
-- one slot. Prints the metric surface per cell.
local detect = require("Game.harness.detect")
local scenarios = require("Game.harness.scenarios")
local drive = require("Game.harness.drive")
local metrics = require("Game.harness.metrics")

local BANDS = {}
for _, b in ipairs(detect.GATED) do
    BANDS[#BANDS + 1] = b
end
for _, b in ipairs(detect.MEASURED) do
    BANDS[#BANDS + 1] = b
end

local KINDS = {}
for k in pairs(detect.KINDS) do
    KINDS[#KINDS + 1] = k
end
table.sort(KINDS)

-- every close reason counted once (spec §3.6), summed over a cell's fights for its printed surface
local function tally(sum, c)
    local T, U = c.I.Tickets, c.I.Units
    sum.opened = (sum.opened or 0) + T.opened
    for why, v in pairs(T.closed) do
        sum[why] = (sum[why] or 0) + v
    end
    sum.unitDup = (sum.unitDup or 0) + U.dup
    sum.unresolved = (sum.unresolved or 0) + U.unresolved
    sum.evicted = (sum.evicted or 0) + U.evicted
    local pays = 0
    for i = 1, c.stream.n do
        pays = pays + c.payN[i]
    end
    sum.rowPays = (sum.rowPays or 0) + pays -- payments inside a dispatch: the GUID check's sample
    sum.tickShift = math.max(sum.tickShift or 0, c.tickShift)
end

local function surface(sum)
    local keys = {}
    for k in pairs(sum) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        out[#out + 1] = k .. "=" .. sum[k]
    end
    return table.concat(out, " ")
end

--- The invariants of one fight (drive captures `c` over stream `s`).
local function invariants(c, s, where)
    local T = c.I.Tickets
    local n = 0
    -- One outcome is the observer's run of rows pushed together: same time, unit and payload, each token once (twins
    -- from two sources repeat the tokens; a source-less row, a partner strike's WOUND 0, has no actor to tell them
    -- apart). unit: each token's last GUID (metrics.tickets' grouping: a cleared token's late rows too).
    local unit, key, toks, disp = {}, nil, {}, 0
    for i = 1, s.n do
        if s.ev[i] == "@guid" and s.a2[i] then
            unit[s.a1[i]] = s.a2[i]
        end
        assert(c.payN[i] <= 1, where .. ": row " .. i .. " paid " .. c.payN[i] .. " tickets")
        assert(c.disp[i] <= 1, where .. ": row " .. i .. " dispatched " .. c.disp[i] .. " times")
        n = n + c.disp[i]
        if s.ev[i] == "UNIT_COMBAT" then
            local k = string.format(
                "%.4f/%s/%s/%s/%s/%s/%s/%s/%s",
                s.t[i],
                tostring(unit[s.a1[i]]),
                s.a2[i],
                tostring(s.a3[i]),
                tostring(s.a4[i]),
                tostring(s.a5[i]),
                tostring(s.castT[i]),
                tostring(s.actor[i]),
                tostring(s.hand[i])
            )
            if k ~= key or toks[s.a1[i]] then
                key, toks, disp = k, {}, 0
            end
            toks[s.a1[i]], disp = true, disp + c.disp[i]
            assert(disp <= 1, where .. ": outcome dispatched twice at " .. s.t[i])
        end
    end
    assert(n == c.rowsOut, where .. ": " .. c.rowsOut .. " dispatches, " .. n .. " on rows")
    assert(T.overpaid == 0, where .. ": " .. T.overpaid .. " payments past owed")
    local closed, open = 0, 0
    for _, v in pairs(T.closed) do
        closed = closed + v
    end
    for i = 1, T.CAP do
        open = open + (T.state[i] ~= T.FREE and 1 or 0)
    end
    assert(T.opened == closed + open, ("%s: opened %d, closed %d + open %d"):format(where, T.opened, closed, open))
    assert(c.crossGUID == 0, where .. ": " .. c.crossGUID .. " payments across GUIDs")
    assert(c.tickShift <= 1, where .. ": a TICKS payment shifted its schedule " .. c.tickShift .. " slots")
end

describe("the invariant sweep #slow", function()
    for _, kind in ipairs(KINDS) do
        for _, band in ipairs(BANDS) do
            it(kind .. " in " .. band, function()
                local sum, f = {}, 0
                local m = detect.run(kind, band, 3, 201, function(c, s)
                    f = f + 1
                    invariants(c, s, kind .. " " .. band .. " fight " .. f)
                    tally(sum, c)
                end)
                assert.are.equal(m.fights, f)
                print(("\nsweep %s %s: %s | %s"):format(kind, band, metrics.ticketLine(m), surface(sum)))
            end)
        end
    end

    it("K17's /reload: both registries", function()
        local c1, c2, half, rest = detect.reload("K17", "party", 3)
        invariants(c1, half, "K17 reload first half")
        invariants(c2, rest, "K17 reload second half")
    end)

    -- the mixed sweep: every spell type at once, lag, jitter and a lockstep partner's phase over every band
    local SPELLS = {}
    for t = 2, 58, 2 do
        SPELLS[#SPELLS + 1] = { t, ({ "instant", "bolt", "doti", "ticks", "unmapped" })[(t / 2) % 5 + 1] }
    end
    local seed = 0
    for _, jitter in ipairs({ 0, 0.05 }) do
        for _, band in ipairs(BANDS) do
            for _, phase in ipairs({ 0, 0.1, 0.5 }) do
                seed = seed + 1
                local s0 = seed
                it(("jitter %.2f %s phase %.1f"):format(jitter, band, phase), function()
                    local others = {}
                    for i, x in ipairs(detect.BANDS[band].others) do
                        others[i] = x
                    end
                    others[#others + 1] = "lockstep"
                    local o = {
                        duration = 60,
                        spells = SPELLS,
                        others = others,
                        phase = phase,
                        jitter = jitter,
                        sessionLag = true,
                        distance = 25,
                        extraMobs = 1,
                        switchTo = { { 21, 2 }, { 37, 1 } },
                        churn = { 7, 0.4 },
                    }
                    if s0 % 2 == 0 then -- FAST DUAL-WIELD (K14f's shape) on every other seed
                        o.weapons, o.haste = { { 40, 54, 1.5 }, { 40, 54, 1.5 } }, 1.2
                    end
                    local s, W = scenarios.stream(o, s0)
                    local c = drive.boot({ boot = detect.boot })
                    drive.run(c, s)
                    local m = metrics.tickets(metrics.newTickets(), c, s, W)
                    local sum = {}
                    tally(sum, c)
                    print(("\nsweep %d: %s | %s"):format(s0, metrics.ticketLine(m), surface(sum)))
                    invariants(c, s, "mixed seed " .. s0)
                    drive.restore(c)
                end)
            end
        end
    end
end)
