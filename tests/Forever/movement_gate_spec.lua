-- tests/Forever/movement_gate_spec.lua (re-pin plan Task 7; design §2.2, rule 19): a move-reached line's range gate,
-- `(toggle.movement&<move condition>|<range gate>)`, through the real engine in the warrior world. Movement ON shows it
-- out of range (the client's tint does the rest); OFF hides it until the bracket says in range; an unknown bracket (a
-- fresh target before any plain range answer, or a secret answer: rule 11, R8) never blocks it either way.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local SECRET = require("Game.State.helpers.fake_api").SECRET

local LINE = "actions+=/mortal_strike,if=(toggle.movement&target.outside5|target.within5)"

-- A world `yd` yards from its target (Mortal Strike's range is the fake client's melee 0-5), the gated line first and
-- a free filler after it, rage enough for the strike. Returns the pick at the next cycle, as a function.
local function world(yd)
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    H.ctl.level.target, H.ctl.distance.target = 60, yd
    H.Fire("PLAYER_TARGET_CHANGED")
    local t = H.ctl.now + 0.2
    assert(headless.cycle(H, t))
    local lines = H.Hekili:ParseActionList(LINE)
    lines[1].enabled = true
    lines[2] = { enabled = true, action = "berserker_stance" }
    H.Hekili.DB.profile.packs[ww.PACK].lists = { precombat = {}, default = lines }
    H.Hekili:LoadScripts()
    H.Fire("PLAYER_REGEN_DISABLED")
    local VS = H.ns.VirtualState
    local power, rage = VS.Power, { est = 60, lo = 60, hi = 60, conf = 1 }
    VS.Power = function(pt, now)
        return pt == 1 and rage or power(pt, now)
    end
    local out = H.Hekili.Engine.Output.Primary
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
    return H,
        function()
            t = t + 0.2
            assert(headless.cycle(H, t))
            assert.are.same({}, H.errors)
            return out.recs[1] and out.recs[1].actionName
        end
end

local function both(H, pick)
    local on = pick()
    H.Hekili:FireToggle("movement", "off")
    local off = pick()
    H.Hekili:FireToggle("movement", "on")
    return on, off
end

describe("a move-reached line's gate (rule 19)", function()
    it("at 20 yd shows only with Movement ON", function()
        local on, off = both(world(20))
        assert.are.equal("mortal_strike", on)
        assert.are.equal("berserker_stance", off)
    end)

    it("at 3 yd shows either way", function()
        local on, off = both(world(3))
        assert.are.equal("mortal_strike", on)
        assert.are.equal("mortal_strike", off)
    end)

    it("with a secret range answer (no plain bracket) shows either way (Review Focus 1)", function()
        local on, off = both(world(SECRET))
        assert.are.equal("mortal_strike", on)
        assert.are.equal("mortal_strike", off)
    end)

    it("on a fresh target before its first plain range answer shows either way (Review Focus 1, R8)", function()
        local H, pick = world(20)
        H.Hekili:FireToggle("movement", "off")
        assert.are.equal("berserker_stance", pick()) -- the 20 yd bracket is known
        H.ctl.distance.target = SECRET -- the new target's range reads stay secret: no plain answer yet
        H.ctl.guid.target = "Creature-0-0-0-0-2-0"
        H.Fire("PLAYER_TARGET_CHANGED")
        assert.are.equal("mortal_strike", pick())
        H.Hekili:FireToggle("movement", "on")
        assert.are.equal("mortal_strike", pick())
    end)
end)
