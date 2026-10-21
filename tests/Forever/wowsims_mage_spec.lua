-- tests/Forever/wowsims_mage_spec.lua (wowsims packs plan, Task 12): the Mage wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.mage_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("MAGE"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- The replay's: Fireball's and Pyroblast's DoT parts are their own GCD-0 Casting lines {SpellID: 10151 / 18809,
-- Tag: 1}: procs, neither decisions nor casts.
-- Frostfire Bolt's DoT part likewise {1237313, Tag: 1}.
local REPLAY = {
    fire = { procs = { ["10151:1"] = true, ["18809:1"] = true } },
    frostfire = { procs = { ["1237313:1"] = true, ["18809:1"] = true } },
}

-- recipe, world content, pack, the replay floor (the first clean run's, never lowered), LIVE60: the pack's own worst
-- idle at 60, rounded up to 0.1 s (P8).
-- Floors: Arcane 0.780 (46 of 59), Fire 0.794 (50 of 63), truncated; the classification in each recipe's header.
-- Fire raised 0.79 -> 0.84 on 0ce5d1a4 (0.841, 53 of 63): the replay's cooldown end is the log's timestamp, so Fire
-- Blast's three decisions at its cooldown's end agree (the CD_PROBE disagreement in mage_fire.lua's header).
-- LIVE60: Arcane never idles at 60; Fire spends its mana out by 85 s of the 120 s fight and then waits on Fire Blast's
-- 340 (Scorch's line holds while the five stacks last), as wowsims's own fight runs dry (its Evocation then on its
-- 8-minute cooldown, which the gate counts as a usable free ability).
-- The loops' flicker (pack_gate FLICKER; 20 fights: Arcane 1.43/min, oracle 1.41; Fire 1.21/min, oracle 0.40). Fire's
-- excess is measured, not fixed: in 3 fights (seeds 1-3), 7 of its 10 first-icon A-B-A flickers are fire_blast >
-- fireball > fire_blast at Fire Blast's cooldown end (the not-ready flag pushes the believed ready time to now +
-- CD_PROBE each settle while the model's own end is nearer: central, mage_fire.lua's header) and 3 combustion > scorch;
-- the 20-fight line's waits [scorch:unknown 148] are the Scorch line's `debuff.fire_vulnerability.remains<5` edge on
-- the modelled (unreadable) target debuff, a candidate not yet measured as flicker.
-- Frostfire (Task FFB): 0.891 (49 of 55), floor 0.89 (mage_frostfire.lua's header); LIVE60 10.8: as Fire's, its mana
-- spent out by about 80 s, it waits on Frostfire Bolt's 314.5 and Fire Blast's 340 (Evocation on its cooldown).
local PACKS = {
    { "mage_arcane", "Arcane", "Arcane (wowsims.com)", 0.77, 0 },
    { "mage_fire", "Fire", "Fire (wowsims.com)", 0.84, 12.6 },
    { "mage_frostfire", "Frostfire", "Frostfire (wowsims.com)", 0.89, 10.8 },
}

describe("the Mage wowsims.com packs #slow #wowsims", function()
    -- one block per pack: the replay floor (measured on the first clean run, never lowered), the pack's own worst
    -- idle at 60 (LIVE60, measured), and the brackets
    for _, p in ipairs(PACKS) do
        local spec, world, pack, FLOOR, LIVE60 = p[1], W[p[2]], p[3], p[4], p[5]
        it(pack .. " follows wowsims's casts", function()
            ws.gate(pack, content(spec, world, pack, 60), spec, FLOOR, REPLAY[p[2]:lower()])
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, world, pack, level), math.max(6, LIVE60))
            end)
        end
    end
end)
