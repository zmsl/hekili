-- tests/Forever/wowsims_shaman_spec.lua (wowsims packs plan, Task 10): the Shaman wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local sw = require("Forever.helpers.shaman_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("SHAMAN"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- Flametongue Totem's weapon proc is logged under the totem's ID with Tag 1 (not a choice); every totem cast fills its
-- slot (1 fire, 2 earth, 3 water, 4 air) for its top rank's DB2 duration.
local ENH_REPLAY = {
    procs = { ["16387:1"] = true },
    totems = {
        searing_totem = { 1, 55 },
        flametongue_totem = { 1, 300 },
        strength_of_earth_totem = { 2, 300 },
        mana_spring_totem = { 3, 300 },
        grace_of_air_totem = { 4, 300 },
    },
}

describe("the Shaman wowsims.com packs #slow #wowsims", function()
    local PACK = "Enhancement (wowsims.com)"
    -- the replay floor, measured on the first clean run (0.602), never lowered
    it(PACK .. " follows wowsims's casts", function()
        ws.gate(PACK, content("shaman_enhancement", sw.Enhancement, PACK, 60), "shaman_enhancement", 0.60, ENH_REPLAY)
    end)
    -- the pack's own worst idle at 60, seconds rounded up to 0.1: wowsims's spending runs the mana out (its own log sits
    -- near 170 of 5530 mana from 90 s), so the priority waits for mana with only cheaper ranks usable
    local LIVE60 = 8.2
    for _, level in ipairs({ 10, 40, 60 }) do
        it(PACK .. " stays live at level " .. level, function()
            ws.live(PACK, content("shaman_enhancement", sw.Enhancement, PACK, level), math.max(6, LIVE60))
        end)
    end
end)
