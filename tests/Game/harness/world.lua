-- tests/Game/harness/world.lua (harness design §3.1, layer 3): runs every behaviour on one clock (a queue by time)
-- and records the TRUE event stream, with the effects the world applies itself (health, our rage). Test code: it
-- allocates freely; the drive loop (drive.lua) reads the observer's flat arrays, never this.
local rng = require("Game.harness.rng")
local behaviours = require("Game.harness.behaviours")
local roll = behaviours.roll

local M = {}

-- Our crit rate on an instant hit (W.hit): the white swings' measured rate.
M.CRIT = behaviours.RATES.crit
M.MELEE = 5 -- yards: our white swings' reach (wowsims's MaxMeleeRange)

--- The share of its cost ability `key` of class data `class` (Hekili.Class) gives back when avoided, as the belief reads
--- it: its `refundOnAvoid` (true: its resource meta's), or nil.
function M.refundOf(class, key)
    local a = class.abilities[key]
    local f = a and rawget(a, "refundOnAvoid")
    if f == true then
        local r = class.resources[a.spendType]
        f = r and r.state and r.state.meta and r.state.meta.refundOnAvoid
    end
    return type(f) == "number" and f or nil
end

-- The outcomes an ability of ours can roll on the target (a press's `outcomes`; wowsims/forever core/spell_outcome.go):
-- "melee" the special melee tables (OutcomeMeleeSpecialHit*, OutcomeMeleeWeaponSpecial*: miss, dodge, parry), "miss"
-- the ones with a miss roll only (OutcomeMeleeSpecialNoBlockDodgeParry*: from behind, Overpower; OutcomeRangedHit*),
-- "spell" a magic hit check (OutcomeMagicHit*: a miss, at the victim's `spellMiss`, else its melee miss), "none" no
-- roll (OutcomeAlwaysHit). The block a wowsims table can roll is a hit here (it lands).
M.OUTCOMES = {
    melee = { "miss", "dodge", "parry" },
    miss = { "miss" },
    spell = { "spellMiss" },
    none = {},
}

--- A new world. `seed` seeds its generator. Truth events: { t, kind, src, dst, hand, act, flag, amount, school, spell }
--- with kind "swing" (a white swing, its outcome rolled; ours land later as "land"), "land", "strike" (an
--- on-next-swing strike frame), "spell" (a spell's outcome), "tick", "proc", "cast", "castStart", "castStop" and "channelStop" (our hard
--- cast's start, its interrupt, our channel's end: W.press, W.endCasts), "item" (a bag count of ours: W.item), "pet" and "petPower" (our pet unit, its
--- power: W.summonPet, W.petGain), "prepull" (the cache and
--- target reads 0.5 s before the pull), "pull", "stop", "form", "buff", "target", "aura", "totem", "queue", "unqueue", "gain", "kill", "move",
--- "regen" and "decay" (a resource's continuous regen and out-of-combat decay, W.startRegen / W.startDecay). A gain
--- (`rage`) or spend (`cost`) of ours is of power type `pt` (default our `pt`, the swing-paid `power`; another type's
--- value after it: `ev.resCur`).
function M.new(seed)
    -- crng: the client-detail draws (the same-ms avoid, a strike frame's order) apart from the fight's own
    local W = { t = 0, q = {}, seq = 0, truth = {}, rng = rng.new(seed), crng = rng.new(seed + 7919), ents = {} }
    W.grng = rng.new(seed + 15485863) -- the GCD flag's order against its cast (W.press), apart from both
    W.mrng = rng.new(seed + 32452843) -- the meter and viewer shapes, apart from every other draw
    W.combat = false
    W.rates = {} -- [powerType] = regen per second (W.startRegen)
    W.fsr = {} -- [powerType] = { spirit, mp5, share?, mp5?, auras? } per second: the five-second rule's two parts (W.startRegen)
    W.distance = nil -- yards from our character to its target (W.moveTo; nil: no positions, every check in range)
    W.hitAtSwing = true -- our white wound takes health at the swing, its row a landing lag later (owner, 2026-10-22)
    W.parryHaste = true -- a parried attack pulls the parrier's next main-hand swing (parry-haste spec decision 63)
    W.crit = M.CRIT -- our crit rate on an instant hit or strike (W.rollOutcome; scenarios' `crit`)

    --- Runs `fn(W)` at time `t` (after everything already queued for `t`).
    function W.at(t, fn)
        W.seq = W.seq + 1
        local item, q = { t = t, seq = W.seq, fn = fn }, W.q
        local lo, hi = 1, #q + 1
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            local m = q[mid]
            if m.t < t or (m.t == t and m.seq < item.seq) then
                lo = mid + 1
            else
                hi = mid
            end
        end
        table.insert(q, lo, item)
    end

    --- Records a truth event at the clock (or at `ev.t`) and applies its effects: a wound takes health, our landed
    --- wound pays our rage (`ev.rage`), a cast spends it (`ev.cost`); a pull or stop keeps our weapon damage then.
    function W.emit(ev)
        ev.t = ev.t or W.t
        W.truth[#W.truth + 1] = ev
        local me = W.ents[1]
        if me then -- who our target is, and whether it targets us, at this event (the tokens that fire for it)
            ev.ourTarget, ev.onUs = me.target, me.target ~= nil and me.target.target == me
        end
        if ev.kind == "prepull" or ev.kind == "target" then -- whom each entity targets now (its tokens' answers)
            ev.targets = {}
            for _, e in ipairs(W.ents) do
                ev.targets[e] = e.target or false
            end
        end
        if ev.kind == "prepull" and me then -- our form at the start (the client's first form answer)
            ev.form = me.form
        end
        if ev.kind == "pull" or ev.kind == "stop" then -- the world's combat runs pull to stop (a kill does not end it)
            W.combat = ev.kind == "pull"
        end
        -- out of combat: the weapon damage UnitDamage reads now, the attack speeds and the regen rates
        if me and (ev.kind == "prepull" or ev.kind == "stop" or (ev.kind == "form" and not W.combat)) then
            local w, m = me.weapons, me.dmgMult
            local o = w[2] or { 0, 0 }
            ev.damage = { w[1][1] * m, w[1][2] * m, o[1] * m, o[2] * m }
            ev.speed = { w[1][3], w[2] and w[2][3] or nil }
            ev.ranged = me.ranged and me.ranged[3] or nil -- UnitRangedDamage's speed
            ev.regen, ev.regenCasting = {}, {}
            for pt in pairs(W.rates) do
                ev.regen[pt], ev.regenCasting[pt] = W.regenRate(me, pt, "idle"), W.regenRate(me, pt, "casting")
            end
        end
        -- our white wound: at the swing (W.hitAtSwing, the default: the server's hit; a white-swing kill clears the
        -- target before its row arrives, the Rogue kill-events capture), else (false) at its `land`
        local skip = W.hitAtSwing and "land" or (ev.ours and "swing") -- the one of our pair that takes nothing
        if ev.act == "WOUND" and ev.dst and ev.kind ~= skip then
            local v = ev.dst
            v.health = math.max(0, v.health - (ev.amount or 0))
            ev.health = v.health -- after the wound (a secret-free client's UnitHealth)
            if v.health <= 0 and not v.dead then -- a kill (headless loop design §2.1.5): the fight's end
                ev.killing = true -- the observer shapes this outcome by kind (unit-registry spec §6.1 row 7)
                v.dead, W.killAt = true, W.t
                W.emit({ kind = "kill", dst = v, src = ev.src, cause = ev })
                for _, e in ipairs(W.ents) do -- a cast at the dead stops (the client's INTERRUPTED and STOP)
                    if e.target == v then
                        W.endCasts(e)
                    end
                end
            end
        elseif ev.act == "HEAL" and ev.dst then
            ev.dst.health = math.min(ev.dst.healthMax, ev.dst.health + (ev.amount or 0))
        end
        -- parry haste: a parried attack, white or special, pulls the parrier's pending main-hand swing at the server's
        -- moment (its outcome row comes later); `land` is a row, not an attack
        local struck = ev.kind == "swing" or ev.kind == "strike" or ev.kind == "spell"
        if W.parryHaste and struck and ev.act == "PARRY" and ev.dst and ev.dst.hasten then
            ev.dst.hasten()
        end
        local us = W.ents[1]
        if ev.kind == "cast" and ev.src == us and (ev.cost or 0) > 0 then -- the five-second rule's window opens
            local pt = ev.pt or us.pt
            us.spentAt[pt], us.heldUntil[pt] = W.t, ev.chanEnds or 0 -- a paid channel holds it to its end (wowsims)
        elseif ev.kind == "channelStop" and ev.src == us then -- however it ends: the stop (a clip) ends the hold
            for pt, u in pairs(us.heldUntil) do
                if u > W.t then
                    us.heldUntil[pt] = W.t
                end
            end
        end
        if ev.src == us and (ev.rage or ev.cost) then
            local r = ev.pt and ev.pt ~= us.pt and us.res[ev.pt]
            if r then
                r.cur = math.min(r.max, math.max(0, r.cur + (ev.rage or 0) - (ev.cost or 0)))
                ev.resCur = r.cur
            else
                us.power = math.min(us.powerMax, math.max(0, us.power + (ev.rage or 0) - (ev.cost or 0)))
                ev.power = us.power
            end
        end
        return ev
    end

    --- `e`'s true value of power type `pt` (nil: its swing-paid `power`).
    function W.res(e, pt)
        if pt == nil or pt == e.pt or not e.res[pt] then
            return e.power
        end
        return e.res[pt].cur
    end

    --- Adds an entity (the first is our character) and its behaviour `fn(W, e)`, started at once.
    function W.add(e, behaviour)
        W.ents[#W.ents + 1] = e
        if behaviour then
            behaviour(W, e)
        end
        return e
    end

    -- Runtime presses (headless loop design §2.1.4): the world's verbs, class-neutral; the content's `effect` uses only
    -- the generic ones below.

    --- The player `e` pressed `key` now. `p` is the content's resolved press { spell, ids (every rank's: the client
    --- answers their cooldown and IsCurrentSpell together; default { spell }), cost, pt (the cost's power type; default
    --- the swing-paid one), cooldown, gcd (seconds; 0 or offGcd: off the GCD), offGcd, onNextSwing, amount ({ lo, hi } of
    --- a queued strike), reagent ({ itemID, n [1] }: a bag count the press needs, paid when its cast lands; short:
    --- "reagent"), cast (a cast time in seconds), channel ({ length, tick, gain = { pt, amount }, effect = fn(W, e,
    --- p, n) }: a channel of `length` s ticking every `tick` s, each tick's gain and effect; the cast, its cost and its
    --- effects at the start), clip (a press during our channel stops it first, the client's cancel; else refused
    --- "casting"), requires = fn(W, e) -> ok, why, effect = fn(W, e, p), and the
    --- generic effects run after `effect`: gain { pt, amount }, points { pt, 1 | "all" } (1: one more on a landed hit
    --- of `effect`'s; "all": spend them all, unless `effect`'s hit was avoided), drain (a power type: spend what is left of it), aura { id, duration,
    --- tick = { pt, every, amount } } (named fields; on us), shift (W.shift's `sh`), item ({ itemID, n }: W.item), pet
    --- ("summon" | "dismiss": W.summonPet, W.dismissPet) }, refund (W.hit's share of the cost
    --- an avoid gives back), outcomes (W.hit's avoid set, a M.OUTCOMES key; a queued strike's too). Checked against the true state in order: a
    --- cast in progress, the GCD, the cooldown, the range, the cost, a strike already queued, `requires`; a refusal
    --- returns false and its reason ("casting", "gcd", "cooldown", "range", "cost", "queued", "requires:<why>") and
    --- changes nothing. An accept
    --- starts the GCD (its length plus `e.gcdLatency`, the client's flag) and the cooldown, then spends, emits the cast
    --- (with `order`, the GCD flag's: 1 after the success, 2 before; `e.gcdOrder` 1, 2 or "mixed", rolled from W.grng)
    --- and runs the effects (a cast time: a "castStart" event with the GCD at the press, all three when the cast
    --- completes; a channel: the cast with its end `chanEnds`, the ticks, a "channelStop" at its end or clip; a queued
    --- strike: queues it, paid at its swing); it returns true.
    function W.press(e, key, p)
        local t = W.t
        local offGcd = p.offGcd or p.gcd == 0
        local clip = p.clip and e.channel ~= nil -- our channel, cut once the press is accepted
        if not p.onNextSwing and not clip and t < (e.castUntil or 0) then
            return false, "casting"
        elseif not offGcd and t < e.gcdUntil - 1e-9 then -- the loop's ticks are a float sum: a 1.0 s GCD ends on one
            return false, "gcd"
        elseif t < (e.cdUntil[key] or 0) then
            return false, "cooldown"
        elseif p.range and W.distance and (W.distance < p.range[1] or W.distance > p.range[2]) then
            return false, "range"
        elseif (p.cost or 0) > W.res(e, p.pt) then
            return false, "cost"
        elseif p.reagent and W.items(e, p.reagent[1]) < (p.reagent[2] or 1) then
            return false, "reagent"
        elseif p.onNextSwing and e.queued then
            return false, "queued"
        end
        if p.requires then
            local ok, why = p.requires(W, e)
            if not ok then
                return false, "requires:" .. tostring(why)
            end
        end
        if clip then
            W.stopChannel(e)
        end
        local gcdLen = not offGcd and (p.gcd or 1.5) + (e.gcdLatency or 0) or nil
        if gcdLen then
            e.gcdUntil = t + gcdLen
        end
        if (p.cooldown or 0) > 0 and not p.onNextSwing then -- a queued strike's starts at its swing
            e.cdUntil[key] = t + p.cooldown
        end
        local hard = (p.cast or 0) > 0 and not p.onNextSwing
        local function land(chanEnds)
            local gcd = not hard and gcdLen or nil -- a hard cast's GCD rose at its start
            local order = e.gcdOrder or 1
            if gcd and order == "mixed" then
                order = W.grng.chance(0.5) and 2 or 1
            end
            W.emit({
                kind = "cast",
                src = e,
                dst = e.target,
                spell = p.spell,
                ids = p.ids,
                cost = p.cost,
                pt = p.pt,
                cd = p.cooldown,
                gcd = gcd,
                order = gcd and order or nil,
                hard = hard or nil, -- its UNIT_SPELLCAST_START came at the press
                chanEnds = chanEnds,
            })
            e.lastHit, e.pressing = nil, p
            -- shortcut: a queued strike (onNextSwing) is checked for its reagent but never pays it; pay it at its swing
            -- (W.queueStrike) when a content queues one with a reagent
            if p.reagent then -- paid when the cast lands
                W.item(e, p.reagent[1], -(p.reagent[2] or 1))
            end
            if p.effect then
                p.effect(W, e, p)
            end
            W.effects(e, p)
            e.pressing = nil
        end
        if p.onNextSwing then
            W.queueStrike(e, p, key)
            if p.effect then
                p.effect(W, e, p)
            end
        elseif hard then
            -- shortcut: no swing-timer pause while casting; upgrade when a melee caster's swings need it.
            e.castUntil = t + p.cast
            local n = (e.castSeq or 0) + 1
            e.castSeq, e.hardSpell = n, p.spell -- W.endCasts stops it; a later cast is another `n`
            W.emit({ kind = "castStart", src = e, spell = p.spell, ends = e.castUntil, gcd = gcdLen })
            W.at(e.castUntil, function()
                if e.castSeq == n and e.hardSpell then
                    e.hardSpell = nil
                    land()
                end
            end)
        elseif p.channel then
            local c = p.channel
            local ch = { spell = p.spell }
            e.channel, e.castUntil = ch, t + c.length
            land(e.castUntil)
            for n = 1, math.floor(c.length / c.tick + 1e-9) do -- every tick lands, the one at the end too
                W.at(t + n * c.tick, function()
                    if e.channel == ch then
                        if c.gain then
                            W.emit({ kind = "gain", src = e, pt = c.gain[1], rage = c.gain[2] })
                        end
                        if c.effect then
                            c.effect(W, e, p, n)
                        end
                    end
                end)
            end
            W.at(e.castUntil, function()
                if e.channel == ch then
                    W.stopChannel(e)
                end
            end)
        else
            land()
        end
        return true
    end

    --- `e`'s channel ends now (its end, or a clip): no tick after it, other presses free.
    function W.stopChannel(e)
        local ch = e.channel
        if ch then
            e.channel, e.castUntil = nil, W.t
            W.emit({ kind = "channelStop", src = e, spell = ch.spell })
        end
    end

    --- `e`'s hard cast or channel in progress ends now, unfinished: the client's interrupt when the target dies, or the
    --- loop leaving the world (loop.run, after its last tick: a stop by the clock is no client event, so the last tick
    --- still sees the cast). Truth "castStop" { src, spell } for a hard cast (no success, nothing paid), W.stopChannel's for a
    --- channel.
    function W.endCasts(e, cause)
        if e.hardSpell then
            W.emit({ kind = "castStop", src = e, spell = e.hardSpell, cause = cause or "death" })
            e.hardSpell, e.castUntil = nil, W.t
        end
        W.stopChannel(e)
    end

    --- `e`'s cooldown of `key` (its ranks' spell IDs `ids`) finishes now: the world's and the client's answers.
    function W.resetCooldown(e, key, ids)
        e.cdUntil[key] = nil
        W.emit({ kind = "cdreset", src = e, ids = ids })
    end

    --- The generic effects of press `p` by `e` (W.press's gain, points, drain, aura, shift), after its `effect`.
    function W.effects(e, p)
        if p.gain then
            W.emit({ kind = "gain", src = e, pt = p.gain[1], rage = p.gain[2] })
        end
        if p.points then
            local pt, n = p.points[1], p.points[2]
            if n == "all" then
                if not (e.lastHit and e.lastHit.act ~= "WOUND") then -- an avoided finisher keeps them (wowsims)
                    W.emit({ kind = "gain", src = e, pt = pt, cost = W.res(e, pt) })
                end
            elseif e.lastHit and e.lastHit.act == "WOUND" then
                W.emit({ kind = "gain", src = e, pt = pt, rage = n })
            end
        end
        if p.drain then
            W.emit({ kind = "gain", src = e, pt = p.drain, cost = W.res(e, p.drain) })
        end
        local a = p.aura
        if a then
            W.applyAura(e, a.id, a.duration)
            local tk = a.tick
            -- shortcut: a refresh keeps the first application's ticks running beside its own (no content refreshes a
            -- ticking aura yet); upgrade with an application count when one does.
            if tk then -- every tick lands, the one at the expiry too
                local applied = e.auras[a.id]
                for k = 1, math.floor(a.duration / tk.every + 1e-9) do
                    W.at(W.t + k * tk.every, function()
                        if applied.expires >= W.t then
                            W.emit({ kind = "gain", src = e, pt = tk.pt, rage = tk.amount })
                        end
                    end)
                end
            end
        end
        if p.shift then
            W.shift(e, p.shift)
        end
        if p.item then
            W.item(e, p.item[1], p.item[2])
        end
        if p.pet == "summon" then
            W.summonPet(e)
        elseif p.pet == "dismiss" then
            W.dismissPet(e)
        end
    end

    --- `e`'s count of item `id` in its bags (0: none).
    function W.items(e, id)
        return e.bags[id] or 0
    end

    --- `e` gains `n` of item `id` now (a negative `n` spends them; never below 0). Truth "item" { src, item, count }.
    function W.item(e, id, n)
        local count = math.max(0, W.items(e, id) + n)
        e.bags[id] = count
        W.emit({ kind = "item", src = e, item = id, count = count })
    end

    -- Our pet (entities.new's `pet`): shortcut: one pet, a summon of any kind brings it full and a dismissal takes it
    -- away (no cast of its own, no health); upgrade when a content needs two kinds told apart. The pet's power rides as
    -- `petPower`: an event's `power` is always ours (the observer's power answers and truth read it).
    local function petEvent(e, kind)
        local p = e.pet
        W.emit({ kind = kind, src = e, up = p.up, pt = p.pt, petPower = p.power })
    end

    --- `e`'s pet is summoned now, its power full. Truth "pet" { src, up, pt, petPower }.
    function W.summonPet(e)
        local p = e.pet
        p.up, p.power = true, p.max
        petEvent(e, "pet")
    end

    --- `e`'s pet is dismissed (or dies) now.
    function W.dismissPet(e)
        e.pet.up = false
        petEvent(e, "pet")
    end

    --- `e`'s pet, while up, gains `amount` power now (a negative amount spends it; within 0 and its max). Truth
    --- "petPower" { src, up, pt, petPower } on a change.
    function W.petGain(e, amount)
        local p = e.pet
        local v = math.min(p.max, math.max(0, p.power + amount))
        if p.up and v ~= p.power then
            p.power = v
            petEvent(e, "petPower")
        end
    end

    --- `e`'s pet regenerates `regen` a second from now, `tick` s at a time (its own declared rate).
    function W.startPetRegen(e)
        local p = e.pet
        local function step()
            W.petGain(e, p.regen * p.tick)
            W.at(W.t + p.tick, step)
        end
        W.at(W.t + p.tick, step)
    end

    --- `e` changes form (after the shift's own cast): `sh` { form, speed (the main hand's new period; default
    --- e.formSpeed[form], else unchanged), dmgMult (the form's weapon damage factor), onEnter = { [pt] = "zero" |
    --- "keep" | fn(W, e, pt, cur) -> the new value } }. The form event comes first, then the resources; out of combat
    --- the form event carries the new damage and speeds (the caches' read). The swing already scheduled keeps its time.
    function W.shift(e, sh)
        e.form, e.formSince = sh.form, W.t
        local speed = sh.speed or e.formSpeed[sh.form]
        if speed and e.weapons[1] then
            e.weapons[1][3] = speed
        end
        if sh.dmgMult then
            e.dmgMult = sh.dmgMult
        end
        W.emit({ kind = "form", form = sh.form })
        for pt, rule in pairs(sh.onEnter or {}) do
            local cur = W.res(e, pt)
            local new = cur
            if rule == "zero" then
                new = 0
            elseif type(rule) == "function" then
                new = rule(W, e, pt, cur)
            end
            if new > cur then
                W.emit({ kind = "gain", src = e, pt = pt, rage = new - cur })
            elseif new < cur then
                W.emit({ kind = "gain", src = e, pt = pt, cost = cur - new })
            end
        end
    end

    --- `e`'s regen per second of `pt` now: the rate, times `W.regenAfter.k` after `W.regenAfter.s` seconds in one form.
    --- An `fsr` type's is its mp5 part A (wowsims's casting rate), plus its spirit part B from 5 s after our last cast
    --- that spent it and after a paid channel's end (held however it ends, mana.go:236-241); `mode` "idle" or "casting" (the out-of-combat read's two returns) asks for both parts or A alone.
    --- While an entry's `auras` are up on `e`, wowsims's PseudoStats rule runs (mana.go:186-206): S = B / (1 - c) (c the
    --- entry's `share`; A - `mp5` when c >= 1), M = A - c x S (or `mp5`); inside the window M + sum(mp5) + S x prod(spirit)
    --- x min(c + sum(share), 1), outside it M + sum(mp5) + S x prod(spirit); "idle" reads the outside rate.
    function W.regenRate(e, pt, mode)
        local f = W.fsr[pt]
        local open = f
            and (
                mode == "idle"
                or (mode ~= "casting" and W.t - (e.spentAt[pt] or -1e9) >= 5 and W.t >= (e.heldUntil[pt] or 0))
            )
        local m, x, s, any = 1, 0, 0, false
        for id, a in pairs(f and f.auras or {}) do
            local up = e.auras[id]
            if up and up.expires > W.t then
                any, m, x, s = true, m * (a.spirit or 1), x + (a.mp5 or 0), s + (a.share or 0)
            end
        end
        if any then
            local c = f.share or 0
            local S = c < 1 and f[1] / (1 - c) or f[2] - (f.mp5 or 0)
            local M = c < 1 and f[2] - c * S or (f.mp5 or 0)
            return M + x + S * m * (open and 1 or math.min(c + s, 1))
        elseif f then
            return f[2] + (open and f[1] or 0)
        end
        local r, ra = W.rates[pt] or 0, W.regenAfter
        if ra and W.t - e.formSince >= ra.s then
            r = r * ra.k
        end
        return r
    end

    --- Continuous regen of `e`'s resources at `rates` ({ [pt] = per second }) from now, applied every `every` s (0.1)
    --- as a "regen" gain, capped at the maximum (no event at it); `after` { s, k }: the rate x k after s seconds in one
    --- form (an unmeasured in-form ramp's knob); `fsr` ({ [pt] = { spirit, mp5, share?, auras? } }): those types by W.regenRate's
    --- five-second rule instead.
    function W.startRegen(e, rates, every, after, fsr)
        every, W.regenAfter = every or 0.1, after
        for pt, r in pairs(rates) do
            W.rates[pt] = r
        end
        for pt, f in pairs(fsr or {}) do
            W.fsr[pt], W.rates[pt] = f, 0
        end
        local function step()
            for pt in pairs(W.rates) do
                local r = e.res[pt] or { cur = e.power, max = e.powerMax }
                local add = math.min(W.regenRate(e, pt) * every, r.max - r.cur)
                if add > 0 then
                    W.emit({ kind = "regen", src = e, pt = pt, rage = add })
                end
            end
            W.at(W.t + every, step)
        end
        W.at(W.t + every, step)
    end

    --- `e`'s out-of-combat decay of power type `d.pt` from now (call it at the combat's end): `d.rate` a second, stepped
    --- and front-loaded: rate x interval at once and at the start of each interval while above 0. `d.pausedBy`: an aura
    --- ID on `e` that pauses it (the quantum then falls at the aura's expiry, and every interval after).
    function W.startDecay(e, d)
        local q = d.rate * d.interval
        local function beat()
            if W.combat then -- out of combat only: the next stop starts it again
                return
            end
            local a = d.pausedBy and e.auras[d.pausedBy]
            if a then
                W.at(a.expires, beat)
                return
            end
            local cur = W.res(e, d.pt)
            if cur > 0 then
                W.emit({ kind = "decay", src = e, pt = d.pt, cost = math.min(cur, q) })
            end
            W.at(W.t + d.interval, beat)
        end
        beat()
    end

    --- Queues `p` (ability `key`) as `e`'s next main-hand swing (the melee behaviour turns it into a strike frame, paid
    --- then; its cooldown `p.cooldown` starts then). `p.price(W, e)`: its cost priced at that swing instead of the
    --- press's `p.cost` (a free-cast aura counts then, as in game).
    function W.queueStrike(e, p, key)
        e.queued = {
            spell = p.spell,
            ids = p.ids,
            cost = p.cost,
            amount = p.amount,
            key = key,
            cd = p.cooldown,
            outcomes = p.outcomes,
            refund = p.refund,
            pt = p.pt,
            price = p.price,
        }
        W.emit({ kind = "queue", src = e, spell = p.spell, ids = p.ids })
    end

    --- Puts aura `id` on `dst` (ours, from the player) for `duration` s, adding `stacks` [1] up to `maxStacks` [1];
    --- it expires on the world clock unless refreshed. Truth events "aura" { dst, aura, stacks (0: gone), expires }.
    function W.applyAura(dst, id, duration, stacks, maxStacks)
        local a = dst.auras[id] or { stacks = 0 }
        a.stacks = math.min(maxStacks or 1, a.stacks + (stacks or 1))
        a.expires, a.duration = W.t + duration, duration
        dst.auras[id] = a
        W.emit({ kind = "aura", dst = dst, aura = id, stacks = a.stacks, expires = a.expires, duration = duration })
        local due = a.expires
        W.at(due, function()
            if dst.auras[id] == a and a.expires == due then
                dst.auras[id] = nil
                W.emit({ kind = "aura", dst = dst, aura = id, stacks = 0, expires = 0, duration = 0 })
            end
        end)
    end

    --- `e` summons into totem slot `slot` (1-4, the client's order) for `duration` s; `spell` the summon's ID. One a
    --- slot: a summon replaces the one there. It expires on the world clock. Truth events "totem" { src, slot, spell,
    --- start (0: empty), duration }.
    function W.summonTotem(e, slot, duration, spell)
        local tt = { spell = spell, start = W.t, expires = W.t + duration }
        e.totems[slot] = tt
        W.emit({ kind = "totem", src = e, slot = slot, spell = spell, start = W.t, duration = duration })
        W.at(tt.expires, function()
            if e.totems[slot] == tt then
                e.totems[slot] = nil
                W.emit({ kind = "totem", src = e, slot = slot, spell = spell, start = 0, duration = 0 })
            end
        end)
    end

    --- `e`'s summon up in totem slot `slot` ({ spell, start, expires }), or nil.
    function W.totem(e, slot)
        return e.totems[slot]
    end

    --- `n` ticks of `amount` in `school` (required: 1 physical) from `e` on `dst`, every `every` s from now, each
    --- +-50 ms (W.crng; the druid-moonfire capture); `key` names the schedule: a new one with the same key on `dst` ends the old (a recast
    --- resets it); `castT` the success it belongs to (the detection suite's truth). A kill stops it.
    function W.dot(e, dst, every, n, amount, school, key, castT)
        assert(school, "W.dot: the ticks' school (1 physical)")
        local mark = {}
        if key then
            dst.dots = dst.dots or {}
            dst.dots[key] = mark
        end
        for k = 1, n do
            W.at(W.t + k * every + (W.crng.next() - 0.5) * 0.1, function()
                if not dst.dead and (not key or dst.dots[key] == mark) then
                    W.emit({
                        kind = "tick",
                        src = e,
                        dst = dst,
                        act = "WOUND",
                        flag = "",
                        amount = amount,
                        school = school,
                        castT = castT,
                    })
                end
            end)
        end
    end

    --- The avoid `set` (a M.OUTCOMES key; default "melee") rolls for a hit of ours on `dst`, with W.crit: the
    --- act ("WOUND", "MISS", "DODGE", "PARRY") and flag.
    function W.rollOutcome(dst, set)
        local av, r = dst.avoid, { crit = W.crit }
        for _, k in ipairs(M.OUTCOMES[set or "melee"]) do
            if k == "spellMiss" then
                r.miss = av.spellMiss or av.miss
            else
                r[k] = av[k]
            end
        end
        return roll(W.rng, r)
    end

    --- An instant outcome of `amount` (in `school`, required: 1 physical) from `e` on `dst`, rolled on `set` or the
    --- press in progress's
    --- `outcomes` (a M.OUTCOMES key; default "melee") against the victim's avoid table and our crit rate (a crit doubles it; an avoid
    --- is recorded in `e.avoidAt[act]`). A nil `amount`: an ability with no damage, whose landed hit shows no outcome
    --- (only its avoid does). An avoid of the press in progress gives back its `refund` share (0-1; the kit's
    --- `refundOnAvoid`) of its cost, a gain before the outcome (the server refunds at the cast's success). Returns the truth event, or { act = "WOUND" } for a
    --- silent landed hit.
    function W.hit(e, dst, amount, school, set, castT, flight)
        assert(school, "W.hit: the outcome's school (1 physical)")
        local p = e.pressing
        local act, flag = W.rollOutcome(dst, set or p and p.outcomes)
        if act ~= "WOUND" then
            e.avoidAt[act] = W.t
        elseif amount == nil then
            e.lastHit = { act = act }
            return e.lastHit
        end
        local amt = act == "WOUND" and math.floor(amount * (flag == "CRITICAL" and 2 or 1) + 0.5) or 0
        if act ~= "WOUND" and p and (p.refund or 0) > 0 and (p.cost or 0) > 0 then
            -- the server refunds at the cast's success (the user, 2026-10-20): before the outcome reports it
            e.pressing = nil -- once a press: a second hit of its effect is no second refund
            W.emit({ kind = "gain", src = e, pt = p.pt, rage = p.refund * p.cost })
        end
        e.lastHit = W.emit({
            kind = "spell",
            src = e,
            dst = dst,
            act = act,
            flag = flag,
            amount = amt,
            school = act == "WOUND" and school or 1,
            castT = castT,
            flight = flight,
        }) -- a spell miss is school 1
        return e.lastHit
    end

    --- A projectile of `e`'s landing `delay` s from now (distance / velocity): W.hit's outcome then, carrying `castT`
    --- (its success). A target dead by then takes nothing.
    function W.hitAt(e, dst, amount, school, set, delay, castT)
        W.at(W.t + delay, function()
            if not dst.dead then
                W.hit(e, dst, amount, school, set, castT, true)
            end
        end)
    end

    --- Starts `e`'s ranged hand (`e.ranged`): a shot now plus `o.delay` and then every ranged speed, while
    --- `e.rangedOn` and its target lives: the auto attack's cast success of `spell` (the content's ID; free, off the
    --- GCD), with `o.swing` also a PLAYER_SWING of the ranged hand (swingType 2), and the shot's physical outcome (W.hit,
    --- the range's middle; a miss only, wowsims's ranged table).
    function W.startRanged(e, spell, o)
        o = o or {}
        e.rangedOn = true
        local function shot()
            local v = e.target
            if not e.rangedOn or not v or v.dead then
                e.rangedOn = false
                return
            end
            local w = e.ranged
            W.emit({ kind = "cast", src = e, dst = v, spell = spell })
            if o.swing then
                W.emit({ kind = "swing", src = e, dst = v, hand = 3, speed = w[3], ours = true })
            end
            W.hit(e, v, (w[1] + w[2]) / 2, 1, "miss") -- wowsims's auto shot: OutcomeRangedHitAndCrit
            W.at(W.t + w[3], shot)
        end
        W.at(W.t + (o.delay or 0), shot)
    end

    --- Our character `e` is `yards` from its target from now (instant; a scenario steps it for a walk): a "move" truth
    --- event { src, distance }, the client's range checks' answer.
    -- shortcut: one position (ours to our target); the mob still swings at us and our ranged hand still shoots at any
    -- distance (no deadzone); upgrade with per-entity positions when a scenario needs either.
    function W.moveTo(e, yards)
        W.distance = yards
        W.emit({ kind = "move", src = e, distance = yards })
    end

    --- Whether our character reaches its target with a white swing (no positions: yes).
    function W.inMelee()
        return (W.distance or 0) <= M.MELEE
    end

    --- `e` gains `amount` power now (a negative amount spends it).
    function W.gain(e, amount)
        if amount >= 0 then
            W.emit({ kind = "gain", src = e, rage = amount })
        else
            W.emit({ kind = "gain", src = e, cost = -amount })
        end
    end

    --- Puts `e` in form `form` (an index into the client's forms; 0 none).
    function W.setForm(e, form)
        e.form, e.formSince = form, W.t
        W.emit({ kind = "form", form = form })
    end

    --- Runs the queue up to `tEnd`.
    function W.run(tEnd)
        local q = W.q
        while q[1] and q[1].t <= tEnd do
            local item = table.remove(q, 1)
            W.t = item.t
            item.fn(W)
        end
        W.t = tEnd
    end

    return W
end

return M
