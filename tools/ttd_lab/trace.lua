-- tools/ttd_lab/trace.lua (TTD lab run 4): replays TTDProbe 0.2.0 traces (central-needs/ttdprobe-020-report.md) the
-- way LibTimeToDie (forever 3c62b18be) feeds its estimator, and scores the answers against the real deaths.
-- One session: every fight of a file on one clock (`start` + `t`, rows in arrival order), one estimator throughout, so
-- a slope carries from fight to fight as it did live. The library's feeding: Restart on a target change and on a gone
-- stream; Band(t, lo, hi) per band with LHV's own t; at combat start a stream with no crossing and no anchor yet
-- restarts and takes its current band at that moment; Get every 0.1 s and in the frame after a band, target or combat
-- event; a sink call when the published death time or the state changes.
-- Death: the p=0 band time when the fight has one, else the gone time (the trace header's rule). Scored window: from
-- the later of the dying mob's first band and the last combat start, to the death; every read in it counts.
local T = {}

T.POLL, T.FRAME = 0.1, 0.017

local TARGET, BAND, COMBAT, GONE, LINE = 1, 2, 3, 4, 5
T.TARGET, T.BAND, T.COMBAT, T.GONE, T.LINE = TARGET, BAND, COMBAT, GONE, LINE

--- The session in a trace file: ev = { kind, t (absolute), a, b, fight } in arrival order (LINE: a = est or false,
--- b = reason); fights = { n, start, death (absolute or false), scoreFrom, endKind }.
function T.parse(path)
    local ev, fights, cur = {}, {}, nil
    local function add(kind, t, a, b)
        ev[#ev + 1] = { kind = kind, t = cur.start + t, a = a, b = b, fight = #fights }
    end
    for line in io.lines(path) do
        local n, start, endKind = line:match("^FIGHT (%d+) start=([%d.]+) .- end=(%a+)")
        if n then
            cur = { n = tonumber(n), start = tonumber(start), endKind = endKind, death = false, gone = false }
            fights[#fights + 1] = cur
        elseif cur then
            local t, rest = line:match("^t=([%d.]+) (.*)$")
            t = tonumber(t)
            if t then
                local lo, hi = rest:match("^p=(%d+) hi=(%d+)$")
                if lo then
                    add(BAND, t, tonumber(lo), tonumber(hi))
                    if tonumber(lo) == 0 and not cur.death then
                        cur.death = cur.start + t
                    end
                elseif rest:match("^target ") then
                    add(TARGET, t)
                elseif rest == "combat 1" then
                    add(COMBAT, t)
                elseif rest == "gone" then
                    add(GONE, t)
                    cur.gone = cur.start + t
                else
                    local est, reason = rest:match("^ttd=(%S+) .-reason=(%S+)$")
                    if est then
                        add(LINE, t, tonumber(est) or false, reason)
                    end
                end
            end
        end
    end
    for _, fi in ipairs(fights) do
        fi.death = fi.death or (fi.endKind == "gone" and fi.gone) or false
    end
    -- the scored window: the dying mob's stream starts after the last target/gone before its death
    for fi, F in ipairs(fights) do
        if F.death then
            local restartAt, firstBand, combatAt = -math.huge, nil, nil
            for _, e in ipairs(ev) do
                if e.t < F.death and e.fight <= fi then
                    if e.kind == TARGET or e.kind == GONE then
                        restartAt, firstBand = e.t, nil
                    elseif e.kind == BAND and not firstBand and e.t >= restartAt then
                        firstBand = e.t
                    elseif e.kind == COMBAT then
                        combatAt = e.t
                    end
                end
            end
            F.scoreFrom = math.max(firstBand or F.death, combatAt or -math.huge)
            F.streamFrom = restartAt
        end
    end
    return { ev = ev, fights = fights }
end

--- Replays a session into `make()` (a new estimator). Returns reads = { t, est (or false), lo, hi, state } in time
--- order, and sinks = { t, est, state } (the library's sink calls: published death time or state changed).
function T.replay(session, make)
    local e = make()
    local reads, sinks = {}, {}
    local clock, due, lastLo, lastHi = -math.huge, math.huge, nil, nil
    local pubSeen, stateSeen = nil, nil
    local function read(now)
        local est, lo, hi, state = e:Get(now)
        if est then
            state = "live:" .. state
        end
        reads[#reads + 1] = { t = now, est = est or false, lo = lo, hi = hi, state = state }
        local pub = est and e.tPub or false
        if pub ~= pubSeen or state ~= stateSeen then
            pubSeen, stateSeen = pub, state
            sinks[#sinks + 1] = { t = now, est = est or false, lo = lo, hi = hi, state = state }
        end
        due = now + T.POLL
    end
    local function advance(to) -- the driver's reads before `to`
        while due < to do
            read(due)
        end
    end
    for _, x in ipairs(session.ev) do
        local t = math.max(x.t, clock)
        if x.kind ~= LINE then
            advance(t)
            clock = t
            if x.kind == TARGET or x.kind == GONE then
                e:Restart()
                lastLo, lastHi = nil, nil
            elseif x.kind == BAND then
                e:Band(x.t, x.a, x.b)
                lastLo, lastHi = x.a, x.b
            elseif x.kind == COMBAT then
                if e.known and e.n == 0 and not e.t0 then
                    e:Restart()
                    if lastLo then
                        e:Band(t, lastLo, lastHi)
                    end
                end
            end
            due = math.min(due, t + T.FRAME)
        end
    end
    advance(clock + 1)
    return reads, sinks
end

--- The logged sink lines against a replay's sink calls: for each logged line, the replay's sink within 0.06 s with
--- the closest estimate. Returns matched, total, worst abs difference and a few misses (strings).
function T.oracle(session, sinks)
    local matched, total, worst, misses = 0, 0, 0, {}
    for _, x in ipairs(session.ev) do
        if x.kind == LINE and x.a then
            total = total + 1
            local best
            for _, s in ipairs(sinks) do
                if math.abs(s.t - x.t) <= 0.06 and s.est then
                    local d = math.abs(s.est - x.a)
                    best = (not best or d < best) and d or best
                end
            end
            if best and best <= 0.05 then
                matched = matched + 1
            elseif #misses < 20 then
                misses[#misses + 1] = string.format(
                    "F%d t=%.2f logged %.2f replay %s",
                    session.fights[x.fight].n,
                    x.t - session.fights[x.fight].start,
                    x.a,
                    best and string.format("off by %.2f", best) or "none"
                )
            end
            worst = math.max(worst, best or math.huge)
        end
    end
    return matched, total, worst, misses
end

--- The probe's own summary per fight over sink lines (logged: the LINE rows; replayed: the replay's sinks): live lines
--- of the dying stream with truth > 0; rel = |est - true| / true median and p90, inside [lo, hi] (logged lines: lo/hi
--- not parsed, nil), wrong side of 5 s. Returns { [fight n] = { n, med, p90, inside, wrong5 } }.
function T.probe(session, lines)
    local out = {}
    for _, F in ipairs(session.fights) do
        if F.death then
            local errs, inside, wrong = {}, 0, 0
            for _, x in ipairs(lines) do
                local tru = F.death - x.t
                if x.est and x.t >= F.streamFrom and tru > 0 then
                    errs[#errs + 1] = math.abs(x.est - tru) / tru
                    if x.lo and x.lo <= tru and tru <= x.hi then
                        inside = inside + 1
                    end
                    if (x.est > 5) ~= (tru > 5) then
                        wrong = wrong + 1
                    end
                end
            end
            out[F.n] = {
                n = #errs,
                med = T.quantile(errs, 0.5),
                p90 = T.quantile(errs, 0.9),
                inside = inside / math.max(1, #errs),
                wrong5 = wrong / math.max(1, #errs),
            }
        end
    end
    return out
end

local function q(list, p)
    if #list == 0 then
        return nil
    end
    local c = {}
    for i, v in ipairs(list) do
        c[i] = v
    end
    table.sort(c)
    return c[math.max(1, math.ceil(p * #c))]
end

T.quantile = q

--- Per fight (and pooled, index 0) scores of a replay's reads: rel (|est - true| / max(true, 2)), relP (the probe's,
--- / true), inside [lo, hi], wrong side of 5 and 8 s (unknown reads as long), unknown share, decision flips per minute
--- beyond the truth's own (5 and 8 s summed), first answer (s from the window's start), hi:lo median.
function T.score(session, reads)
    local out = {}
    local pool = {
        rel = {},
        relP = {},
        ratio = {},
        n = 0,
        ans = 0,
        inside = 0,
        w5 = 0,
        w8 = 0,
        flips = 0,
        time = 0,
        under = 0,
        dead = 0,
        late = 0,
    }
    for fi, F in ipairs(session.fights) do
        if F.death then
            local s = {
                rel = {},
                relP = {},
                ratio = {},
                n = 0,
                ans = 0,
                inside = 0,
                w5 = 0,
                w8 = 0,
                flips = 0,
                under = 0,
                dead = 0,
                late = 0,
            }
            local prev, prevT, first = {}, {}, nil
            for _, r in ipairs(reads) do
                if r.t >= F.scoreFrom and r.t < F.death then
                    local tru = F.death - r.t
                    s.n = s.n + 1
                    if r.est then
                        s.ans = s.ans + 1
                        first = first or r.t - F.scoreFrom
                        s.rel[#s.rel + 1] = math.abs(r.est - tru) / math.max(tru, 2)
                        s.relP[#s.relP + 1] = math.abs(r.est - tru) / tru
                        s.ratio[#s.ratio + 1] = r.hi / math.max(r.lo, 1e-3)
                        if r.lo <= tru and tru <= r.hi then
                            s.inside = s.inside + 1
                        end
                        if tru > 3 and r.est < 0.25 * tru then -- a live mob read as about to die
                            s.under = s.under + 1
                        end
                        if tru > 1 then -- read as dead (under 0.5 s) while it lives more than a second
                            s.late = s.late + 1
                            s.dead = s.dead + (r.est < 0.5 and 1 or 0)
                        end
                    end
                    for k, x in ipairs({ 5, 8 }) do
                        local dec, truth = r.est and r.est < x or false, tru < x
                        if dec ~= truth then
                            s[k == 1 and "w5" or "w8"] = s[k == 1 and "w5" or "w8"] + 1
                        end
                        if prev[k] ~= nil and prev[k] ~= dec then
                            s.flips = s.flips + 1
                        end
                        if prevT[k] ~= nil and prevT[k] ~= truth then
                            s.flips = s.flips - 1
                        end
                        prev[k], prevT[k] = dec, truth
                    end
                end
            end
            s.time = F.death - F.scoreFrom
            s.flips = math.max(0, s.flips)
            s.first = first
            s.fight = F.n
            out[#out + 1] = s
            for _, k in ipairs({ "rel", "relP", "ratio" }) do
                for _, v in ipairs(s[k]) do
                    pool[k][#pool[k] + 1] = v
                end
            end
            for _, k in ipairs({ "n", "ans", "inside", "w5", "w8", "flips", "time", "under", "dead", "late" }) do
                pool[k] = pool[k] + s[k]
            end
            s.index = fi
        end
    end
    out[0] = pool
    for i = 0, #out do
        local s = out[i]
        s.relMed, s.relP90 = q(s.rel, 0.5), q(s.rel, 0.9)
        s.relPMed, s.relPP90 = q(s.relP, 0.5), q(s.relP, 0.9)
        s.ratioMed, s.ratioP90 = q(s.ratio, 0.5), q(s.ratio, 0.9)
        s.deadShare = s.late > 0 and s.dead / s.late or 0
        s.cover = s.ans > 0 and s.inside / s.ans or 0
        s.underShare = s.ans > 0 and s.under / s.ans or 0
        s.unknown = s.n > 0 and 1 - s.ans / s.n or 0
        s.wrong5, s.wrong8 = s.w5 / math.max(1, s.n), s.w8 / math.max(1, s.n)
        s.flipsMin = s.time > 0 and math.max(0, s.flips) / (s.time / 60) or 0
    end
    return out
end

return T
