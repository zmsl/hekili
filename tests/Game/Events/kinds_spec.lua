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

    describe("FLIGHT", function()
        local a

        before_each(function()
            a = I.ab.bySpell[fs.SPENDER_P]
            I.ab.rMax[a] = 30 -- a 30 yd spell: H = 30 / 20 + 0.15 = 1.65
        end)

        it("with no record: only the hard window [0, rMax / speed + TOL], at pass 3", function()
            local i = open(fs.SPENDER_P, 100)
            assert.is_nil(K.Band(i, 1, 101.5, false, "WOUND", 8))
            assert.is_nil(K.Band(i, 2, 101.5, false, "WOUND", 8))
            local lo, hi, e = K.Band(i, 3, 101.5, false, "WOUND", 8)
            assert.is_true(lo == 100 and math.abs(hi - 101.65) < 1e-9)
            assert.is_true(math.abs(e - 100.825) < 1e-9)
        end)

        it("raises the lower bound from the target's plain range bracket, less a running mob's closing", function()
            VS.TargetRange = function()
                return { lo = 20, hi = 30, last = { observed = { t = 100 } } }
            end
            local i = open(fs.SPENDER_P, 100)
            local lo = K.Band(i, 3, 101, false, "WOUND", 8)
            -- (20 - 7 x 1) / 20 - 0.15 = 0.5 s after the success
            assert.is_true(math.abs(lo - 100.5) < 1e-9)
        end)

        it("ignores a range bracket logged after the success", function()
            VS.TargetRange = function()
                return { lo = 20, hi = 30, last = { observed = { t = 100.2 } } }
            end
            local i = open(fs.SPENDER_P, 100)
            assert.are.equal(100, (K.Band(i, 3, 101, false, "WOUND", 8)))
        end)

        it("with a record: the narrow band at pass 1, the widened one at pass 2, none at pass 3", function()
            T.Learn("Creature-1", 20, 1.5, 99)
            local i = open(fs.SPENDER_P, 100)
            local lo, hi, e = K.Band(i, 1, 101.5, false, "WOUND", 8)
            assert.is_true(math.abs(lo - 101.35) < 1e-9 and math.abs(hi - 101.65) < 1e-9 and e == 101.5)
            lo, hi = K.Band(i, 2, 101.5, false, "WOUND", 8) -- d = 2.5 s: down 0.35 x 2.5, up 0.175 x 2.5
            assert.is_true(math.abs(lo - (101.5 - 0.875)) < 1e-9 and math.abs(hi - 101.65) < 1e-9)
            assert.is_nil(K.Band(i, 3, 101.5, false, "WOUND", 8))
        end)

        it("leaves capture a's late MISS foreign once the GUID has a learned lag (spec §3.4's example)", function()
            T.Learn("Creature-1", 20, 1.5, 96.4)
            local i = open(fs.SPENDER_P, 97.374)
            for p = 1, 3 do
                local lo, hi = K.Band(i, p, 97.891, true, "MISS", 1)
                assert.is_false(lo ~= nil and 97.891 >= lo and 97.891 <= hi, "pass " .. p)
            end
        end)

        it("refuses a WOUND outside [0.6 lo, 1.6 hi] once three clean wounds taught the band", function()
            for _, v in ipairs({ 14, 16, 15 }) do
                local i = open(fs.SPENDER_P, 100)
                T.Pay(i, 101.5, false, v, "", true, 3)
            end
            local i = open(fs.SPENDER_P, 110)
            assert.is_true(K.Accepts(i, "WOUND", "", 15, 8, false))
            assert.is_true(K.Accepts(i, "WOUND", "CRITICAL", 30, 8, false))
            assert.are.same({ false, true }, { K.Accepts(i, "WOUND", "", 40, 8, false) }) -- a band refused it
            assert.are.equal(0, T.bandRejected) -- counted per row by T.Pick, not per Accepts
            for p = 1, 3 do
                assert.are.equal(0, (T.Pick(111.5, "Creature-1", p, "WOUND", "", 40, 8, false)))
            end
            assert.is_false(T.Divergent(i, 111.5, 1, "WOUND", "", 40, 8, false))
            assert.are.equal(1, T.bandRejected)
            assert.are.same({ true, true }, { K.Accepts(i, "WOUND", "", 15, 8, false) }) -- banded: ranked first
        end)

        it("ranks a candidate whose learned band accepts the row before an older unbanded one", function()
            for _, v in ipairs({ 30, 32, 31 }) do -- teach the fire instant's band
                T.Pay(open(fs.SPENDER_F, 100), 100.01, false, v, "", true, 1)
            end
            local older = open(fs.SPENDER_C, 110.30) -- a default instant: school ANY, no band, the least closure
            local banded = open(fs.SPENDER_F, 110.32)
            assert.are.equal(banded, (T.Pick(110.33, "Creature-1", 1, "WOUND", "", 31, 4, false)))
            assert.are_not.equal(older, banded)
        end)
    end)

    it("TICKS: tick k at the anchor + k x period +- 0.1 s, every pass alike", function()
        local i = open(fs.SPENDER_M, 10) -- the direct ticket; its TICKS ticket is link[i]
        local j = T.link[i]
        for p = 1, 3 do
            local lo, hi, e = K.Band(j, p, 13, false, "WOUND", 64)
            assert.is_true(math.abs(lo - 12.9) < 1e-9 and math.abs(hi - 13.1) < 1e-9 and e == 13)
        end
        assert.is_nil(K.Band(j, 2, 10.1, true, "MISS", 1)) -- a composed schedule takes no avoid
    end)
end)
