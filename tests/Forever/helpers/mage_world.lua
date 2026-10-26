-- tests/Forever/helpers/mage_world.lua (class-completion plan, "The per-pack gate"): the Mage content of the
-- class-neutral headless loop, in hunter_world.lua's shape, one content per wowsims.com pack (M.Arcane, M.Fire,
-- M.Frostfire): the character the instance logs in as (wowsims/forever's preset builds' talents), each ability's press
-- in the world's generic verbs, the client's usability answers. IDs, costs, cooldowns and aura durations come from the
-- class file (load_druid's recording load of Mage.lua for the character, the booted oracle's Hekili.Class for the
-- rest). The world's own, restated from the DB2 and wowsims/forever (so the class file's belief is measured against
-- them): Arcane Blast's 1.5 s cast, its charges (15 s from the first) and their cost (15% of base mana, +175% a
-- charge), Missile Barrage's proc (its talent's 20% / 40% on Arcane Blast, half that on Fireball, Frostbolt, Frostfire
-- Bolt and Arcane Wrath), Heating Up from the Fire casts' crits (Fire Blast one more on any hit) and Pyroblast's faster
-- cast and spend, Improved Scorch's Fire Vulnerability (33 / 67 / 100%), Fingers of Frost (a Chill's landed hit,
-- Frostbolt's or Frostfire Bolt's, grants its rank's charges at 15%; every other damage spell cast spends one, a landed
-- missile one; wowsims talents_frost.go; deviation: the grant lands at the cast's end, wowsims's at the bolt's hit
-- about 0.8 s later (its FFB log 11.64 cast, 12.47 hit): the harness has no travel time, a shared limit), Frost
-- Channeling's -5% a rank and Improved Fireball's -0.1 s on Frostfire Bolt, Clearcasting (Arcane Concentration's 2% a
-- rank on a damage spell's hit) and Arcane Power's costs, Presence of Mind's instant cast, mana under the five-second
-- rule (the pools and the regen wowsims's logs'). Damage amounts are UNMEASURED.
-- The hard casts are cast bars (a press with a cast time: UNIT_SPELLCAST_START and UnitCastingInfo at the press, the
-- success at the end) and the two channels are the world's channels (W.press `channel`): Arcane Missiles a missile a
-- tick (its rank's 3-5 s, a tick a second; Missile Barrage's half the time, a tick each 0.5 s, free), Evocation 8 s,
-- a tick a second, each tick's mana 16x the spirit part less the part the regen already pays (all of it continues
-- while channelling: DB2 12051 auras 110 and 134). Any press while Evocation runs at 99% mana or more clips it
-- (wowsims's interruptIf in both APLs' Evocation group).
-- Credit: wowsims/forever (MIT) as the reference for the charge, proc and gem rules; no code copied.
local ld = require("Forever.helpers.load_druid")
local world = require("Game.harness.world")

local M = {}

