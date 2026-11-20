-- tests/Forever/expects_spec.lua (unit-registry spec §5.4): the packs' declared outcomes, as each pack registers them,
-- are well formed by Families/Expect.lua's own rule and match the spec's table; the melee packs declare only debuffs.
local load = require("Game.State.helpers.load")
local loader = require("Forever.helpers.load_druid")

-- { expects, velocity, school } as each pack registers them; TICKING: the abilities whose aura (cycle, aura or key)
-- must declare a tick_time and dot = "debuff"
local TICKING = { moonfire = true, insect_swarm = true, serpent_sting = true }
local DECLARED = {
    Druid = {
        wrath = { "travel", 20, "nature" },
        starfire = { "instant", nil, "arcane" },
        moonfire = { "instant", nil, "arcane" },
        insect_swarm = { "ticks", nil, "nature" },
        -- no damage (DB2 effects, wowsims): avoids only (Kinds.lua K.Accepts, school 0)
        demoralizing_roar = { "debuff", nil, nil },
        faerie_fire = { "debuff", nil, nil },
        growl = { "debuff", nil, nil },
        challenging_roar = { "debuff", nil, nil },
    },
    Warrior = {
        sunder_armor = { "debuff", nil, nil },
        demoralizing_shout = { "debuff", nil, nil },
        challenging_shout = { "debuff", nil, nil },
        taunt = { "debuff", nil, nil },
        disarm = { "debuff", nil, nil },
        intimidating_shout = { "debuff", nil, nil },
    },
    Rogue = { expose_armor = { "debuff", nil, nil } },
    Warlock = {
        shadow_bolt = { "travel", 20, "shadow" },
        incinerate = { "travel", 20, "fire" },
        soul_fire = { "travel", 24, "fire" },
        death_coil = { "travel", 24, "shadow" },
        curse_of_the_elements = { "debuff", nil, nil },
        curse_of_recklessness = { "debuff", nil, nil },
        curse_of_weakness = { "debuff", nil, nil },
    },
    Mage = {
        frostbolt = { "travel", 28, "frost" },
        fireball = { "travel", 24, "fire" },
        pyroblast = { "travel", 24, "fire" },
        frostfire_bolt = { "travel", 24, nil },
    },
    Shaman = { lightning_bolt = { "travel", 20, "nature" } },
    Priest = { shoot = { "travel", 20, "physical" } },
    Paladin = { hammer_of_wrath = { "travel", 35, "holy" } },
    Hunter = {
        auto_shot = { "travel", 40, "physical" },
        aimed_shot = { "travel", 40, "physical" },
        arcane_shot = { "travel", 40, "arcane" },
        multi_shot = { "travel", 30, "physical" },
        sniper_shot = { "travel", 60, "physical" },
        serpent_sting = { "ticks", 40, "nature" },
    },
}

describe("the packs' declared outcomes", function()
    local ns = load.module()
    local X = ns.VirtualStateInternal.Expect
    local SCHOOL = load.school() -- Spec.lua's enum, as the build hands it to the belief (def.school)

    for class, list in pairs(DECLARED) do
        it(class .. ": each declaration is the spec's and well formed", function()
            local w = class == "Warrior" and require("Forever.helpers.load_warrior").load()
                or loader.load(nil, "src/Hekili_" .. class .. "/" .. class .. ".lua", class:upper())
            for key, want in pairs(list) do
                local d = assert(w.abilities[key], key)
                assert.are.same(want, { d.expects, d.velocity, d.school }, key)
                local s = d.school and SCHOOL[d.school] or nil
                local au = w.auras[d.cycle or d.aura or key] -- resolved as the simulation does
                if TICKING[key] then
                    assert.is_truthy(au and au.tick_time and au.dot == "debuff", key .. ": its aura is no debuff dot")
                end
                assert.is_nil(X.Malformed(d, d.expects, X.KIND[d.expects], s, au and au.tick_time and au or nil), key)
            end
        end)
    end

    it("leaves the melee packs on their default types but for the declared debuffs", function()
        local packs = { -- the Warrior's own recording loader; the Rogue's through the Druid's
            Warrior = require("Forever.helpers.load_warrior").load(),
            Rogue = loader.load(nil, "src/Hekili_Rogue/Rogue.lua", "ROGUE"),
        }
        for class, w in pairs(packs) do
            for key, d in pairs(w.abilities) do
                local want = DECLARED[class][key]
                assert.are.equal(want and want[1], d.expects, class .. " " .. tostring(key))
            end
        end
    end)

    -- (ledger L1507) Families/Expect.lua's weapon rule against each class world's outcome tables (wowsims
    -- spell_outcome.go; the DB2's DefenseType melee): a press on the special melee tables is a weapon ability, a magic
    -- hit is not. NOT_ROLLED: mapped on the melee tables' default but never dodged or parried there (no avoid roll, a
    -- judgement's alias) or, holy_strike, a holy melee special no declared field names (its own dodge closes no
    -- ticket: a gap).
    local WORLDS = {
        Warrior = "warrior_world",
        Rogue = "rogue_world",
        Druid = "druid_loop_world",
        Hunter = "hunter_world",
        Paladin = "paladin_world",
        Shaman = "shaman_world",
    }
    local NOT_ROLLED = {
        Warrior = { charge = true, taunt = true, challenging_shout = true, death_wish = true },
        Paladin = { consecration = true, swift_judgement = true, holy_strike = true },
    }
    it("calls each melee-table press a weapon ability and each magic hit a spell; the casters' all spells", function()
        for class, file in pairs(WORLDS) do
            local w = class == "Warrior" and require("Forever.helpers.load_warrior").load()
                or loader.load(nil, "src/Hekili_" .. class .. "/" .. class .. ".lua", class:upper())
            local W, skip = require("Forever.helpers." .. file), NOT_ROLLED[class] or {}
            for key in pairs(W.MAP) do
                local d = w.abilities[key]
                if type(d) == "table" and rawget(d, "startsCombat") and not skip[key] then
                    local o = W.OUTCOMES[key]
                    if o == nil or o == "spell" then
                        local s = d.school and SCHOOL[d.school] or nil
                        assert.are.equal(o == nil, X.Weapon(d, s, SCHOOL), class .. " " .. key)
                    end
                end
            end
        end
        for _, class in ipairs({ "Mage", "Warlock" }) do
            local w = loader.load(nil, "src/Hekili_" .. class .. "/" .. class .. ".lua", class:upper())
            for key, d in pairs(w.abilities) do
                if type(d) == "table" then
                    local s = d.school and SCHOOL[d.school] or nil
                    assert.is_false(X.Weapon(d, s, SCHOOL), class .. " " .. tostring(key))
                end
            end
        end
    end)
end)
