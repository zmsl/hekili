-- tests/Virtual/harness/scenarios.lua (harness design §3.1 layer 5, §3.2): a scenario is a roster, a behaviour per
-- entity and a timeline of set pieces (pull, stop, formChange, damageBuff, targetSwitch); between them the fight is
-- emergent. Our character auto-attacks and presses a scripted list. Archetypes by shape only (boundary rule).
local world = require("Virtual.harness.world")
local entities = require("Virtual.harness.entities")
local behaviours = require("Virtual.harness.behaviours")
local observer = require("Virtual.harness.observer")

local M = {}

-- Another source on our target, by shape: `melee` (white hits inside our main-hand range, glancing 1-5 and strike
-- frames as G's partner), `caster` (school-8 spells as G's partner's), `pet` (one quick weapon), `ranged` (a physical
-- stand-in: a 2-3 s period, no dodge or parry by the target's facing).
local ARCHETYPES = {
    melee = function(W, lvl)
        local w = entities.weapons(lvl)[1]
        local e = entities.new({ weapons = { { w[1], w[2], 2.0 + W.rng.next() } }, level = lvl })
        local rates = { miss = 0.08, dodge = 0.05, parry = 0.02, glancing = 0.1, crit = 0.1 }
        return e, behaviours.melee({ rates = rates, glance = { 1, 5 }, strikes = 0.4, strike = { w[1], w[2] } })
    end,
    caster = function(W, lvl)
        local k = lvl / 22
        local e = entities.new({ level = lvl })
        return e, behaviours.caster({ every = 2.5, amount = { math.floor(30 * k), math.floor(45 * k) }, school = 8 })
    end,
    pet = function(W, lvl)
        local w = entities.weapons(lvl)[2]
        local e = entities.new({ kind = "pet", weapons = { { w[1], w[2], 1.6 + 0.4 * W.rng.next() } }, level = lvl })
        return e, behaviours.melee({ rates = { miss = 0.08, dodge = 0.05, parry = 0.02, crit = 0.1 } })
    end,
    ranged = function(W, lvl)
        local w = entities.weapons(lvl)[1]
        local e = entities.new({ weapons = { { w[1], w[2], 2.0 + W.rng.next() } }, level = lvl })
        return e, behaviours.melee({ rates = { miss = 0.05, crit = 0.1 } })
    end,
}
M.ARCHETYPES = ARCHETYPES

-- shortcut: only the other sources on our target are simulated (the rest fire rows on tokens nothing reads), with no
-- heals on party members and no parry haste on our swing timer; add them when a customer reads them.

--- The world of one fight. Knobs `o` (defaults in brackets): duration [120], level [22], dr [0], rates (ours),
--- lag (observer knobs), others { archetype, ... } on our target [none], attackers [1] (mobs on us; the first is our
--- target), mobPeriod [2.0], mobDamage { lo, hi } [10-14], plainSpeed, damageBuff (t: +20% in combat), formAt (t),
--- presses ({ t, spell, cost, kind }), rage ({ main, off } [9, 5]), max (our power cap [1e6]), proc, mobs (per
--- attacker { damage = { lo, hi }, period }) and joinAt ({ [attacker] = t: on us from t }) for hits on us, switches.
function M.build(o, seed)
    local W = world.new(seed)
    local lvl = o.level or 22
    local us = W.add(
        entities.new({ guid = "Player-1", level = lvl, weapons = entities.weapons(lvl), powerMax = o.max or 1e6 })
    )
    local mobs = {}
    for i = 1, math.max(1, o.attackers or 1) do
        local m = o.mobs and o.mobs[i] or {}
        local dmg = m.damage or o.mobDamage or { 10, 14 }
        local mob = W.add(entities.new({
            guid = "Creature-" .. i,
            kind = "mob",
            level = lvl,
            dr = i == 1 and (o.dr or 0) or 0,
            weapons = { { dmg[1], dmg[2], m.period or o.mobPeriod or 2.0 } },
            health = 1e9,
        }))
        mob.target = (i <= (o.attackers or 1) and not (o.joinAt and o.joinAt[i])) and us or nil
        mobs[i] = mob
    end
    us.target = mobs[1]
    local others = {}
    for i, kind in ipairs(o.others or {}) do
        local e, b = ARCHETYPES[kind](W, lvl)
        e.guid = "Other-" .. i
        e.target = mobs[1]
        others[i] = { e = W.add(e), b = b }
    end
    local pull, stop = 1, (o.duration or 120) + 1
    W.at(pull, function()
        W.emit({ kind = "pull" })
        behaviours.melee({
            rates = o.rates,
            land = observer.lag(o.lag),
            rage = o.rage or { 9, 5 },
            presses = o.presses,
            strike = { 70, 90 },
            dot = { 3, 5, 13 },
            proc = o.proc,
        })(W, us)
        for i = 1, #mobs do
            if i <= (o.attackers or 1) then
                behaviours.mob({ phase = 0.3 + W.rng.next() * 2 })(W, mobs[i])
            end
        end
        for _, x in ipairs(others) do
            x.b(W, x.e)
        end
    end)
    if o.damageBuff then
        W.at(o.damageBuff, function()
            us.dmgMult = 1.2
            W.emit({ kind = "buff" })
        end)
    end
    if o.formAt then
        W.at(o.formAt, function()
            us.form = 1
            for _, w in ipairs(us.weapons) do -- the form's own weapon damage: the cache holds the old one
                w[1], w[2] = math.floor(w[1] * 1.6), math.floor(w[2] * 1.6)
            end
            W.emit({ kind = "form", form = 1 })
        end)
    end
    for i, t in pairs(o.joinAt or {}) do -- attacker i turns to us at t
        W.at(t, function()
            mobs[i].target = us
            W.emit({ kind = "target" })
        end)
    end
    for _, sw in ipairs(o.switches or {}) do -- { t, attacker index, true: on us / false: off us }
        W.at(sw[1], function()
            mobs[sw[2]].target = sw[3] and us or nil
            W.emit({ kind = "target" })
        end)
    end
    W.at(stop, function()
        for _, e in ipairs(W.ents) do
            e.stopped = true
        end
        W.emit({ kind = "stop" })
    end)
    W.run(stop + 3)
    return W
end

--- The observed stream of a built world (knobs `o.lag` for the observer; `o.plainSpeed`, `o.usable` over them).
function M.stream(o, seed)
    local W = M.build(o, seed)
    local k = setmetatable({ plainSpeed = o.plainSpeed, usable = o.usable }, { __index = o.lag or observer.DEFAULTS })
    return observer.observe(W, k), W
end

--- The oracle's scenario knobs over `o`: usability answered from our true power (rage capped at 100) and a 10-rage
--- spender pressed every 2 s when the true rage covers it, so rage crosses the spenders' costs (10, 15) all fight.
function M.oracle(o)
    local presses = {}
    for t = 3, (o.duration or 120), (o.pressEvery or 2) do
        presses[#presses + 1] = { t, "CAST", 10, "cast" }
    end
    return setmetatable({ usable = true, max = 100, presses = presses }, { __index = o })
end

return M
