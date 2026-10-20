-- tests/Forever/wowsims_hunter_spec.lua (wowsims packs plan, Task 11): the Hunter wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local replay = require("Game.harness.replay")
local W = require("Forever.helpers.hunter_world")

local function content(spec, base, pack, level, extra)
    local o = { pack = pack, level = level, talents = ws.header(spec).talents, learn = ws.learn("HUNTER") }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- The abilities the Melee Weave casts or recommends that the worlds' characters lack (usable on cost).
local EXTRA = {
    kit = {
        "aspect_of_the_hawk",
        "immolation_trap",
        "mongoose_bite",
        "multi_shot",
        "raptor_strike",
        "serpent_sting",
        "arcane_shot",
        "strider_kick",
        "wing_clip",
    },
}

-- recipe, world content, pack, the replay floor (the first clean run's, never lowered), LIVE60: the pack's own worst
-- idle at 60, rounded up to 0.1 s (the mana it waits for, believed at its in-combat lower bound, while the melee lines
-- that would spend it are omitted: no positions)
local PACKS = {
    { "hunter_beast_mastery", "BeastMastery", "Beast Mastery (wowsims.com)", 0.25, 8.8 },
    { "hunter_marksmanship", "Marksmanship", "Marksmanship (wowsims.com)", 0.23, 8.8 },
    { "hunter_survival", "Survival", "Survival (wowsims.com)", 0.17, 8.8 },
}

describe("the Hunter wowsims.com packs #slow #wowsims", function()
    -- the Melee Weave's prepull opens 22 s before the pull (Hunter's Mark, then Aspect of the Hawk at -20)
    local pull0
    setup(function()
        pull0, replay.PULL = replay.PULL, 23
    end)
    teardown(function()
        replay.PULL = pull0
    end)
    -- one block per pack: the replay floor (measured on the first clean run, never lowered), the pack's own worst
    -- idle at 60 (LIVE60, measured), and the brackets
    for _, p in ipairs(PACKS) do
        local spec, world, pack, FLOOR, LIVE60 = p[1], W[p[2]], p[3], p[4], p[5]
        it(pack .. " follows wowsims's casts", function()
            ws.gate(pack, content(spec, world, pack, 60, EXTRA), spec, FLOOR, {})
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, world, pack, level, EXTRA), math.max(6, LIVE60))
            end)
        end
    end
end)
