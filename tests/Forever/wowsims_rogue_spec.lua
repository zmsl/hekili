-- tests/Forever/wowsims_rogue_spec.lua (wowsims packs plan, Task 8): the Rogue wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.rogue_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("ROGUE"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- { pack, recipe, world content, replay floor (decisions on-GCD, measured 2026-10-20, never lowered; Combat 0.958 and
-- Subtlety 0.963 on central fix 13: the strictSequence opener, the cooldown restart), LIVE60 (the
-- pack's own worst idle at 60: wowsims's energy pooling, seconds rounded up to 0.1) }
-- Mutilate's per-hand hits are GCD-0 Casting lines {SpellID: 1241584, Tag: 1/2}: procs, neither decisions nor casts.
local MUTILATE_HANDS = { procs = { ["1241584:1"] = true, ["1241584:2"] = true } }
local PACKS = {
    { "Assassination (wowsims.com)", "rogue_assassination", W.Assassination, 0.98, 5.0, MUTILATE_HANDS },
    { "Combat (wowsims.com)", "rogue_combat", W.Combat, 0.95, 4.8 },
    { "Subtlety (wowsims.com)", "rogue_subtlety", W.Subtlety, 0.96, 3.8 },
}

describe("the Rogue wowsims.com packs #slow #wowsims", function()
    for _, p in ipairs(PACKS) do
        local pack, spec, base, FLOOR, LIVE60, knobs = p[1], p[2], p[3], p[4], p[5], p[6]
        it(pack .. " follows wowsims's casts", function()
            ws.gate(pack, content(spec, base, pack, 60), spec, FLOOR, knobs)
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, base, pack, level), math.max(6, LIVE60))
            end)
        end
    end
end)
