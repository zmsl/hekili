-- tests/Forever/loop_druid_spec.lua (class-completion plan, "The per-pack gate"): stock Hekili headless as a level 60
-- Druid in each pack (tests/Forever/helpers/druid_loop_world.lua) against the harness's world. `make check` runs 3
-- fights a pack (#slow); `make test-druid` the 20 (#druid). Each gate also asserts its flagged lines ran (review focus
-- 5: run A's in-combat ticks whose first record has `focus` set).
-- The 20-fight gates live one pack a file (loop_druid_<pack>_spec.lua), so `make test-druid` runs them in parallel.
local headless = require("Game.harness.headless")
local pack_gate = require("Forever.helpers.pack_gate")
local scenarios = require("Game.harness.scenarios")
local dlw = require("Forever.helpers.druid_loop_world")

local PACKS = { "Feral", "Guardian", "Balance" }
-- Guardian (wowsims.com) is reported, not gated (Task 7g): rage-starved (11.25 a 2.5 s swing, no rage from damage
-- taken in the class file), its first icon waits for rage between Primal Bite and Lacerate, which the usability
-- ladder's rage rungs cannot split: agreement 0.805 and cost refusals 10.5 (the oracle's 6.3) at seeds 1-3, under
-- the gate's 0.85. Its engine health and focus are still asserted. Central fix 22 round 2 (presses resolve from the
-- current state, not Update's leftover prediction): seeds 1-3 0.811 -> 0.899, the 20 fights 0.774 -> 0.850 (at the
-- gate, so still reported). Gap CH (2026-10-31): the 20 fights read agreement 0.900 / 0.896 / 0.881 at seeds 1-20 /
-- 21-40 / 41-60, but unmatched cost refusals 2.3 / 2.5 / 3.5 (bar 3) and flicker 0.47 / 0.54 / 0.83 over the
-- oracle's (FLICKER_K 0.5) hold only at seeds 1-20, so it stays reported; its M.FLICKER floors apply (pack_gate.solo).
local REPORTED = { Guardian = true }
local function solo(name, n, seed0, tag)
    return pack_gate.solo(name, dlw[name], n, seed0, tag, REPORTED[name])
end

