-- tests/Forever/helpers/warrior_world.lua (headless loop design §7): the Warrior content of the class-neutral headless
-- loop: the character the instance logs in as, each ability's press in the world's generic verbs (W.press's
-- `requires` and `effect`), the client's usability answers and the true rage per landed hit. Spell and aura IDs,
-- costs, cooldowns, durations and stance requirements come from the class file (load_warrior's recording load for the
-- character; the booted instance's Hekili.Class and Hekili.State for the rest), never copied here. Damage amounts are
-- Classic's rank-60 values: the loop compares two runs of one model (A/B), so they set only what a choice is worth.
local loadWarrior = require("Forever.helpers.load_warrior")
local world = require("Game.harness.world")

local M = {}

-- M.SPEC: the Arms spec's id (Hekili:NewClass); M.CLIENT_SPEC: the client's pseudo-spec the character reports.
M.SPEC, M.CLIENT_SPEC, M.CLASS_ID, M.PACK = 100011, 1491, 1, "Arms"

-- The Arms kit a level 60 Warrior has trained (every rank: Classic trains them all by 60) and the talent-granted
-- Mortal Strike of the build below.
M.KIT = {
    "battle_shout",
    "battle_stance",
    "berserker_stance",
    "bloodrage",
    "charge",
    "cleave",
    "defensive_stance",
    "demoralizing_shout",
    "execute",
    "hamstring",
    "heroic_strike",
    "intercept",
    "mortal_strike",
    "overpower",
    "pummel",
    "recklessness",
    "rend",
    "slam",
    "sunder_armor",
    "thunder_clap",
    "victory_rush",
    "whirlwind",
}
-- An Arms build by definition spell (the SPIKE's): Mortal Strike, Anger Management, Deep Wounds 3, Tactical Mastery 5,
-- Impale 2, Improved Rend 3.
M.TALENTS = { [12294] = 1, [12296] = 1, [12834] = 3, [12295] = 5, [16493] = 2, [12163] = 3 }
-- How many of an ability's rank list (`id`, then `copy`) the character knows when the list runs past its trained ranks:
-- Slam's list ends in Improved Slam's override IDs, which this build (no Improved Slam) does not know.
M.RANKS = { slam = 5 }
-- Forever's Tactical Mastery passive (the user's Warrior knows it): the stance keep is 85 (the class file's swap_stance).
M.PASSIVES = { 1310185 }

-- Every known rank's spell ID of each kit ability (the class file reads the usability of the highest rank known).
M.IDS = {}

-- The stances as the client's forms, in order (GetShapeshiftForm's index).
M.FORMS = { "battle_stance", "defensive_stance", "berserker_stance" }
M.FORM = {}
for i, key in ipairs(M.FORMS) do
    M.FORM[key] = i
end

--- The character for headless.new (§1.3): level 60, the kit known, the Arms talents, rage of 100 (secret, as on
--- Forever), a two-hand weapon (speed 3.6; the gear scan reads it as one), the three stances as forms, Battle Stance up.
function M.character()
    local w = loadWarrior.load()
    local known = {}
    for _, key in ipairs(M.KIT) do
        local a = assert(w.abilities[key], key)
        local ids = { a.id }
        for i, id in ipairs(type(a.copy) == "table" and a.copy or {}) do
            if i < (M.RANKS[key] or math.huge) then
                ids[#ids + 1] = id
            end
        end
        M.IDS[key] = ids
        for _, id in ipairs(ids) do
            known[#known + 1] = id
        end
    end
    for _, id in ipairs(M.PASSIVES) do
        known[#known + 1] = id
    end
    local forms = {}
    for i, key in ipairs(M.FORMS) do
        forms[i] = w.abilities[key].id
    end
    return {
        class = "WARRIOR",
        classID = M.CLASS_ID,
        specID = M.CLIENT_SPEC,
        level = 60,
        known = known,
        talents = M.TALENTS,
        power = { type = 1, token = "RAGE", max = 100 },
        speed = { 3.6 },
        items = { [16] = { 1, "Two-Hander", "INVTYPE_2HWEAPON" } },
        forms = forms,
        form = 1,
    }
end

-- The world the loop fights in (scenarios.world's knobs): level 60 against a level 60 mob in melee range, the
-- two-hander's damage (Arcanite Reaper's range, rounded), rage capped at 100, a mob of 15000 health (killed in about
-- 3 minutes by this build: measured 13700-17700 damage in 3 minutes over seeds 1-3).
M.WORLD = { level = 60, weapons = { { 150, 230, 3.6 } }, max = 100, mobHealth = 15000 }

-- True rage per landed white wound: the class file's own model restated (Hekili_Warrior/Warrior.lua, "Rage per white
-- swing": 4.5 x the unhasted speed with a two-hander; a crit one more base swing, 3.46 x speed). Circular on purpose:
-- the loop measures recommendations, not the rage model (its own specs measure that). The loop's gain hook: rage is
-- the character's only power, so `pt` is always rage's.
function M.gain(_, hand, _, flag)
    if hand ~= 1 then
        return 0
    end
    return 4.5 * 3.6 + (flag == "CRITICAL" and 3.46 * 3.6 or 0)
end

-- The avoids each press rolls when not the special melee tables' (world.OUTCOMES, from wowsims/forever's warrior/*.go):
-- Overpower can be missed only (OutcomeMeleeSpecialNoBlockDodgeParry), the shouts and Thunder Clap are magic hits
-- (OutcomeMagicHit*), Intercept always hits.
M.OUTCOMES = {
    overpower = "miss",
    demoralizing_shout = "spell",
    thunder_clap = "spell",
    intercept = "none",
}

-- A weapon hit's amount: the main hand's roll plus `bonus`.
local function weapon(W, e, bonus)
    local w = e.weapons[1]
    return W.rng.int(w[1], w[2]) + bonus
end

-- Each recommendable ability's press: `requires(W, e, X)` (beyond the stance, which the ability's buff/nobuff fields
-- give) and `effect(W, e, p, X)` in the world's verbs; `X` holds the class data (X.aura[key] = { id, duration,
-- max_stack }). An ability missing here fails the loop ("unmapped key").
local function aura(W, X, dst, key, stacks)
    local a = X.aura[key]
    W.applyAura(dst, a.id, a.duration, stacks or 1, a.max_stack)
end
local function stance(key)
    return {
        effect = function(W, e, _, X)
            W.setForm(e, M.FORM[key])
            if e.power > X.keep then -- the class file's swap_stance keep (Tactical Mastery and its talent)
                W.gain(e, X.keep - e.power)
            end
        end,
    }
end
local function selfAura(key)
    return {
        effect = function(W, e, _, X)
            aura(W, X, e, key)
        end,
    }
end
local function strike(amount, key) -- a hit on the target for `amount` (nil: none), and debuff `key` when it lands
    return {
        effect = function(W, e, _, X)
            if W.hit(e, e.target, amount).act == "WOUND" and key then
                aura(W, X, e.target, key)
            end
        end,
    }
end
M.MAP = {
    battle_stance = stance("battle_stance"),
    berserker_stance = stance("berserker_stance"),
    defensive_stance = stance("defensive_stance"),
    battle_shout = {
        effect = function(W, e, _, X)
            aura(W, X, e, "battle_shout")
        end,
    },
    bloodrage = { -- 10 at once, then 1 a second for 10 s (the class file's tick aura)
        effect = function(W, e, _, X)
            aura(W, X, e, "bloodrage")
            W.gain(e, 10)
            for k = 1, 10 do
                W.at(W.t + k, function()
                    W.gain(e, 1)
                end)
            end
        end,
    },
    -- shortcut: no positions, so Charge only pays its rage (rank 3: 15); the pull starts combat; its function-valued
    -- stance `buff` and its out-of-combat, in-range `usable` are not checked. Upgrade with positions.
    charge = {
        effect = function(W, e)
            W.gain(e, 15)
        end,
    },
    -- shortcut: a queued strike that lands has no crit or armour. It rolls its avoids (W.hit's sets, the swing's).
    cleave = { amount = 50 },
    heroic_strike = { amount = 157 },
    demoralizing_shout = strike(nil, "demoralizing_shout"),
    sunder_armor = strike(nil, "sunder_armor"),
    hamstring = strike(45, "hamstring"),
    rend = { -- rank 7: 147 over the aura's duration, a tick every 3 s
        effect = function(W, e, _, X)
            if W.hit(e, e.target, nil).act == "WOUND" then
                local d = X.aura.rend.duration
                aura(W, X, e.target, "rend")
                W.dot(e, e.target, 3, math.floor(d / 3), math.floor(147 * 3 / d))
            end
        end,
    },
    recklessness = selfAura("recklessness"),
    sweeping_strikes = selfAura("sweeping_strikes"),
    death_wish = selfAura("death_wish"),
    berserker_rage = selfAura("berserker_rage"), -- Improved Berserker Rage's rage not modelled (not this build)
    shield_block = selfAura("shield_block"),
    spearing_strike = { -- UNMEASURED amount: a plain weapon hit
        effect = function(W, e)
            W.hit(e, e.target, weapon(W, e, 0))
        end,
    },
    bloodthirst = strike(450), -- 45% of attack power, at about 1000
    shield_slam = strike(342),
    thunder_clap = strike(103, "thunder_clap"),
    mocking_blow = strike(93, "mocking_blow"),
    concussion_blow = strike(nil, "concussion_blow"),
    -- threat and interrupts are not modelled: these only press
    shield_bash = {},
    taunt = {},
    challenging_shout = {},
    revenge = { -- a dodge, parry or block of a swing at us within 5 s (the class file's window)
        requires = function(W, e)
            for i = #W.truth, 1, -1 do
                local ev = W.truth[i]
                if W.t - ev.t > 5 then
                    break
                elseif
                    ev.kind == "swing"
                    and ev.dst == e
                    and (ev.act == "DODGE" or ev.act == "PARRY" or ev.act == "BLOCK")
                then
                    return true
                end
            end
            return false, "no avoid"
        end,
        effect = function(W, e)
            W.hit(e, e.target, 80)
        end,
    },
    mortal_strike = {
        effect = function(W, e)
            W.hit(e, e.target, weapon(W, e, 160))
        end,
    },
    whirlwind = {
        effect = function(W, e)
            W.hit(e, e.target, weapon(W, e, 0))
        end,
    },
    slam = {
        effect = function(W, e)
            W.hit(e, e.target, weapon(W, e, 87))
        end,
    },
    intercept = {
        effect = function(W, e)
            W.hit(e, e.target, 65)
        end,
    },
    -- shortcut: `avoidAt` and `W.killAt` are not per target or source (any dodge of ours opens Overpower, any death
    -- Victory Rush); right solo, upgrade for the party report.
    overpower = { -- a dodge of ours on the target within 5 s opens it; the press uses it up
        requires = function(W, e)
            return W.t - (e.avoidAt.DODGE or -1e9) <= 5, "no dodge"
        end,
        effect = function(W, e)
            e.avoidAt.DODGE = nil
            W.hit(e, e.target, weapon(W, e, 35))
        end,
    },
    execute = { -- the target's true health under 20%; rank 5: 600, and 15 a point of the rage it spends past its cost
        requires = function(_, e)
            local v = e.target
            return v ~= nil and v.health <= 0.2 * v.healthMax, "not in execute range"
        end,
        effect = function(W, e)
            local extra = e.power
            W.gain(e, -extra)
            W.hit(e, e.target, 600 + 15 * extra)
        end,
    },
    victory_rush = { -- a kill of ours within 20 s
        requires = function(W)
            return W.killAt ~= nil and W.t - W.killAt <= 20, "no kill"
        end,
        effect = function(W, e)
            W.hit(e, e.target, 200)
        end,
    },
}

-- The class data the mapping reads, from a booted instance `H` (once per instance): each aura's ID, duration and
-- stacks; `keep`, the rage a stance swap keeps, from the class file's own swap_stance run on the character's known
-- spells and talents.
local cache = setmetatable({}, { __mode = "k" })
local function classData(H)
    if cache[H] then
        return cache[H]
    end
    local X = { aura = {} }
    cache[H] = X
    for key, a in pairs(H.Hekili.Class.auras) do
        if type(key) == "string" and type(a) == "table" and a.id then
            X.aura[key] = { id = a.id, duration = a.duration, max_stack = a.max_stack }
        end
    end
    local w = loadWarrior.load()
    w.game.known = H.ctl.known
    local env = loadWarrior.env(w)
    env.talent, env.rage.current = H.Hekili.State.talent, 100
    env.swap_stance("battle_stance")
    X.keep = 100 - (env.spent[1] or 0)
    return X
end

-- Whether `e`'s true stance meets ability `a`'s buff / nobuff stance fields.
local function stanceOk(a, e)
    if a.buff and M.FORM[a.buff] and e.form ~= M.FORM[a.buff] then
        return false, a.buff
    elseif a.nobuff and M.FORM[a.nobuff] and e.form == M.FORM[a.nobuff] then
        return false, "not " .. a.nobuff
    end
    return true
end

--- The resolved press of `key` (headless loop design §7), read from instance `H` (the loop passes the oracle's: its
--- state is true): the ability's highest known rank's ID and every known rank's, its cost as the state resolves it, its
--- cooldown and GCD, on-next-swing; the mapping's requirement (after the stance's) and effect. Raises "unmapped key" for a key the mapping lacks.
function M.resolve(key, H)
    local m = M.MAP[key]
    if not m then
        error("unmapped key " .. tostring(key), 2)
    end
    assert(next(M.IDS), "M.character() fills M.IDS before a press resolves")
    local a = H.Hekili.Class.abilities[key]
    local X = classData(H)
    local p = {
        spell = H.ns.VirtualState.KnownID(a.id), -- the rank the client casts: the highest known
        ids = M.IDS[key],
        cost = H.Hekili.State.action[key].cost or 0,
        cooldown = tonumber(a.cooldown) or 0,
        gcd = 1.5,
        offGcd = a.gcd == "off",
        cast = tonumber(a.cast) or 0,
        onNextSwing = a.onNextSwing or a.nextSwing,
        refund = world.refundOf(H.Hekili.Class, key), -- an avoid gives back the kit's share (W.hit)
        outcomes = M.OUTCOMES[key], -- nil: the special melee tables
    }
    if m.amount then
        local w = M.WORLD.weapons[1]
        p.amount = { w[1] + m.amount, w[2] + m.amount }
    end
    p.requires = function(W, e)
        local ok, why = stanceOk(a, e)
        if ok and m.requires then
            ok, why = m.requires(W, e, X)
        end
        return ok, why
    end
    if m.effect then
        p.effect = function(W, e)
            m.effect(W, e, p, X)
        end
    end
    return p
end

--- The client's usability answers (observer `k.usable`) for every rank of every mapped ability the character knows,
--- from instance `H`: unusable (not for power) when the stance or the mapping's requirement fails in the true world
--- (Execute's phase, Overpower's opening, Victory Rush's kill: the class file reads these, as in game), else usable
--- when the power (the client's view) covers the cost, short when it does not.
function M.usable(H)
    local out = {}
    local X = classData(H)
    for key, m in pairs(M.MAP) do
        local a = H.Hekili.Class.abilities[key]
        if a and M.IDS[key] then
            local cost = H.Hekili.State.action[key].cost or 0
            local function answer(W, e, power)
                if not stanceOk(a, e) or (m.requires and not m.requires(W, e, X)) then
                    return false, false
                end
                return power >= cost, power < cost
            end
            for _, id in ipairs(M.IDS[key]) do
                out[#out + 1] = { id, answer }
            end
        end
    end
    table.sort(out, function(x, y)
        return x[1] < y[1]
    end)
    return out
end

--- The debuffs whose uptime the loop reports (§5.1): the Arms list keeps Sunder Armor and Demoralizing Shout up (Rend
--- only without Mortal Strike). Returns { { key, auraID } } from instance `H`.
function M.uptime(H)
    local out = {}
    for _, key in ipairs({ "sunder_armor", "demoralizing_shout" }) do
        out[#out + 1] = { key, H.Hekili.Class.auras[key].id }
    end
    return out
end

return M
