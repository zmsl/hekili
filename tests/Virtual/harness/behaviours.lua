-- tests/Virtual/harness/behaviours.lua (harness design §3.1, layer 2): seeded behaviours that drive entities over time,
-- few and parametric: `melee` (white swings per hand, presses, a queued strike, an on-swing proc, a DoT), `caster`
-- (cast bars, spell schools, an optional pet: a `melee` of its own), `mob` (swings at its target, a spell). The matrix
-- comes from parameters and seeds. Named by shape only (boundary rule).
local M = {}

-- Our white swings' outcome rates (P log 2: 10 MISS, 3 DODGE, 3 PARRY in 71 swings; 8 crits in 69 wounds).
M.RATES = { miss = 0.14, dodge = 0.04, parry = 0.04, glancing = 0, crit = 0.12 }
-- A mob's swings at a player: the player's avoid table is the victim's (`entity.avoid`); this is the mob's crit.
M.MOB_CRIT = 0.05
local SAME_MS = { "MISS", "DODGE", "PARRY" }

-- One outcome from `rates` (miss, dodge, parry, block, glancing, crit): the action and its flag.
local function roll(r, rates)
    local x = r.next()
    for _, k in ipairs({ "miss", "dodge", "parry", "block" }) do
        local p = rates[k] or 0
        if x < p then
            return k:upper(), ""
        end
        x = x - p
    end
    if x < (rates.glancing or 0) then
        return "WOUND", "GLANCING"
    end
    x = x - (rates.glancing or 0)
    if x < (rates.crit or 0) then
        return "WOUND", "CRITICAL"
    end
    return "WOUND", ""
end
M.roll = roll

-- A white hit's amount: the weapon's roll x the attacker's damage multiplier, less the victim's armour, doubled for a
-- crit; a glancing blow is `glance` ({ lo, hi } absolute) or three quarters.
local function amount(r, w, e, victim, flag, glance)
    local a = r.int(w[1], w[2]) * e.dmgMult * (1 - (victim and victim.dr or 0))
    if flag == "CRITICAL" then
        a = a * 2
    elseif flag == "GLANCING" then
        a = glance and r.int(glance[1], glance[2]) or a * 0.75
    end
    return math.max(1, math.floor(a + 0.5))
end

