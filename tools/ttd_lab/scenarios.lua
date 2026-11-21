-- tools/ttd_lab/scenarios.lua: synthetic fights with a known true health trace per mob and the player's target plan.
-- A fight: { class, mobs = { {max, ht = {t...}, hv = {pct...}, death} }, plan = { {t, mob} }, own = {t = {}, a = {}},
-- endT }. Damage comes from the player (rate 1) and 0-4 group members (rate 0.6-1.4), hits every 0.3-1.2 s,
-- +-30% noise, 25% crits for double; per-class modifiers below. `own` is the player's damage on every mob (the meter).
local Rng = require("rng")

local S = {}

S.CLASSES = {
    "trash",
    "pack",
    "mixed",
    "elite",
    "boss",
    "burst",
    "dot",
    "execute",
    "stall",
    "heal",
    "phase",
    "damaged",
    "real",
}

-- Run 2 (execute and lust; `run.lua run2`): lust x1.3 for 40 s at the pull, mid-fight (when the first mob falls to
-- 30-60%) and its end while the mob lives; execute at 20% or 35% at x1.3-2.5 (the same fights per threshold: only the
-- multiplier differs); the two together; a solo player and a 16-20 player raid, plain and with both changes.
S.RUN2 = {
    "lust pull boss",
    "lust pull elite",
    "lust pull pack",
    "lust mid boss",
    "lust mid elite",
    "lust end",
    "ex20 x1.3",
    "ex20 x1.6",
    "ex20 x2.0",
    "ex20 x2.5",
    "ex35 x1.3",
    "ex35 x1.6",
    "ex35 x2.0",
    "ex35 x2.5",
    "ex+lust elite",
    "ex+lust boss",
    "solo",
    "raid",
    "solo ex+lust",
    "raid ex+lust",
}

local LUST = 1.3

-- Run 3 (partial-group execute; `run.lua run3`): a session is one fixed group (the player, 3 more DPS, a tank) doing
-- 10 pulls (S.PULLS: packs of trash, elites, a boss). `ex[i]` is DPS i's execute line (1 = the player; false or
-- missing: none); the tank (rate 0.4-0.7) never speeds up. Each executing DPS has its own multiplier x1.5-2.5 below
-- its line, so the group's factor is 1 + sum of executing shares x (mult - 1). `dom`: one random DPS does 2.5-3.5x a
-- normal DPS's damage. `solo`: the player alone.
S.RUN3 = {
    { name = "g0", ex = {} },
    { name = "g1 20 me", ex = { 20 } },
    { name = "g1 35 me", ex = { 35 } },
    { name = "g1 35 other", ex = { false, 35 } },
    { name = "g2 20 me", ex = { 20, 20 } },
    { name = "g2 mix me", ex = { 20, 35 } },
    { name = "g2 35 other", ex = { false, 35, 35 } },
    { name = "g4 20", ex = { 20, 20, 20, 20 } },
    { name = "g4 mix", ex = { 20, 35, 20, 35 } },
    { name = "g1 20 me dom", ex = { 20 }, dom = true },
    { name = "g1 35 other dom", ex = { false, 35 }, dom = true },
    { name = "g2 mix me dom", ex = { 20, 35 }, dom = true },
    { name = "solo 20", ex = { 20 }, solo = true },
    { name = "solo 35", ex = { 35 }, solo = true },
}
S.PULLS = { "trash", "elite", "trash", "trash", "elite", "trash", "boss", "trash", "elite", "trash" }

