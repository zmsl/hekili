-- tests/Forever/helpers/warrior_world.lua (headless loop design §7): the Warrior content of the class-neutral headless
-- loop: the character the instance logs in as. Spell IDs come from the class file itself (load_warrior's recording
-- load: each ability's `id` and `copy` ranks), never copied here.
local loadWarrior = require("Forever.helpers.load_warrior")

local M = {}

M.SPEC, M.CLASS_ID, M.PACK = 1491, 1, "Arms"

-- The Arms kit a level 60 Warrior has trained (every rank: Classic trains them all by 60) and the talent-granted
-- Mortal Strike of the build below.
M.KIT = {
    "battle_shout",
    "battle_stance",
    "berserker_stance",
    "bloodrage",
    "charge",
    "cleave",
    "defensive_stance",
    "demoralizing_shout",
    "execute",
    "hamstring",
    "heroic_strike",
    "intercept",
    "mortal_strike",
    "overpower",
    "pummel",
    "rend",
    "sunder_armor",
    "thunder_clap",
    "victory_rush",
    "whirlwind",
}
-- An Arms build by definition spell (the SPIKE's): Mortal Strike, Anger Management, Deep Wounds 3, Tactical Mastery 5,
-- Impale 2, Improved Rend 3.
M.TALENTS = { [12294] = 1, [12296] = 1, [12834] = 3, [12295] = 5, [16493] = 2, [12163] = 3 }

--- The character for headless.new (§1.3): level 60, the kit known, the Arms talents, rage 0 of 100, a two-hand weapon
--- (speed 3.6), the three stances as forms, Battle Stance up.
function M.character()
    local w = loadWarrior.load()
    local known = {}
    for _, key in ipairs(M.KIT) do
        local a = assert(w.abilities[key], key)
        known[#known + 1] = a.id
        for _, id in ipairs(type(a.copy) == "table" and a.copy or {}) do
            known[#known + 1] = id
        end
    end
    local forms = {}
    for i, key in ipairs({ "battle_stance", "defensive_stance", "berserker_stance" }) do
        forms[i] = w.abilities[key].id
    end
    return {
        class = "WARRIOR",
        classID = M.CLASS_ID,
        specID = M.SPEC,
        level = 60,
        known = known,
        talents = M.TALENTS,
        power = { type = 1, token = "RAGE", max = 100, value = 0 },
        speed = { 3.6 },
        forms = forms,
        form = 1,
    }
end

return M