--- A melee player: per weapon hand, a swing every speed / haste from a random phase, its outcome rolled from `p.rates`
--- (default RATES). `p.land(W, e, hand, t)`: ours only, the lag before the outcome lands (observer.lua); without it the
--- outcome is at the swing (another player's). `p.rage` { main, off } or fn(hand, amount, flag): what a landed wound
--- of ours pays; `p.critRage` { main, off }: the extra a CRITICAL one pays; `p.payIn`: the form whose landed wounds pay
--- (nil: every form). A queued strike (W.queueStrike) our power no longer covers at the swing is dropped (a white swing).
--- `p.presses` { { t, spell, cost, kind } }: kind "queue" (the next main-hand swing is a strike of `p.strike`
--- { lo, hi }), "dot" (`p.dot` { every, n, amount } ticks, school 1), "cast" (no outcome); each only if our power
--- covers its cost.
--- `p.strikes`: another player's chance per main-hand swing to make it a strike frame (G: WOUND 0 + damage).
--- `p.proc` { chance, amount }: a school-32 wound on the swing event (1-2 ms after it). `p.glance` { lo, hi }.
--- `p.sameMs`: the chance per swing of ours of an unexplained avoid in its ms (`ev.sameMs`, the observer's knob);
--- our strike frames carry their order (`ev.order`). Both come from `W.crng`; every draw is the behaviour's.
function M.melee(p)
    p = p or {}
    return function(W, e)
        local rates = p.rates or M.RATES
        e.lastSwing, e.landAt = { 0, 0 }, { 0, 0 }
        for h = 1, #e.weapons do
            local function swing()
                local tgt = e.target
                if e.stopped or not tgt or tgt.health <= 0 then
                    return
                end
                local w = e.weapons[h]
                local foreign = h == 1 and p.strikes and W.rng.chance(p.strikes)
                if h == 1 and e.queued and e.power < (e.queued.cost or 0) then -- short at the swing: a white one
                    W.emit({ kind = "unqueue", src = e, spell = e.queued.spell, ids = e.queued.ids })
                    e.queued = nil
                end
                if h == 1 and (e.queued or foreign) then
                    local q = e.queued or {}
                    e.queued = nil
                    -- our strike frame's order (P log 1's, then the brief's): 1 the success first, 2 the swing first
                    local order = p.land and (W.crng.chance(0.5) and 1 or 2) or nil
                    W.emit({
                        kind = "strike",
                        src = e,
                        dst = tgt,
                        hand = 1,
                        act = "WOUND",
                        flag = "",
                        amount = W.rng.int((q.amount or p.strike or w)[1], (q.amount or p.strike or w)[2]),
                        school = 1,
                        spell = q.spell,
                        ids = q.ids,
                        cost = q.cost,
                        speed = w[3],
                        order = order,
                    })
                else
                    local act, flag = roll(W.rng, rates)
                    local amt = act == "WOUND" and amount(W.rng, w, e, tgt, flag, p.glance) or 0
                    -- an unexplained avoid on the target in our swing event's ms (P log 2), rolled here from the
                    -- client-detail generator so the observer draws nothing (a press changes the fight's future,
                    -- never how its past is observed) and W.rng's draws per seed stay as they were
                    local same = p.sameMs and W.crng.chance(p.sameMs) and W.crng.pick(SAME_MS) or nil
                    local sw = W.emit({
                        kind = "swing",
                        src = e,
                        dst = tgt,
                        hand = h,
                        act = act,
                        flag = flag,
                        amount = amt,
                        school = 1,
                        speed = w[3],
                        ours = p.land ~= nil,
                        sameMs = same,
                    })
                    if p.land then
                        local lag = p.land(W, e, h, W.t)
                        e.landAt[h] = W.t + lag
                        W.at(W.t + lag, function()
                            if act ~= "WOUND" then
                                e.avoidAt[act] = W.t -- the world's truth a content requirement reads (an opening)
                            end
                            local rage = p.rage
                            if type(rage) == "function" then
                                rage = act == "WOUND" and rage(h, amt, flag) or nil
                            else
                                rage = act == "WOUND" and rage and rage[h] or nil
                            end
                            if act == "WOUND" and flag == "CRITICAL" and p.critRage then
                                rage = (rage or 0) + (p.critRage[h] or 0)
                            end
                            if p.payIn and e.form ~= p.payIn then
                                rage = nil
                            end
                            W.emit({
                                kind = "land",
                                src = e,
                                dst = tgt,
                                hand = h,
                                act = act,
                                flag = flag,
                                amount = amt,
                                school = 1,
                                swing = sw,
                                rage = rage,
                            })
                        end)
                    end
                    if p.proc and W.rng.chance(p.proc[1]) then
                        W.at(W.t + W.rng.int(1, 2) / 1000, function()
                            local proc =
                                { kind = "proc", src = e, dst = tgt, act = "WOUND", amount = p.proc[2], school = 32 }
                            W.emit(proc)
                        end)
                    end
                end
                e.lastSwing[h] = W.t
                W.at(W.t + w[3] / (p.haste or 1), swing)
            end
            W.at(W.t + (p.phase and p.phase[h] or W.rng.next() * e.weapons[h][3]), swing)
        end
        for _, press in ipairs(p.presses or {}) do
            W.at(press[1], function()
                if e.stopped or e.power < press[3] then
                    return
                end
                if press[4] == "queue" then
                    e.queued = { spell = press[2], cost = press[3] }
                    return
                end
                W.emit({ kind = "cast", src = e, dst = e.target, spell = press[2], cost = press[3] })
                if press[4] == "dot" then
                    for k = 1, p.dot[2] do
                        W.at(W.t + k * p.dot[1], function()
                            W.emit({
                                kind = "tick",
                                src = e,
                                dst = e.target,
                                act = "WOUND",
                                amount = p.dot[3],
                                school = 1,
                            })
                        end)
                    end
                end
            end)
        end
    end
end

--- A caster: a spell every `p.every` s (a `p.cast` s bar first), school `p.school` (2, 4, 8 or 32), amount `p.amount`
--- { lo, hi }, resisted (MISS) at `p.resist`; its casts are another player's (secret IDs). `p.pet`: a melee behaviour
--- for a pet entity `p.petEntity` on the caster's target.
function M.caster(p)
    return function(W, e)
        local function cast()
            if e.stopped or not e.target or e.target.health <= 0 then
                return
            end
            W.emit({ kind = "cast", src = e, dst = e.target, spell = "SECRET" })
            local resisted = W.rng.chance(p.resist or 0)
            W.emit({
                kind = "spell",
                src = e,
                dst = e.target,
                act = resisted and "MISS" or "WOUND",
                flag = "",
                amount = resisted and 0 or W.rng.int(p.amount[1], p.amount[2]),
                school = p.school or 8,
            })
            W.at(W.t + p.every * (0.8 + 0.4 * W.rng.next()), cast)
        end
        W.at(W.t + (p.cast or 1.5) + W.rng.next(), cast)
    end
end

--- A mob: a swing at its target every weapon speed, rolled against the target's `avoid` table and `p.crit`; `p.spell`
--- { every, lo, hi, school }: a spell at its target.
function M.mob(p)
    p = p or {}
    return function(W, e)
        local function swing()
            local v = e.target
            if e.stopped or e.health <= 0 then
                return
            elseif not v then -- not attacking anyone yet (a later `targetSwitch`): look again a swing later
                W.at(W.t + e.weapons[1][3], swing)
                return
            end
            local rates = { miss = v.avoid.miss, dodge = v.avoid.dodge, parry = v.avoid.parry, block = v.avoid.block }
            rates.crit = p.crit or M.MOB_CRIT
            local act, flag = roll(W.rng, rates)
            local amt = act == "WOUND" and amount(W.rng, e.weapons[1], e, v, flag) or 0
            W.emit({ kind = "swing", src = e, dst = v, hand = 1, act = act, flag = flag, amount = amt, school = 1 })
            W.at(W.t + e.weapons[1][3], swing)
        end
        W.at(W.t + (p.phase or W.rng.next() * e.weapons[1][3]), swing)
        if p.spell then
            local s = p.spell
            local function spell()
                if e.stopped or e.health <= 0 or not e.target then
                    return
                end
                local amt = W.rng.int(s[2], s[3])
                W.emit({
                    kind = "spell",
                    src = e,
                    dst = e.target,
                    act = "WOUND",
                    flag = "",
                    amount = amt,
                    school = s[4],
                })
                W.at(W.t + s[1], spell)
            end
            W.at(W.t + s[1] * W.rng.next() + 1, spell)
        end
    end
end

return M
