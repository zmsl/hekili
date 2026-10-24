-- tests/Forever/druid_harness_spec.lua (GCD kinds design §4, D9): the Druid in the combat harness, through the real
-- VirtualState and Rows.lua, its content from tests/Forever/helpers/druid_world.lua: solo bear (the rage model), solo
-- cat (energy secret, combo points plain), the shift fight (the stale caches, GCD kinds across shifts, resources on
-- entry), the Furor variants and Enrage's decay pause. The gates in make check (#slow) run a tenth of the design's
-- fights; the design's counts run behind make test-druid (#druid). Each gate prints its tally line, which is also its
-- failure message.
local dw = require("Forever.helpers.druid_world")
local metrics = require("Game.harness.metrics")

local function count(t, key, v)
    t[key] = (t[key] or 0) + (v or 1)
end
local function most(t, key, v)
    t[key] = math.max(t[key] or -math.huge, v)
end
local function least(t, key, v)
    t[key] = math.min(t[key] or math.huge, v)
end

-- One line of a tally's numbers, sorted by name (rounded to 3 places).
local function line(name, t, m)
    local keys, out = {}, {}
    for k, v in pairs(t) do
        if type(v) == "number" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        out[#out + 1] = k .. "=" .. math.floor(t[k] * 1000 + 0.5) / 1000
    end
    return name .. ": " .. table.concat(out, " ") .. (m and ("; " .. metrics.line(m)) or "")
end

-- The GCD tally of a fight: every press's GCD seen at its start, owned, its end's error; both edge orders counted.
local function gcd(t, f)
    local g = metrics.gcd(f.c, f.W)
    count(t, "gcds", g.n)
    count(t, "gcdSeen", g.seen)
    count(t, "ownerless", g.ownerless)
    count(t, "gcdExtra", g.extra)
    most(t, "gcdErr", g.errMax)
    for _, ev in ipairs(f.W.truth) do
        if ev.kind == "cast" and ev.order then
            count(t, "order" .. ev.order)
        end
    end
end

-- The first tick of capture `rk` after time `t`: its index.
local function after(rk, t)
    for k = 1, rk.n do
        if rk.t[k] > t then
            return k
        end
    end
end

--- §4.1 solo bear over `n` fights: the credits (metrics.score at the bear step), crits staged, Mauls, the GCDs; and
--- the overshoot windows of the same fights without answers (the model's drift alone: `driftRaw` every window a step
--- over, `driftOver` those that end with the belief above the truth).
local function bear(n)
    local t, m, drift = {}, metrics.new(), metrics.new()
    dw.fights("bear", n, {}, function(f)
        local c, s, W = f.c, f.s, f.W
        metrics.score(m, c, s, W, f.R.swing)
        local crits, staged, false3 = metrics.crits(c, s)
        count(t, "crits", crits)
        count(t, "staged", staged)
        count(t, "false3", false3)
        local maul = dw.press("maul", f.R).spell
        for _, ev in ipairs(W.truth) do
            if ev.kind == "strike" and ev.src == W.ents[1] then
                count(t, "strikes")
                -- an avoided strike in the frame of another cast of ours can be nobody's (Rows.lua: an avoid with
                -- another cast of ours pending pairs with neither), so it may have no row; back to exact (maulRows ==
                -- strikes) when that central gap lands (such an avoid paired, its refund kept)
                if ev.act ~= "WOUND" then
                    for _, o in ipairs(W.truth) do
                        if o.kind == "cast" and o.src == ev.src and math.abs(o.t - ev.t) < 0.01 then
                            count(t, "strikesShared")
                            break
                        end
                    end
                end
            end
        end
        count(t, "maulRows", ((f.rows.SPELL_DAMAGE or {})[maul] or 0) + ((f.rows.SPELL_MISSED or {})[maul] or 0))
        count(t, "maulPaid", (f.rows.SPELL_CAST_SUCCESS or {})[maul] or 0)
        gcd(t, f)
    end)
    dw.fights("bear", n, { usable = false }, function(f)
        local c, W = f.c, f.W
        metrics.score(drift, c, f.s, W, f.R.swing)
        -- a window the belief ends above the truth in: a window that starts with the belief far below it can rise a
        -- step past the truth's change only by the floor at 0 (a Maul's 15 paid from 4 believed), never above it
        for w = 1, c.nWin - 1 do
            local a, b = c.winT[w], c.winT[w + 1]
            local err = (c.win[w + 1] - c.win[w]) - (metrics.truthAt(W, b) - metrics.truthAt(W, a))
            if err >= f.R.swing and c.win[w + 1] > metrics.truthAt(W, b) then
                count(t, "driftOver")
            end
        end
    end)
    t.danger, t.driftRaw, t.driftWindows, t.driftOver = m.danger, drift.over, drift.windows, t.driftOver or 0
    return t, m
