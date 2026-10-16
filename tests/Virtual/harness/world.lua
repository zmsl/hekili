-- tests/Virtual/harness/world.lua (harness design §3.1, layer 3): runs every behaviour on one clock (a queue by time)
-- and records the TRUE event stream, with the effects the world applies itself (health, our rage). Test code: it
-- allocates freely; the drive loop (drive.lua) reads the observer's flat arrays, never this.
local rng = require("Virtual.harness.rng")

local M = {}

--- A new world. `seed` seeds its generator. Truth events: { t, kind, src, dst, hand, act, flag, amount, school, spell }
--- with kind "swing" (a white swing, its outcome rolled; ours land later as "land"), "land", "strike" (an
--- on-next-swing strike frame), "spell" (a spell's outcome), "tick", "proc", "cast", "pull", "stop", "form", "buff",
--- "target".
function M.new(seed)
    local W = { t = 0, q = {}, seq = 0, truth = {}, rng = rng.new(seed), ents = {} }

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
        if ev.kind == "pull" or ev.kind == "target" then -- whom each entity targets now (its tokens' answers)
            ev.targets = {}
            for _, e in ipairs(W.ents) do
                ev.targets[e] = e.target or false
            end
        end
        if (ev.kind == "pull" or ev.kind == "stop") and me then -- the weapon damage UnitDamage would read now
            local w, m = me.weapons, me.dmgMult
            local o = w[2] or { 0, 0 }
            ev.damage = { w[1][1] * m, w[1][2] * m, o[1] * m, o[2] * m }
        end
        if ev.act == "WOUND" and ev.dst and ev.kind ~= "swing" then
            ev.dst.health = math.max(0, ev.dst.health - (ev.amount or 0))
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
