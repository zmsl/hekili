-- tests/Forever/helpers/rogue_world.lua (class-completion plan, "The per-pack gate"): the Rogue content of the
-- class-neutral headless loop, in warrior_world.lua's shape, one content per pack (M.Combat, M.Assassination,
-- M.Subtlety): the character the instance logs in as, each ability's press in the world's generic verbs, the client's
-- usability answers. IDs, costs, cooldowns and durations come from the class file (load_druid's recording load of
-- Rogue.lua for the character, the booted oracle's Hekili.Class and Hekili.State for the rest); the finishers'
-- per-point durations and Relentless Strikes's refund restate the class file's rules (circular on purpose, as
-- warrior_world's rage: the loop measures the picks, not the rules). Damage amounts and the weapons are UNMEASURED.
-- Shortcuts: the client's IsStealthed answers false throughout (fake_api; UPDATE_STEALTH never fires), so the belief
-- holds Stealth and Vanish from our casts only, the in-combat secret case; Preparation finishes the world's
-- cooldowns but not the client's answers. Credit: wowsims/forever (MIT) as the reference for the priorities the packs
-- follow; no code copied.
local ld = require("Forever.helpers.load_druid")

local M = {}

M.SPEC, M.CLASS_ID = 1500, 4
local ENERGY, POINTS = 3, 4 -- Enum.PowerType
local TOKENS = { [ENERGY] = "ENERGY", [POINTS] = "COMBO_POINTS" }
local GCD = { totem = 1.0, spell = 1.5, off = 0 }
local ENERGY_REGEN = 10 -- a second (the Druid's probe: 10.001 out of combat)
local RELENTLESS = 25

-- UNMEASURED: the hits' amounts.
local AMOUNT = {
    sinister_strike = 120,
    backstab = 200,
    mutilate = 220,
    hemorrhage = 110,
    ghostly_strike = 130,
    ambush = 300,
    eviscerate = 450,
}

local W0
local function class()
    W0 = W0 or ld.load(nil, "src/Hekili_Rogue/Rogue.lua", "ROGUE")
    return W0
end

local function aura(W, X, dst, key, duration)
    local a = X.aura[key]
    W.applyAura(dst, a.id, duration or a.duration, 1, a.max_stack)
end
local function drop(W, e, X, key) -- aura `key` off us, if up
    local id = X.aura[key].id
    if e.auras[id] then
        e.auras[id] = nil
        W.emit({ kind = "aura", dst = e, aura = id, stacks = 0, expires = 0, duration = 0 })
    end
end
local function stealthed(e, X)
    return e.auras[X.aura.stealth.id] ~= nil or e.auras[X.aura.vanish.id] ~= nil
end

-- A builder: its hit, Cold Blood taken; `debuffKey` on a landed hit.
local function strike(key, debuffKey)
    return {
        effect = function(W, e, _, X)
            drop(W, e, X, "cold_blood")
            if W.hit(e, e.target, AMOUNT[key]).act == "WOUND" and debuffKey then
                aura(W, X, e.target, debuffKey)
            end
        end,
        points = key == "mutilate" and 2 or 1,
    }
end
-- A finisher: `effect(W, e, cp, X)` before its points go; Relentless Strikes's certain 25 at 5 points.
local function finisher(effect)
    return {
        effect = function(W, e, _, X)
            local cp = W.res(e, POINTS)
            effect(W, e, cp, X)
            if X.relentless and cp >= 5 then
                W.emit({ kind = "gain", src = e, pt = ENERGY, rage = RELENTLESS })
            end
        end,
        points = "all",
        requires = function(W, e)
            return W.res(e, POINTS) > 0, "no combo points"
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

-- Each recommendable ability: `effect(W, e, p, X)`, `requires(W, e, X)`, `points`, `extra(p)`. A key missing here
-- fails the loop.
M.MAP = {
    sinister_strike = strike("sinister_strike"),
    backstab = strike("backstab"),
    mutilate = strike("mutilate"),
    hemorrhage = strike("hemorrhage", "hemorrhage"),
    ghostly_strike = {
        effect = function(W, e, _, X)
            W.hit(e, e.target, AMOUNT.ghostly_strike)
            aura(W, X, e, "ghostly_strike")
        end,
        points = 1,
    },
    ambush = {
        effect = function(W, e, _, X)
            drop(W, e, X, "cold_blood")
            drop(W, e, X, "cutthroat")
            W.hit(e, e.target, AMOUNT.ambush)
        end,
        points = 1,
        requires = function(_, e, X)
            return stealthed(e, X) or e.auras[X.aura.cutthroat.id] ~= nil, "not stealthed"
        end,
    },
    garrote = {
        effect = function(W, e, _, X)
            if W.hit(e, e.target, 0).act == "WOUND" then
                aura(W, X, e.target, "garrote")
                W.dot(e, e.target, 3, 6, 50)
            end
        end,
        points = 1,
        requires = function(_, e, X)
            return stealthed(e, X), "not stealthed"
        end,
    },
    eviscerate = finisher(function(W, e, _, X)
        drop(W, e, X, "cold_blood")
        W.hit(e, e.target, AMOUNT.eviscerate)
    end),
    slice_and_dice = finisher(function(W, e, cp, X)
        aura(W, X, e, "slice_and_dice", (6 + 3 * cp) * (1 + 0.15 * X.isnd))
    end),
    venom = finisher(function(W, e, cp, X)
        aura(W, X, e, "venom", 6 + 3 * cp)
    end),
    rupture = finisher(function(W, e, cp, X)
        if W.hit(e, e.target, 0).act == "WOUND" then
            aura(W, X, e.target, "rupture", 6 + 2 * cp)
            W.dot(e, e.target, 2, 3 + cp, 60)
        end
    end),
    expose_armor = finisher(function(W, e, _, X)
        aura(W, X, e.target, "expose_armor")
    end),
    kick = {},
    adrenaline_rush = { -- +100% energy regen: the world's 10 a second again, while it lasts
        extra = function(p)
            local a = class().auras.adrenaline_rush
            p.aura = {
                id = a.id,
                duration = a.duration,
                tick = { pt = ENERGY, every = 0.1, amount = ENERGY_REGEN * 0.1 },
            }
        end,
    },
    blade_flurry = selfAura("blade_flurry"),
    cold_blood = selfAura("cold_blood"),
    premeditation = {
        extra = function(p)
            p.gain = { POINTS, 2 }
        end,
    },
    preparation = {
        effect = function(_, e)
            for _, key in ipairs({ "cold_blood", "premeditation", "vanish", "ghostly_strike", "blade_flurry" }) do
                e.cdUntil[key] = nil
            end
            e.cdUntil.adrenaline_rush = nil
        end,
    },
    stealth = {
        effect = function(W, e, _, X)
            aura(W, X, e, "stealth")
        end,
        requires = function(W)
            return not W.combat, "in combat"
        end,
    },
    vanish = selfAura("vanish"),
}

-- The three packs' worlds: `kit` the abilities the character knows (every rank), `talents` by spell ID, `uptime` the
-- debuffs reported.
local COMMON = {
    "sinister_strike",
    "backstab",
    "eviscerate",
    "slice_and_dice",
    "rupture",
    "expose_armor",
    "kick",
    "ambush",
    "garrote",
    "stealth",
    "vanish",
}
local function kit(extra)
    local out = {}
    for _, k in ipairs(COMMON) do
        out[#out + 1] = k
    end
    for _, k in ipairs(extra) do
        out[#out + 1] = k
    end
    return out
end
local PACKS = {
    -- Combat Swords: Improved Sinister Strike 2, Adrenaline Rush, Blade Flurry.
    Combat = {
        kit = kit({ "adrenaline_rush", "blade_flurry" }),
        talents = { [13732] = 2 },
        uptime = { "rupture", "garrote" },
    },
    -- Mutilate: Improved Slice and Dice 3, Relentless Strikes, Cold Blood, Venom.
    Assassination = {
        kit = kit({ "mutilate", "cold_blood", "venom" }),
        talents = { [14165] = 3, [14179] = 1 },
        uptime = { "rupture", "garrote" },
    },
    -- Hemorrhage: Ghostly Strike, Premeditation, Preparation, Thousand Cuts.
    Subtlety = {
        kit = kit({ "hemorrhage", "ghostly_strike", "premeditation", "preparation" }),
        talents = { [1310721] = 1 },
        uptime = { "rupture", "hemorrhage" },
    },
}

-- The class data a press reads from a booted instance `H` (once per instance): each aura's ID, duration and stacks,
-- and the talents the rules read.
local cache = setmetatable({}, { __mode = "k" })
local function classData(H)
    if cache[H] then
        return cache[H]
    end
    local X = { aura = {} }
    cache[H] = X
    for key, a in pairs(H.Hekili.Class.auras) do
        if type(key) == "string" and type(a) == "table" and a.id then
            local d = a.duration
            X.aura[key] = { id = a.id, duration = type(d) == "function" and d() or d or 0, max_stack = a.max_stack }
        end
    end
    local talent = H.Hekili.State.talent
    X.relentless = (talent.relentless_strikes.rank or 0) > 0
    X.isnd = talent.improved_slice_and_dice.rank or 0
    return X
end

local function content(name)
    local P = PACKS[name]
    local C = { PACK = name, IDS = {} }

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
        return {
            class = "ROGUE",
            classID = M.CLASS_ID,
            specID = M.SPEC,
            level = 60,
            known = known,
            talents = P.talents,
            power = { type = ENERGY, token = TOKENS[ENERGY], max = 100 },
            speed = { 2.6, 1.8 },
        }
    end

    -- Level 60 against a level 60 mob in melee range, a sword and a dagger, energy at 100 regenerating 10 a second,
    -- combo points beside it, a mob of 15000 health (about 3 minutes).
    C.WORLD = {
        level = 60,
        weapons = { { 70, 130, 2.6 }, { 40, 75, 1.8 } },
        max = 100,
        res = { [POINTS] = { cur = 0, max = 5 } },
        regen = { [ENERGY] = ENERGY_REGEN },
        power = 100,
        mobHealth = 15000,
    }

    -- The client's other power reads: combo points plain (research addendum), energy never.
    C.OBSERVE = { plainPower = { [POINTS] = "always" }, powerTokens = TOKENS }

    -- No power is swing-paid.
    function C.gain()
        return 0
    end

    --- The resolved press of `key` from instance `H` (the oracle's: its state is true): the highest known rank's ID
    --- and every known rank's, the state's cost, the cooldown and GCD, the mapping's effects; an ability that starts
    --- combat breaks Stealth and Vanish first. Raises "unmapped key".
    function C.resolve(key, H)
        local m = M.MAP[key]
        if not m then
            error("unmapped key " .. tostring(key), 2)
        end
        local a = H.Hekili.Class.abilities[key]
        local X = classData(H)
        local S = H.Hekili.State
        local p = {
            spell = H.ns.VirtualState.KnownID(a.id),
            ids = C.IDS[key],
            cost = a.spendType == "energy" and (S.action[key].cost or 0) or 0,
            pt = a.spendType == "energy" and ENERGY or nil,
            cooldown = tonumber(a.cooldown) or S.action[key].cooldown or 0,
            gcd = GCD[a.gcd or "spell"],
            offGcd = a.gcd == "off",
            cast = 0,
        }
        if m.points then
            p.points = { POINTS, m.points }
        end
        if m.extra then
            m.extra(p)
        end
        p.requires = function(W, e)
            if m.requires then
                return m.requires(W, e, X)
            end
            return true
        end
        p.effect = function(W, e)
            if a.startsCombat then
                drop(W, e, X, "stealth")
                drop(W, e, X, "vanish")
            end
            if m.effect then
                m.effect(W, e, p, X)
            end
        end
        return p
    end

    --- The client's usability answers for every known rank of every mapped kit ability: unusable (not for power)
    --- when the mapping's requirement fails in the true world, else usable when energy covers the cost, short when
    --- not.
    function C.usable(H)
        local out = {}
        local X = classData(H)
        for key, m in pairs(M.MAP) do
            local a = H.Hekili.Class.abilities[key]
            if a and C.IDS[key] then
                local c = a.spendType == "energy" and (H.Hekili.State.action[key].cost or 0) or 0
                local function answer(W, e, power)
                    if m.requires and not m.requires(W, e, X) then
                        return false, false
                    end
                    return power >= c, power < c
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

M.Combat, M.Assassination, M.Subtlety = content("Combat"), content("Assassination"), content("Subtlety")

return M
