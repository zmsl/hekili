-- tests/Game/harness/scenarios.lua (harness design §3.1 layer 5, §3.2): a scenario is a roster, a behaviour per
-- entity and a timeline of set pieces (pull, stop, formChange, damageBuff, targetSwitch); between them the fight is
-- emergent. Our character auto-attacks and presses a scripted list. Archetypes by shape only (boundary rule).
local world = require("Game.harness.world")
local entities = require("Game.harness.entities")
local behaviours = require("Game.harness.behaviours")
local observer = require("Game.harness.observer")
local ab = require("Game.harness.ab")
local rng = require("Game.harness.rng")

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
    -- K13: a caster in lockstep with our bolt (nature, our amount band), phase-shifted by `W.phase` s
    lockstep = function(W, lvl)
        local e = entities.new({ level = lvl })
        return e,
            behaviours.caster({
                every = 1.5,
                cast = 1.5 + (W.phase or 0),
                amount = { 14, 18 },
                school = 8,
                resist = 0.05,
            })
    end,
    -- K13 (spec §6.2): our twin, anchored to our presses (W.spells): its cast at our success, its nature 14-18 row
    -- when our bolt lands (W.distance / 20 s later) plus W.phase, on its own outcome roll (resist 0.05, crit 0.1: a
    -- crit doubles, a miss is school 1, as W.hit). Each pair's order in one ms on W.rng: the twin's row first, or
    -- re-queued at its own time behind ours (the world's queue is FIFO within a time).
    twin = function(W, lvl)
        local e = entities.new({ level = lvl })
        return e,
            function(W2, me)
                for _, sp in ipairs(W2.spells or {}) do
                    local done = sp[1] + 1.5
                    W2.at(done, function()
                        if me.stopped or not me.target or me.target.health <= 0 then
                            return
                        end
                        local tgt = me.target
                        W2.emit({ kind = "cast", src = me, dst = tgt, spell = "SECRET" })
                        local function land()
                            if tgt.health <= 0 then
                                return
                            end
                            local r = W2.rng
                            local act = r.chance(0.05) and "MISS" or "WOUND"
                            local crit = act == "WOUND" and r.chance(0.1)
                            local amt = act == "WOUND" and r.int(14, 18) * (crit and 2 or 1) or 0
                            W2.emit({
                                kind = "spell",
                                src = me,
                                dst = tgt,
                                act = act,
                                flag = crit and "CRITICAL" or "",
                                amount = amt,
                                school = act == "WOUND" and 8 or 1,
                            })
                        end
                        W2.at(done + (W2.distance or 20) / 20 + (W2.phase or 0), function()
                            if W2.rng.chance(0.5) then
                                land()
                            else
                                W2.at(W2.t, land) -- behind our row of this ms
                            end
                        end)
                    end)
                end
            end
    end,
    -- K18: a melee whose swings also hit the mob beside our target (a splash)
    splash = function(W, lvl)
        local w = entities.weapons(lvl)[1]
        local e = entities.new({ weapons = { { w[1], w[2], 2.4 } }, level = lvl })
        return e, behaviours.melee({ rates = { miss = 0.05, crit = 0.1 }, splash = true })
    end,
}
M.ARCHETYPES = ARCHETYPES

-- shortcut: only the other sources on our target are simulated (the rest fire rows on tokens nothing reads), with no
-- heals on party members; add them when a customer reads them.

