-- tests/Virtual/harness/world.lua (harness design §3.1, layer 3): runs every behaviour on one clock (a queue by time)
-- and records the TRUE event stream, with the effects the world applies itself (health, our rage). Test code: it
-- allocates freely; the drive loop (drive.lua) reads the observer's flat arrays, never this.
local rng = require("Virtual.harness.rng")
local roll = require("Virtual.harness.behaviours").roll

local M = {}

--- A new world. `seed` seeds its generator. Truth events: { t, kind, src, dst, hand, act, flag, amount, school, spell }
--- with kind "swing" (a white swing, its outcome rolled; ours land later as "land"), "land", "strike" (an
--- on-next-swing strike frame), "spell" (a spell's outcome), "tick", "proc", "cast", "prepull" (the cache and
--- target reads 0.5 s before the pull), "pull", "stop", "form", "buff", "target", "aura", "queue", "unqueue", "gain", "kill".
function M.new(seed)
    -- crng: the client-detail draws (the same-ms avoid, a strike frame's order) apart from the fight's own
    local W = { t = 0, q = {}, seq = 0, truth = {}, rng = rng.new(seed), crng = rng.new(seed + 7919), ents = {} }

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
        if (ev.kind == "prepull" or ev.kind == "stop") and me then -- the weapon damage UnitDamage would read now
            local w, m = me.weapons, me.dmgMult
            local o = w[2] or { 0, 0 }
            ev.damage = { w[1][1] * m, w[1][2] * m, o[1] * m, o[2] * m }
        end
        if ev.act == "WOUND" and ev.dst and (ev.kind ~= "swing" or not ev.ours) then -- ours take it at `land`
            local v = ev.dst
            v.health = math.max(0, v.health - (ev.amount or 0))
            if v.health <= 0 and not v.dead then -- a kill (headless loop design §2.1.5): the fight's end
                v.dead, W.killAt = true, W.t
                W.emit({ kind = "kill", dst = v })
            end
        elseif ev.act == "HEAL" and ev.dst then
            ev.dst.health = math.min(ev.dst.healthMax, ev.dst.health + (ev.amount or 0))
        end
        local us = W.ents[1]
        if ev.src == us and (ev.rage or ev.cost) then
            us.power = math.min(us.powerMax, math.max(0, us.power + (ev.rage or 0) - (ev.cost or 0)))
            ev.power = us.power
        end
        return ev
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

    --- The player `e` pressed `key` now. `p` is the content's resolved press { spell, cost, cooldown, gcd (seconds),
    --- offGcd, onNextSwing, amount ({ lo, hi } of a queued strike), requires = fn(W, e) -> ok, why, effect =
    --- fn(W, e, p) }. Checked against the true state in order: the GCD, the cooldown, the cost, a strike already queued,
    --- `requires`; a refusal returns false and its reason ("gcd", "cooldown", "cost", "queued", "requires:<why>") and
    --- changes nothing. An accept spends (a queued strike at its swing), starts the GCD and the cooldown, emits the
    --- cast (or queues the strike) and runs `effect`; it returns true.
    function W.press(e, key, p)
        local t = W.t
        if not p.offGcd and t < e.gcdUntil then
            return false, "gcd"
        elseif t < (e.cdUntil[key] or 0) then
            return false, "cooldown"
        elseif (p.cost or 0) > e.power then
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
        if not p.offGcd then
            e.gcdUntil = t + (p.gcd or 1.5)
        end
        if (p.cooldown or 0) > 0 then
            e.cdUntil[key] = t + p.cooldown
        end
        if p.onNextSwing then
            W.queueStrike(e, p)
        else
            W.emit({ kind = "cast", src = e, dst = e.target, spell = p.spell, cost = p.cost })
        end
        if p.effect then
            p.effect(W, e, p)
        end
        return true
    end

    --- Queues `p` as `e`'s next main-hand swing (the melee behaviour turns it into a strike frame, paid then).
    function W.queueStrike(e, p)
        e.queued = { spell = p.spell, cost = p.cost, amount = p.amount }
        W.emit({ kind = "queue", src = e, spell = p.spell })
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
        W.emit({ kind = "spell", src = e, dst = dst, act = act, flag = flag, amount = amt, school = school or 1 })
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
        e.form = form
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
