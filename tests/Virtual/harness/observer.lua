-- tests/Virtual/harness/observer.lua (harness design §3.1, layer 4): turns the world's true stream into what the client
-- shows OUR character, as flat arrays the drive loop fires through fake_api. The only place that encodes the client;
-- every rule names its log (P = docs/research/2026-10-16-swing-outcome-pairing.md, G = the group captures doc, U = the
-- UNIT_COMBAT research), and a rule without one is UNMEASURED with a knob in DEFAULTS.
local fs = require("Virtual.State.helpers.fake_spec")
local fake = require("Virtual.State.helpers.fake_api")

local M = {}

M.DEFAULTS = {
    -- Our landing lag after PLAYER_SWING (P log 2, G5): main N(474 ms, 40 ms), a share in a uniform tail over 0.1-1.3 s
    -- (log 2: 5 of 36 outside 435-552 ms; G5: 5 of 22 outside 436-556 ms).
    main = { med = 0.474, sd = 0.04, tail = 0.15 },
    -- Off hand (G5 ruling): 0.703 s after its own swing, or 1.686 s after the latest main swing at or before it, or in
    -- the main hit's frame, else the tail. The shares sit within 0.15 of both logs' (log 2: 10 and 21 of 33; G5: 12 and
    -- 7 of 20, one in the main frame), which only their midpoint does.
    off = { own = 0.703, ownSd = 0.006, main = 1.686, mainSd = 0.004, pOwn = 0.452, pMain = 0.49, pFrame = 0.03 },
    tail = { 0.1, 1.3 },
    sameMs = 3 / 87, -- an avoid on the target in the same ms as our swing event, per swing (P log 2: 3 of 87); the
    -- behaviour rolls it (scenarios.lua passes this knob), the observer fires what it rolled
    usable = false, -- answer usability (true: the fake spec's COSTS against our power; a list: the content's); off: no pins
    usableDelay = 0.1, -- SPELL_UPDATE_USABLE after a true gain that flips an answer (UNMEASURED until G7); a spend at once
    targetTokens = { "plate", "target" }, -- "plate": the target's nameplateN (P logs 1-2: nameplate1 then target)
    plainSpeed = false, -- UnitAttackSpeed of a hostile plain (Attackers.lua notes: secret on Forever)
    secretUnitIs = false, -- UnitIsUnit("<plate>target", "player") answers secret (spec §3.1: plain or secret, UNMEASURED)
}

-- Our spells as the fake spec's (its costs: the usability answers).
M.SPELLS = { STRIKE = fs.SPENDER_B, DOT = fs.SPENDER_C, CAST = fs.SPENDER_A, OTHER = 1 }
M.COSTS = { { fs.SPENDER_A, 10 }, { fs.SPENDER_B, 15 }, { fs.SPENDER_C, 10 } }

--- Our landing lag (the `land` of behaviours.melee) under knobs `k`: the time from a swing of `hand` at `t` to its
--- outcome.
function M.lag(k)
    k = k or M.DEFAULTS
    return function(W, e, hand, t)
        local r = W.rng
        local function tail()
            return k.tail[1] + r.next() * (k.tail[2] - k.tail[1])
        end
        local o = k.off
        if hand == 1 then
            if r.chance(k.main.tail) then
                return tail()
            end
            return math.max(0.05, r.normal(k.main.med, k.main.sd))
        end
        local own = math.max(0.05, r.normal(o.own, o.ownSd))
        local x = r.next()
        if x < o.pOwn then
            return own
        elseif x < o.pOwn + o.pMain then
            local d = e.lastSwing[1] + r.normal(o.main, o.mainSd) - t
            return (e.lastSwing[1] > 0 and d > 0.05) and d or own
        elseif x < o.pOwn + o.pMain + o.pFrame then
            local d = e.landAt[1] - t
            return d > 0 and d or own
        end
        return tail()
    end
end

-- The token rank of a duplicate group (P logs 1-2, G, G5: nameplateN before target before softenemy/softinteract;
-- player before targettarget; partyN before nameplateN): the observer fires in this order, fixtures_spec checks it.
function M.rank(token)
    if token == "player" then
        return 1
    elseif token:match("^party") or token:match("^raid") then
        return 2
    elseif token:match("^nameplate") then
        return 3
    elseif token == "target" then
        return 4
    elseif token:match("^soft") then
        return 5
    end
    return 6 -- targettarget
