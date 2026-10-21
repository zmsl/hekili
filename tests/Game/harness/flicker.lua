-- tests/Game/harness/flicker.lua (headless loop design §5.1, the flicker ledger): what moved on the displayed slots
-- tick to tick, and why, from per-tick frames loop.lua records (one frame per instance: the queue's first three
-- positions, Primary's numIcons, and the focus entry; their waits and costs; the belief's power band; the cooldowns
-- of the shown abilities) and the world's events between two polls (shared by the instances on one world). Pure:
-- no instance, no world; flicker_spec.lua drives it on synthetic frames. Class-neutral: abilities are names.
--
-- Kinds, per slot: a DIP (the slot's icon leaves and returns within WINDOW ticks), a FLASH (an icon appears and
-- leaves within WINDOW ticks, the slot moving on to another), a RETRACTED READY (the slot's icon shown ready, within
-- WINDOW ticks shown waiting again), a WAIT oscillation (the same icon's wait jumping up more than one poll's worth
-- above its countdown: the snap-back; a wait that falls early is a gain arriving, not counted). The cause class is read from the belief and the events at the change's two polls, first match:
-- press (our cast or a spend), avoid (an avoid of ours), credit (a provisional credit vetoed: the estimate fell with
-- no spend, or a pending swing ended with no credit), usability (an answer cut the floor, the estimate steady: G7),
-- cooldown (a believed cooldown of either icon moved off its countdown), aura (an aura or form edge), swing (a swing
-- of ours, or a pending one at either poll: the swing window), near-tie (the two icons' waits within one poll at the
-- earlier poll), unknown. A press, an avoid or an aura change justifies a change; the gates count the rest.
local M = {}

