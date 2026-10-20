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
local world = require("Game.harness.world")

local M = {}

M.CLIENT_SPEC, M.CLASS_ID = 1489, 7 -- the client's Shaman pseudo-spec
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

-- Each rank's mana cost (DB2, rank order; Stormstrike's wowsims/forever's), the world's truth the class file's costs are measured against; Shamanistic
-- Focus (1223030, DB2 aura 108 misc 14) takes 45% off the shocks' and Lightning Shield's.
local COST = {
    lightning_bolt = { 15, 30, 45, 60, 85, 110, 135, 160, 190, 220 },
    lightning_shield = { 45, 80, 125, 180, 240, 305, 370 },
    earth_shock = { 30, 50, 85, 145, 240, 345, 450 },
    flame_shock = { 55, 95, 160, 250, 345, 410 },
    fire_nova = { 95, 170, 280, 395, 520 }, -- the kit's (wowsims/forever's 65..375 not modelled: Shaman.lua)
    stormstrike = { 121 }, -- wowsims/forever's: 8% of base mana, 121 at 60 (the DB2's: 125)
    searing_totem = { 25, 45, 75, 110, 145, 170 },
    flametongue_totem = { 90, 140, 200, 275 },
    strength_of_earth_totem = { 25, 65, 125, 225, 275 },
    mana_spring_totem = { 40, 60, 80, 100 },
    grace_of_air_totem = { 155, 250, 310 },
}
local FOCUSED = { earth_shock = true, flame_shock = true, lightning_shield = true }
local SHAMANISTIC_FOCUS = 1223030
-- Lightning Bolt's cast time by rank (DB2).
local LB_CAST = { 1.5, 2, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5 }

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

-- The cost of `key`'s rank `rank` with Clearcasting (`cc`: up) making an elemental spell free, Shamanistic Focus
-- (`sf`: taken) and each of `mw` Maelstrom Weapon stacks taking 20% off Lightning Bolt's.
local function costOf(key, rank, cc, mw, sf)
    if ELEMENTAL[key] and cc then
        return 0
    end
    local list = COST[key]
    if not list then
        return 0 -- a racial (Blood Fury): no cost
    end
    local c = #list == 1 and list[1] or assert(list[rank], key .. " has no rank " .. tostring(rank)) -- Stormstrike: one
    if FOCUSED[key] and sf then
        c = c * 0.55
    elseif key == "lightning_bolt" then
        c = c * math.max(0, 1 - 0.2 * mw)
    end
    return c
end

-- The rank (1-based) of spell `id` among one key's own IDs `ids` (never a shared category's).
local function rankOf(ids, id)
    for i, x in ipairs(ids) do
        if x == id then
            return i
        end
    end
    error("spell " .. tostring(id) .. " is no rank of its key")
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

