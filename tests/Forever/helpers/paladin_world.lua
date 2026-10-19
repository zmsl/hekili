-- tests/Forever/helpers/paladin_world.lua (class-completion plan, "The per-pack gate"): the Paladin content of the
-- class-neutral headless loop, in rogue_world.lua's shape, one content per pack (M.Retribution, M.Protection): the
-- character the instance logs in as, each ability's press in the world's generic verbs, the client's usability
-- answers. IDs, costs, cooldowns and durations come from the class file (load_druid's recording load of Paladin.lua for
-- the character, the booted oracle's Hekili.Class and Hekili.State for the rest); the seal twist, Swift Judgement and
-- Holy Shield's charges restate the class file's rules (circular on purpose, as rogue_world's finishers: the loop
-- measures the picks, not the rules). The world's own: our landed swing spends an Echo (`landed`), Holy Shield's +30%
-- block on the mob's swings at us and a block spending a charge (`taking`, `took`), mana under the five-second rule.
-- Damage amounts, the weapons, the regen parts and the mana pool are UNMEASURED.
-- Credit: wowsims/forever (MIT) as the reference for the priorities and the seal, Echo and Holy Shield rules; no code
-- copied.
local ld = require("Forever.helpers.load_druid")

local M = {}

M.CLIENT_SPEC, M.CLASS_ID = 1486, 2 -- the client's Paladin pseudo-spec
local MANA = 0 -- Enum.PowerType
local GCD = { totem = 1.0, spell = 1.5, off = 0 }
-- UNMEASURED: the true regen parts (the class file declares 17 and 2: the out-of-combat read corrects them).
local FSR = { 20, 3 }

-- UNMEASURED: the hits' amounts.
local AMOUNT = {
    judgement = 300,
    hammer_of_wrath = 500,
    holy_strike = 250,
    exorcism = 500,
    holy_shock = 350,
}

local W0
local function class()
    W0 = W0 or ld.load(nil, "src/Hekili_Paladin/Paladin.lua", "PALADIN")
    return W0
end

local function aura(W, X, dst, key, duration, stacks)
    local a = X.aura[key]
    W.applyAura(dst, a.id, duration or a.duration, stacks or 1, a.max_stack)
end
local function drop(W, e, X, key) -- aura `key` off us, if up
    local id = X.aura[key].id
    if e.auras[id] then
        e.auras[id] = nil
        W.emit({ kind = "aura", dst = e, aura = id, stacks = 0, expires = 0, duration = 0 })
    end
end
local function up(e, X, key)
    return e.auras[X.aura[key].id] ~= nil
end

local SEALS = { "seal_of_command", "seal_of_righteousness", "seal_of_the_crusader", "seal_of_fury" }
local ECHO = {
    seal_of_command = "echo_of_command",
    seal_of_righteousness = "echo_of_righteousness",
    seal_of_fury = "echo_of_fury",
}
local ECHOES = { "echo_of_command", "echo_of_righteousness", "echo_of_fury" }

-- A seal: the other seal up goes down, leaving its Echo with Twist of Light (one Echo at a time); its own Echo goes.
local function seal(key)
    return {
        effect = function(W, e, _, X)
            for _, other in ipairs(SEALS) do
                if other ~= key and up(e, X, other) then
                    drop(W, e, X, other)
                    if ECHO[other] and X.twist then
                        for _, echo in ipairs(ECHOES) do
                            drop(W, e, X, echo)
                        end
                        aura(W, X, e, ECHO[other])
                    end
                end
            end
            if ECHO[key] then
                drop(W, e, X, ECHO[key])
            end
            aura(W, X, e, key)
        end,
    }
end
local function strike(key)
    return {
        effect = function(W, e)
            W.hit(e, e.target, AMOUNT[key])
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

-- Each recommendable ability: `effect(W, e, p, X)`, `requires(W, e, X)`. A key missing here fails the loop.
M.MAP = {
    seal_of_command = seal("seal_of_command"),
    seal_of_righteousness = seal("seal_of_righteousness"),
    seal_of_the_crusader = seal("seal_of_the_crusader"),
    seal_of_fury = seal("seal_of_fury"),
    judgement = {
        effect = function(W, e, _, X)
            drop(W, e, X, "swift_judgement")
            W.hit(e, e.target, AMOUNT.judgement)
        end,
        requires = function(_, e, X)
            for _, key in ipairs(SEALS) do
                if up(e, X, key) then
                    return true
                end
            end
            return false, "no seal"
        end,
    },
    swift_judgement = {
        effect = function(W, e, _, X)
            W.resetCooldown(e, "judgement", X.ids.judgement)
            aura(W, X, e, "swift_judgement")
        end,
    },
    hammer_of_wrath = { -- the target's true health at or under 20%
        effect = strike("hammer_of_wrath").effect,
        requires = function(_, e)
            local v = e.target
            return v ~= nil and v.health <= 0.2 * v.healthMax, "not in execute range"
        end,
    },
    holy_strike = strike("holy_strike"),
    exorcism = strike("exorcism"),
    holy_shock = {
        effect = function(W, e, _, X)
            drop(W, e, X, "divine_favor")
            W.hit(e, e.target, AMOUNT.holy_shock)
        end,
    },
    consecration = {
        effect = function(W, e, _, X)
            aura(W, X, e.target, "consecrated_ground")
            W.dot(e, e.target, 1, 8, 60)
        end,
    },
    divine_favor = selfAura("divine_favor"),
    holy_shield = {
        effect = function(W, e, _, X)
            aura(W, X, e, "holy_shield", nil, 4)
        end,
    },
    righteous_fury = selfAura("righteous_fury"),
    retribution_aura = selfAura("retribution_aura"),
}

-- The packs' worlds: `kit` the abilities the character knows (every rank), `talents` by spell ID, `weapon` the main
-- hand, `uptime` the debuffs reported.
local PACKS = {
    -- Twist of Light: Seal of Command and Seal of Righteousness twisted, a two-hander.
    Retribution = {
        kit = {
            "seal_of_command",
            "seal_of_righteousness",
            "seal_of_the_crusader",
            "judgement",
            "hammer_of_wrath",
            "holy_strike",
            "consecration",
            "exorcism",
            "retribution_aura",
        },
        talents = { [1310735] = 1, [20375] = 1 },
        weapon = { 150, 230, 3.6 },
        uptime = { "consecrated_ground" },
    },
    -- Seal of Fury, Holy Shield and Swift Judgement, a one-hander and a shield; the mob's swings at us blocked.
    Protection = {
        kit = {
            "seal_of_fury",
            "seal_of_the_crusader",
            "judgement",
            "swift_judgement",
            "hammer_of_wrath",
            "holy_strike",
            "consecration",
            "exorcism",
            "holy_shock",
            "holy_shield",
            "righteous_fury",
            "retribution_aura",
        },
        talents = { [1310994] = 1, [20925] = 1, [20473] = 1 },
        weapon = { 70, 130, 2.7 },
        uptime = { "consecrated_ground" },
    },
}

-- The class data a press reads from a booted instance `H` (once per instance): each aura's ID, duration and stacks,
-- Twist of Light, each ability's known rank IDs.
local cache = setmetatable({}, { __mode = "k" })
local function classData(H, C)
    if cache[H] then
        return cache[H]
    end
    local X = { aura = {}, ids = C.IDS }
    cache[H] = X
    for key, a in pairs(H.Hekili.Class.auras) do
        if type(key) == "string" and type(a) == "table" and a.id then
            local d = a.duration
            X.aura[key] = { id = a.id, duration = type(d) == "function" and d() or d or 0, max_stack = a.max_stack }
        end
    end
    X.twist = (H.Hekili.State.talent.twist_of_light.rank or 0) > 0
    return X
end

local function content(name)
    local P = PACKS[name]
    local C = { PACK = name, IDS = {} }
    C.SPEC = ({ Retribution = 100023, Protection = 100022 })[name]

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
            class = "PALADIN",
            classID = M.CLASS_ID,
            specID = M.CLIENT_SPEC,
            level = 60,
            known = known,
            talents = P.talents,
            power = { type = MANA, token = "MANA", max = 6000 },
            speed = { P.weapon[3] },
        }
    end

    -- The class's world hooks on us, from the class file's aura IDs: our landed swing spends an Echo; Holy Shield
    -- raises the block chance on a swing at us by 30% and a block spends one of its charges.
    local function hooks(_, us)
        local A = class().auras
        local hs = A.holy_shield.id
        us.landed = function(W, act)
            if act ~= "WOUND" then
                return
            end
            for _, key in ipairs(ECHOES) do
                local id = A[key].id
                if us.auras[id] then
                    us.auras[id] = nil
                    W.emit({ kind = "aura", dst = us, aura = id, stacks = 0, expires = 0, duration = 0 })
                end
            end
        end
        us.taking = function(_, _, rates)
            if us.auras[hs] then
                rates.block = (rates.block or 0) + 0.3
            end
        end
        us.took = function(W, _, act)
            local a = us.auras[hs]
            if a and act == "BLOCK" then
                a.stacks = a.stacks - 1
                if a.stacks <= 0 then
                    us.auras[hs] = nil
                end
                W.emit({
                    kind = "aura",
                    dst = us,
                    aura = hs,
                    stacks = math.max(0, a.stacks),
                    expires = a.stacks > 0 and a.expires or 0,
                    duration = a.stacks > 0 and a.duration or 0,
                })
            end
        end
    end

    -- Level 60 against a level 60 mob in melee range swinging at us, the pack's main hand, 6000 mana full and under
    -- the five-second rule, a mob of 15000 health (about 3 minutes).
    C.WORLD = {
        level = 60,
        weapons = { P.weapon },
        max = 6000,
        fsr = { [MANA] = FSR },
        power = 6000,
        mobHealth = 15000,
        script = hooks,
    }

    -- No other power read (mana is secret in combat); our attack speed read out of combat (probe W PR2), which the
    -- swing gap's `mainhand_remains` projects with.
    C.OBSERVE = { powerTokens = { [MANA] = "MANA" }, playerSpeed = true }

    -- No power is swing-paid.
    function C.gain()
        return 0
    end

    -- An answer's mana cost: the state's (the booted oracle's talents), none for Judgement under Swift Judgement.
    local function cost(key, H, e, X)
        if key == "judgement" and up(e, X, "swift_judgement") then
            return 0
        end
        return H.Hekili.State.action[key].cost or 0
    end

    --- The resolved press of `key` from instance `H` (the oracle's: its state is true): the highest known rank's ID
    --- and every known rank's, the cost, the cooldown, GCD and cast time, the mapping's effects. Raises "unmapped key".
    function C.resolve(key, H)
        local m = M.MAP[key]
        if not m then
            error("unmapped key " .. tostring(key), 2)
        end
        local a = H.Hekili.Class.abilities[key]
        local X = classData(H, C)
        local S = H.Hekili.State
        local p = {
            spell = H.ns.VirtualState.KnownID(a.id),
            ids = C.IDS[key],
            cost = (key == "judgement" and H.ns.VirtualState.Aura("player", X.aura.swift_judgement.id, H.ctl.now))
                    and 0
                or S.action[key].cost
                or 0, -- Swift Judgement's charge from the oracle's (true) belief, as Clearcasting
            pt = MANA,
            cooldown = tonumber(a.cooldown) or S.action[key].cooldown or 0,
            gcd = GCD[a.gcd or "spell"],
            offGcd = a.gcd == "off",
            cast = S.action[key].cast_time or tonumber(a.cast) or 0,
        }
        p.requires = function(W, e)
            if m.requires then
                return m.requires(W, e, X)
            end
            return true
        end
        p.effect = function(W, e)
            if m.effect then
                m.effect(W, e, p, X)
            end
        end
        return p
    end

    --- The client's usability answers for every known rank of every mapped kit ability: unusable (not for power)
    --- when the mapping's requirement fails in the true world, else usable when mana covers the cost, short when not.
    function C.usable(H)
        local out = {}
        local X = classData(H, C)
        for key, m in pairs(M.MAP) do
            if H.Hekili.Class.abilities[key] and C.IDS[key] then
                local function answer(W, e, power)
                    if m.requires and not m.requires(W, e, X) then
                        return false, false
                    end
                    local c = cost(key, H, e, X)
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

M.Retribution, M.Protection = content("Retribution"), content("Protection")

return M
