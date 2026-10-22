-- tests/Game/harness/replay.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 3): a
-- wowsims/forever debug log (tools/wowsims/export.lua) as the headless loop's world. `parse` reads the log;
-- `new` binds it to a booted instance's class data (spell ID -> ability key, aura durations) and gives loop.run its one
-- injection (`o.replay`): the world factory, wowsims's decisions and its next cast after a tick. The truth is the
-- log's: casts at their completion, a hard cast's bar from its Casting line (UNIT_SPELLCAST_START), a `channeled`
-- ability's channel from its cast to its aura's fade (else its declared `cast`), powers as the logged after-values (no regen ticks; the client
-- still reads the content's rate, mana's from the log's regen lines: M.manaRegen), our auras and the target's with
-- the duration the client shows (the log's run to a natural fade, the declared one to a removal: a fade after one of
-- our Casting or Completed cast lines in its timestamp), each fade a removal at its time, the content's hidden auras
-- in the truth only, spells landing at once, a white swing's outcome one landing lag after its swing (M.LAND; wowsims
-- logs both at once, with the swing's rage), the mob's health at 20% from the execute phase's start (wowsims's is the
-- last 20% of the duration) and never dead, our distance to it (the request's, then the log's Movement stacks). Not
-- replayed: the target's swings.
-- Class-neutral: the content passes its forms, hidden auras, procs and totems; the casts map through the booted
-- instance's own ability set (Hekili.Class, booted as the log's race). Credit: the log format is wowsims/forever's
-- (MIT, https://github.com/wowsims/forever); no code copied.
local world = require("Game.harness.world")
local entities = require("Game.harness.entities")
local observer = require("Game.harness.observer")
local timing = require("Game.harness.timing")

local M = {}

M.PULL = 5 -- the least world time of the log's 0 (a log whose prepull starts after -4.5)
M.LEAD = 0.5 -- the world time of the log's first line at the latest: after the prepull read at 0.1
M.EPS = 1e-6 -- a line's place within its timestamp, as time: a decision falls just before its Casting line
M.TAIL = 0.2 -- the exporter's execute proportion: the last 20% of the duration

-- Our white swing's landing lag per hand: the main hand's median (P log 2, 474 ms) and the off hand's own-swing mode
-- (G5, 703 ms; log 2's off-hand median is 953 ms), no spread. The swing's rage stays at the swing, the log's line, as
-- the game credits it (checkpoint R1, MEASURED 2026-10-20; Families/Resources.lua's owe).
-- shortcut: fixed lags, deterministic; draw from observer.lag when a gate needs the tail.
M.LAND = { observer.DEFAULTS.main.med, observer.DEFAULTS.off.own }

-- wowsims's mana regen: its tick (manaTickDuration, sim/core/mana.go) and the regen lines' OtherID; Tag 1 the casting
-- rate (inside the five-second rule), Tag 2 the not-casting rate.
M.MANA_TICK, M.MANA_REGEN = 0.1, 2

-- Fix 31 G4: the spell ID of an unmapped item's use (the log names the item, not its use spell): the client's
-- UNIT_SPELLCAST_SUCCEEDED of a spell no ability has (no kit's ID is 0; Engine/Schema/Spec.lua's items are -101 on).
-- shortcut: its success only, no cast bar for a cast-time item; add the START when a gate needs it.
M.UNMAPPED_SPELL = 0

M.MOVE = 20 -- wowsims's OtherActionMove: the Movement aura (sim/core/movement.go), its stacks the distance in yards
-- (max(int(d), 1): truncated, so the replay's position can be up to 1 yd short of wowsims's)

-- wowsims's resource names and the client's power types (Enum.PowerType); other names (health) are not powers.
M.POWER = { mana = 0, rage = 1, focus = 2, energy = 3, ["combo points"] = 4 }

-- wowsims's outcome words and the world's { act, flag }.
local OUTCOME = {
    Hit = { "WOUND", "" },
    Crit = { "WOUND", "CRITICAL" },
    Glance = { "WOUND", "GLANCING" },
    Block = { "WOUND", "" },
    CritBlock = { "WOUND", "CRITICAL" },
    Miss = { "MISS", "" },
    Dodge = { "DODGE", "" },
    Parry = { "PARRY", "" },
}

local function secs(s) -- "1.5s", "250ms", "0s" -> seconds
    local v, m = s:match("^([%d.]+)(m?)s$")
    return v and tonumber(v) / (m == "m" and 1000 or 1) or 0
end
-- "SpellID: 1, Tag: 2" -> 1, nil, 2; "OtherID: 3, Tag: 1" -> nil, 3, 1; "ItemID: 4" -> nil, nil, nil, 4
local function ids(s)
    return tonumber(s:match("SpellID: (%d+)")),
        tonumber(s:match("OtherID: (%d+)")),
        tonumber(s:match("Tag: (%-?%d+)")),
        tonumber(s:match("ItemID: (%d+)"))
end

-- One line of our character's (`rest`, after its "[Name (#1)] ") as an event, or nil.
local function ours(rest)
    local b, cast, gcd = rest:match("^Casting {([^}]*)} %(.-Cast Time = (%S+), GCD = (%S+),")
    if b then
        local id, _, tag, item = ids(b)
        local cost = tonumber(rest:match("Cost = ([%d.]+)"))
        return (id or item)
            and { kind = "casting", id = id, item = item, tag = tag, cast = secs(cast), gcd = secs(gcd), cost = cost }
    end
    b = rest:match("^Completed cast {([^}]*)}")
    if b then
        local id, other, tag, item = ids(b)
        return { kind = "completed", id = id, other = other, tag = tag, item = item }
    end
    local amount, name, src, from, to = rest:match("^%a+ ([%d.]+) ([%a ]-) from {([^}]*)} %(([%d.]+) %-%-> ([%d.]+)%)")
    if name then
        local id, other, tag = ids(src)
        return {
            kind = "power",
            name = name,
            from = tonumber(from),
            to = tonumber(to),
            amount = tonumber(amount),
            total = tonumber(rest:match("of ([%d.]+) total")), -- the pool's maximum
            id = id,
            other = other,
            tag = tag,
        }
    end
    local verb
    verb, b = rest:match("^Aura (%a+): {([^}]*)}")
    if verb then
        local id, _, tag = ids(b) -- an OtherID aura (a pre-pull move) is not a spell's
        return id and { kind = "aura", unit = "player", verb = verb, id = id, tag = tag }
    end
    local n
    b, n = rest:match("^{([^}]*)} stacks: %d+ %-%-> (%d+)")
    if b then
        local id, other, tag = ids(b)
        if other == M.MOVE then -- the Movement aura's stacks: the yards to the target, whole (0: the move's end)
            return tonumber(n) > 0 and { kind = "move", distance = tonumber(n) } or nil
        end
        return id and { kind = "stacks", unit = "player", id = id, to = tonumber(n), tag = tag }
    end
    local word, tail
    b, word, tail = rest:match("^%[Target 1%] {([^}]*)} tick (%a+)(.*)$")
    local what = b and "tick"
    if not b then
        b, word, tail = rest:match("^%[Target 1%] {([^}]*)} (%a+)(.*)$")
    end
    if b then
        local id, other, tag = ids(b)
        local amount = tonumber(tail:match("for ([%d.]+) damage") or 0)
        local o = OUTCOME[word] or (amount > 0 and OUTCOME.Hit)
        if o then
            what = what or (other == 3 and "swing" or "spell")
            return {
                kind = "hit",
                what = what,
                hand = tag == 2 and 2 or 1,
                id = id,
                act = o[1],
                flag = o[2],
                amount = amount,
            }
        end
    end
end

-- A target line (`rest`, after "[Target 1] ") as an event, or nil.
local function theirs(rest)
    local verb, b = rest:match("^Aura (%a+): {([^}]*)}")
    if verb then
        local id, _, tag = ids(b) -- an OtherID aura (a pre-pull move) is not a spell's
        return id and { kind = "aura", unit = "target", verb = verb, id = id, tag = tag }
    end
    local n
    b, n = rest:match("^{([^}]*)} stacks: %d+ %-%-> (%d+)")
    if b then
        local id, _, tag = ids(b)
        return id and { kind = "stacks", unit = "target", id = id, to = tonumber(n), tag = tag }
    end
end

--- The events of a log's text: { header = { pin, spec, seed, duration, targetLevel, talents = { { id, rank, tree } }
--- }, ev = { { t, kind, ... } } } in line order. Kinds: casting { id | item, tag, cast, gcd, cost }, completed { id, other,
--- tag, item },
--- power { name, from, to, amount, total, id, other, tag }, aura { unit ("player" | "target"), verb ("gained" | "faded" | "refreshed"), id }, stacks
--- { unit, id, to }, hit { what ("swing" | "spell" | "tick"), hand, id, act, flag, amount }, move { distance } (our
--- Movement aura's stacks: wowsims's yards to the target, truncated, at least 1, while we move). Other lines are
--- skipped.
--- The leading aura and stack lines at 0 before any other event are the sim's opening state (`initial`).
function M.parse(text)
    local h, ev = { talents = {} }, {}
    local opening = true
    for line in text:gmatch("[^\n]+") do
        if line:sub(1, 1) == "#" then
            local pin, spec, seed, dur, lvl = line:match("^# wowsims (%x+) (%S+) seed (%d+) (%d+) s target (%d+)")
            if pin then
                h.pin, h.spec, h.seed, h.duration, h.targetLevel =
                    pin, spec, tonumber(seed), tonumber(dur), tonumber(lvl)
            end
            local list = line:match("^# talents (.*)$")
            for id, rank, tree in (list or ""):gmatch("(%d+)=(%d+)@(%d+)") do
                h.talents[#h.talents + 1] = { tonumber(id), tonumber(rank), tonumber(tree) }
            end
        else
            local t, who, rest = line:match("^%[(%-?[%d.]+)%] %[([^%]]+)%] (.*)$")
            t = tonumber(t)
            local e
            if t and who:match(" %(#1%)$") then -- ours, not our pets' ("<Name> (#1) - <Pet>")
                e = ours(rest)
            elseif t and who == "Target 1" then
                e = theirs(rest)
            end
            if e then
                e.t = t
                opening = opening and t == 0 and (e.kind == "aura" or e.kind == "stacks")
                e.initial = opening or nil
                ev[#ev + 1] = e
            end
        end
    end
    return { header = h, ev = ev }
end

--- The mana regen rates per second the log's regen lines show: not casting, casting; nil without any. Each is its
--- tag's most frequent amount a tick (partial ticks at the five-second rule's edges are rarer). A casting rate above
--- the not-casting one is a temporary boost (Innervate: wowsims's casting rate is the mp5 part plus at most all of the
--- spirit part), so the casting rate is then 0; with no not-casting line the casting rate stands for both.
function M.manaRegen(ev)
    local count, best = { {}, {} }, { 0, 0 }
    for _, e in ipairs(ev) do
        local tag = e.kind == "power" and e.name == "mana" and e.other == M.MANA_REGEN and e.tag
        if tag == 1 or tag == 2 then
            local n = (count[tag][e.amount] or 0) + 1
            count[tag][e.amount] = n
            if n > (count[tag][best[tag]] or 0) then
                best[tag] = e.amount
            end
        end
    end
    local casting, idle = best[1] / M.MANA_TICK, best[2] / M.MANA_TICK
    if idle == 0 and casting == 0 then
        return nil
    elseif idle == 0 then
        return casting, casting
    end
    return idle, casting <= idle and casting or 0
end

--- The log's pools (M.parse's `ev`): { [powerType] = its first line's before-value }, { [powerType] = its maximum
--- ("of N total") }: the one source of every pool maximum in a replay (the world's, the client's UnitPowerMax and the
--- character's: tests/Forever/helpers/wowsims.lua `logged`).
--- shortcut: the first line's total; take each line's own if a log's maximum moves mid-fight
function M.pools(ev)
    local start0, maxOf = {}, {}
    for _, e in ipairs(ev) do
        local pt = e.kind == "power" and M.POWER[e.name]
        if pt and start0[pt] == nil then
            start0[pt], maxOf[pt] = e.from, e.total
        end
    end
    return start0, maxOf
end

--- A replay of log `text` bound to booted instance `H`'s class data (abilities by `key`, `id`, `copy`, `cooldown`: a
--- number, else the engine's answer `H.Hekili.State.action[key].cooldown` (talent-modified), else the log's least
--- spacing between two of the key's casts; auras by `id`, `copy`, `duration`). `o.shared` ({ [key] = partner key or
--- keys }: a category cooldown, the content's) puts the partners on the cast's cooldown too, on every member's ranks. `o`: forms ({ spellID, ... }: the client's form index of each form's spell and
--- aura), hidden ({ [auraID] = true }: in the truth, never shown to the client), procs ({ [spellID] = true }: neither a
--- decision nor a cast; a key is a spell ID, every tag of it, or "<spellID>:<tag>", that tag only: a weapon proc logged
--- under its totem's ID), totems ({ [key] = { slot, duration } }: a completed cast of the key summons into that slot,
--- W.summonTotem), speed (the main hand's period; default the log's first two main-hand swings), regen and fsr (the
--- rates the client reads: W.rates, W.fsr; no regen ticks; the loop's world knobs, mana's replaced by the log's), pull (the world time of the log's 0; default the log's
--- earliest line M.LEAD s into the world, at least M.PULL: a -10 s prepull pulls at 10.5). Prepull casts (before the
--- log's 0) are decisions like any other: wowsims counts them as its casts and the engine recommends a pack's precombat
--- list out of combat (each line under its guard against recasting), so an on-GCD one is scored. creatureType: the mob's
--- (`target.creature_type`'s key; the request's mobType: tests/Forever/helpers/wowsims.lua `creatureType`), distance (the request's distanceFromTarget: our yards from the target at the start,
--- W.moveTo; the log's move lines step it; nil: no positions). An ItemID cast maps through the abilities' `item`/`items`:
--- a decision and a cooldown, no cast event (shortcut: the client is not shown the item's spell; emit it when a gate
--- reads an item's cast).
function M.new(text, H, o)
    o = o or {}
    local p = M.parse(text)
    local h = p.header
    -- the pull: the log's earliest line (its prepull, wowsims's doAtValue) M.LEAD into the world, at least M.PULL;
    -- `o.pull` overrides it
    local first = 0
    for _, e in ipairs(p.ev) do
        if not e.initial and e.t < first then
            first = e.t
        end
    end
    local R = {
        header = h,
        pull = o.pull or math.max(M.PULL, M.LEAD - first),
        duration = h.duration or 180,
        targetLevel = h.targetLevel,
        creatureType = o.creatureType,
    }
    local class = H.Hekili.Class
    -- a cooldown the kit computes (a function: talent-modified) as the booted engine answers it, or nil (an error
    -- too: the log's spacing stands in). shortcut: read once at boot, so a state-dependent cooldown (a buff, haste)
    -- keeps its boot value; read it at each cast when a kit's cooldown moves in a fight.
    local function engineCooldown(key)
        local S = H.Hekili.State
        local ok, v = pcall(function()
            return S.action[key].cooldown
        end)
        return ok and tonumber(v) or nil
    end
    -- spell ID -> ability key (every rank), the key's IDs and cooldown; aura ID -> duration
    local keyOf, itemOf, rankIDs, cd, dur, form, spacing, engine = {}, {}, {}, {}, {}, {}, {}, {}
    local keys = {}
    for key, a in pairs(class.abilities) do
        if type(key) == "string" and type(a) == "table" and a.key == key then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local a = class.abilities[key]
        local list = { a.id }
        for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
            list[#list + 1] = id
        end
        rankIDs[key], cd[key] = {}, tonumber(a.cooldown) or (a.cooldown == nil and 0) or nil
        if cd[key] == nil then
            engine[key] = engineCooldown(key)
        end
        for _, id in ipairs(list) do
            if type(id) == "number" then
                keyOf[id] = keyOf[id] or key
                table.insert(rankIDs[key], id)
            end
        end
        for _, id in ipairs(type(a.items) == "table" and a.items or { rawget(a, "item") }) do
            if type(id) == "number" then
                itemOf[id] = itemOf[id] or key
            end
        end
    end
    -- a computed cooldown: the engine's, capped at the log's least spacing between two of the key's casts (wowsims
    -- did cast it that soon); the spacing alone when the engine cannot say; none of either: no cooldown
    local lastAt = {}
    for _, e in ipairs(p.ev) do
        local key = e.kind == "casting" and (e.id and keyOf[e.id] or (e.item and itemOf[e.item]))
        if key and cd[key] == nil then
            if lastAt[key] then
                spacing[key] = math.min(spacing[key] or math.huge, e.t - lastAt[key])
            end
            lastAt[key] = e.t
        end
    end
    for _, key in ipairs(keys) do
        local e, sp = engine[key], spacing[key]
        cd[key] = cd[key] or (e and sp and math.min(e, sp)) or e or sp or 0
    end
    -- a shared category (o.shared: { [key] = partner key or keys }): a cast puts every member on its cooldown, the
    -- client answering it on every member's ranks (as the worlds' resolve does)
    local shared = {}
    for _, key in ipairs(keys) do
        local partners = o.shared and o.shared[key]
        if partners then
            local ids, list = {}, type(partners) == "table" and partners or { partners }
            for _, id in ipairs(rankIDs[key]) do
                ids[#ids + 1] = id
            end
            for _, k in ipairs(list) do
                for _, id in ipairs(rankIDs[k] or {}) do
                    ids[#ids + 1] = id
                end
            end
            shared[key] = { keys = list, ids = ids }
        end
    end
    local stealthy = {} -- the auras IsStealthed answers for (`isStealthed`), every rank
    -- a snapshot: reading a computed field (a function `duration`) can add keys to class.auras, and a table that grows
    -- under pairs skips entries (GAP AT: Rend's ranks were dropped)
    local auras = {}
    for _, a in pairs(class.auras) do
        auras[#auras + 1] = a
    end
    for _, a in ipairs(auras) do
        if type(a) == "table" and type(a.id) == "number" and a.isStealthed == true then
            stealthy[a.id] = true
            for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
                stealthy[id] = true
            end
        end
        if type(a) == "table" and type(a.id) == "number" and type(a.duration) == "number" then
            dur[a.id] = dur[a.id] or a.duration
            for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
                if type(id) == "number" then
                    dur[id] = dur[id] or a.duration
                end
            end
        end
    end
    for i, id in ipairs(o.forms or {}) do
        form[id] = i
    end
    local hidden, procs, totems = o.hidden or {}, o.procs or {}, o.totems or {}
    -- the event's ability key, or nil (unmapped, or a proc)
    local function keyFor(e)
        if e.id and (procs[e.id] or procs[e.id .. ":" .. (e.tag or 0)]) then
            return nil
        end
        return e.id and keyOf[e.id] or (e.item and itemOf[e.item])
    end
    -- world times: log time + pull, each line after the earlier ones of its timestamp; the opening state at 0
    -- a tagged aura whose spell ID also logs untagged on that unit is another wowsims aura sharing the ID (a stacking
    -- counter beside a buff; the example in tools/wowsims/specs/paladin_protection.lua): not the client's aura of that
    -- ID, so its lines are dropped; a tag alone (an External's -1, a weapon's 1) stays the aura. Limit: any tag is
    -- dropped once an untagged line exists, -1 and 1 included (the example's is 1, so no tag can be spared); an External's
    -- copy of an aura we also carry would be lost (none in the checked-in logs)
    local plain = {}
    for _, e in ipairs(p.ev) do
        if e.kind == "aura" and not e.tag then
            plain[e.unit .. ":" .. e.id] = true
        end
    end
    local kept = {}
    for _, e in ipairs(p.ev) do
        if not ((e.kind == "aura" or e.kind == "stacks") and e.tag and plain[e.unit .. ":" .. e.id]) then
            kept[#kept + 1] = e
        end
    end
    p.ev = kept
    local seq = {}
    for _, e in ipairs(p.ev) do
        local n = (seq[e.t] or 0) + 1
        seq[e.t] = n
        e.wt = e.initial and 0 or R.pull + e.t + n * M.EPS
        assert(e.initial or e.t > 0.1 - R.pull, "the log starts before the replay's prepull read: raise o.pull")
    end
    -- the duration the client is shown at each application (UNIT_AURA's): its run when its next line is a natural
    -- fade (the real duration: combo-point or talent scaled), the declared duration when a fade is a removal (one of
    -- our Casting or Completed cast lines earlier in the fade's timestamp, a white swing's "Completed cast {OtherID: 3}"
    -- included: a recast, consume or cancel), else the declared (apply)
    local castAt
    for _, e in ipairs(p.ev) do
        if e.kind == "casting" or e.kind == "completed" then
            castAt = e.t
        elseif e.kind == "aura" and e.verb == "faded" then
            e.removed = castAt == e.t
        end
    end
    local nextOf = {}
    for i = #p.ev, 1, -1 do
        local e = p.ev[i]
        if e.kind == "aura" then
            local k = e.unit .. ":" .. e.id
            local nx = nextOf[k]
            if e.verb ~= "faded" and nx and nx.verb == "faded" then
                local run = nx.wt - e.wt
                e.d = nx.removed and dur[e.id] and math.max(dur[e.id], run) or run
            end
            nextOf[k] = e
        end
    end
    -- a channel's end (an ability the kit declares `channeled`): its aura's next fade on either unit before its next
    -- cast (wowsims's channel is a dot whose aura fades at the end or at a clip), else its declared length (`cast`)
    -- shortcut: a function `channeled` or `cast` reads as none; read the engine's answer if a kit declares one
    for i, e in ipairs(p.ev) do
        local key = e.kind == "completed" and e.id and keyFor(e)
        local a = key and class.abilities[key]
        if a and rawget(a, "channeled") == true then
            for j = i + 1, #p.ev do
                local f = p.ev[j]
                if f.id == e.id and (f.kind == "completed" or (f.kind == "aura" and f.verb == "faded")) then
                    e.chanEnd = f.kind == "aura" and f.wt or nil
                    break
                end
            end
            e.chanEnd = e.chanEnd or e.wt + (tonumber(rawget(a, "cast")) or 0)
        end
    end
    -- wowsims's casts (procs out): the decisions just before their Casting lines, sorted
    R.decisions, R.casts = {}, {}
    for _, e in ipairs(p.ev) do
        if e.kind == "casting" and keyFor(e) then
            local d = { t = e.wt - M.EPS / 2, key = keyFor(e), gcd = e.cast > 0 or e.gcd > 0 }
            R.decisions[#R.decisions + 1], R.casts[#R.casts + 1] = d, d
        end
    end
    table.sort(R.decisions, function(x, y)
        return x.t < y.t
    end)
    R.timing = timing.new(R, p.ev, keyFor, cd, M.POWER) -- each decision's ready class (timing.lua)
    -- the main hand's period: the first two main-hand swings
    local last
    for _, e in ipairs(p.ev) do
        if e.kind == "hit" and e.what == "swing" and e.hand == 1 then
            if last then
                R.speed = R.speed or (math.floor((e.t - last) * 1000 + 0.5) / 1000)
                break
            end
            last = e.t
        end
    end
    R.speed = o.speed or R.speed
    -- the mob: health crosses 20% exactly at the execute phase's start (the damage before it is 80%)
    local before, start = 0, R.pull + (1 - M.TAIL) * R.duration
    for _, e in ipairs(p.ev) do
        if e.kind == "hit" and e.wt < start then
            before = before + e.amount
        end
    end
    R.mobHealth = math.floor(before / (1 - M.TAIL)) + 1
    local start0
    start0, R.maxOf = M.pools(p.ev)

    R.manaIdle, R.manaCasting = M.manaRegen(p.ev)

    local ci = 1
    --- wowsims's next cast strictly after world time `t` (its key), or false; `t` only grows within a world.
    function R.next(t)
        while R.casts[ci] and R.casts[ci].t <= t do
            ci = ci + 1
        end
        return R.casts[ci] and R.casts[ci].key or false
    end

    --- The world of the log (loop.run's factory: `wo` the loop's knobs, `seed` the world's generator).
    function R.world(wo, seed)
        ci = 1
        local W = world.new(seed)
        local w = wo.weapons and wo.weapons[1] or { 1, 2, R.speed or 2 }
        local us = W.add(entities.new({
            guid = "Player-1",
            level = wo.level,
            weapons = { { w[1], w[2], R.speed or w[3] } },
            powerMax = wo.max,
            pt = wo.pt,
            res = wo.res,
            -- shortcut: the content's bags, pet and stats as the world starts; the log's own (its pet's mana, its
            -- reagents) are not read, and nothing spends them here; read them when a replay gate needs them
            bags = wo.bags,
            pet = wo.pet,
            stats = wo.stats,
        }))
        if us.pet then
            W.startPetRegen(us)
        end
        us.power = start0[us.pt] or wo.power or 0
        us.power0 = us.power
        for pt, r in pairs(us.res) do
            if start0[pt] then
                r.cur, us.res0[pt] = start0[pt], start0[pt]
            end
        end
        for pt, m in pairs(R.maxOf) do -- the log's pools: the client's UnitPowerMax (the loop's powerMax knob)
            if pt == us.pt then
                us.powerMax = m
            elseif us.res[pt] then
                us.res[pt].max = m
            else
                us.res[pt] = { cur = start0[pt] or m, max = m }
                us.res0[pt] = us.res[pt].cur
            end
        end
        us.lastSwing, us.landAt = { 0, 0 }, { 0, 0 }
        local mob = W.add(entities.new({
            guid = "Creature-1" .. (wo.tag or ""),
            kind = "mob",
            level = R.targetLevel or wo.level,
            health = R.mobHealth,
            creatureType = R.creatureType or wo.creatureType,
        }))
        mob.target, us.target = us, mob
        local env = W.add(entities.new({ guid = "Other-replay", level = wo.level })) -- the execute phase's source
        for pt, rate in pairs(wo.regen or {}) do -- the client's rate reads only: the log's after-values are the truth
            W.rates[pt] = rate
        end
        for pt, f in pairs(wo.fsr or {}) do
            W.fsr[pt] = f
        end
        if R.manaIdle then -- the log's own mana regen wins over the content's: { spirit part, mp5 part } (W.fsr)
            W.rates[0], W.fsr[0] = 0, { R.manaIdle - R.manaCasting, R.manaCasting }
        end
        local function show(dst, id, a) -- an aura change the client sees (not a hidden one)
            if not hidden[id] then
                W.emit({
                    kind = "aura",
                    dst = dst,
                    aura = id,
                    stacks = a and a.stacks or 0,
                    expires = a and a.expires or 0,
                    duration = a and a.duration or 0,
                })
            end
        end
        local function stealthed() -- IsStealthed: any stealth aura of ours up
            for id in pairs(us.auras) do
                if stealthy[id] then
                    return true
                end
            end
            return false
        end
        local function apply(e)
            local T = W.t
            local key = (e.kind == "completed" or (e.kind == "casting" and e.id and e.cast > 0)) and keyFor(e)
            -- a cooldown ends at its cast's log timestamp plus the cooldown, as wowsims's does, not at the line's place
            -- within the timestamp (M.EPS each): else the next cast's decision, line 1 of its timestamp, still reads it
            -- running (the ready-time ruling, timing.lua)
            local cdk = key and cd[key] > 0 and cd[key] - (T - (R.pull + e.t)) or 0
            if key and not e.id then -- an item: its cooldown only
                if cd[key] > 0 then
                    us.cdUntil[key] = T + cdk
                end
            elseif not key and e.kind == "completed" and e.item then -- an unmapped item's use: still our cast
                W.emit({ kind = "cast", src = us, dst = mob, spell = M.UNMAPPED_SPELL })
            elseif key and e.kind == "casting" then -- a hard cast's start: its cast bar, the GCD from now
                W.emit({
                    kind = "castStart",
                    src = us,
                    spell = e.id,
                    ends = T + e.cast,
                    gcd = e.gcd > 0 and e.gcd or nil,
                })
            elseif key then
                local sh = shared[key]
                W.emit({
                    kind = "cast",
                    src = us,
                    dst = mob,
                    spell = e.id,
                    ids = sh and sh.ids or rankIDs[key],
                    cd = cdk,
                    gcd = (e.cast or 0) == 0 and (e.gcd or 0) > 0 and e.gcd or nil,
                    order = 1,
                    hard = (e.cast or 0) > 0 or nil,
                    chanEnds = e.chanEnd,
                })
                if e.chanEnd then
                    W.at(e.chanEnd, function()
                        W.emit({ kind = "channelStop", src = us, spell = e.id })
                    end)
                end
                if cd[key] > 0 then
                    us.cdUntil[key] = T + cdk
                    for _, k in ipairs(sh and sh.keys or {}) do
                        us.cdUntil[k] = T + cdk
                    end
                end
                local tt = totems[key]
                if tt then
                    W.summonTotem(us, tt[1], tt[2], e.id)
                end
            elseif e.kind == "move" then
                W.moveTo(us, e.distance)
            elseif e.kind == "power" then
                local pt = M.POWER[e.name]
                if pt and (pt == us.pt or us.res[pt]) then
                    local delta = e.to - W.res(us, pt)
                    if delta ~= 0 then
                        W.emit({
                            kind = "gain",
                            src = us,
                            pt = pt ~= us.pt and pt or nil,
                            rage = delta > 0 and delta or nil,
                            cost = delta < 0 and -delta or nil,
                        })
                    end
                end
            elseif e.kind == "aura" and form[e.id] and e.unit == "player" then
                if e.verb ~= "faded" then
                    W.setForm(us, form[e.id])
                elseif us.form == form[e.id] then
                    W.setForm(us, 0)
                end
            elseif e.kind == "aura" and (dur[e.id] or hidden[e.id]) then
                local dst = e.unit == "target" and mob or us
                local was = stealthy[e.id] and dst == us and stealthed()
                if e.verb == "faded" then
                    dst.auras[e.id] = nil
                    show(dst, e.id, nil)
                else
                    local d = e.d or dur[e.id] or 3600 -- a refresh re-reports its new expiry; a fade is a removal
                    local cur = dst.auras[e.id]
                    local a = { stacks = cur and cur.stacks or 1, expires = T + d, duration = d }
                    dst.auras[e.id] = a
                    show(dst, e.id, a)
                end
                if stealthy[e.id] and dst == us and stealthed() ~= was then -- IsStealthed flips: UPDATE_STEALTH
                    W.emit({ kind = "stealthed", on = not was })
                end
            elseif e.kind == "stacks" and e.to > 0 then
                local dst = e.unit == "target" and mob or us
                local a = dst.auras[e.id]
                if a then
                    a.stacks = e.to
                    show(dst, e.id, a)
                end
            elseif e.kind == "hit" then
                local amount = math.min(e.amount, math.max(0, mob.health - 1)) -- the mob never dies
                if e.act ~= "WOUND" then
                    us.avoidAt[e.act] = T
                end
                if e.what == "swing" then
                    us.lastSwing[e.hand] = T
                    local sw = W.emit({
                        kind = "swing",
                        src = us,
                        dst = mob,
                        hand = e.hand,
                        act = e.act,
                        flag = e.flag,
                        amount = amount,
                        school = 1,
                        speed = R.speed,
                        ours = true,
                    })
                    W.at(T + M.LAND[e.hand], function() -- its outcome a landing lag later; rage at the swing
                        W.emit({
                            kind = "land",
                            src = us,
                            dst = mob,
                            hand = e.hand,
                            act = e.act,
                            flag = e.flag,
                            amount = amount,
                            school = 1,
                            swing = sw,
                        })
                    end)
                else
                    W.emit({
                        kind = e.what,
                        src = us,
                        dst = mob,
                        act = e.act,
                        flag = e.flag,
                        amount = amount,
                        school = 1,
                    })
                end
            end
        end
        -- a Completed line carries its Casting line's cast time and GCD
        local lastCast = {}
        for _, e in ipairs(p.ev) do
            local id = tostring(e.id or ("item" .. tostring(e.item))) .. ":" .. (e.tag or 0)
            if e.kind == "casting" then
                lastCast[id] = e
            elseif e.kind == "completed" and lastCast[id] then
                e.cast, e.gcd = lastCast[id].cast, lastCast[id].gcd
            end
            W.at(e.wt, function()
                apply(e)
            end)
        end
        if o.distance then
            W.at(0, function()
                W.moveTo(us, o.distance)
            end)
        end
        W.at(0.1, function() -- out of combat: the caches and the target (after the opening state at 0)
            W.emit({ kind = "prepull" })
        end)
        W.at(R.pull, function()
            W.emit({ kind = "pull" })
        end)
        W.at(start, function() -- the execute phase: the mob at 20% (another source's wound, not ours)
            local floor20 = math.floor(M.TAIL * mob.healthMax)
            if mob.health > floor20 then
                W.emit({
                    kind = "spell",
                    src = env,
                    dst = mob,
                    act = "WOUND",
                    flag = "",
                    amount = mob.health - floor20,
                    school = 1,
                })
            end
        end)
        W.at(R.pull + R.duration, function()
            for _, e in ipairs(W.ents) do
                e.stopped = true
            end
            W.emit({ kind = "stop" })
        end)
        W.stopAt, W.after = R.pull + R.duration, 0
        return W
    end

    return R
end

return M