end

--- An incremental observer of world `W` for our character (W.ents[1]) under knobs `k`. `obs.step(tEnd)` reads the truth
--- events at or before `tEnd` the world appended since the last step and appends to `obs.s` the client events at or
--- before `tEnd`, in time then sequence order (later ones, the usability delay or a strike's wound 1 ms on, wait for
--- a later step); it returns the first and last index it appended. The stream `obs.s`: { n, t[], ev[], a1..a5[], src[]
--- (1 ours, 2 another source, 3 unexplained, 0 not an outcome), hand[] (our swing's hand; 0 a cast's), swingT[] (our
--- swing's true time), actor[] (the entity index of a hit on us) }. An `ev` starting with "@" is a client-answer change
--- for the drive (`@damage` UnitDamage, `@usable`, `@form`, `@guid`, `@unitIs`, `@speed`, `@combat`, `@auraError`,
--- `@current` IsCurrentSpell, `@aura` an aura list entry, `@dead`), or `@truth` our true power after an event. It draws nothing from `W.rng` (the behaviours roll every
--- random choice and record it on the truth event), so batch and incremental streams of one world are equal.
--- `k.usable`: true (the fake spec's COSTS against our power) or a list { { spellID, fn(W, us, power) -> bool } }
--- (the content's); `power` is the client's view of ours (a gain `usableDelay` late, a spend at once). Each answer is
--- evaluated at every power change and, stepping, at each step's end (an aura or a target's health may flip it).
function M.new(W, k)
    k = k or M.DEFAULTS
    local us = W.ents[1]
    local idx, plate, party, mobs = {}, {}, {}, {}
    local nMob, nParty = 0, 0
    for i, e in ipairs(W.ents) do
        idx[e] = i
        if e.kind == "mob" then
            nMob = nMob + 1
            plate[e], mobs[nMob] = "nameplate" .. nMob, e
        elseif e.kind == "player" and i > 1 then
            nParty = nParty + 1
            party[e] = "party" .. nParty
        elseif e.kind == "pet" then
            party[e] = "partypet1"
        end
    end
    local s = { n = 0, t = {}, ev = {}, a1 = {}, a2 = {}, a3 = {}, a4 = {}, a5 = {} }
    s.src, s.hand, s.swingT, s.actor = {}, {}, {}, {}
    local obs = { s = s }
    local list, seq = {}, 0
    local function push(t, ev, a1, a2, a3, a4, a5, src, hand, swingT, actor)
        seq = seq + 1
        list[#list + 1] = { t, seq, ev, a1, a2, a3, a4, a5, src or 0, hand or 0, swingT or 0, actor or 0 }
    end
    -- player then targettarget (P log 1 1297); another player's on partyN (G).
    local function tokensOf(v, ev)
        local out = {}
        if v == us then
            out[1] = "player"
            if ev.onUs then
                out[2] = "targettarget"
            end
        elseif v == ev.ourTarget then
            for _, tok in ipairs(k.targetTokens) do
                out[#out + 1] = tok == "plate" and plate[v] or tok
            end
        elseif plate[v] then
            out[1] = plate[v]
        elseif party[v] then
            out[1] = party[v]
        end
        table.sort(out, function(a, b)
            return M.rank(a) < M.rank(b)
        end)
        return out
    end
    local function outcome(t, ev, src, hand, swingT)
        for _, tok in ipairs(tokensOf(ev.dst, ev)) do
            push(
                t,
                "UNIT_COMBAT",
                tok,
                ev.act,
                ev.flag or "",
                ev.amount or 0,
                ev.school or 1,
                src,
                hand,
                swingT,
                idx[ev.src]
            )
        end
    end
    local function targets(t, ev)
        local tt = ev.targets
        for _, e in ipairs(mobs) do
            local tok = plate[e]
            push(t, "@guid", tok, e.guid)
            if k.secretUnitIs then
                push(t, "@unitIs", tok .. "target", fake.SECRET)
            else
                push(t, "@unitIs", tok .. "target", tt[e] == us and "player" or nil)
            end
            if k.plainSpeed then
                push(t, "@speed", tok, e.weapons[1][3])
            end
        end
        for _, e in ipairs(mobs) do
            push(t, "NAME_PLATE_UNIT_ADDED", plate[e])
        end
        local tgt = tt[us] or nil
        push(t, "@guid", "target", tgt and tgt.guid)
        push(t, "@unitIs", "targettarget", tgt and tt[tgt] == us and "player" or nil)
        if k.plainSpeed and tgt then
            push(t, "@speed", "target", tgt.weapons[1][3])
        end
        push(t, "PLAYER_TARGET_CHANGED")
    end
    -- UnitDamage read out of combat only (docs/superpowers/specs/2026-10-16-forever-protection-design.md §1.1).
    local function cache(t, d)
        push(t, "@damage", d[1], d[2], d[3], d[4])
        push(t, "PLAYER_EQUIPMENT_CHANGED")
    end
    local function spellID(name)
        return M.SPELLS[name] or name -- a real ID (the content's) passes as is
    end
    local castN = 0
    local deltas, dseq = {}, 0 -- our power's changes as the client's usability sees them: { t, delta, seq }
    local function read(ev)
        local t, kind = ev.t, ev.kind
        if kind == "prepull" then -- 0.5 s before the pull: the cache, then the target 0.1 s later
            cache(t, ev.damage)
            targets(t + 0.1, ev)
        elseif kind == "pull" then
            push(t, "@combat", true)
            push(t, "@auraError", "target", true) -- spec §3.1: the target's auras raise in combat
            push(t, "PLAYER_REGEN_DISABLED")
        elseif kind == "stop" then
            push(t, "@combat", false)
            push(t, "@auraError", "target", false)
            cache(t, ev.damage)
            push(t, "PLAYER_REGEN_ENABLED")
        elseif kind == "form" then
            push(t, "@form", ev.form)
            push(t, "UPDATE_SHAPESHIFT_FORM")
        elseif kind == "target" then
            targets(t, ev)
        elseif kind == "swing" and ev.src == us then
            push(t, "PLAYER_SWING", ev.speed, ev.hand - 1)
            if ev.sameMs then -- the behaviour's roll (P log 2: 3 of 87)
                outcome(t, { dst = ev.ourTarget, ourTarget = ev.ourTarget, act = ev.sameMs, amount = 0 }, 3)
            end
        elseif kind == "land" then
            outcome(t, ev, 1, ev.hand, ev.swing.t)
        elseif kind == "strike" and ev.src ~= us then -- G 177249/177250: WOUND 0, then the damage 1 ms later
            outcome(t, { dst = ev.dst, ourTarget = ev.ourTarget, act = "WOUND", amount = 0, school = 1 }, 2)
            outcome(t + 0.001, ev, 2)
        elseif kind == "strike" then
            castN = castN + 1
            local frame = { dst = ev.dst, ourTarget = ev.ourTarget, act = "WOUND", amount = 0, school = 1 }
            if ev.order == 1 then -- P log 1's order, then the brief's: swing and success either way round
                push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
                outcome(t, frame, 1)
                push(t, "PLAYER_SWING", ev.speed, 0)
            else
                push(t, "PLAYER_SWING", ev.speed, 0)
                outcome(t, frame, 1)
                push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
            end
            outcome(t + 0.001, ev, 1)
            push(t, "@current", spellID(ev.spell), false) -- IsCurrentSpell: no longer queued
        elseif kind == "queue" or kind == "unqueue" then -- our on-next-swing press (IsCurrentSpell, plain)
            push(t, "@current", spellID(ev.spell), kind == "queue")
        elseif kind == "aura" then -- ours on the player (plain), ours on the target (raising in combat)
            local unit = ev.dst == us and "player" or (ev.dst == ev.ourTarget and "target" or nil)
            if unit then
                push(t, "@aura", unit, ev.aura, ev.stacks, ev.expires, ev.duration)
                push(t, "UNIT_AURA", unit)
            end
        elseif kind == "kill" then -- our target gone; out of combat when no living attacker is left
            if ev.dst == ev.ourTarget then
                push(t, "@dead", "target", true)
                push(t, "UNIT_HEALTH", "target")
            end
            local left = false
            for _, e in ipairs(mobs) do
                left = left or (not e.dead and e.target == us)
            end
            if not left then
                push(t, "@combat", false)
                push(t, "@auraError", "target", false)
                push(t, "PLAYER_REGEN_ENABLED")
            end
        -- our cast IDs plain (docs/superpowers/specs/2026-10-16-forever-protection-design.md §1.1)
        elseif kind == "cast" and ev.src == us then -- others' secret (G 49873)
            castN = castN + 1
            push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
            if ev.onUs then -- P log 1 1345, 4329-4330, 6532: also on targettarget while our target targets us
                push(t, "UNIT_SPELLCAST_SUCCEEDED", "targettarget", "Cast-" .. castN, spellID(ev.spell))
            end
        elseif kind == "cast" and party[ev.src] then
            push(t, "UNIT_SPELLCAST_SUCCEEDED", party[ev.src], fake.SECRET, fake.SECRET)
        elseif kind == "proc" and ev.src == us then -- G5: the wound on the target, then a heal of the same amount on us, same ms
            outcome(t, ev, 1)
            outcome(t, { dst = us, onUs = ev.onUs, act = "HEAL", amount = ev.amount, school = 1 }, 0)
        elseif ev.act and ev.dst then -- another source's outcome, our DoT's tick, a hit on us or on someone else
            outcome(t, ev, (ev.src == us) and 1 or 2)
        end
        if ev.power then
            dseq = dseq + 1
            deltas[#deltas + 1] = { t + (ev.cost and 0 or k.usableDelay), (ev.rage or 0) - (ev.cost or 0), dseq }
            push(t, "@truth", ev.power) -- the metrics' truth (harness design §3.3), no client answer
        end
    end
    -- usability: the content's answers, or the fake spec's costs against our power (as the client answers them)
    local answers = k.usable
    if answers == true then
        answers = {}
        for i, c in ipairs(M.COSTS) do
            local cost = c[2]
            answers[i] = {
                c[1],
                function(_, _, p)
                    return p >= cost
                end,
            }
        end
    end
    local usable, power = {}, 0
    local function answer(t)
        local flipped = false
        for _, u in ipairs(answers) do
            local st = u[2](W, us, power) and 1 or 2
            if usable[u[1]] ~= st then
                usable[u[1]] = st
                push(t, "@usable", u[1], st)
                flipped = true
            end
        end
        if flipped then
            push(t, "SPELL_UPDATE_USABLE")
        end
    end
    if answers then
        for _, u in ipairs(answers) do
            usable[u[1]] = 2
            push(0, "@usable", u[1], 2)
        end
    end
    local function byTime(a, b)
        return a[1] < b[1] or (a[1] == b[1] and a[#a] < b[#b])
    end
    local function bySeq(a, b)
        return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
    end
    local cursor = 0
    function obs.step(tEnd)
        local truth = W.truth
        while truth[cursor + 1] and truth[cursor + 1].t <= tEnd do
            cursor = cursor + 1
            read(truth[cursor])
        end
        if answers then
            table.sort(deltas, byTime)
            local keep = {}
            for _, d in ipairs(deltas) do
                if d[1] <= tEnd then
                    power = math.min(us.powerMax, power + d[2]) -- unclamped below: a spend can land before a delayed gain
                    answer(d[1])
                else
                    keep[#keep + 1] = d
                end
            end
            deltas = keep
            if tEnd < math.huge then
                answer(tEnd)
            end
        end
        table.sort(list, bySeq)
        local first, keep = s.n + 1, {}
        for _, e in ipairs(list) do
            if e[1] <= tEnd then
                local i = s.n + 1
                s.n = i
                s.t[i], s.ev[i], s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i] = e[1], e[3], e[4], e[5], e[6], e[7], e[8]
                s.src[i], s.hand[i], s.swingT[i], s.actor[i] = e[9], e[10], e[11], e[12]
            else
                keep[#keep + 1] = e
            end
        end
        list = keep
        return first, s.n
    end
    return obs
end

--- The whole client stream of a finished world `W` under knobs `k` (one step to the end of time).
function M.observe(W, k)
    local obs = M.new(W, k)
    obs.step(math.huge)
    return obs.s
end

return M
