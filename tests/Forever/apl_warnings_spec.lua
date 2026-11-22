-- tests/Forever/apl_warnings_spec.lua: ns.AplSecretToken (Task 9b; Engine/Sim/AplWarnings.lua, the core's own
-- load-time scan since border batch 3), the scan behind Hekili:LoadScript's "Forever: ... is secret" warnings. No
-- health is warned (FABLE-FOR-OWNER 7): target health reads the hidden-value band (lane B2) and the player's own reads it
-- in combat (lane B3); time to die answers "unknown" (Targets.lua's FOREVER): unwarned.
local alloc = require("Game.State.helpers.alloc")

describe("APL secret-token scan", function()
    local scan

    before_each(function()
        local ns = {}
        assert(loadfile("src/Hekili/Engine/Sim/AplWarnings.lua"))("Hekili", ns)
        scan = ns.AplSecretToken
    end)

    it("leaves target health unwarned: the band reads it (lane B2, FABLE-FOR-OWNER 7)", function()
        for _, hp in ipairs({
            "target.health.pct<20",
            "!buff.spender_c.up&target.health.pct<=20",
            "target.health.percent<20",
            "target.health.current<5",
            "target.health.actual<5",
            "target.health_pct<20",
            "target.health_percent>80",
            "target.health_current<5",
            "min:target.health.pct",
        }) do
            assert.is_nil(scan(hp), hp)
        end
    end)

    it("leaves the player's own health unwarned: the band reads it in combat (lane B3, FABLE-FOR-OWNER 7)", function()
        for _, hp in ipairs({
            "(health.pct<35)",
            "health.current<5000",
            "health.deficit>5000",
            "health.percent>50",
            "health.actual<9",
            "health<5000",
            "buff.spender_c.up&!(health>10)",
        }) do
            assert.is_nil(scan("buff.spender_c.up&" .. hp), hp)
        end
        assert.is_nil(scan("health.pct<50&target.health.pct<20"))
    end)

    it("leaves a target_if expression unwarned", function()
        assert.is_nil(scan("min:health.pct"))
        assert.is_nil(scan("max:target.health.pct"))
    end)

    it("ignores everything else", function()
        assert.is_nil(scan("buff.spender_c.up&rage>=30"))
        assert.is_nil(scan("health.max>0"))
        assert.is_nil(scan("target.health.max>0"))
        assert.is_nil(scan("pet.health.pct<50"))
        for _, ttd in ipairs({ "target.time_to_die>12", "fight_remains<20", "time_to_pct_20>10", "longest_ttd<10" }) do
            assert.is_nil(scan(ttd), ttd) -- time to die answers "unknown", unwarned
        end
        assert.is_nil(scan("pet.health.current<50"))
        assert.is_nil(scan("group_health<50"))
        assert.is_nil(scan("variable.time_to_die_soon"))
        assert.is_nil(scan("time_to_dies>1"))
        assert.is_nil(scan("rage.time_to_42"))
        assert.is_nil(scan("debuff.spender_c.remains"))
        assert.is_nil(scan(""))
        assert.is_nil(scan(nil))
        assert.is_nil(scan(42))
    end)

    it("allocates nothing", function()
        local a, b = "buff.spender_c.up&health.pct<20", "buff.spender_c.up&rage>=30&pet.health.pct<50"
        assert.are.equal(
            0,
            alloc.bytes(function()
                scan(a)
                scan(b)
            end, 10000)
        )
    end)
end)
