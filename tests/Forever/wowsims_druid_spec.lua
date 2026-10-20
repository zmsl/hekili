-- tests/Forever/wowsims_druid_spec.lua (wowsims packs plan, Task 7): the Druid wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.druid_loop_world")
local loop = require("Game.harness.loop")
local replay = require("Game.harness.replay")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("DRUID"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

describe("the Druid wowsims.com packs #slow #wowsims", function()
    it("Feral's replay world reports the energy rate the client reads", function()
        local C = content("druid_feral", W.Feral, "Feral (wowsims.com)", 60)
        local R = replay.new(ws.log("druid_feral"), loop.new(C).oracle, {})
        assert.is_true(R.world(setmetatable({ pt = 3 }, { __index = C.WORLD }), 1).rates[3] > 0)
    end)

    it("Feral (wowsims.com) follows wowsims's casts", function()
        ws.gate("Feral (wowsims.com)", content("druid_feral", W.Feral, "Feral (wowsims.com)", 60), "druid_feral", 0.92)
    end)
    local FERAL60 = 3.2 -- the pack's own worst idle at 60 (wowsims's energy pooling), seconds
    for _, level in ipairs({ 20, 40, 60 }) do
        it("Feral (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Feral (wowsims.com)",
                content("druid_feral", W.Feral, "Feral (wowsims.com)", level),
                math.max(6, FERAL60)
            )
        end)
    end
end)
