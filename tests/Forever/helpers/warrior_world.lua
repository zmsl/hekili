-- tests/Forever/helpers/warrior_world.lua (headless loop design §7): the Warrior content of the class-neutral headless
-- loop: the character the instance logs in as, each ability's press in the world's generic verbs (W.press's
-- `requires` and `effect`), the client's usability answers and the true rage per landed hit. Spell and aura IDs,
-- costs, cooldowns, durations and stance requirements come from the class file (load_warrior's recording load for the
-- character; the booted instance's Hekili.Class and Hekili.State for the rest), never copied here. Damage amounts are
-- Classic's rank-60 values: the loop compares two runs of one model (A/B), so they set only what a choice is worth.
local loadWarrior = require("Forever.helpers.load_warrior")

local M = {}

M.SPEC, M.CLASS_ID, M.PACK = 1491, 1, "Arms"

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
    "rend",
    "sunder_armor",
    "thunder_clap",
    "victory_rush",
    "whirlwind",
}
-- An Arms build by definition spell (the SPIKE's): Mortal Strike, Anger Management, Deep Wounds 3, Tactical Mastery 5,
-- Impale 2, Improved Rend 3.
M.TALENTS = { [12294] = 1, [12296] = 1, [12834] = 3, [12295] = 5, [16493] = 2, [12163] = 3 }

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
        known[#known + 1] = a.id
        for _, id in ipairs(type(a.copy) == "table" and a.copy or {}) do
            known[#known + 1] = id
        end
    end
    local forms = {}
    for i, key in ipairs(M.FORMS) do
        forms[i] = w.abilities[key].id
    end
    return {
        class = "WARRIOR",
        classID = M.CLASS_ID,
        specID = M.SPEC,
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
-- two-hander's damage (Arcanite Reaper's range, rounded), rage capped at 100.
M.WORLD = { level = 60, weapons = { { 150, 230, 3.6 } }, max = 100 }

-- True rage per landed white wound: the class file's own model restated (Forever/Classes/Warrior.lua, "Rage per white
-- swing": 4.5 x the unhasted speed with a two-hander; a crit one more base swing, 3.46 x speed). Circular on purpose:
-- the loop measures recommendations, not the rage model (its own specs measure that).
function M.rage(hand, _, flag)
    if hand ~= 1 then
        return 0
    end
    return 4.5 * 3.6 + (flag == "CRITICAL" and 3.46 * 3.6 or 0)
end

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
        effect = function(W, e)
            W.setForm(e, M.FORM[key])
            if e.power > 25 then -- Tactical Mastery 5/5 keeps 25 rage through a stance change
                W.gain(e, 25 - e.power)
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
    -- shortcut: no positions, so Charge only pays its rage (rank 3: 15); the pull starts combat. Upgrade with positions.
    charge = {
        effect = function(W, e)
            W.gain(e, 15)
        end,
    },
    cleave = { amount = 50, onNextSwing = true },
    heroic_strike = { amount = 157, onNextSwing = true },
    demoralizing_shout = {
        effect = function(W, e, _, X)
            aura(W, X, e.target, "demoralizing_shout")
        end,
    },
    sunder_armor = {
        effect = function(W, e, _, X)
            aura(W, X, e.target, "sunder_armor")
        end,
    },
    hamstring = {
        effect = function(W, e, _, X)
            aura(W, X, e.target, "hamstring")
            W.hit(e, e.target, 45)
        end,
    },
    rend = { -- rank 7: 147 over the aura's duration, a tick every 3 s
        effect = function(W, e, _, X)
            local d = X.aura.rend.duration
            aura(W, X, e.target, "rend")
            W.dot(e, e.target, 3, math.floor(d / 3), math.floor(147 * 3 / d))
        end,
    },
    recklessness = {
        effect = function(W, e, _, X)
            aura(W, X, e, "recklessness")
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
            return v ~= nil and v.health < 0.2 * v.healthMax, "not in execute range"
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

-- The class data the mapping reads, from a booted instance `H` (once per instance).
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
--- state is true): the ability's ID, its cost as the state resolves it, its cooldown and GCD, on-next-swing; the
--- mapping's requirement (after the stance's) and effect. Raises "unmapped key" for a key the mapping lacks.
function M.resolve(key, H)
    local m = M.MAP[key]
    if not m then
        error("unmapped key " .. tostring(key), 2)
    end
    local a = H.Hekili.Class.abilities[key]
    local X = classData(H)
    local p = {
        spell = a.id,
        cost = H.Hekili.State.action[key].cost or 0,
        cooldown = tonumber(a.cooldown) or 0,
        gcd = 1.5,
        offGcd = a.gcd == "off",
        onNextSwing = m.onNextSwing or a.onNextSwing or a.nextSwing,
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

--- The client's usability answers (observer `k.usable`) for every mapped ability the character knows, from instance
--- `H`: the power (the client's view) covers the cost, the stance fits and the mapping's requirement holds in the true
--- world (Execute's phase and Overpower's opening read these, as in game).
function M.usable(H)
    local out = {}
    for key, m in pairs(M.MAP) do
        local a = H.Hekili.Class.abilities[key]
        if a and H.ctl.known[a.id] then
            local cost = H.Hekili.State.action[key].cost or 0
            local X = classData(H)
            out[#out + 1] = {
                a.id,
                function(W, e, power)
                    return power >= cost and stanceOk(a, e) and (not m.requires or m.requires(W, e, X)) or false
                end,
            }
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
