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
-- Whirlwind's off-hand hit (1680 Tag 2) is logged as its own Casting line: a hit of the one cast, not a decision.
-- wowsims logs the Heroic Strike queue (25286 Tag 1) as an aura the client never shows (the client sees
-- IsCurrentSpell): hidden.
local FURY_REPLAY = { hidden = { [1282733] = true, [25286] = true }, procs = { ["1680:2"] = true }, speed = 2.1 }

-- Protection: wowsims's Revenge window is an aura it logs under Revenge's own ID (25288; the DB2's Defensive State 5302,
-- 5 s, from a block, dodge or parry of the target's swing). The replay does not replay the target's swings, so the
-- window stays in the truth (`hidden`) and answers Revenge's usability; the live world's mob swings at us, so there
-- Revenge keeps the world's own requirement. The Heroic Strike queue (25286 Tag 1) as Fury's. Shield Slam is the talent's
-- rank 1 plus its trained ranks (the log casts rank 4, 23925).
local PROT_KIT = { "berserker_rage", "revenge", "shield_block", "shield_slam", "shield_wall", "shield_bash", "taunt" }
local PROT = {
    kit = PROT_KIT,
    requires = {
        revenge = function(_, e)
            return e.auras[25288] ~= nil and e.form == 2, "no window"
        end,
    },
}
local PROT_REPLAY = { hidden = { [25288] = true, [25286] = true }, procs = {}, speed = 2.35 }

describe("the Warrior wowsims.com packs #slow #wowsims", function()
    it("Arms (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Arms (wowsims.com)",
            content("warrior_arms", ARMS_CHAR, "Arms (wowsims.com)", 60, ARMS),
            "warrior_arms",
            -- measured 0.896: 0.910 after central fixes 7, 13 and 16 (was 0.86, provisional), less the pre-pull Berserker
            -- Rage wowsims casts at -4.5 without Improved Berserker Rage (the build has none), which the user's ruling
            -- (2026-10-21) gates on that talent (berserker_rage -> battle_shout, 1 of 67)
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
    -- the pack's own worst idle at 60 (wowsims's pooling), after fixes 7, 13 and 16; L10 and L40 5.6 with the recipe's
    -- leveling Hamstring (11.2 and 9.0 without it, on-GCD presses only)
    local LIVE60 = 9.2
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Arms (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Arms (wowsims.com)",
                content("warrior_arms", ww, "Arms (wowsims.com)", level, ARMS),
                math.max(6, LIVE60)
            )
        end)
    end
    it("Fury (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Fury (wowsims.com)",
            content("warrior_fury", ww.Fury, "Fury (wowsims.com)", 60, FURY),
            "warrior_fury",
            -- measured 0.917: 0.933 after central fixes 7, 13 and 16 (was 0.81 with GAP AD), less the pre-pull Berserker
            -- Rage the user's ruling (2026-10-21) gates on Improved Berserker Rage, which the build lacks (1 of 60)
            0.91,
            FURY_REPLAY
        )
    end)
    -- the pack's own worst idle at 60 (wowsims's pooling), after fix 16 (8.2 with GAP AD's Intercept)
    local FURY_LIVE60 = 6.8
    -- below Bloodthirst: 7.6 s (L10, in Battle Stance: pooling for Heroic Strike), the recipe's idle before its leveling
    -- Sunder since that Sunder stops at 5 stacks (fix 18) and the gate counts on-GCD presses only (final review fix 3);
    -- L40 2.4 with the leveling Hamstring in Berserker Stance (8.6 without it); the owner's call
    local FURY_LIVE_LEVELING = 7.6
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Fury (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Fury (wowsims.com)",
                content("warrior_fury", ww.Fury, "Fury (wowsims.com)", level, FURY),
                math.max(6, level < 60 and FURY_LIVE_LEVELING or FURY_LIVE60)
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
    -- The leveling filler Hamstring (the user's rule: a recipe filler, never a higher limit): shown at level 40, before
    -- the main strike's talent, and never at 60, where wowsims's lists have no Hamstring.
    for _, case in ipairs({
        { "warrior_arms", ww, "Arms (wowsims.com)", ARMS },
        { "warrior_fury", ww.Fury, "Fury (wowsims.com)", FURY },
    }) do
        it(case[3] .. " fills with Hamstring at level 40 and never at 60", function()
            local shown = {}
            for _, level in ipairs({ 40, 60 }) do
                local L = loop.new(content(case[1], case[2], case[3], level, case[4]))
                shown[level] = 0
                loop.run(L, 1, {
                    duration = 120,
                    on = function(_, steps)
                        if steps[1].q.name[1] == "hamstring" then
                            shown[level] = shown[level] + 1
                        end
                    end,
                }, { { H = L.us } })
            end
            assert.is_true(shown[40] > 0, "no Hamstring at 40")
            assert.are.equal(0, shown[60])
        end)
    end
    it("Protection (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Protection (wowsims.com)",
            content("warrior_protection", ww.Protection, "Protection (wowsims.com)", 60, PROT),
            "warrior_protection",
            0.97, -- measured 0.904 (94); 0.979 once the replay ends a cooldown at its log timestamp (ready-time ruling)
            PROT_REPLAY
        )
    end)
    local PROT_LIVE60 = 5.4 -- the pack's own worst idle at 60, under the 6 s floor
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Protection (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Protection (wowsims.com)",
                content("warrior_protection", ww.Protection, "Protection (wowsims.com)", level, { kit = PROT_KIT }),
                math.max(6, PROT_LIVE60)
            )
        end)
    end
end)
