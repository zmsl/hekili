-- tests/Forever/state_unknown_key_spec.lua (audit item 14): an unknown bare identifier in the emulated environment is
-- logged once per script and key, not on every read (each log builds a debugstack string).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the state's unknown-key log", function()
    it("logs an unknown key once per script", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local S = H.Hekili.State
        S.scriptID = "audit:list:1"
        local before = #H.errors
        for _ = 1, 5 do
            local _ = S.audit_no_such_key
        end
        assert.are.equal(1, #H.errors - before)
    end)
end)
