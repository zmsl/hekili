-- tests/Forever/wowsims_hunter_spec.lua (wowsims packs plan, Task 11): the Hunter wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.hunter_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("HUNTER"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- The abilities the Melee Weave casts or recommends that the worlds' characters lack (usable on cost); Strider Kick
-- comes with the MM and SV builds' talent (the log header's), never the BM build's.
local EXTRA = {
    kit = {
        "aspect_of_the_hawk",
        "immolation_trap",
        "mongoose_bite",
        "multi_shot",
        "raptor_strike",
        "serpent_sting",
        "arcane_shot",
        "wing_clip",
    },
}
-- The replay's: Mongoose Bite's window in wowsims's fights is Expose Prey (1310726, 10 s, the MM and SV builds' talent
-- proc); the client answers the bite usable while it is up (the kit reads that plain usability, not the aura).
local REPLAY_EXTRA = {
    kit = EXTRA.kit,
    requires = {
        mongoose_bite = function(_, e)
            return e.auras[1310726] ~= nil, "no window"
        end,
    },
}
-- Expose Prey in the truth only: the kit opens Mongoose Bite from its usability read, never from the player aura walk
local REPLAY = { hidden = { [1310726] = true } }

-- recipe, world content, pack, the replay floor (the first clean run's, never lowered), LIVE60: the pack's own worst
-- idle at 60, rounded up to 0.1 s (it waits for mana it believes at its in-combat lower bound: mana is secret; the BM
-- and MM worlds stand at 11 yd, the weave's range)
local PACKS = {
    { "hunter_beast_mastery", "BeastMastery", "Beast Mastery (wowsims.com)", 0.74, 4.6 },
    { "hunter_marksmanship", "Marksmanship", "Marksmanship (wowsims.com)", 0.73, 4.6 },
    { "hunter_survival", "Survival", "Survival (wowsims.com)", 0.65, 6.6 },
}

describe("the Hunter wowsims.com packs #slow #wowsims", function()
    -- one block per pack: the replay floor (measured on the first clean run, never lowered), the pack's own worst
    -- idle at 60 (LIVE60, measured), and the brackets
    for _, p in ipairs(PACKS) do
        local spec, world, pack, FLOOR, LIVE60 = p[1], W[p[2]], p[3], p[4], p[5]
        it(pack .. " follows wowsims's casts", function()
            ws.gate(pack, content(spec, world, pack, 60, REPLAY_EXTRA), spec, FLOOR, REPLAY)
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, world, pack, level, EXTRA), math.max(6, LIVE60))
            end)
        end
    end
end)
