-- tests/Game/State/apl_warnings_spec.lua: VS.AplSecretToken (Task 9b), the scan behind Hekili:LoadScript's
-- "Forever: ... is secret" warnings for conditions that read health (spec §6.5, §7.4); time to die answers "unknown"
-- (Targets.lua's FOREVER) and is not warned.
local load = require("Game.State.helpers.load")
local alloc = require("Game.State.helpers.alloc")

describe("APL secret-token scan", function()
    local scan

    before_each(function()
        scan = load.module().VirtualState.AplSecretToken
    end)

    it("finds target health and player health", function()
        assert.are.same({
            "target.health.pct",
            "target health is secret",
            "reads 100 until a health-gated ability pins it, always on a spec without one",
        }, { scan("target.health.pct<20") })
        assert.are.equal("target.health.pct", scan("!buff.spender_c.up&target.health.pct<=20"))
        assert.are.equal("target.health_percent", scan("target.health_percent>80"))
        assert.are.same({
            "health.current",
            "player health is secret",
            "reads the health maximum while player health is unreadable",
        }, { scan("health.current<5000") })
        assert.are.equal("health.pct", scan("(health.pct<35)"))
        assert.are.equal("health.deficit", scan("health.deficit>5000"))
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
