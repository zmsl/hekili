-- tests/Virtual/State/apl_warnings_spec.lua: VS.AplSecretToken (Task 9b), the scan behind Hekili:LoadScript's
-- "Forever: ... is secret" warnings for conditions that read health or time to die (spec §6.5, §7.4).
local load = require("Virtual.State.helpers.load")
local alloc = require("Virtual.State.helpers.alloc")

describe("APL secret-token scan", function()
    local scan

    before_each(function()
        scan = load.module().VirtualState.AplSecretToken
    end)

    it("finds target health, player health and time to die", function()
        assert.are.same({
            "target.health.pct",
            "target health is secret",
            "reads 100 until a health-gated ability pins it, always on a spec without one",
        }, { scan("target.health.pct<20") })
        assert.are.equal("target.health.pct", scan("!buff.spender_c.up&target.health.pct<=20"))
        assert.are.equal("target.health_percent", scan("target.health_percent>80"))
        assert.are.equal("target.time_to_die", scan("target.time_to_die>12"))
        assert.are.equal("target.time_to_pct_", scan("target.time_to_pct_35<5"))
        assert.are.same({
            "health.current",
            "player health is secret",
            "reads the health maximum while player health is unreadable",
        }, { scan("health.current<5000") })
        assert.are.equal("health.pct", scan("(health.pct<35)"))
        assert.are.equal("time_to_die", scan("time_to_die<5"))
        assert.are.equal("interpolated_fight_remains", scan("interpolated_fight_remains>20"))
        assert.are.equal("fight_remains", scan("cooldown.recklessness.remains>fight_remains"))
        assert.are.equal("time_to_pct_", scan("time_to_pct_20>10"))
        assert.are.equal("health.deficit", scan("health.deficit>5000"))
        assert.are.equal("longest_ttd", scan("longest_ttd<10"))
        assert.are.equal("target.time_to_die", scan("target.time_to_die<5"))
        assert.are.equal("fight_remains", scan("fight_remains>10"))
        assert.are.equal("target.time_to_pct_", scan("target.time_to_pct_20"))
    end)

    it("finds a token in a target_if expression", function()
        assert.are.equal("target.time_to_die", scan("min:target.time_to_die"))
    end)

    it("ignores everything else", function()
        assert.is_nil(scan("buff.spender_c.up&rage>=30"))
        assert.is_nil(scan("health.max>0"))
        assert.is_nil(scan("target.health.max>0"))
        assert.is_nil(scan("pet.health.pct<50"))
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
