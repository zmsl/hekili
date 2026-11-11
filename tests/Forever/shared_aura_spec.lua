-- tests/Forever/shared_aura_spec.lua (central fix 15, GAP AJ): an aura's `shared` names the unit whose auras it reads
-- whoever cast them. A target debuff marked `shared = "target"` (Thunder Clap) another player put on our target reads up.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("a shared aura", function()
    it("reads a shared target debuff from the target, cast by another player (GAP AJ)", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local aura = H.Hekili.Class.auras.thunder_clap
        assert.are.equal("target", aura.shared)
        local t = H.ctl.now + 0.2
        H.ctl.auras.target.HARMFUL[1] = {
            name = "Thunder Clap",
            spellId = aura.id,
            expirationTime = t + 20,
            duration = 26,
            applications = 0,
            sourceUnit = "party1",
        }
        H.Fire("UNIT_AURA", "target")
        assert(headless.cycle(H, t))
        local st = H.Hekili.State
        st.reset("Primary", true)
        assert.is_true(st.debuff.thunder_clap.up)
    end)

    it("registers Thunderfury's slow (27648, 12 s) and the Protection priority reads it (S1)", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        local aura = H.Hekili.Class.auras.thunderfury
        assert.are.same({ 27648, 12 }, { aura.id, aura.duration })
        local f = assert(io.open("src/Hekili_Warrior/APLs/Protection (wowsims.com).simc"))
        local simc = f:read("*a")
        f:close()
        assert.is_truthy(simc:find("!debuff.thunderfury.up&", 1, true))
        assert.is_nil(simc:find("default #27: dropped the unresolved aura 27648", 1, true))
    end)
end)
