-- tests/Game/harness/observer.lua (harness design §3.1, layer 4): turns the world's true stream into what the client
-- shows OUR character, as flat arrays the drive loop fires through fake_api. The only place that encodes the client;
-- every rule names its log (P = docs/research/2026-10-16-swing-outcome-pairing.md, G = the group captures doc, U = the
-- UNIT_COMBAT research), and a rule without one is UNMEASURED with a knob in DEFAULTS.
local fs = require("Game.State.helpers.fake_spec")
local fake = require("Game.State.helpers.fake_api")

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
    -- A secret-free client (the headless loop's oracle, design §4/D4): our power (`powerType`, its event token
    -- `powerToken`), the target's health and our cooldown times plain, the target's auras listed (no auraError). The
    -- events are the same; usability without delay is the caller's `usableDelay = 0`.
    plain = false,
    gcdSpell = nil, -- the spell whose cooldown is the GCD (the addon's constant; nil: no GCD answers)
    powerType = 1,
    powerToken = "RAGE",
    -- Power reads by type: { [powerType] = "always" | "ooc" | "never" } (UnitPower plain always, out of combat only, or
    -- never: the swing-paid type's default, as measured in combat); "always" and "ooc" answer each change with
    -- UNIT_POWER_FREQUENT and the type's token in `powerTokens` ({ [powerType] = token }; default `powerToken`).
    plainPower = false,
    powerTokens = false,
    powerMax = false, -- UnitPowerMax answers the world's pools at the out-of-combat reads (the replay's: the log's)
    regenRead = true, -- GetPowerRegenForPowerType answers the true rate out of combat (probe W), secret in combat
    playerSpeed = false, -- UnitAttackSpeed("player") answers our weapons' periods with the damage cache (out of combat)
    forms = false, -- the client's forms (index to spell ID: the content's), answered once
    -- 2026-10-22 captures (unit-registry spec §6.1): Action Targeting off by default (softenemy then never fires);
    -- the DELAYED pushback row is opt-in (it moves the player's UNIT_COMBAT 0.37 s later).
    actionTargeting = false,
    pushback = false,
    enterCombat = false, -- PLAYER_ENTER_COMBAT at the pull (K10: the first swing's mark, Task 9's T.first)
    firstLag = nil, -- the first main-hand swing's landing lag (K10; probe U10's one sample: 989 ms)
    -- A kill's shape by kind (s, from the kill truth; spec §2.5): the death events after the blow; a white swing's
    -- clear after its swing (its row comes at the landing lag, on the corpse); a projectile's clear after the death and
    -- its row after the clear (11-36 ms measured); an instant's clear after its row.
    -- A white-swing kill (the kill-events capture): PARTY_KILL at the swing, the death +2 ms, the target none +4 ms; the
    -- 100 ms clear is an instant strike's, after its row (Rogue capture b).
    killTiming = { died = 0.002, meleeClear = 0.004, flightClear = 0.002, flightRow = 0.020, strikeClear = 0.100 },
    killTokens = { melee = { "softinteract" }, flight = { "plate", "target", "softinteract" } },
    -- A secret-free client's target health after our white swing: at the swing (true, the measured model's default)
    -- or at its landing row (false). UNMEASURED: probe U12 (does the execute usability flag flip at the swing or at
    -- the row). shortcut: the usability answers (k.usable) read the world's true health at the swing either way;
    -- upgrade them to the client's view if U12 measures the row.
    healthAtSwing = true,
    -- The providers' measured shapes (providers spec §4.2), events only, from W.mrng: `meter` the damage meter's
    -- DAMAGE_METER_COMBAT_SESSION_UPDATED groups (DM research §2: a hit swing of the group 0-11 ms after it, none for an
    -- avoid; spells and procs in their row's frame, ticks 1-2 ms; type 7 at a hit on the group), `viewer` the Cooldown
    -- Manager's item edges 3-5 ms after an aura of ours (CV research §2), `takenLag` moves the hit row on us (s; type 7
    -- leads it by 0.39-0.57 s in game), `group` false: the other sources are strangers (their hits never tick).
    meter = false,
    viewer = false,
    takenLag = 0,
    group = true,
}

M.COMBAT_END = 1.0 -- s from a kill to PLAYER_REGEN_ENABLED when no attacker is left (Rogue kill-events capture)
M.PUSHBACK = 0.5 -- s a hit on us adds to our hard cast's bar (DELAYED's moved @casting; UNMEASURED)
M.FRAME = 1e-4 -- seconds: one update's events (a replay's lines of one timestamp sit 1e-6 apart; a strike's 1 ms is the next)

