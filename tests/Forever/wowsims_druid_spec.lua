-- tests/Forever/wowsims_druid_spec.lua (wowsims packs plan, Task 7): the Druid wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.druid_loop_world")
local loop = require("Game.harness.loop")
local replay = require("Game.harness.replay")
local headless = require("Game.harness.headless")

-- Berserk (417141) is a talent's spell with no trainer level: known through its talent's points only, not the
-- worlds' kit list (which a missing level would teach at 1).
local LEARN = setmetatable({ [417141] = math.huge }, { __index = ws.learn("DRUID") })

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = LEARN,
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

describe("the Druid wowsims.com packs #slow #wowsims", function()
    it("Feral's replay world reports the energy rate the client reads", function()
        local C = content("druid_feral", W.Feral, "Feral (wowsims.com)", 60)
        local R = replay.new(ws.log("druid_feral"), loop.new(C).oracle, {})
        assert.is_true(R.world(setmetatable({ pt = 3 }, { __index = C.WORLD }), 1).rates[3] > 0)
    end)

    -- the replay floor: 0.932 measured on central fix 13 (82/88: the observer's cooldown restart); 0.955 (84/88) on
    -- central fix 14 (Shifting Power's function cooldown in the belief), never lowered
    it("Feral (wowsims.com) follows wowsims's casts", function()
        ws.gate("Feral (wowsims.com)", content("druid_feral", W.Feral, "Feral (wowsims.com)", 60), "druid_feral", 0.95)
    end)
    -- the pack's own worst idle at 60 (wowsims's energy pooling), seconds: 4.0 on central fix 22 round 1 (the live
    -- world's presses resolve from the driving instance, not the never-stepped oracle; L20 4.0 -> 3.0, L40 3.8 -> 3.4,
    -- L60 3.8 -> 4.0); 4.2 before
    local FERAL60 = 4.0
    for _, level in ipairs({ 20, 40, 60 }) do
        it("Feral (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Feral (wowsims.com)",
                content("druid_feral", W.Feral, "Feral (wowsims.com)", level),
                math.max(6, FERAL60)
            )
        end)
    end

    it("Guardian (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Guardian (wowsims.com)",
            content("druid_guardian", W.Guardian, "Guardian (wowsims.com)", 60),
            "druid_guardian",
            0.80, -- 0.782 (61/78) with Primal Fury's onCrit (central fix 15) and the bear's 11.25 a swing; 0.808 (63/78)
            -- once the replay ends a cooldown at its log timestamp (the ready-time ruling)
            -- Maul's untagged Casting lines are wowsims's queue at each swing (Cost = 0); its Tag 1 line is the hit,
            -- when the game's cast succeeds
            { procs = { ["9881:0"] = true } }
        )
    end)
    -- wowsims's sim starts in Dire Bear Form, so its list never shifts; the recipe's `bear_form` line does (a
    -- sim-setup difference: never fires in the replay)
    it("Guardian (wowsims.com) recommends Bear Form out of it", function()
        local c = W.Guardian.character()
        c.form, c.power = 0, { type = 0, token = "MANA", max = 4000, value = 4000 } -- caster form: mana
        local H = headless.new({ character = c, pack = "Guardian (wowsims.com)" })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        assert.are.same({}, H.errors)
        local out = H.Hekili.Engine.Output.Primary
        assert.are.equal("bear_form", out.recs[1] and out.recs[1].actionName)
    end)
    -- The recipe's leveling Demoralizing Roar filler is behind the pack setting `demoralizing_roar_filler` (user,
    -- 2026-10-21; default on): off, a level 10 bear in Bear Form with the rage for it and the Roar already on the
    -- target is shown something else
    it("Guardian (wowsims.com)'s Demoralizing Roar filler is skipped with its setting off", function()
        local function first(on)
            local c = content("druid_guardian", W.Guardian, "Guardian (wowsims.com)", 10).character()
            local p = c.power
            c.power = { type = p.type, token = p.token, max = p.max, value = 30 } -- Roar's 10 (a copy: the world's own is shared)
            local H = headless.new({ character = c, pack = "Guardian (wowsims.com)" })
            assert.are.same({}, H.loadErrors)
            local hk = H.Hekili
            local settings = hk.DB.profile.specs[hk.State.spec.id].settings
            assert.is_true(settings.demoralizing_roar_filler) -- the registered default
            settings.demoralizing_roar_filler = on
            H.ctl.inRange.target, H.ctl.level.target = true, 10
            H.Fire("PLAYER_TARGET_CHANGED")
            H.ctl.auras.target.HARMFUL[1] = { -- the Roar up: keep_up's own Roar line stands aside
                name = "Demoralizing Roar",
                spellId = hk.Class.auras.demoralizing_roar.id,
                expirationTime = H.ctl.now + 30,
                duration = 30,
                applications = 1,
                sourceUnit = "player",
            }
            H.Fire("UNIT_AURA", "target")
            assert.is_true(hk.Engine.Subscribe("Primary", function() end))
            assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
            assert.are.same({}, H.errors)
            local names = {}
            for i, r in ipairs(hk.Engine.Output.Primary.recs) do
                names[i] = r.actionName
            end
            return table.concat(names, " ")
        end
        local f = assert(io.open("src/Hekili_Druid/APLs/Guardian (wowsims.com).simc", "rb"))
        local simc = f:read("*a")
        f:close()
        assert.matches("\n# Setting demoralizing_roar_filler %(", simc)
        assert.matches(
            "\nactions%+=/demoralizing_roar,if=settings%.demoralizing_roar_filler&!action%.lacerate%.known",
            simc
        )
        assert.matches("demoralizing_roar", first(true))
        assert.not_matches("demoralizing_roar", first(false))
    end)
    -- The pack's own worst idle at 60, seconds: 5.8 on central fix 22 round 2 (presses resolve from the current state,
    -- not Update's leftover prediction: a predicted Berserk had dropped Primal Bite's cooldown in the world, 9.2);
    -- 10.0 before (L10 10.0, L40 9.6, L60 8.4 with the gate counting only on-GCD presses, final review fix 3: Maul, off
    -- the GCD, no longer resets the idle streak). L10 presses the recipe's leveling Maul (wowsims's list has nothing
    -- else before Primal Bite at 25: 11.8 s idle without it); before Lacerate (42) its leveling Demoralizing Roar fills
    -- a GCD at 10 rage and Faerie Fire (Feral) below it, at most every 6 s (the kit's cooldown in a form): Demoralizing
    -- Roar took L10 to 0.2 s and L40 to 8.4 s, Faerie Fire L40 from 8.4 to 2.6 s (0.4 and 2.8 rebased)
    local GUARDIAN60 = 5.8
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Guardian (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Guardian (wowsims.com)",
                content("druid_guardian", W.Guardian, "Guardian (wowsims.com)", level),
                math.max(6, GUARDIAN60)
            )
        end)
    end

    it("Balance (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Balance (wowsims.com)",
            content("druid_balance", W.Balance, "Balance (wowsims.com)", 60),
            "druid_balance",
            -- 0.909 (50/55) on central fix 22 (cast bars: the DoT-refresh replay limit gone); 0.855 (47/55) on central
            -- fixes 14-15 (Task 7g); 0.836 on central fix 13 over fix 12; 0.818 on central fix 12 (GAP R), from 0.56
            0.90
        )
    end)
    -- wowsims's sim starts in Moonkin Form (its list never casts it); the recipe's `moonkin_form` line does, once
    -- the form is known (a sim-setup difference: never fires in the replay)
    it("Balance (wowsims.com) recommends Moonkin Form out of it", function()
        local function first(level)
            local c = W.Balance.character()
            c.form, c.level = 0, level -- caster form
            local H = headless.new({ character = c, pack = "Balance (wowsims.com)" })
            assert.are.same({}, H.loadErrors)
            H.ctl.inRange.target, H.ctl.level.target = true, 60
            H.Fire("PLAYER_TARGET_CHANGED")
            assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
            assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
            assert.are.same({}, H.errors)
            local out = H.Hekili.Engine.Output.Primary
            return out.recs[1] and out.recs[1].actionName
        end
        assert.are.equal("moonkin_form", first(40))
        assert.are.equal("moonkin_form", first(60))
    end)
    -- The pack's own worst idle at 60, seconds: 0.0 on central fix 22 (L10 0.0, L40 0.0: the cast bars chain the
    -- casts; the live world's presses now resolve from the driving instance, so a Clearcasting free cast is free in the
    -- world too: the 10.8 s measured before that was the world refusing Moonfire for cost under Clearcasting, read
    -- from the never-stepped oracle); 1.4 (L10 1.6, L40 1.4: Task 7g, after shared gap R's fix; 8.6 before it)
    local BALANCE60 = 0.0
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Balance (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Balance (wowsims.com)",
                content("druid_balance", W.Balance, "Balance (wowsims.com)", level),
                math.max(6, BALANCE60)
            )
        end)
    end
end)
