-- tests/Forever/helpers/druid_world.lua (GCD kinds design §3-§4): the Druid content of the class-neutral combat
-- harness: the character's resources, forms and rates, each ability's press in the world's generic verbs, the client's
-- usability answers and the fights the gates run (tests/Forever/druid_harness_spec.lua). Spell and aura IDs, costs,
-- GCD kinds, cooldowns, durations, form requirements, the rage per swing, Enrage's ticks, the decay, the entry rules
-- of a shift and Shifting Power's energy come from the class file (load_druid.lua's recording load, its `now` and
-- `swap_form` run in the stand-in state), never copied here. Damage amounts and the weapon are UNMEASURED: the
-- scenarios score the belief, not the damage.
local ld = require("Forever.helpers.load_druid")
local dvs = require("Forever.helpers.druid_vs")
local drive = require("Game.harness.drive")
local scenarios = require("Game.harness.scenarios")
local fs = require("Game.State.helpers.fake_spec")

local M = {}

M.MANA, M.RAGE, M.ENERGY, M.POINTS = 0, 1, 3, 4 -- Enum.PowerType
local PT = { mana = M.MANA, rage = M.RAGE, energy = M.ENERGY, combo_points = M.POINTS }
M.TOKENS = { [M.MANA] = "MANA", [M.RAGE] = "RAGE", [M.ENERGY] = "ENERGY", [M.POINTS] = "COMBO_POINTS" }

-- The client's forms in Classic's index order (Forms.lua maps them by spell ID, so the real order (Q2) changes nothing).
M.FORMS = { "bear_form", "aquatic_form", "cat_form", "travel_form" }
M.FORM = {}
for i, key in ipairs(M.FORMS) do
    M.FORM[key] = i
end
M.BEAR, M.CAT = M.FORM.bear_form, M.FORM.cat_form
-- The main hand's period in each form (Classic's; checkpoint G6 reads them) and its damage against Cat's (UNMEASURED).
M.SPEED = { [M.BEAR] = 2.5, [M.CAT] = 1.0 }
M.DMG = { [M.BEAR] = 1.6, [M.CAT] = 1.0 }
M.WEAPON = { 55, 75 } -- the paws' white damage in Cat (UNMEASURED)
M.ENERGY_REGEN = 10 -- energy a second (probe W's out-of-combat read: 10.001)
-- GCD seconds by kind, at haste 1 (Hekili's kinds; the DB2's StartRecoveryTime; checkpoints G1-G3).
M.GCD = { totem = 1.0, spell = 1.5, off = 0 }
-- UNMEASURED amounts of the instant strikes (a hit on the target: Rows.lua credits it to the cast).
local AMOUNT = {
    claw = 90,
    shred = 160,
    rake = 40,
    ferocious_bite = 300,
    primal_bite = 120,
    lacerate = 30,
    swipe_bear = 80,
}

-- The recording load and its stand-in state (talents at rank 0), once.
local W0, E0
local function class()
    if not W0 then
        W0 = ld.load()
        E0 = ld.env(W0)
    end
    return W0, E0
end

-- What a `now` gains, by resource key (the class file's own amounts: Shifting Power's energy, Enrage's rage).
local function nowGains(key)
    local w, e = class()
    e.gained = {}
    ld.run(w.abilities[key].now, e)
    local out = {}
    for _, g in ipairs(e.gained) do
        out[#out + 1] = { PT[g[2]], g[1] }
    end
    return out
end

-- A shift's entry rule per resource, from the class file's swap_form at 50 rage: "zero" when it spends it all.
local function entryRules(form)
    local w, e = class()
    e.spent, e.rage.current, e.energy.current = {}, 50, 50
    e.swap_form(form)
    local rules = { [M.RAGE] = "keep", [M.ENERGY] = "keep" }
    for _, s in ipairs(e.spent) do
        if s[1] == 50 then
            rules[PT[s[2]]] = "zero"
        end
    end
    return rules
end

-- The rage entries of the class file's model: per white swing in Bear (`value`, `crit`), Enrage's ticks, the decay.
local function rageModel()
    local w = class()
    local r = w.resources[M.RAGE]
    return r.models, r.meta
end

--- The world's rates and rules read from the class file: { swing, crit, payIn, tick = { every, amount }, decay = {
--- rate, interval }, enterBear, enterCat, shiftingPower (energy), enrage (rage at once) }.
function M.rules()
    local models, meta = rageModel()
    local mh, en = models.mainhand, models.enrage
    return {
        swing = mh.value(),
        crit = mh.crit(),
        payIn = M.FORM[mh.aura],
        tick = { every = en.interval, amount = en.value },
        decay = { rate = meta.decay(), interval = meta.decayInterval() },
        enterBear = entryRules("bear_form"),
        enterCat = entryRules("cat_form"),
        shiftingPower = nowGains("shifting_power")[1][2],
        enrage = nowGains("enrage")[1][2],
    }
end

-- Each pressed ability's effect beyond its cost (the world's generic verbs); `R` the rules above.
local function hit(key)
    return function(W, e)
        W.hit(e, e.target, AMOUNT[key])
    end
