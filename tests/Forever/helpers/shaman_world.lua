-- tests/Forever/helpers/shaman_world.lua (class-completion plan, "The per-pack gate"): the Shaman content of the
-- class-neutral headless loop, in paladin_world.lua's shape, one content per pack (M.Enhancement): the character the
-- instance logs in as, each ability's press in the world's generic verbs, the client's usability answers. IDs, costs,
-- cooldowns and aura durations come from the class file (load_druid's recording load of Shaman.lua for the character,
-- the booted oracle's Hekili.Class and Hekili.State for the rest). The world's own, restated from the DB2 and
-- wowsims/forever (so the class file's belief is measured against them): the totem slots and durations (W.summonTotem;
-- slot order fire, earth, water, air: checkpoint), the shocks' shared cooldown, Fire Nova needing a fire totem,
-- Maelstrom Weapon stacked by our landed melee (10 a minute, wowsims's rate) and spent by Lightning Bolt, Elemental
-- Focus's Clearcasting (10% after a Fire or Nature damage spell, spent by the next one), Lightning Shield's charges
-- spent by the mob's hits on us, mana under the five-second rule. Damage amounts, the weapon, the regen parts and the
-- mana pool are UNMEASURED.
-- Credit: wowsims/forever (MIT) as the reference for the priorities and the totem, Fire Nova, Maelstrom Weapon and
-- Clearcasting rules; no code copied.
local ld = require("Forever.helpers.load_druid")

local M = {}

M.SPEC, M.CLASS_ID = 1489, 7
local MANA = 0 -- Enum.PowerType
local GCD = { totem = 1.0, spell = 1.5, off = 0 }
-- UNMEASURED: the true regen parts (the class file declares 17 and 2: the out-of-combat read corrects them).
local FSR = { 20, 3 }
local MAELSTROM_PPM = 10 -- wowsims talents_enhancement.go (fits a 3.6 s weapon)
local CLEARCASTING = 0.1 -- Elemental Focus's chance (DB2 16164 ProcChance)

-- The totems the kit summons at level 60: the slot (1 fire, 2 earth, 3 water, 4 air) and the top rank's duration (DB2).
local TOTEM = {
    searing_totem = { 1, 55 },
    flametongue_totem = { 1, 300 },
    strength_of_earth_totem = { 2, 300 },
    mana_spring_totem = { 3, 300 },
    grace_of_air_totem = { 4, 300 },
}

-- The top rank's mana cost (DB2), the world's truth the class file's costs are measured against.
local COST = {
    lightning_bolt = 220,
    lightning_shield = 370,
    earth_shock = 450,
    flame_shock = 410,
    fire_nova = 520,
    stormstrike = 125,
    searing_totem = 170,
    flametongue_totem = 275,
    strength_of_earth_totem = 275,
    mana_spring_totem = 100,
    grace_of_air_totem = 310,
}

-- UNMEASURED: the hits' amounts.
local AMOUNT = {
    stormstrike = 400,
    earth_shock = 500,
    flame_shock = 250,
    lightning_bolt = 550,
    fire_nova = 350,
}

-- The spells Clearcasting covers (the class file's cost modifier) and whose casts roll it (Fire, Nature damage).
local ELEMENTAL = { lightning_bolt = true, earth_shock = true, flame_shock = true, fire_nova = true }

local W0
local function class()
    W0 = W0 or ld.load(nil, "src/Hekili_Shaman/Shaman.lua", "SHAMAN")
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

-- A melee hit of ours that lands stacks Maelstrom Weapon at its rate a minute (by the main hand's speed).
local function maelstrom(W, e, X)
    if W.rng.chance(MAELSTROM_PPM * e.weapons[1][3] / 60) then
        aura(W, X, e, "maelstrom_weapon")
    end
end

-- An elemental damage spell: it spends Clearcasting, then rolls a new one.
local function elemental(W, e, X)
    drop(W, e, X, "clearcasting")
    if W.rng.chance(CLEARCASTING) then
        aura(W, X, e, "clearcasting")
    end
end

-- The cost of `key` with Clearcasting (`cc`: up) making an elemental spell free and each of `mw` Maelstrom Weapon
-- stacks taking 20% off Lightning Bolt's.
local function costOf(key, cc, mw)
    if ELEMENTAL[key] and cc then
        return 0
    elseif key == "lightning_bolt" then
        return COST[key] * math.max(0, 1 - 0.2 * mw)
    end
    return COST[key]
end

local function spell(key, extra)
    return {
        effect = function(W, e, p, X)
            W.hit(e, e.target, AMOUNT[key], (key == "flame_shock" or key == "fire_nova") and 4 or 8)
            if extra then
                extra(W, e, p, X)
            end
            elemental(W, e, X)
        end,
    }
end
local function totem(key)
    return {
        effect = function(W, e, p)
            W.summonTotem(e, TOTEM[key][1], TOTEM[key][2], p.spell)
        end,
    }
end

-- Each recommendable ability: `effect(W, e, p, X)`, `requires(W, e, X)`. A key missing here fails the loop.
M.MAP = {
    lightning_bolt = spell("lightning_bolt", function(W, e, _, X)
        drop(W, e, X, "maelstrom_weapon")
    end),
    earth_shock = spell("earth_shock", function(W, e)
        e.cdUntil.flame_shock = W.t + 6 -- the shared category
    end),
    flame_shock = spell("flame_shock", function(W, e, _, X)
        e.cdUntil.earth_shock = W.t + 6
        aura(W, X, e.target, "flame_shock")
        W.dot(e, e.target, 3, 4, 80)
    end),
    fire_nova = { -- around the fire totem up
        effect = spell("fire_nova").effect,
        requires = function(W, e)
            return W.totem(e, 1) ~= nil, "no fire totem"
        end,
    },
    stormstrike = {
        effect = function(W, e, _, X)
            if W.hit(e, e.target, AMOUNT.stormstrike).act == "WOUND" then
                maelstrom(W, e, X)
            end
        end,
    },
    lightning_shield = {
        effect = function(W, e, _, X)
            aura(W, X, e, "lightning_shield", nil, 3)
        end,
    },
    searing_totem = totem("searing_totem"),
    flametongue_totem = totem("flametongue_totem"),
    strength_of_earth_totem = totem("strength_of_earth_totem"),
    mana_spring_totem = totem("mana_spring_totem"),
    grace_of_air_totem = totem("grace_of_air_totem"),
}

-- The packs' worlds: `kit` the abilities the character knows (every rank), `weapon` the main hand, `uptime` the debuffs
-- reported. The imbues are left out of the kit: the world has no weapon enchant read (shaman_spec covers the reminder).
local PACKS = {
    -- Stormstrike, Maelstrom Weapon and Elemental Focus, a two-hander.
    Enhancement = {
        kit = {
            "lightning_bolt",
            "lightning_shield",
            "earth_shock",
            "flame_shock",
            "fire_nova",
            "stormstrike",
            "searing_totem",
            "flametongue_totem",
            "strength_of_earth_totem",
            "mana_spring_totem",
            "grace_of_air_totem",
        },
        weapon = { 180, 260, 3.6 },
        uptime = { "flame_shock" },
    },
}

-- The class data a press reads from a booted instance `H` (once per instance): each aura's ID, duration and stacks,
-- each ability's known rank IDs.
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
            class = "SHAMAN",
            classID = M.CLASS_ID,
            specID = M.SPEC,
            level = 60,
            known = known,
            talents = {},
            power = { type = MANA, token = "MANA", max = 5000 },
            speed = { P.weapon[3] },
        }
    end

    -- The class's world hooks on us, from the class file's aura IDs: our landed swing stacks Maelstrom Weapon; a hit
    -- that lands on us spends a Lightning Shield charge.
    local function hooks(_, us)
        us.health, us.healthMax = 1e9, 1e9 -- never killed: see C.WORLD
        local A = class().auras
        local X = { aura = {} }
        for _, key in ipairs({ "maelstrom_weapon", "lightning_shield" }) do
            X.aura[key] = { id = A[key].id, duration = A[key].duration, max_stack = A[key].max_stack }
        end
        local ls = A.lightning_shield.id
        us.landed = function(W, act)
            if act == "WOUND" then
                maelstrom(W, us, X)
            end
        end
        us.took = function(W, _, act)
            local a = us.auras[ls]
            if a and act == "WOUND" then
                a.stacks = a.stacks - 1
                if a.stacks <= 0 then
                    us.auras[ls] = nil
                end
                W.emit({
                    kind = "aura",
                    dst = us,
                    aura = ls,
                    stacks = math.max(0, a.stacks),
                    expires = a.stacks > 0 and a.expires or 0,
                    duration = a.stacks > 0 and a.duration or 0,
                })
            end
        end
    end

    -- Level 60 against a level 60 mob in melee range swinging at us, a two-hander, 5000 mana full and under the
    -- five-second rule. Neither side dies (the mob's health here, ours in `hooks`): each fight ends at its stop, out of
    -- combat. A kill ends the loop before the client sees it, so the next fight's prepull would be believed in combat
    -- and its totem slots never read (a harness quirk every pack shares; the totems are the first to feel it).
    C.WORLD = {
        level = 60,
        weapons = { P.weapon },
        max = 5000,
        fsr = { [MANA] = FSR },
        power = 5000,
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
    --- and every known rank's (a shock's with the other shock's: the client answers the shared cooldown on both), the
    --- cost (Clearcasting and Maelstrom Weapon in the oracle's state), the cooldown, GCD and cast time, the mapping's
    --- effects. Raises "unmapped key".
    function C.resolve(key, H)
        local m = M.MAP[key]
        if not m then
            error("unmapped key " .. tostring(key), 2)
        end
        local a = H.Hekili.Class.abilities[key]
        local X = classData(H, C)
        local S = H.Hekili.State
        local VS, now = H.ns.VirtualState, H.ctl.now
        local ids = C.IDS[key]
        if key == "earth_shock" or key == "flame_shock" then
            ids = {}
            for _, k in ipairs({ "earth_shock", "flame_shock" }) do
                for _, id in ipairs(C.IDS[k]) do
                    ids[#ids + 1] = id
                end
            end
        end
        -- Clearcasting and Maelstrom Weapon from the oracle's (true) belief, as paladin_world's Swift Judgement
        local cc = VS.Aura("player", X.aura.clearcasting.id, now)
        local _, mw = VS.Aura("player", X.aura.maelstrom_weapon.id, now)
        local p = {
            spell = VS.KnownID(a.id),
            ids = ids,
            cost = costOf(key, cc ~= nil, mw or 0),
            pt = MANA,
            cooldown = tonumber(a.cooldown) or S.action[key].cooldown or 0,
            gcd = GCD[a.gcd or "spell"],
            offGcd = a.gcd == "off",
            -- every press is instant but Lightning Bolt, 2.5 s less 20% a Maelstrom Weapon stack (DB2 15208)
            cast = key == "lightning_bolt" and 2.5 * math.max(0, 1 - 0.2 * (mw or 0)) or 0,
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
                    local mw = e.auras[X.aura.maelstrom_weapon.id]
                    local c = costOf(key, e.auras[X.aura.clearcasting.id] ~= nil, mw and mw.stacks or 0)
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

M.Enhancement = content("Enhancement")

return M
