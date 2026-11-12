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
            local recs
            recs, t = queue(H, t)
            assert.are.equal(2, H.Hekili.State.active_enemies)
            assert.is_nil(find(recs, nil, "cycle"))
            local n = 0
            local function cast(id)
                n = n + 1
                t = t + 0.1
                H.ctl.now = t
                H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-map" .. n, id)
                local _
                _, t = queue(H, t) -- a GCD and more between casts, each folded on its target
            end
            for _, k in ipairs(SPREAD) do -- on mob A, our target
                cast(A[k].id)
            end
            recs, t = queue(H, t)
            assert.is_nil(find(recs, nil, "cycle"), "toggle off: no swap " .. names(recs))
            spec.cycle = true
            recs, t = queue(H, t)
            local before = names(recs)
            assert.is_truthy(find(recs, nil, "cycle"), before)
            mw.target(H, 2) -- the swap: mob B
            recs, t = queue(H, t)
            for _, k in ipairs(SPREAD) do
                cast(A[k].id)
            end
            cast(A.bane_of_havoc.id) -- Havoc (other_target=1) on B, for A
            mw.target(H, 1) -- back to mob A
            recs, t = queue(H, t)
            print("\nDestruction under Map: before the swap " .. before .. "; after " .. names(recs))
            for _, k in ipairs(SPREAD) do
                assert.are.equal(2, H.Hekili.State.active_dot[k], k)
            end
            assert.is_nil(find(recs, nil, "cycle"), "every plate carries them: no swap " .. names(recs))
            spec.cycle = false
        end
    )
end)
