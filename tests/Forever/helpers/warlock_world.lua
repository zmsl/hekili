-- tests/Forever/helpers/warlock_world.lua (class-completion plan, "The per-pack gate"): the Warlock content of the
-- class-neutral headless loop, in mage_world.lua's shape, one content per wowsims.com pack (M.Affliction, M.Demonology,
-- M.Destruction, M.SMRuin, M.ShadowBrand) on wowsims/forever's builds (aff_wrack, demo_fire_brand, destro, sm_ruin,
-- demo_shadow_brand): the character the instance logs in as (the build's talents), each ability's press in the world's
-- generic verbs, the client's usability answers. IDs, costs, cooldowns and aura durations come from the class file
-- (load_druid's recording load of Warlock.lua for the character, the booted oracle's Hekili.Class for the rest). The
-- world's own, restated from the DB2 and wowsims/forever (so the class file's belief is measured against them): the
-- casts (Bane's -0.1 s a rank on Shadow Bolt, Immolate and Incinerate, -0.4 s on Soul Fire; Improved Corruption's -0.4
-- s; Decimation's faster Soul Fire; Master Summoner's summons; Shadow Trance's instant Shadow Bolt), Cataclysm's and
-- Master Summoner's costs, the DoTs, Banes and Curses on the target (each on a landed hit; one Bane and one Curse: each
-- removes the others; their ticks), Amplify Curse spent by Bane of Agony and Curse of Weakness, Nightfall's Shadow
-- Trance (2% a rank on a Corruption tick and a Drain Life, Drain Soul or Wrack tick), Conflagrate on our Immolate
-- (consumed unless Shadow and Flame keeps it, 20% a rank), Demonic Brand's charges from Searing Pain, Improved Shadow
-- Bolt's Shadow Vulnerability on a Shadow Bolt crit, Life Tap's mana (its rank's points, the level gain and the build's
-- Spirit, x Improved Life Tap; Demonic Energies' share to the demon), mana under the five-second rule (the pools and
-- the regen the five builds' logs show), and the channels (Drain Life 5 s a tick a second, Drain Soul 15 s every 3 s,
-- Wrack 6 s a tick a second with its debuff, Rain of Fire 8 s every 2 s, Hellfire 15 s a tick a second). Central fix
-- 27's harness: the Soul Shards in the bags (`WORLD.bags`, wowsims's 32; the shard spells' `reagent`, Shadow and
-- Flame's refund), the demon (`WORLD.pet`: the build's demon out from the start, as wowsims; its mana and regen from
-- wowsims's logs; the summons and Demonic Sacrifice's `pet`, the demon's own Firebolt or Lash of Pain spending its
-- mana; Demonic Sacrifice's effects, the build's sacrificed demon's from the pull) and the Spirit Life Tap reads
-- (`WORLD.stats`). The harness has one pet of any kind: summoning a different demon refills it to the build demon's
-- pool. Damage amounts are UNMEASURED.
-- Not in the world: the demon's swings and the brand charges they spend, and Decimation (below 35% target health; the
-- mob never gets there).
-- Credit: wowsims/forever (MIT, https://github.com/wowsims/forever) as the reference for the mechanics; no code copied.
local ld = require("Forever.helpers.load_druid")
local world = require("Game.harness.world")

local M = {}

M.CLIENT_SPEC, M.CLASS_ID = 1490, 9 -- the client's Warlock pseudo-spec (assumed: the alphabetical 1483-1491 row)
local MANA = 0 -- Enum.PowerType
local BASE = 1373 -- base mana at 60 (wowsims's ExtraClassBaseStats): a percent-of-base cost's base
local GCD = { spell = 1.5, off = 0 }
-- The regen a second, outside the five-second rule and inside it (wowsims's logs at 60, the preraid gear: 4.428 and
-- 1.04 a 0.1 s tick): the spirit part (paused inside it) and the mp5 part. UNMEASURED in game.
local FSR = { 33.88, 10.4 }
local SPIRIT = 221 -- the builds' Spirit at 60 (wowsims's logs: Life Tap 774 = (424 + 221) x 1.2)
local SOUL_SHARD = 6265 -- the item (ItemSparse); wowsims's builds carry 32 (classOptions.soulShards)
-- The demons the builds summon: their mana and regen a second at 60 (wowsims's logs, the preraid gear: "Pet stats"
-- Mana, MP5 / 5), the spell each casts on its own (DB2: Firebolt 11763 115 mana, 2 s cast; Lash of Pain 11780 160
-- mana, 12 s category cooldown) as { cost, every }, and the Demonic Sacrifice effect each leaves (DB2 18789-18792; the
-- Incubus as the Succubus, the same Sayaad).
local DEMON = {
    imp = { max = 2180, regen = 17.04, spell = { 115, 2 }, sacrifice = 18789 },
    succubus = { max = 1871, regen = 5.68, spell = { 160, 12 }, sacrifice = 18791 },
    incubus = { sacrifice = 18791 },
    voidwalker = { sacrifice = 18792 },
    felhunter = { sacrifice = 18790 },
}
local SACRIFICES = { 18789, 18790, 18791, 18792 }

-- Each rank's mana cost (DB2), lowest rank first, the world's truth the class file's are measured against (a level's
-- highest known rank pays its own); a number less than 1 is a fraction of base mana.
local COST = {
    shadow_bolt = { 25, 40, 70, 110, 160, 210, 265, 315, 370, 380 },
    immolate = { 25, 45, 90, 155, 220, 295, 370, 380 },
    corruption = { 35, 55, 100, 160, 225, 290, 340 },
    bane_of_agony = { 25, 50, 90, 130, 170, 215 },
    bane_of_doom = 300,
    curse_of_the_elements = { 50, 100, 150, 200 },
    curse_of_recklessness = { 35, 60, 90, 115 },
    curse_of_weakness = { 20, 35, 70, 95, 130, 175 },
    siphon_life = { 150, 205, 285, 365 },
    drain_life = { 55, 85, 135, 185, 240, 300 },
    drain_soul = { 55, 125, 210, 290 },
    wrack = 200,
    rain_of_fire = { 295, 605, 885, 1185 },
    hellfire = { 645, 975, 1300 },
    death_coil = { 435, 525, 600 },
    conflagrate = { 100, 130, 165, 200, 230, 255 },
    shadowburn = { 105, 130, 190, 245, 305, 365 },
    searing_pain = { 45, 68, 91, 118, 141, 168 },
    incinerate = { 205, 265, 325 },
    soul_fire = { 305, 335 },
    life_tap = 0,
    amplify_curse = 0,
    summon_imp = 0.8,
    summon_voidwalker = 1,
    summon_succubus = 1,
    summon_incubus = 1,
    summon_felhunter = 1,
}
-- Cataclysm's scope (DB2 17778's mask) and its cut by rank (wowsims's curve).
local CATACLYSM = {
    shadow_bolt = true,
    immolate = true,
    rain_of_fire = true,
    soul_fire = true,
    hellfire = true,
    shadowburn = true,
    searing_pain = true,
    conflagrate = true,
    incinerate = true,
}
local CATACLYSM_CUT = { [0] = 0, 0.03, 0.06, 0.1 }
local SUMMON = { summon_imp = true, summon_voidwalker = true, summon_succubus = true, summon_incubus = true }
SUMMON.summon_felhunter = true
local SHARD = { shadowburn = true, soul_fire = true, summon_voidwalker = true, summon_succubus = true }
SHARD.summon_incubus, SHARD.summon_felhunter = true, true
local REAGENT = { SOUL_SHARD, 1 }

-- The cast times (DB2), top rank, unhasted, before the talents.
local CAST = { shadow_bolt = 3, immolate = 2, corruption = 2, searing_pain = 1.5, incinerate = 2.5, soul_fire = 6 }
local BANED = { shadow_bolt = 0.1, immolate = 0.1, incinerate = 0.1, soul_fire = 0.4 } -- Bane's cut a rank

-- UNMEASURED: the hits' amounts, a tick's.
local AMOUNT = {
    shadow_bolt = 800,
    immolate = 300,
    searing_pain = 350,
    incinerate = 700,
    soul_fire = 1200,
    conflagrate = 600,
    shadowburn = 600,
    death_coil = 500,
    tick = 150,
}

-- The DoTs, Banes and Curses: { duration, tick (nil: none), school, group }; one of each group on a target.
local DOT = {
    corruption = { 18, 3, 32 },
    immolate = { 15, 3, 4 },
    bane_of_agony = { 24, 2, 32, "bane" },
    bane_of_doom = { 60, 60, 32, "bane" },
    siphon_life = { 30, 3, 32 },
    curse_of_the_elements = { 300, nil, 32, "curse" },
    curse_of_recklessness = { 120, nil, 32, "curse" },
    curse_of_weakness = { 120, nil, 32, "curse" },
}
local GROUP = {
    bane = { "bane_of_agony", "bane_of_doom" },
    curse = { "curse_of_the_elements", "curse_of_recklessness", "curse_of_weakness" },
}
local AMPLIFIED = { bane_of_agony = true, curse_of_weakness = true } -- Amplify Curse's scope (DB2 18288 effect 0)

-- The talents the world reads, by their rank-1 spells (wowsims's tree).
local T = {
    bane = 17788,
    improved_corruption = 17810,
    cataclysm = 17778,
    master_summoner = 18709,
    decimation = 440870,
    improved_life_tap = 18182,
    nightfall = 18094,
    shadow_and_flame = 426316,
    demonic_brand = 1293695,
    demonic_energies = 1225214,
    demonic_pact = 425464,
    improved_shadow_bolt = 17793,
}

local W0
local function class()
    W0 = W0 or ld.load(nil, "src/Hekili_Warlock/Warlock.lua", "WARLOCK")
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

-- The trainer's spells every pack's character knows at 60, and each build's talent spells.
local BASELINE = {
    "shadow_bolt",
    "immolate",
    "corruption",
    "bane_of_agony",
    "bane_of_doom",
    "curse_of_the_elements",
    "curse_of_recklessness",
    "curse_of_weakness",
    "drain_life",
    "drain_soul",
    "death_coil",
    "searing_pain",
    "soul_fire",
    "life_tap",
    "rain_of_fire",
    "hellfire",
    "summon_imp",
    "summon_voidwalker",
    "summon_succubus",
    "summon_incubus",
    "summon_felhunter",
}

-- The packs' worlds: `pack` the wowsims.com pack it runs, `spec` its spec id, `kit` the talent
-- abilities the build adds to BASELINE, `talents` the build's ({ [rank-1 spell] = rank }, its talentsString through
-- wowsims's tree), `max` the pool (the build's log), `demon` the build's summon (classOptions.summon: the pet's mana),
-- `petMax` the demon's pool where the build's talents raise it (the log's "Pet stats"), `sacrificed` its sacrificed
-- demon (classOptions.sacrificedDemon), `uptime` the debuffs reported.
local PACKS = {
    -- aff_wrack.build.json 25300020135201351--0550005003 (33/0/18)
    Affliction = {
        pack = "Affliction (wowsims.com)",
        spec = 100091,
        max = 5353,
        demon = "succubus",
        kit = { "siphon_life", "wrack", "amplify_curse" },
        talents = {
            [18182] = 2, -- Improved Life Tap
            [18174] = 5, -- Suppression
            [17810] = 3, -- Improved Corruption
            [18827] = 2, -- Improved Bane of Agony
            [18288] = 1, -- Amplify Curse
            [427712] = 3, -- Pandemic
            [1310949] = 5, -- Malevolence
            [18094] = 2, -- Nightfall
            [18265] = 1, -- Siphon Life
            [17804] = 3, -- Soul Siphon
            [18271] = 5, -- Shadow Mastery
            [1316697] = 1, -- Wrack
            [17793] = 5, -- Improved Shadow Bolt
            [17788] = 5, -- Bane
            [17959] = 5, -- Ruin
            [17927] = 3, -- Agonizing Flames
        },
        uptime = { "corruption", "bane_of_agony" },
    },
    -- demo_fire_brand.build.json 011-0305003201220301351-0050055003 (2/31/18)
    Demonology = {
        pack = "Demonology (wowsims.com)",
        spec = 100092,
        max = 6156,
        demon = "imp",
        sacrificed = "succubus",
        kit = { "demonic_sacrifice" },
        talents = {
            [18174] = 1, -- Suppression
            [17810] = 1, -- Improved Corruption
            [18694] = 3, -- Improved Imp
            [18769] = 5, -- Unholy Power
            [18731] = 3, -- Fel Vitality
            [1225214] = 2, -- Demonic Energies
            [18788] = 1, -- Demonic Sacrifice
            [18709] = 2, -- Master Summoner
            [440870] = 2, -- Decimation
            [1293695] = 3, -- Demonic Brand
            [19028] = 1, -- Soul Link
            [412732] = 3, -- Demonic Knowledge
            [23785] = 5, -- Master Demonologist
            [425464] = 1, -- Demonic Pact
            [17788] = 5, -- Bane
            [18119] = 5, -- Aftermath
            [17959] = 5, -- Ruin
            [17927] = 3, -- Agonizing Flames
        },
        uptime = { "corruption", "immolate" },
    },
    -- destro.build.json 2530000013-0004-0050355103101351 (14/4/33)
    Destruction = {
        pack = "Destruction (wowsims.com)",
        spec = 100093,
        max = 5353,
        demon = "succubus",
        kit = { "conflagrate", "shadowburn", "incinerate", "amplify_curse" },
        talents = {
            [18182] = 2, -- Improved Life Tap
            [18174] = 5, -- Suppression
            [17810] = 3, -- Improved Corruption
            [18288] = 1, -- Amplify Curse
            [427712] = 3, -- Pandemic
            [18769] = 4, -- Unholy Power
            [17788] = 5, -- Bane
            [17778] = 3, -- Cataclysm
            [18119] = 5, -- Aftermath
            [17959] = 5, -- Ruin
            [17877] = 1, -- Shadowburn
            [17927] = 3, -- Agonizing Flames
            [1293817] = 1, -- Conflagrate
            [1225228] = 1, -- Bane of Havoc
            [412751] = 3, -- Fire and Brimstone
            [426316] = 5, -- Shadow and Flame
            [412758] = 1, -- Incinerate
        },
        uptime = { "immolate", "corruption" },
    },
    -- sm_ruin.build.json 2540002013520105--0550305003 (30/0/21): Affliction's second pack
    SMRuin = {
        pack = "SM Ruin (wowsims.com)",
        spec = 100091,
        max = 5353,
        demon = "succubus",
        kit = { "siphon_life", "amplify_curse" },
        talents = {
            [18182] = 2, -- Improved Life Tap
            [18174] = 5, -- Suppression
            [17810] = 4, -- Improved Corruption
            [18827] = 2, -- Improved Bane of Agony
            [18288] = 1, -- Amplify Curse
            [427712] = 3, -- Pandemic
            [1310949] = 5, -- Malevolence
            [18094] = 2, -- Nightfall
            [18265] = 1, -- Siphon Life
            [18271] = 5, -- Shadow Mastery
            [17793] = 5, -- Improved Shadow Bolt
            [17788] = 5, -- Bane
            [17778] = 3, -- Cataclysm
            [17959] = 5, -- Ruin
            [17927] = 3, -- Agonizing Flames
        },
        uptime = { "corruption", "bane_of_doom" },
    },
    -- demo_shadow_brand.build.json 011-0005003231220301351-0550005003 (2/31/18): Demonology's second pack; the
    -- Succubus out with Fel Vitality's pool (wowsims's log: 2151.65 mana), the Imp sacrificed (Burning Shadow)
    ShadowBrand = {
        pack = "Shadow Brand (wowsims.com)",
        spec = 100092,
        max = 6156,
        demon = "succubus",
        petMax = 2151.65,
        sacrificed = "imp",
        kit = { "demonic_sacrifice" },
        talents = {
            [18174] = 1, -- Suppression
            [17810] = 1, -- Improved Corruption
            [18769] = 5, -- Unholy Power
            [18731] = 3, -- Fel Vitality
            [1225214] = 2, -- Demonic Energies
            [18754] = 3, -- Improved Sayaad
            [18788] = 1, -- Demonic Sacrifice
            [18709] = 2, -- Master Summoner
            [440870] = 2, -- Decimation
            [1293695] = 3, -- Demonic Brand
            [19028] = 1, -- Soul Link
            [412732] = 3, -- Demonic Knowledge
            [23785] = 5, -- Master Demonologist
            [425464] = 1, -- Demonic Pact
            [17793] = 5, -- Improved Shadow Bolt
            [17788] = 5, -- Bane
            [17959] = 5, -- Ruin
            [17927] = 3, -- Agonizing Flames
        },
        uptime = { "corruption", "immolate" },
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
-- resolve). Each returns up(key).
local function onEntity(e, X)
    return function(key)
        return e.auras[X.aura[key].id] ~= nil
    end
end
local function inBelief(H, X)
    local VS, now = H.ns.VirtualState, H.ctl.now
    return function(key)
        return VS.Aura("player", X.aura[key].id, now) ~= nil
    end
end

local function aura(W, X, dst, key, n, duration)
    local a = X.aura[key]
    W.applyAura(dst, a.id, duration or a.duration, n or 1, a.max_stack)
end
local function drop(W, e, X, key) -- aura `key` off `e`, if up (its ticks too)
    local id = X.aura[key].id
    if e.dots then
        e.dots[key] = nil
    end
    if e.auras[id] then
        e.auras[id] = nil
        W.emit({ kind = "aura", dst = e, aura = id, stacks = 0, expires = 0, duration = 0 })
    end
end

-- The highest rank of `ids` instance `H`'s character knows (the last when none).
local function rankOf(H, ids, n)
    for i = #ids, 1, -1 do
        if H.ctl.known[ids[i]] then
            return i
        end
    end
    return n
end

-- The cost of `key` (`ids`: its ranks, lowest first): its rank's, less Cataclysm and Master Summoner; a fraction of
-- base floored (the kit's percent-of-base costs).
local function costOf(key, ids, H)
    local c = COST[key] or 0
    if type(c) == "table" then
        c = c[rankOf(H, ids, #c)]
    end
    if CATACLYSM[key] then
        c = c * (1 - CATACLYSM_CUT[math.min(talentRank(H, T.cataclysm), 3)])
    elseif SUMMON[key] then
        c = math.floor(c * (1 - 0.2 * talentRank(H, T.master_summoner)) * BASE)
    end
    return c
end

-- The cast time of `key`: Shadow Trance's instant Shadow Bolt, the talents' cuts, Decimation's faster Soul Fire.
local function castOf(key, H, up)
    if SUMMON[key] then
        return 10 - 2 * talentRank(H, T.master_summoner)
    end
    local c = CAST[key]
    if not c or (key == "shadow_bolt" and up("shadow_trance")) then
        return 0
    end
    c = c - (BANED[key] or 0) * talentRank(H, T.bane)
    if key == "corruption" then
        c = math.max(0, c - 0.4 * talentRank(H, T.improved_corruption))
    elseif key == "soul_fire" and up("decimation") then
        c = c * (1 - 0.2 * talentRank(H, T.decimation))
    end
    return c
end

-- Nightfall's roll on a tick of Corruption, Drain Life, Drain Soul or Wrack (wowsims talents_affliction.go).
local function nightfall(W, e, X, H)
    local r = talentRank(H, T.nightfall)
    if r > 0 and W.rng.chance(0.02 * r) then
        aura(W, X, e, "shadow_trance")
    end
end

-- A tick of ours on `dst` (school `school`), and `then(W)` after it.
local function tick(W, e, dst, school, after)
    if not dst.dead then
        W.emit({ kind = "tick", src = e, dst = dst, act = "WOUND", flag = "", amount = AMOUNT.tick, school = school })
        if after then
            after(W)
        end
    end
end

-- A DoT's, Bane's or Curse's landing: the others of its group off the target, its ticks (each while this application
-- is the target's: a refresh or a removal ends them; the last lands at the expiry, as wowsims's), its aura on.
local function dot(W, e, X, H, key)
    local d, v = DOT[key], e.target
    for _, other in ipairs(d[4] and GROUP[d[4]] or {}) do
        if other ~= key then
            drop(W, v, X, other)
        end
    end
    v.dots = v.dots or {}
    local live = {}
    v.dots[key] = live
    for n = 1, d[2] and math.floor(d[1] / d[2] + 1e-9) or 0 do
        W.at(W.t + n * d[2], function()
            if v.dots[key] == live then
                tick(W, e, v, d[3], key == "corruption" and function()
                    nightfall(W, e, X, H)
                end)
            end
        end)
    end
    aura(W, X, v, key, 1, d[1])
end

-- A spell's hit (`school`; `amount` nil: no damage) and, on a landed one, `extra(W, e, X, H, p)`.
local function spell(key, school, extra)
    return {
        outcomes = "spell",
        effect = function(W, e, p, X, H)
            if AMPLIFIED[key] then
                drop(W, e, X, "amplify_curse") -- spent at the cast (wowsims), a miss too
            end
            local hit = W.hit(e, e.target, AMOUNT[key], school)
            if hit.act == "WOUND" and extra then
                extra(W, e, X, H, p)
            end
        end,
    }
end
local function lands(key)
    return spell(key, DOT[key][3], function(W, e, X, H)
        dot(W, e, X, H, key)
    end)
end

-- A channel of `length` s, a tick each `every` s on the target (`school`), Nightfall rolled on each (`procs`).
local function channel(key, length, every, school, procs, start)
    return {
        outcomes = "spell",
        effect = start,
        channel = function(H)
            local X = classData(H)
            return {
                length = length,
                tick = every,
                effect = function(W, e)
                    tick(W, e, e.target, school, procs and function()
                        nightfall(W, e, X, H)
                    end)
                end,
            }
        end,
    }
end

-- Whether `key` needs a Soul Shard on `e` now: a shard spell, Soul Fire not under Decimation (A_NO_REAGENT_USE).
local function needsShard(key, up)
    return SHARD[key] and not (key == "soul_fire" and up("decimation"))
end

-- A Demonic Sacrifice effect's aura on `e` (DB2's duration, 2 h; wowsims: until a summon ends it), or off.
local function sacrificeOn(W, e, id)
    W.applyAura(e, id, 7200, 1, 1)
end
local function sacrificeOff(W, e, id)
    if e.auras[id] then
        e.auras[id] = nil
        W.emit({ kind = "aura", dst = e, aura = id, stacks = 0, expires = 0, duration = 0 })
    end
end

-- A summon's (the press's `pet = "summon"` brings it full): the demon `key` out, Demonic Sacrifice's effects ended
-- (any without Demonic Pact, the summoned demon's own with it: wowsims summon.go).
local function summon(key)
    return {
        effect = function(W, e, _, _, H)
            e.demon = key
            local pact = talentRank(H, T.demonic_pact) > 0
            for _, id in ipairs(SACRIFICES) do
                if not pact or id == DEMON[key].sacrifice then
                    sacrificeOff(W, e, id)
                end
            end
        end,
    }
end

-- The demon's own spell while it is out (wowsims pets.go: cast once its mana covers the cost, else wait):
-- shortcut: a retry each `every` s, not at the regen's exact refill; upgrade if a gate reads the pet's mana closely.
local function demonCasts(W, e)
    local function step()
        local d = e.pet.up and e.demon and DEMON[e.demon].spell
        if d and e.pet.power >= d[1] then
            W.petGain(e, -d[1])
        end
        W.at(W.t + (d and d[2] or 1), step)
    end
    W.at(W.t, step)
end

-- Each recommendable ability: `effect(W, e, p, X, H)` (a channel's at its start), `requires(W, e, X, H)`,
-- `channel(H)` (a channel's { length, tick, effect }). A key missing here fails the loop.
M.MAP = {
    -- Improved Shadow Bolt: a crit's Shadow Vulnerability on the target (DB2 17793 / 17794, 12 s)
    shadow_bolt = spell("shadow_bolt", 32, function(W, e, X, H)
        if e.lastHit.flag == "CRITICAL" and talentRank(H, T.improved_shadow_bolt) > 0 then
            aura(W, X, e.target, "shadow_vulnerability")
        end
    end),
    immolate = spell("immolate", 4, function(W, e, X, H)
        dot(W, e, X, H, "immolate")
    end),
    corruption = lands("corruption"),
    bane_of_agony = lands("bane_of_agony"),
    bane_of_doom = lands("bane_of_doom"),
    curse_of_the_elements = lands("curse_of_the_elements"),
    curse_of_recklessness = lands("curse_of_recklessness"),
    curse_of_weakness = lands("curse_of_weakness"),
    siphon_life = lands("siphon_life"),
    drain_life = channel("drain_life", 5, 1, 32, true),
    drain_soul = channel("drain_soul", 15, 3, 32, true),
    wrack = channel("wrack", 6, 1, 32, true, function(W, e, _, X)
        aura(W, X, e.target, "wrack") -- the channel's debuff (wowsims's log: on the target for the 6 s)
    end),
    rain_of_fire = channel("rain_of_fire", 8, 2, 4),
    hellfire = channel("hellfire", 15, 1, 4),
    death_coil = spell("death_coil", 32),
    searing_pain = spell("searing_pain", 4, function(W, e, X, H)
        local r = talentRank(H, T.demonic_brand)
        if r > 0 then
            e.target.auras[X.aura.demonic_brand.id] = nil -- the charges set to the rank's, refreshed
            aura(W, X, e.target, "demonic_brand", 2 * r)
        end
    end),
    incinerate = spell("incinerate", 4),
    conflagrate = {
        outcomes = "spell",
        requires = function(_, e, X)
            return e.target.auras[X.aura.immolate.id] ~= nil, "no immolate"
        end,
        effect = function(W, e, _, X, H)
            local hit = W.hit(e, e.target, AMOUNT.conflagrate, 4)
            if hit.act == "WOUND" and not W.rng.chance(0.2 * talentRank(H, T.shadow_and_flame)) then
                drop(W, e.target, X, "immolate")
            end
        end,
    },
    shadowburn = {
        outcomes = "spell",
        effect = function(W, e, _, _, H)
            local hit = W.hit(e, e.target, AMOUNT.shadowburn, 32)
            -- Shadow and Flame: a landed Shadowburn refunds its shard, 20% a rank (wowsims's curve)
            if hit.act == "WOUND" and W.rng.chance(0.2 * talentRank(H, T.shadow_and_flame)) then
                W.item(e, SOUL_SHARD, 1)
            end
        end,
    },
    soul_fire = {
        outcomes = "spell",
        effect = function(W, e)
            W.hit(e, e.target, AMOUNT.soul_fire, 4)
        end,
    },
    life_tap = {
        effect = function(W, e, _, _, H)
            -- rank 6's 420 points + 4 (levels 56 to 60) + Spirit, x Improved Life Tap's 10% a rank
            local amount = (424 + SPIRIT) * (1 + 0.1 * talentRank(H, T.improved_life_tap))
            W.emit({ kind = "gain", src = e, pt = MANA, rage = amount })
            -- Demonic Energies: the demon out gains 50% of it a rank (wowsims's curve; its log: 645 to the Imp at 2/2)
            W.petGain(e, amount * 0.5 * talentRank(H, T.demonic_energies))
        end,
    },
    amplify_curse = {
        effect = function(W, e, _, X)
            aura(W, X, e, "amplify_curse")
        end,
    },
    -- the Orc racial the builds' Boosts group casts (Hekili_Shared/Races/Orc.lua): its buff on us
    blood_fury = {
        effect = function(W, e, _, X)
            aura(W, X, e, "blood_fury")
        end,
    },
    summon_imp = summon("imp"),
    summon_voidwalker = summon("voidwalker"),
    summon_succubus = summon("succubus"),
    summon_incubus = summon("incubus"),
    summon_felhunter = summon("felhunter"),
    -- the demon out dismissed (the press's `pet`), its effect up, any other ended (wowsims talents_demonology.go)
    demonic_sacrifice = {
        requires = function(_, e)
            return e.pet.up and e.demon ~= nil, "no demon"
        end,
        effect = function(W, e)
            for _, id in ipairs(SACRIFICES) do
                sacrificeOff(W, e, id)
            end
            sacrificeOn(W, e, DEMON[e.demon].sacrifice)
            e.demon = nil
        end,
    },
}
local PET = { summon_imp = "summon", summon_voidwalker = "summon", summon_succubus = "summon" }
PET.summon_incubus, PET.summon_felhunter, PET.demonic_sacrifice = "summon", "summon", "dismiss"

local function content(name)
    local P = PACKS[name]
    local C = { PACK = P.pack, SPEC = P.spec, IDS = {} }
    local MAX = P.max

    function C.character()
        local w = class()
        local known = {}
        local keys = {}
        for _, key in ipairs(BASELINE) do
            keys[#keys + 1] = key
        end
        for _, key in ipairs(P.kit) do
            keys[#keys + 1] = key
        end
        for _, key in ipairs(keys) do
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
            class = "WARLOCK",
            classID = M.CLASS_ID,
            specID = M.CLIENT_SPEC,
            level = 60,
            known = known,
            talents = P.talents,
            power = { type = MANA, token = "MANA", max = MAX },
            speed = { 2.0 },
        }
    end

    -- Level 60 against a level 60 mob in range, the pack's mana full and under the five-second rule. Neither side dies
    -- (hunter_world's reason: a kill ends the loop before the client sees it).
    -- The build's sacrificed demon's effect from the pull (wowsims sacrifices it before the fight).
    local function hooks(W, us)
        us.health, us.healthMax = 1e9, 1e9
        us.demon = P.demon -- out from the start (wowsims: the summon option's demon, EnabledOnStart)
        if P.sacrificed then
            sacrificeOn(W, us, DEMON[P.sacrificed].sacrifice)
        end
        demonCasts(W, us)
    end
    local D = DEMON[P.demon]
    C.WORLD = {
        level = 60,
        weapons = { { 40, 70, 2.0 } },
        max = MAX,
        fsr = { [MANA] = FSR },
        power = MAX,
        mobHealth = 1e9,
        distance = 25, -- a caster's range: no melee swings of ours
        script = hooks,
        bags = { [SOUL_SHARD] = 32 },
        -- the build's demon, out from the start with its mana full (wowsims)
        pet = { pt = MANA, max = P.petMax or D.max, power = P.petMax or D.max, regen = D.regen, tick = 2, up = true },
        stats = { [5] = SPIRIT }, -- UnitStat(5)'s Spirit, Life Tap's
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
        local up = inBelief(H, X)
        local p = {
            spell = VS.KnownID(a.id),
            ids = ids,
            cost = costOf(key, ids, H),
            pt = MANA,
            cooldown = key == "soul_fire" and 60 * (1 - 0.45 * talentRank(H, T.decimation))
                or tonumber(a.cooldown)
                or S.action[key].cooldown
                or 0,
            gcd = GCD[a.gcd or "spell"],
            offGcd = a.gcd == "off",
            cast = castOf(key, H, up),
            refund = world.refundOf(H.Hekili.Class, key),
            outcomes = m.outcomes,
            reagent = needsShard(key, up) and REAGENT or nil,
            pet = PET[key],
        }
        if m.channel then
            p.channel = m.channel(H)
            p.cast = nil
        end
        p.requires = function(W, e)
            if m.requires then
                return m.requires(W, e, X, H)
            end
            return true
        end
        p.effect = function(W, e)
            if key == "shadow_bolt" and p.cast == 0 then
                drop(W, e, X, "shadow_trance") -- spent by the instant cast
            end
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
                    if m.requires and not m.requires(W, e, X, H) then
                        return false, false
                    end
                    if needsShard(key, onEntity(e, X)) and W.items(e, SOUL_SHARD) < 1 then
                        return false, false
                    end
                    local cost = costOf(key, ids, H)
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

M.Affliction = content("Affliction")
M.Demonology = content("Demonology")
M.Destruction = content("Destruction")
M.SMRuin = content("SMRuin")
M.ShadowBrand = content("ShadowBrand")

return M
