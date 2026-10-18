-- tests/Forever/damage_ring_spec.lua (audit first wave, Task 3, item 6): Targets.lua's incoming damage and healing
-- ring buffers against upstream's timer buckets (the OLD block below, copied verbatim from Engine/Sim/Targets.lua at
-- forever b26f70ab, ns renamed old, driven by a fake C_Timer on the headless clock): 200 recorded hits of mixed kinds
-- over 12 s, read at many times for the 1 s / 5 s / 10 s windows and between them; the overflow; 0 B per hit.
-- luacheck: ignore 211 (locals of the verbatim copy)
local headless = require("Game.harness.headless")

describe("the incoming damage and healing ring buffers", function()
    local H, ns, old, timers

    local function runTimers(now)
        local i = 1
        while i <= #timers do
            if timers[i][1] <= now then
                table.remove(timers, i)[2]()
            else
                i = i + 1
            end
        end
    end

    setup(function()
        H = headless.new({})
        ns = H.ns
        old, timers = {}, {}
        local C_Timer = {
            After = function(s, fn)
                timers[#timers + 1] = { H.ctl.now + s, fn }
            end,
        }
-- stylua: ignore start
do
    local damage = {
        [1] = 0,
        [5] = 0,
        [10] = 0,
    }

    local physical = {
        [1] = 0,
        [5] = 0,
        [10] = 0
    }

    local magical = {
        [1] = 0,
        [5] = 0,
        [10] = 0
    }

    local healing = {
        [1] = 0,
        [5] = 0,
        [10] = 0
    }

    old.storeDamage = function( _, dam, isPhysical )
        if dam and dam > 0 then
            local db = isPhysical and physical or magical

            db[ 1 ] = db[ 1 ] + dam
            damage[ 1 ] = damage[ 1 ] + dam

            C_Timer.After( 1, function()
                db[ 1 ] = db[ 1 ] - dam
                damage[ 1 ] = damage[ 1 ] - dam
            end )

            db[ 5 ] = db[ 5 ] + dam
            damage[ 5 ] = damage[ 5 ] + dam

            C_Timer.After( 5, function()
                db[ 5 ] = db[ 5 ] - dam
                damage[ 5 ] = damage[ 5 ] - dam
            end )

            db[ 10 ] = db[ 10 ] + dam
            damage[ 10 ] = damage[ 10 ] + dam

            C_Timer.After( 10, function()
                db[ 10 ] = db[ 10 ] - dam
                damage[ 10 ] = damage[ 10 ] - dam
            end )
        end
    end

    old.damageInLast = function( seconds, isPhysical )
        local db
        if isPhysical == nil then db = damage
        elseif isPhysical == true then db = physical
        else db = magical end

        if db[ seconds ] then return db[ seconds ] end

        if seconds < 1 then
            return db[ 1 ] * ( seconds / 1 )
        end

        if seconds < 5 then
            return db[ 1 ] + ( db[ 5 ] - db[ 1 ] ) * ( seconds - 1 ) / 5
        end

        if seconds < 10 then
            return db[ 5 ] + ( db[ 10 ] - db[ 5 ] ) * ( seconds - 5 ) / 10
        end

        return db[ 10 ] * seconds / 10
    end

    old.storeHealing = function( _, amount )
        if amount and amount > 0 then
            healing[ 1 ] = healing[ 1 ] + amount
            C_Timer.After( 1, function() healing[ 1 ] = healing[ 1 ] - amount end )

            healing[ 5 ] = healing[ 5 ] + amount
            C_Timer.After( 5, function() healing[ 5 ] = healing[ 5 ] - amount end )

            healing[ 10 ] = healing[ 10 ] + amount
            C_Timer.After( 10, function() healing[ 10 ] = healing[ 10 ] - amount end )
        end
    end

    old.healingInLast = function( seconds )
        if healing[ seconds ] then return healing[ seconds ] end

        if seconds < 1 then
            return healing[ 1 ] * ( seconds / 1 )
        end

        if seconds < 5 then
            return healing[ 1 ] + ( healing[ 5 ] - healing[ 1 ] ) * ( seconds - 1 ) / 5
        end

        if seconds < 10 then
            return healing[ 5 ] + ( healing[ 10 ] - healing[ 5 ] ) * ( seconds - 5 ) / 10
        end

        return healing[ 10 ] * seconds / 10
    end
end
        -- stylua: ignore end
    end)

    local function close(a, b)
        return math.abs(a - b) <= 1e-6 * math.max(1, math.abs(a))
    end

    it("sum as upstream's buckets over 200 hits of mixed kinds across 12 s, at every read time and window", function()
        local seed = 12345
        local function rand()
            seed = (seed * 1103515245 + 12345) % 2147483648
            return seed / 2147483648
        end
        local t0 = H.ctl.now + 100 -- past anything an earlier hit left
        local hits = {}
        for i = 1, 200 do
            hits[i] = { t0 + 12 * rand(), math.floor(1 + 500 * rand()), rand() } -- time, amount, kind roll
        end
        table.sort(hits, function(a, b)
            return a[1] < b[1]
        end)
        local reads, wrong, most = 0, {}, 0
        local function compare(now)
            H.ctl.now = now
            runTimers(now)
            for _, s in ipairs({ 0.5, 1, 2.5, 5, 7, 10, 15 }) do
                for _, kind in ipairs({ "nil", "true", "false" }) do
                    local p = ({ ["nil"] = nil, ["true"] = true, ["false"] = false })[kind]
                    local a, b = ns.damageInLast(s, p), old.damageInLast(s, p)
                    reads, most = reads + 1, math.max(most, b)
                    if not close(a, b) then
                        wrong[#wrong + 1] = ("damage %s s %s at %.3f: %s vs %s"):format(s, kind, now - t0, a, b)
                    end
                end
                local a, b = ns.healingInLast(s), old.healingInLast(s)
                if not close(a, b) then
                    wrong[#wrong + 1] = ("healing %s s at %.3f: %s vs %s"):format(s, now - t0, a, b)
                end
            end
        end
        for _, h in ipairs(hits) do
            compare(h[1] - 0.0007) -- read between hits as well as after
            H.ctl.now = h[1]
            runTimers(h[1])
            if h[3] < 0.45 then
                ns.storeDamage(nil, h[2], true)
                old.storeDamage(nil, h[2], true)
            elseif h[3] < 0.8 then
                ns.storeDamage(nil, h[2], false)
                old.storeDamage(nil, h[2], false)
            else
                ns.storeHealing(nil, h[2])
                old.storeHealing(nil, h[2])
            end
        end
        for k = 1, 60 do -- and the 12 s after the last hit, until every window is empty
            compare(hits[#hits][1] + 0.2 * k + 0.0003)
        end
        assert.are.same({}, wrong)
        assert.is_true(reads > 5000 and most > 10000, reads .. " reads, most " .. most)
        assert.are.equal(0, ns.damageInLast(10))
    end)

    it("keeps the newest 128 hits of a kind: past that the oldest drop out of the sums; 0 B per hit", function()
        local t = H.ctl.now + 100
        for i = 1, 200 do
            H.ctl.now = t + i * 0.01
            ns.storeDamage(nil, i, true)
        end
        local kept = 0
        for i = 200 - 127, 200 do
            kept = kept + i
        end
        assert.are.equal(kept, ns.damageInLast(10, true))
        assert.are.equal(0, ns.damageInLast(10, false))
        collectgarbage("stop")
        local b = collectgarbage("count")
        for i = 1, 1000 do
            H.ctl.now = H.ctl.now + 0.01
            ns.storeDamage(nil, i, i % 2 == 0)
            ns.storeHealing(nil, i)
        end
        local bytes = (collectgarbage("count") - b) * 1024
        collectgarbage("restart")
        assert.are.equal(0, bytes)
    end)
end)
