-- tests/Game/harness/loop_spec.lua (class-completion plan, Task 1): the loop is class-neutral. A stub content of a
-- non-rage power (type 3, no pack) drives two fights, and its per-hit gains reach the observer as that power.
local loop = require("Game.harness.loop")

local PT, TOKEN = 3, "ENERGY"

describe("the headless loop, class-neutral", function()
    it(
        "drives two fights of a stub energy world: content.gain answers for its power, the observer reports it",
        function()
            local asked = {}
            local stub = {
                character = function()
                    return { level = 60, power = { type = PT, token = TOKEN, max = 100 } }
                end,
                resolve = function()
                    return {}
                end,
                usable = function()
                    return {}
                end,
                uptime = function()
                    return {}
                end,
                gain = function(pt, hand)
                    asked[pt] = true
                    return hand == 1 and 5 or 0
                end,
                WORLD = { level = 60, max = 100, mobHealth = 1e9 },
            }
            local L = loop.new(stub)
            local seen = { fights = {}, power = 0, tokens = 0 }
            local m = loop.tally(L, 2, {
                duration = 12,
                on = function(run, steps)
                    seen.fights[run.W] = true
                    seen.pt, seen.truth = run.us.pt, run.us.power
                    local s = steps[#steps].obs.s -- the oracle's secret-free client
                    for i = 1, s.n do
                        if s.ev[i] == "@power" and s.a1[i] == PT then
                            seen.power = math.max(seen.power, s.a2[i])
                        elseif s.ev[i] == "UNIT_POWER_FREQUENT" and s.a2[i] == TOKEN then
                            seen.tokens = seen.tokens + 1
                        end
                    end
                end,
            })
            assert.are.equal(2, m.fights)
            local worlds = 0
            for _ in pairs(seen.fights) do
                worlds = worlds + 1
            end
            assert.are.equal(4, worlds) -- run A and run B of each fight
            assert.are.same({ [PT] = true }, asked)
            assert.are.equal(PT, seen.pt)
            assert.is_true(seen.truth > 0 and seen.power > 0 and seen.tokens > 0)
            assert.are.equal(0, m.focus) -- no pack, no flagged record
        end
    )
end)

describe("the headless loop between two fights on one boot", function()
    it("ends a fight killed by the last tick's press out of combat for every instance", function()
        local stub = {
            character = function()
                return { level = 60, power = { type = 1, token = "RAGE", max = 100 } }
            end,
            resolve = function()
                return {}
            end,
            usable = function()
                return {}
            end,
            uptime = function()
                return {}
            end,
            gain = function()
                return 0
            end,
            WORLD = { level = 60, max = 100, mobHealth = 1e9 },
        }
        local L = loop.new(stub)
        local o = {
            duration = 12,
            on = function(run, _, t) -- a kill after this tick's feed, as a press's would be
                if t >= 5 and not run.W.killAt then
                    run.W.emit({ kind = "spell", src = run.us, dst = run.us.target, act = "WOUND", amount = 1e12 })
                end
            end,
        }
        local a = loop.run(L, 1, o, { { H = L.us }, { H = L.oracle, plain = true } })
        assert.is_truthy(a.W.killAt)
        for _, H in ipairs({ L.us, L.oracle }) do
            assert.is_false(H.ns.VirtualStateInternal.inCombat) -- the kill's PLAYER_REGEN_ENABLED arrived
        end
        -- the next fight's fresh world: each instance hears the client's plain reads of it before anything happens
        -- (no buff, cooldown, form or totem of the last fight carried over)
        local heard = {}
        local fire = L.us.Fire
        L.us.Fire = function(ev, ...)
            heard[ev] = (heard[ev] or 0) + 1
            return fire(ev, ...)
        end
        loop.run(L, 2, { duration = 1 }, { { H = L.us } })
        L.us.Fire = fire
        assert.are.same({ 1, 1, 1, 4 }, {
            heard.UNIT_AURA and 1,
            heard.SPELL_UPDATE_COOLDOWN and 1,
            heard.UPDATE_SHAPESHIFT_FORM and 1,
            heard.PLAYER_TOTEM_UPDATE,
        })
    end)
end)

describe("the headless loop's pools between two fights (loop.rest)", function()
    local function stub(pt, world)
        return {
            character = function()
                return { level = 60, power = { type = pt, token = "POOL", max = 100 } }
            end,
            resolve = function()
                return {}
            end,
            usable = function()
                return {}
            end,
            uptime = function()
                return {}
            end,
            gain = function()
                return 0
            end,
            WORLD = world,
        }
    end
    -- at the pull our pool is drained (or filled) to `v`; the next fight on the boot starts from it through the gap
    local function twoFights(L, v)
        local o = {
            duration = 4,
            on = function(run, _, t)
                if t >= 3.5 and t < 3.7 then
                    local us = run.us
                    run.W.emit({ kind = "gain", src = us, rage = v - us.power })
                end
            end,
        }
        local a = loop.run(L, 1, o, { { H = L.us } })
        local b = loop.run(L, 2, { duration = 1 }, { { H = L.us } })
        return a, b
    end

    it("regenerates a pool at its idle rate through the gap: a fight that ended dry does not start full", function()
        local L = loop.new(stub(3, { level = 60, max = 100, mobHealth = 1e9, power = 100, regen = { [3] = 1 } }))
        local a, b = twoFights(L, 0)
        assert.is_true(a.us.power < 5) -- dry at the end (a few seconds' regen)
        assert.are.equal(math.min(100, a.us.power + loop.GAP), b.us.power0)
    end)

    it("decays a pool by the world's stepped out-of-combat decay through the gap", function()
        local decay = { pt = 1, rate = 1, interval = 1 }
        local L = loop.new(stub(1, { level = 60, max = 100, mobHealth = 1e9, decay = decay }))
        local a, b = twoFights(L, 50)
        assert.are.equal(49, a.us.power) -- the world's stop came: its first quantum taken
        assert.are.equal(49 - loop.GAP, b.us.power0)
    end)
end)

describe("the headless loop's paired refusals (loop.unmatched)", function()
    it("counts a refusal against us only when the oracle shadow did not show that icon ready at that tick", function()
        local shown = { name = { "spender" }, time = { 0.02 } }
        local other = { name = { "other" }, time = { 0 } }
        local waiting = { name = { "spender" }, time = { 0.4 } }
        assert.is_false(loop.unmatched("spender", shown, loop.REACT)) -- both would press: no belief error
        assert.is_true(loop.unmatched("spender", other, loop.REACT))
        assert.is_true(loop.unmatched("spender", waiting, loop.REACT))
        assert.is_true(loop.unmatched("spender", nil, loop.REACT)) -- no shadow: ours
        local m = loop.blank()
        m.attempts, m.attemptsB = 10, 10
        m.refused.cost, m.refusedB.cost = 2, 1 -- two refusals at a tick the shadow pressed too: unmatched 0
        local r = loop.summary(m)
        assert.are.same({ 20, 0, 10 }, { r.per100.cost, r.per100U.cost, r.per100B.cost })
        m.unmatched.cost = 1 -- one where the shadow did not show the icon ready
        assert.are.equal(10, loop.summary(m).per100U.cost)
        assert.is_truthy(loop.line(m):find("cost 20.0 (oracle 10.0, unmatched 10.0)", 1, true))
    end)

    it("bars the unmatched cost refusals at a plain 3 per 100 (pack_gate), whatever the oracle's own rate", function()
        local gate = require("Forever.helpers.pack_gate")
        local ab = require("Game.harness.ab")
        local arm = ab.arm
        ab.arm = function() -- the bar itself, in every arm (make gate-ab's provider arms record bars, providers §4.1)
            return "default"
        end
        finally(function()
            ab.arm = arm
        end)
        local h = { errors = 0, raises = 0, selfCheck = 0, misses = {}, secrets = {} }
        local function r(u, b)
            return {
                agreement = 1,
                reactMedian = 0,
                reactP90 = 0,
                cpuMean = 0,
                per100 = { cost = 40 },
                per100U = { cost = u },
                per100B = { cost = b },
            }
        end
        assert.has_no.errors(function()
            gate.gate(h, r(3, 0), "line")
        end)
        assert.has.errors(function()
            gate.gate(h, r(3.1, 30), "line") -- the oracle refusing more does not widen it
        end)
    end)
end)

describe("the headless loop's replay injection (o.replay)", function()
    local scenarios = require("Game.harness.scenarios")
    it("presses nothing, cycles at each decision and scores only the on-GCD ones", function()
        local stub = {
            character = function()
                return { level = 60, power = { type = 1, token = "RAGE", max = 100 } }
            end,
            resolve = function()
                error("no press in a replay")
            end,
            usable = function()
                return {}
            end,
            uptime = function()
                return {}
            end,
            gain = function()
                return 0
            end,
            WORLD = { level = 60, max = 100, mobHealth = 1e9 },
        }
        local L = loop.new(stub)
        local R = {
            pull = 3,
            duration = 6,
            decisions = {
                { t = 3.3, key = "a", gcd = true },
                { t = 3.5, key = "b", gcd = false },
                { t = 4.1, key = "c", gcd = true },
            },
        }
        function R.world(wo, seed)
            return scenarios.world(wo, seed)
        end
        function R.next(t)
            for _, d in ipairs(R.decisions) do
                if d.t > t then
                    return d.key
                end
            end
            return false
        end
        local m = loop.replay(L, R)
        assert.are.same({ 2, 0 }, { m.dec.both, m.dec.agree }) -- no pack: our on-GCD icon is false at both
        assert.are.equal(0, m.attempts)
        local r = loop.summary(m)
        assert.are.equal(0, r.decisions)
        assert.is_truthy(loop.line(m):find("; decisions on-GCD 0.000 (2)", 1, true))
        assert.is_truthy(
            loop.line(m):find("; decision flips 0 (0.0 per 100), retracted confirmed by wowsims 0", 1, true)
        )
        local t = loop.tally(L, 1, { duration = 6, hold = true })
        assert.is_nil(loop.summary(t).decisions) -- the normal tally: unchanged
        -- every line carries the ledger's fields, and says when the hold experiment was on
        assert.is_truthy(loop.line(t):find("; dips 0.00 flashes 0.00; top []", 1, true))
        assert.is_truthy(loop.line(t):find("; hold on$"))
        t = loop.tally(L, 1, { duration = 6, steady = true }) -- the shipped steady icons on our instance
        assert.is_truthy(loop.line(t):find("; steady icons on$"))
    end)
end)

describe("the headless loop's bags, pet and stats (central fix 27)", function()
    it("gives both instances the world's bag counts, pet power and stats through the facade", function()
        local ITEM = 6000
        local stub = {
            character = function()
                return { level = 60, power = { type = 1, token = "RAGE", max = 100 } }
            end,
            resolve = function()
                return {}
            end,
            usable = function()
                return {}
            end,
            uptime = function()
                return {}
            end,
            gain = function()
                return 0
            end,
            WORLD = {
                level = 60,
                max = 100,
                mobHealth = 1e9,
                bags = { [ITEM] = 4 },
                pet = { pt = 0, max = 500, power = 200, regen = 5, tick = 2 },
                stats = { 10, 20, 30, 40, 55 },
            },
        }
        local L = loop.new(stub)
        local seen = {}
        loop.tally(L, 1, {
            duration = 12,
            on = function(run, steps)
                for i, st in ipairs(steps) do
                    local F, S = st.H.ns.Facade, st.H.Hekili.State
                    seen[i] = {
                        F.C_Item.GetItemCount(ITEM),
                        F.UnitExists("pet"),
                        S.pet.mana,
                        (st.H.ns.VirtualState.Stat("UnitStat", 5)),
                    }
                end
                seen.truth = run.us.pet.power
            end,
        })
        -- the pet regenerated from 200 by 10 every 2 s up to the fight's end (the true value is the client's answer)
        assert.is_true(seen.truth > 200)
        assert.are.same({ 4, true, seen.truth, 55 }, seen[1])
        assert.are.same(seen[1], seen[2])
    end)
end)
