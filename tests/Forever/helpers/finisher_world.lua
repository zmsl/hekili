-- tests/Forever/helpers/finisher_world.lua (lane finisher-miss, L1810, L1763): a missed 5-point Rip (and a missed Rake)
-- through the real Feral priority, the real belief and the fake client, with the client's events fired at their own
-- times and Hekili.Update run at the real driver's cadence (Engine/Driver.lua: a forced update waits 0.2 s, an unforced
-- one 0.5 s in combat). Each case asserts, over time from the cast: slot 1's sequence, when it returns to the missed
-- spell, that the finisher (Ferocious Bite) or the builder never shows while the bleed is truly down beyond the case's
-- information window, the believed bleed against the truth, energy and combo points, and that each change of slot 1
-- follows a fact. Tests only: a failing case is a finding for the controller, not fixed here.
-- The world is a scenario builder (Game/harness/scenario.lua, refactor lane 2): its queue, frames, swings, casts and rows;
-- this file keeps the truth (energy, points, the bleeds) and the Feral specifics.
local headless = require("Game.harness.headless")
local scenario = require("Game.harness.scenario")
local dlw = require("Forever.helpers.druid_loop_world")

local SWING = 1.0 -- the Feral world's main hand (druid_loop_world: weapon 1.0 s)
local REGEN = 10 -- energy a second (wowsims energy.go; the class file's regen)
local REFUND = 0.8 -- refundOnMiss (wowsims feral.go; the class file's refundOnAvoid)

-- The two bleeds: the rank the level-60 character casts (its aura's ID on the target and the viewer's), the pack aura's
-- base ID (the belief's key), the energy cost (Rake 40 - Ferocity 5/5), the combo points a landed cast leaves.
local BLEED = {
    rip = { cast = 9896, base = 1079, cost = 30, item = 951, cd = "rip" },
    rake = { cast = 9904, base = 1822, cost = 35, item = 950, cd = "rake" },
}

local M = {}

-- A Cat at level 60 in melee range of a level-60 mob; Faerie Fire left out of the kit (its debuff is the target's, a
-- line ahead of every bleed: not this spec's subject).
local function character()
    local c = dlw.Feral.character()
    local ff = {}
    for _, id in ipairs(dlw.Feral.IDS.faerie_fire) do
        ff[id] = true
    end
    local known = {}
    for _, id in ipairs(c.known) do
        if not ff[id] then
            known[#known + 1] = id
        end
    end
    c.known = known
    return c
end

-- One frame after its events: the VirtualState frame (the staged flush, the verdict's deadline wake), the timers
-- (headless.frame), and the driver's choice (Driver.lua:150-170).
local function frame(W, ft)
    local was = W.engine.criticalUpdate
    headless.frame(W.H, ft)
    if W.engine.criticalUpdate and not was then -- the verdict's deadline wake (or another belief edge) asked a cycle
        W.facts[#W.facts + 1] = { t = ft, what = "wake" }
    end
    local eng = W.engine
    eng.refreshTimer = (eng.refreshTimer or 0) + W.dt
    if eng.refreshTimer > (eng.criticalUpdate and 0.2 or (W.ctl.combat and 0.5 or 0.25)) then
        eng.criticalUpdate, eng.refreshTimer = false, 0
        local ok, err = xpcall(W.H.Hekili.Update, debug.traceback)
        assert(ok, err)
    end
end

--- A world: `o.viewer` "proven" (the Cooldown Manager tracks Rip and Rake, both proven by a landed cast) or false (no
--- item), `o.cdmOff` (the debug session switch), `o.plain` (UNIT_COMBAT amounts plain: the October beta; else secret,
--- live). The fight starts at W.t0 with our white swings every SWING s.
function M.world(o)
    o = o or {}
    local H = headless.new({
        character = character(),
        pack = dlw.Feral.PACK,
        beforeLogin = function(core)
            core.cdmOff = o.cdmOff == true
        end,
    })
    assert(#H.loadErrors == 0, table.concat(H.loadErrors, "; "))
    local W = scenario.new(H, { plain = o.plain, frame = frame })
    W.o, W.pubs, W.items = o, {}, {}
    W.S, W.VS, W.I = H.Hekili.State, H.ns.VirtualState, H.ns.VirtualStateInternal
    local ctl = H.ctl
    ctl.viewer.log = false
    if o.viewer then
        for _, k in ipairs({ "rip", "rake" }) do -- the items are this world's (W.items), never the shared table's
            local b = BLEED[k]
            ctl.viewer.sets[2][#ctl.viewer.sets[2] + 1] = b.item
            ctl.viewer.infos[b.item] = { spellID = b.cast }
            W.items[k] = ctl.ViewerItem("BuffIconCooldownViewer", #ctl.viewer.sets[2], b.item)
        end
        H.Fire("COOLDOWN_VIEWER_DATA_LOADED")
    end
    ctl.inRange.target, ctl.level.target, ctl.distance.target = true, 60, 3
    ctl.power[3] = nil -- energy: secret, as live
    ctl.power[4] = 0 -- combo points: plain (UnitPower(player, 4) in combat, 2026-10-18)
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(H.Hekili.Engine.Subscribe("Primary", function(_, _, out)
        local r, t = out.recs[1], ctl.now
        local p = M.belief(W, t)
        p.t, p.name, p.wait = t, r and r.actionName or false, r and r.time or 0
        p.raw, p.held = out.rawName and out.rawName[1] or p.name, out.held and out.held[1] or false -- the steady hold's
        p.trueE, p.trueCp, p.trueUp = M.energyAt(W, t), W.cp, { rip = W.up.rip ~= nil, rake = W.up.rake ~= nil }
        W.pubs[#W.pubs + 1] = p
    end))
    W.engine = H.ns.EngineFrame
    W.vsFrame = W.I.Events.frame
    -- the truth
    W.energy, W.eT, W.cp = 100, ctl.now, 0
    W.up = {} -- [bleed] = true expiry while truly up
    W.t0 = ctl.now + 0.5
    return W
end

-- The true energy at t.
function M.energyAt(W, t)
    return math.min(100, W.energy + REGEN * (t - W.eT))
end
local function setEnergy(W, t, v)
    W.energy, W.eT = math.min(100, v), t
end

--- Schedules `fn(W, t)` at world time t (a fact named `what` unless `bg`, a background event).
function M.at(W, t, what, fn, bg)
    W:at(t, what, fn, bg)
end

--- Runs the world to time t.
function M.run(W, t)
    W:run(t)
end

-- The client's events -------------------------------------------------------------------------------------------------

-- The plain combo points read n (or n(W) then) at t, the truth with it.
local function points(W, t, n, name)
    W:power(t, 4, n, {
        name = name or "points",
        set = function(W2, v)
            W2.cp = v
        end,
    })
end
-- The aura edge as the observer fires it: the list entry (raising in combat), UNIT_AURA, the viewer 4 ms later.
local function auraEdge(W, t, b, up)
    local B = BLEED[b]
    M.at(W, t, b .. (up and " up" or " down"), function(W2)
        W2:fire("UNIT_AURA", "target")
    end)
    local it = W.items[b]
    if it then
        M.at(W, t + 0.004, b .. (up and " lit" or " dark"), function(W2)
            if up then
                W2.ctl.ViewerAura(it, "target", B.cast)
            else
                W2.ctl.ViewerClear(it)
            end
        end)
    end
end

--- Our white swings from `from` every SWING s until `to`: PLAYER_SWING, its row (a wound) scenario.LAND s later
--- (background).
--- `odd` ({ at, act, lag }) changes the one swing at `at`: its row `act` (a wound or an avoid) `lag` s after it.
function M.swings(W, from, to, odd)
    local t = from
    while t <= to do
        local act, lag = "WOUND", scenario.LAND
        if odd and math.abs(t - odd.at) < 1e-6 then
            act, lag = odd.act, odd.lag
        end
        W:swing(t, { speed = SWING, act = act, lag = lag })
        t = t + SWING
    end
end

--- Our cast of bleed `b` succeeding at t: SENT 0.08 s before, the success, then its outcome. `c.act` WOUND (landed) or
--- an avoid; `c.row` the outcome row's time from the success (nil: no row; negative: logged before the success). A landed
--- Rip deals no direct damage, so it has no row (wowsims rip.go: CalcAndDealOutcome; the world's rip press is an effect
--- only); a landed Rake's row is its initial hit (rake.go CalcAndDealDamage). Landed: the combo points 2 ms after the
--- success (Rip spends all, Rake adds one), the aura edge 11 ms after (its viewer light 4 ms later: about the measured
--- 15 ms), the ticks (a wound row each tick_time: Rip 2 s, Rake 3 s) and the run-out. Avoided: 80% of the cost back at
--- once, the combo points kept (rip.go spends them only when it lands). `c.gain`: the points a landed Rake adds (1;
--- 2 with Blood Frenzy's point on its crit, wowsims talents_feral_combat.go:146).
function M.cast(W, t, b, c)
    local B = BLEED[b]
    W:cast(t, B.cast, {
        name = b,
        act = c.act,
        row = c.row,
        success = function(W2, tt)
            setEnergy(W2, tt, M.energyAt(W2, tt) - B.cost)
        end,
    })
    if c.act == "WOUND" then
        points(W, t + (c.cpLag or 0.002), function(W2) -- `c.gain` 2: Blood Frenzy's crit point
            return b == "rip" and 0 or math.min(5, W2.cp + (c.gain or 1))
        end, b .. " points")
        local exp = t + (b == "rip" and 12 or 9)
        M.at(W, t, b .. " applied", function(W2)
            W2.up[b] = exp
        end, true)
        auraEdge(W, t + 0.011, b, true)
        auraEdge(W, exp, b, false)
        local tick = b == "rip" and 2 or 3
        for k = tick, exp - t + 1e-6, tick do
            W:row(t + k, "WOUND", { name = b .. " tick", amount = 30, bg = true })
        end
        M.at(W, exp, b .. " expired", function(W2)
            if W2.up[b] == exp then
                W2.up[b] = nil
            end
        end, true)
    else
        M.at(W, t, b .. " refund", function(W2, tt)
            setEnergy(W2, tt, M.energyAt(W2, tt) + REFUND * B.cost)
        end, true)
    end
end

-- Reads ---------------------------------------------------------------------------------------------------------------

--- The belief's view at t: { energy = {est, lo, hi}, cp, rip = expiry or false, rake = ... } (sampled at each publish
--- into W.pubs, with the truth: trueE, trueCp, trueUp[bleed]).
function M.belief(W, t)
    local e = W.VS.Power(3, t)
    local p = W.VS.Power(4, t)
    local out = { energy = e and { e.est, e.lo, e.hi } or false, cp = p and p.est or false }
    for b, B in pairs(BLEED) do
        local a = W.VS.Aura("target", B.base, t)
        out[b] = a and a.est or false
    end
    return out
end

--- Slot 1's publishes from t on: { {t, name}, ... } with only the changes kept (the first one always).
function M.seq(W, from)
    local out, last = {}, nil
    for _, p in ipairs(W.pubs) do
        if p.t >= from and p.name ~= last then
            out[#out + 1] = { t = p.t, name = p.name }
            last = p.name
        end
    end
    return out
end

function M.seqString(seq, t0)
    local s = {}
    for _, p in ipairs(seq) do
        s[#s + 1] = ("%+.3f %s"):format(p.t - t0, tostring(p.name))
    end
    return table.concat(s, ", ")
end

-- The prelude every case shares: in combat at t0, our swings running (one of them at T + `o.swingAt`, default -0.9,
-- its row `o.odd` = { act, lag } when given); a landed Rip and Rake (lit when a viewer tracks them: their items proven);
-- both run out. For `o.bleed` "rip" (default) the Rake is recast and 5 combo points; for "rake" 2 points (builders not
-- modelled: the points are plain). Energy is full at the case's cast time T = t0 + M.CAST_AT (returned).
M.CAST_AT = 18
function M.prelude(W, o)
    o = o or {}
    local t0 = W.t0
    local T = t0 + M.CAST_AT
    M.at(W, t0, "combat", function(W2)
        W2.ctl.combat = true
        W2.H.Fire("PLAYER_REGEN_DISABLED")
    end)
    local swingAt = o.swingAt or -0.9
    local first = t0 + 0.1 + (M.CAST_AT + swingAt - 0.1) % SWING
    M.swings(W, first, T + 15, o.odd and { at = T + swingAt, act = o.odd.act, lag = o.odd.lag })
    points(W, t0 + 0.3, 5)
    M.cast(W, t0 + 0.5, "rip", { act = "WOUND" }) -- runs out at t0 + 12.5
    M.cast(W, t0 + 1.5, "rake", { act = "WOUND", row = 0.004 }) -- runs out at t0 + 10.5
    points(W, t0 + 2.0, 2)
    if (o.bleed or "rip") == "rip" then
        M.cast(W, t0 + 13.5, "rake", { act = "WOUND", row = 0.004 }) -- up through the case (to T + 4.5)
        points(W, t0 + 14.0, 5)
    end
    return T
end

--- One case: the world (`c.viewer`, `c.cdmOff`, `c.plain`), the prelude (`c.bleed`, `c.swingAt`, `c.odd`), then our
--- cast of c.bleed at T with `c.act`, its row at `c.row` (nil: none) and its points `c.gain`, a tick at `c.tickAt`, the
--- missing point's fact at `c.pointFact`, run to T + `c.span` (3.5). Returns W, T.
function M.case(c)
    local W = M.world(c)
    local T = M.prelude(W, c)
    M.run(W, T - 0.5)
    local b = c.bleed or "rip"
    W.bleed = b
    M.cast(W, T, b, { act = c.act, row = c.row, gain = c.gain })
    if c.tickAt then -- a bleed's tick (a background white wound) at T + c.tickAt
        W:row(T + c.tickAt, "WOUND", { name = "tick", amount = 30, bg = true })
    end
    if c.pointFact then -- the point that never came: a fact once no read shows it by then (L1832 PT_AVOID)
        M.at(W, T + c.pointFact, "no point", function() end)
    end
    if c.pointsAt then -- builders not modelled: the plain points come back
        points(W, T + c.pointsAt[1], c.pointsAt[2])
    end
    M.run(W, T + 0.05)
    -- the verdict's window of the record our cast wrote (Auras.lua: max(W0, travel + TOL))
    W.verdictW = W.I.auraVerdict.W[W.I.AURA_UNIT + W.I.auras.bySpell[BLEED[b].base]]
    M.run(W, T + (c.span or 3.5))
    return W, T
end

-- Checks ---------------------------------------------------------------------------------------------------------------

-- The icons a missed bleed must not leave in slot 1 past the window: Rip's finisher, Rake's builders.
M.WRONG = { rip = { ferocious_bite = true }, rake = { shred = true, claw = true } }
local function fmtE(p)
    return p.energy and ("%.1f [%.1f, %.1f]"):format(p.energy[1], p.energy[2], p.energy[3]) or "none"
end

--- The case's timeline from T - 0.2 for a failure message: slot 1 by publish (shown, raw when the hold differs), the
--- believed and true bleed, energy and points, then the facts.
function M.timeline(W, T, to)
    local b = W.bleed or "rip"
    local out = {}
    for _, p in ipairs(W.pubs) do
        if p.t >= T - 0.2 and p.t <= T + (to or 3.5) then
            out[#out + 1] = ("  %+.3f %s%s | %s bel %s true %s | E bel %s true %.1f | cp bel %s true %d"):format(
                p.t - T,
                tostring(p.name),
                p.raw ~= p.name and (" (raw " .. tostring(p.raw) .. ")") or "",
                b,
                p[b] and ("%.2f"):format(p[b] - T) or "down",
                tostring(p.trueUp[b]),
                fmtE(p),
                p.trueE,
                tostring(p.cp),
                p.trueCp
            )
        end
    end
    local f = {}
    for _, x in ipairs(W.facts) do
        if x.t >= T - 0.2 and x.t <= T + (to or 3.5) then
            f[#f + 1] = ("%+.3f %s"):format(x.t - T, x.what)
        end
    end
    out[#out + 1] = "  facts: " .. table.concat(f, "; ")
    return table.concat(out, "\n")
end

--- The checks of one case (`c.window`: seconds after the information time the belief may lag; `c.info`: that time
--- from T, default the later of the success and the row). Returns the failures (empty: pass) and a summary
--- { back (slot 1's first return to the bleed, s from T, or false), wrongLast (the last wrong icon's publish) }.
--- A miss: past the window slot 1 never shows a wrong icon (shown or raw), its first publish there is the bleed, the
--- belief holds the bleed down, its energy band holds the truth, its combo points equal the truth. A land (the mirror):
--- the belief holds the bleed up, the energy band holds the truth, slot 1 never shows the bleed while it is up. Each
--- change of slot 1 within T - 0.2 .. T + 3.5 has a fact (not a background swing, row or tick) since the change before.
function M.check(W, T, c)
    local b, fails = c.bleed or "rip", {}
    local missed = c.act ~= "WOUND"
    local info = T + (c.info or math.max(0, c.row or 0))
    local from = info + (c.window or 0)
    local first, back, wrongLast = true, false, false
    local function fail(s)
        if #fails < 8 then
            fails[#fails + 1] = s
        end
    end
    local before -- not vacuous: slot 1 shows the bleed before the cast
    for _, p in ipairs(W.pubs) do
        if p.t < T then
            before = p.name
        end
    end
    if before ~= b then
        fail("slot 1 shows " .. tostring(before) .. " before the cast, not " .. b)
    end
    for _, p in ipairs(W.pubs) do
        if p.t > T and p.name == b and not back and missed then
            back = p.t - T
        end
        if p.t > T and missed and (M.WRONG[b][p.name] or M.WRONG[b][p.raw]) then
            wrongLast = p.t - T
        end
        if p.t >= from and p.t <= T + (c.span or 3.5) then
            local at = ("%+.3f"):format(p.t - T)
            local trueUp = p.trueUp[b]
            local belUp = p[b] ~= false and p[b] > p.t
            if missed then
                if M.WRONG[b][p.name] then
                    fail(at .. " slot 1 shows " .. p.name .. " while " .. b .. " is down")
                elseif M.WRONG[b][p.raw] then
                    fail(at .. " the engine picks " .. p.raw .. " while " .. b .. " is down")
                end
                if first and p.name ~= b then
                    fail(at .. " the first publish past the window shows " .. tostring(p.name) .. ", not " .. b)
                end
            elseif p.name == b and trueUp then
                fail(at .. " slot 1 shows " .. b .. " while it is up")
            end
            if belUp ~= trueUp then
                fail(at .. " the belief holds " .. b .. (belUp and " up" or " down") .. ", the truth the other")
            end
            if not p.energy or p.trueE < p.energy[2] - 0.5 or p.trueE > p.energy[3] + 0.5 then
                fail(at .. " energy " .. fmtE(p) .. " misses the truth " .. ("%.1f"):format(p.trueE))
            end
            if p.t >= T + 0.01 and p.cp ~= p.trueCp then
                fail(at .. " combo points " .. tostring(p.cp) .. ", truth " .. p.trueCp)
            end
            first = false
        end
    end
    -- `c.expect` { { dt, name }, ... }: the first publish after T + dt shows `name` (the controls: the right icon is
    -- reachable, so a case cannot pass by showing nothing wrong)
    for _, e in ipairs(c.expect or {}) do
        for _, p in ipairs(W.pubs) do
            if p.t > T + e[1] then
                if p.name ~= e[2] then
                    fail(("%+.3f slot 1 shows %s, not %s"):format(p.t - T, tostring(p.name), e[2]))
                end
                break
            end
        end
    end
    -- the flicker rule (memory no-jittery-recommendations): each change follows a fact since the change before
    local lastChange, lastName = nil, nil
    for _, p in ipairs(W.pubs) do
        if p.t >= T - 0.2 and p.t <= T + 3.5 then
            if lastName ~= nil and p.name ~= lastName then
                local found = false
                for _, f in ipairs(W.facts) do
                    if f.t > (lastChange or T - 0.2) and f.t <= p.t then
                        found = true
                        break
                    end
                end
                if not found then
                    fail(
                        ("%+.3f slot 1 changes %s -> %s with no fact since %+.3f"):format(
                            p.t - T,
                            tostring(lastName),
                            tostring(p.name),
                            (lastChange or T - 0.2) - T
                        )
                    )
                end
                lastChange = p.t
            end
            lastName = p.name
        end
    end
    return fails, { back = back, wrongLast = wrongLast }
end

return M