--- The world of one fight. Knobs `o` (defaults in brackets): duration [120], level [22], dr [0], rates (ours),
--- lag (observer knobs), others { archetype, ... } on our target [none], attackers [1] (mobs on us; the first is our
--- target), mobPeriod [2.0], mobDamage { lo, hi } [10-14], plainSpeed, damageBuff (t: +20% in combat), formAt (t),
--- presses ({ t, spell, cost, kind }), rage ({ main, off } [9, 5]), max (our power cap [1e6]), proc, mobs (per
--- attacker { damage = { lo, hi }, period }) and joinAt ({ [attacker] = t: on us from t }) for hits on us, switches.
--- The headless loop's knobs: weapons (ours [entities.weapons(level)]), ranged (our ranged hand { lo, hi, speed }, read
--- out of combat from the prepull; W.startRanged shoots it [none]), mobHealth (our target's [1e9]: a kill ends
--- the fight), pull (its time [1]), prepull (the cache and target reads [pull - 0.5]), form (ours at the start [0]),
--- power (ours at the start [0]), tag (appended to the mobs' GUIDs: a fresh target per fight on one boot).
--- Several resources (GCD kinds design §2): pt (the swing-paid power type [1]), res ({ [pt] = { cur, max } }: the
--- others), regen ({ [pt] = per second }, from the prepull), fsr ({ [pt] = { spirit, mp5, share?, auras? } }: W.startRegen's five-
--- second rule), regenTick [0.1], regenAfter ({ s, k }), decay ({ pt, rate, interval, pausedBy }: from the stop), formSpeed ({ [form] = period }), payIn (the form whose swings pay), critRage
--- ({ main, off }), gcdOrder (1, 2 or "mixed") and gcdLatency [0] (W.press), script (fn(W, us): our presses, started
--- at the pull), after (seconds the world runs past the stop [3]), distance (yards from our target from the start
--- [none: no positions]; W.moveTo changes it), bags, pet and stats (ours: entities.new's; the pet regenerates from the
--- start, W.startPetRegen), canParry (false: we never parry a swing at us, so no parry haste of ours; wowsims's
--- PseudoStats.CanParry, true only for some classes [true]), mobAvoid (the mobs' avoid table of our hits, entities.new's
--- `avoid` [its 5/5/5]), crit (our crit rate on an instant hit or strike, W.crit [world.CRIT]) and takenRage (W.takenRage:
--- the swing-paid power a landed wound on us pays [none]).
--- The detection suite's (unit-registry spec §6.2): noMelee (no white swings of ours), spells ({ t, kind }:
--- behaviours.ours, from the pull, with distance and jitter), switchTo ({ t, mob index }: our target changes), churn
--- ({ every, gap }: our target's plate leaves and comes back), extraMobs (mobs not on us, each with a plate), swapEvery
--- (s, or { lo, hi } drawn each time: our target moves to the next live mob that often from the pull), phase
--- (the lockstep archetype's shift), hitAtSwing (false: our white wound takes health at its land, not the swing),
--- actionTargeting and pushback (observer knobs, M.stream).
--- Returns the world with every behaviour scheduled, not run (`M.build` runs it).
function M.world(o, seed)
    local W = world.new(seed)
    local lvl = o.level or 22
    local weapons = o.twins and { { 30, 30, 2.0 }, { 30, 30, 2.0 } } or o.weapons
    local us = W.add(entities.new({
        guid = "Player-1",
        level = lvl,
        weapons = weapons or entities.weapons(lvl),
        powerMax = o.max or 1e6,
        pt = o.pt,
        res = o.res,
        formSpeed = o.formSpeed,
        ranged = o.ranged,
        bags = o.bags,
        pet = o.pet,
        stats = o.stats,
    }))
    if o.canParry == false then
        us.avoid.parry = 0
    end
    W.crit = o.crit or W.crit
    W.takenRage = o.takenRage
    if us.pet then
        W.startPetRegen(us)
    end
    us.form, us.power = o.form or 0, o.power or 0
    us.power0 = us.power -- the observer's first view (a batch stream reads the finished world)
    us.gcdOrder, us.gcdLatency = o.gcdOrder, o.gcdLatency
    local mobs = {}
    W.phase, W.hitAtSwing = o.phase, o.hitAtSwing ~= false
    W.spells = o.spells -- the twin archetype's anchors (K13; its flight from W.distance, the world's own)
    for i = 1, math.max(1, o.attackers or 1) + (o.extraMobs or 0) do
        local m = o.mobs and o.mobs[i] or {}
        local dmg = m.damage or o.mobDamage or { 10, 14 }
        local mob = W.add(entities.new({
            guid = "Creature-" .. i .. (o.tag or ""),
            kind = "mob",
            level = lvl,
            dr = i == 1 and (o.dr or 0) or 0,
            weapons = { { dmg[1], dmg[2], m.period or o.mobPeriod or 2.0 } },
            health = i == 1 and o.mobHealth or 1e9,
            creatureType = m.creatureType or o.creatureType,
            avoid = o.mobAvoid,
        }))
        mob.target = (i <= (o.attackers or 1) and not (o.joinAt and o.joinAt[i])) and us or nil
        mobs[i] = mob
        mob.plate = i > 1 and o.extraMobs ~= nil or nil
    end
    us.target = mobs[1]
    local others = {}
    for i, kind in ipairs(o.others or {}) do
        local e, b = ARCHETYPES[kind](W, lvl)
        e.guid = "Other-" .. i
        e.target = mobs[1]
        others[i] = { e = W.add(e), b = b }
    end
    if o.ourPet then -- K14: our pet on our target (the `pet` archetype's swings): its rows are not ours to pay
        local e, b = ARCHETYPES.pet(W, lvl)
        e.guid, e.target, e.ourPet = "Pet-1", mobs[1], true
        others[#others + 1] = { e = W.add(e), b = b }
    end
    local pull = o.pull or 1
    local stop = (o.duration or 120) + pull
    if o.distance then
        W.at(0, function()
            W.moveTo(us, o.distance)
        end)
    end
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
        local lag = o.lag or observer.DEFAULTS
        if o.sessionLag then -- K10: this session's landing lag, from [0.4, 1.0] s (one session's 988-456 ms)
            local med = 0.4 + 0.6 * W.crng.next()
            lag = setmetatable({ main = { med = med, sd = 0.04, tail = 0.15 }, firstLag = o.firstLag }, {
                __index = observer.DEFAULTS,
            })
        end
        behaviours.melee({
            rates = o.rates,
            land = observer.lag(lag),
            haste = o.haste,
            phase = o.twins and { 0.5, 0.5 } or nil,
            sameMs = (o.lag or observer.DEFAULTS).sameMs,
            rage = o.rage or { 9, 5 },
            critRage = o.critRage,
            payIn = o.payIn,
            presses = o.presses,
            strike = { 70, 90 },
            dot = { 3, 5, 13 },
            proc = o.proc,
            noSwing = o.noMelee,
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
    if o.spells then -- our scripted spells (the detection suite)
        W.at(pull, function()
            behaviours.ours({ spells = o.spells, distance = o.distance, jitter = o.jitter })(W, us)
        end)
    end
    for _, sw in ipairs(o.switchTo or {}) do -- { t, mob index }: our target changes (K5, K12, K19)
        W.at(sw[1], function()
            us.target = mobs[sw[2]]
            W.emit({ kind = "target" })
        end)
    end
    local every = o.swapEvery -- s or { lo, hi } (a drawn gap each): our target cycles through the live mobs
    if every then
        local r, i, t = rng.new(seed + 70011), 1, pull -- its own draws: no other draw moves
        local lo, hi = type(every) == "table" and every[1] or every, type(every) == "table" and every[2] or every
        while true do
            t = t + lo + (hi - lo) * r.next()
            if t >= stop then
                break
            end
            W.at(t, function()
                for _ = 1, #mobs do
                    i = i % #mobs + 1
                    if not mobs[i].dead then
                        break
                    end
                end
                us.target = mobs[i]
                W.emit({ kind = "target", relist = true }) -- the client's "target" auras follow (observer relist)
            end)
        end
    end
    if o.churn then -- { every, gap }: our target's plate leaves and comes back (K7)
        for t = pull + o.churn[1], stop, o.churn[1] do
            W.at(t, function()
                W.emit({ kind = "plateOff", mob = mobs[1] })
            end)
            W.at(t + o.churn[2], function()
                W.emit({ kind = "plateOn", mob = mobs[1] })
            end)
        end
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
    local k = {
        plainSpeed = o.plainSpeed,
        usable = o.usable,
        actionTargeting = o.actionTargeting,
        pushback = o.pushback,
        enterCombat = o.enterCombat,
        meter = o.meter,
        viewer = o.viewer,
        takenLag = o.takenLag,
        group = o.group,
    }
    ab.observe(k) -- a provider arm's shapes (make gate-ab)
    for key, v in pairs(o.observe or {}) do
        k[key] = v
    end
    setmetatable(k, { __index = o.lag or observer.DEFAULTS })
    return observer.observe(W, k), W
end

-- The Cooldown Manager's four viewers (fake_api.VIEWERS order: category 0 Essential, 1 Utility, 2 Buff icon, 3 Buff bar).
local VIEWERS =
    { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local CD0 = 910000 -- the layouts' own cooldownIDs (a fixture's keep theirs)

--- The Cooldown Manager layout `preset` (cdm-default plan Task 8, decision 110) on an instance's fake `ctl`, for the
--- fight of `seed`; `o` { pull, duration, fixture }. The frames are built ONCE an instance (the leaf gives each frame a
--- slot for the session, MAX_SLOTS 128): a later fight clears every aura, undoes the re-point and the hidden viewer,
--- and adds no frame. Returns the fight's layout events { t, ev, a1, a2, a3, a4 } (drive.op's `@viewerLayout` and
--- `@viewerShown`), or nil for "fixture" with no fixture (the arm is skipped). Presets:
--- `none` no item; `buffs` one Buff icon item per pack aura; `fixture` the class fixture's entries (by category) plus
--- an Essential entry per ability whose aura the pack registers (F6); `mixed` 0-3 items an aura over the four viewers
--- (at least one), two unconfigured Buff bar slots, a silent item (F12) beside a working one of the same aura, an
--- Essential item held with no unit (a stress flag, not a client state: BD:368-379 records the unit), and per fight
--- one viewer hidden for 10 s and one re-point, the Utility pool growing in the first fight only, and
--- `ctl.viewer.lag = 1` on even seeds (the seen rule's lagging item, I-B).
--- Every item names all of its aura's IDs (linkedSpellIDs), so any rank the world applies lights it.
function M.viewerLayout(ctl, def, preset, seed, o)
    local V = ctl.viewer
    V.log = false -- no write log in the loops (L279: one entry a light, unbounded over a boot)
    local L = V.layout
    if L then -- a later fight: the same frames, reset
        ctl.ViewerReset()
        for _, name in ipairs(VIEWERS) do
            for _, item in ipairs(V.items[name]) do
                if item.base then
                    item.cooldownID = item.base
                end
            end
        end
        V.shown, V.parentShown = {}, true
    elseif preset == "fixture" and not o.fixture then
        return nil
    else
        L = { cds = {}, n = 0, mapped = {} }
        V.layout = L
        local function cdFor(j, category) -- aura j's entry in category category: one cooldownID, in that category's set
            local key = j * 4 + category
            if not L.cds[key] then
                L.n = L.n + 1
                local id = CD0 + L.n
                L.cds[key] = id
                local ids = def.auraIds[j]
                V.infos[id] = { spellID = ids[1], linkedSpellIDs = ids }
                V.sets[category][#V.sets[category] + 1] = id
            end
            return L.cds[key]
        end
        local function add(category, id)
            local list = V.items[VIEWERS[category + 1]]
            local item = ctl.ViewerItem(VIEWERS[category + 1], #list + 1, id)
            item.base = id
            return item
        end
        local auras = {} -- the pack's auras with a spell ID (an id-less enchant's pseudo-ID is negative)
        for j = 1, #def.auraIds do
            if def.auraIds[j][1] > 0 then
                auras[#auras + 1] = j
            end
        end
        L.auras = auras
        if preset == "buffs" then
            for _, j in ipairs(auras) do
                add(2, cdFor(j, 2))
            end
        elseif preset == "fixture" then
            local ids = {}
            for id in pairs(o.fixture) do
                ids[#ids + 1] = id
            end
            table.sort(ids) -- pairs order is not stable: the layout must be
            for _, id in ipairs(ids) do
                local e = o.fixture[id]
                V.infos[id] = { spellID = e[2], overrideSpellID = e[3], linkedSpellIDs = e[4] }
                V.sets[e[1]][#V.sets[e[1]] + 1] = id
                if e[1] <= 3 then
                    add(e[1], id)
                end
            end
            local byKey = {}
            for _, j in ipairs(auras) do
                byKey[def.auras[j].key] = j
            end
            for i, a in ipairs(def.abilities) do
                local j = byKey[a.key]
                if j then -- the ability's cooldown entry holds its aura (F6)
                    L.n = L.n + 1
                    local id = CD0 + L.n
                    V.infos[id] = { spellID = def.abilityIds[i][1], linkedSpellIDs = def.auraIds[j] }
                    V.sets[0][#V.sets[0] + 1] = id
                    add(0, id)
                end
            end
        elseif preset == "mixed" then
            local r = rng.new(seed + 70001) -- the layout's own draws: no other draw moves
            for _, j in ipairs(auras) do
                for category = 0, 3 do -- every aura's entry in every category is in the sets (a re-point stays mapped)
                    cdFor(j, category)
                end
                for _ = 1, r.int(0, 3) do
                    local category = r.int(0, 3)
                    L.mapped[#L.mapped + 1] = { add(category, cdFor(j, category)), category, j }
                end
            end
            if not L.mapped[1] and auras[1] then -- at least one item
                L.mapped[1] = { add(2, cdFor(auras[1], 2)), 2, auras[1] }
            end
            if L.mapped[1] then
                add(2, cdFor(L.mapped[1][3], 2)).silent = true -- never lights (F12), beside a working item of its aura
                add(0, cdFor(r.pick(auras), 0)).noUnit = true -- held, unit nil: a stress of the leaf, not a client state
                L.grow = cdFor(r.pick(auras), 1)
            end
            add(3, nil) -- two unconfigured slots
            add(3, nil)
        end
    end
    V.lag = preset == "mixed" and seed % 2 == 0 and 1 or false
    local ev = {}
    if preset == "mixed" and L.mapped[1] then
        local r = rng.new(seed + 70003)
        local t = o.pull + r.next() * math.max(0, o.duration - 10)
        local name = VIEWERS[r.int(1, 4)]
        ev[#ev + 1] = { t, "@viewerShown", name, false }
        ev[#ev + 1] = { t + 10, "@viewerShown", name, true }
        local m = L.mapped[r.int(1, #L.mapped)]
        local a = L.auras[r.int(1, #L.auras)] -- another aura's entry in the same viewer (its own when drawn again)
        local to = L.cds[a * 4 + m[2]]
        ev[#ev + 1] = { o.pull + r.next() * o.duration, "@viewerLayout", "repoint", VIEWERS[m[2] + 1], m[1].base, to }
        if not L.grown then
            L.grown = true
            ev[#ev + 1] = { o.pull + r.next() * o.duration, "@viewerLayout", "acquire", VIEWERS[2], L.grow }
        end
        table.sort(ev, function(x, y)
            return x[1] < y[1]
        end)
    end
    return ev
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
