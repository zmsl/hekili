-- tests/Forever/health_warning_spec.lua (L1808, owner "yes add the health.known warning but dont for the others since
-- we model those"): a custom priority line (one the player wrote or imported) that reads the player's own health without
-- `health.known` is warned once at load, naming the priority and the line. Unknown health reads full, so such a line
-- (`health.pct>X`) would pass on no reading. Power lines are not warned: the model answers them. The detection is the
-- translator's guard check (tools/wowsims/apl.lua rule 23), one function in the core (AplThresholds.lua).
local headless = require("Game.harness.headless")
local dlw = require("Forever.helpers.druid_loop_world")
local apl = require("tools.wowsims.apl")

describe("the custom-line health.known warning", function()
    it("finds a read of the player's own health with no health.known (the translator's check too)", function()
        local H = headless.new({ character = dlw.Guardian.character(), pack = "Guardian (wowsims.com)" })
        for _, unguarded in ipairs({ H.ns.HealthUnguarded, apl.unguarded }) do
            assert.is_true(unguarded("health.pct<40"))
            assert.is_true(unguarded("health.deficit>500&buff.x.up"))
            assert.is_true(unguarded("actions=barkskin,if=health.current<4000"))
            -- def-1 review minor 1: a term that does not guard the whole condition, and the aliases
            assert.is_true(unguarded("!health.known|health.pct<30"))
            assert.is_true(unguarded("health.known&buff.x.up|health.pct>80"))
            assert.is_true(unguarded("health.pct>80|health.known"))
            assert.is_true(unguarded("stat.health_pct<30"))
            assert.is_true(unguarded("at_risk"))
            assert.is_false(unguarded("health.known&health.pct<40"))
            assert.is_false(unguarded("target.health.pct<20"))
            assert.is_false(unguarded("pet.health.pct<20"))
            assert.is_false(unguarded("mana.pct<30"))
            assert.is_false(unguarded("rage.current>=30&energy.deficit<20"))
            assert.is_false(unguarded(nil))
        end
    end)

    describe("at load", function()
        local H, printed

        before_each(function()
            H = headless.new({ character = dlw.Guardian.character(), pack = "Guardian (wowsims.com)" })
            assert.are.same({}, H.loadErrors)
            printed = {}
            H.Hekili.Print = function(_, msg)
                printed[#printed + 1] = msg
            end
        end)

        it("never warns for a shipped priority", function()
            H.Hekili.Scripts:LoadScripts()
            assert.are.same({}, printed)
        end)

        it("warns once for each custom line reading health unguarded, naming the priority and the line", function()
            local spec = H.Hekili.State.spec.id
            H.Hekili.DB.profile.packs["My Bear"] = {
                spec = spec,
                builtIn = false,
                lists = {
                    default = {
                        { enabled = true, action = "barkskin", criteria = "health.pct<40" },
                        { enabled = true, action = "barkskin", criteria = "health.known&health.pct<40" },
                        { enabled = true, action = "maul", criteria = "target.health.pct<20" },
                        { enabled = true, action = "maul", criteria = "mana.pct<30" },
                        { enabled = true, action = "barkskin", criteria = "!health.known|health.pct<30" },
                        { enabled = true, action = "barkskin", criteria = "health.known&buff.x.up|health.pct>80" },
                        { enabled = true, action = "barkskin", criteria = "health.pct>80|health.known" },
                        { enabled = false, action = "barkskin", criteria = "health.pct<20" }, -- switched off: silent
                    },
                },
            }
            H.Hekili.Scripts:LoadScripts()
            table.sort(printed)
            assert.are.equal(4, #printed)
            for i, line in ipairs({ 1, 5, 6, 7 }) do
                assert.is_truthy(printed[i]:find("My Bear", 1, true))
                assert.is_truthy(printed[i]:find("default", 1, true))
                assert.is_truthy(printed[i]:find("line " .. line .. " ", 1, true), printed[i])
                assert.is_truthy(printed[i]:find("health.known", 1, true))
            end
            H.Hekili.Scripts:LoadScripts() -- every options edit loads again: still once
            assert.are.equal(4, #printed)
        end)
    end)
end)
