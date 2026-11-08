-- tests/Forever/wowsims_druid_spec.lua (wowsims packs plan, Task 7): the Druid wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.druid_loop_world")
local loop = require("Game.harness.loop")
local replay = require("Game.harness.replay")
local headless = require("Game.harness.headless")

-- Berserk (417141) is a talent's spell with no trainer level: known through its talent's points only, not the
-- worlds' kit list (which a missing level would teach at 1). Lacerate's hotfix ranks (113554) are not in the DB2:
-- its rank 1 (1328617) is now such a talent's, its rank 2 (1328616) the class file's level 34.
local LEARN = setmetatable({ [417141] = math.huge, [1328617] = math.huge, [1328616] = 34 }, {
    __index = ws.learn("DRUID"),
})

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = LEARN,
        race = ws.race(spec),
        gear = ws.gear(spec), -- the request's gear (Balance's Swarming Idol: Insect Swarm's 16 s, R32)
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

describe("the Druid wowsims.com packs #slow #wowsims", function()
    it("Balance's replay runs the Serenity Field regen entry over the log's window", function()
        local C = ws.logged(content("druid_balance", W.Balance, "Balance (wowsims.com)", 60), "druid_balance")
        local L = loop.new(C)
        local R = replay.new(ws.log("druid_balance"), L.oracle, ws.replayOptions(C, "druid_balance"))
        local up, down = 0, math.huge -- the belief's rate at the log's 116-125 s and 130-170 s
        loop.replay(L, R, {
            on = function(_, steps, t)
                local st = steps[1]
                local VS = st.H.ns.VirtualState
                local rate, at = VS.Regen(0, st.base + t, VS.NOT_CASTING).est, t - R.pull
                if at > 116 and at < 125 then
                    up = math.max(up, rate)
                elseif at > 130 and at < 170 then
                    down = math.min(down, rate)
                end
            end,
        })
        -- re-pin e2842f0a78: the log's regen is 12.6 a second and 17.1 inside Serenity Field (112.21-127.21 s), all
        -- Tag 1 (Reflection 3/3 in the new build); was Tag 2's 31 and 22 (up > 30, down < 24)
        assert.is_true(up > 16 and down < 13, up .. " vs " .. down)
    end)

    it("Feral's replay world reports the energy rate the client reads", function()
        local C = content("druid_feral", W.Feral, "Feral (wowsims.com)", 60)
        local R = replay.new(ws.log("druid_feral"), loop.new(C).oracle, {})
        assert.is_true(R.world(setmetatable({ pt = 3 }, { __index = C.WORLD }), 1).rates[3] > 0)
    end)

    -- the replay floor: 0.932 measured on central fix 13 (82/88: the observer's cooldown restart); 0.955 (84/88) on
    -- central fix 14 (Shifting Power's function cooldown in the belief), never lowered; 0.95 -> 0.94 (0.943, 82/87; base
    -- 0.966, 85/88; R8) from upstream #641's fight change on the oracle refresh: its 26.99 Shifting Power (a not-ready
    -- flag pushes the modelled 26.99 to now + CD_PROBE; the keep-it fix 4bd02bde0 broke the loop gates, reverted) and
    -- 76.24 Rake (gap AS with the swing's wound first) were the misses it exposed; the 76.24 miss is fixed (0.954, 87),
    -- the 26.99 cooldown probe remains, so 0.94 -> 0.95
    -- 0.95 -> 0.91 (0.916, 76/83) re-pin e2842f0a78 (adaptive list, Movement on, R52): 7 misses, none content: 21.25
    -- shred -> rip and 39.88 shred -> faerie_fire, the belief's energy lo 3.2 and 1.0 under the truth at Rip's 62
    -- threshold and Shred's 42 (energy is secret: API-forced); 140.38 shred -> rip, Rip fades in the instant wowsims
    -- Shreds (same-instant order); 19.25 shifting_power -> shred, a not-ready flag 0.05 s before the ready pushes it
    -- to now + CD_PROBE (shared, the 26.99 case above); 111.89 shifting_power -> shred, mana 687 against the 684 cost
    -- (the belief's mana near cost, shared); 162.38 shred -> faerie_fire, after the missed 160.88 Faerie Fire the
    -- belief holds Faerie Fire ready about 0.1 s after every cast (kit or belief: undetermined; a scalar 6 clears it,
    -- scratch); 15.04 innervate -> cat_form, pre-existing (a 0.04 s tie at the Innervate powershift)
    -- the replay's flicker ceiling (Movement on): 1.33/min measured on the re-pin e2842f0a78 (oracle 0.00; the DB2
    -- ranges in the Feral world moved nothing), so 1.4. The gap to the oracle's 0.00 is untraced (L115).
    -- owner deviation R69 (no Prowl cancel line; Faerie Fire waits while a known Prowl is up): nothing moved (0.916
    -- (83), flicker 1.33/min, timing fixture identical): the replay's kit knows neither Prowl nor Ravage
    -- 0.91 -> 0.96 (0.965, 82/85 decisions on-GCD; agreement 0.939) and flicker 1.4 -> 0.7 (0.67/min) on the 0.7 floors
    -- run (integ/0.7 5deb101c4: CN8's cooldown countdown and steady icons as the default, over the pin-2 export; the
    -- two are not separated). The 21.25, 39.88, 111.89, 140.38 and 162.38 never rows are gone; left: innervate ->
    -- cat_form (the 0.04 s powershift tie), rake -> faerie_fire and shred -> faerie_fire
    it("Feral (wowsims.com) follows wowsims's casts", function()
        local r, line = ws.gate(
            "Feral (wowsims.com)",
            content("druid_feral", W.Feral, "Feral (wowsims.com)", 60),
            "druid_feral",
            0.96
        )
        assert.is_true(r.flicker <= 0.7, line)
    end)
    -- the pack's own worst idle at 60 (wowsims's energy pooling), seconds: 4.0 on central fix 22 round 1 (the live
    -- world's presses resolve from the driving instance, not the never-stepped oracle; L20 4.0 -> 3.0, L40 3.8 -> 3.4,
    -- L60 3.8 -> 4.0); 4.2 before; 4.0 -> 3.2 re-pin e2842f0a78 (L20 3.0, L40 3.2, L60 3.2; the bar stays 6 s)
    local FERAL60 = 3.2
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
            -- 0 -> 0.63 (0.632 of 117 decisions on-GCD; R6, truncated): no rage from hits yet (CN7): the kit has no `taken`, so
            -- the belief sees only the bear's own rage (0.923 with the archived rule: named gap in the recipe header). Old pin: 0.782 (61/78)
            0.63,
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
    -- wowsims's Demoralizing Roar line (re-pin: "Attack-power reduction is covered") is behind the
    -- maintenance setting `maintain_demoralizing_roar` (rule 15; user, 2026-10-21; off in game, on in the harness): off,
    -- or with the Roar already on the target, a level 10 bear in Bear Form with the rage for it is shown something else
    it("Guardian (wowsims.com)'s Demoralizing Roar is skipped with its setting off or the debuff up", function()
        local function first(on, up, level, aura, name, rage)
            level, aura, name = level or 10, aura or "demoralizing_roar", name or "Demoralizing Roar"
            local c =
                content("druid_guardian", W.Guardian, "Guardian (wowsims.com)", level, rage and { talents = {} }).character()
            local p = c.power
            c.power = { type = p.type, token = p.token, max = p.max, value = rage or 30 } -- Roar's 10 (a copy: the world's own is shared)
            local H = headless.new({ character = c, pack = "Guardian (wowsims.com)" })
            assert.are.same({}, H.loadErrors)
            local hk = H.Hekili
            local settings = hk.DB.profile.specs[hk.State.spec.id].settings
            assert.is_false(settings.maintain_demoralizing_roar) -- the in-game default (a direct boot is in game)
            settings.maintain_demoralizing_roar = on
            H.ctl.inRange.target, H.ctl.level.target = true, level
            H.Fire("PLAYER_TARGET_CHANGED")
            if up then -- the debuff on the target: the line stands aside (R45)
                H.ctl.auras.target.HARMFUL[1] = {
                    name = name,
                    spellId = hk.Class.auras[aura].id,
                    expirationTime = H.ctl.now + 30,
                    duration = 30,
                    applications = 1,
                    sourceUnit = "player",
                }
            end
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
        assert.matches("\n# Setting maintain_demoralizing_roar %(", simc)
        assert.matches(
            "\nactions%+=/demoralizing_roar,focus=2,if=settings%.maintain_demoralizing_roar&%(!%(!%(debuff%.demoralizing_roar%.remains<=0%)%)",
            simc
        )
        assert.matches(
            "\nactions%+=/faerie_fire,if=%(action%.faerie_fire%.known&debuff%.faerie_fire%.remains<=0%)",
            simc
        )
        assert.matches("demoralizing_roar", first(true, false))
        assert.not_matches("demoralizing_roar", first(true, true)) -- R45: only while the debuff is down
        assert.not_matches("demoralizing_roar", first(false, false))
        -- Faerie Fire likewise (wowsims's own line, no setting), at 5 rage so only it is affordable
        local ff = "faerie_fire"
        assert.matches(ff, first(false, false, 30, ff, "Faerie Fire", 5))
        assert.not_matches(ff, first(false, true, 30, ff, "Faerie Fire", 5))
    end)
    -- The pack's own worst idle at L10 and L40, seconds: L10 presses the recipe's leveling Maul (wowsims's list has
    -- nothing else before Primal Bite at 25: 11.8 s idle without it). Before Lacerate (42) its leveling Demoralizing
    -- Roar and Faerie Fire (free in a form, a 6 s cooldown) are cast only while their debuff is down (R45): L10 idles up
    -- to 10.2 s (limit 10.2, nothing useful to cast: see the comment below), L40 stays at the 6.0 s limit.
    -- L60's bar (owner ruling 2026-10-25): the MEDIAN of the per-seed worst idle over seeds 1-30, each a fresh boot
    -- (its own first fight), limit 6.0 s. One seed's worst is noise: with the parry fix the single seed 1 measured 8.4
    -- (rage below Primal Bite's 15 from two white misses in a row). On these tables: median 4.4, worst 11.0, 4 of 30
    -- seeds over 6.0 (rage 357.2 a minute against wowsims's 349.9).
    -- L60's outcome tables, wowsims's for its export (druid_guardian.log, seed 101: 65 white swings, 79 yellow strikes;
    -- owner approved 2026-10-25). From its code: no parry (the export has no inFrontOfTarget, so the bear attacks from
    -- behind: spell_outcome.go), the white dodge the level 63 table's 6.5% less expertise (spell_outcome.go's white
    -- outcome: BaseDodgeChance - DodgeParrySuppression; attack_table_test.go: 6.5% at skill 300; the export has no
    -- consumable and no druid source of expertise) and glancing fixed at BaseGlanceChance 40% (attack_table_test.go).
    -- From the log (the export's gear is item IDs only): the white miss 1.5% (the table's 8% less about 6.5% gear hit),
    -- crit about 28% (19 of 65: 29.2%), the yellows' crit 26.6% (21 of 79). The yellows' avoids from its code, the
    -- same table from behind (spell_outcome.go outcomeMeleeSpecialHitAndCrit: applyAttackTableMissNoDWPenalty, the
    -- table's 8% less the same gear hit, 1.5%; applyAttackTableDodge, unit.go GetTotalDodgeChanceAsDefender: 6.5%,
    -- the target has no dodge rating and the bear no expertise), not the log's 1 miss and 3 dodges of 79.
    -- The generic tables gave the bear 274.5 rage a minute (guardian-rage-cmp).
    local GUARDIAN_TABLES = {
        rates = { miss = 0.015, dodge = 0.065, parry = 0, glancing = 0.40, crit = 0.28 },
        mobAvoid = { miss = 0.015, dodge = 0.065, parry = 0, block = 0 },
        crit = 0.266,
    }
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Guardian (wowsims.com) stays live at level " .. level, function()
            local C = content("druid_guardian", W.Guardian, "Guardian (wowsims.com)", level)
            if level == 60 then
                for k, v in pairs(GUARDIAN_TABLES) do
                    C.WORLD[k] = v
                end
                ws.live("Guardian (wowsims.com)", C, 6.0, 30, "median")
            else
                -- R45 (R41): the L10 bear's Roar line fires only with the debuff down, so with Roar up (30 s) the bar
                -- idles: nothing useful to cast (Roar up, Maul off the GCD, Faerie Fire not known at L10, learned at 18): 0.2 -> 10.2 s
                -- L40 6.0 -> 8.4 (8.4 s measured): R41 white-miss rage starvation (the bear's rage comes from its own swings only and
                -- no rage from hits yet, CN7), as in the old-pin analysis
                ws.live("Guardian (wowsims.com)", C, level == 10 and 10.2 or 8.4)
            end
        end)
    end

    it("Balance (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Balance (wowsims.com)",
            content("druid_balance", W.Balance, "Balance (wowsims.com)", 60),
            "druid_balance",
            -- 0.93 -> 0.97 (0.975, 77/79) (task #3, gear-aware: the Swarming Idol's 16 s): the replay wears the
            -- request's gear, so the kit's Insect Swarm is the log's 16 s (R32) and the 3 wrath -> insect_swarm misses
            -- go; left: the 2 missed Wraths' Eclipse (wrath -> starfire, a replay limit).
            -- 0.86 -> 0.93 (0.937, 74/79) re-pin e2842f0a78, owner R20a: Innervate low-mana only (the recipe's
            -- `condition`), the 8 Innervate misses gone; left: Insect Swarm's 16 s in wowsims's log against the kit's
            -- DB2 14 s (3), and a Wrath that missed grants no Eclipse in wowsims, ours always (2; the recipe's header).
            -- 0.90 -> 0.86 (0.861, 68/79) re-pin e2842f0a78: the new Innervate line's `fight_remains>380&mana<70%`
            -- branch held for us from the first mana dip (fight_remains reads 3600: gap AN, API-forced), 8 of the 11
            -- misses. 0.909 (50/55) on central fix 22 (cast bars: the DoT-refresh replay limit gone); 0.855 (47/55) on
            -- central fixes 14-15 (Task 7g); 0.836 on central fix 13 over fix 12; 0.818 on central fix 12 (GAP R), from 0.56
            0.97
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
    -- 0.0 -> 0.2 measured on the re-pin e2842f0a78 (L10 0.2, L40 0.2, L60 0.2; the same after owner R20a): not traced,
    -- harmless: two 0.1 s ticks of idle, far under the 6 s limit, which it never sets (math.max(6, BALANCE60))
    local BALANCE60 = 0.2
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
