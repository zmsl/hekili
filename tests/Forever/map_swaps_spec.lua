-- tests/Forever/map_swaps_spec.lua (T1 task 7; ledger L643): in a dungeon (the Map restriction: every unit identity
-- secret, in combat, the target's auras unreadable) the token plate count gives the engine its enemies, so the AoE
-- lines and Recommend Target Swaps (option D) work there: the count comes from Engine/Sim/Targets.lua's token plates,
-- the debuffs on the other enemies from the belief's plate memory (Facade.DebuffCount, lane T2m). Nothing is stubbed.
local ld = require("Forever.helpers.load_druid")
local headless = require("Game.harness.headless")
local mw = require("Forever.helpers.map_world")

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
end)
