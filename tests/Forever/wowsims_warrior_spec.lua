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

describe("the Warrior wowsims.com packs #slow #wowsims", function()
    it("Arms (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Arms (wowsims.com)",
            content("warrior_arms", ARMS_CHAR, "Arms (wowsims.com)", 60, ARMS),
            "warrior_arms",
            0.86, -- measured 0.866; provisional until central fix 7 (ruling L10; was 0.83 before fix 6)
            ARMS_REPLAY
        )
    end)
    -- the replay's world is the log's: loop.run presses nothing of ours (Task 3's loop_spec check runs on a stub pack)
    it("Arms (wowsims.com)'s replay presses nothing", function()
        local C = content("warrior_arms", ARMS_CHAR, "Arms (wowsims.com)", 60, ARMS)
        local L = loop.new(C)
        local ro = setmetatable({ forms = C.character().forms }, { __index = ARMS_REPLAY })
        local R = replay.new(ws.log("warrior_arms"), L.oracle, ro)
        local run = loop.run(L, 1, { replay = R, trace = false }, { { H = L.us } })
        assert.are.equal(0, run.presses)
        assert.is_true(#run.dec.ours > 40, "decisions scored")
    end)
    local LIVE60 = 9.2 -- the pack's own worst idle at 60 (wowsims's pooling), measured on the rebased tree
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Arms (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Arms (wowsims.com)",
                content("warrior_arms", ww, "Arms (wowsims.com)", level, ARMS),
                math.max(6, LIVE60)
            )
        end)
    end
end)
