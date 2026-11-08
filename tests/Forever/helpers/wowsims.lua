-- tests/Forever/helpers/wowsims.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 3):
-- a class world's content (tests/Forever/helpers/<class>_world.lua) as a wowsims replay's and as a leveling
-- bracket's, and the two gates. `content`: the build's talents from the log header (cut to a level's points, the
-- dominant tree first), ranks above the level unknown (learn_<class>.lua, the DB2's), the abilities the world's kit
-- lacks, requirement overrides; `gate`: the replay gate (decision-point on-GCD agreement >= a floor, the engine's
-- health); `live`: the leveling gate (the pack driving the loop's own world never idles `n` GCDs while a known on-GCD
-- ability is usable, no error). Data: wowsims/forever (MIT, https://github.com/wowsims/forever).
local assert = require("luassert")
local ab = require("Game.harness.ab")
local util = require("luassert.util")
local loop = require("Game.harness.loop")
local replay = require("Game.harness.replay")
local pack_gate = require("Forever.helpers.pack_gate")
local timing = require("Game.harness.timing")

local M = {}

M.DIR = "tests/Forever/wowsims/"

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

--- The checked-in log of spec `spec`.
function M.log(spec)
    return slurp(M.DIR .. spec .. ".log")
end

--- The log header of spec `spec` (replay.parse's).
function M.header(spec)
    return replay.parse(M.log(spec)).header
end

-- wowsims's Race enum names whose client token (UnitRace's second return) is not the name without "Race".
M.RACE = { RaceUndead = "Scourge" }

--- The client race token of spec `spec`'s character (its checked-in request's `race`, e.g. "RaceOrc" -> "Orc").
function M.race(spec)
    local req = require("dkjson").decode(slurp(M.DIR .. spec .. ".json"))
    local race = req.raid.parties[1].players[1].race
    return M.RACE[race] or (race:gsub("^Race", ""))
end

--- The creature type of spec `spec`'s target (its checked-in request's first target's `mobType`, e.g.
--- "MobTypeUndead" -> "undead": `target.creature_type`'s key; "MobTypeUnknown" -> "unknown").
function M.creatureType(spec)
    local req = require("dkjson").decode(slurp(M.DIR .. spec .. ".json"))
    local t = req.encounter and req.encounter.targets and req.encounter.targets[1]
    return t and t.mobType and t.mobType:gsub("^MobType", ""):lower() or nil
end

--- Our yards from the target at the start in spec `spec`'s checked-in request (`distanceFromTarget`; wowsims's 0 when
--- unset).
function M.distance(spec)
    local req = require("dkjson").decode(slurp(M.DIR .. spec .. ".json"))
    return req.raid.parties[1].players[1].distanceFromTarget or 0
end

--- The learn levels of class `token` ({ [spellID] = level }).
function M.learn(token)
    return dofile(M.DIR .. "learn_" .. token:lower() .. ".lua")
end

local sets = {}
local function abilities(token) -- the class's ability set (every race's racials: engine.abilitySet), once a class
    if not sets[token] then
        sets[token] = require("Forever.helpers.engine").abilitySet(token).abilities
    end
    return sets[token]