M.WINDOW = 5 -- ticks (1 s at 5 Hz): an episode ends within this or is not one
M.SLOTS = 4 -- queue positions 1-3 (Primary's numIcons) and the focus entry
M.FOCUS = 4
M.EVENTS = { "cast", "spend", "avoid", "aura", "swing" }
local EPS = 1e-6
local JUSTIFIED = { press = true, avoid = true, aura = true }

--- The world's events between two polls, by in-combat tick: one table per run, shared by its instances' frames.
function M.events()
    local ev = {}
    for _, k in ipairs(M.EVENTS) do
        ev[k] = {}
    end
    return ev
end

--- An empty frame over the run's events `ev`: per slot name, wait, cost (in the character's power, 0 otherwise); per
--- tick lo, est, hi (the belief), truth (the world's power), pend (a swing pending: GAP AK), cd ({ [name] = believed
--- cooldown remaining } for the abilities shown this tick or the last), gcd (the world's GCD remaining), t.
function M.frame(ev)
    local f = { n = 0, name = {}, wait = {}, cost = {}, ev = ev }
    for s = 1, M.SLOTS do
        f.name[s], f.wait[s], f.cost[s] = {}, {}, {}
    end
    f.lo, f.est, f.hi, f.truth, f.pend, f.cd, f.gcd, f.t = {}, {}, {}, {}, {}, {}, {}, {}
    return f
end

local function waitOf(f, i, x)
    for s = 1, M.SLOTS do
        if f.name[s][i] == x then
            return f.wait[s][i]
        end
    end
    return nil
end

local function event(f, c)
    local ev = f.ev
    return ev.cast[c] or ev.spend[c] or ev.avoid[c] or ev.aura[c]
end

-- The cause class of a change between polls p and c (= p + 1) involving icons a (before) and b (after).
local function cause(f, p, c, a, b, tick)
    local ev = f.ev
    if ev.cast[c] or ev.spend[c] then
        return "press"
    elseif ev.avoid[c] then
        return "avoid"
    elseif f.est[c] < f.est[p] - EPS or (f.pend[p] and not f.pend[c] and f.est[c] <= f.est[p] + EPS) then
        return "credit"
    elseif f.lo[c] < f.lo[p] - EPS then
        return "usability"
    end
    for _, x in ipairs({ a, b }) do
        local cp, cc = x and f.cd[p][x], x and f.cd[c][x]
        if cp and cc and math.abs(cc - math.max(0, cp - tick)) > tick + EPS then
            return "cooldown"
        end
    end
    if ev.aura[c] then
        return "aura"
    elseif ev.swing[c] or f.pend[p] or f.pend[c] then
        return "swing"
    end
    local wa, wb = a and waitOf(f, p, a), b and waitOf(f, p, b)
    if a ~= b and wa and wb and math.abs(wa - wb) <= tick + EPS then
        return "near-tie"
    end
    return "unknown"
end

-- The engine's stated wait after a retraction of `x` in slot `s` at poll c: its cooldown, its cost, the GCD, else a
-- condition (an aura, an APL line).
local function reason(f, s, c, x, react, tick)
    local w, cd, k = f.wait[s][c], f.cd[c][x], f.cost[s][c]
    if cd and cd > react and cd >= w - tick then
        return "cooldown"
    elseif k > 0 and f.lo[c] < k then
        return "cost"
    elseif f.gcd[c] > react and f.gcd[c] >= w - tick then
        return "gcd"
    end
    return "condition"
end

--- The ledger of frame `f` (o: tick, react, window): { entries, gapLo, gapEst }. Each entry { kind, slot, tick (the
--- change's poll), from, to, len (ticks), cause, justified, lo, est, truth (at the change), cost (the slot's, 0:
--- not cost-gated), floor (the floor crossed the cost while the estimate stayed above it: floor jitter); a retracted
--- one adds ready (its first ready tick), wait and reason }. gapLo/gapEst: lo - truth and est - truth at every
--- cost-gated decision (the first icon's cost inside the belief's band, lo < cost <= hi) and every change of a
--- cost-gated slot.
function M.ledger(f, o)
    local tick, react, W = o.tick, o.react, o.window or M.WINDOW
    local led = { entries = {}, gapLo = {}, gapEst = {} }
    local n = f.n
    for i = 1, n do
        local k = f.cost[1][i]
        if k > 0 and f.lo[i] < k and k <= f.hi[i] then
            led.gapLo[#led.gapLo + 1], led.gapEst[#led.gapEst + 1] = f.lo[i] - f.truth[i], f.est[i] - f.truth[i]
        end
    end
    local function add(e, s, p, c)
        e.slot, e.tick = s, c
        e.cause = e.cause or cause(f, p, c, e.from, e.to, tick)
        e.justified = e.justified or JUSTIFIED[e.cause] or false
        e.lo, e.est, e.truth = f.lo[c], f.est[c], f.truth[c]
        local k = f.cost[s][p] > 0 and f.cost[s][p] or f.cost[s][c]
        e.cost, e.floor = k, false
        if k > 0 then
            e.floor = (f.lo[p] >= k) ~= (f.lo[c] >= k) and f.est[p] >= k and f.est[c] >= k
            led.gapLo[#led.gapLo + 1], led.gapEst[#led.gapEst + 1] = e.lo - e.truth, e.est - e.truth
        end
        led.entries[#led.entries + 1] = e
    end
    for s = 1, M.SLOTS do
        local name, wait = f.name[s], f.wait[s]
        -- icon changes: dips and flashes
        local i = 2
        while i <= n do
            local a, b = name[i - 1], name[i]
            if a ~= b then
                local j = nil
                for k = i + 1, math.min(n, i + W) do
                    if name[k] == a then
                        j = k
                        break
                    end
                end
                if j then
                    add({ kind = "dip", from = a, to = b, len = j - i }, s, i - 1, i)
                    i = j + 1
                else
                    local e = i
                    while e < n and name[e + 1] == b do
                        e = e + 1
                    end
                    if e - i + 1 <= W and e < n then
                        add({ kind = "flash", from = a, to = b, len = e - i + 1 }, s, i - 1, i)
                    end
                    i = e + 1
                end
            else
                i = i + 1
            end
        end
        -- readiness and waits of the same icon
        local since = nil -- the current ready run's first tick
        for c = 1, n do
            local x = name[c]
            local ready = x and wait[c] <= react
            local p = c - 1
            local same = p >= 1 and name[p] == x and x
            if ready and not (same and wait[p] <= react) then
                since = c
            elseif same and not ready and wait[p] <= react then
                if since and c - since <= W then
                    local len = 0
                    while c + len <= n and name[c + len] == x and wait[c + len] > react do
                        len = len + 1
                    end
                    local just = false
                    for k = since + 1, c do
                        just = just or event(f, k)
                    end
                    add({
                        kind = "retracted",
                        from = x,
                        to = x,
                        len = len,
                        ready = since,
                        wait = wait[c],
                        reason = reason(f, s, c, x, react, tick),
                        justified = just,
                    }, s, p, c)
                end
            elseif same and wait[c] > math.max(0, wait[p] - tick) + tick + EPS and not event(f, c) then
                add({ kind = "wait", from = x, to = x, len = 1 }, s, p, c)
            end
        end
    end
    return led
end

--- Ledgers merged across fights (`into` nil: a new one; `led` nil: none).
function M.merge(into, led)
    into = into or { entries = {}, gapLo = {}, gapEst = {} }
    for _, key in ipairs({ "entries", "gapLo", "gapEst" }) do
        for _, x in ipairs(led and led[key] or {}) do
            into[key][#into[key] + 1] = x
        end
    end
    return into
end

local function quantile(list, p)
    local t = {}
    for i, x in ipairs(list) do
        t[i] = x
    end
    table.sort(t)
    return t[math.max(1, math.ceil(p * #t))] or 0
end

local function abs(list)
    local t = {}
    for i, x in ipairs(list) do
        t[i] = math.abs(x)
    end
    return t
end

-- "key n" of a count table's top `k`, joined by "; ".
local function top(counts, k)
    local list = {}
    for key, v in pairs(counts) do
        list[#list + 1] = { key, v }
    end
    table.sort(list, function(x, y)
        return x[2] > y[2] or (x[2] == y[2] and x[1] < y[1])
    end)
    local out = {}
    for i = 1, math.min(k, #list) do
        out[i] = list[i][1] .. " " .. list[i][2]
    end
    return table.concat(out, "; ")
end

--- A merged ledger over `minutes` of combat: per minute dips, flashes (not our presses'), retracted readies and wait
--- oscillations (unjustified), justified retractions (per minute), the top causes of the dips and flashes, their p90
--- length (ticks), the top retracted and wait abilities (ability:cause), floor jitter (count), the decision gaps
--- (lo - truth and est - truth: median, p90 of the magnitude, n), and `byKind` counts (all slots) for the report.
function M.summary(led, minutes)
    local mins = math.max(1e-9, minutes)
    local r = { dips = 0, flashes = 0, retracted = 0, justified = 0, waits = 0, floor = 0 }
    local causes, lens, rtop, wtop, bySlot = {}, {}, {}, {}, {}
    for _, e in ipairs(led.entries) do
        local slot = bySlot[e.slot] or {}
        bySlot[e.slot] = slot
        if e.kind == "dip" or e.kind == "flash" then
            if e.cause ~= "press" then
                local key = e.kind == "dip" and "dips" or "flashes"
                r[key] = r[key] + 1
                causes[e.cause] = (causes[e.cause] or 0) + 1
                lens[#lens + 1] = e.len
                slot[e.kind] = (slot[e.kind] or 0) + 1
            end
        elseif e.kind == "retracted" then
            if e.justified then
                r.justified = r.justified + 1
            else
                r.retracted = r.retracted + 1
                local key = tostring(e.from) .. ":" .. e.cause .. "/" .. e.reason
                rtop[key] = (rtop[key] or 0) + 1
                slot.retracted = (slot.retracted or 0) + 1
            end
        elseif e.kind == "wait" then
            r.waits = r.waits + 1
            local key = tostring(e.from) .. ":" .. e.cause
            wtop[key] = (wtop[key] or 0) + 1
            slot.wait = (slot.wait or 0) + 1
        end
        if e.floor and not e.justified and e.cause ~= "press" then
            r.floor = r.floor + 1
        end
    end
    r.counts = { dips = r.dips, flashes = r.flashes, retracted = r.retracted, waits = r.waits }
    for _, key in ipairs({ "dips", "flashes", "retracted", "justified", "waits" }) do
        r[key] = r[key] / mins
    end
    r.causes, r.top = causes, top(causes, 2)
    r.lenP90 = quantile(lens, 0.9)
    r.rtop, r.wtop, r.bySlot = top(rtop, 2), top(wtop, 2), bySlot
    r.gapN = #led.gapLo
    r.gapLoMed, r.gapLoP90 = quantile(led.gapLo, 0.5), quantile(abs(led.gapLo), 0.9)
    r.gapEstMed, r.gapEstP90 = quantile(led.gapEst, 0.5), quantile(abs(led.gapEst), 0.9)
    return r
end

--- The ledger's fields for a loop line: ours `s` and the oracle shadow's `o` (M.summary).
function M.line(s, o)
    return (
        "dips %.2f flashes %.2f; top [%s]; p90 length %d ticks; retracted %.2f/min (oracle %.2f) [%s] justified %.2f; "
        .. "waits %.2f/min (oracle %.2f) [%s]; floor jitter %d; at cost lo-truth %.1f/%.1f est-truth %.1f/%.1f (%d)"
    ):format(
        s.dips,
        s.flashes,
        s.top,
        s.lenP90,
        s.retracted,
        o.retracted,
        s.rtop,
        s.justified,
        s.waits,
        o.waits,
        s.wtop,
        s.floor,
        s.gapLoMed,
        s.gapLoP90,
        s.gapEstMed,
        s.gapEstP90,
        s.gapN
    )
end

--- A display hold's state (M.hold), one per instance per run.
function M.newHold()
    return { name = {}, time = {}, cost = {}, rawN = {}, rawT = {} }
end

--- The display-side hold experiment (o.hold, off by default): queue `q` (slots 1..SLOTS: name, time, cost) as shown
--- after holding each slot's change one poll. A slot shows its new state (icon, ready or not) once the raw queue
--- has held it two polls; before that it shows the last shown one. Unheld: a retraction (the shown icon no longer
--- ready: a hold never keeps a ready the engine withdrew) and any change after our own cast (`cast`: the addon sees
--- its own cast succeed, and the queue moves on from it).
function M.hold(h, q, react, cast)
    for s = 1, M.SLOTS do
        local n, w = q.name[s], q.time[s]
        local r, hn, hw = w <= react, h.name[s], h.time[s]
        local keep = false
        if hn ~= nil and not cast then
            local pn, pw = h.rawN[s], h.rawT[s]
            local same = n == hn and r == (hw <= react)
            local persisted = n == pn and r == (pw <= react)
            local retract = n == hn and hw <= react and not r
            keep = not (same or persisted or retract)
        end
        h.rawN[s], h.rawT[s] = n, w
        if keep then
            q.name[s], q.time[s], q.cost[s] = hn, hw, h.cost[s]
        end
        h.name[s], h.time[s], h.cost[s] = q.name[s], q.time[s], q.cost[s]
    end
end

return M
