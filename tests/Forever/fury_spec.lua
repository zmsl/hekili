-- tests/Forever/fury_spec.lua: the Fury priority (src/Hekili_Warrior/APLs/Fury.simc) on the headless engine. Each line's
-- `if=` runs through the real Scripts.lua against the real state of a booted Fury Warrior (helpers/warrior_world.lua's
-- character plus Bloodthirst), with the state's rage, swing, cooldowns and target count pinned per case.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local BLOODTHIRST = 23881

local H, st

-- A Fury Warrior in `stance`, in melee with a level 60 target.
local function boot(stance)
    local c = ww.character()
    c.known[#c.known + 1] = BLOODTHIRST
    local talents = {}
    for k, v in pairs(ww.TALENTS) do
        talents[k] = v
    end
    talents[BLOODTHIRST] = 1
    c.talents, c.form = talents, ww.FORM[stance]
    H = headless.new({ character = c, pack = "Fury" })
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(headless.cycle(H, H.ctl.now + 0.2))
    st = H.Hekili.State
    st.reset("Primary", true) -- the now-state: the cycle's prediction may have simulated a stance return
    assert.is_true(st.buff[stance].up, stance)
end

local function set(name, value)
    H.Hekili.DB.profile.specs[H.Hekili.State.spec.id].settings[name] = value -- the Fury spec
end

-- The `n`th (default first) `action` line's condition in Fury's `list` (default list by default) as the engine
-- evaluates it now.
local function check(action, n, list)
    n, list = n or 1, list or "default"
    for i, e in ipairs(H.Hekili.DB.profile.packs.Fury.lists[list]) do
        if e.action == action then
            n = n - 1
            if n == 0 then
                local ok, err = H.Hekili.Scripts:CheckScript("Fury:" .. list .. ":" .. i)
                assert.is_nil(err, action)
                return ok and true or false
            end
        end
    end
    error("no " .. action .. " line")
end

-- The pinned state: rage now, the next main-hand swing, Bloodthirst's and Whirlwind's cooldowns, the enemy count.
local function pin(rage, swing, bt, wwcd, enemies)
    rawset(st.rage, "current", rage)
    rawset(st, "mainhand_remains", swing)
    rawset(st, "active_enemies", enemies or 1)
    st.cooldown.bloodthirst.expires = st.query_time + bt
    st.cooldown.whirlwind.expires = st.query_time + wwcd
end

describe("the Fury priority", function()
    it("is the user's list with every wowsims Fury cast, Heroic Strike and Cleave in two focus tiers", function()
        local fury = assert(loadfile("tools/make_pack.lua"))("lists")[2]
        assert.are.equal("Fury", fury.name)
        local function lines(list)
            local out = {}
            for i, e in ipairs(fury.lists[list]) do
                out[i] = e.action .. (e.focus and " " .. e.focus or "")
            end
            return out
        end
        assert.are.same({
            "victory_rush 1",
            "overpower 1",
            "revenge 1",
            "heroic_strike 1",
            "heroic_strike 2",
            "cleave 1",
            "cleave 2",
            "rend",
            "sunder_armor",
            "call_action_list",
            "thunder_clap",
            "demoralizing_shout",
            "bloodthirst",
            "whirlwind",
            "execute",
            "hamstring",
            "berserker_stance",
            "bloodrage",
            "berserker_rage",
            "battle_shout",
        }, lines("default"))
        assert.are.same({ "battle_shout", "charge", "intercept" }, lines("precombat"))
        assert.are.same({ "use_items", "death_wish", "sweeping_strikes" }, lines("cooldowns")) -- no focus
        local names = {}
        for name in pairs(fury.lists) do
            names[#names + 1] = name
        end
        table.sort(names)
        assert.are.same({ "cooldowns", "default", "precombat" }, names)
        local d = fury.lists.default
        assert.are.equal("cooldowns", d[10].list_name)
        assert.are.equal("boss||target.level>=level+3", d[10].criteria) -- Arms.simc's cooldowns gate; a stored | is ||
        for i = 4, 7 do
            assert.are.equal(1, d[i].use_off_gcd)
        end
        assert.are.equal("active_enemies=1&rage>=settings.rage_cap_threshold", d[4].criteria)
        assert.are.equal("active_enemies>1&rage>=settings.rage_cap_threshold", d[6].criteria)
    end)

    it("defaults the thresholds to 40 (80 near the cap) and the upkeep toggles to Sunder on, the rest off", function()
        local w = require("Forever.helpers.load_warrior").load()
        assert.are.same({ 80, 40, 40, true, false, false }, {
            w.settings.rage_cap_threshold.default,
            w.settings.hs_threshold.default,
            w.settings.cleave_threshold.default,
            w.settings.debuff_sunder_enabled.default,
            w.settings.maintain_thunder_clap.default,
            w.settings.debuff_demoshout_enabled.default,
        })
    end)

    describe("Heroic Strike and Cleave below the cap never clip Bloodthirst or Whirlwind (Review Focus 1)", function()
        before_each(function()
            boot("berserker_stance")
        end)

        it("refuses Heroic Strike when Bloodthirst comes up before the swing and the rest is short of it", function()
            local hs, bt = st.action.heroic_strike.cost, st.action.bloodthirst.cost
            pin(hs + bt - 1, 1.5, 1, 9)
            assert.is_true(st.rage.current >= 40)
            assert.is_false(check("heroic_strike", 2))
            pin(hs + bt, 1.5, 1, 9) -- enough left for Bloodthirst
            assert.is_true(check("heroic_strike", 2))
            pin(hs + bt - 1, 1.5, 2, 9) -- Bloodthirst comes up after the swing
            assert.is_true(check("heroic_strike", 2))
            pin(hs + bt - 1, 0, 0, 9) -- a swing due now (or no swing speed read): Bloodthirst ready still reserved
            assert.is_false(check("heroic_strike", 2))
        end)

        it("refuses Cleave when Whirlwind comes up before the swing and the rest is short of it", function()
            local cl, wwc = st.action.cleave.cost, st.action.whirlwind.cost
            pin(cl + wwc - 1, 1.5, 9, 0.5, 2)
            assert.is_true(st.rage.current >= 40)
            assert.is_false(check("cleave", 2))
            pin(cl + wwc, 1.5, 9, 0.5, 2)
            assert.is_true(check("cleave", 2))
            pin(cl + wwc - 1, 1.5, 9, 3, 2) -- Whirlwind comes up after the swing
            assert.is_true(check("cleave", 2))
            pin(cl + wwc - 1, 0, 9, 0, 2) -- a swing due now: Whirlwind ready still reserved
            assert.is_false(check("cleave", 2))
        end)

        it("needs the threshold's rage and the target count: Heroic Strike on one, Cleave on more", function()
            pin(39, 1.5, 9, 9)
            assert.is_false(check("heroic_strike", 2))
            pin(40, 1.5, 9, 9)
            assert.is_true(check("heroic_strike", 2))
            assert.is_false(check("cleave", 2))
            set("hs_threshold", 60)
            assert.is_false(check("heroic_strike", 2))
            pin(40, 1.5, 9, 9, 3)
            assert.is_false(check("heroic_strike", 2))
            assert.is_true(check("cleave", 2))
            set("cleave_threshold", 41)
            assert.is_false(check("cleave", 2))
        end)

        it("dumps at the cap whatever the no-clip rule says, on the tier 1 lines only", function()
            pin(80, 0, 0, 0)
            assert.is_true(check("heroic_strike", 1))
            assert.is_false(check("cleave", 1))
            pin(79, 0, 0, 0)
            assert.is_false(check("heroic_strike", 1))
            pin(80, 0, 0, 0, 2)
            assert.is_true(check("cleave", 1))
            assert.is_false(check("heroic_strike", 1))
            set("rage_cap_threshold", 90)
            assert.is_false(check("cleave", 1))
            -- a cap low enough that the reserve refuses there: the tier 1 line still fires, tier 2 does not
            local hs, bt = st.action.heroic_strike.cost, st.action.bloodthirst.cost
            set("rage_cap_threshold", 40)
            pin(hs + bt - 1, 0, 0, 9)
            assert.is_true(st.rage.current >= 40)
            assert.is_true(check("heroic_strike", 1))
            assert.is_false(check("heroic_strike", 2))
            local cl, wwc = st.action.cleave.cost, st.action.whirlwind.cost
            pin(cl + wwc - 1, 0, 9, 0, 2)
            assert.is_true(check("cleave", 1))
            assert.is_false(check("cleave", 2))
        end)
    end)

    it("drops each upkeep line when its toggle is off (Review Focus 2)", function()
        boot("battle_stance")
        rawset(st.rage, "current", 100)
        for line, toggle in pairs({
            sunder_armor = "debuff_sunder_enabled",
            thunder_clap = "maintain_thunder_clap",
            demoralizing_shout = "debuff_demoshout_enabled",
        }) do
            set(toggle, true)
            assert.is_true(check(line), line .. " on")
            set(toggle, false)
            assert.is_false(check(line), line .. " off")
        end
    end)

    it("gates Overpower, Revenge, Rend and Thunder Clap on the stances that allow them (Review Focus 4)", function()
        local want = {
            battle_stance = { overpower = true, revenge = false, rend = true, thunder_clap = true },
            defensive_stance = { overpower = false, revenge = true, rend = true, thunder_clap = true },
            berserker_stance = { overpower = false, revenge = false, rend = false, thunder_clap = false },
        }
        for stance, lines in pairs(want) do
            boot(stance)
            set("maintain_thunder_clap", true)
            set("debuff_demoshout_enabled", true)
            for line, ok in pairs(lines) do
                assert.are.equal(ok, check(line), stance .. " " .. line)
            end
            assert.is_true(check("demoralizing_shout"), stance .. " demoralizing_shout") -- castable in every stance
        end
    end)

    it("recommends Execute only in the execute phase (below 20%), after Bloodthirst and Whirlwind", function()
        boot("berserker_stance")
        rawset(st.rage, "current", 100)
        rawset(st, "execute_phase", false)
        assert.is_false(check("execute"))
        rawset(st, "execute_phase", true)
        assert.is_true(check("execute"))
    end)

    it("keeps the cooldowns behind the cooldowns toggle and Arms's boss gate (inert when off)", function()
        boot("berserker_stance")
        assert.is_false(check("call_action_list")) -- a level 60 non-boss: no cooldowns
        H.ctl.level.target = 63
        H.Fire("PLAYER_TARGET_CHANGED")
        assert(headless.cycle(H, H.ctl.now + 0.2))
        st = H.Hekili.State
        assert.is_true(check("call_action_list"))
        local toggles = H.Hekili.Engine.settings.toggles
        local was = toggles.cooldowns.value
        for _, key in ipairs({ "death_wish", "bloodrage" }) do
            assert.are.equal("cooldowns", H.Hekili.Class.abilities[key].toggle, key)
            toggles.cooldowns.value = false
            H.Hekili:ResetSpellCaches()
            st.reset("Primary", true)
            assert.is_true((st:IsDisabled(key)), key .. " off")
            toggles.cooldowns.value = true
            H.Hekili:ResetSpellCaches()
            st.reset("Primary", true)
            assert.is_false((st:IsDisabled(key)), key .. " on")
        end
        toggles.cooldowns.value = was
    end)

    it("refreshes Battle Shout at 10 s or less and holds the GCD fillers for Bloodthirst and Whirlwind", function()
        boot("berserker_stance")
        rawset(st.rage, "current", 50)
        st.applyBuff("battle_shout", 11)
        pin(50, 1.5, 9, 9)
        assert.is_false(check("battle_shout"))
        st.applyBuff("battle_shout", 10)
        assert.is_true(check("battle_shout"))
        assert.is_true(check("battle_shout", 1, "precombat"))
        pin(50, 1.5, 1, 9) -- Bloodthirst within a GCD: wowsims's Delay Check holds the shout
        assert.is_false(check("battle_shout"))
        pin(50, 1.5, 9, 1)
        assert.is_false(check("battle_shout"))
        pin(89, 1.5, 9, 9)
        assert.is_true(check("bloodrage"))
        pin(90, 1.5, 9, 9)
        assert.is_false(check("bloodrage"))
        assert.is_false(check("berserker_rage")) -- only with Improved Berserker Rage, as a rage generator
        assert.is_false(check("hamstring")) -- only under a Windfury Totem
        st.applyBuff("windfury", 10)
        assert.is_true(check("hamstring"))
        rawset(st, "execute_phase", true)
        assert.is_false(check("hamstring"))
    end)

    it("returns to Berserker Stance when Bloodthirst or Whirlwind is ready", function()
        boot("battle_stance")
        pin(50, 1.5, 9, 9)
        assert.is_false(check("berserker_stance"))
        pin(50, 1.5, 0, 9)
        assert.is_true(check("berserker_stance"))
        pin(50, 1.5, 9, 0.05) -- Whirlwind within the reaction time
        assert.is_true(check("berserker_stance"))
        pin(50, 1.5, 9, 0.5)
        assert.is_false(check("berserker_stance"))
    end)

    -- The window (Victorious, 20 s) and the 30 s cooldown run apart: a cast is predicted only while both allow it.
    it("refuses Victory Rush when its cooldown ends after Victorious, and allows it when it ends inside", function()
        boot("berserker_stance")
        st.applyBuff("victorious", 5)
        st.cooldown.victory_rush.expires = st.query_time + 12
        st.advance(12)
        assert.is_true(st.cooldown.victory_rush.ready)
        assert.is_false(st.buff.victorious.up)
        assert.is_false((st:IsUsable("victory_rush")))
        st.reset("Primary", true)
        st.applyBuff("victorious", 5)
        st.cooldown.victory_rush.expires = st.query_time + 3
        st.advance(3)
        assert.is_true(st.cooldown.victory_rush.ready)
        assert.is_true(st.buff.victorious.up)
        assert.is_true((st:IsUsable("victory_rush")))
    end)
end)
