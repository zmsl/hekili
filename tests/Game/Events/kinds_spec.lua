-- tests/Game/Events/kinds_spec.lua (unit-registry spec §3.3, §3.4): each kind's acceptance and bands, written once.
-- Task 6: FRAME and STRIKE; Tasks 7 and 8 add FLIGHT, TICKS and CHANNEL.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("the kinds", function()
    local api, ctl, ns, VS, I, T, K, X, L, saved

    local function open(id, t)
        return T.OpenCast(t, I.ab.bySpell[id], id, "Creature-1")
    end

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        T, K, X, L = I.Tickets, I.Kinds, I.Expect, I.Log
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        VS.Start(api)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("FRAME: the frame at pass 1; an avoid's landing window, or CAST_WINDOW once others avoid", function()
        local i = open(fs.SPENDER_F, 10)
        assert.are.same({ 10, 10 + 0.05, 10 }, { K.Band(i, 1, 10.01, false, "WOUND", 4) })
        local lo, hi = K.Band(i, 2, 10.3, true, "DODGE", 1)
        assert.are.same({ 10, 10 + L.LandWindow(1) }, { lo, hi })
        L.bg[7] = 1 -- others avoid on the target too (GAP AX)
        local lo2, hi2 = K.Band(i, 2, 10.1, true, "DODGE", 1)
        assert.are.same({ 10, 10 + 0.2 }, { lo2, hi2 })
        L.bg[7] = 0
        local lo3, hi3 = K.Band(i, 2, 10.1, true, "BLOCK", 1) -- not a refused avoid: the cast's own window
        assert.are.same({ 10, 10 + 0.2 }, { lo3, hi3 })
    end)

    it("FRAME on a default type: a non-white WOUND only in its frame (today's rule)", function()
        local i = open(fs.SPENDER_C, 10)
        assert.is_nil(K.Band(i, 2, 10.1, false, "WOUND", 8))
        assert.is_truthy(K.Band(i, 2, 10.1, false, "WOUND", 1))
    end)

    it("accepts by school: equal mask, ANY, or none (only an avoid)", function()
        local f, c = open(fs.SPENDER_F, 10), open(fs.SPENDER_C, 10)
        assert.is_true(K.Accepts(f, "WOUND", "", 30, 4, false))
        assert.is_false(K.Accepts(f, "WOUND", "", 30, 8, false))
        assert.is_true(K.Accepts(f, "MISS", "", 0, 1, true))
        assert.is_true(K.Accepts(c, "WOUND", "", 30, 32, false))
        T.school[f] = 0
        assert.is_false(K.Accepts(f, "WOUND", "", 30, 4, false))
        assert.is_true(K.Accepts(f, "PARRY", "", 0, 1, true))
    end)
end)
