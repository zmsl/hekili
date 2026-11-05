-- tests/Forever/wowsims_warrior_spec.lua (wowsims packs plan, Tasks 5-6): the Warrior wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log; wowsims/forever (MIT, https://github.com/wowsims/forever))
-- and at three levels.
local ws = require("Forever.helpers.wowsims")
local ww = require("Forever.helpers.warrior_world")
local loop = require("Game.harness.loop")
local replay = require("Game.harness.replay")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("WARRIOR"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- Forever's Overpower window (aura 1282733, 5 s): wowsims's Overpower condition; the client cannot list it, so the
-- replay keeps it in the truth (`hidden`) and answers Overpower's usability from it.
local ARMS = {
    kit = { "spearing_strike", "berserker_rage" },
    requires = {
        overpower = function(_, e)
            return e.auras[1282733] ~= nil and e.form == 1, "no window"
        end,
    },
}
local ARMS_REPLAY = { hidden = { [1282733] = true }, procs = {} }
-- The replay's character wields the wowsims build's main hand (p1_arms: Arcanite Reaper, 12784, ItemDelay 3800 in the
-- Forever DB2), so the client's swing speed is the log's swings' 3.8 s, not the loop world's 3.6 s weapon.
local ARMS_CHAR = setmetatable({
    character = function()
        local c = ww.character()
        c.speed = { 3.8 }
        return c
    end,
}, { __index = ww })

-- Fury: the same Overpower window (its Overpower Weaving group reads 1282733); Berserker Rage is a trained ability the
-- loop kit lacks. The base is the dual-wield world (ww.Fury), the log's own weapon speeds.
local FURY = { kit = { "berserker_rage" }, requires = ARMS.requires }
-- Whirlwind's off-hand hit (1680 Tag 15, the off hand's item slot) is logged as its own Casting line: a hit of the one cast, not a decision.
-- wowsims logs the Heroic Strike queue (25286 Tag 1) as an aura the client never shows (the client sees
-- IsCurrentSpell): hidden.
local FURY_REPLAY = { hidden = { [1282733] = true, [25286] = true }, procs = { ["1680:15"] = true }, speed = 2.1 }

-- Protection: wowsims's Revenge window is an aura it logged under Revenge's own ID (25288) before e2842f0a78, and logs
-- as the DB2's Defensive State 5302 since (5 s, from a block, dodge or parry of the target's swing). The replay does not replay the target's swings, so the
-- window stays in the truth (`hidden`) and answers Revenge's usability; the live world's mob swings at us, so there
-- Revenge keeps the world's own requirement. The Heroic Strike queue (25286 Tag 1) as Fury's. Shield Slam is the talent's
-- rank 1 plus its trained ranks (the log casts rank 4, 23925).
local PROT_KIT = { "berserker_rage", "revenge", "shield_block", "shield_slam", "shield_wall", "shield_bash", "taunt" }
local PROT = {
    kit = PROT_KIT,
    requires = {
        revenge = function(_, e)
            return (e.auras[5302] ~= nil or e.auras[25288] ~= nil) and e.form == 2, "no window"
        end,
    },
}
local PROT_REPLAY = { hidden = { [5302] = true, [25288] = true, [25286] = true }, procs = {}, speed = 2.35 }

