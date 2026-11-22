-- tests/Forever/apl_warnings_spec.lua: ns.AplSecretToken (Task 9b; Engine/Sim/AplWarnings.lua, the core's own
-- load-time scan since border batch 3), the scan behind Hekili:LoadScript's "Forever: ... is secret" warnings for
-- conditions that read target health (spec §6.5, §7.4); the player's own health (hidden in combat, owner L1462) is read
-- from the hidden-value band in combat since lane B3, unwarned (FABLE-FOR-OWNER 7); time to die answers "unknown"
-- (Targets.lua's FOREVER): unwarned.
local alloc = require("Game.State.helpers.alloc")

describe("APL secret-token scan", function()
    local scan

    before_each(function()
        local ns = {}
        assert(loadfile("src/Hekili/Engine/Sim/AplWarnings.lua"))("Hekili", ns)
        scan = ns.AplSecretToken
    end)

    it("finds target health", function()
        assert.are.same({
            "target.health.pct",
            "target health is secret",
            "reads 100 until a health-gated ability pins it, always on a spec without one",
        }, { scan("target.health.pct<20") })
        assert.are.equal("target.health.pct", scan("!buff.spender_c.up&target.health.pct<=20"))
        assert.are.equal("target.health_percent", scan("target.health_percent>80"))
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
        assert.are.equal("target.health.pct", scan("health.pct<50&target.health.pct<20")) -- the target's still is
    end)

    it("finds a token in a target_if expression", function()
        assert.are.equal("target.health.pct", scan("min:target.health.pct"))
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
        assert.is_nil(scan("group_health<50")) -- not the player's own row
        assert.is_nil(scan("variable.time_to_die_soon"))
        assert.is_nil(scan("time_to_dies>1"))
        assert.is_nil(scan("rage.time_to_42"))
        assert.is_nil(scan("debuff.spender_c.remains"))
        assert.is_nil(scan(""))
        assert.is_nil(scan(nil))
        assert.is_nil(scan(42))
    end)

    it("allocates nothing on a hit or a miss", function()
        local hit, miss = "buff.spender_c.up&target.health.pct<20", "buff.spender_c.up&rage>=30&pet.health.pct<50"
        assert.are.equal(
            0,
            alloc.bytes(function()
                scan(hit)
                scan(miss)
            end, 10000)
        )
    end)
end)