end

--- §4.2 solo cat over `n` fights (variant `v`: regenAfter, regenRead): energy from `from` seconds on, rage, points,
--- the GCDs; the main hand's credits as the pairing report.
local function cat(n, v, from)
    local t, m = {}, metrics.new()
    dw.fights("cat", n, v, function(f)
        local c, s, W = f.c, f.s, f.W
        metrics.score(m, c, s, W, f.R.swing)
        local e = metrics.power(c, W, dw.ENERGY, 5, { after = from })
        count(t, "energyMean", e.meanAbs / n)
        most(t, "energyMax", e.maxAbs)
        count(t, "energyOver", e.over)
        count(t, "windows", e.windows)
        most(t, "rageErr", metrics.power(c, W, dw.RAGE, 0).maxAbs)
        local p = metrics.power(c, W, dw.POINTS, 0.5)
        count(t, "pointsTicks", p.settled)
        count(t, "pointsExact", p.exact * p.settled)
        gcd(t, f)
    end)
    t.pairing = metrics.rate(m, 1)
    return t, m
end

--- §4.3-§4.4 the shift fight over `n` fights (variant `v`: onEnter): by form section, the credits, the share scored on
--- timing alone, the rage belief's overshoot in Bear; the believed minus the true rage right after each Bear entry
--- (`bearEntryOver`, `bearEntryUnder`: the rage zeroed in both, or a swing landing after it paid both), the energy error at each
--- Cat entry and the time until it is within 5; the swing value; the GCDs.
local function shift(n, v)
    local t, mBear, mCat = {}, metrics.new(), metrics.new()
    dw.fights("shift", n, v, function(f)
        local c, s, W = f.c, f.s, f.W
        local formAt = dw.formAt(W, dw.CAT)
        local function inBear(x)
            return formAt(x) == dw.BEAR
        end
        local function inCat(x)
            return formAt(x) == dw.CAT
        end
        metrics.score(mBear, c, s, W, f.R.swing, 0, inBear)
        metrics.score(mCat, c, s, W, f.R.swing, 0, inCat)
        -- in combat only: after the stop the client re-reads UnitDamage in Bear, so a late row is not stale
        local nb, ub = metrics.unknown(c, s, function(x)
            return inBear(x) and x < W.stopAt
        end)
        local nc, uc = metrics.unknown(c, s, inCat)
        count(t, "bearWounds", nb)
        count(t, "bearUnknown", ub)
        count(t, "catWounds", nc)
        count(t, "catUnknown", uc)
        local r = metrics.power(c, W, dw.RAGE, f.R.swing, { keep = inBear })
        count(t, "rageOver", r.over)
        count(t, "rageMean", r.meanAbs / n)
        most(t, "rageOverMax", r.overMax)
        local e = metrics.power(c, W, dw.ENERGY, 5)
        count(t, "energyOver", e.over)
        count(t, "energyMean", e.meanAbs / n)
        most(t, "swingMax", f.swingValues.max) -- D4: every swing the rage belief pays at the form's fixed 2.5 s
        least(t, "swingMin", f.swingValues.min)
        local rk, ek = c.trk[dw.RAGE], c.trk[dw.ENERGY]
        local rageAt, energyAt = metrics.truthOf(W, dw.RAGE), metrics.truthOf(W, dw.ENERGY)
        for _, ev in ipairs(W.truth) do
            if ev.kind == "form" and ev.form == dw.BEAR then -- a swing landing just after the entry pays both
                local k = after(rk, ev.t)
                most(t, "bearEntryOver", rk.est[k] - rageAt(rk.t[k]))
                least(t, "bearEntryUnder", rk.est[k] - rageAt(rk.t[k]))
            elseif ev.kind == "form" and ev.form == dw.CAT then
                local k = after(ek, ev.t)
                local err = math.abs(ek.est[k] - energyAt(ek.t[k]))
                count(t, "catEntries")
                count(t, "entryErr", err)
                while k < ek.n and math.abs(ek.est[k] - energyAt(ek.t[k])) > 5 do
                    k = k + 1
                end
                count(t, "fixSeconds", ek.t[k] - ev.t)
            end
        end
        gcd(t, f)
    end)
    t.entryErr, t.fixSeconds = t.entryErr / t.catEntries, t.fixSeconds / t.catEntries
    return t, mBear, mCat