describe("the Warrior wowsims.com packs #slow #wowsims", function()
    it("Arms (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Arms (wowsims.com)",
            content("warrior_arms", ARMS_CHAR, "Arms (wowsims.com)", 60, ARMS),
            "warrior_arms",
            -- measured 0.896: 0.910 after central fixes 7, 13 and 16 (was 0.86, provisional), less the pre-pull Berserker
            -- Rage wowsims casts at -4.5 without Improved Berserker Rage (the build has none), which the user's ruling
            -- (2026-10-21) gates on that talent (berserker_rage -> battle_shout, 1 of 67); 0.881 (59 of 67) with the world's
            -- parry haste (decision 63): the same-frame Bloodrage gap (gaps.md, fix 40); 0.896 (60 of 67) with fix 40
            0.89,
            ARMS_REPLAY
        )
    end)
    -- the replay's world is the log's: loop.run presses nothing of ours (Task 3's loop_spec check runs on a stub pack)
    it("Arms (wowsims.com)'s replay presses nothing", function()
        local C = content("warrior_arms", ARMS_CHAR, "Arms (wowsims.com)", 60, ARMS)
        local L = loop.new(C)
        local R = replay.new(ws.log("warrior_arms"), L.oracle, ws.replayOptions(C, "warrior_arms", ARMS_REPLAY))
        local run = loop.run(L, 1, { replay = R, trace = false }, { { H = L.us } })
        assert.are.equal(0, run.presses)
        assert.is_true(#run.dec.ours > 40, "decisions scored")
    end)
    -- The pack's own worst idle per bracket (R7; R22a: L10 and L40 keep the 6 s bar unless a measured limit names its
    -- cause; R41, owner 2026-11-05: an idle with nothing useful to cast is correct and gets a measured limit, never a
    -- filler). L60: wowsims's pooling, 9.2 after fixes 7, 13 and 16, 5.0 measured with R41 (the shared max(6, LIVE60)
    -- lifted L10 and L40 to 9.2 before). L10 7.4 and L40 12.8 since R41 removed the leveling Hamstring (5.6 / 5.6 with
    -- it; 9.0 / 11.2 before it): nothing useful to cast before Mortal Strike's talent: L10 Rend, Thunder Clap and five
    -- Sunders up, the rage going to the off-GCD Heroic Strike; L40 the same with Slam and Spearing Strike cooling.
    local ARMS_LIVE = { [10] = 7.4, [40] = 12.8, [60] = 6 } -- 7.4 / 12.8 / 5.0
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Arms (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Arms (wowsims.com)",
                content("warrior_arms", ww, "Arms (wowsims.com)", level, ARMS),
                ARMS_LIVE[level]
            )
        end)
    end
    it("Fury (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Fury (wowsims.com)",
            content("warrior_fury", ww.Fury, "Fury (wowsims.com)", 60, FURY),
            "warrior_fury",
            -- measured 0.917: 0.933 after central fixes 7, 13 and 16 (was 0.81 with GAP AD), less the pre-pull Berserker
            -- Rage the user's ruling (2026-10-21) gates on Improved Berserker Rage, which the build lacks (1 of 60);
            -- 0.897 (61 of 68) after the harness corrected to the measured swing timing (2026-10-22): the log's swings
            -- take health at the swing, so the execute phase opens a landing lag earlier than the rows show it; 0.926 (68)
            -- with the world's parry haste (decision 63)
            0.92,
            FURY_REPLAY
        )
    end)
    -- The pack's own worst idle per bracket (R7, R22a, R41 as Arms's). L60 6.8: wowsims's pooling, after fix 16 (8.2
    -- with GAP AD's Intercept). Below Bloodthirst nothing useful to cast: L10 7.6 (Battle Stance: Rend up, five Sunders
    -- up, the rage pooling for the off-GCD Heroic Strike; the world's off hand by rank moved it from 7.4); L40 8.4 since
    -- R41 removed the leveling Hamstring (2.4 with it): Berserker Stance (no Rend or Overpower), Whirlwind cooling, five
    -- Sunders up, the rage going to Heroic Strike
    local FURY_LIVE = { [10] = 7.6, [40] = 8.4, [60] = 6.8 } -- 7.6 / 8.4 / 6.8
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Fury (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Fury (wowsims.com)",
                content("warrior_fury", ww.Fury, "Fury (wowsims.com)", level, FURY),
                FURY_LIVE[level]
            )
        end)
    end
    -- Central fix 18 (in game, level 30 beta: no Mortal Strike or Bloodthirst before 40): the leveling filler Sunder
    -- fired at 5 stacks. Below 40, with ours driving on the secret client (target auras raise in combat), the first
    -- icon is never Sunder while the target's true 5 stacks have more than 15 s left (past any wait the queue shows)
    -- and the fifth is older than one tick (the cast's frame, before its success folds in).
    for _, case in ipairs({
        { "warrior_arms", ww, "Arms (wowsims.com)", ARMS },
        { "warrior_fury", ww.Fury, "Fury (wowsims.com)", FURY },
    }) do
        it(case[3] .. " stops Sunder Armor at 5 stacks at level 30", function()
            local L = loop.new(content(case[1], case[2], case[3], 30, case[4]))
            local H = L.us
            local id = H.Hekili.Class.auras.sunder_armor.id
            local at5, five, raised = {}, 0, 0
            loop.run(L, 1, {
                duration = 120,
                on = function(run, steps, t)
                    if H.ctl.auraError.target then
                        raised = raised
                            + (pcall(H.api.C_UnitAuras.GetAuraDataByIndex, "target", 1, "HARMFUL") and 0 or 1)
                    end
                    -- a killed target's stacks are no client's: the kill clears `target` (2026-10-22 kill capture)
                    local a = not run.W.killAt and run.us.target and run.us.target.auras[id]
                    local left = a and a.stacks == 5 and a.expires - t or 0
                    if left > 15 and left < 30 - loop.TICK then
                        five = five + 1
                        if steps[1].q.name[1] == "sunder_armor" then
                            at5[#at5 + 1] = ("%.1f"):format(t)
                        end
                    end
                end,
            }, { { H = H } })
            assert.is_true(raised > 0 and five > 0, raised .. " raised reads, " .. five .. " ticks at 5")
            assert.are.same({}, at5)
        end)
    end
    it("Protection (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Protection (wowsims.com)",
            content("warrior_protection", ww.Protection, "Protection (wowsims.com)", 60, PROT),
            "warrior_protection",
            -- measured 0.904 (94); 0.979 once the replay ends a cooldown at its log timestamp (ready-time ruling), held with
            -- partial blocks replayed as BLOCK_REDUCED wounds (gap AH); 0.97 -> 0.93 (0.938, 91 of 97, after gap AS's
            -- Rend give-back): W2's fight exposes exact-1.5 s Shield Slam ties (sim artifact; reverting upstream #755
            -- alone gives 0.989)
            0.93,
            PROT_REPLAY
        )
    end)
    -- the pack's own worst idle by level over seeds 1-20, 120 s (gap CK, 2026-10-31; was 5.4 at 60 and 40 from one
    -- seed): L60 median 11.8 worst 17.2, L40 11.8 / 19.0; L10 7.8 / 10.4 in those 120 s fights while this check's own
    -- fight reads 5.6, so 10 keeps the 6 s floor. The world pays rage for our white swings only (wowsims's Protection log earns 55% of its rage
    -- from damage taken, 20% from white swings) and raises no block for Shield Block (no `us.taking`), so the character
    -- pools at 7-10 rage through runs of avoided swings while the APL waits on Shield Slam (Rend and Sunder gated on its
    -- cooldown). 5.4 was measured while Revenge's window never reached the client (review C1), which held the APL in
    -- the Shield Block fishing branch. A world fix (gap CK) tightens these again.
    local PROT_LIVE = { [10] = 6, [40] = 19.0, [60] = 17.2 }
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Protection (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Protection (wowsims.com)",
                content("warrior_protection", ww.Protection, "Protection (wowsims.com)", level, { kit = PROT_KIT }),
                PROT_LIVE[level]
            )
        end)
    end
end)
