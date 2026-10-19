-- tests/Game/State/enchants_spec.lua: the weapon-enchant source (Sources/Enchants.lua, C4). Out of combat, at the
-- first poll after a build and after WEAPON_ENCHANT_CHANGED, UNIT_INVENTORY_CHANGED or combat's end, one
-- C_Item.GetWeaponEnchantInfo read per weapon slot with a `weaponEnchant` pseudo-aura puts that aura up (the time
-- left, the charges as stacks) or down; in combat nothing is read and our apply cast's modelled expiry stands; a secret
-- answer, or a secret field, reads nothing; the aura walk never takes the pseudo-aura down.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")

local MH, OH, OTHER = -1001, -1002, 1099 -- RegisterAura's negative pseudo-IDs for the two id-less pseudo-auras

local function def()
    return {
        abilities = {},
        abilityIds = {},
        abilitySlot = {},
        resources = {},
        auras = {
            { key = "mh", id = MH, weaponEnchant = 0 },
            { key = "oh", id = OH, weaponEnchant = 1 },
            { key = "other", id = OTHER },
        },
        auraIds = { { MH }, { OH }, { OTHER } },
        talents = {},
        units = { "player", "target" },
    }
end

local function enchant(timeLeft, charges)
    return { { hasEnchant = true, enchantType = 0, timeLeft = timeLeft, charges = charges, enchantID = 7 } }
end

describe("weapon enchants", function()
    local VS, I, S, api, ctl

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S = I.Sources
        ctl.now = 1
        I.Build(def(), 1)
        VS.Start(api)
    end)

    local function poll(t)
        ctl.now = t
        ctl.Tick(t)
        S.RunPolls(t)
        I.Fold(t)
        I.Settle(t)
    end

    it("reads each slot once at the first poll: the time left and the charges, and nothing per frame after", function()
        ctl.enchants[0] = enchant(1800000, 20)
        poll(10)
        local rec, stacks = VS.Aura("player", MH, 10)
        assert.are.same({ 1810, 20, "observed" }, { rec.est, stacks, rec.basis })
        assert.is_nil(VS.Aura("player", OH, 10)) -- an empty list: no enchant
        assert.are.equal(2, ctl.enchantCalls)
        poll(11)
        poll(12)
        assert.are.equal(2, ctl.enchantCalls) -- no event: no read
    end)

    it("reads again after WEAPON_ENCHANT_CHANGED, UNIT_INVENTORY_CHANGED and combat's end, never in combat", function()
        poll(10)
        ctl.enchants[1] = enchant(600000, 0)
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(11)
        assert.are.equal(611, VS.Aura("player", OH, 11).est)
        ctl.enchants[1] = nil
        ctl.Fire("UNIT_INVENTORY_CHANGED", "player")
        poll(12)
        assert.is_nil(VS.Aura("player", OH, 12))
        ctl.Fire("PLAYER_REGEN_DISABLED")
        I.AuraModel(1, 1, 13, 1813, 0, 13, VS.Obs.CastSuccess, false) -- our apply cast in combat: modelled
        local calls = ctl.enchantCalls
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(14)
        assert.are.equal(calls, ctl.enchantCalls) -- in combat: no read
        assert.are.same({ 1813, "modelled" }, { VS.Aura("player", MH, 14).est, VS.Aura("player", MH, 14).basis })
        ctl.enchants[0] = enchant(1700000, 0)
        ctl.Fire("PLAYER_REGEN_ENABLED")
        poll(15)
        assert.are.same({ 1715, "observed" }, { VS.Aura("player", MH, 15).est, VS.Aura("player", MH, 15).basis })
    end)

    it("reads nothing from a secret answer or a secret field", function()
        ctl.enchants[0] = enchant(1800000, 20)
        poll(10)
        local n = I.log.n
        ctl.enchants[0] = fake.SECRET
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(11)
        ctl.enchants[0] = enchant(fake.SECRET, 20)
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(12)
        ctl.enchants[0] = { fake.SECRET }
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(13)
        assert.are.equal(n, I.log.n)
        assert.are.equal(1810, VS.Aura("player", MH, 13).est)
    end)

    it("is never taken down by an aura walk that cannot list it", function()
        ctl.enchants[0] = enchant(1800000, 20)
        poll(10)
        ctl.Fire("UNIT_AURA", "player") -- a clean, empty walk
        poll(11)
        assert.is_not_nil(VS.Aura("player", MH, 11))
    end)
end)
