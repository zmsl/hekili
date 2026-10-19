-- tests/Game/harness/world.lua (harness design §3.1, layer 3): runs every behaviour on one clock (a queue by time)
-- and records the TRUE event stream, with the effects the world applies itself (health, our rage). Test code: it
-- allocates freely; the drive loop (drive.lua) reads the observer's flat arrays, never this.
local rng = require("Game.harness.rng")
local behaviours = require("Game.harness.behaviours")
local roll = behaviours.roll

local M = {}

-- Our crit rate on an instant hit (W.hit): the white swings' measured rate.
M.CRIT = behaviours.RATES.crit

--- A new world. `seed` seeds its generator. Truth events: { t, kind, src, dst, hand, act, flag, amount, school, spell }
--- with kind "swing" (a white swing, its outcome rolled; ours land later as "land"), "land", "strike" (an
--- on-next-swing strike frame), "spell" (a spell's outcome), "tick", "proc", "cast", "prepull" (the cache and
--- target reads 0.5 s before the pull), "pull", "stop", "form", "buff", "target", "aura", "queue", "unqueue", "gain", "kill",
--- "regen" and "decay" (a resource's continuous regen and out-of-combat decay, W.startRegen / W.startDecay). A gain
--- (`rage`) or spend (`cost`) of ours is of power type `pt` (default our `pt`, the swing-paid `power`; another type's
--- value after it: `ev.resCur`).
function M.new(seed)
    -- crng: the client-detail draws (the same-ms avoid, a strike frame's order) apart from the fight's own
    local W = { t = 0, q = {}, seq = 0, truth = {}, rng = rng.new(seed), crng = rng.new(seed + 7919), ents = {} }
    W.grng = rng.new(seed + 15485863) -- the GCD flag's order against its cast (W.press), apart from both
    W.combat = false
    W.rates = {} -- [powerType] = regen per second (W.startRegen)
    W.fsr = {} -- [powerType] = { spirit, mp5 } per second: the five-second rule's two parts (W.startRegen)

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
            ev.regen, ev.regenCasting = {}, {}
            for pt in pairs(W.rates) do
                ev.regen[pt], ev.regenCasting[pt] = W.regenRate(me, pt, "idle"), W.regenRate(me, pt, "casting")
            end
        end
        if ev.act == "WOUND" and ev.dst and (ev.kind ~= "swing" or not ev.ours) then -- ours take it at `land`
            local v = ev.dst
            v.health = math.max(0, v.health - (ev.amount or 0))
            ev.health = v.health -- after the wound (a secret-free client's UnitHealth)
            if v.health <= 0 and not v.dead then -- a kill (headless loop design §2.1.5): the fight's end
                v.dead, W.killAt = true, W.t
                W.emit({ kind = "kill", dst = v })
            end
        elseif ev.act == "HEAL" and ev.dst then
            ev.dst.health = math.min(ev.dst.healthMax, ev.dst.health + (ev.amount or 0))
        end
        local us = W.ents[1]
        if ev.kind == "cast" and ev.src == us and (ev.cost or 0) > 0 then -- the five-second rule's window opens
            us.spentAt[ev.pt or us.pt] = W.t
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
    --- a queued strike), cast (a cast time in seconds), requires = fn(W, e) -> ok, why, effect = fn(W, e, p), and the
    --- generic effects run after `effect`: gain { pt, amount }, points { pt, 1 | "all" } (1: one more on a landed hit
    --- of `effect`'s; "all": spend them all), drain (a power type: spend what is left of it), aura { id, duration,
    --- tick = { pt, every, amount } } (named fields; on us), shift (W.shift's `sh`) }. Checked against the true state in order: a
    --- cast in progress, the GCD, the cooldown, the cost, a strike already queued, `requires`; a refusal returns false
    --- and its reason ("casting", "gcd", "cooldown", "cost", "queued", "requires:<why>") and changes nothing. An accept
    --- starts the GCD (its length plus `e.gcdLatency`, the client's flag) and the cooldown, then spends, emits the cast
    --- (with `order`, the GCD flag's: 1 after the success, 2 before; `e.gcdOrder` 1, 2 or "mixed", rolled from W.grng)
    --- and runs the effects (a cast time: all three when the cast completes; a queued strike: queues it, paid at its
    --- swing); it returns true.
    function W.press(e, key, p)
        local t = W.t
        local offGcd = p.offGcd or p.gcd == 0
        if not p.onNextSwing and t < (e.castUntil or 0) then
            return false, "casting"
        elseif not offGcd and t < e.gcdUntil - 1e-9 then -- the loop's ticks are a float sum: a 1.0 s GCD ends on one
            return false, "gcd"
        elseif t < (e.cdUntil[key] or 0) then
            return false, "cooldown"
        elseif (p.cost or 0) > W.res(e, p.pt) then
            return false, "cost"
        elseif p.onNextSwing and e.queued then
            return false, "queued"
        end
        if p.requires then
            local ok, why = p.requires(W, e)
            if not ok then
                return false, "requires:" .. tostring(why)
            end
        end
        local gcdLen = not offGcd and (p.gcd or 1.5) + (e.gcdLatency or 0) or nil
        if gcdLen then
            e.gcdUntil = t + gcdLen
        end
        if (p.cooldown or 0) > 0 then
            e.cdUntil[key] = t + p.cooldown
        end
        local function land()
            -- shortcut: a cast time's GCD is over at its success, so the client sees no GCD flag for it; upgrade
            -- with UNIT_SPELLCAST_START.
            local gcd = (p.cast or 0) == 0 and gcdLen or nil
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
            })
            e.lastHit = nil
            if p.effect then
                p.effect(W, e, p)
            end
            W.effects(e, p)
        end
        if p.onNextSwing then
            W.queueStrike(e, p)
            if p.effect then
                p.effect(W, e, p)
            end
        elseif (p.cast or 0) > 0 then
            -- shortcut: the client sees only the success at the cast's end (no UNIT_SPELLCAST_START or
            -- UnitCastingInfo, no swing-timer pause); upgrade when a cast-time ability's recommendations need them.
            e.castUntil = t + p.cast
            W.at(e.castUntil, land)
        else
            land()
        end
        return true
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
                W.emit({ kind = "gain", src = e, pt = pt, cost = W.res(e, pt) })
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
    --- An `fsr` type's is its mp5 part, plus its spirit part from 5 s after our last cast that spent it; `mode` "idle"
    --- or "casting" (the out-of-combat read's two returns) asks for both parts or the mp5 part alone.
    function W.regenRate(e, pt, mode)
        local f = W.fsr[pt]
        if f then
            local open = mode == "idle" or (mode ~= "casting" and W.t - (e.spentAt[pt] or -1e9) >= 5)
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
    --- form (an unmeasured in-form ramp's knob); `fsr` ({ [pt] = { spirit, mp5 } }): those types by W.regenRate's
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

    --- Queues `p` as `e`'s next main-hand swing (the melee behaviour turns it into a strike frame, paid then).
    function W.queueStrike(e, p)
        e.queued = { spell = p.spell, ids = p.ids, cost = p.cost, amount = p.amount }
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

    --- `n` ticks of `amount` (school 1) from `e` on `dst`, every `every` s from now.
    function W.dot(e, dst, every, n, amount)
        for k = 1, n do
            W.at(W.t + k * every, function()
                if not dst.dead then
                    W.emit({ kind = "tick", src = e, dst = dst, act = "WOUND", flag = "", amount = amount, school = 1 })
                end
            end)
        end
    end

    --- An instant outcome of `amount` (school [1]) from `e` on `dst`, rolled against the victim's avoid table and our
    --- crit rate (a crit doubles it; an avoid is recorded in `e.avoidAt[act]`).
    function W.hit(e, dst, amount, school)
        local av = dst.avoid
        local act, flag = roll(W.rng, { miss = av.miss, dodge = av.dodge, parry = av.parry, crit = M.CRIT })
        if act ~= "WOUND" then
            e.avoidAt[act] = W.t
        end
        local amt = act == "WOUND" and math.floor(amount * (flag == "CRITICAL" and 2 or 1) + 0.5) or 0
        e.lastHit =
            W.emit({ kind = "spell", src = e, dst = dst, act = act, flag = flag, amount = amt, school = school or 1 })
        return e.lastHit
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
