-- tests/Forever/defensive_displays_spec.lua (L1808, owner "Defensives and interrupts should always be categorized in
-- defensive and interrupt displays"): the Defensives and Interrupts windows are separate by default, every defensive
-- and kick carries its toggle, and a spell also used offensively has a second key (`variantOf`) that carries it, so
-- the toggle routes that use alone; the variant leaves the spell's IDs and the belief's record to the original and
-- shares its cooldown in the simulation.
local headless = require("Game.harness.headless")
local loader = require("Forever.helpers.load_druid")

local function load(Class)
    if Class == "Warrior" then
        return require("Forever.helpers.load_warrior").load()
    end
    return loader.load(nil, "src/Hekili_" .. Class .. "/" .. Class .. ".lua", Class:upper())
end

describe("the defensive and interrupt displays", function()
    it("are separate by default (a fresh profile)", function()
        local dlw = require("Forever.helpers.druid_loop_world")
        local H = headless.new({ character = dlw.Guardian.character(), pack = "Guardian (wowsims.com)" })
        local t = H.Hekili.DB.profile.toggles
        assert.is_true(t.defensives.separate)
        assert.is_true(t.interrupts.separate)
        assert.is_true(t.defensives.value)
        assert.is_true(t.interrupts.value)
        t.defensives.separate = false -- a player's choice differs from the default: it is saved and kept
        assert.is_false(rawget(t.defensives, "separate"))
    end)

    local TOGGLES = {
        Rogue = { evasion = "defensives", kick = "interrupts" },
        Paladin = { divine_shield = "defensives", divine_protection = "defensives", lay_on_hands = "defensives" },
        Hunter = { deterrence = "defensives" },
        Mage = {
            mana_shield = "defensives",
            ice_block = "defensives",
            counterspell = "interrupts",
            ice_barrier_defensive = "defensives",
        },
        Warlock = { shadow_ward = "defensives", death_coil_defensive = "defensives" },
        Warrior = { pummel = "interrupts", shield_bash = "interrupts" },
        Shaman = { earth_shock_interrupt = "interrupts" },
        Priest = { power_word_shield = "defensives", desperate_prayer = "defensives" },
    }
    for Class, want in pairs(TOGGLES) do
        it("carry their toggle (" .. Class .. ")", function()
            local abilities = load(Class).abilities
            for key, toggle in pairs(want) do
                assert.is_table(abilities[key], key)
                assert.are.equal(toggle, abilities[key].toggle, key)
            end
        end)
    end

    -- the offensive use keeps its key, untoggled; the defensive or kick use is the variant
    local VARIANTS = {
        { "Warlock", "death_coil_defensive", "death_coil" },
        { "Mage", "ice_barrier_defensive", "ice_barrier" },
        { "Shaman", "earth_shock_interrupt", "earth_shock" },
    }
    for _, v in ipairs(VARIANTS) do
        local Class, key, of = v[1], v[2], v[3]
        it(key .. " is a variant of " .. of .. ": the same spell, its own toggle", function()
            local abilities = load(Class).abilities
            assert.are.equal(of, abilities[key].variantOf)
            assert.are.equal(abilities[of].id, abilities[key].id)
            assert.is_nil(abilities[of].toggle)
        end)
    end

    describe("a variant in the engine (Warlock, Death Coil)", function()
        local wl = require("Forever.helpers.warlock_world")
        local H

        before_each(function()
            H = headless.new({ character = wl.Affliction.character(), pack = wl.Affliction.PACK })
            assert.are.same({}, H.loadErrors)
        end)

        it("leaves the spell's IDs and the belief's record to the original", function()
            local abilities = H.Hekili.Class.abilities
            assert.are.equal("death_coil", abilities[6789].key)
            assert.are.equal("death_coil_defensive", abilities.death_coil_defensive.key)
            local n = 0
            for _, rec in ipairs(H.ns.VirtualStateInternal.def.abilities) do
                if rec.key == "death_coil" or rec.key == "death_coil_defensive" then
                    n = n + 1
                    assert.are.equal("death_coil", rec.key)
                end
            end
            assert.are.equal(1, n)
            -- the options list is keyed by label: each key has its own, the variant's naming its toggle
            local list = H.Hekili.Class.abilityList
            assert.are_not.equal(list.death_coil, list.death_coil_defensive)
            assert.is_truthy(list.death_coil_defensive:find("(Defensives)", 1, true))
        end)

        it("shares the cooldown both ways in the simulation", function()
            assert(headless.cycle(H, H.ctl.now + 0.2))
            local S = H.Hekili.State
            S.reset("Primary")
            assert.are.equal(0, S.cooldown.death_coil.true_remains)
            S.runHandler("death_coil_defensive")
            assert.is_true(S.cooldown.death_coil.true_remains > 100)
            S.reset("Primary")
            S.runHandler("death_coil")
            assert.is_true(S.cooldown.death_coil_defensive.true_remains > 100)
        end)
    end)
end)

-- def-2 review Minor 1: a bar holds the spell once, by its ID, so the keybind reader and the bar glow resolve the
-- original; the variant takes the original's keybind and glows the original's button (the original's `bind`)
describe("a variant's keybind and bar glow (Warlock, Death Coil)", function()
    local fake = require("Game.State.helpers.fake_api")
    local wl = require("Forever.helpers.warlock_world")
    local H

    before_each(function()
        local fakeNew = fake.new
        fake.new = function(...)
            local api, ctl = fakeNew(...)
            api.GetActionInfo = function(slot)
                if slot == 1 then
                    return "spell", 6789
                end
            end
            api.GetBindingKey = function(command)
                if command == "ACTIONBUTTON1" then
                    return "5"
                end
            end
            return api, ctl
        end
        local ok, h = pcall(headless.new, { character = wl.Affliction.character(), pack = wl.Affliction.PACK })
        fake.new = fakeNew
        assert(ok, h)
        H = h
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
    end)

    it("shows the original's keybind", function()
        H.ns.ReadKeybindings()
        local conf = H.Hekili.DB.profile.displays.Defensives
        assert.are.equal("5", H.Hekili:GetBindingForAction("death_coil", conf, 1))
        assert.are.equal("5", H.Hekili:GetBindingForAction("death_coil_defensive", conf, 1))
    end)

    it("glows the original's button", function()
        local BG = H.ns.UI.BarGlow
        local lit = {}
        BG.Glower = {
            ProcGlow_Start = function(b, opts)
                lit[b] = opts.key
            end,
            ProcGlow_Stop = function(b)
                lit[b] = nil
            end,
        }
        local cfg = H.Hekili.DB.profile.barGlow
        cfg.enabled, cfg.combatOnly = true, false
        BG.Apply()
        H.env.ActionButton1 = { action = 1 }
        BG.Rescan()
        local o = H.ns.Output.Begin("Primary")
        o[1].actionName, o[1].actionID, o[1].texture = "death_coil_defensive", 6789, "tex"
        o[1].time, o[1].exact_time = 0, H.ctl.now
        H.ns.Output.steady = false
        H.ns.Output.Publish("Primary", 1)
        assert.is_not_nil(lit[H.env.ActionButton1])
    end)
end)

-- def-2 part 2 item 4 (CPU): a separate display whose active priority has no line for it is not walked (no reset, no
-- forecast); a line for it in a custom priority, or an ability a player moves onto its toggle, walks it again
describe("a separate display with no line in the active priority", function()
    local rw = require("Forever.helpers.rogue_world")
    local H, walked

    before_each(function()
        H = headless.new({ character = rw.Combat.character(), pack = rw.Combat.PACK })
        assert.are.same({}, H.loadErrors)
        walked = {}
        local S = H.Hekili.State
        local reset = S.reset
        S.reset = function(dispName, ...)
            if dispName then
                walked[dispName] = (walked[dispName] or 0) + 1
            end
            return reset(dispName, ...)
        end
    end)

    local function cycles(n)
        walked = {}
        for _ = 1, n do
            assert(headless.cycle(H, H.ctl.now + 0.2))
        end
        return walked
    end

    it("is skipped: Interrupts (no kick in the Combat priority), while Defensives and Primary are walked", function()
        local w = cycles(5)
        assert.is_nil(w.Interrupts)
        assert.is_true((w.Defensives or 0) > 0 and (w.Primary or 0) > 0)
    end)

    it("is walked once a player moves an ability of the priority onto its toggle", function()
        local spec = H.Hekili.DB.profile.specs[H.Hekili.State.spec.id]
        spec.abilities.sinister_strike.toggle = "interrupts"
        H.Hekili:ResetSpellCaches()
        assert.is_true((cycles(5).Interrupts or 0) > 0)
    end)

    it("is walked for a custom priority with a kick line", function()
        local spec = H.Hekili.State.spec.id
        H.Hekili.DB.profile.packs["My Kicks"] = {
            spec = spec,
            builtIn = false,
            lists = {
                default = { { enabled = true, action = "kick" }, { enabled = true, action = "sinister_strike" } },
            },
        }
        H.Hekili.DB.profile.specs[spec].package = "My Kicks"
        H.Hekili.Scripts:LoadScripts()
        assert.is_true((cycles(5).Interrupts or 0) > 0)
    end)
end)