end

--- §4.5 the decay after a fight ending in Bear with Enrage up, over `n` fights (variant `v`: pausedBy, declared): the
--- believed change of rage since 1.5 s after the stop (our last swings landed) minus the true change, at every second.
local function decay(n, v)
    local t = {}
    dw.fights("decay", n, v, function(f)
        local c, W = f.c, f.W
        local rk, at = c.trk[dw.RAGE], metrics.truthOf(W, dw.RAGE)
        least(t, "rageAtStop", at(W.stopAt))
        local base = after(rk, W.stopAt + 1.5)
        local e0, v0 = rk.est[base], at(rk.t[base])
        local low = 0
        for k = base, rk.n do
            local x = rk.t[k] - W.stopAt
            if rk.t[k] <= W.t and math.abs(x - math.floor(x + 0.5)) < 0.05 then
                local err = (rk.est[k] - e0) - (at(rk.t[k]) - v0)
                most(t, "errMax", err)
                least(t, "errMin", err)
                low = math.min(low, err)
            end
        end
        count(t, "lowFights", low < -1.25 and 1 or 0)
    end)
    return t
end

local function gcdGate(t, msg)
    assert.is_true(t.gcdSeen == t.gcds and t.gcdExtra == 0 and t.gcdErr <= 0.01, msg)
    assert.is_true(t.ownerless == 0 and t.order1 > 0 and t.order2 > 0, msg)
end

