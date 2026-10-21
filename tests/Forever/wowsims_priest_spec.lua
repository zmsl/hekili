-- tests/Forever/wowsims_priest_spec.lua (wowsims packs plan, Task 14): the Priest wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.priest_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("PRIEST"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

local REPLAY = {}

-- recipe, world content, pack, the replay floor (the first clean run's, never lowered), LIVE60: the pack's own worst
-- idle at 60, rounded up to 0.1 s (P8).
local PACKS = {
    { "priest_shadow", "Shadow", "Shadow (wowsims.com)", 1.00, 1.8 },
    { "priest_smite", "Smite", "Smite (wowsims.com)", 0.93, 0.2 },
}

describe("the Priest wowsims.com packs #slow #wowsims", function()
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
