-- tests/Forever/cycle_spec.lua (option D, owner 2026-11-11): Recommend Target Swaps on the engine's target-cycle
-- machinery. `active_dot` is the belief's count (Facade.DebuffCount, stubbed here; tests/Game/State/token_slots_spec.lua
-- proves the count itself), unknown is saturated (never 0: a 0 suggests a swap for ever), the current target's own
-- debuff floors it at 1, `max_cycle_targets` caps the targets, and time to die (never known on Forever) excludes nobody.
-- The bed: the headless Arms instance with a two-line list, Rend (cycle_targets=1, cast where it is down) over a filler.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("target swaps (cycle_targets, option D)", function()
    local H, st, rec, t, count, enemies, rendId

    -- The list: `rendLine`'s modifiers (cycle_targets=1 unless overridden) over a Battle Shout filler.
    local function boot(mods)
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        st = H.Hekili.State
        rendId = H.Hekili.Class.auras.rend.id
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.ctl.power[1] = 100
        H.Fire("PLAYER_TARGET_CHANGED")
        t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        local rend = { enabled = true, action = "rend", criteria = "!debuff.rend.up", cycle_targets = 1 }
        for k, v in pairs(mods or {}) do
            rend[k] = v or nil
        end
        H.Hekili.DB.profile.packs[ww.PACK].lists = {
            default = { rend, { enabled = true, action = "battle_shout" } },
        }
        H.Hekili:LoadScripts()
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        count, enemies = 1, 3
        H.ns.Facade.DebuffCount = function(id)
            if id == rendId then
                return count
            end
            return 0
        end
        H.ns.getNumberTargets = function()
            return enemies, enemies
        end
        H.Hekili.Engine.settings.specs[ww.SPEC].cycle = true
    end

    local function rendUp(remains)
        H.ctl.auras.target.HARMFUL[1] = {
            name = "Rend",
            spellId = rendId,
            expirationTime = H.ctl.now + remains,
            duration = 21,
            applications = 1,
            sourceUnit = "player",
        }
        H.Fire("UNIT_AURA", "target")
    end

    local function update()
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.same({}, H.errors)
        rec = H.Hekili.Engine.Output.Primary.recs
        return rec[1].actionName, rec[1].indicator
    end

    after_each(function()
        H.Hekili.Engine.settings.specs[ww.SPEC].cycle = false
        H.Hekili.Engine.settings.specs[ww.SPEC].cycle_min = 6
    end)

    it("suggests Rend on another target while fewer enemies carry it than are in combat", function()
        boot()
        rendUp(10)
        assert.are.same({ "rend", "cycle" }, { update() })
    end)

    it("suggests no swap once every enemy carries it", function()
        boot()
        rendUp(10)
        count = 3
        assert.are.same({ "battle_shout" }, { update() })
    end)

    it("with the toggle off, the line reads the current target only, as without cycle_targets", function()
        boot()
        rendUp(10)
        H.Hekili.Engine.settings.specs[ww.SPEC].cycle = false
        local on = { update() }
        boot({ cycle_targets = false })
        rendUp(10)
        H.Hekili.Engine.settings.specs[ww.SPEC].cycle = false
        assert.are.same({ "battle_shout" }, on)
        assert.are.same(on, { update() })
    end)

    it("suggests no swap with one enemy", function()
        boot()
        rendUp(10)
        enemies = 1
        assert.are.same({ "battle_shout" }, { update() })
    end)

    it("caps the targets at max_cycle_targets", function()
        boot({ max_cycle_targets = 2 })
        rendUp(10)
        count = 2
        assert.are.same({ "battle_shout" }, { update() })
        count = 1
        assert.are.same({ "rend", "cycle" }, { update() })
    end)

    it("reads an unknown count as every enemy carrying it: no swap, never 0", function()
        boot()
        rendUp(10)
        count = nil -- the belief holds no slot for the target (Map with no plate, plates off)
        assert.are.same({ "battle_shout" }, { update() })
        st.reset("Primary", true)
        assert.are.equal(st.true_active_enemies, st.active_dot.rend)
        assert.are.equal(3, st.active_dot.rend)
    end)

    it("floors the count at 1 while the current target carries it", function()
        boot()
        rendUp(10)
        count, enemies = 0, 2
        assert.are.same({ "rend", "cycle" }, { update() })
        st.reset("Primary", true)
        st.SetupCycle(H.Hekili.Class.abilities.rend, true)
        assert.is_true((st.IsCycling(nil, true)))
        assert.are.equal(1, st.active_dot.rend)
    end)

    it("excludes nobody by time to die, which Forever never knows", function()
        boot()
        rendUp(10)
        H.Hekili.Engine.settings.specs[ww.SPEC].cycle_min = 15
        st.reset("Primary", true)
        assert.are.equal(3, st.cycle_enemies)
    end)

    it("counts the swapped cast in the forecast: the next icon is no second swap", function()
        boot()
        rendUp(10)
        count = 2 -- one enemy left
        assert.are.same({ "rend", "cycle" }, { update() })
        assert.is_true(H.Hekili.Engine.Output.Primary.count >= 2)
        assert.are_not.same({ "rend", "cycle" }, { rec[2].actionName, rec[2].indicator })
    end)
end)