end
local function debuff(key, alsoHit) -- the debuff when its hit (for `key`'s amount, or none) lands
    return function(W, e)
        local w = class()
        local a = w.auras[key]
        if W.hit(e, e.target, alsoHit and AMOUNT[key] or nil).act == "WOUND" then
            W.applyAura(e.target, a.id, a.duration, 1, a.max_stack)
        end
    end
end
-- The avoids each press rolls when not the special melee tables' (world.OUTCOMES; wowsims/forever's faerie_fire.go
-- and demoralizing_roar.go: OutcomeMagicHit).
M.OUTCOMES = { faerie_fire = "spell", demoralizing_roar = "spell" }
local MAP = {
    claw = { effect = hit("claw"), points = 1 },
    shred = { effect = hit("shred"), points = 1 },
    rake = { effect = debuff("rake", true), points = 1 },
    rip = { effect = debuff("rip"), points = "all" },
    ferocious_bite = { effect = hit("ferocious_bite"), points = "all", drain = M.ENERGY },
    shifting_power = {
        extra = function(p, R)
            p.gain = { M.ENERGY, R.shiftingPower }
        end,
    },
    faerie_fire = { effect = debuff("faerie_fire") },
    primal_bite = { effect = hit("primal_bite") },
    lacerate = { effect = debuff("lacerate", true) },
    swipe_bear = { effect = hit("swipe_bear") },
    demoralizing_roar = { effect = debuff("demoralizing_roar") },
    maul = { amount = { 110, 140 } },
    enrage = {
        extra = function(p, R)
            local w = class()
            p.gain = { M.RAGE, R.enrage }
            local a = w.auras.enrage
            p.aura = {
                id = a.id,
                duration = a.duration,
                tick = { pt = M.RAGE, every = R.tick.every, amount = R.tick.amount },
            }
        end,
    },
    bear_form = {
        extra = function(p, R, o)
            local mult = M.DMG[M.BEAR] / M.DMG[o.form or M.CAT] -- the pull's form's weapon is the base
            p.shift = { form = M.BEAR, dmgMult = mult, onEnter = (o.onEnter or {}).bear or R.enterBear }
        end,
    },
    cat_form = {
        extra = function(p, R, o)
            local mult = M.DMG[M.CAT] / M.DMG[o.form or M.CAT]
            p.shift = { form = M.CAT, dmgMult = mult, onEnter = (o.onEnter or {}).cat or R.enterCat }
        end,
    },
}
M.MAP = MAP

