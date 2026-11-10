-- tests/Game/harness/edgestats_spec.lua (cdm-verdict review M4): edgestats' phantom seconds (staleUp) count only the
-- auras the leaf judges (a player form or enchant never) and report the player's and the target's apart.
local edgestats = require("Game.harness.edgestats")

-- A belief with three auras on two units: 1 a form, 2 a tracked buff, 3 a tracked debuff; all believed up to t = 100.
local function instance()
    local ctl = { now = 0, ViewerAuraBySpell = function() end, ViewerRetarget = function() end }
    local VI = {
        AURA_UNIT = 8,
        auras = {
            n = 2,
            nAura = 3,
            index = { player = 1, target = 2 },
            bySpell = { [11] = 1, [12] = 2, [13] = 3 },
            exp0 = { { 100, 100, 0 }, { 0, 0, 100 } },
        },
        presence = { tracked = { true, true, true } },
        formAura = { [1] = true },
    }
    return { ctl = ctl }, VI
end

describe("edgestats", function()
    it("staleUp skips the player's form and sums the player and the target apart", function()
        local H, VI = instance()
        edgestats.start(H, VI)
        for i = 1, 4 do -- 2 s in combat, the viewer dark for all three
            edgestats.tick(H, VI, i * 0.5, 0.5, true)
        end
        edgestats.tick(H, VI, 3, 0.5, false) -- out of combat: not counted
        local line = edgestats.line(H, VI)
        assert.is_truthy(line:match("staleUp 2%.00/2%.00 "), line) -- the form's 2 s are not in the player's
        assert.is_truthy(line:match("earlyDown 0%.00/0%.00 "), line)
    end)

    it("without the form flag the form counts as any tracked aura (the leaf's rule is the flag)", function()
        local H, VI = instance()
        VI.formAura = nil
        edgestats.start(H, VI)
        edgestats.tick(H, VI, 1, 1, true)
        assert.is_truthy(edgestats.line(H, VI):match("staleUp 2%.00/1%.00 "))
    end)

    it("a lit item with the belief down is earlyDown on its unit", function()
        local H, VI = instance()
        VI.auras.exp0[2][3] = 0
        local em = edgestats.start(H, VI)
        em.on("target", 13, true, 0)
        edgestats.tick(H, VI, 1, 1, true)
        assert.is_truthy(edgestats.line(H, VI):match("staleUp 1%.00/0%.00 earlyDown 0%.00/1%.00 "))
    end)
end)
