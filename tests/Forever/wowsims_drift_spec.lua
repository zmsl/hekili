-- tests/Forever/wowsims_drift_spec.lua: tools/wowsims/drift.lua's pure helpers (the record diff and the ladder parse).
local drift = assert(loadfile("tools/wowsims/drift.lua"))()

describe("wowsims drift", function()
    it("lists every changed leaf, a key one side lacks as nil", function()
        assert.are.same(
            { "Cooldowns.CategoryCooldownMs: 18000 -> 15000", "Powers.1.Cost: 145 -> 245", "Subtexts: Rank 4 -> nil" },
            drift.changes({
                Cooldowns = { CategoryCooldownMs = 18000, GCDMs = 1500 },
                Powers = { { Cost = 145 } },
                Subtexts = "Rank 4",
            }, { Cooldowns = { CategoryCooldownMs = 15000, GCDMs = 1500 }, Powers = { { Cost = 245 } } })
        )
        assert.are.same({}, drift.changes({ a = { 1, 2 } }, { a = { 1, 2 } }))
    end)

    it("reads a generated file's ladders and its not-generated notes", function()
        local l = drift.ladders(table.concat({
            "// Not generated:",
            "//   Holy Shield: rank 4, spell 1239570, has no SpellMisc row",
            "var spellData = generatedSpellData{",
            "\tHolyShield:                    spelldata.Ranked(20925, 20927, 20928),",
            "\tHolyPower:                     spelldata.Talent(5923, 5),",
            "}",
        }, "\n"))
        assert.are.equal("Ranked(20925, 20927, 20928)", l.HolyShield)
        assert.are.equal("Talent(5923, 5)", l.HolyPower)
        assert.is_true(l["# Holy Shield: rank 4, spell 1239570, has no SpellMisc row"])
    end)
end)
