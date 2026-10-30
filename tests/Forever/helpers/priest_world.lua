-- tests/Forever/helpers/priest_world.lua (class-completion plan, "The per-pack gate"): the Priest content of the
-- class-neutral headless loop, in mage_world.lua's shape, one content per wowsims.com pack (M.Shadow on Shadow, M.Smite
-- on Discipline): the character the instance logs in as (wowsims/forever's two preset builds' talents), each ability's
-- press in the world's generic verbs, the client's usability answers. IDs, costs, cooldowns and aura durations come from
-- the class file (load_druid's recording load of Priest.lua for the character, the booted oracle's Hekili.Class for the
-- rest). The world's own, restated from the DB2 and wowsims/forever (so the class file's belief is measured against
-- them): each rank's cost, Mental Agility's -3 / -7 / -10% on its mask's spells, Devouring Contagion's -25 / -50% on
-- Devouring Plague, Shadowform's -50% on the Shadow spells, Inner Focus's free next spell and Holy Purpose's free Holy
-- Nova, Divine Fury's -0.1 s a rank on Smite and Holy Fire, Improved Shadow Word: Pain's +3 s a rank, the percent
-- costs (Shadowform 40%, Power Infusion 20% of base mana), Dark Sacrifice's mana (320 and the Undead build's Spirit
-- over five 3 s ticks), mana under the five-second rule (the pools and the regen wowsims's logs': testing.build.json
-- and smite_testing.build.json at the pin, seed 101). Damage amounts are UNMEASURED.
-- The hard casts are cast bars (Mind Blast, Smite, Holy Fire: UNIT_SPELLCAST_START and UnitCastingInfo at the press,
-- the success at the end) and the four channels are the world's channels (W.press `channel`): Mind Flay 3 s and
-- Starshards 6 s, a tick a second; Penance 2 s, a bolt at its start and each second; the wand's Shoot one shot a wand
-- speed after the press (wowsims's core/wand.go: Shoot blocks the rotation until it).
-- Not modelled here: the procs (Holy Purpose from Searing Light's roll on Holy Fire's ticks: no solo fight casts Holy
-- Nova, wowsims's line needs three targets; Spirit Tap; Shadow Weaving), resists of the DoTs, Shadow Word: Death's
-- backlash. Dark Inspiration (1326168, 10 s; the Shadow build's 5/5) is on us at the pull, on each landed Mind Blast
-- and on each Mind Flay channel's last tick (wowsims talents_shadow.go:107-138), its Spirit x 1.15 in the regen.
-- Credit: wowsims/forever (MIT, https://github.com/wowsims/forever) as the reference for the talent, wand and Dark
-- Sacrifice rules and the source of the builds; no code copied.
local ld = require("Forever.helpers.load_druid")
local world = require("Game.harness.world")

local M = {}

M.CLIENT_SPEC, M.CLASS_ID = 1487, 5 -- the client's Priest pseudo-spec (assumed: the alphabetical 1483-1491 row)
local MANA = 0 -- Enum.PowerType
local BASE = 1376 -- base mana at 60 (wowsims's priest base stats): a percent-of-base cost's base
local GCD = { spell = 1.5, off = 0 }
local SHADOWFORM = 1 -- its index in the client's forms (the Shadow character's only one)

-- Each rank's mana cost (DB2), lowest rank first, the world's truth the class file's are measured against (a level's
-- highest known rank pays its own); a fraction is of base mana.
local COST = {
    shadow_word_pain = { 25, 50, 95, 155, 230, 305, 385, 470 },
    mind_blast = { 50, 80, 110, 150, 185, 225, 265, 310, 350 },
    mind_flay = { 45, 70, 100, 135, 165, 205 },
    devouring_plague = { 215, 350, 495, 645, 810, 985 },
    shadow_word_death = { 175, 205, 250, 340 },
    vampiric_embrace = 40,
    shadowform = 0.4,
    shadowguard = { 50, 85, 120, 160, 200, 250 },
    dark_sacrifice = 0,
    starshards = { 50, 85, 140, 190, 245, 300, 350 },
    smite = { 20, 30, 60, 95, 140, 185, 230, 280 },
    holy_fire = { 85, 95, 125, 145, 170, 200, 230, 255 },
    penance = { 150, 220, 270, 385 },
    holy_nova = { 185, 290, 400, 520, 635, 750 },
    power_word_shield = { 45, 80, 130, 175, 210, 250, 300, 355, 425, 500 },
    inner_fire = { 30, 65, 105, 165, 235, 315 },
    inner_focus = 0,
    power_infusion = 0.2,
    shoot = 0,
}

-- The hard casts (DB2), top rank, unhasted; Smite's by rank.
local CAST = { mind_blast = 1.5, holy_fire = 3.5 }
local SMITE_CAST = { 1.5, 2, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5 }

-- UNMEASURED: the hits' amounts (a channel's a tick).
local AMOUNT = {
    mind_blast = 980,
    shadow_word_death = 700,
    smite = 750,
    holy_fire = 900,
    holy_nova = 400,
    mind_flay = 330,
    starshards = 350,
    penance = 500,
}
local SCHOOL = { shadow = 32, holy = 2, arcane = 64, fire = 4 }

-- The scopes, by the DB2 masks and schools: Mental Agility's (14520 effect 0), Shadowform's Shadow spells (15473 effect
-- 3, misc 32), Inner Focus's (14751 effect 0).
local AGILE = {
    power_word_shield = true,
    smite = true,
    inner_fire = true,
    shadow_word_pain = true,
    devouring_plague = true,
    power_infusion = true,
    holy_fire = true,
    holy_nova = true,
    vampiric_embrace = true,
    shadowform = true,
    shadowguard = true,
}
local SHADOW = {
    shadow_word_pain = true,
    devouring_plague = true,
    mind_blast = true,
    vampiric_embrace = true,
    mind_flay = true,
    shadowform = true,
    shadowguard = true,
    shadow_word_death = true,
}
local FOCUSED = {
    power_word_shield = true,
    smite = true,
    inner_fire = true,
    shadow_word_pain = true,
    devouring_plague = true,
    mind_blast = true,
    power_infusion = true,
    starshards = true,
    holy_fire = true,
    holy_nova = true,
    vampiric_embrace = true,
    mind_flay = true,
    shadowform = true,
    shadowguard = true,
    penance = true,
    shadow_word_death = true,
}
local MENTAL_AGILITY = { [0] = 0, 0.03, 0.07, 0.1, 0.1, 0.1 } -- wowsims's per rank; the DB2's ranks 4-5 as the third
local DEVOURING_CONTAGION = { [0] = 0, 0.25, 0.5 }

-- The talents the world reads, by their DB2 (or wowsims's) rank-1 spells.
local T = {
    mental_agility = 14520,
    devouring_contagion = 1309950,
    divine_fury = 18530,
    improved_shadow_word_pain = 15275,
    dark_inspiration = 1326159,
}

local W0
local function class()
    W0 = W0 or ld.load(nil, "src/Hekili_Priest/Priest.lua", "PRIEST")
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

-- The rank of `ids` (lowest first) instance `H`'s character knows highest (the top's when none).
local function rankOf(ids, H)
    for i = #ids, 1, -1 do
        if H.ctl.known[ids[i]] then
            return i
        end
    end
    return #ids
end

-- The packs' worlds: `pack` the wowsims.com pack it runs (the next task's), `spec` its spec id, `kit` the abilities the
-- character knows (every rank), `talents` the preset build's ({ [rank-1 spell] = rank }; a rank past the DB2's maximum
-- as the DB2's), `forms` / `form` the client's forms and the one up at login (wowsims's preShadowform), `uptime` the
-- debuffs reported. `max` the mana pool and `fsr` the regen ({ the spirit part, the part that continues while casting }
-- a second, as W.regenRate): the logs' (Shadow: 2.688 a 0.1 s tick pre-pull while casting, Meditation's 0.5 share,
-- S = 6.25 + 186.67/8 = 29.58 without Dark Inspiration; under it Spirit +28, S + 3.5: the log's 2.863 a tick while
-- casting; Smite: 3.573 casting, 5.585 outside); `stats` UnitStat's (the belief's Spirit read: Shadow 187, Dark
-- Inspiration's 186.67; Smite 272, the Dark Sacrifice tick's).
local PACKS = {
    Shadow = {
        pack = "Shadow (wowsims.com)",
        spec = 100053,
        max = 4711,
        fsr = { 14.79, 26.88, share = 0.5, auras = { [1326168] = { spirit = (29.58 + 3.5) / 29.58 } } },
        stats = { [5] = 187 },
        kit = {
            "shadowform",
            "shadow_word_pain",
            "devouring_plague",
            "mind_blast",
            "mind_flay",
            "shadow_word_death",
            "vampiric_embrace",
            "inner_focus",
            "inner_fire",
            "smite", -- the pack's leveling filler before Mind Flay (silent at 60)
        },
        talents = { -- 00530320103--50052201251302051 (Human)
            [1225132] = 5, -- Twin Disciplines
            [14523] = 3, -- Silent Resolve
            [18551] = 3, -- Mental Strength
            [14531] = 2, -- Martyrdom
            [14751] = 1, -- Inner Focus
            [14521] = 3, -- Meditation
            [15260] = 5, -- Shadow Focus
            [15273] = 5, -- Improved Mind Blast
            [15275] = 2, -- Improved Shadow Word: Pain
            [17322] = 2, -- Shadow Reach
            [15407] = 1, -- Mind Flay
            [1225139] = 2, -- Improved Mind Flay
            [1326159] = 5, -- Dark Inspiration
            [15286] = 1, -- Vampiric Embrace
            [15257] = 3, -- Shadow Weaving
            [1309950] = 2, -- Devouring Contagion
            [15259] = 5, -- Darkness
            [15473] = 1, -- Shadowform
        },
        forms = { 15473 },
        form = SHADOWFORM,
        uptime = { "shadow_word_pain", "devouring_plague" },
    },
    Smite = {
        pack = "Smite (wowsims.com)",
        spec = 100051,
        max = 6151,
        fsr = { 20.12, 35.73 },
        stats = { [5] = 272 },
        kit = {
            "smite",
            "holy_fire",
            "shadow_word_pain",
            "devouring_plague",
            "shadow_word_death",
            "mind_blast",
            "penance",
            "holy_nova",
            "power_infusion",
            "shoot",
            "inner_focus",
            "inner_fire",
            "dark_sacrifice",
        },
        talents = { -- 525235031030001001-30515100002-3 (Undead)
            [1309969] = 5, -- Power in Light
            [14524] = 2, -- Wand Specialization
            [1225132] = 5, -- Twin Disciplines
            [14523] = 2, -- Silent Resolve
            [1309957] = 3, -- Holy Precision
            [18551] = 5, -- Mental Strength
            [14520] = 3, -- Mental Agility
            [14751] = 1, -- Inner Focus
            [14521] = 3, -- Meditation
            [402174] = 1, -- Penance
            [10060] = 1, -- Power Infusion
            [14913] = 2, -- Twilight Focus (wowsims 3; the DB2's 2)
            [14889] = 5, -- Holy Specialization
            [27900] = 1, -- Spell Warding
            [18530] = 5, -- Divine Fury
            [15237] = 1, -- Holy Nova
            [14909] = 2, -- Searing Light
            [15260] = 3, -- Shadow Focus
        },
        ranged = { 52, 82, 1.2 }, -- the Brilliant Wand (ItemSparse 249385: 1.2 s; the log's base damage 52-82)
        uptime = { "shadow_word_pain", "holy_fire" },
    },
}

-- The class data a press reads from a booted instance `H` (once per instance): each aura's ID, duration (a function's:
-- nil, the press passes its own) and stacks.
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
            X.aura[key] = { id = a.id, duration = type(d) == "number" and d or nil, max_stack = a.max_stack }
        end
    end
    return X
end

-- What a press reads of our state: on the true entity `e` (a usability answer; Shadowform its form) or in the oracle's
-- true belief (a resolve). Each returns up(key).
local function onEntity(e, X)
    return function(key)
        if key == "shadowform" then
            return e.form == SHADOWFORM
        end
        return e.auras[X.aura[key].id] ~= nil
    end
end
local function inBelief(H, X)
    local VS, now = H.ns.VirtualState, H.ctl.now
    return function(key)
        return VS.Aura("player", X.aura[key].id, now) ~= nil
    end
end

local function aura(W, X, dst, key, duration, n)
    local a = X.aura[key]
    W.applyAura(dst, a.id, duration or a.duration, n or 1, a.max_stack)
end
local function drop(W, e, X, key) -- aura `key` off `e`, if up
    local id = X.aura[key].id
    if e.auras[id] then
        e.auras[id] = nil
        W.emit({ kind = "aura", dst = e, aura = id, stacks = 0, expires = 0, duration = 0 })
    end
end

-- The cost of `key`'s highest rank instance `H`'s character knows (`ids`: its ranks, lowest first), our auras read by
-- `up`: the talents' cuts, Shadowform's, then Inner Focus's and Holy Purpose's free cast (the truth the class file's
-- spend functions and cost modifiers are measured against).
local function costOf(key, ids, H, up)
    local c = COST[key] or 0
    if type(c) == "table" then
        c = c[rankOf(ids, H)]
    elseif c > 0 and c < 1 then
        c = math.floor(c * BASE)
    end
    if AGILE[key] then
        c = c * (1 - MENTAL_AGILITY[talentRank(H, T.mental_agility)])
    end
    if key == "devouring_plague" then
        c = c * (1 - DEVOURING_CONTAGION[talentRank(H, T.devouring_contagion)])
    end
    if SHADOW[key] and up("shadowform") then
        c = c * 0.5
    end
    if (FOCUSED[key] and up("inner_focus")) or (key == "holy_nova" and up("holy_purpose")) then
        return 0
    end
    return c
end

-- The cast time of `key`: Divine Fury's cut on Smite and Holy Fire.
local function castOf(key, ids, H)
    local c = key == "smite" and SMITE_CAST[rankOf(ids, H)] or CAST[key]
    if not c then
        return 0
    end
    if key == "smite" or key == "holy_fire" then
        c = c - 0.1 * talentRank(H, T.divine_fury)
    end
    return c
end

-- A spell's cast: Inner Focus spent by a spell in its scope with a cost (wowsims: its charge), a hit of `AMOUNT[key]`
-- (nil: a DoT's own landing, no damage) in `school`, and `debuff` (its duration `dur(H)` or the aura's) on the target
-- when it lands.
local function spell(key, school, debuff, dur)
    return {
        outcomes = "spell",
        effect = function(W, e, p, X, H)
            if FOCUSED[key] and (COST[key] or 0) ~= 0 then
                drop(W, e, X, "inner_focus")
            end
            if key == "holy_nova" then
                drop(W, e, X, "holy_purpose")
            end
            local landed = W.hit(e, e.target, AMOUNT[key], SCHOOL[school]).act == "WOUND"
            if landed and debuff then
                aura(W, X, e.target, debuff, dur and dur(H))
            end
            if landed and key == "mind_blast" and talentRank(H, T.dark_inspiration) > 0 then
                aura(W, X, e, "dark_inspiration")
            end
        end,
    }
end
local function selfAura(key, n)
    return {
        effect = function(W, e, _, X)
            if FOCUSED[key] and (COST[key] or 0) ~= 0 then
                drop(W, e, X, "inner_focus")
            end
            aura(W, X, e, key, nil, n)
        end,
    }
end
-- A channel of `length` s ticking every `tick` s (`first`: a hit at its start too, Penance's bolt), each tick a hit;
-- `debuff` its aura on the target for the channel.
local function channel(key, school, length, tick, first)
    return {
        effect = function(W, e, _, X)
            drop(W, e, X, "inner_focus") -- each channel here is in its scope and costs mana
            aura(W, X, e.target, key, length)
            if first then
                W.hit(e, e.target, AMOUNT[key], SCHOOL[school], "spell")
            end
        end,
        channel = function(H)
            local inspires = key == "mind_flay" and talentRank(H, T.dark_inspiration) > 0
            return {
                length = length,
                tick = tick,
                effect = function(W, e, _, n)
                    W.hit(e, e.target, AMOUNT[key], SCHOOL[school], "spell")
                    if inspires and n == math.floor(length / tick + 1e-9) then -- the full channel's last tick
                        aura(W, classData(H), e, "dark_inspiration")
                    end
                end,
            }
        end,
    }
end

-- Each recommendable ability: `effect(W, e, p, X, H)` (a channel's at its start), `requires(W, e, X)`, `channel(H, P)`
-- (a channel's { length, tick, effect }), `aura(spell)` (W.press's generic aura with ticks, the cast rank's ID), `shift`
-- (W.press's form change). A key missing here fails the loop.
M.MAP = {
    shadow_word_pain = spell("shadow_word_pain", "shadow", "shadow_word_pain", function(H)
        return 18 + 3 * talentRank(H, T.improved_shadow_word_pain)
    end),
    devouring_plague = spell("devouring_plague", "shadow", "devouring_plague"),
    vampiric_embrace = spell("vampiric_embrace", "shadow", "vampiric_embrace"),
    mind_blast = spell("mind_blast", "shadow"),
    shadow_word_death = spell("shadow_word_death", "shadow"),
    smite = spell("smite", "holy"),
    holy_fire = spell("holy_fire", "holy", "holy_fire"),
    holy_nova = spell("holy_nova", "holy"),
    mind_flay = channel("mind_flay", "shadow", 3, 1),
    starshards = channel("starshards", "arcane", 6, 1),
    penance = channel("penance", "holy", 2, 1, true),
    shoot = {
        effect = function(W, e, _, X)
            aura(W, X, e.target, "shoot", e.ranged[3])
        end,
        channel = function(_, P) -- one shot a wand speed after the press (wowsims's wand.go)
            local w = P.ranged
            return {
                length = w[3],
                tick = w[3],
                effect = function(W, e)
                    W.hit(e, e.target, W.rng.int(w[1], w[2]), SCHOOL.fire, "spell") -- the Brilliant Wand's school
                end,
            }
        end,
    },
    shadowform = {
        shift = { form = SHADOWFORM },
        effect = function(W, e, _, X)
            drop(W, e, X, "inner_focus")
        end,
    },
    shadowguard = selfAura("shadowguard", 3),
    inner_fire = selfAura("inner_fire", 20),
    power_word_shield = {
        requires = function(_, e, X)
            return not onEntity(e, X)("weakened_soul"), "weakened soul"
        end,
        effect = function(W, e, _, X)
            drop(W, e, X, "inner_focus")
            aura(W, X, e, "power_word_shield")
            aura(W, X, e, "weakened_soul")
        end,
    },
    inner_focus = {
        requires = function(_, e, X)
            return not onEntity(e, X)("inner_focus"), "already up"
        end,
        effect = function(W, e, _, X)
            aura(W, X, e, "inner_focus")
        end,
    },
    power_infusion = {
        effect = function(W, e, _, X)
            drop(W, e, X, "inner_focus")
            W.applyAura(e, 10060, 15, 1, 1) -- Hekili_Shared's power_infusion (DB2 15 s)
        end,
    },
    -- its mana every 3 s for 15 s: 320 and Spirit once over the five ticks (the Undead build's, about 272)
    dark_sacrifice = {
        aura = function(spell)
            return { id = spell, duration = 15, tick = { pt = MANA, every = 3, amount = 320 + 272 / 5 } }
        end,
    },
}

local function content(name)
    local P = PACKS[name]
    local C = { PACK = P.pack, SPEC = P.spec, IDS = {} }
    local MAX = P.max

    function C.character()
        local w = class()
        local known = {}
        for _, key in ipairs(P.kit) do
            local a = assert(w.abilities[key], key)
            local ids = { a.id }
            for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
                ids[#ids + 1] = id
            end
            C.IDS[key] = ids
            for _, id in ipairs(ids) do
                known[#known + 1] = id
            end
        end
        return {
            class = "PRIEST",
            classID = M.CLASS_ID,
            specID = M.CLIENT_SPEC,
            level = 60,
            known = known,
            talents = P.talents,
            power = { type = MANA, token = "MANA", max = MAX },
            speed = { 3.0 },
            forms = P.forms,
            form = P.form,
        }
    end

    -- Level 60 against a level 60 mob in range, the pack's mana full and under the five-second rule. Neither side dies
    -- (hunter_world's reason: a kill ends the loop before the client sees it).
    local function hooks(W, us)
        us.health, us.healthMax = 1e9, 1e9
        if P.talents[T.dark_inspiration] then -- up at the pull (wowsims's log: from 0.01 s)
            W.applyAura(us, 1326168, 10, 1, 1)
        end
    end
    C.WORLD = {
        level = 60,
        canParry = false, -- priests never parry (wowsims's CanParry)
        weapons = { { 40, 70, 3.0 } },
        ranged = P.ranged,
        max = MAX,
        fsr = { [MANA] = P.fsr },
        power = MAX,
        mobHealth = 1e9,
        distance = 20, -- wowsims's distanceFromTarget: no melee swings of ours
        script = hooks,
        stats = P.stats,
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
        local p = {
            spell = VS.KnownID(a.id),
            ids = ids,
            cost = costOf(key, ids, H, inBelief(H, X)),
            pt = MANA,
            cooldown = tonumber(a.cooldown) or S.action[key].cooldown or 0,
            gcd = GCD[a.gcd or "spell"],
            offGcd = a.gcd == "off",
            cast = castOf(key, ids, H),
            refund = world.refundOf(H.Hekili.Class, key),
            outcomes = m.outcomes,
            shift = m.shift,
        }
        p.aura = m.aura and m.aura(p.spell)
        if m.channel then
            p.channel = m.channel(H, P)
        end
        p.requires = m.requires and function(W, e)
            return m.requires(W, e, X)
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

M.Shadow = content("Shadow")
M.Smite = content("Smite")

return M
