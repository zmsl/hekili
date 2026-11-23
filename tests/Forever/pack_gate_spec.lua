-- tests/Forever/pack_gate_spec.lua: a record-only arm's own floors (pack_gate.ARM_FLOORS, L1795).
local ab = require("Game.harness.ab")
local pack_gate = require("Forever.helpers.pack_gate")

describe("pack_gate's arm floors", function()
    it("replace the named fields in that arm alone; every other field and arm keeps M.FLICKER's", function()
        local arm, check = ab.arm, ab.check
        finally(function()
            ab.arm, ab.check = arm, check
        end)
        local missed
        ab.check = function(ok, _, line)
            if not ok then
                missed[#missed + 1] = line:match("^[^:]+")
            end
        end
        local fl = pack_gate.FLICKER["Arms"]
        local r = { flicker = 0.40, retracted = 0, readyShort = 0, heldReady = fl.heldReady + 1, loOver = 0 }
        for name, want in pairs({
            default = { "flicker floor", "held-while-ready floor" },
            bands = { "held-while-ready floor" },
            ["bands-drop"] = { "flicker floor", "held-while-ready floor" },
        }) do
            ab.arm = function()
                return name
            end
            missed = {}
            pack_gate.flicker("Arms", r, "line", true)
            assert.are.same(want, missed, name)
        end
    end)
end)
