-- tests/Forever/wowsims_druid_spec.lua (wowsims packs plan, Task 7): the Druid wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.druid_loop_world")
local loop = require("Game.harness.loop")
local replay = require("Game.harness.replay")

-- Berserk (417141) is a talent's spell with no trainer level: known through its talent's points only, not the
-- worlds' kit list (which a missing level would teach at 1).
local LEARN = setmetatable({ [417141] = math.huge }, { __index = ws.learn("DRUID") })

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = LEARN,
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

    -- the replay floor: 0.932 measured on central fix 13 (82/88: the observer's cooldown restart), never lowered
    it("Feral (wowsims.com) follows wowsims's casts", function()
        ws.gate("Feral (wowsims.com)", content("druid_feral", W.Feral, "Feral (wowsims.com)", 60), "druid_feral", 0.93)
    end)
    local FERAL60 = 4.2 -- the pack's own worst idle at 60 (wowsims's energy pooling), seconds
    for _, level in ipairs({ 20, 40, 60 }) do
        it("Feral (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Feral (wowsims.com)",
                content("druid_feral", W.Feral, "Feral (wowsims.com)", level),
                math.max(6, FERAL60)
            )
        end)
    end

    it("Balance (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Balance (wowsims.com)",
            content("druid_balance", W.Balance, "Balance (wowsims.com)", 60),
            "druid_balance",
            0.83 -- 0.836 (46/55) on central fix 13 over fix 12; 0.818 on central fix 12 (GAP R), from 0.56
        )
    end)
    -- The pack's own worst idle at 60, seconds: out of mana from shared gap R (the combat mana forecast reads the
    -- casting rate; the recipe's header), not wowsims's pooling. Re-measure and re-tighten it (and the L10/L40 limit)
    -- when R lands.
    local BALANCE60 = 8.6
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Balance (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Balance (wowsims.com)",
                content("druid_balance", W.Balance, "Balance (wowsims.com)", level),
                math.max(6, BALANCE60)
            )
        end)
    end
end)
