-- tests/Forever/helpers/hunter_world.lua (class-completion plan, "The per-pack gate"): the Hunter content of the
-- class-neutral headless loop, in shaman_world.lua's shape, one content per pack (M.BeastMastery, M.Marksmanship,
-- M.Survival): the character the instance logs in as, each ability's press in the world's generic verbs, the client's
-- usability answers. IDs, costs, cooldowns and aura durations come from the class file (load_druid's recording load of
-- Hunter.lua for the character, the booted oracle's Hekili.Class and Hekili.State for the rest). The world's own,
-- restated from the DB2 and wowsims/forever (so the class file's belief is measured against them): the shared
-- category cooldowns (Arcane Shot and Summon Hawk, Aimed Shot and Multi-Shot), the ranged casts hasted by Rapid Fire
-- and Quick Shots, Quick Shots off our Auto Shots under Aspect of the Hawk (Deadly Aspects 5/5: 10%), Mongoose Bite's
-- window from our dodge (5 s, spent by the bite), Raptor Strike on the next main-hand swing, Serpent Sting's ticks,
-- mana under the five-second rule, our Auto Shots on the ranged hand (W.startRanged) in the turret worlds. Damage
-- amounts, the weapons, the regen parts and the mana pool are UNMEASURED; the hawks deal nothing here (no read of them
-- exists), ranged haste does not speed the Auto Shots (no priority reads the clock, D5), and our melee swings run in
-- every world (the harness has no positions: a turret Hunter is in melee too).
-- Credit: wowsims/forever (MIT) as the reference for the priorities and the Summon Hawk, Sniper Shot, Raptor Strike,
-- Mongoose Bite and Quick Shots rules; no code copied.
local ld = require("Forever.helpers.load_druid")

local M = {}

M.SPEC, M.CLASS_ID = 1484, 3
local MANA = 0 -- Enum.PowerType
local MAX = 5000
local GCD = { spell = 1.5, off = 0 }
-- UNMEASURED: the true regen parts (the class file declares 15 and 2: the out-of-combat read corrects them).
local FSR = { 18, 3 }
local QUICK_SHOTS = 0.1 -- wowsims aspects.go: Deadly Aspects' 2% a rank, 5 ranks
local AUTO_SHOT = 75

-- The top rank's mana cost (DB2), the world's truth the class file's costs are measured against; a percent-of-base
-- cost (PowerCostPct) as the class file prices it, a fraction of the maximum.
local COST = {
    hunters_mark = 60,
    aspect_of_the_hawk = 120,
    aspect_of_the_beast = 110,
    rapid_fire = 100,
    serpent_sting = 250,
    arcane_shot = 190,
    summon_hawk = 190,
    aimed_shot = 310,
    multi_shot = 0.139 * MAX,
    sniper_shot = 365,
    raptor_strike = 100,
    mongoose_bite = 65,
    strider_kick = 0.0581 * MAX,
    wing_clip = 80,
}

-- UNMEASURED: the hits' amounts.
local AMOUNT = {
    arcane_shot = 300,
    summon_hawk = 150,
    aimed_shot = 600,
    multi_shot = 350,
    sniper_shot = 700,
    mongoose_bite = 250,
    strider_kick = 300,
    wing_clip = 50,
}

-- The cast times (DB2) the ranged haste shortens: Rapid Fire +40%, Quick Shots +30% (aura 140).
local CAST = { aimed_shot = 2, multi_shot = 0.5, sniper_shot = 4 }

-- The category cooldowns two abilities share (6 s each).
local SHARED = {
    arcane_shot = "summon_hawk",
    summon_hawk = "arcane_shot",
    aimed_shot = "multi_shot",
    multi_shot = "aimed_shot",
}

local W0
local function class()
    W0 = W0 or ld.load(nil, "src/Hekili_Hunter/Hunter.lua", "HUNTER")
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

-- Our dodge of a swing at us within 5 s, after the last bite: Mongoose Bite's window (Defensive State 5302).
local function dodged(W, e)
    for i = #W.truth, 1, -1 do
        local ev = W.truth[i]
        if W.t - ev.t > 5 or ev.t <= (e.bitAt or -1e9) then
            break
        elseif ev.kind == "swing" and ev.dst == e and ev.act == "DODGE" then
            return true
        end
    end
    return false
end

local function shot(key, extra)
    return {
        effect = function(W, e, p, X)
            local other = SHARED[key]
            if other then
                e.cdUntil[other] = W.t + 6
            end
            if AMOUNT[key] then
                W.hit(e, e.target, AMOUNT[key])
            end
            if extra then
                extra(W, e, p, X)
            end
        end,
    }
end

-- Each recommendable ability: `effect(W, e, p, X)`, `requires(W, e, X)`. A key missing here fails the loop.
M.MAP = {
    aspect_of_the_hawk = {
        effect = function(W, e, _, X)
            drop(W, e, X, "aspect_of_the_beast")
            aura(W, X, e, "aspect_of_the_hawk")
        end,
    },
    aspect_of_the_beast = {
        effect = function(W, e, _, X)
            drop(W, e, X, "aspect_of_the_hawk")
            aura(W, X, e, "aspect_of_the_beast")
        end,
    },
    hunters_mark = {
        effect = function(W, e, _, X)
            aura(W, X, e.target, "hunters_mark")
        end,
    },
    rapid_fire = {
        effect = function(W, e, _, X)
            aura(W, X, e, "rapid_fire")
        end,
    },
    serpent_sting = {
        effect = function(W, e, _, X)
            aura(W, X, e.target, "serpent_sting")
            W.dot(e, e.target, 3, 5, 60)
        end,
    },
    arcane_shot = shot("arcane_shot"),
    summon_hawk = shot("summon_hawk"),
    aimed_shot = shot("aimed_shot"),
    multi_shot = shot("multi_shot"),
    sniper_shot = shot("sniper_shot"),
    strider_kick = shot("strider_kick"),
    wing_clip = shot("wing_clip"),
    raptor_strike = { bonus = 100 }, -- the queued swing's damage over the weapon's
    mongoose_bite = {
        requires = function(W, e)
            return dodged(W, e), "no dodge"
        end,
        effect = function(W, e)
            e.bitAt = W.t
            W.hit(e, e.target, AMOUNT.mongoose_bite)
        end,
    },
}

-- The packs' worlds: `kit` the abilities the character knows (every rank), `weapon` the main hand, `ranged` the ranged
-- hand (shooting from the pull), `aspect` the one the character keeps up, `uptime` the debuffs reported.
local PACKS = {
    BeastMastery = {
        kit = {
            "auto_shot",
            "aspect_of_the_hawk",
            "hunters_mark",
            "rapid_fire",
            "summon_hawk",
            "arcane_shot",
            "serpent_sting",
            "aimed_shot",
            "multi_shot",
        },
        weapon = { 150, 220, 3.5 },
        ranged = { 140, 200, 3.0 },
        aspect = "aspect_of_the_hawk",
        uptime = { "serpent_sting", "hunters_mark" },
    },
    Marksmanship = {
        kit = {
            "auto_shot",
            "aspect_of_the_hawk",
            "hunters_mark",
            "rapid_fire",
            "aimed_shot",
            "serpent_sting",
            "sniper_shot",
            "arcane_shot",
            "multi_shot",
        },
        weapon = { 150, 220, 3.5 },
        ranged = { 140, 200, 3.0 },
        aspect = "aspect_of_the_hawk",
        uptime = { "serpent_sting", "hunters_mark" },
    },
    -- Melee: a two-hander, no Auto Shots.
    Survival = {
        kit = {
            "aspect_of_the_beast",
            "hunters_mark",
            "raptor_strike",
            "mongoose_bite",
            "strider_kick",
            "summon_hawk",
            "wing_clip",
        },
        weapon = { 180, 260, 3.6 },
        aspect = "aspect_of_the_beast",
        uptime = { "hunters_mark" },
    },
}

-- The class data a press reads from a booted instance `H` (once per instance): each aura's ID, duration and stacks.
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
    return X
end

-- The ranged haste on us at `now` in belief `VS`: Rapid Fire's 1.4 times Quick Shots' 1.3.
local function haste(VS, now, X)
    local rf, qs = VS.Aura("player", X.aura.rapid_fire.id, now), VS.Aura("player", X.aura.quick_shots.id, now)
    return (rf and 1.4 or 1) * (qs and 1.3 or 1)
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
            class = "HUNTER",
            classID = M.CLASS_ID,
            specID = M.SPEC,
            level = 60,
            known = known,
            talents = {},
            power = { type = MANA, token = "MANA", max = MAX },
            speed = { P.weapon[3] },
        }
    end

    -- At the pull: the pack's aspect, if not up (a permanent buff the character carries from one fight to the next,
    -- which each fight's fresh world would otherwise drop under a belief that keeps it); our Auto Shots (the turret
    -- worlds), and Quick Shots rolled on each under Aspect of the Hawk.
    local function hooks(W, us)
        us.health, us.healthMax = 1e9, 1e9 -- never killed: see C.WORLD
        local A = class().auras
        local asp = A[P.aspect]
        if not us.auras[asp.id] then
            W.applyAura(us, asp.id, asp.duration, 1, asp.max_stack)
        end
        if not P.ranged then
            return
        end
        local hawk, qs = A.aspect_of_the_hawk.id, A.quick_shots
        W.startRanged(us, AUTO_SHOT)
        local function roll() -- after each shot (queued behind it at the same time)
            if not us.rangedOn then
                return
            end
            if us.auras[hawk] and W.rng.chance(QUICK_SHOTS) then
                W.applyAura(us, qs.id, qs.duration, 1, qs.max_stack)
            end
            W.at(W.t + P.ranged[3], roll)
        end
        W.at(W.t, roll)
    end

    -- Level 60 against a level 60 mob in melee range swinging at us, 5000 mana full and under the five-second rule.
    -- Neither side dies (the mob's health here, ours in `hooks`): each fight ends at its stop, out of combat. A kill
    -- ends the loop before the client sees it, so the next fight's prepull would be believed in combat (the harness
    -- quirk shaman_world works around the same way).
    C.WORLD = {
        level = 60,
        weapons = { P.weapon },
        ranged = P.ranged,
        max = MAX,
        fsr = { [MANA] = FSR },
        power = MAX,
        mobHealth = 1e9,
        script = hooks,
    }

    -- No other power read (mana is secret in combat); our attack speed read out of combat (probe W PR2).
    C.OBSERVE = { powerTokens = { [MANA] = "MANA" }, playerSpeed = true }

    -- No power is swing-paid.
    function C.gain()
        return 0
    end

    --- The resolved press of `key` from instance `H` (the oracle's: its state is true): the highest known rank's ID
    --- and every known rank's (with the cooldown partner's: the client answers the shared cooldown on both), the cost,
    --- the cooldown, GCD and cast time (hasted by the oracle's ranged haste), on-next-swing, the mapping's effects. Raises
    --- "unmapped key".
    function C.resolve(key, H)
        local m = M.MAP[key]
        if not m then
            error("unmapped key " .. tostring(key), 2)
        end
        local a = H.Hekili.Class.abilities[key]
        local X = classData(H)
        local S = H.Hekili.State
        local VS, now = H.ns.VirtualState, H.ctl.now
        local ids = C.IDS[key]
        if SHARED[key] and C.IDS[SHARED[key]] then
            ids = {}
            for _, k in ipairs({ key, SHARED[key] }) do
                for _, id in ipairs(C.IDS[k]) do
                    ids[#ids + 1] = id
                end
            end
        end
        local p = {
            spell = VS.KnownID(a.id),
            ids = ids,
            cost = COST[key],
            pt = MANA,
            cooldown = tonumber(a.cooldown) or S.action[key].cooldown or 0,
            gcd = GCD[a.gcd or "spell"],
            offGcd = a.gcd == "off",
            onNextSwing = a.onNextSwing,
            -- the ranged haste from the oracle's (true) belief, as shaman_world's Maelstrom Weapon
            cast = CAST[key] and CAST[key] / haste(VS, now, X) or 0,
        }
        if m.bonus then
            local w = P.weapon
            p.amount = { w[1] + m.bonus, w[2] + m.bonus }
        end
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
        local X = classData(H)
        for key, m in pairs(M.MAP) do
            if H.Hekili.Class.abilities[key] and C.IDS[key] then
                local function answer(W, e, power)
                    if m.requires and not m.requires(W, e, X) then
                        return false, false
                    end
                    return power >= COST[key], power < COST[key]
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

M.BeastMastery = content("BeastMastery")
M.Marksmanship = content("Marksmanship")
M.Survival = content("Survival")

return M