--- The resolved press of `key` from the class file: its rank 1 ID, its cost (rank 0 talents) and power type (a mana
--- cost is not modelled: mana is never read), its cooldown, its GCD by kind, on-next-swing, its form requirement (the
--- ability's `buff` / `nobuff` form fields) and the mapping's effects. `o.onEnter` { bear, cat }: a variant's entry
--- rules over the class file's.
function M.press(key, R, o)
    local m = assert(MAP[key], "unmapped key " .. tostring(key))
    local w, e = class()
    local a = w.abilities[key]
    local cost, pt = ld.run(a.spend, e) or 0, PT[a.spendType]
    if pt == M.MANA or cost < 1 then
        cost, pt = 0, nil
    end
    local share = a.refundOnAvoid -- the belief's: true takes the resource meta's
    if share == true then
        share = pt and w.resources[pt] and w.resources[pt].meta and w.resources[pt].meta.refundOnAvoid
    end
    local p = {
        spell = a.id,
        cost = cost,
        pt = pt,
        refund = type(share) == "number" and share or nil, -- an avoid gives back the kit's share (W.hit)
        outcomes = M.OUTCOMES[key], -- nil: the special melee tables
        cooldown = ld.run(a.cooldown, e) or 0,
        gcd = M.GCD[a.gcd or "spell"],
        onNextSwing = a.onNextSwing,
        amount = m.amount,
        effect = m.effect,
        drain = m.drain,
    }
    if m.points then
        p.points = { M.POINTS, m.points }
    end
    if m.extra then
        m.extra(p, R, o or {})
    end
    local need, avoid = M.FORM[a.buff], M.FORM[a.nobuff]
    assert((a.buff == nil or need) and (a.nobuff == nil or avoid), "an unmapped form requirement: " .. key)
    p.requires = function(_, us)
        if need and us.form ~= need then
            return false, a.buff
        elseif avoid and us.form == avoid then
            return false, "not " .. a.nobuff
        end
        return true
    end
    return p
end

--- The client's usability answers (observer `k.usable`) for `keys`' rank 1 IDs: unusable (not for power) out of the
--- required form, else usable when the client's view of the cost's own type covers it, short when not.
function M.usable(keys, R)
    local out = {}
    for _, key in ipairs(keys) do
        local p = M.press(key, R)
        out[#out + 1] = {
            p.spell,
            function(W, us, power, view)
                if not p.requires(W, us) then
                    return false, false
                end
                local have = (p.pt == nil and math.huge) or (p.pt == us.pt and power) or view[p.pt]
                return have >= p.cost, have < p.cost
            end,
        }
    end
    return out
end

--- Our presses as a script (scenarios.world's `script`): every `every` s, once the true GCD is over, the first entry
--- of `list` ({ key, when = fn(W, us, t) }) whose `when` holds and that W.press accepts; `extra` entries (off the
--- GCD) are tried every 0.1 s. `presses` (optional) collects each accepted press as { t, key }.
function M.script(list, every, extra, R, o, presses)
    local P = {}
    for _, x in ipairs(list) do
        P[x[1]] = M.press(x[1], R, o)
    end
    for _, x in ipairs(extra or {}) do
        P[x[1]] = M.press(x[1], R, o)
    end
    return function(W, us)
        local nextT = W.t
        local function tick()
            if us.stopped then
                return
            end
            for _, x in ipairs(extra or {}) do
                if (not x.when or x.when(W, us, W.t)) and W.press(us, x[1], P[x[1]]) and presses then
                    presses[#presses + 1] = { W.t, x[1] }
                end
            end
            if W.t >= nextT - 1e-9 and W.t >= us.gcdUntil then
                for _, x in ipairs(list) do
                    if (not x.when or x.when(W, us, W.t)) and W.press(us, x[1], P[x[1]]) then
                        nextT = W.t + every
                        if presses then
                            presses[#presses + 1] = { W.t, x[1] }
                        end
                        break
                    end
                end
            end
            W.at(W.t + 0.1, tick)
        end
        -- half a tick off the drive's 0.1 s grid: a press and its GCD edges never share a time with a drive tick, so
        -- one frame's events (the edge and the success, either order) reach the belief before a GcdInfo read
        W.at(W.t + 0.05, tick)
    end
end

-- Whether the target has aura `key` (the class file's ID) in the world now.
local function onTarget(us, key)
    local w = class()
    return us.target and us.target.auras[w.auras[key].id] ~= nil
end
M.onTarget = onTarget

-- The scripted lists (§4.1, §4.2). Bear, every 1.5 s down the list when the true rage covers each: Demoralizing Roar
-- while its debuff is down, Primal Bite and Lacerate above 40 rage, Swipe above 60 (the rage left over pays Maul);
-- Maul queued whenever the rage covers Maul and Primal Bite; Enrage once, at `enrageAt`. Cat: Faerie Fire every 40 s,
-- Shifting Power off cooldown, Rip at 5 points, Rake while its debuff is down, Shred otherwise, each only when the
-- true energy covers it.
local function rageAbove(n)
    return function(_, us)
        return us.power >= n
    end
end
function M.bearList()
    return {
        {
            "demoralizing_roar",
            when = function(_, us)
                return not onTarget(us, "demoralizing_roar")
            end,
        },
        { "primal_bite", when = rageAbove(40) },
        { "lacerate", when = rageAbove(40) },
        { "swipe_bear", when = rageAbove(60) },
    }
end
function M.bearExtra(R, enrageAt)
    local maul, bite = M.press("maul", R), M.press("primal_bite", R)
    local enraged = false
    return {
        {
            "maul",
            when = function(_, us)
                return us.form == M.BEAR and not us.queued and us.power >= maul.cost + bite.cost
            end,
        },
        {
            "enrage",
            when = function(_, us, t)
                if enraged or us.form ~= M.BEAR or t < enrageAt then
                    return false
                end
                enraged = true
                return true
            end,
        },
    }
end
function M.catList()
    local fire = -math.huge
    return {
        {
            "faerie_fire",
            when = function(W, us)
                if W.t - fire >= 40 and us.form == M.CAT then
                    fire = W.t
                    return true
                end
                return false
            end,
        },
        { "shifting_power" },
        {
            "rip",
            when = function(W, us)
                return W.res(us, M.POINTS) >= 5
            end,
        },
        {
            "rake",
            when = function(_, us)
                return not onTarget(us, "rake")
            end,
        },
        { "shred" },
    }
end

M.KEYS = {
    "claw",
    "shred",
    "rake",
    "rip",
    "ferocious_bite",
    "shifting_power",
    "primal_bite",
    "lacerate",
    "swipe_bear",
    "demoralizing_roar",
    "maul",
}

--- The knobs of a Druid fight over scenario `o` (scenarios.world's): level 60, the paws, our resources (rage the
--- swing-paid `power`; energy 100 of 100 regenerating, combo points, mana unmodelled), the form's period and damage at
--- the pull, the rage per Bear swing and crit from the class file, its out-of-combat decay, the GCD flag's order mixed,
--- and the observer: the GCD spell, combo points plain, rage and energy never, the forms, usability from `KEYS`.
--- `o.form` the pull's form; `o.script` our presses; `o.pausedBy` the decay's truth variant; `o.regenAfter`,
--- `o.regenRead` (false: no regen read, a /reload in combat), `o.usable` (false: no answers).
function M.knobs(o, R, gcdSpell)
    local form = o.form or M.CAT
    local k = {
        level = 60,
        weapons = { { M.WEAPON[1] * M.DMG[form], M.WEAPON[2] * M.DMG[form], M.SPEED[form] } },
        max = 100,
        mobHealth = 1e9,
        duration = o.duration,
        pt = M.RAGE,
        res = { [M.ENERGY] = { cur = 100, max = 100 }, [M.POINTS] = { cur = 0, max = 5 } },
        regen = { [M.ENERGY] = M.ENERGY_REGEN },
        regenAfter = o.regenAfter,
        decay = { pt = M.RAGE, rate = R.decay.rate, interval = R.decay.interval, pausedBy = o.pausedBy or false },
        formSpeed = M.SPEED,
        payIn = R.payIn,
        rage = { R.swing, 0 },
        critRage = { R.crit, 0 },
        gcdOrder = "mixed",
        form = form,
        script = o.script,
        after = o.after,
        rates = o.rates,
        usable = o.usable ~= false and M.usable(M.KEYS, R) or false,
        observe = {
            gcdSpell = gcdSpell,
            plainPower = { [M.RAGE] = "never", [M.ENERGY] = "never", [M.POINTS] = "always" },
            powerTokens = M.TOKENS,
            forms = M.formIds(),
            playerSpeed = true,
            regenRead = o.regenRead ~= false,
        },
    }
    return k
end

--- The client's forms list (index to the class file's spell ID).
function M.formIds()
    local w = class()
    local ids = {}
    for i, key in ipairs(M.FORMS) do
        ids[i] = w.abilities[key].id
    end
    return ids
end

--- One Druid fight of scenario `o` at `seed`: VirtualState booted with the Druid's class (`o.edit(class, w)` a
--- declaration variant), the world built and observed, the stream run. Returns { c, s, W, R, rows, swingValues }
--- (`rows` the combat-log rows of ours by event: { [subevent] = { [spellID] = n } }; `swingValues` { min, max } of the
--- rage belief's swing values); the caller restores with M.done.
function M.fight(o, seed)
    local R = M.rules()
    local saved = {}
    local c = drive.boot({
        max = 100,
        oracle = o.oracle,
        track = { M.RAGE, M.ENERGY, M.POINTS },
        boot = function(c)
            for _, key in ipairs({ "UnitGUID", "debugprofilestop" }) do
                saved[key] = rawget(_G, key) or false
            end
            _G.UnitGUID = c.api.UnitGUID
            _G.debugprofilestop = function()
                return 0
            end
            local ctl = c.ctl
            ctl.powerMax[M.ENERGY], ctl.powerMax[M.POINTS], ctl.powerMax[M.MANA] = 100, 5, 1e6
            ctl.powerMax[M.RAGE] = 100
            local w = class()
            for _, key in ipairs(M.KEYS) do
                ctl.known[w.abilities[key].id] = true
            end
            for _, key in ipairs({ "bear_form", "cat_form", "enrage", "faerie_fire" }) do
                ctl.known[w.abilities[key].id] = true
            end
            dvs.boot(c.ns, c.api, o.edit)
        end,
    })
    c.druidSaved = saved
    -- every swing value the rage belief steps by (Resources.lua asks I.SwingValue at each landed swing it pays)
    local sv, I, rage = c.I.SwingValue, c.I, 0
    for r = 1, I.res.n do
        rage = I.res.type[r] == M.RAGE and r or rage
    end
    local values = { min = math.huge, max = -math.huge }
    I.SwingValue = function(r, hand)
        local v = sv(r, hand)
        if r == rage and hand ~= 2 and v > 0 then -- the main hand's while Bear's aura is believed up
            values.min, values.max = math.min(values.min, v), math.max(values.max, v)
        end
        return v
    end
    local rows = {}
    local GetInfo = c.ns.Facade.CombatLogGetCurrentEventInfo
    local sink = c.I.Events.CreateFrame("Frame")
    sink:SetScript("OnEvent", function()
        local _, ev, _, src, _, _, _, _, _, _, _, spell = GetInfo()
        if src == "Player-1" then
            rows[ev] = rows[ev] or {}
            rows[ev][spell or 0] = (rows[ev][spell or 0] or 0) + 1
        end
    end)
    sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    local k = M.knobs(o, R, c.I.GCD_SPELL)
    for key, v in pairs(o.world or {}) do
        k[key] = v
    end
    local s, W = scenarios.stream(k, seed)
    drive.run(c, s)
    return { c = c, s = s, W = W, R = R, rows = rows, swingValues = values }
end

--- Puts back what M.fight replaced.
function M.done(f)
    drive.restore(f.c)
    for key, v in pairs(f.c.druidSaved) do
        _G[key] = v or nil
    end
    fs.clock = nil
end

-- The scenarios (§4.1-§4.5): each builds the fight's knobs `o` for M.fight from the rules `R`.
local PULL = 1 -- scenarios.world's default pull
M.SCENARIOS = {
    -- §4.1: pull in Bear, the bear list, Maul, Enrage once at 20 s
    bear = function(R, v)
        local o = { form = M.BEAR, usable = v.usable, oracle = v.oracle }
        o.script = M.script(M.bearList(), 1.5, M.bearExtra(R, PULL + 20), R, o)
        return o
    end,
    -- §4.2: pull in Cat, the cat list; `v.regenAfter`, `v.regenRead`
    cat = function(R, v)
        local o = { form = M.CAT, regenAfter = v.regenAfter, regenRead = v.regenRead }
        o.script = M.script(M.catList(), 1.0, {}, R, o)
        return o
    end,
    -- §4.3-§4.4: Cat at the pull, Bear at 30 s, Cat at 60, Bear at 90, stop at 120; `v.onEnter` a Furor variant
    shift = function(R, v)
        local o = { form = M.CAT, onEnter = v.onEnter }
        local function at(form, from, to)
            return function(_, us, t)
                return us.form ~= form and t >= PULL + from and t < PULL + to
            end
        end
        local list = { { "bear_form", when = at(M.BEAR, 30, 60) }, { "cat_form", when = at(M.CAT, 60, 90) } }
        list[3] = { "bear_form", when = at(M.BEAR, 90, 1e9) }
        for _, x in ipairs(M.catList()) do
            list[#list + 1] = x
        end
        for _, x in ipairs(M.bearList()) do
            list[#list + 1] = x
        end
        o.script = M.script(list, 1.0, M.bearExtra(R, math.huge), R, o)
        return o
    end,
    -- §4.5: Bear, the fight ends at 60 s with Enrage pressed at 57 (its last 7 s out of combat), 20 s observed after;
    -- `v.pausedBy` the truth's pause, `v.declared` the class's `pausesDecay` on its Enrage entry; no answers (the
    -- model alone)
    decay = function(R, v)
        local o = { form = M.BEAR, duration = 59, after = 20, usable = false }
        o.pausedBy = v.pausedBy and class().auras.enrage.id
        if v.declared then
            o.edit = function(class)
                class.resources.rage.state.regenModel.enrage.pausesDecay = true
            end
        end
        o.script = M.script(M.bearList(), 1.5, M.bearExtra(R, PULL + 56), R, o)
        return o
    end,
}

--- Fight `n` seeds of scenario `name` (variant `v`), calling `each(f)` on every fight before it is restored.
function M.fights(name, n, v, each)
    local R = M.rules()
    for seed = 1, n do
        local f = M.fight(M.SCENARIOS[name](R, v or {}), seed)
        each(f)
        M.done(f)
    end
end

--- The true form at time `t` of world `W` (our form changes, in order), from the pull's `form0`.
function M.formAt(W, form0)
    local changes = {}
    for _, ev in ipairs(W.truth) do
        if ev.kind == "form" then
            changes[#changes + 1] = { ev.t, ev.form }
        end
    end
    return function(t)
        local f = form0
        for _, x in ipairs(changes) do
            if x[1] > t then
                break
            end
            f = x[2]
        end
        return f
    end
end

return M
