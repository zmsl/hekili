-- tests/Game/harness/scenarios.lua (harness design §3.1 layer 5, §3.2): a scenario is a roster, a behaviour per
-- entity and a timeline of set pieces (pull, stop, formChange, damageBuff, targetSwitch); between them the fight is
-- emergent. Our character auto-attacks and presses a scripted list. Archetypes by shape only (boundary rule).
local world = require("Game.harness.world")
local entities = require("Game.harness.entities")
local behaviours = require("Game.harness.behaviours")
local observer = require("Game.harness.observer")

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
--- The headless loop's knobs: weapons (ours [entities.weapons(level)]), mobHealth (our target's [1e9]: a kill ends
--- the fight), pull (its time [1]), prepull (the cache and target reads [pull - 0.5]), form (ours at the start [0]),
--- power (ours at the start [0]), tag (appended to the mobs' GUIDs: a fresh target per fight on one boot).
--- Several resources (GCD kinds design §2): pt (the swing-paid power type [1]), res ({ [pt] = { cur, max } }: the
--- others), regen ({ [pt] = per second }, from the prepull), fsr ({ [pt] = { spirit, mp5 } }: W.startRegen's five-
--- second rule), regenTick [0.1], regenAfter ({ s, k }), decay ({ pt, rate, interval, pausedBy }: from the stop), formSpeed ({ [form] = period }), payIn (the form whose swings pay), critRage
--- ({ main, off }), gcdOrder (1, 2 or "mixed") and gcdLatency [0] (W.press), script (fn(W, us): our presses, started
--- at the pull), after (seconds the world runs past the stop [3]).
--- Returns the world with every behaviour scheduled, not run (`M.build` runs it).
function M.world(o, seed)
    local W = world.new(seed)
    local lvl = o.level or 22
    local us = W.add(entities.new({
        guid = "Player-1",
        level = lvl,
        weapons = o.weapons or entities.weapons(lvl),
        powerMax = o.max or 1e6,
        pt = o.pt,
        res = o.res,
        formSpeed = o.formSpeed,
    }))
    us.form, us.power = o.form or 0, o.power or 0
    us.power0 = us.power -- the observer's first view (a batch stream reads the finished world)
    us.gcdOrder, us.gcdLatency = o.gcdOrder, o.gcdLatency
    local mobs = {}
    for i = 1, math.max(1, o.attackers or 1) do
        local m = o.mobs and o.mobs[i] or {}
        local dmg = m.damage or o.mobDamage or { 10, 14 }
        local mob = W.add(entities.new({
            guid = "Creature-" .. i .. (o.tag or ""),
            kind = "mob",
            level = lvl,
            dr = i == 1 and (o.dr or 0) or 0,
            weapons = { { dmg[1], dmg[2], m.period or o.mobPeriod or 2.0 } },
            health = i == 1 and o.mobHealth or 1e9,
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
    local pull = o.pull or 1
    local stop = (o.duration or 120) + pull
    if o.regen or o.fsr then -- before the prepull: its reads answer the rates
        W.at(0, function()
            W.startRegen(us, o.regen or {}, o.regenTick, o.regenAfter, o.fsr)
        end)
    end
    W.at(o.prepull or pull - 0.5, function() -- out of combat: the weapon damage cache and the target (observer.lua)
        W.emit({ kind = "prepull" })
    end)
    W.at(pull, function()
        W.emit({ kind = "pull" })
        behaviours.melee({
            rates = o.rates,
            land = observer.lag(o.lag),
            sameMs = (o.lag or observer.DEFAULTS).sameMs,
            rage = o.rage or { 9, 5 },
            critRage = o.critRage,
            payIn = o.payIn,
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
        if o.script then
            o.script(W, us)
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
        if o.decay then
            W.startDecay(us, o.decay)
        end
    end)
    W.stopAt, W.after = stop, o.after or 3
    return W
end

--- The world of one fight (M.world's knobs), run to `o.after` (3) s past its end.
function M.build(o, seed)
    local W = M.world(o, seed)
    W.run(W.stopAt + W.after)
    return W
end

--- The observed stream of a built world (knobs `o.lag` for the observer; `o.plainSpeed`, `o.usable` and the table
--- `o.observe` over them).
function M.stream(o, seed)
    local W = M.build(o, seed)
    local k = { plainSpeed = o.plainSpeed, usable = o.usable }
    for key, v in pairs(o.observe or {}) do
        k[key] = v
    end
    setmetatable(k, { __index = o.lag or observer.DEFAULTS })
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