M.CLIENT_SPEC, M.CLASS_ID = 1485, 8 -- the client's Mage pseudo-spec (assumed: the alphabetical 1483-1491 row)
local MANA = 0 -- Enum.PowerType
local BASE = 1213 -- base mana at 60 (wowsims's ExtraClassBaseStats): a percent-of-base cost's base
local GCD = { spell = 1.5, off = 0 }
-- The spirit regen a second outside the five-second rule (wowsims's logs at 60: 2.913 a 0.1 s tick, both builds; the
-- class file declares the same 29.13, which the out-of-combat read corrects); each pack's share of it that continues while casting
-- is its own (below). UNMEASURED in game.
local SPIRIT = 29.13

-- Each rank's mana cost (DB2; Arcane Wrath wowsims's), lowest rank first, the world's truth the class file's are
-- measured against (a level's highest known rank pays its own).
local COST = {
    arcane_missiles = { 85, 140, 235, 320, 410, 500, 595, 655 },
    arcane_wrath = { 140, 220, 305, 395 },
    frostbolt = { 25, 35, 50, 65, 100, 130, 160, 195, 225, 260, 290 },
    fireball = { 30, 45, 65, 95, 140, 185, 220, 260, 305, 350, 395, 410 },
    scorch = { 50, 65, 80, 100, 115, 135, 150 },
    pyroblast = { 125, 150, 195, 240, 285, 335, 385, 440 },
    fire_blast = { 40, 75, 115, 165, 220, 280, 340 },
    frostfire_bolt = { 205, 285, 370 },
    counterspell = 100,
    evocation = 0,
    arcane_power = 0,
    presence_of_mind = 0,
    combustion = 0,
}

-- The cast times (DB2; Arcane Wrath wowsims's), top rank, unhasted.
local CAST = {
    arcane_blast = 1.5, -- wowsims's (ruling M9; the DB2's 2.5)
    arcane_wrath = 3.5,
    frostbolt = 3,
    fireball = 3.5,
    scorch = 1.5,
    pyroblast = 6,
    frostfire_bolt = 3,
}

-- UNMEASURED: the hits' amounts.
local AMOUNT = {
    arcane_missiles = 250, -- a missile
    arcane_blast = 700,
    arcane_wrath = 900,
    frostbolt = 700,
    fireball = 800,
    scorch = 400,
    pyroblast = 1100,
    fire_blast = 500,
    frostfire_bolt = 750,
}

-- The schools' damage spells (Clearcasting's and Arcane Power's scope by the DB2 masks; Arcane Wrath's by wowsims's),
-- Missile Barrage's proc casts, Heating Up's.
local CLEARCAST = {
    arcane_blast = true,
    arcane_missiles = true,
    arcane_wrath = true,
    frostbolt = true,
    fireball = true,
    scorch = true,
    pyroblast = true,
    fire_blast = true,
    frostfire_bolt = true,
}
local POWERED = CLEARCAST
local BARRAGE = { arcane_blast = 1, fireball = 0.5, frostbolt = 0.5, frostfire_bolt = 0.5, arcane_wrath = 0.5 }
local HEATING = { fireball = true, frostfire_bolt = true, fire_blast = true, scorch = true }
local FIRE = { fireball = true, frostfire_bolt = true, fire_blast = true, scorch = true, pyroblast = true }
local CHILL = { frostbolt = true, frostfire_bolt = true } -- Permafrost's mask's (wowsims's chillFlags) the kit casts
local FROST_CHANNELING = { frostbolt = true, frostfire_bolt = true } -- DB2 11160 effect 0's mask

-- The talents the world reads, by their DB2 (or wowsims's) rank-1 spells.
local T = {
    missile_barrage = 400588,
    arcane_concentration = 11213,
    heating_up = 400624,
    improved_scorch = 11095,
    improved_fireball = 11069,
    improved_frostbolt = 11070,
    wake_of_fire = 11078,
    fingers_of_frost = 400647,
    frost_channeling = 11160,
}

local W0
local function class()
    W0 = W0 or ld.load(nil, "src/Hekili_Mage/Mage.lua", "MAGE")
    return W0
end

-- The rank instance `H`'s character has in the talent whose spell is `spell` (0: untaken), from its traits.
local function talentRank(H, spell)
    local tr = H.ctl.traits
    for i, d in ipairs(tr and tr.defs or {}) do
        if d == spell then
            return tr.nodes[i].activeRank
        end
    end
    return 0
end

-- The packs' worlds: `pack` the wowsims.com pack it runs (the next task's), `spec` its spec id, `kit` the abilities the
-- character knows (every rank), `talents` wowsims/forever's preset build's ({ [rank-1 spell] = rank }; presets.ts
-- Arcane 0552205003100311531-03-0515, Fire 0502205-23550000130135031-005), `uptime` the debuffs reported.
-- `max` the mana pool and `casting` the share of SPIRIT that continues inside the five-second rule (wowsims's logs: the
-- Arcane build's 2.913 a tick inside it too, Arcane Meditation 3/3 on Mage Armor; the Fire build's 1.456, Mage Armor's).
local PACKS = {
    Arcane = {
        pack = "Arcane (wowsims.com)",
        spec = 100081,
        max = 6678,
        casting = 1,
        kit = {
            "arcane_missiles",
            "arcane_wrath",
            "arcane_blast",
            "frostbolt",
            "evocation",
            "arcane_power",
            "presence_of_mind",
            "counterspell",
        },
        talents = {
            [11222] = 5, -- Arcane Focus
            [11237] = 5, -- Improved Channeling
            [400588] = 2, -- Missile Barrage
            [11210] = 2, -- Arcane Subtlety
            [11213] = 5, -- Arcane Concentration
            [11242] = 3, -- Arcane Impact
            [400574] = 1, -- Arcane Blast
            [18462] = 3, -- Arcane Meditation
            [1326079] = 1, -- Arcane Wrath
            [12043] = 1, -- Presence of Mind
            [11232] = 5, -- Arcane Mind
            [15058] = 3, -- Arcane Instability
            [12042] = 1, -- Arcane Power
            [18459] = 2, -- Incineration (wowsims 3; the DB2's 2)
            [11070] = 5, -- Improved Frostbolt
            [29438] = 1, -- Elemental Precision
            [11207] = 5, -- Ice Shards
        },
        uptime = {},
    },
    Fire = {
        pack = "Fire (wowsims.com)",
        spec = 100082,
        max = 6168,
        casting = 0.5,
        kit = {
            "scorch",
            "pyroblast",
            "fire_blast",
            "arcane_missiles",
            "fireball",
            "frostfire_bolt",
            "evocation",
            "combustion",
            "counterspell",
        },
        talents = {
            [11222] = 5, -- Arcane Focus
            [400588] = 2, -- Missile Barrage
            [11210] = 2, -- Arcane Subtlety
            [11213] = 5, -- Arcane Concentration
            [11078] = 2, -- Wake of Fire (wowsims's Improved Fire Blast)
            [18459] = 2, -- Incineration (wowsims 3; the DB2's 2)
            [11069] = 5, -- Improved Fireball
            [11119] = 5, -- Ignite
            [11366] = 1, -- Pyroblast
            [11095] = 3, -- Improved Scorch
            [400624] = 1, -- Heating Up
            [29074] = 3, -- Master of Elements
            [11115] = 3, -- Critical Mass (wowsims 5; the DB2's 3)
            [11124] = 3, -- Fire Power
            [11129] = 1, -- Combustion
            [29438] = 3, -- Elemental Precision (wowsims 5; the DB2's 3)
        },
        uptime = { "fire_vulnerability" },
    },
    -- presets.ts FFBTalents -2355000013011503-00550003310003002 (29 Fire, 22 Frost: the Fire spec); the log's pool and
    -- regen are the Fire build's (6168; half the spirit part while casting, Mage Armor's).
    Frostfire = {
        pack = "Frostfire (wowsims.com)",
        spec = 100082,
        max = 6168,
        casting = 0.5,
        kit = {
            "scorch",
            "pyroblast",
            "fire_blast",
            "fireball",
            "frostbolt",
            "frostfire_bolt",
            "evocation",
            "counterspell",
        },
        talents = {
            [11078] = 2, -- Wake of Fire (wowsims's Improved Fire Blast)
            [18459] = 2, -- Incineration (wowsims 3; the DB2's 2)
            [11069] = 5, -- Improved Fireball
            [11119] = 5, -- Ignite
            [11366] = 1, -- Pyroblast
            [11095] = 3, -- Improved Scorch
            [400624] = 1, -- Heating Up
            [29074] = 1, -- Master of Elements
            [11115] = 3, -- Critical Mass (wowsims 5; the DB2's 3)
            [11124] = 3, -- Fire Power
            [29438] = 3, -- Elemental Precision (wowsims 5; the DB2's 3)
            [11207] = 5, -- Ice Shards
            [11151] = 3, -- Piercing Ice
            [11160] = 3, -- Frost Channeling
            [1312002] = 1, -- Ice Lance
            [11170] = 3, -- Shatter
            [400647] = 2, -- Fingers of Frost
        },
        uptime = { "fire_vulnerability" },
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

-- What a press reads of our auras: on the true entity `e` (a usability answer) or in the oracle's true belief (a
-- resolve: hunter_world reads its haste so). Each returns up(key) and stacks(key).
local function onEntity(e, X)
    return function(key)
        return e.auras[X.aura[key].id] ~= nil
    end, function(key)
        local a = e.auras[X.aura[key].id]
        return a and a.stacks or 0
    end
end
local function inBelief(H, X)
    local VS, now = H.ns.VirtualState, H.ctl.now
    return function(key)
        return VS.Aura("player", X.aura[key].id, now) ~= nil
    end, function(key)
        local rec, n = VS.Aura("player", X.aura[key].id, now)
        return rec and n or 0
    end
end

local function aura(W, X, dst, key, n)
    local a = X.aura[key]
    W.applyAura(dst, a.id, a.duration, n or 1, a.max_stack)
end
local function drop(W, e, X, key) -- aura `key` off `e`, if up
    local id = X.aura[key].id
    if e.auras[id] then
        e.auras[id] = nil
        W.emit({ kind = "aura", dst = e, aura = id, stacks = 0, expires = 0, duration = 0 })
    end
end
local function unstack(W, e, X, key) -- one stack of `key` off `e`, its expiry kept
    local a = e.auras[X.aura[key].id]
    if a and a.stacks > 1 then
        a.stacks = a.stacks - 1
        W.emit({
            kind = "aura",
            dst = e,
            aura = X.aura[key].id,
            stacks = a.stacks,
            expires = a.expires,
            duration = a.duration,
        })
    elseif a then
        drop(W, e, X, key)
    end
end

-- The cost of `key`'s highest rank instance `H`'s character knows (`ids`: its ranks, lowest first), with our auras read
-- by `up` and `stacks`: Arcane Blast's from its charges, Clearcasting's free cast, Arcane Power's +30% (the truth the
-- cost modifiers are measured against).
local function costOf(key, ids, H, up, stacks)
    local c
    if key == "arcane_blast" then
        c = math.floor(0.15 * (1 + 1.75 * stacks("arcane_blast")) * BASE) -- as the kit's spendBase: floor(fraction x base)
    else
        c = COST[key] or 0
        if type(c) == "table" then
            local rank = #c
            for i = #ids, 1, -1 do
                if H.ctl.known[ids[i]] then
                    rank = i
                    break
                end
            end
            c = c[rank]
        end
        if FROST_CHANNELING[key] then
            c = c * (1 - 0.05 * talentRank(H, T.frost_channeling))
        end
    end
    if (CLEARCAST[key] and up("clearcasting")) or (key == "arcane_missiles" and up("missile_barrage")) then
        return 0
    end
    if POWERED[key] and up("arcane_power") then
        c = c * 1.3
    end
    return c
end

-- The cast time of `key`: Presence of Mind instant, Heating Up's -25% a stack on Pyroblast, the talents' cuts.
local function castOf(key, H, up, stacks)
    local c = CAST[key]
    if not c or up("presence_of_mind") then
        return 0
    end
    if key == "pyroblast" then
        c = c * (1 - 0.25 * stacks("heating_up"))
    elseif key == "fireball" or key == "frostfire_bolt" then -- Improved Fireball's mask names both (DB2 11069)
        c = c - 0.1 * talentRank(H, T.improved_fireball)
    elseif key == "frostbolt" then
        c = c - 0.1 * talentRank(H, T.improved_frostbolt)
    end
    return c
end

-- A damage spell's hit and its procs (Missile Barrage, Heating Up, Clearcasting); Clearcasting spent first, Presence of
-- Mind by a spell with a cast time. `extra(W, e, X, H, landed, instant)` after.
local function spell(key, extra)
    return {
        outcomes = "spell",
        effect = function(W, e, p, X, H)
            local up = onEntity(e, X)
            if CLEARCAST[key] and up("clearcasting") then
                drop(W, e, X, "clearcasting")
            end
            local instant = (p.cast or 0) == 0
            if CAST[key] then
                drop(W, e, X, "presence_of_mind")
            end
            unstack(W, e, X, "fingers_of_frost") -- spent at the cast, before this cast's own grant
            local hit = W.hit(e, e.target, AMOUNT[key], FIRE[key] and 4 or 64)
            local landed, crit = hit.act == "WOUND", hit.flag == "CRITICAL"
            local fof = CHILL[key] and talentRank(H, T.fingers_of_frost) or 0
            if landed and fof > 0 and W.rng.chance(0.15) then -- the charges set to the rank's (1 / 2), refreshed
                e.auras[X.aura.fingers_of_frost.id] = nil
                aura(W, X, e, "fingers_of_frost", fof)
            end
            if landed then
                local mb = BARRAGE[key] and 0.2 * talentRank(H, T.missile_barrage) * BARRAGE[key] or 0
                if mb > 0 and W.rng.chance(mb) then
                    aura(W, X, e, "missile_barrage")
                end
                local ac = talentRank(H, T.arcane_concentration)
                if ac > 0 and W.rng.chance(0.02 * ac) then
                    aura(W, X, e, "clearcasting")
                end
                local n = HEATING[key] and ((crit and 1 or 0) + (key == "fire_blast" and 1 or 0)) or 0
                if n > 0 and talentRank(H, T.heating_up) > 0 then
                    aura(W, X, e, "heating_up", n)
                end
            end
            if extra then
                extra(W, e, X, H, landed, instant)
            end
        end,
    }
end

local IMPROVED_SCORCH = { 0.33, 0.67, 1 }
local WAKE_OF_FIRE = { [0] = 0, 1, 2, 2 } -- Fire Blast's cooldown cut by rank (wowsims's; a third DB2 rank as the second)

local MISSILES_TIME = { 3, 4, 5, 5, 5, 5, 5, 5 } -- Arcane Missiles' channel by rank (DB2)

-- Each recommendable ability: `effect(W, e, p, X, H)` (a channel's at its start), `requires(W, e, X)`, `channel(H, ids,
-- up)` (a channel's { length, tick, effect }). A key missing here fails the loop.
M.MAP = {
    arcane_blast = spell("arcane_blast", function(W, e, X)
        local a, c = X.aura.arcane_blast, e.auras[X.aura.arcane_blast.id]
        -- a charge; the run ends 15 s after its first (wowsims arcane_charge.go)
        W.applyAura(e, a.id, c and c.expires - W.t or a.duration, 1, a.max_stack)
    end),
    arcane_wrath = spell("arcane_wrath"),
    frostbolt = spell("frostbolt"),
    fireball = spell("fireball"),
    frostfire_bolt = spell("frostfire_bolt"),
    fire_blast = spell("fire_blast"),
    scorch = spell("scorch", function(W, e, X, H, landed)
        local r = talentRank(H, T.improved_scorch)
        if landed and r > 0 and W.rng.chance(IMPROVED_SCORCH[r] or 1) then
            aura(W, X, e.target, "fire_vulnerability")
        end
    end),
    pyroblast = spell("pyroblast", function(W, e, X, _, _, instant)
        if not instant then -- every stack spent, unless Presence of Mind made it instant (wowsims talents_fire.go)
            drop(W, e, X, "heating_up")
        end
    end),
    arcane_power = {
        effect = function(W, e, _, X)
            aura(W, X, e, "arcane_power")
        end,
    },
    presence_of_mind = {
        requires = function(_, e, X)
            return not onEntity(e, X)("presence_of_mind"), "already up"
        end,
        effect = function(W, e, _, X)
            aura(W, X, e, "presence_of_mind")
        end,
    },
    combustion = {
        requires = function(_, e, X)
            return not onEntity(e, X)("combustion"), "already up"
        end,
        effect = function(W, e, _, X)
            aura(W, X, e, "combustion")
        end,
    },
    counterspell = {
        requires = function()
            return false, "the mob casts nothing"
        end,
    },
    arcane_missiles = {
        effect = function(W, e, _, X)
            local up = onEntity(e, X)
            for _, key in ipairs({ "missile_barrage", "clearcasting" }) do -- the cast spends both (wowsims talents_arcane.go)
                if up(key) then
                    drop(W, e, X, key)
                end
            end
        end,
        channel = function(H, ids, up)
            local rank = #MISSILES_TIME
            for i = #ids, 1, -1 do
                if H.ctl.known[ids[i]] then
                    rank = i
                    break
                end
            end
            local half, X = up("missile_barrage") and 0.5 or 1, classData(H)
            return {
                length = MISSILES_TIME[rank] * half,
                tick = half,
                effect = function(W, e)
                    -- each missile rolls its own hit; a landed one spends a Fingers of Frost charge
                    if W.hit(e, e.target, AMOUNT.arcane_missiles, 64, "spell").act == "WOUND" then
                        unstack(W, e, X, "fingers_of_frost")
                    end
                end,
            }
        end,
    },
    evocation = {
        effect = function(W, e, _, X) -- its buff for the channel (the replay's from the log)
            aura(W, X, e, "evocation")
        end,
        channel = function()
            return {
                length = 8,
                tick = 1,
                effect = function(W, e)
                    W.emit({ kind = "gain", src = e, pt = MANA, rage = 16 * SPIRIT - W.regenRate(e, MANA) })
                end,
            }
        end,
    },
}

-- The book ranks (Fireball 12, Frostbolt 11, Arcane Missiles 8, DB2 level 56-60) no trainer teaches: wowsims/forever's
-- Mage registers the last trainer rank (sim/mage/fireball.go:11-12, frostbolt.go:11-12, arcane_missiles.go:11-12; its
-- logs cast 10151, 10181 and 10212), so the worlds' character has not learned them.
local BOOK = { [25306] = true, [25304] = true, [25345] = true }

local function content(name)
    local P = PACKS[name]
    local C = { PACK = P.pack, SPEC = P.spec, IDS = {} }
    local MAX = P.max
    local FSR = { SPIRIT * (1 - P.casting), SPIRIT * P.casting } -- { spirit part, the part that continues }

    function C.character()
        local w = class()
        local known = {}
        for _, key in ipairs(P.kit) do
            local a = assert(w.abilities[key], key)
            local ids = { a.id }
            for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
                ids[#ids + 1] = not BOOK[id] and id or nil
            end
            C.IDS[key] = ids
            for _, id in ipairs(ids) do
                known[#known + 1] = id
            end
        end
        return {
            class = "MAGE",
            classID = M.CLASS_ID,
            specID = M.CLIENT_SPEC,
            level = 60,
            known = known,
            talents = P.talents,
            power = { type = MANA, token = "MANA", max = MAX },
            speed = { 3.0 },
        }
    end

    -- Level 60 against a level 60 mob in range, the pack's mana full and under the five-second rule. Neither side dies
    -- (hunter_world's reason: a kill ends the loop before the client sees it).
    local function hooks(_, us)
        us.health, us.healthMax = 1e9, 1e9
    end
    C.WORLD = {
        level = 60,
        canParry = false, -- mages never parry (wowsims's CanParry)
        weapons = { { 40, 70, 3.0 } },
        max = MAX,
        fsr = { [MANA] = FSR },
        power = MAX,
        mobHealth = 1e9,
        distance = 25, -- a caster's range: no melee swings of ours
        script = hooks,
    }

    -- No other power read (mana is secret in combat).
    C.OBSERVE = { powerTokens = { [MANA] = "MANA" } }

    -- No power is swing-paid.
    function C.gain()
        return 0
    end

    --- The resolved press of `key` from instance `H` (the oracle's: its state is true): the highest known rank's ID
    --- and every known rank's, the cost, the cooldown, GCD and cast time on the true state, the mapping's effects. Raises
    --- "unmapped key".
    function C.resolve(key, H)
        local m = M.MAP[key]
        if not m then
            error("unmapped key " .. tostring(key), 2)
        end
        local a = H.Hekili.Class.abilities[key]
        local X = classData(H)
        local S = H.Hekili.State
        local VS = H.ns.VirtualState
        local ids = C.IDS[key]
        if not ids then -- a key the world's kit lacks: every rank the class registers
            ids = { a.id }
            for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
                ids[#ids + 1] = id
            end
        end
        local up, stacks = inBelief(H, X)
        local p = {
            spell = VS.KnownID(a.id),
            ids = ids,
            cost = costOf(key, ids, H, up, stacks),
            pt = MANA,
            cooldown = key == "fire_blast" and 8 - WAKE_OF_FIRE[talentRank(H, T.wake_of_fire)]
                or tonumber(a.cooldown)
                or S.action[key].cooldown
                or 0,
            gcd = GCD[a.gcd or "spell"],
            offGcd = a.gcd == "off",
            cast = castOf(key, H, up, stacks),
            refund = world.refundOf(H.Hekili.Class, key),
            outcomes = m.outcomes,
        }
        if m.channel then
            p.channel = m.channel(H, ids, up)
        end
        -- Evocation clipped at 99% mana (the oracle's true belief: its channel and its mana)
        local I = H.ns.VirtualStateInternal
        p.clip = I.channel and I.castAb == I.ab.bySpell[12051] and VS.Power(MANA, H.ctl.now).est >= 0.99 * MAX
        p.requires = function(W, e)
            local ok, why = true, nil
            if m.requires then
                ok, why = m.requires(W, e, X)
            end
            -- a clip ends Evocation's buff with its channel: W.press reads `requires` last, just before the clip
            if ok and p.clip and e.channel then
                drop(W, e, X, "evocation")
            end
            return ok, why
        end
        p.effect = function(W, e)
            if m.effect then
                m.effect(W, e, p, X, H)
            end
        end
        return p
    end

    --- The client's usability answers for every known rank of every pressable kit ability: unusable (not for power)
    --- when the mapping's requirement fails in the true world, else usable when mana covers the cost, short when not.
    function C.usable(H)
        local out = {}
        local X = classData(H)
        for key, m in pairs(M.MAP) do
            if H.Hekili.Class.abilities[key] and C.IDS[key] then
                local ids = C.IDS[key]
                local function answer(W, e, power)
                    if m.requires and not m.requires(W, e, X) then
                        return false, false
                    end
                    local cost = costOf(key, ids, H, onEntity(e, X))
                    return power >= cost, power < cost
                end
                for _, id in ipairs(ids) do
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

M.Arcane = content("Arcane")
M.Fire = content("Fire")
M.Frostfire = content("Frostfire")

return M
