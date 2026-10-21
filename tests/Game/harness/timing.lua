-- tests/Game/harness/timing.lua (docs/superpowers/specs/2026-10-16-headless-recommendation-loop.md §12): how close a
-- replay's recommendation shows an ability ready to when wowsims casts it. Fed by two hooks: replay.lua's `new` (each
-- decision's ready class from the log: what wowsims waited for) and loop.lua's per-poll step (our queue and the power
-- band against the truth). `rows` gives one row per decision: the shown offset b (gated), the predicted offset a, the
-- class, the tolerance verdict and, at cost-gated decisions, lo - truth and est - truth. Class-neutral: keys, pools and
-- costs come from the log and the instance.
local M = {}

-- The tolerances (design §3). REACT: loop.REACT (a first icon with this wait or less is shown ready); EDGE: float
-- slack at a window's edge; G7: the client's usability lag (observer.DEFAULTS.usableDelay, UNMEASURED); HOLD: the
-- belief's deliberate pending-swing hold (Events/Rows.lua ORACLE_MIN); TICK: a ticked pool's tick (State.lua
-- tick_rate); reaction and queue: the request's reactionTimeMs and queueDelay (the caller's, seconds).
M.P = { REACT = 0.05, EDGE = 1e-3, G7 = 0.1, HOLD = 0.1, TICK = 0.1, reaction = 0, queue = 0 }

M.SWING = 3 -- wowsims's OtherID of a white swing (a power line from it is swing-paid)
local GCD_TOL, CD_TOL = 1.5e-3, 0.02 -- a cast "at" a GCD end or crossing; at a cooldown end (log times are 0.01 s)