-- The gates (§4.6), each at `k` x the design's fights.
local GATES = {
    bear = function(k)
        local t, m = bear(200 * k)
        local msg = line("solo bear", t, m)
        print(msg)
        assert.is_true(metrics.rate(m, 1) >= 0.94 and m.wrong[1] == 0 and metrics.falsePer100(m) == 0, msg)
        assert.is_true(t.driftOver == 0 and t.danger == 0, msg)
        local shared = t.strikesShared or 0 -- the narrow tolerance above: exact again with the central Rows.lua fix
        assert.is_true(t.strikes > 0 and t.maulRows <= t.strikes and t.maulRows >= t.strikes - shared, msg)
        assert.is_true(t.maulPaid == t.strikes, msg)
        assert.is_true(t.staged >= 0.94 * t.crits and t.false3 == 0, msg)
        gcdGate(t, msg)
    end,
    cat = function(k)
        local t, m = cat(200 * k, {}, 0)
        local msg = line("solo cat", t, m)
        print(msg) -- the white pairing at a 1.0 s period: reported
        assert.is_true(t.rageErr == 0, msg)
        assert.is_true(t.energyMean <= 10 and t.energyOver <= 0.02 * t.windows, msg)
        assert.is_true(t.pointsExact == t.pointsTicks, msg)
        gcdGate(t, msg)
    end,
    regenAfter = function(k)
        local t, m = cat(100 * k, { regenAfter = { s = 5, k = 1.25 } }, 21)
        local msg = line("solo cat, regenAfter 5 s x 1.25", t, m)
        print(msg)
        assert.is_true(t.energyMean <= 15 and t.energyOver <= 0.05 * t.windows, msg)
    end,
    reload = function(k)
        local t, m = cat(50 * k, { regenRead = false }, 0)
        print(line("solo cat, a /reload in combat (no regen read)", t, m)) -- report only: sizes the shortcut
    end,
    shift = function(k)
        local t, mBear, mCat = shift(100 * k, {})
        local msg = line("shift fight", t, mBear) .. " | Cat sections: " .. metrics.line(mCat)
        print(msg)
        assert.is_true(metrics.rate(mBear, 1) >= 0.85, msg)
        assert.is_true(metrics.falsePer100(mBear) == 0 and metrics.falsePer100(mCat) == 0, msg)
        assert.is_true(t.catUnknown == 0 and t.bearUnknown == t.bearWounds and t.bearWounds > 0, msg)
        assert.is_true(
            t.rageOver == 0 and math.abs(t.swingMin - 11.25) < 1e-9 and math.abs(t.swingMax - 11.25) < 1e-9,
            msg
        )
        assert.is_true(t.bearEntryOver <= 1.3, msg) -- no rage carried into Bear: a swing at the calibrated scale at most
        gcdGate(t, msg)
    end,
    furor = function(k)
        local variants = {
            { "Cat entry zero", { cat = { [dw.ENERGY] = "zero" } } },
            {
                -- Furor's Cat restore (the energy left plus 10 a second out of Cat) is what the world's regen in every
                -- form already gives: the Cat entry keeps
                "Furor rank 5",
                {
                    bear = {
                        [dw.RAGE] = function()
                            return 10 -- 20% a rank of 10 rage: rank 5 always
                        end,
                    },
                },
            },
        }
        for _, x in ipairs(variants) do
            local t, mBear = shift(50 * k, { onEnter = x[2] })
            local msg = line("shift fight, " .. x[1], t, mBear)
            print(msg) -- report: the error at each Cat entry and the time a usability pin takes to correct it
            assert.is_true(t.rageOver == 0 and t.bearEntryOver <= 1.3, msg) -- Bear's rage never an overshoot
        end
    end,
    decay = function(k)
        for _, v in ipairs({
            { pausedBy = true, declared = true },
            { pausedBy = false, declared = false },
        }) do
            local t = decay(20 * k, v)
            local msg = line(("decay, paused %s, declared %s"):format(tostring(v.pausedBy), tostring(v.declared)), t)
            print(msg)
            -- no fight low (errMin >= -1.25 is lowFights == 0): Enrage's expiry tick, once lost against the decay's
            -- first quantum (seed 15), kept since ffc300da
            assert.is_true(t.errMax <= 1.25 and t.errMin >= -1.25, msg)
        end
        local over = decay(20 * k, { pausedBy = false, declared = true })
        local overMsg = line("decay, a declared pause over a decaying truth", over)
        print(overMsg) -- the dangerous sign: up to 1.25 x 7 rage above the truth
        assert.is_true(over.errMax > 1.25 and over.errMin >= -1.25, overMsg)
        local under = decay(20 * k, { pausedBy = true, declared = false })
        local underMsg = line("decay, no declaration over a pausing truth", under)
        print(underMsg) -- the safe sign: below the truth
        assert.is_true(under.errMin < -1.25 and under.errMax <= 1.25, underMsg)
    end,
}

describe("the shift fight's usability answers", function()
    it("answers the Cat spenders short in Cat after a Bear section (seed 1: the 61.05 Cat entry)", function()
        dw.fights("shift", 1, {}, function(f)
            local W, s, R = f.W, f.s, f.R
            local spenders = {}
            for _, key in ipairs({ "claw", "shred", "rake", "rip", "ferocious_bite", "shifting_power" }) do
                spenders[dw.press(key, R).spell] = true
            end
            local entry, leave -- the second Cat entry and the next shift
            for _, ev in ipairs(W.truth) do
                if ev.kind == "form" and ev.form == dw.CAT and ev.t > 31 and not entry then
                    entry = ev.t
                elseif ev.kind == "form" and entry and not leave then
                    leave = ev.t
                end
            end
            assert.is_true(math.abs(entry - 61.05) < 1e-6, tostring(entry))
            local short = 0
            for i = 1, s.n do
                if s.ev[i] == "@usable" and spenders[s.a1[i]] and s.a2[i] == 2 then
                    short = short + ((s.t[i] >= entry and s.t[i] < leave) and 1 or 0)
                end
            end
            assert.is_true(short > 0)
        end)
    end)
end)

describe("Druid harness scenarios, a tenth of the fights (GCD kinds design §4.6) #slow", function()
    for _, name in ipairs({ "bear", "cat", "regenAfter", "reload", "shift", "furor", "decay" }) do
        it(name, function()
            GATES[name](0.1)
        end)
    end
end)

describe("Druid harness scenarios at the design's fight counts (GCD kinds design §4.6) #druid", function()
    for _, name in ipairs({ "bear", "cat", "regenAfter", "reload", "shift", "furor", "decay" }) do
        it(name, function()
            GATES[name](1)
        end)
    end
end)
