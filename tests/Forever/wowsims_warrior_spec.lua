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
            0.91, -- measured 0.910 after central fixes 7, 13 and 16 (was 0.86, provisional)
            ARMS_REPLAY
        )
    end)
    -- the replay's world is the log's: loop.run presses nothing of ours (Task 3's loop_spec check runs on a stub pack)
    it("Arms (wowsims.com)'s replay presses nothing", function()
        local C = content("warrior_arms", ARMS_CHAR, "Arms (wowsims.com)", 60, ARMS)
        local L = loop.new(C)
        local ro = setmetatable({
            forms = C.character().forms,
            creatureType = ws.creatureType("warrior_arms"),
            distance = ws.distance("warrior_arms"),
            shared = C.SHARED,
        }, { __index = ARMS_REPLAY }) -- ws.gate's knobs
        local R = replay.new(ws.log("warrior_arms"), L.oracle, ro)
        local run = loop.run(L, 1, { replay = R, trace = false }, { { H = L.us } })
        assert.are.equal(0, run.presses)
        assert.is_true(#run.dec.ours > 40, "decisions scored")
    end)
    local LIVE60 = 9.2 -- the pack's own worst idle at 60 (wowsims's pooling), re-measured after fixes 7, 13 and 16
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
            0.93, -- measured 0.933 after central fixes 7, 13 and 16 (was 0.81 with GAP AD)
            FURY_REPLAY
        )
    end)
    -- the pack's own worst idle at 60 (wowsims's pooling), after fix 16 (8.2 with GAP AD's Intercept)
    local FURY_LIVE60 = 6.8
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Fury (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Fury (wowsims.com)",
                content("warrior_fury", ww.Fury, "Fury (wowsims.com)", level, FURY),
                math.max(6, FURY_LIVE60)
            )
        end)
    end
    it("Protection (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Protection (wowsims.com)",
            content("warrior_protection", ww.Protection, "Protection (wowsims.com)", 60, PROT),
            "warrior_protection",
            0.90, -- measured 0.904 (94)
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
