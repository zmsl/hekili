-- tests/Forever/expects_spec.lua (unit-registry spec §5.4): the casters' and Hunter's declared outcomes, as each pack
-- registers them, are well formed by Families/Expect.lua's own rule and match the spec's table.
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
        demoralizing_roar = { "instant", nil, nil }, -- no damage: avoids only (Kinds.lua K.Accepts, school 0)
    },
    Warlock = {
        shadow_bolt = { "travel", 20, "shadow" },
        incinerate = { "travel", 20, "fire" },
        soul_fire = { "travel", 24, "fire" },
        death_coil = { "travel", 24, "shadow" },
    },
    Mage = {
        frostbolt = { "travel", 28, "frost" },
        fireball = { "travel", 24, "fire" },
        pyroblast = { "travel", 24, "fire" },
        frostfire_bolt = { "travel", 24, nil },
    },
    Shaman = { lightning_bolt = { "travel", 20, "nature" }, lava_burst = { "travel", 20, "fire" } },
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

    for class, list in pairs(DECLARED) do
        it(class .. ": each declaration is the spec's and well formed", function()
            local w = loader.load(nil, "src/Hekili_" .. class .. "/" .. class .. ".lua", class:upper())
            for key, want in pairs(list) do
                local d = assert(w.abilities[key], key)
                assert.are.same(want, { d.expects, d.velocity, d.school }, key)
                local s = d.school and ns.SCHOOL[d.school] or nil
                local au = w.auras[d.cycle or d.aura or key] -- resolved as the simulation does
                if TICKING[key] then
                    assert.is_truthy(au and au.tick_time and au.dot == "debuff", key .. ": its aura is no debuff dot")
                end
                assert.is_nil(X.Malformed(d, d.expects, X.KIND[d.expects], s, au and au.tick_time and au or nil), key)
            end
        end)
    end

    it("leaves the melee packs on their default types", function()
        local packs = { -- the Warrior's own recording loader; the Rogue's through the Druid's
            Warrior = require("Forever.helpers.load_warrior").load(),
            Rogue = loader.load(nil, "src/Hekili_Rogue/Rogue.lua", "ROGUE"),
        }
        for class, w in pairs(packs) do
            for key, d in pairs(w.abilities) do
                assert.is_nil(d.expects, class .. " " .. tostring(key))
            end
        end
    end)
end)
