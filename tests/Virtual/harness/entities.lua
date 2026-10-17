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
--- damage its armour takes away, 0-1), avoid ({ miss, dodge, parry, block } on swings at it), health, powerMax, pt (the
--- power type of `power`, the swing-paid resource [1]), res ({ [powerType] = { cur, max } }: the other resources),
--- formSpeed ({ [form] = the main hand's period in that form }).
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
        pt = o.pt or 1,
        res = o.res or {},
        formSpeed = o.formSpeed or {},
        formSince = 0, -- when the current form began (W.shift; a regen ramp's clock)
        auras = {},
        target = o.target,
        form = 0,
        dmgMult = 1,
        gcdUntil = 0, -- the true GCD's end (W.press)
        cdUntil = {}, -- [key] = the true cooldown's end
        avoidAt = {}, -- [act] = the last time an outcome of ours on a target was that avoid (MISS, DODGE, PARRY)
    }
    e.res0 = {} -- each other resource's value at the start (the observer's first view; the world changes `res`)
    for pt, r in pairs(e.res) do
        e.res0[pt] = r.cur
    end
    return e
end

return M
