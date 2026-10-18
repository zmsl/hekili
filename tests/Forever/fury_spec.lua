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
    assert.is_true(st.buff[stance].up, stance)
end

local function set(name, value)
    H.Hekili.DB.profile.specs[ww.SPEC].settings[name] = value
end

-- Line `action`'s condition (its entry in Fury's default list) as the engine evaluates it now.
local function check(action)
    for i, e in ipairs(H.Hekili.DB.profile.packs.Fury.lists.default) do
        if e.action == action then
            local ok, err = H.Hekili.Scripts:CheckScript("Fury:default:" .. i)
            assert.is_nil(err, action)
            return ok and true or false
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
    it("is the user's list: the five focus lines first, no Execute, cooldowns, shouts or stance swaps", function()
        local fury = assert(loadfile("tools/make_pack.lua"))("lists")[2]
        assert.are.equal("Fury", fury.name)
        local order, focus = {}, {}
        for i, e in ipairs(fury.lists.default) do
            order[i] = e.action
            if e.focus == 1 then
                focus[#focus + 1] = e.action
            end
        end
        assert.are.same({
            "victory_rush",
            "overpower",
            "revenge",
            "heroic_strike",
            "cleave",
            "rend",
            "sunder_armor",
            "thunder_clap",
            "demoralizing_shout",
            "bloodthirst",
            "whirlwind",
        }, order)
        assert.are.same({ "victory_rush", "overpower", "revenge", "heroic_strike", "cleave" }, focus)
        local lists = {}
        for name, entries in pairs(fury.lists) do
            lists[#lists + 1] = name .. " " .. #entries
        end
        table.sort(lists)
        assert.are.same({ "default 11", "precombat 1" }, lists) -- the precombat list is the Charge opener only
        assert.are.equal("charge", fury.lists.precombat[1].action)
        assert.are.same({ 1, 1 }, { fury.lists.default[4].use_off_gcd, fury.lists.default[5].use_off_gcd })
    end)

    it("defaults the thresholds to 40 and the upkeep toggles to Sunder on, Thunder Clap and the shout off", function()
        local w = require("Forever.helpers.load_warrior").load()
        assert.are.same({ 40, 40, true, false, false }, {
            w.settings.hs_threshold.default,
            w.settings.cleave_threshold.default,
            w.settings.debuff_sunder_enabled.default,
            w.settings.maintain_thunder_clap.default,
            w.settings.debuff_demoshout_enabled.default,
        })
    end)

    describe("Heroic Strike and Cleave never clip Bloodthirst or Whirlwind (Review Focus 1)", function()
        before_each(function()
            boot("berserker_stance")
        end)

        it("refuses Heroic Strike when Bloodthirst comes up before the swing and the rest is short of it", function()
            local hs, bt = st.action.heroic_strike.cost, st.action.bloodthirst.cost
            pin(hs + bt - 1, 1.5, 1, 9)
            assert.is_true(st.rage.current >= 40)
            assert.is_false(check("heroic_strike"))
            pin(hs + bt, 1.5, 1, 9) -- enough left for Bloodthirst
            assert.is_true(check("heroic_strike"))
            pin(hs + bt - 1, 1.5, 2, 9) -- Bloodthirst comes up after the swing
            assert.is_true(check("heroic_strike"))
            pin(hs + bt - 1, 0, 0, 9) -- a swing due now (or no swing speed read): Bloodthirst ready still reserved
            assert.is_false(check("heroic_strike"))
        end)

        it("refuses Cleave when Whirlwind comes up before the swing and the rest is short of it", function()
            local cl, wwc = st.action.cleave.cost, st.action.whirlwind.cost
            pin(cl + wwc - 1, 1.5, 9, 0.5, 2)
            assert.is_true(st.rage.current >= 40)
            assert.is_false(check("cleave"))
            pin(cl + wwc, 1.5, 9, 0.5, 2)
            assert.is_true(check("cleave"))
            pin(cl + wwc - 1, 1.5, 9, 3, 2) -- Whirlwind comes up after the swing
            assert.is_true(check("cleave"))
            pin(cl + wwc - 1, 0, 9, 0, 2) -- a swing due now: Whirlwind ready still reserved
            assert.is_false(check("cleave"))
        end)

        it("needs the threshold's rage and the target count: Heroic Strike on one, Cleave on more", function()
            pin(39, 1.5, 9, 9)
            assert.is_false(check("heroic_strike"))
            pin(40, 1.5, 9, 9)
            assert.is_true(check("heroic_strike"))
            assert.is_false(check("cleave"))
            set("hs_threshold", 60)
            assert.is_false(check("heroic_strike"))
            pin(40, 1.5, 9, 9, 3)
            assert.is_false(check("heroic_strike"))
            assert.is_true(check("cleave"))
            set("cleave_threshold", 41)
            assert.is_false(check("cleave"))
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
end)
