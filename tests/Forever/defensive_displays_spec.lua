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
            fire_ward = "defensives", -- def-2 review Minor 10: the school wards, like Shadow Ward
            frost_ward = "defensives",
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

    -- def-2 review Minor 6: Cold Snap ends Ice Barrier's cooldown under both keys in the simulation
    it("Cold Snap ends both Ice Barrier keys' cooldown (Mage)", function()
        local mw = require("Forever.helpers.mage_world")
        local H = headless.new({ character = mw.Frost.character(), pack = mw.Frost.PACK })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        local S = H.Hekili.State
        S.reset("Primary")
        S.setCooldown("ice_barrier", 30) -- a cast's: its own key's cooldown, and its handler the other's
        S.setCooldown("ice_barrier_defensive", 30)
        S.runHandler("cold_snap")
        assert.are.equal(0, S.cooldown.ice_barrier.true_remains)
        assert.are.equal(0, S.cooldown.ice_barrier_defensive.true_remains)
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

-- (def-2c re-review F2) The Defensives skip below covers every built-in priority: each line on the Defensives toggle
-- (the ability's own, racials and shared items included) is NeedsHealth, so none walks Defensives while the player's
-- health is unread (the library-off rule: no defensive shown without a reading).
describe("every built-in priority's Defensives lines", function()
    it("each need a health reading (all 30 priorities, each with one at least)", function()
        local CLASSES = { -- one world a class: a boot loads every priority of its class (Scripts:LoadScripts)
            Druid = require("Forever.helpers.druid_loop_world").Guardian,
            Warrior = require("Forever.helpers.warrior_world").Protection,
            Rogue = require("Forever.helpers.rogue_world").Combat,
            Mage = require("Forever.helpers.mage_world").Frost,
            Paladin = require("Forever.helpers.paladin_world").Retribution,
            Priest = require("Forever.helpers.priest_world").Shadow,
            Hunter = require("Forever.helpers.hunter_world").Survival,
            Warlock = require("Forever.helpers.warlock_world").Affliction,
            Shaman = require("Forever.helpers.shaman_world").Enhancement,
        }
        local packs, bare = {}, {}
        for class, C in pairs(CLASSES) do
            local H = headless.new({ character = C.character(), pack = C.PACK or "Protection (wowsims.com)" })
            assert.are.same({}, H.loadErrors)
            local abilities, DB = H.Hekili.Class.abilities, H.Hekili.Scripts.DB
            for name, p in pairs(H.Hekili.DB.profile.packs) do
                if p.builtIn then
                    local key = class .. " " .. name
                    packs[key] = packs[key] or 0
                    for list, entries in pairs(p.lists) do
                        for i, e in ipairs(entries) do
                            local a = abilities[e.action]
                            if a and a.toggle == "defensives" then
                                local script = DB[name .. ":" .. list .. ":" .. i]
                                assert.is_table(script, name .. ":" .. list .. ":" .. i)
                                packs[key] = packs[key] + 1
                                if not script.NeedsHealth then
                                    bare[#bare + 1] = key .. " " .. list .. " " .. i .. ": " .. e.action
                                end
                            end
                        end
                    end
                end
            end
        end
        table.sort(bare)
        assert.are.same({}, bare)
        local n = 0
        for name, lines in pairs(packs) do
            n = n + 1
            assert.is_true(lines > 0, name .. ": no Defensives line")
        end
        assert.are.equal(30, n)
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

    it("is skipped: Interrupts (no kick in the Combat priority), while Primary is walked", function()
        local w = cycles(5)
        assert.is_nil(w.Interrupts)
        assert.is_true((w.Primary or 0) > 0)
    end)

    -- def-2 review CPU item: every Defensives line of the Combat priority reads `health.known&...` (the guard
    -- detector's sense), so none can pass while the health is unread: the display is not walked until a reading
    describe("whose every line needs a health reading", function()
        local fake_lhv = require("Game.harness.fake_lhv")

        local function custom(entries)
            local spec = H.Hekili.State.spec.id
            H.Hekili.DB.profile.packs["My Evasion"] = { spec = spec, builtIn = false, lists = { default = entries } }
            H.Hekili.DB.profile.specs[spec].package = "My Evasion"
            H.Hekili.Scripts:LoadScripts()
            return H.Hekili.DB.profile.specs[spec]
        end

        -- the library answering the player's health (a reading after its first prime)
        local function library()
            local lhv = fake_lhv.new({
                now = function()
                    return H.ctl.now
                end,
            })
            local major, minor = lhv:GetVersion()
            local stub = rawget(H.env, "LibStub")
            stub.libs[major], stub.minors[major] = lhv, minor
            H.Hekili.bandOff = false
            H.Hekili:ProvidersChanged()
            H.ctl.health, H.ctl.healthMax = 1000, 1000
            lhv:Push("health", "player", nil, 1000, 1000, H.ctl.now)
            return lhv
        end

        -- n updates, one at a time: each walks Defensives exactly when the health is read (the skip's live read,
        -- Core.lua canPass, the same instant); returns the first update that read it, or nil
        local function each(n, want)
            local S, first = H.Hekili.State, nil
            for i = 1, n do
                local w = cycles(1)
                local known = S.health.known == true
                assert.are.equal(known, (w.Defensives or 0) > 0, "update " .. i)
                if want ~= nil then
                    assert.are.equal(want, known, "update " .. i)
                end
                first = first or (known and i or nil)
            end
            return first
        end

        it("is skipped while the health is unread, walked from the first update with a reading", function()
            assert.is_nil(cycles(5).Defensives)
            local lhv = library()
            assert.is_true((each(20) or 0) > 1) -- unread through the prime, then read: walked from that update on
            lhv:SetAvailable("unavailable", "error", "health") -- the reading lost: skipped from the next update
            each(2) -- the loss reaches the read at the next update at the latest
            each(5, false)
        end)

        it(
            "is walked on the first update after the Defensives toggle comes back on, and after a pack reload",
            function()
                local lhv = library()
                each(14)
                each(1, true)
                local toggles = H.Hekili.DB.profile.toggles
                toggles.defensives.value = false
                assert.is_nil(cycles(3).Defensives)
                toggles.defensives.value = true
                each(1, true)
                H.Hekili.Scripts:LoadScripts() -- a pack reload sets each script's NeedsHealth again
                each(1, true)
                lhv:SetAvailable("unavailable", "error", "health")
                each(2)
                each(1, false)
                H.Hekili.Scripts:LoadScripts()
                each(3, false)
            end
        )

        it("is walked for a custom line that does not need it", function()
            custom({
                { enabled = true, action = "evasion", criteria = "buff.evasion.down" },
                { enabled = true, action = "sinister_strike" },
            })
            assert.is_true((cycles(5).Defensives or 0) > 0)
        end)

        -- def-2 review Minor 7: a line the player switched off, or its ability disabled, shows nothing either
        it("is skipped for a line switched off or an ability disabled", function()
            local entry = { enabled = false, action = "evasion", criteria = "buff.evasion.down" }
            local spec = custom({ entry, { enabled = true, action = "sinister_strike" } })
            assert.is_nil(cycles(5).Defensives)
            entry.enabled = true
            H.Hekili.Scripts:LoadScripts()
            assert.is_true((cycles(5).Defensives or 0) > 0)
            spec.abilities.evasion.disabled = true
            H.Hekili:ResetSpellCaches()
            assert.is_nil(cycles(5).Defensives)
        end)
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
