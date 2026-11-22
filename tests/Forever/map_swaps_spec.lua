-- tests/Forever/map_swaps_spec.lua (T1 task 7; ledger L643): in a dungeon (the Map restriction: every unit identity
-- secret, in combat, the target's auras unreadable) the token plate count gives the engine its enemies, so the AoE
-- lines and Recommend Target Swaps (option D) work there: the count comes from Engine/Sim/Targets.lua's token plates,
-- the debuffs on the other enemies from the belief's plate memory (Facade.DebuffCount, lane T2m). Nothing is stubbed.
local ld = require("Forever.helpers.load_druid")
local headless = require("Game.harness.headless")
local mw = require("Forever.helpers.map_world")
local ww = require("Forever.helpers.warrior_world")

-- A character of `class` who knows every rank of the class file's kit.
local function character(file, class, classID, specID)
    local w = ld.load(nil, file, class)
    local known = {}
    for _, a in pairs(w.abilities) do
        known[#known + 1] = a.id
        for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
            known[#known + 1] = id
        end
    end
    return {
        class = class,
        classID = classID,
        specID = specID,
        level = 60,
        known = known,
        talents = {},
        power = { type = 0, token = "MANA", max = 6000, value = 6000 },
        speed = { 2 },
    }
end

-- Each record of the Primary queue after an update: { actionName, indicator } (indicator "" for none).
local function queue(H, t)
    for _ = 1, 3 do -- the update after the change, the count's held fall, and the published set they build
        t = t + 0.6
        assert.is_true(headless.cycle(H, t))
    end
    assert.are.same({}, H.errors)
    local out, recs = H.Hekili.Engine.Output.Primary, {}
    for i = 1, out.count do
        recs[i] = { out.recs[i].actionName, out.recs[i].indicator or "" }
    end
    return recs, t
end
local function find(recs, name, indicator)
    for _, r in ipairs(recs) do
        if (name == nil or r[1] == name) and (indicator == nil or r[2] == indicator) then
            return r
        end
    end
end
local function names(recs)
    local s = {}
    for i, r in ipairs(recs) do
        s[i] = r[1] .. (r[2] ~= "" and ("@" .. r[2]) or "")
    end
    return table.concat(s, " ")
end

describe("a dungeon pull through the token plate count (T1)", function()
    it("Elemental: 3 plates count 3 and the AoE totem line fires; 1 plate: the single-target one", function()
        local H = mw.new("C", {
            character = character("src/Hekili_Shaman/Shaman.lua", "SHAMAN", 7, 1489),
            pack = "Elemental (wowsims.com)",
        })
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        for k = 1, 3 do
            mw.plate(H, k)
        end
        mw.target(H, 1)
        local recs, t = queue(H, H.ctl.now)
        assert.are.equal(3, H.Hekili.State.active_enemies)
        assert.is_truthy(find(recs, "magma_totem"), names(recs))
        assert.is_nil(find(recs, "searing_totem"), names(recs))
        mw.unplate(H, 2)
        mw.unplate(H, 3)
        recs = queue(H, t)
        assert.are.equal(1, H.Hekili.State.active_enemies)
        assert.is_truthy(find(recs, "searing_totem"), names(recs))
        assert.is_nil(find(recs, "magma_totem"), names(recs))
    end)

    it(
        "Destruction with Recommend Target Swaps: its curse and DoTs swap to the other plate until it carries them",
        function()
            local H = mw.new("C", {
                character = character("src/Hekili_Warlock/Warlock.lua", "WARLOCK", 9, 1490),
                pack = "Destruction (wowsims.com)",
            })
            assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
            local spec = H.Hekili.Engine.settings.specs[100093]
            local A = H.Hekili.Class.abilities
            local SPREAD = { "curse_of_the_elements", "immolate", "corruption" } -- the cycle_targets=1 lines' debuffs
            mw.plate(H, 1)
            mw.plate(H, 2)
            mw.target(H, 1)
            local t = H.ctl.now
            local start = t
            local recs
            recs, t = queue(H, t)
            assert.are.equal(2, H.Hekili.State.active_enemies)
            assert.is_nil(find(recs, nil, "cycle"))
            -- the enemies the belief holds aura `k` up on now (Facade.DebuffCount: active_dot's source; the State after an
            -- update is the queue's last simulated step, where Conflagrate may have eaten an Immolate)
            local function carriers(k)
                return H.ns.Facade.DebuffCount(H.Hekili.Class.auras[k].id, t)
            end
            local n = 0
            local function cast(id) -- our cast on the current target, folded there (the belief's drain) before a tab
                n = n + 1
                t = t + 0.1
                H.ctl.now = t
                H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-map" .. n, id)
                t = t + 0.2
                assert.is_true(headless.cycle(H, t))
            end
            local function tab(k)
                mw.target(H, k)
                t = t + 0.2
                assert.is_true(headless.cycle(H, t))
            end
            for _, k in ipairs(SPREAD) do -- on mob A, our target
                cast(A[k].id)
            end
            recs, t = queue(H, t)
            assert.is_nil(find(recs, nil, "cycle"), "toggle off: no swap " .. names(recs))
            spec.cycle = true
            recs, t = queue(H, t)
            local first = names(recs)
            assert.is_truthy(find(recs, "curse_of_the_elements", "cycle"), first)
            tab(2) -- the swap to mob B: the curse and Havoc only
            cast(A.curse_of_the_elements.id)
            cast(A.bane_of_havoc.id) -- Havoc (other_target=1) on B, for A
            tab(1)
            recs, t = queue(H, t)
            local dots = names(recs)
            assert.are.equal(2, carriers("curse_of_the_elements"))
            assert.is_nil(find(recs, "curse_of_the_elements", "cycle"), dots)
            assert.is_truthy(
                find(recs, "immolate", "cycle") or find(recs, "corruption", "cycle"),
                "a DoT swap " .. dots
            )
            tab(2) -- the DoTs on B
            cast(A.immolate.id)
            cast(A.corruption.id)
            tab(1)
            recs, t = queue(H, t)
            print(
                ("\nDestruction under Map (t %.1f s after the first cast): %s; curse on both: %s; all on both: %s"):format(
                    t - start,
                    first,
                    dots,
                    names(recs)
                )
            )
            for _, k in ipairs(SPREAD) do
                assert.are.equal(2, carriers(k), k)
            end
            assert.is_nil(find(recs, nil, "cycle"), "every plate carries them: no swap " .. names(recs))
            spec.cycle = false
        end
    )

    it("a stable ID is never an identity: no GUID, no row destination, no count (unit-registry spec 2.8)", function()
        local H = mw.new("C")
        local I, L = H.ns.VirtualStateInternal, H.ns.VirtualStateInternal.Log
        local emit = L.Emit
        local bad = 0
        L.Emit = function(...)
            local dst = select(9, ...) -- dstGUID
            if type(dst) ~= "string" or dst:match("^%d+$") then
                bad = bad + 1
            end
            return emit(...)
        end
        mw.plate(H, 1)
        mw.target(H, 1)
        local t = H.ctl.now
        local _, settled = queue(H, t)
        t = settled
        local count = H.Hekili.State.active_enemies
        for _, k in ipairs({ 0, 1 }) do
            mw.target(H, k)
            _, t = queue(H, t)
            assert.is_true((I.targetID or 0) > 0, "an ID is held")
            assert.is_nil(H.ns.Facade.UnitGUID("target"))
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-id" .. k, ww.character().known[1])
            _, t = queue(H, t)
        end
        assert.are.equal(count, H.Hekili.State.active_enemies)
        assert.are.equal(0, bad)
    end)

    -- integ/dot review I1 (the owner's no-jitter rule): a dotted mob's plate leaving forgets its debuffs in the belief
    -- at once, so the enemy count must not stay one update above the debuff count: no swap flash on that update.
    describe("a dotted plate leaving shows no swap on the first update after", function()
        local H, A, t, n
        local function boot(plates)
            H = mw.new("C", {
                character = character("src/Hekili_Warlock/Warlock.lua", "WARLOCK", 9, 1490),
                pack = "Destruction (wowsims.com)",
            })
            assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
            H.Hekili.Engine.settings.specs[100093].cycle = true
            A, t, n = H.Hekili.Class.abilities, H.ctl.now, 0
            for k = 1, plates do
                mw.plate(H, k)
            end
            mw.target(H, 1)
        end
        local function cast(id)
            n = n + 1
            t = t + 0.1
            H.ctl.now = t
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-gone" .. n, id)
            t = t + 0.2
            assert.is_true(headless.cycle(H, t))
        end
        local function tab(k)
            mw.target(H, k)
            t = t + 0.2
            assert.is_true(headless.cycle(H, t))
        end
        local function first() -- the queue of the one update right after the change
            t = t + 0.2
            assert.is_true(headless.cycle(H, t))
            assert.are.same({}, H.errors)
            local out, recs = H.Hekili.Engine.Output.Primary, {}
            for i = 1, out.count do
                recs[i] = { out.recs[i].actionName, out.recs[i].indicator or "" }
            end
            return recs
        end

        it("Destruction, 3 mobs carrying the curse, Immolate and Corruption: one leaves, no swap", function()
            boot(3)
            for k = 1, 3 do
                tab(k)
                for _, a in ipairs({ "curse_of_the_elements", "immolate", "corruption" }) do -- the cycled lines' debuffs
                    cast(A[a].id)
                end
                if k == 2 then
                    cast(A.bane_of_havoc.id)
                end
            end
            tab(1)
            local recs
            recs, t = queue(H, t)
            assert.is_nil(find(recs, nil, "cycle"), "all 3 carry them " .. names(recs))
            mw.unplate(H, 3)
            recs = first()
            assert.is_nil(find(recs, nil, "cycle"), "first update after C's plate left " .. names(recs))
        end)

        it("Destruction, Havoc on B: B leaves, no Havoc on the first update", function()
            boot(2)
            tab(2)
            cast(A.bane_of_havoc.id)
            tab(1)
            local recs
            recs, t = queue(H, t)
            assert.is_nil(find(recs, "bane_of_havoc"), "Havoc is up on B " .. names(recs))
            mw.unplate(H, 2)
            recs = first()
            assert.is_nil(find(recs, "bane_of_havoc"), "first update after B's plate left " .. names(recs))
        end)

        -- The stable IDs' adoption (unit-registry spec 2.8): the tab hides the line (the count unknown), and the late
        -- plate must not bring it back before the next tab (on, off, on).
        it("Destruction, Havoc on nobody: a late plate after the tab brings no Havoc before the next tab", function()
            boot(2)
            local function havoc()
                return H.ns.Facade.DebuffCount(A.bane_of_havoc.id, t)
            end
            for k = 2, 1, -1 do -- both plates carry the cycled lines' debuffs, so the queue has room for Havoc's line
                tab(k)
                for _, a in ipairs({ "curse_of_the_elements", "immolate", "corruption" }) do
                    cast(A[a].id)
                end
            end
            local recs
            recs, t = queue(H, t)
            assert.are.equal(0, havoc(), "on A")
            assert.is_truthy(find(recs, "bane_of_havoc"), "on A: Havoc shows " .. names(recs))
            mw.target(H, 0)
            recs = first() -- one update lands before the plate: the queue shows its answer an update later
            assert.is_nil(havoc(), "no plate yet")
            H.ctl.unitIs.target, H.ctl.unitIs.nameplate3 = "nameplate3", "target"
            mw.plate(H, 3)
            recs = first()
            assert.is_nil(find(recs, "bane_of_havoc"), "the tab's unknown count hides the line " .. names(recs))
            recs, t = queue(H, t)
            assert.is_nil(find(recs, "bane_of_havoc"), "the late plate's mob, settled " .. names(recs))
            assert.is_nil(havoc(), "still unknown")
            mw.target(H, 1)
            recs, t = queue(H, t)
            assert.is_truthy(find(recs, "bane_of_havoc"), "the next tab: Havoc is back " .. names(recs))
        end)

        -- The accepted trade-off of I1's fix (swaps read the count before the hold): a plate that flaps (REMOVED, then
        -- ADDED the next update) while it is the only enemy lacking the debuffs disarms the swap for that one update,
        -- while the held count (AoE lines, the display) stays. A dotted add dying is far more common than an edge flap
        -- (owner no-jitter rule, ledger L709). Pinned so a change is visible.
        it("a flapping plate, the only one lacking the debuffs, disarms the swap for one update (trade-off)", function()
            boot(3)
            for k = 1, 2 do
                tab(k)
                for _, a in ipairs({ "curse_of_the_elements", "immolate", "corruption" }) do
                    cast(A[a].id)
                end
                if k == 2 then
                    cast(A.bane_of_havoc.id)
                end
            end
            tab(1)
            local recs
            recs, t = queue(H, t)
            assert.is_truthy(find(recs, nil, "cycle"), "C lacks them: a swap shows " .. names(recs))
            mw.unplate(H, 3)
            recs = first()
            local held, _, unheld = H.ns.getNumberTargets()
            assert.are.same({ 3, 2 }, { held, unheld }, "the dip update: count held, swaps see 2")
            assert.is_nil(find(recs, nil, "cycle"), "the dip update: swap disarmed " .. names(recs))
            mw.plate(H, 3)
            recs = first()
            assert.is_truthy(find(recs, nil, "cycle"), "C back: the swap re-arms at once " .. names(recs))
        end)
    end)

    -- Ledger L1734 (owner's A): a hard Immolate sent at mob A, a tab to B during its cast. The belief lands it on A at
    -- the success; the core's compare must read the tab during the cast (by GUID in the open world, by the stable ID
    -- under Map), so B's queue shows Immolate before the success as after it: no flip.
    describe("a hard cast that lands after a tab (L1734)", function()
        local H, A, S, t
        -- World `w` ("A" open, "C" Map), both in combat with the target's walk raising; curse and Doom on plates 2 and 1.
        local function boot(w)
            H = mw.new(w, {
                character = character("src/Hekili_Warlock/Warlock.lua", "WARLOCK", 9, 1490),
                pack = "Destruction (wowsims.com)",
            })
            assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
            if w == "A" then
                H.ctl.combat = true
                H.ctl.auraError.target = true
                H.Fire("PLAYER_REGEN_DISABLED")
            end
            A, S = H.Hekili.Class.abilities, H.Hekili.State
            mw.plate(H, 1)
            mw.plate(H, 2)
            t = H.ctl.now
            local n = 0
            for _, k in ipairs({ 2, 1 }) do
                mw.target(H, k)
                t = t + 0.2
                assert.is_true(headless.cycle(H, t))
                for _, key in ipairs({ "curse_of_the_elements", "bane_of_doom" }) do
                    n = n + 1
                    t = t + 0.1
                    H.ctl.now = t
                    H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-pre" .. n, A[key].id)
                    t = t + 0.2
                    assert.is_true(headless.cycle(H, t))
                end
            end
            t = t + 1.5
            assert.is_true(headless.cycle(H, t))
        end
        local function step()
            t = t + 0.1
            assert.is_true(headless.cycle(H, t))
            assert.are.same({}, H.errors)
            local out, r = H.Hekili.Engine.Output.Primary, {}
            for i = 1, out.count do
                r[i] = { out.recs[i].actionName, out.recs[i].indicator or "" }
            end
            return r
        end
        -- Immolate sent at the target, its cast bar 2 s; one update on it.
        local function send()
            H.ctl.now = t
            H.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-I1", A.immolate.id)
            H.ctl.casting = { t * 1000, (t + 2) * 1000 }
            H.Fire("UNIT_SPELLCAST_START", "player", "Cast-I1", A.immolate.id)
            step()
        end
        local function succeed()
            H.ctl.now = t
            H.ctl.casting = nil
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-I1", A.immolate.id)
        end
        -- The core's view past the cast's end: Immolate on the target, and on how many.
        local function atEnd()
            S.reset("Primary")
            S.advance(2.1)
            return { S.debuff.immolate.up, S.active_dot.immolate }
        end

        for _, w in ipairs({ "A", "C" }) do
            it(
                "world " .. w .. ": B's queue shows Immolate from the update after the tab, unchanged at the success",
                function()
                    boot(w)
                    send()
                    assert.are.same({ true, 1 }, atEnd(), "no tab: it lands on the target")
                    mw.target(H, 2)
                    step() -- the tab's own update
                    local before = step()
                    assert.is_truthy(find(before, "immolate"), names(before))
                    assert.are.same({ false, 1 }, atEnd(), "after the tab: on A, counted, not on B")
                    for _ = 1, 10 do
                        assert.are.same(before, step(), "during the cast")
                    end
                    succeed()
                    for _ = 1, 6 do
                        assert.are.same(before, step(), "at and after the success")
                    end
                end
            )
        end

        -- The real queue's Immolate CAST_FINISH start (nil none).
        local function queuedStart()
            for _, e in ipairs(S:GetQueue(true)) do
                if e.action == "immolate" and e.type == "CAST_FINISH" then
                    return e.start
                end
            end
        end

        for _, w in ipairs({ "A", "C" }) do
            it("world " .. w .. ": a pushback after the tab is the same cast, on A: no flip at it", function()
                boot(w)
                local t0 = t
                send()
                mw.target(H, 2)
                step()
                local before = step()
                assert.is_truthy(find(before, "immolate"), names(before))
                H.ctl.now = t
                H.ctl.casting = { (t0 + 0.5) * 1000, (t0 + 2.5) * 1000 } -- the bar's start and end move on
                H.Fire("UNIT_SPELLCAST_DELAYED", "player", "Cast-I1", A.immolate.id)
                assert.is_true(math.abs(queuedStart() - (t0 + 0.5)) < 1e-6, "the core re-queued it")
                for _ = 1, 10 do
                    assert.are.same(before, step(), "after the pushback")
                end
                assert.are.same({ false, 1 }, atEnd(), "on A, counted, not on B")
                succeed()
                for _ = 1, 6 do
                    assert.are.same(before, step(), "at and after the success")
                end
            end)
        end

        -- Cast Immolate (Cast-I<k>) on the target with its bar starting at `from`, then one update.
        local function recast(k, from)
            H.ctl.now = t
            H.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-I" .. k, A.immolate.id)
            H.ctl.casting = { from * 1000, (from + 2) * 1000 }
            H.Fire("UNIT_SPELLCAST_START", "player", "Cast-I" .. k, A.immolate.id)
        end
        -- B's queue does not change from the update after the cast's start to after its success.
        local function steady(k)
            local during = step()
            for _ = 1, 10 do
                assert.are.same(during, step(), "during the cast")
            end
            H.ctl.now = t
            H.ctl.casting = nil
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-I" .. k, A.immolate.id)
            for _ = 1, 6 do
                assert.are.same(during, step(), "at and after the success")
            end
        end

        it("under Map, a cast stopped after the tab and cast again on B is a new cast: on B", function()
            boot("C")
            send()
            mw.target(H, 2)
            step()
            H.ctl.now = t
            H.ctl.casting = nil
            H.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-I1", A.immolate.id)
            step()
            assert.is_nil(queuedStart(), "the core dropped it")
            recast(2, t) -- before the stopped cast's finish
            step()
            assert.are.same({ true, 1 }, atEnd(), "sent at B: on B")
            steady(2)
        end)

        -- Immolate sent on A, a tab to B, updates up to its finish, its success; then the next Immolate on B, its bar
        -- starting `lead` s before the first's finish, after an update or in the success's own frame.
        local function chain(lead, between)
            boot("C")
            local t0 = t
            send()
            mw.target(H, 2)
            while t < t0 + 1.95 do
                step()
            end
            succeed()
            if between then
                step()
            end
            recast(2, t0 + 2 - lead)
            step()
            return atEnd()
        end

        it("under Map, the next Immolate on B is a new cast at the last one's finish (spell queue window)", function()
            assert.are.same({ true, 2 }, chain(0), "the first on A, this one on B")
            steady(2)
        end)

        it("under Map, the next Immolate on B is a new cast after an update without the last one", function()
            assert.are.same({ true, 2 }, chain(0.05, true), "the first on A, this one on B")
            steady(2)
        end)

        it("a known limit: under Map the next Immolate on B, in the success's frame, starting early, is A's", function()
            -- shortcut: no update saw the last one leave and its start is before the pinned finish, so it reads as
            -- that cast (the core sim has it on A, the belief on B: one flip at its success)
            assert.are.same({ false, 2 }, chain(0.05), "the core pinned it as the first one")
        end)

        it("the known limit: under Map a tab before the first update after the cast's start flips once", function()
            boot("C")
            H.ctl.now = t
            H.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-I1", A.immolate.id)
            H.ctl.casting = { t * 1000, (t + 2) * 1000 }
            H.Fire("UNIT_SPELLCAST_START", "player", "Cast-I1", A.immolate.id)
            mw.target(H, 2) -- no update between: the core pins mob B's ID
            step()
            local before = step()
            assert.is_nil(find(before, "immolate"), "the core believes it lands on B " .. names(before))
            for _ = 1, 16 do
                step()
            end
            succeed()
            step()
            local after = step()
            assert.is_truthy(find(after, "immolate"), "the belief has it on A " .. names(after))
        end)

        it("under Map, a plain target on either side of the tab still reads as a swap", function()
            boot("C")
            H.ctl.guid.target, H.ctl.unitIs.target, H.ctl.unitIs.nameplate1 = "Player-1", nil, nil
            H.Fire("PLAYER_TARGET_CHANGED") -- a target read plain (a party member, say)
            step()
            assert.are.equal(0, H.ns.Facade.TargetID())
            send()
            mw.target(H, 2)
            step()
            assert.are.same({ false, 1 }, atEnd(), "sent at the plain target: its GUID tells the tab")
            boot("C")
            send()
            H.ctl.guid.target, H.ctl.unitIs.target, H.ctl.unitIs.nameplate1 = "Player-1", nil, nil
            H.Fire("PLAYER_TARGET_CHANGED")
            step()
            assert.are.same({ false, 1 }, atEnd(), "sent at plate 1's mob: the ID tells the tab to a plain target")
        end)
    end)
end)
