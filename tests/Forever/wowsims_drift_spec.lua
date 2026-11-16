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

    it("hands the request's tank slot to the translation context, as the pack build does", function()
        local got
        local stub = {
            isTank = require("tools.wowsims.apl").isTank,
            context = function(_, _, _, _, _, tank)
                got = tank
                return {}
            end,
            translate = function()
                return "", {}
            end,
        }
        local apl = require("tools.wowsims.apl")
        local tankReq = { raid = { tanks = { { type = "Player", index = 0 } } } }
        assert.is_true(apl.isTank(tankReq))
        assert.is_false(apl.isTank({ raid = { tanks = { { type = "Player", index = 1 } } } }))
        assert.is_false(apl.isTank({ raid = {} }))
        drift.translate(stub, {}, {}, "", { rotation = {} }, tankReq)
        assert.is_true(got)
    end)

    it("parses a pin-side .siml with WOWSIMS_PIN_CLI, and a new-rev one with WOWSIMS_NEW_CLI", function()
        local ctx = { new = "n", cli = "newcli", pinCli = "pincli" }
        assert.are.equal("newcli", drift.pinCli(ctx, "n"))
        assert.are.equal("pincli", drift.pinCli(ctx, "p"))
        assert.is_nil(drift.pinCli({ new = "n", cli = "newcli" }, "p"))
    end)
end)
