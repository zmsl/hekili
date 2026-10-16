-- tests/Virtual/harness/entities.lua (harness design §3.1, layer 1): the true state of each actor of a fight (our
-- character, party members, enemies, pets). Plain test tables; nothing here is named after a class.
local M = {}

-- Log 2's weapon damage at level 22 (UnitDamage, before armour), each hand { min, max, speed }.
M.LOG2_WEAPONS = { { 36, 50, 2.2 }, { 24, 32, 2.5 } }

--- Weapons for `level`: log 2's ranges scaled by level / 22 (UNMEASURED scaling), the same speeds.
function M.weapons(level, speeds)
    local k, out = (level or 22) / 22, {}
    for h, w in ipairs(M.LOG2_WEAPONS) do
        local s = speeds and speeds[h] or w[3]
        out[h] = { math.floor(w[1] * k + 0.5), math.floor(w[2] * k + 0.5), s }
    end
    return out
end

--- A new actor. `o`: guid, kind ("player", "mob", "pet"), level, weapons ({ { min, max, speed }, ... }), dr (the
--- damage its armour takes away, 0-1), avoid ({ miss, dodge, parry, block } on swings at it), health, powerMax.
function M.new(o)
    local e = {
        guid = o.guid,
        kind = o.kind or "player",
        level = o.level or 22,
        weapons = o.weapons or {},
        dr = o.dr or 0,
        avoid = o.avoid or { miss = 0.05, dodge = 0.05, parry = 0.05, block = 0 },
        health = o.health or 1000,
        healthMax = o.health or 1000,
        power = 0,
        powerMax = o.powerMax or 100,
        auras = {},
        target = o.target,
        form = 0,
        dmgMult = 1,
    }
    return e
end

return M
