-- tests/Game/State/school_spec.lua (unit-registry spec §5.1): the school enum is one core table, Engine/Schema/Spec.lua's
-- `ns.SCHOOL`, which the build hands the belief in `def.school` (Engine/Schema/Tracked.lua); the headless loader
-- reads the same table off Spec.lua's line (load.school) for the fakes' defs.
local load = require("Game.State.helpers.load")

describe("the school enum", function()
    it("is Spec.lua's table, read for the headless fakes' defs", function()
        assert.are.same(
            { physical = 1, holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64 },
            load.school()
        )
        assert.is_nil(load.module().SCHOOL) -- the belief gets it in def.school, never off ns
    end)

    it("is published on the Hekili object and read by Hekili_Shared's lockouts", function()
        local src = assert(io.open("src/Hekili/Engine/Schema/Spec.lua")):read("*a")
        assert.is_truthy(src:find("Hekili.SCHOOL = ns.SCHOOL", 1, true))
        local shared = assert(io.open("src/Hekili_Shared/Shared/Auras.lua")):read("*a")
        assert.is_truthy(shared:find("local SCHOOLS = Hekili.SCHOOL", 1, true))
    end)
end)
