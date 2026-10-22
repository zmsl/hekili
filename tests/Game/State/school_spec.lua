-- tests/Game/State/school_spec.lua (unit-registry spec §5.1): the school enum is one core table, Engine/Schema/Spec.lua's
-- `ns.SCHOOL`, and the headless loader hands the same table to the Game files.
local load = require("Game.State.helpers.load")

describe("the school enum", function()
    it("is Spec.lua's table, seeded into a headless ns", function()
        local ns = load.module()
        assert.are.same(
            { physical = 1, holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64 },
            ns.SCHOOL
        )
    end)

    it("is published on the Hekili object and read by Hekili_Shared's lockouts", function()
        local src = assert(io.open("src/Hekili/Engine/Schema/Spec.lua")):read("*a")
        assert.is_truthy(src:find("Hekili.SCHOOL = ns.SCHOOL", 1, true))
        local shared = assert(io.open("src/Hekili_Shared/Shared/Auras.lua")):read("*a")
        assert.is_truthy(shared:find("local SCHOOLS = Hekili.SCHOOL", 1, true))
    end)
end)