--- One session's group: rates (1 = the player, the tank last), ex[i] = { pct, mult } or false, and what a caller
--- could know: own (the player's line or false), lines (descending, tank excluded), nDPS, nExec; and the truth:
--- F[line] = the group's damage factor below that line (every executor whose line is at or above it counted).
function S.group(comp, seed)
    local rng = Rng.new(seed)
    local nDPS = comp.solo and 1 or 4
    local rates, ex = { 1 }, {}
    for i = 2, nDPS do
        rates[i] = rng:uni(0.7, 1.3)
    end
    if comp.dom then
        rates[rng:int(1, nDPS)] = rng:uni(2.5, 3.5)
    end
    if not comp.solo then
        rates[nDPS + 1] = rng:uni(0.4, 0.7) -- the tank
    end
    local total, lines, seen, nExec = 0, {}, {}, 0
    for i = 1, #rates do
        total = total + rates[i]
        local line = i <= nDPS and comp.ex[i]
        ex[i] = line and { pct = line, mult = rng:uni(1.5, 2.5) } or false
        if line then
            nExec = nExec + 1
            if not seen[line] then
                seen[line], lines[#lines + 1] = true, line
            end
        end
    end
    table.sort(lines, function(a, b)
        return a > b
    end)
    local F = {}
    for _, line in ipairs(lines) do
        local f = 0
        for i = 1, #rates do
            f = f + rates[i] * ((ex[i] and ex[i].pct >= line) and ex[i].mult or 1)
        end
        F[line] = f / total
        assert(F[line] > 1 and F[line] <= 2.5 and (not comp.solo or F[line] == ex[1].mult), "group factor")
    end
    return {
        rates = rates,
        ex = ex,
        own = ex[1] and ex[1].pct or false,
        lines = lines,
        nDPS = nDPS,
        nExec = nExec,
        F = F,
        name = comp.name,
    }
end

-- A run 3 pull of one length: trash is a pack (2-4 mobs, cleave, 0-2 deliberate swaps), elite 30-60 s, boss 3-6 min.
local function spec3(length, rng)
    local sp = { mobs = 1, members = 0, cleave = 0, swaps = 0 }
    if length == "trash" then
        sp.mobs, sp.dur, sp.cleave, sp.swaps = rng:int(2, 4), rng:uni(8, 20), rng:uni(0.3, 0.7), rng:int(0, 2)
    elseif length == "elite" then
        sp.dur = rng:uni(30, 60)
    elseif length == "boss" then
        sp.dur = rng:uni(180, 360)
    else
        error("unknown length " .. tostring(length))
    end
    return sp
end

local function run2(class, rng, sp)
    local ex, x = class:match("^ex(%d+) x([%d.]+)$")
    if ex then
        sp.dur, sp.execute = rng:uni(20, 60), { pct = tonumber(ex), mult = tonumber(x) }
        return sp
    end
    if class:find("boss") then
        sp.dur, sp.members = rng:uni(180, 360), 4
    else
        sp.dur = rng:uni(30, 60)
    end
    if class:find("^solo") then
        sp.members = 0
    elseif class:find("^raid") then
        sp.members = rng:int(15, 19)
    end
    if class == "lust pull pack" then
        sp.mobs, sp.dur, sp.cleave = rng:int(3, 5), rng:uni(8, 20), rng:uni(0.3, 0.7)
        sp.members, sp.swaps = rng:int(1, 4), rng:int(0, 2)
    elseif class == "lust end" then -- the mob outlives the lust: the drop at 40 s falls at 35-65% health
        sp.dur = rng:uni(80, 150)
    end
    if class:find("^lust pull") or class == "lust end" then
        sp.lust = { t = 0, dur = 40, mult = LUST }
    elseif class:find("^lust mid") then
        sp.lust = { atPct = rng:uni(30, 60), dur = 40, mult = LUST }
    elseif class:find("ex%+lust") then -- lust held for the execute: it starts 0-15% above the threshold
        sp.execute = { pct = rng:uni(20, 35), mult = rng:uni(1.6, 2.5) }
        sp.lust = { atPct = sp.execute.pct + rng:uni(0, 15), dur = 40, mult = LUST }
    elseif class ~= "solo" and class ~= "raid" then
        error("unknown class " .. tostring(class))
    end
    return sp
end

-- Run 3, LibTimeToDie review I-3 (`run.lua idle`): the player targets a full mob that nobody hits for 5-30 s, then the
-- fight starts. In combat the stream runs through the idle; out of combat the caller restarts it when combat starts
-- (a second target event on the same mob at the first hit).
S.IDLE = { "idle trash", "idle elite", "idle boss", "idle solo elite", "idle ooc elite", "idle ooc boss" }

local function idle(class, rng, sp)
    sp.idle, sp.ooc = rng:uni(5, 30), class:find("ooc") and true or false
    if class:find("trash") then
        sp.dur = rng:uni(8, 20)
    elseif class:find("boss") then
        sp.dur, sp.members = rng:uni(180, 360), 4
    else
        sp.dur = rng:uni(30, 60)
    end
    if class:find("solo") then
        sp.members = 0
    end
    return sp
end

-- Run 4 (real traces; `run.lua run4`): lumpy solo damage as the owner's first in-game traces show it (band falls: 72% 1-3%,
-- 16% 4-7%, 12% 9-15%; a band change every 0.64 s at the median), opener timing (the target at full, combat start
-- 0.3-2 s later, the first damage 0-4 s after that; `instant`: in the same frame as combat start), an opener burst
-- x1-2.5 for 2-4 s from the first damage, fights of 6-40 s. `pair`: two mobs, the second takes 10-30% cleave, the
-- player swaps to it at the first one's death.
S.LUMPY = { "lumpy solo", "lumpy instant", "lumpy pair" }

-- One lump factor (mean 1): small steps, medium hits and big chunks in the traces' proportions.
local function lump(rng)
    local u, x = rng:next(), nil
    if u < 0.72 then
        x = rng:uni(0.25, 0.95)
    elseif u < 0.88 then
        x = rng:uni(1.2, 2.2)
    else
        x = rng:uni(2.8, 4.6)
    end
    return x / 1.148
end

local function lumpy(class, rng, sp)
    sp.members, sp.dur, sp.lumpy = 0, rng:uni(6, 40), true
    sp.combat = rng:uni(0.3, 2)
    sp.firstHit = sp.combat + (class == "lumpy instant" and 0 or rng:uni(0, 4))
    sp.opener = { mult = rng:uni(1, 2.5), dur = sp.firstHit + rng:uni(2, 4) }
    if class == "lumpy pair" then
        sp.mobs, sp.cleave = 2, rng:uni(0.1, 0.3)
    end
    return sp
end

--- The per-class fight spec. `dur`: seconds one mob lives under the whole group's single-target damage.
local function spec(class, rng)
    local sp = { mobs = 1, members = rng:int(0, 4), cleave = 0, swaps = 0 }
    if class:find("^lumpy") then
        return lumpy(class, rng, sp)
    elseif class:find("^idle") then
        return idle(class, rng, sp)
    elseif class:find(" ") or class == "solo" or class == "raid" then
        return run2(class, rng, sp)
    elseif class == "trash" then
        sp.dur = rng:uni(8, 20)
    elseif class == "pack" then
        sp.mobs, sp.dur, sp.cleave = rng:int(3, 5), rng:uni(8, 20), rng:uni(0.3, 0.7)
        sp.members, sp.swaps = rng:int(1, 4), rng:int(0, 2)
    elseif class == "mixed" then -- a pack with one big mob (3-5x health): a swap carries a wrong slope
        sp.mobs, sp.dur, sp.cleave = rng:int(3, 5), rng:uni(8, 20), rng:uni(0.3, 0.7)
        sp.members, sp.swaps = rng:int(1, 4), rng:int(1, 3)
        sp.big, sp.bigMob = rng:uni(3, 5), rng:int(1, sp.mobs)
    elseif class == "elite" then
        sp.dur = rng:uni(30, 60)
    elseif class == "boss" then
        sp.dur, sp.members = rng:uni(180, 360), 4
        sp.opener = { mult = 1.8, dur = rng:uni(15, 25) }
        sp.execute = { pct = 20, mult = 1.3 }
        sp.lust = { t = rng:uni(0, 60), dur = 40, mult = 1.3 }
    elseif class == "burst" then
        sp.dur, sp.opener = rng:uni(10, 45), { mult = rng:uni(2, 3.5), dur = rng:uni(6, 15) }
    elseif class == "dot" then
        sp.dur, sp.dot, sp.members = rng:uni(15, 50), rng:uni(6, 14), rng:int(0, 1)
    elseif class == "execute" then
        sp.dur, sp.execute = rng:uni(20, 60), { pct = rng:uni(20, 35), mult = rng:uni(1.6, 2.5) }
    elseif class == "stall" then
        sp.dur, sp.stall = rng:uni(20, 50), { at = rng:uni(30, 70), dur = rng:uni(4, 10) }
    elseif class == "heal" then
        sp.dur, sp.heals = rng:uni(20, 50), rng:int(2, 5)
    elseif class == "phase" then
        sp.dur, sp.phase = rng:uni(40, 90), { at = rng:uni(35, 55), to = rng:uni(70, 100), immune = 2 }
    elseif class == "damaged" then
        sp.dur, sp.targetAt, sp.members = rng:uni(25, 60), rng:uni(30, 90), rng:int(1, 4)
    else
        error("unknown class " .. tostring(class))
    end
    return sp
end

local function record(m, t)
    m.ht[#m.ht + 1], m.hv[#m.hv + 1] = t, 100 * m.hp / m.max
end

local function pct(m)
    return 100 * m.hp / m.max
end

--- Applies attacker `who`'s `amt` to mob `m` at `t` under the spec's per-mob rules; returns the damage done.
local function apply(sp, m, amt, t, who)
    if m.death or t < m.immuneUntil then
        return 0
    end
    m.firstHit = m.firstHit or t
    if sp.dot then -- DoTs ramp up: a quarter of the damage at first, all of it after `dot` seconds
        amt = amt * math.min(1, 0.25 + 0.75 * (t - m.firstHit) / sp.dot)
    end
    local x = sp.pexec and sp.pexec[who]
    if x and pct(m) < x.pct then -- run 3: this attacker's own execute; a change point per line per mob
        amt = amt * x.mult
        m.lines = m.lines or {}
        if not m.lines[x.pct] then
            m.lines[x.pct] = t
            sp.changes[#sp.changes + 1] = { t = t, mob = m.index }
        end
    elseif sp.execute and pct(m) < sp.execute.pct then
        amt = amt * sp.execute.mult
        if not m.execAt then
            m.execAt = t
            sp.changes[#sp.changes + 1] = { t = t, mob = m.index }
        end
    end
    m.hp = m.hp - amt
    if m.hp <= 0 then
        m.hp, m.death = 0, t
    elseif sp.phase and not m.phased and pct(m) < sp.phase.at then
        m.phased, m.hp, m.immuneUntil = true, m.max * sp.phase.to / 100, t + sp.phase.immune
    elseif sp.stall and not m.stalled and pct(m) < sp.stall.at then
        m.stalled, m.immuneUntil = true, t + sp.stall.dur
    end
    record(m, t)
    return amt
end

local function firstAlive(mobs, except)
    for i = 1, #mobs do
        if not mobs[i].death and i ~= except then
            return i
        end
    end
end

--- A fight of `class`; run 3: `class` is a pull length and `group` the session's group (S.group).
function S.build(class, seed, group)
    local rng = Rng.new(seed)
    local sp = group and spec3(class, rng) or spec(class, rng)
    sp.changes = {} -- rate changes { t, mob } (mob 0: every mob), for the post-change metrics
    local rates = { 1 }
    if group then
        rates, sp.pexec = group.rates, group.ex
    end
    for i = 1, sp.members do
        rates[i + 1] = rng:uni(0.6, 1.4)
    end
    local total = 0
    for i = 1, #rates do
        total = total + rates[i]
    end
    local mobs = {}
    for i = 1, sp.mobs do
        local hp = sp.dur * total * (sp.mobs > 1 and rng:uni(0.8, 1.2) or 1) * (i == sp.bigMob and sp.big or 1)
        mobs[i] = { max = hp, hp = hp, ht = {}, hv = {}, immuneUntil = -1, heals = {}, index = i }
        record(mobs[i], 0)
        for _ = 1, sp.heals or 0 do
            mobs[i].heals[#mobs[i].heals + 1] = { t = rng:uni(0.15, 0.85) * sp.dur, amt = rng:uni(1, 5) }
        end
    end
    local nextHit = {}
    for i = 1, #rates do
        nextHit[i] = sp.firstHit or rng:uni(0, 1) + (sp.idle or 0)
    end
    local swapAt = {}
    for _ = 1, sp.swaps do
        swapAt[#swapAt + 1] = rng:uni(2, sp.dur * 1.5)
    end
    table.sort(swapAt)
    local plan, own = {}, { t = {}, a = {} }
    local ptarget, reacquireAt, swapBack, si = nil, nil, nil, 1
    local function target(mob, t)
        ptarget = mob
        plan[#plan + 1] = { t = t, mob = mob }
    end
    local dt, t = 0.02, 0
    local horizon = sp.dur * sp.mobs * 4 + 60 + (sp.idle or 0)
    while t < horizon and firstAlive(mobs) do
        if not ptarget and not reacquireAt and #plan == 0 then
            if not sp.targetAt or pct(mobs[1]) <= sp.targetAt then
                target(1, t)
            end
        end
        if sp.ooc and ptarget and t >= sp.idle then -- combat starts: the caller restarts the stream
            sp.ooc = false
            target(ptarget, t)
        end
        if ptarget and mobs[ptarget].death then
            ptarget, reacquireAt = nil, t + rng:uni(0.2, 0.8)
        end
        if reacquireAt and t >= reacquireAt then
            reacquireAt = nil
            local nxt = (swapBack and not mobs[swapBack.mob].death) and swapBack.mob or firstAlive(mobs)
            swapBack = nil
            if nxt then
                target(nxt, t)
            end
        end
        if ptarget and swapAt[si] and t >= swapAt[si] then -- a deliberate swap, back after 2-5 s half the time
            si = si + 1
            local other = firstAlive(mobs, ptarget)
            if other then
                if rng:next() < 0.5 then
                    swapBack = { mob = ptarget, t = t + rng:uni(2, 5) }
                end
                target(other, t)
            end
        end
        if ptarget and swapBack and t >= swapBack.t and swapBack.mob ~= ptarget then
            local back = swapBack.mob
            swapBack = nil
            if not mobs[back].death then
                target(back, t)
            end
        end
        local mult = 1
        if sp.opener and t < sp.opener.dur then
            mult = mult * sp.opener.mult
        end
        local lust = sp.lust
        if lust and not lust.t and pct(mobs[1]) <= lust.atPct then
            lust.t = t
        end
        if lust and lust.t and t >= lust.t and t < lust.t + lust.dur then
            mult = mult * lust.mult
        end
        local groupTarget = firstAlive(mobs)
        for i = 1, #rates do
            if t >= nextHit[i] then
                local interval = sp.lumpy and rng:uni(0.4, 1) or rng:uni(0.3, 1.2)
                nextHit[i] = t + interval
                local tgt = i == 1 and ptarget or groupTarget
                if tgt then
                    local amt
                    if sp.lumpy then -- the traces' lump mix, mean rate x interval
                        amt = rates[i] * interval * lump(rng) * mult
                    else
                        amt = rates[i] * interval * rng:uni(0.7, 1.3) * (rng:next() < 0.25 and 2 or 1) / 1.25 * mult
                    end
                    local done = apply(sp, mobs[tgt], amt, t, i)
                    for m = 1, #mobs do
                        if m ~= tgt and sp.cleave > 0 then
                            done = done + apply(sp, mobs[m], amt * sp.cleave, t, i)
                        end
                    end
                    if i == 1 and done > 0 then
                        own.t[#own.t + 1], own.a[#own.a + 1] = t, done
                    end
                end
            end
        end
        for m = 1, #mobs do
            local mob = mobs[m]
            local h = mob.heals[1]
            if h and t >= h.t then
                table.remove(mob.heals, 1)
                if not mob.death then
                    mob.hp = math.min(mob.max, mob.hp + mob.max * h.amt / 100)
                    record(mob, t)
                end
            end
        end
        t = t + dt
    end
    local endT = 0
    for i = 1, #mobs do
        endT = math.max(endT, mobs[i].death or horizon)
    end
    local changes = sp.changes
    if sp.idle then -- the post-change window: the first 10 s of damage
        changes[#changes + 1] = { t = sp.idle, mob = 0 }
    end
    if sp.opener then
        changes[#changes + 1] = { t = sp.opener.dur, mob = 0 }
    end
    local lust = sp.lust
    if lust and lust.t then
        changes[#changes + 1] = { t = lust.t, mob = 0 }
        changes[#changes + 1] = { t = lust.t + lust.dur, mob = 0 }
    end
    return {
        class = class,
        mobs = mobs,
        plan = plan,
        own = own,
        endT = endT,
        changes = changes,
        lust = lust and lust.t and lust or nil, -- { t, dur, mult } once it started
        execute = sp.execute, -- { pct, mult }
        members = sp.members,
        group = group,
        combat = sp.combat, -- run 4: combat start (the library re-anchors a stream with no crossing yet)
    }
end

return S
