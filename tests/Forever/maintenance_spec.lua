-- tests/Forever/maintenance_spec.lua: the maintenance-debuff settings (tools/wowsims/apl.lua rule 15; the user's ruling
-- 2026-10-21): off in game, so the pack never shows the debuff and the lines that wait on it read "up or disabled";
-- on under the harness (loop.new's scenario "sim"), wowsims's raid boss.
local loop = require("Game.harness.loop")
local ws = require("Forever.helpers.wowsims")
local ww = require("Forever.helpers.warrior_world")
local dw = require("Forever.helpers.druid_loop_world")

-- The keys anywhere in our queue over one 90 s fight of content `C` booted in `scenario` ("game" or "sim").
local function shown(C, scenario)
    local L = loop.new(setmetatable({ SCENARIO = scenario }, { __index = C }))
    local keys = {}
    loop.run(L, 1, {
        duration = 90,
        on = function(_, steps)
            for _, name in ipairs(steps[1].q.name) do
                if name then
                    keys[name] = true
                end
            end
        end,
    }, { { H = L.us } })
    return keys
end

local PROT = ws.content(ww.Protection, {
    pack = "Protection (wowsims.com)",
    level = 60,
    talents = ws.header("warrior_protection").talents,
    learn = ws.learn("WARRIOR"),
    race = ws.race("warrior_protection"),
    kit = { "berserker_rage", "revenge", "shield_block", "shield_slam", "shield_wall", "shield_bash", "taunt" },
})

describe("the maintenance-debuff settings #slow", function()
    it("Guardian: in game no Demoralizing Roar and Berserk still comes; the harness casts both", function()
        local game, sim = shown(dw.Guardian, "game"), shown(dw.Guardian, "sim")
        assert.are.same({ false, true }, { game.demoralizing_roar == true, game.berserk == true })
        assert.are.same({ true, true }, { sim.demoralizing_roar == true, sim.berserk == true })
    end)

    it("Protection: in game no Demoralizing Shout, Thunder Clap as wowsims has it; the harness casts both", function()
        local game, sim = shown(PROT, "game"), shown(PROT, "sim")
        assert.are.same({ false, true }, { game.demoralizing_shout == true, game.thunder_clap == true })
        assert.are.same({ true, true }, { sim.demoralizing_shout == true, sim.thunder_clap == true })
    end)

    it("Arms at level 40: in game no Thunder Clap (its leveling filler); the harness casts it", function()
        local arms = ws.content(ww, {
            pack = "Arms (wowsims.com)",
            level = 40,
            talents = ws.header("warrior_arms").talents,
            learn = ws.learn("WARRIOR"),
            race = ws.race("warrior_arms"),
            kit = { "spearing_strike", "berserker_rage" },
        })
        assert.are.same(
            { false, true },
            { shown(arms, "game").thunder_clap == true, shown(arms, "sim").thunder_clap == true }
        )
    end)
end)