-- Our spells as the fake spec's (its costs: the usability answers).
M.SPELLS = {
    STRIKE = fs.SPENDER_B,
    DOT = fs.SPENDER_C,
    CAST = fs.SPENDER_A,
    OTHER = 1,
    INSTANT = fs.SPENDER_F,
    BOLT = fs.SPENDER_P,
    DOTI = fs.SPENDER_M,
    TICKS = fs.SPENDER_S,
    NONE = fs.SPENDER_N,
    BOGUS = fs.SPENDER_Q,
    CHAN = fs.SPENDER_H,
    POTION = 999999, -- no ability's: an unmapped success
}
M.COSTS = { { fs.SPENDER_A, 10 }, { fs.SPENDER_B, 15 }, { fs.SPENDER_C, 10 } }

--- Our landing lag (the `land` of behaviours.melee) under knobs `k`: the time from a swing of `hand` at `t` to its
--- outcome.
function M.lag(k)
    k = k or M.DEFAULTS
    local firstDone = false
    return function(W, e, hand, t)
        local r = W.rng
        if hand == 1 and k.firstLag and not firstDone then
            firstDone = true
            return k.firstLag -- U10: the first swing of a combat (one sample: 989 ms)
        end
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
--- `@current` IsCurrentSpell, `@aura` an aura list entry, `@itemCount` C_Item.GetItemCount, `@pet` the pet unit and
--- its power, `@petPower`, `@stats` UnitStat's values, `@stealthed` IsStealthed, `@dead`, `@cooldown`, `@power`, `@regen`, `@attackSpeed`,
--- `@rangedSpeed`, `@forms`, `@distance` the range checks' yards), or `@truth` our true power after an event. It draws nothing from `W.rng` (the behaviours roll every
--- random choice and record it on the truth event), so batch and incremental streams of one world are equal for
--- power-only answers (in batch, a list answer that reads `W` sees the finished world at every time).
--- `k.usable`: true (the fake spec's COSTS against our power) or a list { { spellID, fn(W, us, power, view) -> ok,
--- short } } (the content's): IsSpellUsable's two answers (usable; unusable for lack of power), `@usable` 1, 2 or 3
--- (unusable for another reason); `power` is the client's view of our swing-paid power and `view[pt]` of each other
--- type's (a gain `usableDelay` late, a spend at once). Each answer is evaluated at every power change and, stepping,
--- at each step's end (an aura or a target's health may flip it).
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
    s.src, s.hand, s.swingT, s.actor, s.castT = {}, {}, {}, {}, {}
    local obs = { s = s }
    local list, seq = {}, 0
    local function push(t, ev, a1, a2, a3, a4, a5, src, hand, swingT, actor, castT)
        seq = seq + 1
        list[#list + 1] = { t, seq, ev, a1, a2, a3, a4, a5, src or 0, hand or 0, swingT or 0, actor or 0, castT or 0 }
    end
    local function spellID(name)
        return M.SPELLS[name] or name -- a real ID (the content's) passes as is
    end
    -- (providers spec §4.2) a damage group: types 0, 1, 10 for the session, then the same for session 0 (DM §1)
    local session = 200
    local function group(t)
        for _, sid in ipairs({ session, 0 }) do
            for _, ty in ipairs({ 0, 1, 10 }) do
                push(t, "DAMAGE_METER_COMBAT_SESSION_UPDATED", ty, sid)
            end
        end
    end
    local function inGroup(e)
        return e == us or (k.group and party[e] ~= nil)
    end
    -- The meter's events for truth event `ev` (k.meter): added events only, so the stream without them is today's.
    -- A row while a group is still pending (its time at or after the row's) joins that batch: same-frame rows share
    -- one group (DM §2: a proc 2 ms after its swing, in the swing's group); otherwise a new group `lo`-`hi` ms on.
    local pending = -1
    local function groupFor(t, lo, hi)
        if pending >= t then
            return
        end
        pending = t + W.mrng.int(lo, hi) / 1000
        group(pending)
    end
    local function meter(t, ev)
        if ev.act ~= "WOUND" then
            return
        end
        local kind = ev.kind
        if kind == "swing" and inGroup(ev.src) then -- ours or a partner's, any hand; an avoid never (DM §2)
            groupFor(t, 0, 11)
        elseif (kind == "spell" or kind == "proc" or kind == "strike") and inGroup(ev.src) then
            groupFor(t, 3, 14)
        elseif kind == "tick" and inGroup(ev.src) then
            groupFor(t, 1, 2)
        end
        if (kind == "swing" or kind == "spell") and ev.dst and inGroup(ev.dst) and not inGroup(ev.src) then
            push(t, "DAMAGE_METER_COMBAT_SESSION_UPDATED", 7, session) -- a hit on the group, at its truth time
        end
    end
    -- our hard cast's and channel's castGUID numbers (their start's, carried to the success and the stop), and the
    -- hard cast's spell
    local hardN, chanN, castSpell = 0, 0, nil
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
            if k.actionTargeting then
                out[#out + 1] = "softenemy"
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
    local castOpen, castFrom, castTo = false, 0, 0 -- our hard cast in progress and its bar (DELAYED, pushback)
    -- One player cast event, echoed on targettarget (another castBarID) while our target targets us: every kind of
    -- them (captures b and c: SENT, START, SUCCEEDED, STOP, FAILED, INTERRUPTED, DELAYED).
    local function castEv(t, onUs, name, g, id, a4, a5)
        push(t, name, "player", g, id, a4, a5)
        if onUs then
            push(t, name, "targettarget", g, id, a4 and (a4 .. "-tt") or nil, a5 and (a5 .. "-tt") or nil)
        end
    end
    local function sent(t, onUs, g, id)
        push(t, "UNIT_SPELLCAST_SENT", "player", "Mob", g, id)
        if onUs then
            push(t, "UNIT_SPELLCAST_SENT", "targettarget", "Mob", g, id)
        end
    end
    -- The tokens and time of a killing outcome (killTiming, killTokens); nil: the usual ones (an instant's).
    local function killShape(t, ev)
        local sw = ev.swing
        local kt = k.killTiming
        local list
        if ev.kind == "land" and sw and sw.killing then
            list = k.killTokens.melee -- at the landing lag, after the clear: the corpse only
        elseif ev.killing and ev.flight then
            t, list = t + kt.died + kt.flightClear + kt.flightRow, k.killTokens.flight
        end
        if not list then
            return nil
        end
        local toks = {}
        for _, tok in ipairs(list) do
            toks[#toks + 1] = tok == "plate" and plate[ev.dst] or tok
        end
        return t, toks
    end
    local cleared = {} -- [mob] = the time our target's kill cleared it: the corpse answers softinteract from then
    local function outcome(t, ev, src, hand, swingT)
        local toks = tokensOf(ev.dst, ev)
        local kt, ktoks = killShape(t, ev)
        if kt then
            t, toks = kt, ktoks
        elseif cleared[ev.dst] and t >= cleared[ev.dst] then -- after the clear "target" names nobody: the corpse's
            -- rows come on softinteract alone (kill-events capture 4820; spec §2.2). For a non-killing post-clear row
            -- this is a choice stronger than the measurement: capture b's 74805 came on the plate and soft
            toks = { "softinteract" }
        end
        if ev.dst == us and castOpen and k.pushback and ev.act == "WOUND" then
            -- shortcut: the bar moves on the client only (the world's cast still ends at its press's end); move the
            -- world's too when a suite reads the success's time under pushback
            castTo = castTo + M.PUSHBACK
            push(t, "@casting", castFrom * 1000, castTo * 1000)
            castEv(t, ev.onUs, "UNIT_SPELLCAST_DELAYED", "Cast-" .. hardN, spellID(castSpell), "Bar-" .. hardN)
            t = t + 0.37 -- the player's row comes about 0.37 s after DELAYED (capture b)
        end
        for _, tok in ipairs(toks) do
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
                idx[ev.src],
                ev.castT
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
        if k.actionTargeting then
            push(t, "@guid", "softenemy", tgt and tgt.guid)
        end
        push(t, "@unitIs", "targettarget", tgt and tt[tgt] == us and "player" or nil)
        if k.plainSpeed and tgt then
            push(t, "@speed", "target", tgt.weapons[1][3])
        end
        push(t, "PLAYER_TARGET_CHANGED")
    end
    -- UnitDamage read out of combat only (docs/superpowers/specs/2026-10-16-forever-protection-design.md §1.1); the
    -- attack speeds (Sources/Swing.lua, probe W PR2) and the regen rates (probe W: 10.001 a second out of combat) too.
    local function cache(t, ev)
        local d = ev.damage
        push(t, "@damage", d[1], d[2], d[3], d[4])
        if k.powerMax then -- UnitPowerMax, plain [W PR16]: the world's pools, not the character sheet's
            push(t, "@powerMax", us.pt, us.powerMax)
            for pt, r in pairs(us.res) do
                push(t, "@powerMax", pt, r.max)
            end
        end
        if k.playerSpeed and ev.speed then
            push(t, "@attackSpeed", ev.speed[1], ev.speed[2])
        end
        if ev.ranged then -- only a world with a ranged hand: the others' streams are unchanged
            push(t, "@rangedSpeed", ev.ranged)
        end
        if k.regenRead and ev.regen then
            for pt, r in pairs(ev.regen) do
                push(t, "@regen", pt, r, ev.regenCasting and ev.regenCasting[pt]) -- not casting, casting
            end
        end
        push(t, "PLAYER_EQUIPMENT_CHANGED")
    end
    local modes, tokens = k.plainPower or {}, k.powerTokens or {}
    local cur, inCombat = {}, false -- our true power by type as the stream has told it; the client's combat flag
    local spentT = -math.huge -- our latest spend's time (a gain in its frame is answered with it)
    local function plainPower(t, pt) -- a plain read of `pt` now, if its mode answers it
        local m = modes[pt]
        if m == "always" or (m == "ooc" and not inCombat) then
            push(t, "@power", pt, cur[pt])
            push(t, "UNIT_POWER_FREQUENT", "player", tokens[pt] or k.powerToken)
        end
    end
    -- our totem slots' truth: [slot] = the last "totem" event that filled it; `touched`: the slots ever summoned into,
    -- whose reads turn secret in combat (a stream with no totem stays as it was)
    local totems, touched = {}, {}
    local function totemRead(t, slot) -- GetTotemInfo: secret in combat [W PR12] (no spell: a secret answer)
        local tt = totems[slot]
        if inCombat and not k.plain then
            push(t, "@totem", slot)
        elseif tt then
            push(t, "@totem", slot, tt.spell, tt.start, tt.duration)
        else
            push(t, "@totem", slot, 0, 0, 0)
        end
    end
    local function combat(t, on) -- the plain-out-of-combat reads turn secret in combat and plain again after it
        inCombat = on
        if not k.plain then
            for slot = 1, 4 do
                if touched[slot] then
                    totemRead(t, slot)
                end
            end
        end
        for pt, m in pairs(modes) do
            if m == "ooc" then
                if on then
                    push(t, "@power", pt, nil)
                else
                    plainPower(t, pt)
                end
            end
        end
        if on and k.regenRead then
            for pt in pairs(W.rates or {}) do
                push(t, "@regen", pt, nil)
            end
        end
    end
    local castN = 0
    -- a cooldown's pending end (at or after `t`) whose start a restart or a reset supersedes: dropped, or it would end the
    -- new one (a restart on the old end's instant: that end's float sum lands a ulp after the new start)
    local function dropEnds(t, id)
        for i = #list, 1, -1 do
            local e = list[i]
            if e[1] >= t and e[3] == "@cooldown" and e[4] == id then
                table.remove(list, i)
            end
        end
    end
    local gcdEnd -- the latest GCD's falling edge: its flag and its event (the list entries)
    -- on cooldown and the GCD (the client's GCD spell, `k.gcdSpell`) from `t`: the flags plain (probe W PR4), the times
    -- secret but to a secret-free client
    local function cooldown(t, id, d)
        local gcdFlag = id == k.gcdSpell
        -- a GCD pressed on the last one's end: that end's float sum can land a ulp after this rise, so it moves
        -- back to it (its lower seq keeps it first)
        if gcdFlag and gcdEnd and gcdEnd[1][1] > t and gcdEnd[1][1] - t < 1e-6 then
            gcdEnd[1][1], gcdEnd[2][1] = t, t
        end
        if not gcdFlag then
            dropEnds(t, id)
        end
        if k.plain then
            push(t, "@cooldown", id, t, d)
            push(t + d, "@cooldown", id, 0, 0)
        else
            push(t, "@cooldown", id, fake.SECRET, fake.SECRET)
            push(t + d, "@cooldown", id)
        end
        local flag = list[#list]
        push(t, "SPELL_UPDATE_COOLDOWN")
        if gcdFlag then
            gcdEnd = { flag, flag } -- Forever sends no SPELL_UPDATE_COOLDOWN at a GCD's end
        else
            push(t + d, "SPELL_UPDATE_COOLDOWN")
        end
    end
    local deltas, dseq = {}, 0 -- our power's changes as the client's usability sees them: { answer time, delta, power type, true time, seq } (a
    -- form change: { t, form, "form", seq }; byTime orders by the last field)
    -- the answers' view of us: our form as of the answer's time (a form change is a delta), the rest live
    local now = setmetatable({}, { __index = us })
    for _, ev in ipairs(W.truth) do
        if ev.kind == "prepull" then
            now.form = ev.form
            break
        end
    end
    local function formDelta(t, form)
        dseq = dseq + 1
        deltas[#deltas + 1] = { t, form, "form", dseq }
    end
    local function read(ev)
        local t, kind = ev.t, ev.kind
        if kind == "prepull" then -- 0.5 s before the pull: the cache, then the target 0.1 s later
            formDelta(t, ev.form)
            if ev.form ~= 0 then -- a fight that starts in a form (the loop's consecutive fights)
                push(t, "@form", ev.form)
                push(t, "UPDATE_SHAPESHIFT_FORM")
            end
            cache(t, ev)
            targets(t + 0.1, ev)
            local v = ev.targets[us]
            if k.plain and v then
                push(t + 0.1, "@health", "target", v.health, v.healthMax)
            end
        elseif kind == "pull" then
            combat(t, true)
            push(t, "@combat", true)
            if not k.plain then
                push(t, "@auraError", "target", true) -- spec §3.1: the target's auras raise in combat
            end
            push(t, "PLAYER_REGEN_DISABLED")
            if k.enterCombat then
                push(t, "PLAYER_ENTER_COMBAT")
            end
        elseif kind == "stop" then
            push(t, "@combat", false)
            combat(t, false)
            if not k.plain then
                push(t, "@auraError", "target", false)
            end
            cache(t, ev)
            push(t, "PLAYER_REGEN_ENABLED")
        elseif kind == "form" then -- after its cast's success (Forms.lua, Q2)
            formDelta(t, ev.form)
            push(t, "@form", ev.form)
            push(t, "UPDATE_SHAPESHIFT_FORM")
            if ev.damage then -- out of combat: the caches read the form's own
                cache(t, ev)
            end
        elseif kind == "target" then
            targets(t, ev)
        elseif kind == "move" and ev.src == us then
            push(t, "@distance", "target", ev.distance)
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
            ev.castT = t -- the strike's outcome row is our cast's (the detection suite's truth, K2); its WOUND 0 frame is not
            local g, sid = "Cast-" .. castN, spellID(ev.spell)
            -- shortcut: the strike's SENT in its frame (the client's comes at the queueing press); move it to the
            -- "queue" event when a suite reads the gap
            sent(t, ev.onUs, g, sid)
            if ev.order == 1 then -- P log 1's order, then the brief's: swing and success either way round
                castEv(t, ev.onUs, "UNIT_SPELLCAST_SUCCEEDED", g, sid)
                outcome(t, frame, 1)
                push(t, "PLAYER_SWING", ev.speed, 0)
            else
                push(t, "PLAYER_SWING", ev.speed, 0)
                outcome(t, frame, 1)
                castEv(t, ev.onUs, "UNIT_SPELLCAST_SUCCEEDED", g, sid)
            end
            outcome(t + 0.001, ev, 1)
            for _, id in ipairs(ev.ids or { spellID(ev.spell) }) do
                push(t, "@current", id, false) -- IsCurrentSpell: no longer queued
                if (ev.cd or 0) > 0 then -- a queued strike's cooldown, from its swing (every rank)
                    dropEnds(t, id)
                    push(t, "@cooldown", id, k.plain and t or fake.SECRET, k.plain and ev.cd or fake.SECRET)
                    if k.plain then
                        push(t + ev.cd, "@cooldown", id, 0, 0)
                    else
                        push(t + ev.cd, "@cooldown", id)
                    end
                end
            end
            if (ev.cd or 0) > 0 then
                push(t, "SPELL_UPDATE_COOLDOWN")
                push(t + ev.cd, "SPELL_UPDATE_COOLDOWN")
            end
        elseif kind == "totem" and ev.src == us then -- our summon or its end: the slot's read, then its event
            totems[ev.slot], touched[ev.slot] = ev.start > 0 and ev or nil, true
            totemRead(t, ev.slot)
            push(t, "PLAYER_TOTEM_UPDATE", ev.slot)
        elseif kind == "queue" or kind == "unqueue" then -- our on-next-swing press (IsCurrentSpell, plain)
            for _, id in ipairs(ev.ids or { spellID(ev.spell) }) do
                push(t, "@current", id, kind == "queue")
            end
        elseif kind == "aura" then -- ours on the player (plain), ours on the target (raising in combat)
            local unit = ev.dst == us and "player" or (ev.dst == ev.ourTarget and "target" or nil)
            if unit then
                push(t, "@aura", unit, ev.aura, ev.stacks, ev.expires, ev.duration)
                push(t, "UNIT_AURA", unit)
                if k.viewer then -- the Cooldown Manager's item shows or hides 3-5 ms later (CV §2)
                    push(t + W.mrng.int(3, 5) / 1000, "@viewer", unit, ev.aura, ev.stacks > 0)
                end
            end
        elseif kind == "item" and ev.src == us then -- a bag count, plain [W PR13]; nothing reads its BAG_UPDATE
            push(t, "@itemCount", ev.item, ev.count)
        elseif kind == "pet" and ev.src == us then -- our pet unit, plain [W PR14], then the client's UNIT_PET
            push(t, "@pet", ev.up, ev.pt, ev.petPower)
            push(t, "UNIT_PET", "player")
        elseif kind == "petPower" and ev.src == us then -- UnitPower("pet") (unprobed with a pet out: plain here; a
            -- pet's UNIT_POWER_FREQUENT reaches no frame of ours, the belief's poll 13 reads it)
            push(t, "@petPower", ev.petPower)
        elseif kind == "stealthed" then -- IsStealthed (plain: no SecretWhen* flag) and its event
            push(t, "@stealthed", ev.on)
            push(t, "UPDATE_STEALTH")
        elseif kind == "kill" then -- 2026-10-22 kill-events capture: PARTY_KILL with the blow when ours; UNIT_DIED and
            -- PLAYER_TARGET_DIED `died` later; the clear by kind (killTiming); the corpse answers softinteract
            local kt, c = k.killTiming, ev.cause or {}
            local clear = t + kt.strikeClear -- an instant's (its row came in its frame)
            if c.kind == "swing" then
                clear = t + kt.meleeClear
            elseif c.flight then
                clear = t + kt.died + kt.flightClear
            end
            if ev.src == us then
                push(t, "PARTY_KILL", us.guid, ev.dst.guid)
            end
            push(t + kt.died, "UNIT_DIED", ev.dst.guid)
            if ev.dst == ev.ourTarget then
                push(t + kt.died, "PLAYER_TARGET_DIED")
                push(t + kt.died, "@dead", "target", true)
                push(clear, "@guid", "target", nil)
                push(clear, "@guid", "softinteract", ev.dst.guid)
                cleared[ev.dst] = clear
                push(clear, "PLAYER_TARGET_CHANGED")
                push(clear, "UNIT_HEALTH", "target")
            end
            local left = false
            for _, e in ipairs(mobs) do
                left = left or (not e.dead and e.target == us)
            end
            if not left then -- after the killing row (Rogue capture: about 1 s after the kill)
                local te = t + M.COMBAT_END
                push(te, "@combat", false)
                combat(te, false)
                if not k.plain then
                    push(te, "@auraError", "target", false)
                end
                push(te, "PLAYER_REGEN_ENABLED")
            end
        -- our cast IDs plain (docs/superpowers/specs/2026-10-16-forever-protection-design.md §1.1)
        elseif kind == "cast" and ev.src == us then -- others' secret (G 49873)
            castN = castN + 1
            local gcdFirst = ev.gcd and k.gcdSpell and ev.order == 2
            if gcdFirst then
                cooldown(t, k.gcdSpell, ev.gcd)
            end
            local guid, bar, id = "Cast-" .. castN, nil, spellID(ev.spell)
            local tc = t + (ev.jitter or 0) -- cast-event latency (K10), recorded on the truth by the behaviour
            if ev.hard then -- the start's castGUID; UnitCastingInfo answers nothing from the success on
                castN, guid, bar, castOpen = castN - 1, "Cast-" .. hardN, "Bar-" .. hardN, false
                push(tc, "@casting", nil)
            elseif ev.chanEnds then
                chanN = castN
                sent(tc, ev.onUs, guid, id)
                push(tc, "@channel", t * 1000, ev.chanEnds * 1000)
                castEv(tc, ev.onUs, "UNIT_SPELLCAST_CHANNEL_START", guid, id)
            else
                sent(tc, ev.onUs, guid, id) -- an instant's SENT, the same ms
            end
            castEv(tc, ev.onUs, "UNIT_SPELLCAST_SUCCEEDED", guid, id, bar)
            if (ev.cd or 0) > 0 then
                for _, rid in ipairs(ev.ids or { id }) do
                    cooldown(t, rid, ev.cd)
                end
            end
            if ev.gcd and k.gcdSpell and not gcdFirst then
                cooldown(t, k.gcdSpell, ev.gcd)
            end
            if ev.hard then
                castEv(tc, ev.onUs, "UNIT_SPELLCAST_STOP", guid, id, bar)
            end
        elseif kind == "castStart" and ev.src == us then -- our hard cast: SENT, UnitCastingInfo, START, the GCD
            castN = castN + 1
            hardN, castSpell, castOpen, castFrom, castTo = castN, ev.spell, true, t, ev.ends
            local g, id, bar = "Cast-" .. castN, spellID(ev.spell), "Bar-" .. castN
            sent(t, ev.onUs, g, id)
            push(t, "@casting", t * 1000, ev.ends * 1000)
            castEv(t, ev.onUs, "UNIT_SPELLCAST_START", g, id, bar)
            if ev.gcd and k.gcdSpell then
                cooldown(t, k.gcdSpell, ev.gcd)
            end
        elseif kind == "castStop" and ev.src == us then -- capture b: a death is FAILED then STOP in one ms, then three
            -- INTERRUPTED with no castBarID 0.15 s later; a move is INTERRUPTED (castBarID 5th), STOP 1 ms later, then two;
            -- each echoed on targettarget while our target targets us
            local g, id, bar = "Cast-" .. hardN, spellID(ev.spell), "Bar-" .. hardN
            castOpen = false
            push(t, "@casting", nil)
            if ev.cause == "move" then
                castEv(t, ev.onUs, "UNIT_SPELLCAST_INTERRUPTED", g, id, nil, bar)
                castEv(t + 0.001, ev.onUs, "UNIT_SPELLCAST_STOP", g, id, bar)
                for _ = 1, 2 do
                    castEv(t + 0.15, ev.onUs, "UNIT_SPELLCAST_INTERRUPTED", g, id, nil, nil)
                end
            else
                castEv(t, ev.onUs, "UNIT_SPELLCAST_FAILED", g, id, bar)
                castEv(t, ev.onUs, "UNIT_SPELLCAST_STOP", g, id, bar)
                for _ = 1, 3 do
                    castEv(t + 0.15, ev.onUs, "UNIT_SPELLCAST_INTERRUPTED", g, id, nil, nil)
                end
            end
        elseif kind == "refused" and ev.src == us then -- a cast refused at its start (range, line of sight): K15
            castN = castN + 1
            local g, id = "Cast-" .. castN, spellID(ev.spell)
            sent(t, ev.onUs, g, id)
            castEv(t, ev.onUs, "UNIT_SPELLCAST_FAILED", g, id, nil)
        elseif kind == "plateOff" then -- soft-targeting log: the removal still answers the GUID; the plate goes after
            push(t, "NAME_PLATE_UNIT_REMOVED", plate[ev.mob])
            push(t + 0.001, "@guid", plate[ev.mob], nil)
        elseif kind == "plateOn" then
            push(t, "@guid", plate[ev.mob], ev.mob.guid)
            push(t, "NAME_PLATE_UNIT_ADDED", plate[ev.mob])
        elseif kind == "channelStop" and ev.src == us then -- its end or a clip: UnitChannelInfo empty, then the stop
            push(t, "@channel", nil)
            castEv(t, ev.onUs, "UNIT_SPELLCAST_CHANNEL_STOP", "Cast-" .. chanN, spellID(ev.spell))
        elseif kind == "cdreset" and ev.src == us then -- a cooldown finished early (W.resetCooldown): every rank ready
            for _, id in ipairs(ev.ids) do
                dropEnds(t, id)
                push(t, "@cooldown", id, k.plain and 0 or nil)
            end
            push(t, "SPELL_UPDATE_COOLDOWN")
        elseif kind == "cast" and party[ev.src] then
            push(t, "UNIT_SPELLCAST_SUCCEEDED", party[ev.src], fake.SECRET, fake.SECRET)
        elseif kind == "proc" and ev.src == us then -- G5: the wound on the target, then a heal of the same amount on us, same ms
            outcome(t, ev, 1)
            outcome(t, { dst = us, onUs = ev.onUs, act = "HEAL", amount = ev.amount, school = 1 }, 0)
        elseif ev.act and ev.dst then -- another source's outcome, our DoT's tick, a hit on us or on someone else
            local tr = t
            if (k.takenLag or 0) > 0 and ev.dst == us and ev.act == "WOUND" then -- the hit row on us, later (DM §2)
                tr = t + k.takenLag + W.mrng.next() * 0.24 - 0.12
            end
            outcome(tr, ev, (ev.src == us) and 1 or 2)
        end
        if k.meter then
            meter(t, ev)
        end
        local hv = ev -- whose health a secret-free client reads now: our white swing's at its row (healthAtSwing off)
        if not k.healthAtSwing and ev.ours then
            hv = nil
        elseif not k.healthAtSwing and kind == "land" and ev.swing and ev.swing.health then
            hv = ev.swing
        end
        if k.plain and hv and hv.health and ev.dst == ev.ourTarget then -- a secret-free client's target health
            push(t, "@health", "target", hv.health, ev.dst.healthMax)
        end
        if ev.power or ev.resCur then
            local pt = ev.resCur and ev.pt or us.pt
            cur[pt] = ev.resCur or ev.power
            if k.plain and ev.power then -- a secret-free client's power, and its event
                push(t, "@power", k.powerType, ev.power)
                push(t, "UNIT_POWER_FREQUENT", "player", k.powerToken)
            end
            plainPower(t, pt)
            dseq = dseq + 1
            local d = (ev.rage or 0) - (ev.cost or 0)
            -- a gain in the frame of a spend reaches the answers with it, either order (UNMEASURED: one server update
            -- carries both, as an avoid's refund with its cost or a swing's rage with a press at its instant)
            local when = t + k.usableDelay
            if ev.cost then
                when, spentT = t, t
                for _, x in ipairs(deltas) do
                    if x[3] ~= "form" and x[1] > t and t - x[4] < M.FRAME then
                        x[1] = t
                    end
                end
            elseif t - spentT < M.FRAME then
                -- the frame's answers wait for this gain: the spend's (and what moved to it) at this gain's time, so
                -- no answer shows a gain before it happened
                when = t
                for _, x in ipairs(deltas) do
                    if x[3] ~= "form" and x[1] >= spentT and x[1] < t and t - x[4] < M.FRAME then
                        x[1] = t
                    end
                end
            end
            deltas[#deltas + 1] = { when, d, pt, t, dseq }
            if ev.power then
                push(t, "@truth", ev.power) -- the metrics' truth (harness design §3.3), no client answer
            end
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
                    return p >= cost, p < cost
                end,
            }
        end
    end
    local usable, power, view = {}, us.power0 or 0, {} -- the client's view of our power from the start (`power0`)
    for pt, v in pairs(us.res0 or {}) do
        view[pt], cur[pt] = v, v
    end
    local function answer(t)
        local flipped = false
        for _, u in ipairs(answers) do
            local ok, short = u[2](W, now, power, view)
            local st = ok and 1 or (short and 2 or 3)
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
    if answers then -- the answers before anything happens (no event: the client's state at login)
        for _, u in ipairs(answers) do
            local ok, short = u[2](W, now, power, view)
            usable[u[1]] = ok and 1 or (short and 2 or 3)
            push(0, "@usable", u[1], usable[u[1]])
        end
    end
    if k.plain then
        push(0, "@power", k.powerType, us.power)
    end
    -- the bags, the pet and the stats at login (no event)
    local ids = {}
    for id in pairs(us.bags0 or {}) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        push(0, "@itemCount", id, us.bags0[id])
    end
    if us.pet0 then
        push(0, "@pet", us.pet0.up, us.pet.pt, us.pet0.power)
    end
    if us.stats then
        push(0, "@stats", us.stats)
    end
    if k.forms then
        push(0, "@forms", k.forms)
    end
    for pt in pairs(modes) do -- the client's state at login (no event)
        cur[pt] = cur[pt] or 0
        if modes[pt] ~= "never" then
            push(0, "@power", pt, cur[pt])
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
            for i, d in ipairs(deltas) do
                if d[1] <= tEnd then
                    -- unclamped below: a spend can land before a delayed gain
                    if d[3] == "form" then
                        now.form = d[2]
                    elseif d[3] == us.pt or not us.res[d[3]] then
                        power = math.min(us.powerMax, power + d[2])
                    else
                        view[d[3]] = math.min(us.res[d[3]].max, view[d[3]] + d[2])
                    end
                    local nx = deltas[i + 1]
                    if not (nx and nx[1] == d[1]) then -- one answer per instant: a shift's form and its entry rule together
                        answer(d[1])
                    end
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
                s.src[i], s.hand[i], s.swingT[i], s.actor[i], s.castT[i] = e[9], e[10], e[11], e[12], e[13]
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