end
local function racials(token, race) -- the keys of race `race`'s abilities for class `token`, sorted
    local out = {}
    for key, r in pairs(require("Forever.helpers.engine").abilitySet(token, race).racial) do
        if r == race then
            out[#out + 1] = key
        end
    end
    table.sort(out)
    return out
end
local function rankIDs(token, key)
    local a = assert(abilities(token)[key], "no ability " .. key)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
        out[#out + 1] = id
    end
    return out
end

-- wowsims's ItemSlot order (proto/common.proto: Head 0 ... Ranged 16) as client inventory slots; 0 not equipped here:
-- the trinkets and weapons (the world owns weapon facts; no trinket effect is modelled yet)
M.SLOT = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 0, 0, 0, 0, 18 }

--- The request's gear of spec `spec` as headless `items` ({ [slot] = { itemID } }: no name, an uncached item), minus
--- the pieces of each set in `skips` ({ [set key] = { piece IDs } }; default the recipe's `oracleSkips`, R35: sets the
--- oracle's pin silently skipped, so the replay world matches its log; loops and live worlds never read it).
function M.gear(spec, skips)
    if skips == nil then
        local ok, recipe = pcall(dofile, "tools/wowsims/specs/" .. spec .. ".lua")
        skips = ok and recipe.oracleSkips or {}
    end
    local drop = {}
    for _, ids in pairs(skips) do
        for _, id in ipairs(ids) do
            drop[id] = true
        end
    end
    local req = require("dkjson").decode(slurp(M.DIR .. spec .. ".json"))
    local out = {}
    for i, it in ipairs(req.raid.parties[1].players[1].equipment.items) do
        local slot = M.SLOT[i]
        if slot and slot > 0 and type(it.id) == "number" and not drop[it.id] then
            out[slot] = { it.id }
        end
    end
    return out
end

--- Content `base` (a class world's: character, usable, resolve, uptime, gain, WORLD, OBSERVE) as pack `o.pack`'s at
--- `o.level` [60]. `o.talents` ({ { id, rank, tree } }: the build's; default the world's) are cut to the level's points
--- (one a level from 10), the dominant tree first, each talent's spell known; `o.learn` ({ [spellID] = level }) drops
--- ranks above the level (an ID it lacks counts as level 1); `o.kit` adds abilities the world's kit lacks (usable on
--- cost); `o.requires` ({ [key] = fn(W, e) -> ok, why }) replaces an ability's requirement in the usability answers
--- (it then owns the stance check too); `o.race` (a race token: `M.race(spec)`) boots the character as that race, its
--- racials known from their learn level (like `o.kit`'s). The world's mob is the character's level. `o.gear` (`M.gear`'s: { [slot] = { itemID } }) is worn
--- besides the world's own items (its weapons win a slot).
function M.content(base, o)
    local level = o.level or 60
    if o.race then
        local kit = {}
        for _, key in ipairs(o.kit or {}) do
            kit[#kit + 1] = key
        end
        for _, key in ipairs(racials(base.character().class, o.race)) do
            kit[#kit + 1] = key
        end
        o = setmetatable({ kit = kit }, { __index = o })
    end
    local C = setmetatable({ PACK = o.pack or base.PACK }, { __index = base })
    C.WORLD = setmetatable({ level = level }, { __index = base.WORLD })
    local learn = o.learn or {}
    local function learned(id)
        return type(id) ~= "number" or (learn[id] or 1) <= level
    end
    function C.character()
        local c = {}
        for k, v in pairs(base.character()) do
            c[k] = v
        end
        c.level, c.race = level, o.race or c.race
        if o.gear then
            local items = {}
            for slot, item in pairs(c.items or {}) do
                items[slot] = item
            end
            for slot, item in pairs(o.gear) do
                items[slot] = items[slot] or item -- the world's own (its weapons) first
            end
            c.items = items
        end
        local known = {}
        for _, id in ipairs(c.known) do
            if learned(id) then
                known[#known + 1] = id
            end
        end
        for _, key in ipairs(o.kit or {}) do
            for _, id in ipairs(rankIDs(c.class, key)) do
                if learned(id) then
                    known[#known + 1] = id
                end
            end
        end
        if o.talents then
            local points, per = math.max(0, level - 9), {}
            for _, t in ipairs(o.talents) do
                per[t[3]] = (per[t[3]] or 0) + t[2]
            end
            local dom, most = 1, -1
            for tree, n in pairs(per) do
                if n > most or (n == most and tree < dom) then
                    dom, most = tree, n
                end
            end
            local order = {}
            for _, t in ipairs(o.talents) do
                if t[3] == dom then
                    order[#order + 1] = t
                end
            end
            for _, t in ipairs(o.talents) do
                if t[3] ~= dom then
                    order[#order + 1] = t
                end
            end
            local talents = {}
            for _, t in ipairs(order) do
                local r = math.min(t[2], points)
                if r <= 0 then
                    break
                end
                talents[t[1]], points = r, points - r
                known[#known + 1] = t[1]
            end
            c.talents = talents
        end
        c.known = known
        return c
    end
    function C.usable(H)
        local token = base.character().class
        local over, out, seen = {}, {}, {}
        for key in pairs(o.requires or {}) do
            for _, id in ipairs(rankIDs(token, key)) do
                over[id] = key
            end
        end
        for _, row in ipairs(base.usable(H)) do
            if not over[row[1]] then
                out[#out + 1], seen[row[1]] = row, true
            end
        end
        local function answer(key, req)
            local cost = H.Hekili.State.action[key].cost or 0
            return function(W, e, power)
                local ok = not req or req(W, e)
                return ok and power >= cost, ok and power < cost
            end
        end
        for key, req in pairs(o.requires or {}) do
            for _, id in ipairs(rankIDs(token, key)) do
                out[#out + 1] = { id, answer(key, req) }
            end
        end
        for _, key in ipairs(o.kit or {}) do
            if not (o.requires and o.requires[key]) then
                for _, id in ipairs(rankIDs(token, key)) do
                    if not seen[id] then
                        out[#out + 1] = { id, answer(key) }
                    end
                end
            end
        end
        table.sort(out, function(x, y)
            return x[1] < y[1]
        end)
        return out
    end
    return C
end

--- Content `C` as the replay character of spec `spec`'s log: its power's maximum the log's (replay.pools), the pool
--- the world and the client's UnitPowerMax read too, so percent costs are priced on it at boot.
function M.logged(C, spec)
    local _, maxOf = replay.pools(replay.parse(M.log(spec)).ev)
    return setmetatable({
        character = function()
            local c = C.character()
            local p, m = c.power, maxOf[c.power and c.power.type]
            if m then
                c.power = { type = p.type, token = p.token, value = p.value, max = m }
            end
            return c
        end,
    }, { __index = C })
end

--- replay.new's options for content `C` on spec `spec` (the gate's: the character's forms, the request's creature
--- type and distance, C.SHARED), over knobs `o`.
function M.replayOptions(C, spec, o)
    return setmetatable({
        forms = C.character().forms,
        creatureType = M.creatureType(spec),
        distance = M.distance(spec),
        shared = C.SHARED,
        reacted = M.reacted(spec),
    }, { __index = o or {} })
end

--- replay.new's `reacted` for spec `spec`: { [auraID] = the request's reaction time in s } for every auraIsActive
--- read of our own aura with includeReactionTime in the request's APL.
function M.reacted(spec)
    local req = require("dkjson").decode(slurp(M.DIR .. spec .. ".json"))
    local player = req.raid.parties[1].players[1]
    local out, s = {}, (player.reactionTimeMs or 0) / 1000
    local function walk(t)
        local v = t.auraIsActive
        if type(v) == "table" and v.includeReactionTime and not v.sourceUnit and v.auraId and v.auraId.spellId then
            out[v.auraId.spellId] = s
        end
        for _, x in pairs(t) do
            if type(x) == "table" then
                walk(x)
            end
        end
    end
    walk(player.rotation or {})
    return out
end

-- The request's first-player knob `name` (milliseconds, at any depth: reactionTimeMs, a class option's queueDelay) in
-- seconds; 0 when unset (wowsims's proto default).
local function knob(spec, name)
    local function find(t)
        for k, v in pairs(t) do
            if k == name then
                return v
            elseif type(v) == "table" then
                local x = find(v)
                if x then
                    return x
                end
            end
        end
    end
    local req = require("dkjson").decode(slurp(M.DIR .. spec .. ".json"))
    return (find(req.raid.parties[1].players[1]) or 0) / 1000
end

M.FIXTURES = "tests/Forever/fixtures/"

-- The ready-time floors per spec (docs/superpowers/specs/2026-10-16-headless-recommendation-loop.md §12): { median |b|
-- of the real (outside-tolerance) on-GCD decisions, rounded up to 0.01 s; their count }, from the first clean run
-- (forever-readytime, 2026-10-21), only ever lowered, except that re-pins re-set to the measurement (R6). Balance's, Feral's, Warrior Protection's and Combat's medians rose
-- in review round 1 from the metric alone (the cost class from the crossing; the on-GCD-only walk); behaviour unchanged.
-- Oracle refresh (sim pin e2842f0a78 + documented patches, 2026-11-02, R12): Feral, Paladin Protection and
-- Retribution, Assassination, Combat, Enhancement, Demonology, Destruction, Fury and Warrior Protection re-set to their
-- measured { median, real } (4bd02bde0 reverted; with 68dee8fa5 reverted too every line is the same), so the move is
-- the oracle's. Was: Feral { 0.43, 4 }, Paladin Protection { 0.54, 12 },
-- Retribution { 0, 0 }, Assassination { 0.16, 15 }, Combat { 0.22, 11 }, Enhancement { 0.96, 3 }, Demonology
-- { 0.20, 1 }, Destruction { 0.40, 17 }, Fury { 0.44, 35 }, Warrior Protection { 0.50, 5 }.
M.READY = {
    -- 17 -> 22 re-pin e2842f0a78: the new log's 79 decisions (42 Wraths, was 28 of 55); 17 of the 22 Wrath, cost class
    -- (the mana floor); median 0.260, the same after owner R20a (Innervate low-mana only), so 0.71 -> 0.26 (R6);
    -- kept on task #3 (gear-aware): median 0.260, 22 real (the three moved Wrath rows, the wrath -> insect_swarm
    -- misses, were never, not real)
    druid_balance = { 0.26, 22 },
    -- 0.26 -> 0.43: 0.26 rested on the Innervate miscalibration that ran the mana belief ~31 high before the 107.74 s
    -- Shifting Power; with regen correct the floor (lo) reaches the cost ~0.4 s after the truth (gap BQ); owner ruling
    -- 2026-10-26
    -- { 0.25, 7 } -> { 0.50, 5 }: gap AS's reversed order (Rake dodged at 75.24 now undoes Rake): 76.24 timed, and
    -- the 91.74 / 95.24 late rows (0.22 / 0.25 s) fall inside the cost absorption; the five left have the larger median
    -- (controller ruling 2026-11-03 overnight, pending owner review)
    -- { 0.50, 5 } -> { 0.50, 9 } re-pin e2842f0a78 (adaptive list, 82 on-GCD decisions): median 0.500, 9 real (early 2,
    -- late 7); top shifting_power 4 (max 0.50: a not-ready flag's CD_PROBE push, shared), rake 2, rip 2 (energy is
    -- secret: the belief's lo under the truth at the cost)
    -- { 0.50, 9 } -> { 0.35, 10 } on the 0.7 floors run (integ/0.7 5deb101c4; R6): the never rows of the
    -- old log are gone (CN8's cooldown countdown, pin-2 export: not separated) but cost rows rake 25.14 and
    -- shifting_power 111.89 (0.47 / 0.45, the belief's lo under the truth) are now late; 10 real (early 2, late 8), median 0.350
    -- { 0.35, 10 } -> { 0.40, 10 } (CN8 I1, R6: a probe stands until the game says ready): decision 12, shifting_power
    -- at 11.75, the model's end short of the flag's, reads 0.500 late (0.350 while the probe counted down); real 10
    -- (early 2, late 8), median 0.400
    druid_feral = { 0.40, 10 },
    -- { 0.54, 41 } -> { 2.50, 10 } (lane 14, replay world fix): a GCD now ends at its cast's log time plus the GCD (a
    -- late line of its timestamp ended it after the next GCD's rise, clearing the client's flag), so the 11 early
    -- GCD-chain rows are in grain; the 10 left are the late ones, so the median rises by the metric alone
    -- { 2.50, 10 } -> { 1.76, 55 } (re-pin e5a9cd2a2d, floors step): 55 late GCD-chain rows (median 1.751): with no rage from hits
    -- yet (CN7) Lacerate/Primal Bite show a GCD after wowsims casts them (24 lacerate -> primal_bite replay misses); the median falls (1.751 measured; a ceiling rounds up)
    -- 2.50 -> 1.75, the count rises by the same cause (not by the metric)
    druid_guardian = { 1.76, 55 }, -- was 0.540, 41 (was 40): the world's parry haste (decision 63) and the tie hand-back
    -- re-pin 8b-2 (controller ruling, round 3): move-reached weave strikes show at the decision to walk (the Auto Shot that
    -- opens the weave window); wowsims logs the cast at arrival; the offset is the walk time, which Hekili does not model
    -- (owner rule: no movement in Hekili or the belief) and which is the lead a player needs to start walking. Every new
    -- real row is a weave strike shown early (the replay now feeds wowsims's OtherID 4 Auto Shots, so the weave runs).
    -- { 0.36, 7 } -> { 1.09, 13 } re-pin e2842f0a78 (Task 19, the new log, R51): the weave cause above at the new
    -- distance (11.67 yd): weave rows (wing_clip, immolation_trap) 1.03 to 1.37 s early, the off-GCD cooldowns at
    -- 6.22 and 127.83 (-1.12, -1.33), a Serpent Sting row late (0.17, the cast-anchored dot)
    -- { 1.09, 13 } -> { 0.46, 28 } re-pin e5a9cd2a2d (0.7 floors, CN8 merged, steady icons on): upstream's new weave (melee strikes
    -- on `ranged_remains>=ranged_speed-(mainhand_speed-mainhand_remains)`, shots otherwise): 28 real rows, 26 early (slack 26,
    -- gcd 25, aura 10: wing_clip 22, max 3.32), the walk the replay cannot forecast (triage Case 1) plus the melee range
    -- read as unknown (wing_clip:unknown 40; hotfix-0.6.2's maxRange 0 bug, probable, untraced); median is the larger set's
    hunter_beast_mastery = { 0.46, 28 }, -- was { 1.09, 13 }; before that { 0.32, 5 }: wing_clip 27.49 / 115.64 early (-1.59 / -0.74)
    -- { 0.15, 7 } -> { 0.38, 13 } (re-pin 8b-2, the weave cause above): six strike rows early, strider_kick 11.40 -0.10 -> -0.70
    -- { 0.38, 13 } -> { 0.98, 10 } re-pin e2842f0a78 (Task 19, the new log, R51): the weave cause above, strike rows
    -- 0.48 to 1.32 s early at 11.67 yd
    -- { 0.98, 10 } -> { 0.32, 22 } re-pin e5a9cd2a2d (0.7 floors): the same new-weave cause as Beast Mastery (22 real, 20 early:
    -- strider_kick 7, mongoose_bite 6 max 1.36, wing_clip 4); the median fell as the set grew
    hunter_marksmanship = { 0.32, 22 }, -- was { 0.98, 10 }; before that { 0.15, 10 } (b8d673eb8 raised it to 0.18 for gap BW, reverted with BW's fix): measured real 8 median 0.15 once the replay seeds the casting rate from unboosted ticks (168.28 strider_kick back to never); real 7 since gap CE's fractional read
    -- { 0.14, 9 } -> { 0.14, 10 } (Task 5): row 91.49 mongoose_bite now late 0.14 s, a cost decision with the belief's
    -- lo 1.9 mana under truth (the lo lag, gaps BQ/BT, G7); the base row rested on the replay artifact (belief 5.5
    -- mana over truth); owner-approved 2026-10-30.
    -- { 0.14, 10 } -> { 0.19, 6 } (Task 12): the replay world priced Strider Kick at 0.0581 of its 5000-mana pool (116
    -- under Resourcefulness), now of the class file's base 1720 (39.6, wowsims's log); count 10 -> 6, p90 0.36 -> 0.19, the
    -- median of the smaller set 0.14 -> 0.19 (the three 0.14 strider_kick rows and the 3.23 / 1.45 s cost rows gone, the
    -- 100.24 and 126.89 rows now 0.19 / 0.27); owner standing approval 2026-10-30. The median's rise to 0.19 is a
    -- smaller set (the rows above gone), not slower recommendations: p90 fell 0.36 -> 0.19, on-GCD .976 -> 1.000
    -- 0.19, 6 -> 0.20, 5 (gap CE; one fight, the log's seed; owner standing approval 2026-10-30): the whole-number read
    -- gone, Hunter's Mark leaves the real set (late 0.19 -> in the cost window), so the median of the 5 left is their 0.20
    -- { 0.20, 5 } -> { 0.63, 11 } (re-pin 8b-2, the weave cause above): six strike rows early (-0.39 to -1.59)
    -- { 0.63, 11 } -> { 0.39, 10 } re-pin e2842f0a78 (Task 19, the new log, R51): the weave cause above
    -- { 0.39, 10 } -> { 0.29, 22 } re-pin e5a9cd2a2d (0.7 floors): the new weave's strikes: 22 real, all early (strider_kick 10 max
    -- 2.34, wing_clip 6 max 2.80, immolation_trap 3): the walk the replay cannot forecast (triage Case 1) and the weave's omitted
    -- `wait` rows #2/#3 (CN19, second translator lane); the median fell as the set grew
    hunter_survival = { 0.29, 22 },
    -- { 0.47, 21 } -> { 0.76, 9 } re-pin e2842f0a78 (the new log): the 9 real rows late, cost class (gap BQ: lo reaches
    -- a cost after the truth), fire_blast 7 (max 0.76: the dry-mana waits on its 340)
    mage_arcane = { 0.76, 9 }, -- 0.760, 9 (ruling M13)
    -- { 0.37, 31 } -> { 0.45, 10 } re-pin e2842f0a78: cost class, scorch 10; the median is gap BQ's size, but the
    -- max 2.23 s rows sit about 50 mana under the truth, past BQ's ~0.4 s (untraced: an unseen Master of Elements
    -- refund is the candidate)
    mage_fire = { 0.45, 10 }, -- 0.450, 10
    -- { 0.38, 31 } -> { 0.42, 9 } re-pin e2842f0a78: cost class (gap BQ), scorch 6 (max 1.39)
    mage_frostfire = { 0.42, 9 }, -- 0.420, 9 (Task FFB, ruling M13)
    -- { 0.86, 7 } -> { 0.00, 0 } re-pin e2842f0a78: real 0 once Holy Shield's block hits are procs (PROT_REPLAY)
    -- { 0.00, 0 } -> { 0.43, 1 } pin move 2 on CN8 (rank 4 log, PROT_REPLAY's rank-4 procs, steady icons): one row, holy_strike
    -- late 0.43 s, cost class: lo under the truth at the cost (-208 mana, the unmodelled Shieldsworn return, gaps.md CU)
    paladin_protection = { 0.43, 1 }, -- 0.430, 1
    -- { 0.29, 10 } -> { 0.10, 7 } re-pin e2842f0a78 (fresh floor, Task 17: the Unsealed Wrath APL and the opener move):
    -- holy_strike 5 (max 0.10), seal_of_command 1 (0.23), seal_of_righteousness 1 (0.17)
    paladin_retribution = { 0.10, 7 }, -- 0.100, 7
    -- 1.500, 36 (Priest lane, Task 14; first clean run on 30e92574+): Mind Flay's 3 s channel, the next icon ready at
    -- the GCD's end inside it (Arcane's Missiles likewise, about 0.9 s)
    priest_shadow = { 1.50, 36 },
    -- 0.50, 27 -> 0.70, 10, owner ruling 2026-10-26: gap BD's cast-bar fix removed the small misses; decision by
    -- decision none worse and none new; the median of the rest rose
    -- 0.70, 10 -> 0.70, 11 (gap CE; one fight, the log's seed; owner standing approval 2026-10-30): the fractional read
    -- moves `shoot,if=mana.pct<=10`: at log 150.4 lo is 615.703, whole-number 615 stayed on the shoot side, the fraction
    -- crosses, so Penance shows one poll sooner (150.4 vs 150.6) with truth 621.4 above the crossing; wowsims acts at
    -- 150.7, offset -0.10 -> -0.30, past the reaction window: early against its decision grid, no promotion
    priest_smite = { 0.70, 11 },
    -- 30 -> 25 (fix 40): a short answer before our own energy gain shows is no rung; 0.20, 25 -> 0.15, 14 (gap CE, the
    -- fractional read) -> 0.16, 15 (gap CE; one fight, the log's seed; owner standing approval 2026-10-30): a poll whose
    -- short answer stands on the crossing now waits a whole energy, 0.10 s, the old read's wait: never ready before the
    -- client says so
    -- { 0.23, 18 } -> { 0.23, 29 } re-pin e2842f0a78 (R29's Mutilate log): cost class; 5 rows 0.45 s or less after an
    -- unseen Rogue Armor Energize 27788 (lo 9-20 under the truth, b ~1 s), the rest the floor 0.4-2.5 under the truth
    -- (b 0.16-0.33 s, gap BQ/CE: lo reaches the cost after the truth), 7 -> 15 of them with more decisions at the cost:
    -- both logs have the same build and 10 energizes; the gear changed (off hand Black Amnesty 19166 for 5267, two
    -- Darkmantle pieces swapped out, 4 remain), which moves the energy cadence (named, not traced row by row)
    -- { 0.23, 29 } -> { 0.23, 31 } R42 (the replay answers fight_remains from the log): only rows that were
    -- "never" moved, now timed
    -- (174.06 eviscerate in:reaction, 178.66 mutilate and 179.66 eviscerate late 0.16/0.20 s: the fight's last 6 s)
    -- { 0.23, 31 } -> { 0.20, 35 } (0.7 rogue lane's re-pin e5a9cd2a2d, R6; set on central-gatefix): lane-rogue e7fe801a4
    -- re-recorded the fixture on the new log (58 -> 90 decisions) but kept the old row; 35 real, all late, median 0.20:
    -- 32 cost (the belief's lo under the truth at the cost edge, gap BQ/CE; the two longest, 46.10 and 97.80 Mutilate
    -- 1.15/1.44 s, follow an unseen Rogue Armor Energize 27788 at 46.08/97.17), 3 gcd, each a cost edge landing on the
    -- GCD's end (class gcd: the later gate; no lo-truth recorded): 33.20 Eviscerate 0.23 (energy 10 -> 20 = cost over the
    -- GCD after the 32.20 Mutilate), 47.10 Eviscerate 0.71 (the same, behind the 46.08 unseen Energize), 63.60 Mutilate
    -- 1.12 (25 + Relentless Strikes 14179's 25 at 62.60 + regen = 60 = cost at the GCD's end; the belief's lo ~11 under,
    -- not traced further)
    rogue_assassination = { 0.20, 35 }, -- 0.200, 35
    -- { 0.20, 18 } -> { 0.24, 20 } re-pin e2842f0a78: cost class; 6 of the 7 large rows follow a 27788 energize (6 in
    -- the new log, 2 in the old: 21.18, 56.26, 64.69, 65.49, 69.00, 83.96), the rest the floor's lag (gap BQ/CE)
    -- { 0.24, 20 } -> { 0.24, 21 } R42 (the replay answers fight_remains from the log): only rows that were
    -- "never" moved, now timed (176.62 eviscerate late 0.19 s)
    rogue_combat = { 0.24, 21 }, -- 0.240, 21
    rogue_subtlety = { 0.17, 40 }, -- 0.20, 45 -> 0.15, 32 -> 0.17, 40 (gap CE): as rogue_assassination, a mark inside the ready wait
    -- { 0.21, 7 } -> { 0.71, 16 } re-pin e2842f0a78 (lane 15, R6): the build's own list (Magma and Windfury Totems,
    -- Fire Nova the filler at 375, Skyborne); 85 decisions, 16 real (10 early, 6 late); by class cooldown 15, cost 9, gcd 43
    -- { 0.71, 16 } -> { 0.38, 34 } 0.7 re-pin (e5a9cd2a2dfc, lane shaman, R6, owner ruling option b, reversible): 92
    -- decisions, early 26 / late 8, by class cooldown 23 / cost 10 / gcd 46 (earth_shock 11, stormstrike 6, fire_nova 6,
    -- shown 0.2-0.8 s before wowsims's cast). Cause as the Enhancement loop bar (pack_gate M.REACT_P90_BY): the
    -- conservative mana lower bound loses cost ties at the oracle's exact edge, re-timed by CN8's queue window; no cast
    -- lost. Not traced row by row (deferral)
    shaman_enhancement = { 0.38, 34 },
    -- { 0.48, 54 } -> { 2.20, 3 } re-pin 0.7 (lane shaman, R6): 91 decisions, 3 real (all late, cost class: the Major
    -- Mana Potion / Demonic Rune refills the belief cannot see leave lo ~2630 under the truth, gaps.md "Potion mana
    -- refill"; Lightning Bolt at its top rank's 198 where wowsims down-ranks, gap BL), median 2.20; the count falls from
    -- 54 with the new build's list (Lava Burst gone)
    shaman_elemental = { 2.20, 3 },
    -- 1.000, 18 (Warlock lane, Task 13; first clean run on 5d62f44c+): Shadow Bolt's 2.5 s cast, the next icon ready
    -- at the GCD's end inside it (Shadow's Mind Flay likewise). Count 18 -> 21 on fix 31 (06eec227): G4 keeps
    -- Corruption believed, so 12 more decisions are shown (never 22 -> 10), 3 of them a Shadow Bolt's early 1.0 s.
    -- Count 21 -> 23 on Task 16 (pack expects): decisions 12 and 15 (Shadow Bolt) moved from never to early (~1.0 s);
    -- never 10 -> 8; median 1.00 unchanged
    -- { 1.00, 23 } -> { 0.00, 0 } (Task 16, R6 and L82 M5: the floor follows the measurement; the fixture's 83 timed
    -- decisions all in grain since 5049ede22 and R42; the kit's fsr seed moves 142.50 wrack never -> in grain)
    warlock_affliction = { 0.00, 0 },
    -- Searing Pain's 1.5 s cast equals the GCD, so nearly every decision is absorbed at the grain. 0.10, 3 -> 0.20, 1,
    -- owner ruling 2026-10-26: gap BD's cast-bar fix removed the small misses; decision by decision none worse and
    -- none new; the median of the rest rose (the one left: life_tap 0.2 s early)
    -- { 0.30, 1 } -> { 0.30, 10 } R42 (the replay answers fight_remains from the log): only rows that were
    -- "never" moved, now timed
    -- (never 25 -> 2; 9 of them 0.2-0.3 s early, the Searing Pain grain as above); median 0.20
    -- { 0.30, 10 } -> { 0.00, 0 } re-pin e2842f0a78 (Task 16, R6, L82 M5): 114 decisions, 103 timed all in grain,
    -- never 11 (A: the refill-blind Life Tap, R50)
    warlock_demonology = { 0.00, 0 },
    -- 0.500, 5: Incinerate's 2.0 s cast, likewise. { 0.50, 5 } -> { 0.50, 16 } R42 (the replay answers
    -- fight_remains from the log): only rows that were "never" moved, now timed
    -- (never 28 -> 0; 12 of them early at the cast's grain); median 0.40
    -- { 0.50, 16 } -> { 0.00, 0 } re-pin e2842f0a78 (Task 16, R6, L82 M5): 107 decisions, 97 timed all in grain
    warlock_destruction = { 0.00, 0 },
    -- 0.900, 16: Shadow Bolt's, likewise. -> { 0.20, 1 } re-pin e2842f0a78 (Task 16, R6, L82 M5): 100 decisions, 1
    -- real (shadow_bolt late 0.20 s), the rest in grain or tie, never 24
    warlock_shadow_brand = { 0.20, 1 },
    -- 0.900, 18: Shadow Bolt's, likewise; 14 -> 18 on fix 31 (never 37 -> 28). -> { 0.20, 8 } re-pin e2842f0a78 (Task
    -- 16, R6, L82 M5; R49's stand-in DoT lines): 93 decisions, 8 real all early (shadow_bolt 4 max 0.30, life_tap 2,
    -- immolate 1), never 20
    warlock_sm_ruin = { 0.20, 8 },
    -- 0.880, 5 (was 0.80, 6): the world's parry haste (decision 63); the tie hand-back moves 177.88 sunder late -> never
    -- 0.680, 6 (fix 40): a short answer read before our own gain shows is no rung, so 177.88 sunder never -> early 0.68
    -- { 0.68, 6 } -> { 1.21, 4 } (re-pin e2842f0a78, lane 14, R6): after the replay's GCD fix every early row is in
    -- grain; the four left are late, each a cost wait on a same-instant gain wowsims casts on: 102.65 Mortal Strike
    -- (3.80: a white crit's 34.2 rage logged at the cast, heard one landing lag later, so the queue waits a swing),
    -- 40.05 / 90.05 Sunder and 110.05 Mortal Strike (1.81 / 1.21 / 0.21: an Anger Management tick crosses the cost
    -- 0.05 s before the cast; the belief's lo sits 1.5-6.9 under the truth)
    -- -> { 1.81, 2 } (0.7 warrior lane, R6; re-pin 4b0030a44b/e5a9cd2a2d, fixtures re-recorded): 67 decisions, 2 real, both late
    -- cost waits (Execute 2.01, Sunder Armor 1.81 on a same-instant gain wowsims casts on)
    warrior_arms = { 1.81, 2 },
    -- 0.51, 35 (was 0.48, 32): harness corrected to the measured swing timing (2026-10-22); 0.44 (fix 40): Whirlwind at
    -- 57.09 and 117.06 late -> early 0.09 and 0.06
    -- { 0.52, 26 } -> { 0.90, 19 } (lane 14, replay world fix, as druid_guardian's): 6 early GCD-chain rows in grain,
    -- the 19 left all late; -> { 0.42, 13 } re-pin e2842f0a78 (R6: the new log's 87 decisions, 13 real, all late)
    -- -> { 0.42, 14 } (0.7 warrior lane, R6): 95 decisions, 14 real, all late (Bloodthirst x7, Whirlwind x3, Sunder x3), median 0.40
    warrior_fury = { 0.42, 14 },
    -- { 0.38, 11 } -> { 0.37, 3 } re-pin e2842f0a78 (lane 14, R6; after 5049ede22's GCD fix): 98 decisions, 3 real, all
    -- early, class aura: Shield Slam 49.84 (0.24), Sunder Armor 71.77 / 143.44 (0.37 / 0.44): wowsims queues Shield Block
    -- (`Queueing up 2565 to cast at`) and casts the on-GCD ability at that instant, after ours shows it ready
    -- -> { 0.37, 4 } (0.7 warrior lane, R6): 97 decisions, 4 real, all late, median 0.18 (Thunder Clap x2 0.32, Demoralizing
    -- Shout 0.31, Revenge 0.18: cost and cooldown edges at the cast's instant)
    warrior_protection = { 0.37, 4 },
}

--- The ready-time check of replay `R` (timing.lua) on spec `spec` after its run: prints "<label> wowsims timing:
--- <line>", diffs the decisions against tests/Forever/fixtures/timing_<spec>.lua (TIMING=record rewrites it) and
--- asserts the spec's M.READY floor. Returns the summary and the line.
function M.ready(label, spec, R)
    local P = setmetatable({ reaction = knob(spec, "reactionTimeMs"), queue = knob(spec, "queueDelay") }, {
        __index = timing.P,
    })
    local rows = timing.rows(R.timing, P)
    local s = timing.summary(rows, R.timing.flips, P)
    local line = timing.line(s)
    print(label .. " wowsims timing: " .. line)
    local path = M.FIXTURES .. "timing_" .. spec .. ".lua"
    if os.getenv("TIMING") == "record" then
        local git = assert(io.popen("git rev-parse --short HEAD"))
        local head = git:read("*l")
        git:close()
        local knobs = {}
        for _, k in ipairs({ "REACT", "G7", "HOLD", "TICK", "reaction", "queue" }) do
            knobs[#knobs + 1] = k .. " " .. P[k]
        end
        timing.write(
            path,
            rows,
            ("Generated by tests/Forever/helpers/wowsims.lua (TIMING=record) on %s: do not edit. %s"):format(
                head,
                table.concat(knobs, ", ")
            )
        )
    end
    local want = dofile(path)
    local floor = assert(M.READY[spec], "no ready-time floor for " .. spec)
    if ab.arm() ~= "default" then -- a provider arm records how many decisions moved off the fixture (providers §4.1)
        local moved = math.abs(#want - #rows)
        for i = 1, math.min(#want, #rows) do
            local r = rows[i]
            moved = moved
                + (util.deepcompare(want[i], { r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] }) and 0 or 1)
        end
        ab.check(moved == 0, label .. " timing", ("%d of %d decisions off the fixture; %s"):format(moved, #want, line))
        ab.check(s.realMedian <= floor[1] + 1e-9 and s.real <= floor[2], label .. " timing floor", line)
        return s, line
    end
    assert.are.equal(#want, #rows, "decisions in " .. path)
    for i, r in ipairs(rows) do
        assert.are.same(want[i], { r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] }, path .. " decision " .. i)
    end
    -- the fixture comparison is the gate (any decision's change fails it); the count floor documents the real set
    assert.is_true(s.realMedian <= floor[1] + 1e-9 and s.real <= floor[2], line)
    return s, line
end

--- The replay gate of content `C` on spec `spec`'s log: prints "<label> wowsims: <line>", asserts the engine's health
--- (pack_gate.health) and decisions on-GCD >= `floor`. `o`: replay.new's knobs over the character's forms, the
--- request's target creature type, its distance (M.distance), the content's shared category cooldowns (C.SHARED) and
--- the content WORLD's regen and fsr; the character's pool the log's (M.logged); then the ready-time check (M.ready).
--- Returns the summary and the line.
--- (re-pin design §3a, decision 11) The windows' drift guard on headless instance `H`, polled every `poll` seconds
--- [0.2: the loop's 5 Hz]: every open the forecast predicts (an `open_window` line's or a handler's, through
--- state.openWindow, at the open's query_time) from an update a poll or less before it (plus the recheck's 0.01 pad)
--- is matched by the belief's
--- open of that window (Facade.Window's openedAt, read at each `tick`) within one poll; drift is flicker. A prediction
--- made further ahead is made again by the updates after it, so only the freshest counts. The forecast clears an
--- open_window line's last result at every reset (State.lua CopyWindows), so a line held true opens again at each
--- update while the window is down: an up window ignores it (no refresh: no new open, nothing recorded), and a down
--- one (closed by a cast the belief also saw) is a fresh open, held to the belief like any, so a held line is never a
--- false miss while the belief's window is up. `tick(base)` reads the belief (`base`: the run clock's zero, for the
--- times listed); `misses()` lists each unmatched predicted open as "<window> at <time> s", in time order; also
--- returned: the predicted and believed opens ({ name, time }).
function M.windowGuard(H, poll)
    poll = poll or 0.2
    local S, F = H.Hekili.State, H.ns.Facade
    local predicted, believed, lastAt, zero = {}, {}, {}, 0
    local open = S.openWindow
    S.openWindow = function(name, ...)
        local w = S.window[name]
        local was = w and w.up and w.elapsed == 0
        open(name, ...)
        -- one poll ahead at most, plus the recheck's pad past a clock's crossing (Scripts.lua: 0.01)
        if w and w.up and w.elapsed == 0 and not was and S.query_time - S.now <= poll + 0.02 then
            predicted[#predicted + 1] = { name, S.query_time }
        end
    end
    local function tick(base)
        zero = base or 0
        for name in pairs(H.Hekili.Class.windows) do
            local up, at = F.Window(name)
            if up and at ~= lastAt[name] then
                lastAt[name] = at
                believed[#believed + 1] = { name, at }
            end
        end
    end
    local function misses()
        local out, seen = {}, {}
        for _, p in ipairs(predicted) do
            local key = p[1] .. ("%.3f"):format(p[2])
            local hit = false
            for _, b in ipairs(seen[key] and {} or believed) do
                hit = hit or (b[1] == p[1] and math.abs(b[2] - p[2]) <= poll + 1e-6)
            end
            if not seen[key] and not hit then
                out[#out + 1] = ("%s at %.2f s"):format(p[1], p[2] - zero)
            end
            seen[key] = true
        end
        return out
    end
    return tick, misses, predicted, believed
end

function M.gate(label, C, spec, floor, o)
    C = M.logged(C, spec)
    local L = loop.new(C)
    local R = replay.new(M.log(spec), L.oracle, M.replayOptions(C, spec, o))
    local tick, misses, predicted, believed = M.windowGuard(L.us)
    local m = loop.replay(L, R, {
        on = function(_, steps)
            tick(steps[1].base)
        end,
    })
    local r, line = loop.summary(m), loop.line(m)
    print("\n" .. label .. " wowsims: " .. line)
    local missed = misses()
    print(
        ("%s windows: %d forecast opens, %d belief opens, drift %d [%s]"):format(
            label,
            #predicted,
            #believed,
            #missed,
            table.concat(missed, "; ")
        )
    )
    pack_gate.health(m, r, line)
    assert.are.same({}, missed, label .. ": a forecast window open the belief did not make within one poll")
    ab.check(r.decisions >= floor, label, line) -- a bar: recorded in a provider arm (providers spec §4.1)
    M.ready(label, spec, R)
    return r, line
end

--- The leveling gate of content `C` (its pack drives the loop's own world at C's level, `fights` [1] fights of 120 s,
--- one instance): prints "<label> live L<level>: ..." and asserts no error, raise or unlisted read, at least one press,
--- and never idle longer than `limit` seconds [6: four GCDs] in a row with a known on-GCD ability the world would
--- accept. Idle: in combat, our GCD free, no cast in progress, no on-GCD press this tick (an off-GCD press is idle). Returns the worst idle and the line.
--- `stat` "median": each fight a fresh boot (its own first fight), and the bar is the median of the per-fight worsts.
function M.live(label, C, limit, fights, stat)
    limit = limit or 6
    local median = stat == "median"
    local L = loop.new(C)
    local c = C.character()
    local known = {}
    for _, id in ipairs(c.known) do
        known[id] = true
    end
    local abilities = L.oracle.Hekili.Class.abilities
    local worst, presses, errors = 0, 0, 0
    local worsts = {} -- per fight (median)
    for seed = 1, fights or 1 do
        if median and seed > 1 then
            L = loop.new(C)
            abilities = L.oracle.Hekili.Class.abilities
        end
        local streak, last, fightWorst = 0, 0, 0
        local run = loop.run(L, seed, {
            duration = 120,
            on = function(run, _, t)
                local us = run.us
                -- the run's own GCD-idle tick (in combat, GCD free, no on-GCD press): an off-GCD press is still idle
                local gcdIdle = run.idle > last
                last = run.idle
                local idle = t >= loop.PULL and gcdIdle and t >= (us.castUntil or 0)
                local usable = false
                if idle then
                    for _, row in ipairs(L.answers) do
                        local a = known[row[1]] and abilities[row[1]]
                        if a and a.gcd ~= "off" and row[2](run.W, us, us.power) then
                            usable = true
                            break
                        end
                    end
                end
                streak = (idle and usable) and streak + 1 or 0
                fightWorst = math.max(fightWorst, streak)
            end,
        }, { { H = L.us } })
        worst = math.max(worst, fightWorst)
        worsts[seed] = fightWorst
        presses = presses + run.presses
        errors = errors + run.errors + run.raises + #run.misses
    end
    local seconds = worst * loop.TICK
    local line = ("worst idle %.1f s with a usable on-GCD ability (limit %.1f), presses %d, errors %d"):format(
        seconds,
        limit,
        presses,
        errors
    )
    if median then
        table.sort(worsts)
        local n = #worsts
        seconds = (worsts[math.floor((n + 1) / 2)] + worsts[math.floor(n / 2) + 1]) / 2 * loop.TICK
        local fmt = "median worst idle %.1f s over %d fresh fights (limit %.1f), worst %.1f s, presses %d, errors %d"
        line = fmt:format(seconds, n, limit, worst * loop.TICK, presses, errors)
    end
    print("\n" .. label .. " live L" .. c.level .. ": " .. line)
    assert.are.equal(0, errors, line)
    assert.is_true(presses > 0, line)
    ab.check(seconds <= limit + 1e-9, label .. " live", line) -- a bar: recorded in a provider arm (providers §4.1)
    return seconds, line
end

return M
