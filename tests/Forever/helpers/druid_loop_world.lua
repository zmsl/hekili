-- tests/Forever/helpers/druid_loop_world.lua (class-completion plan, "The per-pack gate"): the Druid content of the
-- class-neutral headless loop, in warrior_world.lua's shape, one content per pack (M.Feral, M.Guardian, M.Balance):
-- the character the instance logs in as, each ability's press in the world's generic verbs, the client's usability
-- answers and the true power per landed swing. Forms, the rage rules and Shifting Power's energy come from
-- druid_world.lua's reads of the class file; IDs, costs, cooldowns, cast times and durations from the class file
-- (load_druid's recording load for the character, the booted oracle's Hekili.Class and Hekili.State for the rest),
-- never copied here. Damage amounts, the weapons, Omen of Clarity's rate and Innervate's mana are UNMEASURED: the gate
-- scores the belief and the picks, not the damage. Credit: wowsims/forever (MIT) as the reference for the priorities
-- the packs follow; no code copied.
local ld = require("Forever.helpers.load_druid")
local dw = require("Forever.helpers.druid_world")
local world = require("Game.harness.world")

local M = {}

M.CLIENT_SPEC, M.CLASS_ID = 1483, 11 -- the client's Druid pseudo-spec
local MANA, RAGE, ENERGY, POINTS = dw.MANA, dw.RAGE, dw.ENERGY, dw.POINTS
local TOKENS = dw.TOKENS

-- The client's forms: druid_world's order, then Moonkin (Forms.lua maps them by spell ID, so the order changes
-- nothing).
local FORMS = { "bear_form", "aquatic_form", "cat_form", "travel_form", "moonkin_form" }
local FORM = {}
for i, key in ipairs(FORMS) do
    FORM[key] = i
end
-- A form field that names a group: the class file's `feral_form` alias.
local GROUP = { feral_form = { [FORM.cat_form] = true, [FORM.bear_form] = true } }

-- UNMEASURED: Omen of Clarity's chance per press of ours (about one Clearcasting every 10 presses), Innervate's mana a
-- second over its 20 s (the worlds that keep mana: Balance's and Feral's), and the hits' amounts.
local OMEN = 0.1
local INNERVATE_MANA = 100
-- the generic hits' non-physical schools (DB2); the rest physical (1)
local SCHOOL = { faerie_fire = 8, moonfire = 64 }
local AMOUNT = {
    claw = 90,
    shred = 160,
    rake = 40,
    ferocious_bite = 300,
    primal_bite = 120,
    lacerate = 30,
    swipe_bear = 80,
    wrath = 250,
    starfire = 500,
    moonfire = 100,
}

-- The recording load (talents at rank 0), once: the aura data and the cost modifier's covered spells.
local W0
local function class()
    W0 = W0 or ld.load()
    return W0
end
local R0
local function rules()
    R0 = R0 or dw.rules()
    return R0
end

-- The effects, in the world's verbs; `X` the class data (X.aura[key] = { id, duration, max_stack }).
local function aura(W, X, dst, key, stacks)
    local a = X.aura[key]
    W.applyAura(dst, a.id, a.duration, stacks or 1, a.max_stack)
end
-- Aura `id` on `dst` to `n` stacks, its expiry kept (0: gone): a charge spent, a proc used.
local function setStacks(W, dst, id, n)
    local a = dst.auras[id]
    if not a then
        return
    end
    if n <= 0 then
        dst.auras[id] = nil
        W.emit({ kind = "aura", dst = dst, aura = id, stacks = 0, expires = 0, duration = 0 })
    else
        a.stacks = n
        W.emit({ kind = "aura", dst = dst, aura = id, stacks = n, expires = a.expires, duration = a.duration })
    end
end
local function hit(key)
    return function(W, e)
        W.hit(e, e.target, AMOUNT[key], SCHOOL[key] or 1)
    end