-- The avoids each press rolls when not the special melee tables' (world.OUTCOMES, from wowsims/forever's shaman/*.go):
-- the spells are magic hits (OutcomeMagicHitAndCrit); Stormstrike is a special melee hit.
M.OUTCOMES = { lightning_bolt = "spell", earth_shock = "spell", flame_shock = "spell", fire_nova = "spell" }

-- Each recommendable ability: `effect(W, e, p, X)`, `requires(W, e, X)`. A key missing here fails the loop.
M.MAP = {
    lightning_bolt = spell("lightning_bolt", function(W, e, _, X)
        drop(W, e, X, "maelstrom_weapon")
    end),
    earth_shock = spell("earth_shock", function(W, e, _, X)
        e.cdUntil.flame_shock = W.t + X.shockCd -- the shared category
    end),
    flame_shock = spell("flame_shock", function(W, e, _, X)
        e.cdUntil.earth_shock = W.t + X.shockCd
        if e.lastHit.act == "WOUND" then -- the DoT only when the shock lands
            aura(W, X, e.target, "flame_shock", X.flameShock)
            W.dot(e, e.target, 3, X.flameShock / 3, 80)
        end
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
    -- The Orc racial wowsims fires (its autocast cooldowns, rule 13): its buff on us, nothing else the world models.
    blood_fury = {
        effect = function(W, e, _, X)
            aura(W, X, e, "blood_fury")
        end,
    },
    searing_totem = totem("searing_totem"),
    flametongue_totem = totem("flametongue_totem"),
    strength_of_earth_totem = totem("strength_of_earth_totem"),
    mana_spring_totem = totem("mana_spring_totem"),
    grace_of_air_totem = totem("grace_of_air_totem"),
}

-- The packs' worlds: `pack` the priority, `kit` the abilities the character knows (every rank), `weapon` the main hand, `uptime` the debuffs
-- reported. The imbues are left out of the kit: the world has no weapon enchant read (shaman_spec covers the reminder).
local PACKS = {
    -- Stormstrike, Maelstrom Weapon and Elemental Focus, a two-hander.
    Enhancement = {
        pack = "Enhancement (wowsims.com)",
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
            X.aura[key] = { id = a.id, duration = type(d) == "number" and d or 0, max_stack = a.max_stack }
        end
    end
    -- The world's own talent rules (the booted state's talents), restated from wowdb and wowsims/forever's spell data:
    -- Reverberation -0.2 s a rank on the shocks' 6 s, Call of Flame +3 s a rank on Flame Shock's 12 s.
    local T = H.Hekili.State.talent
    X.shockCd = 6 - 0.2 * T.reverberation.rank
    X.flameShock = 12 + 3 * T.call_of_flame.rank
    return X
end

local function content(name)
    local P = PACKS[name]
    local C = { PACK = P.pack, IDS = {} }
    local truth -- the current world's us (hooks): a press is priced by its true auras
    C.SPEC = ({ Enhancement = 100072 })[name]

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
            specID = M.CLIENT_SPEC,
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
        truth = us
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
    C.SHARED = { earth_shock = "flame_shock", flame_shock = "earth_shock" } -- the shocks' category (resolve's and the replay's)

    -- No power is swing-paid.
    function C.gain()
        return 0
    end

    --- The resolved press of `key` from instance `H` (the oracle's: its state is true): the highest known rank's ID
    --- and every known rank's (a shock's with the other shock's: the client answers the shared cooldown on both), the
    --- cost (Clearcasting and Maelstrom Weapon on the current world's us), the cooldown, GCD and cast time, the
    --- mapping's effects. Raises "unmapped key".
    function C.resolve(key, H)
        local m = M.MAP[key]
        if not m then
            error("unmapped key " .. tostring(key), 2)
        end
        local a = H.Hekili.Class.abilities[key]
        local X = classData(H, C)
        local S = H.Hekili.State
        local VS = H.ns.VirtualState
        local own = C.IDS[key] or { a.id } -- a racial (the content's race) is no kit key
        local ids = own
        if C.SHARED[key] then
            ids = {}
            local members = { key, C.SHARED[key] }
            table.sort(members) -- the category's ranks in one order whichever member is cast
            for _, k in ipairs(members) do
                for _, id in ipairs(C.IDS[k]) do
                    ids[#ids + 1] = id
                end
            end
        end
        -- Clearcasting and Maelstrom Weapon from the world, not the oracle: the leveling brackets never step the oracle
        if truth and truth.stopped then
            truth = nil -- the world ended (its stop): a later press has no world to read
        end
        local auras = truth and truth.auras or {}
        local cc = auras[X.aura.clearcasting.id]
        local mw = auras[X.aura.maelstrom_weapon.id] and auras[X.aura.maelstrom_weapon.id].stacks
        local spellID = VS.KnownID(a.id)
        local rank = rankOf(own, spellID)
        local p = {
            spell = spellID,
            ids = ids,
            cost = costOf(key, rank, cc ~= nil, mw or 0, S.talent.shamanistic_focus.rank > 0),
            pt = MANA,
            cooldown = tonumber(a.cooldown) or S.action[key].cooldown or 0,
            gcd = GCD[a.gcd or "spell"],
            offGcd = a.gcd == "off",
            -- every press is instant but Lightning Bolt, 2.5 s less 20% a Maelstrom Weapon stack (DB2 15208)
            cast = key == "lightning_bolt" and LB_CAST[rank] * math.max(0, 1 - 0.2 * (mw or 0)) or 0,
            refund = world.refundOf(H.Hekili.Class, key), -- an avoid gives back the kit's share (W.hit)
            outcomes = M.OUTCOMES[key], -- nil: the special melee tables
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
        local sf = H.Hekili.State.talent.shamanistic_focus.rank > 0 -- the build's (the booted oracle's talents)
        for key, m in pairs(M.MAP) do
            if H.Hekili.Class.abilities[key] and C.IDS[key] then
                for rank, id in ipairs(C.IDS[key]) do
                    out[#out + 1] = {
                        id,
                        function(W, e, power)
                            if m.requires and not m.requires(W, e, X) then
                                return false, false
                            end
                            local mw = e.auras[X.aura.maelstrom_weapon.id]
                            local cc = e.auras[X.aura.clearcasting.id] ~= nil
                            local c = costOf(key, rank, cc, mw and mw.stacks or 0, sf)
                            return power >= c, power < c
                        end,
                    }
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
