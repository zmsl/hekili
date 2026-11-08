-- tests/Forever/helpers/protection_gate.lua: the Protection (wowsims.com) content of the headless Warrior gates (gap
-- CI), shared by loop_warrior_protection_spec.lua (the 20-fight gate) and loop_warrior_spec.lua (the world checks).
-- It is wowsims_warrior_spec.lua's live Protection content: the one-hander-and-shield world (ww.Protection), the log's
-- talents and race, the Protection kit; Revenge keeps the live world's own window (the mob swings at us).
local ws = require("Forever.helpers.wowsims")
local ww = require("Forever.helpers.warrior_world")

local M = {}

M.KIT =
    { "berserker_rage", "retaliation", "revenge", "shield_block", "shield_slam", "shield_wall", "shield_bash", "taunt" }

--- The Protection (wowsims.com) content at `level` [60].
function M.content(level)
    return ws.content(ww.Protection, {
        pack = "Protection (wowsims.com)",
        level = level or 60,
        talents = ws.header("warrior_protection").talents,
        learn = ws.learn("WARRIOR"),
        race = ws.race("warrior_protection"),
        kit = M.KIT,
    })
end

return M