end
-- A bear strike's hit (`key`'s amount; with `debuffKey`, the debuff when it lands): Primal Fury's rage on its crit in
-- Bear Form (X.primalFury, the class file's rule at the character's rank). Maul's queued strike never crits in the
-- world (behaviours.lua's strike frame), so it pays none.
local function bearHit(key, debuffKey)
    return function(W, e, _, X)
        local r = W.hit(e, e.target, AMOUNT[key], SCHOOL[key] or 1)
        if r.act == "WOUND" and debuffKey then
            aura(W, X, e.target, debuffKey)
        end
        if r.flag == "CRITICAL" and e.form == FORM.bear_form and X.primalFury > 0 then
            W.gain(e, X.primalFury)
        end
    end
end
local function selfAura(key)
    return function(W, e, _, X)
        aura(W, X, e, key)
    end
end
local function debuff(key, alsoHit) -- the debuff when its hit (for `key`'s amount, or none) lands
    return function(W, e, _, X)
        if W.hit(e, e.target, alsoHit and AMOUNT[key] or nil, SCHOOL[key] or 1).act == "WOUND" then
            aura(W, X, e.target, key)
        end
    end
end
local function shift(key, mult)
    return {
        extra = function(p)
            local R = rules()
            local onEnter = key == "bear_form" and R.enterBear or (key == "cat_form" and R.enterCat or nil)
            p.shift = { form = FORM[key], dmgMult = mult, onEnter = onEnter }
        end,
    }
end

-- The avoids each press rolls when not the special melee tables' (world.OUTCOMES, from wowsims/forever's druid/*.go):
-- Pounce and Ravage can be missed only (OutcomeMeleeSpecialNoBlockDodgeParry*), the spells are magic hits
-- (OutcomeMagicHit*).
M.OUTCOMES = {
    pounce = "miss",
    ravage = "miss",
    faerie_fire = "spell",
    demoralizing_roar = "spell",
    wrath = "spell",
    starfire = "spell",
    moonfire = "spell",
    insect_swarm = "spell",
    hurricane = "spell",
}

-- Each recommendable ability: `effect(W, e, p, X)`, `requires(W, e)` (beyond the form fields), `points` (combo points:
-- 1 on a landed hit, "all" spent), `drain`, `extra(p, pt, res)` (generic effects; the world's main power and other
-- pools). A key missing here fails the loop.
M.MAP = {
    cat_form = shift("cat_form", 1),
    bear_form = shift("bear_form", 1),
    moonkin_form = shift("moonkin_form", 1),
    claw = { effect = hit("claw"), points = 1 },
    shred = { effect = hit("shred"), points = 1 },
    rake = { -- the debuff only on a landed hit (the class file removes a missed one from the combat log)
        effect = function(W, e, _, X)
            if W.hit(e, e.target, AMOUNT.rake, 1).act == "WOUND" then
                aura(W, X, e.target, "rake")
            end
        end,
        points = 1,
    },
    rip = { effect = debuff("rip"), points = "all" },
    ferocious_bite = { effect = hit("ferocious_bite"), points = "all", drain = ENERGY },
    shifting_power = {
        extra = function(p)
            p.gain = { ENERGY, rules().shiftingPower }
        end,
    },
    berserk = { -- Berserk also ends Primal Bite's running cooldown (the class file's handler; wowsims's log)
        effect = function(W, e, _, X)
            aura(W, X, e, "berserk")
            local a = class().abilities.primal_bite
            W.resetCooldown(e, "primal_bite", { a.id, unpack(a.copy or {}) })
        end,
    },
    faerie_fire = { effect = debuff("faerie_fire") },
    mark_of_the_wild = { effect = selfAura("mark_of_the_wild") },
    elunes_light = { effect = selfAura("elunes_light") }, -- the Night Elf racial (Hekili_Shared): its buff only
    thorns = { effect = selfAura("thorns") },
    -- leaves the form (the client unshifts to cast it) but Moonkin (wowsims/forever: castable in Moonkin Form; UNMEASURED
    -- on Forever, the class file's rule); mana only where the world keeps it
    innervate = {
        effect = function(W, e, p, X)
            if e.form ~= 0 and e.form ~= FORM.moonkin_form then
                W.setForm(e, 0)
            end
            aura(W, X, e, "innervate")
        end,
        extra = function(p, pt, res)
            if pt == MANA or res[MANA] then
                local a = class().auras.innervate
                p.aura = { id = a.id, duration = a.duration, tick = { pt = MANA, every = 1, amount = INNERVATE_MANA } }
            end
        end,
    },
    primal_bite = { effect = bearHit("primal_bite") }, -- its cooldown the state's (none while Berserk is up)
    lacerate = { effect = bearHit("lacerate", "lacerate") },
    swipe_bear = { effect = bearHit("swipe_bear") },
    demoralizing_roar = { effect = debuff("demoralizing_roar") },
    maul = { amount = { 110, 140 } },
    enrage = {
        extra = function(p)
            local R, a = rules(), class().auras.enrage
            p.gain = { RAGE, R.enrage }
            p.aura =
                { id = a.id, duration = a.duration, tick = { pt = RAGE, every = R.tick.every, amount = R.tick.amount } }
        end,
    },
    frenzied_regeneration = { effect = selfAura("frenzied_regeneration") }, -- its rage-to-health unmodelled
    wrath = { -- Eclipse's charges with the talent, the class file's rule (2 a Wrath, at most the aura's stacks)
        effect = function(W, e, _, X)
            W.hit(e, e.target, AMOUNT.wrath, 8)
            if X.eclipse then
                aura(W, X, e, "eclipse", 2)
            end
        end,
    },
    starfire = { -- spends a charge
        effect = function(W, e, _, X)
            W.hit(e, e.target, AMOUNT.starfire, 64)
            local a = e.auras[X.aura.eclipse.id]
            if a then
                setStacks(W, e, X.aura.eclipse.id, a.stacks - 1)
            end
        end,
    },
    moonfire = {
        effect = function(W, e, _, X)
            local d = X.aura.moonfire.duration
            if W.hit(e, e.target, AMOUNT.moonfire, 64).act == "WOUND" then
                aura(W, X, e.target, "moonfire")
                W.dot(e, e.target, 3, math.floor(d / 3), 40, 64)
            end
        end,
    },
    insect_swarm = {
        effect = function(W, e, _, X)
            local d = X.aura.insect_swarm.duration
            if W.hit(e, e.target, nil, 8).act == "WOUND" then
                aura(W, X, e.target, "insect_swarm")
                W.dot(e, e.target, 2, math.floor(d / 2), 30, 8)
            end
        end,
    },
    hurricane = { effect = hit("moonfire") }, -- the AoE list only (one mob: never)
}

-- A finisher needs a combo point (the client answers it unusable without one).
for _, key in ipairs({ "rip", "ferocious_bite" }) do
    M.MAP[key].requires = function(W, e)
        return W.res(e, POINTS) > 0, "no combo points"
    end
end

-- The three packs' worlds. `kit` the abilities the character knows (every rank), `talents` by spell ID, `power` the
-- swing-paid or main power, `res` the others the world keeps, `form` at the pull, the main hand, `world` knobs over
-- the loop's, `uptime` the debuffs reported.
local PACKS = {
    Feral = {
        kit = {
            "cat_form",
            "aquatic_form",
            "travel_form",
            "bear_form",
            "claw",
            "shred",
            "rake",
            "rip",
            "ferocious_bite",
            "shifting_power",
            "berserk",
            "faerie_fire",
            "innervate",
            "mark_of_the_wild",
            "thorns",
        },
        power = { type = ENERGY, token = TOKENS[ENERGY], max = 100 },
        -- mana: wowsims/forever's Feral log's pool (pre-raid gear) and regen (2.175 a 0.1 s tick outside the
        -- five-second rule, none inside it: { spirit, mp5 } = { 22, 0 } a second)
        res = { [POINTS] = { cur = 0, max = 5 }, [MANA] = { cur = 2674, max = 2674 } },
        form = "cat_form",
        weapon = { 55, 75, 1.0 },
        world = { regen = { [ENERGY] = dw.ENERGY_REGEN }, fsr = { [MANA] = { 22, 0 } }, power = 100 },
        uptime = { "rip", "rake" },
    },
    Guardian = {
        kit = {
            "bear_form",
            "cat_form",
            "aquatic_form",
            "travel_form",
            "maul",
            "swipe_bear",
            "primal_bite",
            "lacerate",
            "demoralizing_roar",
            "enrage",
            "frenzied_regeneration",
            "berserk",
            "faerie_fire",
            "innervate",
            "mark_of_the_wild",
            "thorns",
        },
        talents = { [16958] = 2 }, -- Primal Fury (wowsims's bear build's 2/2): its rage on our crits
        power = { type = RAGE, token = TOKENS[RAGE], max = 100 },
        res = {},
        form = "bear_form",
        weapon = { 88, 120, 2.5 },
        -- a boss: the pack stacks Lacerate on one; out of combat rage decays as the class file's meta says (1.25 a
        -- second, stepped and front-loaded)
        world = { targetLevel = -1, payIn = FORM.bear_form, decay = { pt = RAGE, rate = 1.25, interval = 1 } },
        uptime = { "lacerate", "demoralizing_roar" },
    },
    Balance = {
        kit = {
            "moonkin_form",
            "cat_form",
            "aquatic_form",
            "travel_form",
            "bear_form",
            "wrath",
            "starfire",
            "moonfire",
            "insect_swarm",
            "hurricane",
            "innervate",
            "faerie_fire",
            "mark_of_the_wild",
            "thorns",
        },
        talents = { [408248] = 1 }, -- Eclipse (the placeholder node): Wrath's charges
        power = { type = MANA, token = TOKENS[MANA], max = 4000 },
        res = {},
        form = "moonkin_form",
        weapon = { 40, 60, 2.0 },
        -- the five-second rule's { spirit, mp5 } parts a second: wowsims/forever's Balance log (2.2 mana a 0.1 s tick
        -- outside the rule, none inside it but Innervate's; prebis gear)
        world = { power = 4000, fsr = { [MANA] = { 22, 0 } } },
        uptime = { "moonfire", "insect_swarm" },
    },
}

-- The class data a press reads from a booted instance `H` (once per instance): each aura's ID, duration and stacks,
-- whether the Eclipse talent is known, the Clearcasting cost modifier's covered spell IDs.
local cache = setmetatable({}, { __mode = "k" })
-- shortcut: the latest booted oracle's Primal Fury rage (classData), for C.gain's white crits, which get no instance;
-- right while one loop runs at a time (the loop boots its oracle, then reads usable(H)); upgrade if loops interleave.
local pfRage = 0
local function classData(H)
    if cache[H] then
        pfRage = cache[H].primalFury
        return cache[H]
    end
    local X = { aura = {}, covered = {} }
    cache[H] = X
    for key, a in pairs(H.Hekili.Class.auras) do
        if type(key) == "string" and type(a) == "table" and a.id then
            local d = a.duration -- a function of the talents (Insect Swarm's): the booted state's answer
            X.aura[key] = { id = a.id, duration = type(d) == "function" and d() or d or 0, max_stack = a.max_stack }
        end
    end
    X.eclipse = (H.Hekili.State.talent.eclipse.rank or 0) > 0
    -- Primal Fury's rage on a crit of ours in Bear Form at the character's rank: the class file's white-crit rule read
    -- under the booted state's talents, less its rank-0 crit (the recording load's)
    local w, base = class(), rules().crit
    local talent = w.state.talent
    w.state.talent = H.Hekili.State.talent
    X.primalFury = w.resources[RAGE].models.mainhand.crit() - base
    w.state.talent = talent
    pfRage = X.primalFury
    X.cc = class().costMods[1]
    for _, id in ipairs(X.cc.spells) do
        X.covered[id] = true
    end
    return X
end

-- Whether `e`'s true form meets ability `a`'s form / nobuff fields (a function field: the class file's choice,
-- Berserk's "Cat or Bear"; read from `funcs`, as Hekili's ability table answers it evaluated in its own state).
local function formOk(a, e)
    local need, avoid = a.funcs and a.funcs.form or a.form, a.nobuff
    if type(need) == "function" then
        need = nil
        if e.form ~= FORM.cat_form and e.form ~= FORM.bear_form then
            return false, "a feral form"
        end
    end
    if need and FORM[need] and e.form ~= FORM[need] then
        return false, need
    elseif avoid and (FORM[avoid] and e.form == FORM[avoid] or GROUP[avoid] and GROUP[avoid][e.form]) then
        return false, "not " .. avoid
    end
    return true
end

local function content(name)
    local P = PACKS[name]
    local C = { PACK = name .. " (wowsims.com)", IDS = {} } -- the spec's default (wowsims packs plan, P9)
    C.SPEC = ({ Balance = 100111, Feral = 100112, Guardian = 100113 })[name]
    local pt = P.power.type

    function C.character()
        local w = class()
        local known = {}
        for _, key in ipairs(P.kit) do
            local a = assert(w.abilities[key], key)
            local ids = { a.id }
            for _, id in ipairs(type(a.copy) == "table" and a.copy or {}) do
                ids[#ids + 1] = id
            end
            C.IDS[key] = ids
            for _, id in ipairs(ids) do
                known[#known + 1] = id
            end
        end
        local talents = {}
        for id, r in pairs(P.talents or {}) do
            talents[id] = r
        end
        local forms = {}
        for i, key in ipairs(FORMS) do
            forms[i] = C.IDS[key] and w.abilities[key].id or nil
        end
        return {
            class = "DRUID",
            classID = M.CLASS_ID,
            specID = M.CLIENT_SPEC,
            level = 60,
            known = known,
            talents = talents,
            power = P.power,
            speed = { P.weapon[3] },
            forms = forms,
            form = FORM[P.form],
        }
    end

    -- The world's knobs (scenarios.world's): level 60 against a level 60 mob in melee range, the main hand, the main
    -- power's cap, the other resources, the forms' periods, a mob of 15000 health (about 3 minutes).
    C.WORLD = setmetatable({
        level = 60,
        weapons = { P.weapon },
        max = P.power.max,
        res = P.res,
        formSpeed = { [FORM.bear_form] = dw.SPEED[dw.BEAR], [FORM.cat_form] = dw.SPEED[dw.CAT] },
        mobHealth = 15000,
    }, { __index = P.world })

    -- The client's other power reads: combo points plain (research addendum), the rest never. UnitPowerMax answers the
    -- world's pools where it keeps mana (Feral's 2674, Balance's 4000; else the fake's 100).
    C.OBSERVE = {
        plainPower = { [POINTS] = "always" },
        powerTokens = TOKENS,
        powerMax = pt == MANA or P.res[MANA] ~= nil,
    }

    -- True rage per landed white wound in Bear (the class file's model, druid_world's rules); no other power is
    -- swing-paid.
    function C.gain(p, hand, _, flag)
        if p ~= RAGE or hand ~= 1 then
            return 0
        end
        local R = rules()
        return R.swing + (flag == "CRITICAL" and R.crit + pfRage or 0)
    end

    -- The press's cost: the state's for the main power and any other the world keeps (Clearcasting's, from the
    -- run's truth instance: loop.run's), none for one it does not (mana in the Guardian world).
    local function cost(key, a, H, X)
        local c = H.Hekili.State.action[key].cost or 0
        local spendPt = ({ mana = MANA, rage = RAGE, energy = ENERGY })[a.spendType]
        if spendPt ~= pt and not P.res[spendPt] then
            return 0, nil
        elseif spendPt ~= pt then -- a kept pool's: the declared cost, priced as the engine prices it (ns.SpendPoints)
            local f = rawget(a, "declaredSpend") or a.spend
            c = type(f) == "function" and f() or f or 0
            return H.ns.SpendPoints(c, H.Hekili.State[a.spendType], a), spendPt
        end
        if X.covered[a.id] and H.ns.VirtualState.Aura("player", X.aura.clearcasting.id, H.ctl.now) then
            return 0, spendPt, true
        end
        return c, spendPt
    end

    --- The resolved press of `key` from instance `H` (the loop passes its run's truth instance): the highest
    --- known rank's ID and every known rank's, the cost, its cooldown, GCD and cast time as the state has them, the
    --- form fields and the mapping's effects; Omen of Clarity rolled on every press. Raises "unmapped key".
    function C.resolve(key, H)
        local m = M.MAP[key]
        if not m then
            error("unmapped key " .. tostring(key), 2)
        end
        local a = H.Hekili.Class.abilities[key]
        local X = classData(H)
        local S = H.Hekili.State
        local c, cpt, free = cost(key, a, H, X)
        local p = {
            spell = H.ns.VirtualState.KnownID(a.id),
            ids = C.IDS[key],
            cost = c,
            pt = cpt,
            cooldown = tonumber(a.cooldown) or S.action[key].cooldown or 0,
            gcd = dw.GCD[a.gcd or "spell"],
            offGcd = a.gcd == "off",
            cast = S.action[key].cast_time or tonumber(a.cast) or 0,
            onNextSwing = a.onNextSwing,
            amount = m.amount,
            drain = m.drain,
            refund = world.refundOf(H.Hekili.Class, key), -- an avoid gives back the kit's share (W.hit)
            outcomes = M.OUTCOMES[key], -- nil: the special melee tables
        }
        if m.points then
            p.points = { POINTS, m.points }
        end
        if m.extra then
            m.extra(p, pt, P.res)
        end
        p.requires = function(W, e)
            local ok, why = formOk(a, e)
            if ok and m.requires then
                ok, why = m.requires(W, e)
            end
            return ok, why
        end
        p.effect = function(W, e)
            if free then -- Clearcasting used
                setStacks(W, e, X.aura.clearcasting.id, 0)
            end
            if m.effect then
                m.effect(W, e, p, X)
            end
            -- shortcut: the proc lands a tick after the cast it rolled on, so the belief prices that cast before it
            -- sees Clearcasting (in game both can arrive in one frame: the in-game check); upgrade with a measured
            -- order.
            if W.rng.chance(OMEN) then
                W.at(W.t + 0.25, function()
                    aura(W, X, e, "clearcasting")
                end)
            end
        end
        return p
    end

    --- The client's usability answers for every known rank of every mapped kit ability, from instance `H`: unusable
    --- (not for power) out of form or when the mapping's requirement fails in the true world, else usable when the
    --- client's view of the cost's power covers it, short when not (Clearcasting: free).
    function C.usable(H)
        local out = {}
        local X = classData(H)
        for key, m in pairs(M.MAP) do
            local a = H.Hekili.Class.abilities[key]
            if a and C.IDS[key] then
                local c = H.Hekili.State.action[key].cost or 0
                local cpt = ({ rage = RAGE, energy = ENERGY, mana = MANA })[a.spendType]
                local covered = X.covered[a.id]
                local function answer(W, e, power, view)
                    if not formOk(a, e) or (m.requires and not m.requires(W, e)) then
                        return false, false
                    end
                    -- Clearcasting from the world's truth (an answer is the client's, and no instance's state is the
                    -- truth in every run: ws.live and the replay step ours alone)
                    local cc = covered and e.auras[X.aura.clearcasting.id]
                    if cc and cc.stacks > 0 then
                        return true, false
                    end
                    -- mana where the world keeps none (the feral loop worlds; ws.live passes no view): never short
                    local have = (cpt == nil and math.huge)
                        or (cpt == e.pt and power)
                        or (view and view[cpt])
                        or (cpt == MANA and math.huge)
                        or 0
                    return have >= c, have < c
                end
                for _, id in ipairs(C.IDS[key]) do
                    out[#out + 1] = { id, answer }
                end
            end
        end
        table.sort(out, function(x, y)
            return x[1] < y[1]
        end)
        return out
    end

    --- The debuffs whose uptime the loop reports and self-checks: { { key, auraID } } from instance `H`.
    function C.uptime(H)
        local out = {}
        for _, key in ipairs(P.uptime) do
            out[#out + 1] = { key, H.Hekili.Class.auras[key].id }
        end
        return out
    end

    return C
end

M.Feral, M.Guardian, M.Balance = content("Feral"), content("Guardian"), content("Balance")
M.FORM = FORM

return M
