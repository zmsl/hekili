-- tests/Forever/minmax_guard_spec.lua (central fix 28, T1): the translator writes wowsims's min / max values as
-- `min(...)` / `max(...)` with each term that may be nil as `(<known>&<term>)` (tools/wowsims/apl.lua rule 6); the
-- engine's min and max (Engine/Sim/Utils.lua safeMin / safeMax) skip the false an unlearned term reads.
local headless = require("Game.harness.headless")
local dlw = require("Forever.helpers.druid_loop_world")

describe("a min / max argument guarded by a known test", function()
    it("is skipped while its ability is unlearned and read once learned", function()
        local C = dlw.Guardian
        local H = headless.new({ character = C.character(), pack = C.PACK })
        local lists = H.Hekili.DB.profile.packs[C.PACK].lists
        local list = next(lists)
        local cases = { -- hurricane and starfire are unlearned for this character, maul learned
            { "action.hurricane.known", false },
            { "action.maul.known", true },
            { "min((action.hurricane.known&10),5)>4", true },
            { "max((action.hurricane.known&10),5)<6", true },
            { "min((action.maul.known&1),5)<2", true },
            { "min((action.hurricane.known&10),(action.starfire.known&3),7)>6", true },
            { "min(1,2,3)=1&max(1,2,3)=3", true },
        }
        for i = #cases, 1, -1 do
            table.insert(lists[list], 1, { action = "maul", criteria = cases[i][1], enabled = true })
        end
        H.Hekili:LoadScripts()
        assert.is_true(headless.cycle(H, H.ctl.now + 1))
        H.Hekili.State.reset()
        for i, case in ipairs(cases) do
            assert.are.equal(case[2], H.Hekili.Scripts:CheckScript(C.PACK .. ":" .. list .. ":" .. i), case[1])
        end
        assert.are.same({}, H.errors)
    end)
end)
