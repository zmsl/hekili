-- tools/ttd_lab/scenarios.lua: synthetic fights with a known true health trace per mob and the player's target plan.
-- A fight: { class, mobs = { {max, ht = {t...}, hv = {pct...}, death} }, plan = { {t, mob} }, own = {t = {}, a = {}},
-- endT }. Damage comes from the player (rate 1) and 0-4 group members (rate 0.6-1.4), hits every 0.3-1.2 s,
-- +-30% noise, 25% crits for double; per-class modifiers below. `own` is the player's damage on every mob (the meter).
local Rng = require("rng")

local S = {}

S.CLASSES = { "trash", "pack", "elite", "boss", "burst", "dot", "execute", "stall", "heal", "phase", "damaged", "real" }

--- The per-class fight spec. `dur`: seconds one mob lives under the whole group's single-target damage.
local function spec(class, rng)
    local sp = { mobs = 1, members = rng:int(0, 4), cleave = 0, swaps = 0 }
    if class == "trash" then
        sp.dur = rng:uni(8, 20)
    elseif class == "pack" then
        sp.mobs, sp.dur, sp.cleave = rng:int(3, 5), rng:uni(8, 20), rng:uni(0.3, 0.7)
        sp.members, sp.swaps = rng:int(1, 4), rng:int(0, 2)
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

--- Applies `amt` to mob `m` at `t` under the spec's per-mob rules; returns the damage done.
local function apply(sp, m, amt, t)
    if m.death or t < m.immuneUntil then
        return 0
    end
    m.firstHit = m.firstHit or t
    if sp.dot then -- DoTs ramp up: a quarter of the damage at first, all of it after `dot` seconds
        amt = amt * math.min(1, 0.25 + 0.75 * (t - m.firstHit) / sp.dot)
    end
    if sp.execute and pct(m) < sp.execute.pct then
        amt = amt * sp.execute.mult
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

function S.build(class, seed)
    local rng = Rng.new(seed)
    local sp = spec(class, rng)
    local rates = { 1 }
    for i = 1, sp.members do
        rates[i + 1] = rng:uni(0.6, 1.4)
    end
    local total = 0
    for i = 1, #rates do
        total = total + rates[i]
    end
    local mobs = {}
    for i = 1, sp.mobs do
        local hp = sp.dur * total * (sp.mobs > 1 and rng:uni(0.8, 1.2) or 1)
        mobs[i] = { max = hp, hp = hp, ht = {}, hv = {}, immuneUntil = -1, heals = {} }
        record(mobs[i], 0)
        for _ = 1, sp.heals or 0 do
            mobs[i].heals[#mobs[i].heals + 1] = { t = rng:uni(0.15, 0.85) * sp.dur, amt = rng:uni(1, 5) }
        end
    end
    local nextHit = {}
    for i = 1, #rates do
        nextHit[i] = rng:uni(0, 1)
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
    local horizon = sp.dur * sp.mobs * 4 + 60
    while t < horizon and firstAlive(mobs) do
        if not ptarget and not reacquireAt and #plan == 0 then
            if not sp.targetAt or pct(mobs[1]) <= sp.targetAt then
                target(1, t)
            end
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
        if sp.lust and t >= sp.lust.t and t < sp.lust.t + sp.lust.dur then
            mult = mult * sp.lust.mult
        end
        local groupTarget = firstAlive(mobs)
        for i = 1, #rates do
            if t >= nextHit[i] then
                local interval = rng:uni(0.3, 1.2)
                nextHit[i] = t + interval
                local tgt = i == 1 and ptarget or groupTarget
                if tgt then
                    local amt = rates[i] * interval * rng:uni(0.7, 1.3) * (rng:next() < 0.25 and 2 or 1) / 1.25 * mult
                    local done = apply(sp, mobs[tgt], amt, t)
                    for m = 1, #mobs do
                        if m ~= tgt and sp.cleave > 0 then
                            done = done + apply(sp, mobs[m], amt * sp.cleave, t)
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
    return { class = class, mobs = mobs, plan = plan, own = own, endT = endT }
end

return S
