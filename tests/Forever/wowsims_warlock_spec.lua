-- tests/Forever/wowsims_warlock_spec.lua (wowsims packs plan, Task 13): the Warlock wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.warlock_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("WARLOCK"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- recipe, world content, pack, the replay floor (the first clean run's, on 5d62f44c + Task 13; never lowered), LIVE60:
-- the pack's own worst idle at 60, rounded up to 0.1 s (P8). The classification of each pack's disagreements is in its
-- recipe's header. Measured: Affliction 0.728 (81), SM Ruin 0.606 (94), Demonology 0.767 (116), Shadow Brand 0.735
-- (98), Destruction 0.743 (109), truncated. Most of the gap is API-forced (`fight_remains` 3600 s: wowsims's
-- last-minute Bane of Agony) and two shared gaps (reported): wowsims's dynamite miss credited to our pending Corruption
-- (Affliction 0.901 without it) and the replay's pet mana (Demonology's `pet.mana<115` Life Tap).
-- LIVE60 0.2 in every pack: each list ends in an unconditional Life Tap, so no bracket idles (worst 0.2 s at 10, 40
-- and 60); no recipe needs a leveling line.
local PACKS = {
    { "warlock_affliction", "Affliction", "Affliction (wowsims.com)", 0.72, 0.2 },
    { "warlock_sm_ruin", "SMRuin", "SM Ruin (wowsims.com)", 0.60, 0.2 },
    { "warlock_demonology", "Demonology", "Demonology (wowsims.com)", 0.76, 0.2 },
    { "warlock_shadow_brand", "ShadowBrand", "Shadow Brand (wowsims.com)", 0.73, 0.2 },
    { "warlock_destruction", "Destruction", "Destruction (wowsims.com)", 0.74, 0.2 },
}

describe("the Warlock wowsims.com packs #slow #wowsims", function()
    -- one block per pack: the replay floor, the pack's own worst idle at 60 (LIVE60, measured), and the brackets
    for _, p in ipairs(PACKS) do
        local spec, world, pack, FLOOR, LIVE60 = p[1], W[p[2]], p[3], p[4], p[5]
        it(pack .. " follows wowsims's casts", function()
            ws.gate(pack, content(spec, world, pack, 60), spec, FLOOR)
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, world, pack, level), math.max(6, LIVE60))
            end)
        end
    end
end)