--- Classifies each decision of replay `R` from the log's events `ev` (replay.parse's, with `wt`), in place: d.lt (log
--- time), d.cls ("prepull" | "first" | "gcd" | "cost" | "cooldown" | "aura" | "slack" | "queue" | "landing"),
--- d.cost, d.pt (the pool's power type, `POWER` by name) and d.swing (the crossing came from a white swing). `keyFor`
--- and `cd` are the replay's. Returns the recorder T { decisions, polls, costed = { [key] = pt }, pools, pull }.
function M.new(R, ev, keyFor, cd, POWER)
    local T = { decisions = R.decisions, polls = {}, costed = {}, pools = {}, pull = R.pull }
    local ci, prevEnd, lastAt, queued, first = 0, -math.huge, {}, {}, false
    for i, e in ipairs(ev) do
        local key = e.kind == "casting" and keyFor(e)
        if key then
            ci = ci + 1
            local d = R.casts[ci]
            d.lt, d.cost = e.t, e.cost or 0
            -- the pool: the name of the cast's own spend line, before its next Casting line (a hard cast pays at its end)
            for j = i + 1, #ev do
                local f = ev[j]
                if f.kind == "casting" and f.id == e.id then
                    break
                elseif f.kind == "power" and f.id == e.id and f.to < f.from then
                    d.pt = POWER[f.name]
                    break
                end
            end
            -- the cost crossing: the latest line of that pool before the cast that took it from below the cost to it
            local cross, pool = -math.huge, nil
            for j = i - 1, (d.pt and d.cost > 0) and 1 or i, -1 do
                local f = ev[j]
                if f.kind == "power" and POWER[f.name] == d.pt then
                    if f.to < d.cost - 1e-6 then
                        cross = math.huge -- below the cost before the cast: paid some other way
                        break
                    elseif f.from < d.cost - 1e-6 then
                        cross, pool = f.t, f
                        break
                    end
                end
            end
            d.swing = pool ~= nil and pool.other == M.SWING
            local aura = false
            for j = i - 1, 1, -1 do
                if ev[j].t ~= e.t then
                    break
                end
                aura = aura or ev[j].kind == "aura"
            end
            local cdEnd = lastAt[key] and (cd[key] or 0) > 0 and lastAt[key] + cd[key] or -math.huge
            local ready = math.max(prevEnd, cdEnd, cross < math.huge and cross or -math.huge)
            if e.t < 0 then
                d.cls = "prepull"
            elseif not d.gcd then
                if (e.tag == 1) and d.cost == 0 then
                    d.cls, queued[key] = "queue", true
                elseif queued[key] and not e.tag then
                    d.cls, queued[key] = "landing", nil
                end
            elseif not first then
                d.cls, first = "first", true
            end
            if not d.cls then
                if math.abs(cross - e.t) < GCD_TOL and cross >= ready - GCD_TOL then
                    d.cls = "cost"
                elseif math.abs(cdEnd - e.t) < CD_TOL then
                    d.cls = "cooldown"
                elseif math.abs(prevEnd - e.t) < GCD_TOL then
                    d.cls = "gcd"
                else
                    d.cls = aura and "aura" or "slack"
                end
            end
            if d.pt and d.cost > 0 then
                T.costed[key], T.pools[d.pt] = d.pt, true
            end
            lastAt[key] = e.t
        end
        if e.kind == "casting" and ((e.gcd or 0) > 0 or (e.cast or 0) > 0) then
            prevEnd = e.t + math.max(e.gcd, e.cast)
        end
    end
    return T
end

--- loop.run's per-poll hook: instance `H`'s queue just after its cycle at world time `t` (names, waits, off-GCD
--- flags) and, for each pool a decision spends, the belief's lo and est minus world `W`'s truth. A poll earlier than the
--- last starts a new run.
function M.poll(T, t, H, W)
    local last = T.polls[#T.polls]
    if last and t < last.t then
        T.polls = {}
    end
    local out, ab = H.Hekili.Engine.Output.Primary, H.Hekili.Class.abilities
    local p = { t = t, name = {}, wait = {}, off = {}, n = out.count }
    for i = 1, out.count do
        local r = out.recs[i]
        local a = ab[r.actionName]
        p.name[i], p.wait[i], p.off[i] = r.actionName, r.time or 0, (a and a.gcd == "off") or false
    end
    local us = W.ents[1]
    for pt in pairs(T.pools) do
        if pt == us.pt or us.res[pt] then
            local b = H.ns.VirtualState.Power(pt, H.ctl.now) -- the cycle's own `now`: the same answer it read
            local truth = W.res(us, pt)
            p[pt] = { b.lo - truth, b.est - truth }
        end
    end
    T.polls[#T.polls + 1] = p
end

-- A poll's pick for decision `d`: our first on-GCD icon (an on-GCD decision), else `d`'s key anywhere; name, wait.
local function pick(p, d)
    for i = 1, p.n do
        if d.gcd and not p.off[i] then
            return p.name[i], p.wait[i]
        elseif not d.gcd and p.name[i] == d.key then
            return p.name[i], p.wait[i]
        end
    end
end

local function r3(x) -- rounded to 0.001 (the fixture's grain)
    return x and tonumber(("%.3f"):format(x)) or nil
end

--- The verdict of a row's class `cls` and shown offset `b` under tolerances `P` ("scope" | "never" | "in:<window>" |
--- "early" | "late"); `tie`: a not-shown decision that swaps with its neighbour.
function M.verdict(cls, b, swing, tie, P)
    local e = P.EDGE
    if cls == "prepull" or cls == "first" or cls == "landing" then
        return "scope"
    elseif b == nil then
        return tie and "in:tie" or "never"
    elseif math.abs(b) <= P.REACT + e then
        return "in:grain"
    elseif cls == "cost" and b > 0 and b <= P.G7 + (swing and P.HOLD or P.TICK) + e then
        return "in:cost"
    elseif (cls == "aura" or cls == "slack") and b < 0 and b >= -(P.reaction + P.REACT) - e then
        return "in:reaction"
    elseif cls == "queue" and b >= 0 and b <= P.queue + e then
        return "in:queue"
    end
    return b < 0 and "early" or "late"
end

--- One row per decision (R.decisions' order): { t (log s), key, class, "on" | "off", b, a, verdict, lo - truth,
--- est - truth } rounded to 0.001. b: an icon shown ready at the decision poll, the first poll since the previous
--- decision's that showed it so, minus the cast (<= 0); shown waiting, its wait (exact: the poll is at the cast);
--- otherwise nil (not shown). a: the last poll before the decision's, its wait for the key plus its time minus the cast.
--- lo and est: cost-gated rows only, at the decision poll. Also sets T.flips: { lo, est } at each in-combat poll whose
--- first on-GCD icon changed to or from a costed key.
function M.rows(T, P)
    P = P or M.P
    local polls, rows, j, prevDec, fg = T.polls, {}, 1, 0, {}
    for i, d in ipairs(T.decisions) do
        while polls[j + 1] and polls[j + 1].t <= d.t + 1e-9 do
            j = j + 1
        end
        local p = polls[j]
        local b, a
        local name, wait = pick(p, d)
        if name == d.key and wait <= P.REACT then
            local k = j
            while k > prevDec do
                local n2, w2 = pick(polls[k], d)
                if n2 ~= d.key or w2 > P.REACT then
                    break
                end
                b, k = polls[k].t - d.t, k - 1
            end
        elseif name == d.key then
            b = wait
        end
        local pr = polls[j - 1]
        for s = 1, pr and pr.n or 0 do
            if pr.name[s] == d.key then
                a = pr.t + pr.wait[s] - d.t
                break
            end
        end
        local band = d.cls == "cost" and d.pt and p[d.pt]
        fg[i] = pick(p, { gcd = true })
        rows[i] = {
            r3(d.lt),
            d.key,
            d.cls,
            d.gcd and "on" or "off",
            r3(b),
            r3(a),
            false,
            band and r3(band[1]) or nil,
            band and r3(band[2]) or nil,
        }
        rows[i].swing = d.swing
        prevDec = j
    end
    -- the near-tie: a not-shown on-GCD decision whose neighbour on-GCD decision swaps keys with it
    local on = {}
    for i, d in ipairs(T.decisions) do
        if d.gcd then
            on[#on + 1] = i
        end
    end
    for n, i in ipairs(on) do
        local tie = false
        for _, m in ipairs({ on[n - 1], on[n + 1] }) do
            local x = T.decisions[m]
            tie = tie or (fg[i] == x.key and fg[m] == T.decisions[i].key)
        end
        rows[i].tie = tie
    end
    for _, r in ipairs(rows) do
        r[7] = M.verdict(r[3], r[5], r.swing, r.tie, P)
    end
    T.flips = {}
    local prev
    for _, p in ipairs(polls) do
        local x = pick(p, { gcd = true })
        if p.t >= T.pull and prev ~= nil and x ~= prev then
            local pt = T.costed[x] or T.costed[prev]
            if pt and p[pt] then
                T.flips[#T.flips + 1] = p[pt]
            end
        end
        prev = x or false
    end
    return rows
end

local function quantile(list, q)
    local s = {}
    for i, v in ipairs(list) do
        s[i] = v
    end
    table.sort(s)
    return s[math.max(1, math.ceil(q * #s))] or 0
end

local function bandOf(list, i) -- median signed and p90 of |x| of column `i` of `list`
    local v, a = {}, {}
    for n, x in ipairs(list) do
        v[n], a[n] = x[i], math.abs(x[i])
    end
    return quantile(v, 0.5), quantile(a, 0.9)
end

--- A pack's summary of `rows` (and T.flips): on-GCD in-scope rows (not "scope"): n, timed, never, raw median and p90
--- |b|, early and late counts beyond REACT, the real ones (early, late, median |b|: the floored one), absorbed per
--- window, by class { n, median |b| }, the top 3 keys by real count, the cost-gated band (lo and est minus the truth:
--- median, p90 |.|) at decisions and at flips, and the off-GCD rows (n, real, median |b| of real).
function M.summary(rows, flips, P)
    P = P or M.P
    local s = { n = 0, timed = 0, never = 0, early = 0, late = 0, scope = 0, absorbed = {}, class = {}, keys = {} }
    local raw, real, cost, offReal = {}, {}, {}, {}
    s.off = 0
    for _, r in ipairs(rows) do
        local b, v = r[5], r[7]
        if r[4] == "off" then
            s.off = s.off + (v == "scope" and 0 or 1)
            if v == "early" or v == "late" then
                offReal[#offReal + 1] = math.abs(b)
            end
        elseif v == "scope" then
            s.scope = s.scope + 1
        else
            s.n = s.n + 1
            if b == nil then
                s.never = s.never + (v == "never" and 1 or 0)
            else
                s.timed = s.timed + 1
                raw[#raw + 1] = math.abs(b)
                s.early = s.early + (b < -(P.REACT + P.EDGE) and 1 or 0)
                s.late = s.late + (b > P.REACT + P.EDGE and 1 or 0)
                local c = s.class[r[3]] or { n = 0, b = {} }
                c.n, c.b[#c.b + 1] = c.n + 1, math.abs(b)
                s.class[r[3]] = c
            end
            local w = v:match("^in:(.*)")
            if w then
                s.absorbed[w] = (s.absorbed[w] or 0) + 1
            elseif v ~= "never" then
                real[#real + 1] = math.abs(b)
                s[v .. "Real"] = (s[v .. "Real"] or 0) + 1
                local k = s.keys[r[2]] or { n = 0, max = 0 }
                k.n, k.max = k.n + 1, math.max(k.max, math.abs(b))
                s.keys[r[2]] = k
            end
            if r[8] then
                cost[#cost + 1] = { r[8], r[9] }
            end
        end
    end
    s.median, s.p90 = quantile(raw, 0.5), quantile(raw, 0.9)
    s.real, s.realMedian = #real, quantile(real, 0.5)
    s.offReal, s.offMedian = #offReal, quantile(offReal, 0.5)
    s.cost, s.flips = cost, flips or {}
    return s
end

local function sorted(t)
    local list = {}
    for k in pairs(t) do
        list[#list + 1] = k
    end
    table.sort(list)
    return list
end

--- The per-spec summary line (appended after the replay gate's own).
function M.line(s)
    local abs, cls, top = {}, {}, {}
    for _, w in ipairs(sorted(s.absorbed)) do
        abs[#abs + 1] = w .. " " .. s.absorbed[w]
    end
    for _, c in ipairs(sorted(s.class)) do
        cls[#cls + 1] = ("%s %d %.3f"):format(c, s.class[c].n, quantile(s.class[c].b, 0.5))
    end
    local keys = sorted(s.keys)
    table.sort(keys, function(x, y)
        local a, b = s.keys[x], s.keys[y]
        return a.n > b.n or (a.n == b.n and (a.max > b.max or (a.max == b.max and x < y)))
    end)
    for i = 1, math.min(3, #keys) do
        top[i] = ("%s %d max %.2f"):format(keys[i], s.keys[keys[i]].n, s.keys[keys[i]].max)
    end
    local cm, cp = bandOf(s.cost, 1)
    local em, ep = bandOf(s.cost, 2)
    local fm, fp = bandOf(s.flips, 1)
    local gm, gp = bandOf(s.flips, 2)
    return (
        "ready on-GCD %d timed %d never %d scope %d; |b| median %.3f p90 %.3f; early %d late %d; "
        .. "real %d (early %d late %d) median %.3f; absorbed [%s]; by class [%s]; top [%s]; "
        .. "cost-gated lo-truth %.1f p90 %.1f est-truth %.1f p90 %.1f (%d), flips lo-truth %.1f p90 %.1f "
        .. "est-truth %.1f p90 %.1f (%d); off-GCD %d real %d median %.3f"
    ):format(
        s.n,
        s.timed,
        s.never,
        s.scope,
        s.median,
        s.p90,
        s.early,
        s.late,
        s.real,
        s.earlyReal or 0,
        s.lateReal or 0,
        s.realMedian,
        table.concat(abs, ", "),
        table.concat(cls, ", "),
        table.concat(top, "; "),
        cm,
        cp,
        em,
        ep,
        #s.cost,
        fm,
        fp,
        gm,
        gp,
        #s.flips,
        s.off,
        s.offReal,
        s.offMedian
    )
end

local function lit(v)
    return v == nil and "nil" or type(v) == "string" and ('"' .. v .. '"') or ("%.3f"):format(v)
end

--- Writes `rows` as a fixture at `path` (one row per decision), `head` its first comment line.
function M.write(path, rows, head)
    local f = assert(io.open(path, "w"))
    f:write("-- ", head, "\n")
    f:write(
        "-- { t_cast (log s), key, class, gcd, b shown offset, a predicted offset, verdict, lo-truth, est-truth }\n"
    )
    f:write("return {\n")
    for _, r in ipairs(rows) do
        local cells = {}
        for i = 1, 9 do
            cells[i] = lit(r[i])
        end
        f:write("    { ", table.concat(cells, ", "), " },\n")
    end
    f:write("}\n")
    f:close()
end

return M