describe("the Druid loop worlds", function()
    for _, name in ipairs(PACKS) do
        it(name .. ": boots, and maps every ability the pack can recommend that the character knows", function()
            local C = dlw[name]
            local H = headless.new({ character = C.character(), pack = C.PACK })
            assert.are.same({}, H.loadErrors)
            local unmapped = {}
            for _, list in pairs(H.Hekili.DB.profile.packs[C.PACK].lists) do
                for _, entry in ipairs(list) do
                    local a = entry.action and H.Hekili.Class.abilities[entry.action]
                    if a and a.id and H.ctl.known[a.id] and not dlw.MAP[entry.action] then
                        unmapped[#unmapped + 1] = entry.action
                    end
                end
            end
            assert.are.same({}, unmapped)
            assert.is_false(pcall(C.resolve, "not_an_ability", H))
            if name == "Feral" then -- wowsims's Furor 3/5 in the character and in the world's Cat entry (60% kept)
                local enter = C.resolve("cat_form", H).shift.onEnter[require("Forever.helpers.druid_world").ENERGY]
                assert.are.same({ 3, 30 }, { H.Hekili.State.talent.furor.rank, enter(nil, nil, nil, 50) })
            end
        end)
    end
end)

describe("the Feral loop world's press", function()
    -- druid_loop_world prices the GCD kind from the ability as the engine reads it (no function branch of its own, as
    -- druid_world has): the kit's form-dependent kind resolves through the engine's ability table (ledger L757)
    it(
        "prices a form-dependent GCD kind from the believed form: the totem kind in Cat Form, the spell kind else",
        function()
            local C = dlw.Feral
            local H = headless.new({ character = C.character(), pack = C.PACK })
            local got = {}
            for _, form in ipairs({ dlw.FORM.cat_form, dlw.FORM.bear_form }) do
                H.ctl.form = form
                H.Fire("UPDATE_SHAPESHIFT_FORM")
                headless.cycle(H, H.ctl.now + 0.2)
                H.Hekili.State.reset("Primary", true)
                got[#got + 1] = C.resolve("faerie_fire", H).gcd
            end
            local dw = require("Forever.helpers.druid_world")
            assert.are.same({ dw.GCD.totem, dw.GCD.spell }, got)
        end
    )

    -- The build the Feral log plays (its header: 16958=2 Blood Frenzy, 1328613=1 Predatory Discipline): wowsims
    -- e4ef929e54 talents_feral_combat.go:146 (a builder's crit in Cat Form, one more combo point: 100% at 2/2, the
    -- log's 2.01 "from {SpellID: 16958}") and ferocious_bite.go:22-35 (the extra energy stays).
    local POINTS = require("Forever.helpers.druid_world").POINTS
    local function feralPress(key, power, points, crit)
        local C = dlw.Feral
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local p = C.resolve(key, H)
        local W = scenarios.world(setmetatable({ power = power, form = C.character().form }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        W.t = 1
        W.crit = crit and 1 or 0
        us.target.avoid = {}
        us.res[POINTS].cur = points
        local ok, why = W.press(us, key, p)
        assert.is_true(ok, tostring(why))
        return W.res(us, POINTS), us.power, p.cost
    end
    it("gives a builder's crit in Cat Form Blood Frenzy's second combo point, a plain hit one", function()
        local got = { (feralPress("shred", 100, 0, true)), (feralPress("rake", 100, 0, false)) }
        got[3] = feralPress("claw", 100, 4, true) -- capped at 5
        assert.are.same({ 2, 1, 5 }, got)
    end)
    -- Ferocity 5/5 in both e4ef929e54 builds (the log headers' 16934=5): the logs' Rake 35 and Maul 10
    it("prices Rake and Guardian's Maul at the logs' costs", function()
        local got = {}
        for _, c in ipairs({ { "Feral", "rake" }, { "Guardian", "maul" } }) do
            local C = dlw[c[1]]
            got[#got + 1] = C.resolve(c[2], headless.new({ character = C.character(), pack = C.PACK })).cost
        end
        assert.are.same({ 35, 10 }, got)
    end)
    it("keeps Ferocious Bite's extra energy (Predatory Discipline) and spends the combo points", function()
        local points, energy, cost = feralPress("ferocious_bite", 90, 5, false)
        assert.are.same({ 0, 90 - cost }, { points, energy })
    end)
end)

describe("the Guardian loop world's press", function()
    -- review fix: the press is checked at the cost the client sees (0 under Clearcasting); the swing prices it
    it("accepts a Maul pressed under Clearcasting with rage below its cost, and takes nothing at the queue", function()
        local C = dlw.Guardian
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local VS = H.ns.VirtualState
        local Aura = VS.Aura
        VS.Aura = function() -- Clearcasting up on the truth instance
            return true
        end
        local p = C.resolve("maul", H)
        VS.Aura = Aura
        local W = scenarios.world(setmetatable({ power = 5, form = C.character().form }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        W.t = 1
        local ok, why = W.press(us, "maul", p)
        assert.is_true(ok, tostring(why))
        assert.are.equal(5, us.power)
    end)

    -- L1110: a queued strike's own Omen proc comes at its swing, after its strike, so it never takes it
    it("pays a Maul in full at its swing and raises its own Clearcasting after the strike", function()
        local C = dlw.Guardian
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local cc = H.Hekili.Class.auras.clearcasting.id
        local p = C.resolve("maul", H)
        local W = scenarios.world(setmetatable({ power = 60, form = C.character().form }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        W.t = 1
        local omen = dlw.OMEN
        dlw.OMEN = 1
        local ok, why = W.press(us, "maul", p)
        dlw.OMEN = omen
        assert.is_true(ok, tostring(why))
        W.run(8)
        local out = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "strike" and ev.src == us and ev.spell then
                out[#out + 1] = "strike " .. tostring(ev.cost)
            elseif ev.kind == "aura" and ev.aura == cc then
                out[#out + 1] = "cc " .. ev.stacks
            end
        end
        assert.is_true(p.cost > 0)
        assert.are.same({ "strike " .. p.cost, "cc 1" }, { out[1], out[2] })
    end)

    -- Blood Frenzy 1/2 (the e4ef929e54 log's 16958=1): its 5 rage (16959) on half our crits in Bear Form, Maul's
    -- included: the log's 18 Maul crits bring 10 of its 21 gains, plus one tied with a Lacerate crit (each 0.01 s after the crit), so the world pays the
    -- class file's expected 2.5 on a Maul crit at its swing, as on the on-GCD strikes' and the white swings'
    it("pays Primal Fury's rage on a Maul crit at its swing", function()
        local C = dlw.Guardian
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local p = C.resolve("maul", H)
        local W = scenarios.world(setmetatable({ power = 60, form = C.character().form }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        W.t = 1
        W.crit = 1
        us.target.avoid = {}
        local ok, why = W.press(us, "maul", p)
        assert.is_true(ok, tostring(why))
        W.run(8)
        local out = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "strike" and ev.src == us and ev.spell then
                out[#out + 1] = "strike " .. ev.flag
            elseif ev.kind == "gain" and ev.src == us and #out > 0 then
                out[#out + 1] = "gain " .. tostring(ev.rage)
            end
        end
        assert.are.same({ "strike CRITICAL", "gain 2.5" }, { out[1], out[2] })
    end)
end)

-- Owner ruling L1110 (in game): Omen of Clarity procs on the cast, at its success, so a hard cast started right after
-- takes it; a cast never takes its own proc, and Wrath never takes one.
describe("the Balance loop world's Clearcasting", function()
    it("procs at the cast's success; the next hard cast pays at its landing, free; Wrath keeps it", function()
        local C = dlw.Balance
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local cc = H.Hekili.Class.auras.clearcasting.id
        local W = scenarios.world(setmetatable({ form = C.character().form }, { __index = C.WORLD }), 1)
        local us = W.ents[1]
        local omen = dlw.OMEN
        local function press(key, procs, t)
            dlw.OMEN = procs and 1 or 0
            W.t = t
            local p = C.resolve(key, H) -- the instance never hears the world here: its press price is always full
            local c0, ok, why = p.cost, W.press(us, key, p)
            assert.is_true(ok, key .. " " .. tostring(why) .. " at " .. t)
            local n = #W.truth
            W.run(t + (p.cast or 0) + 0.3)
            dlw.OMEN = omen
            local out = {}
            for i = n + 1, #W.truth do
                local ev = W.truth[i]
                if ev.kind == "cast" and ev.src == us then
                    out[#out + 1] = ("cast %s %.2f"):format(tostring(ev.cost), ev.t)
                elseif ev.kind == "aura" and ev.aura == cc then
                    out[#out + 1] = ("cc %d %.2f"):format(ev.stacks, ev.t)
                end
            end
            return table.concat(out, ", "), p, c0
        end
        local a, pa = press("starfire", true, 1)
        local land = 1 + pa.cast
        -- A pays in full and procs at its success, not later
        assert.are.equal(("cast %s %.2f, cc 1 %.2f"):format(tostring(pa.cost), land, land), a)
        assert.is_true(pa.cost > 0)
        local wrath, pw = press("wrath", false, land + 0.3)
        assert.are.equal(("cast %s %.2f"):format(tostring(pw.cost), land + 0.3 + pw.cast), wrath) -- full, kept
        local t = land + 0.3 + pw.cast
        local b, pb, cb = press("starfire", false, t) -- priced full at its press (the instance saw nothing)
        assert.is_true(cb > 0)
        assert.are.equal(("cast 0 %.2f, cc 0 %.2f"):format(t + pb.cast, t + pb.cast), b) -- free at its landing
    end)
end)

describe("the headless Druid gates, 3 fights a pack #slow", function()
    for _, name in ipairs(PACKS) do
        it(
            name .. " solo, level 60, one mob, 3 fights of up to 3 minutes: the first icon against the oracle's",
            function()
                local r, line = solo(name, 3, nil, "seeds 1-3")
                assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
            end
        )
    end
end)

-- Gap BD: the cast bar the loop's client answered was on the world's clock (and shared by both instances), so the
-- engine never saw a hard cast in progress. Two fights on one boot (the second on clocks the oracle's lone run B
-- moved apart), ours driving.
describe("the Balance loop at a hard cast's end (gap BD) #slow", function()
    it("prices the cast in progress and flips nothing between two polls where nothing happened", function()
        local loop = require("Game.harness.loop")
        local L = loop.new(dlw.Balance)
        local jumps, flips, casts = {}, {}, 0
        for seed = 1, 2 do
            local a = loop.fight(L, seed, { trace = false })
            local f, s = a.frames[1], a.ours
            local ev = f.ev
            for i = 2, a.combat do
                casts = casts + (ev.spend[i] and 1 or 0)
                -- (1) shown ready just before the cast lands, then its wait jumps past the GCD at the landing: the
                -- forecast missed the cast's cost (and the five-second rule from its success)
                if ev.spend[i] and f.wait[1][i - 1] <= 0.2 and f.wait[1][i] > f.gcd[i] + 1 then
                    jumps[#jumps + 1] = ("seed %d tick %d %s %.2f -> %.2f"):format(
                        seed,
                        i,
                        s[i],
                        f.wait[1][i - 1],
                        f.wait[1][i]
                    )
                end
                -- (2) A -> B -> A with no cast, spend, avoid or aura between the first two polls: a pick computed
                -- from the cast's end that flips back at the end tick. A press of B at its tick or the next is no flip
                -- (the owner's rule, loop.flips): its cast event is the next tick's (Lane R2: seed 1 tick 288, Starfire
                -- shown and pressed the poll its usable answer lifted the floor to its cost, then the next pick)
                local pressedB = a.pressed[i] == s[i] or a.pressed[i + 1] == s[i]
                local q = ev.cast[i] or ev.spend[i] or ev.avoid[i] or ev.aura[i] or pressedB
                if i < a.combat and s[i - 1] ~= s[i] and s[i + 1] == s[i - 1] and not q then
                    flips[#flips + 1] = ("seed %d tick %d %s -> %s"):format(seed, i, tostring(s[i - 1]), tostring(s[i]))
                end
            end
        end
        assert.is_true(casts > 20)
        assert.are.same({}, jumps)
        assert.are.same({}, flips)
    end)
end)
