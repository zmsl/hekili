-- tests/Game/State/enchants_spec.lua: the weapon-enchant source (Sources/Enchants.lua, C4). At the first poll after a
-- build and after WEAPON_ENCHANT_CHANGED or WEAPON_SLOT_CHANGED (in combat too), or UNIT_INVENTORY_CHANGED and combat's
-- end (out of combat), one C_Item.GetWeaponEnchantInfo read per weapon slot: a `weaponEnchant` slot pseudo-aura is up
-- while its slot carries an imbue-layer enchant (not a stone or oil, enchantType 2), an `enchants` aura while either
-- slot carries one of its enchant IDs (the time left, the charges as stacks), else down; a secret answer, or a secret
-- field, reads nothing and takes nothing down; a 0 time left (the client's first seconds after login) is unknown; the
-- aura walk never takes these auras down.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")

local MH, OH, OTHER = -1001, -1002, 1099 -- RegisterAura's negative pseudo-IDs for the two id-less pseudo-auras
local RB, DP = -1003, -1004 -- two id-less `enchants` auras (an imbue's and a poison's enchant IDs)

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
            { key = "rb", id = RB, enchants = { 29, 1664 } },
            { key = "dp", id = DP, enchants = { 2630 } },
        },
        auraIds = { { MH }, { OH }, { OTHER }, { RB }, { DP } },
        talents = {},
        units = { "player", "target" },
    }
end

local function enchant(timeLeft, charges)
    return { { hasEnchant = true, enchantType = 0, timeLeft = timeLeft, charges = charges, enchantID = 7 } }
end

-- One list entry: an imbue-layer enchant (3) unless `kind` says otherwise.
local function entry(id, timeLeft, kind, charges)
    return { hasEnchant = true, enchantType = kind or 3, timeLeft = timeLeft, charges = charges or 0, enchantID = id }
end
local NONE = { hasEnchant = false, enchantType = 0, timeLeft = 0, charges = 0, enchantID = 0 }
local OIL = { hasEnchant = true, enchantType = 2, timeLeft = 900000, charges = 0, enchantID = 2628 }

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

    it("reads again after WEAPON_ENCHANT_CHANGED, UNIT_INVENTORY_CHANGED and combat's end", function()
        poll(10)
        ctl.enchants[1] = enchant(600000, 0)
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(11)
        assert.are.equal(611, VS.Aura("player", OH, 11).est)
        ctl.enchants[1] = nil
        ctl.Fire("UNIT_INVENTORY_CHANGED", "player")
        poll(12)
        assert.is_nil(VS.Aura("player", OH, 12))
        ctl.enchants[0] = enchant(1700000, 0)
        ctl.Fire("PLAYER_REGEN_ENABLED")
        poll(15)
        assert.are.same({ 1715, "observed" }, { VS.Aura("player", MH, 15).est, VS.Aura("player", MH, 15).basis })
    end)

    -- Owner 2026-11-05: the list is plain in combat (Shaman L10 probe, open world and a dungeon); a recast shows
    -- through WEAPON_ENCHANT_CHANGED. UNIT_INVENTORY_CHANGED (durability too) stays an out-of-combat trigger.
    it(
        "reads in combat after WEAPON_ENCHANT_CHANGED or WEAPON_SLOT_CHANGED, never after UNIT_INVENTORY_CHANGED",
        function()
            poll(10)
            ctl.Fire("PLAYER_REGEN_DISABLED")
            I.AuraModel(1, 1, 13, 1813, 0, 13, VS.Obs.CastSuccess, false) -- our apply cast in combat: modelled
            local calls = ctl.enchantCalls
            ctl.enchants[0] = enchant(1700000, 0)
            ctl.Fire("UNIT_INVENTORY_CHANGED", "player")
            poll(14)
            assert.are.equal(calls, ctl.enchantCalls)
            assert.are.same({ 1813, "modelled" }, { VS.Aura("player", MH, 14).est, VS.Aura("player", MH, 14).basis })
            ctl.Fire("WEAPON_ENCHANT_CHANGED")
            poll(15)
            assert.are.same({ 1715, "observed" }, { VS.Aura("player", MH, 15).est, VS.Aura("player", MH, 15).basis })
            ctl.enchants[0] = nil -- a weapon swapped for an unenchanted one
            ctl.Fire("WEAPON_SLOT_CHANGED", 0)
            poll(16)
            assert.is_nil(VS.Aura("player", MH, 16))
        end
    )

    it("coalesces a burst of inventory events into one read per slot", function()
        poll(10)
        local calls = ctl.enchantCalls
        for _ = 1, 60 do -- the login burst (probe 2026-11-05: about 60 in one instant)
            ctl.Fire("UNIT_INVENTORY_CHANGED", "player")
        end
        poll(11)
        assert.are.equal(calls + 2, ctl.enchantCalls)
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

    -- Forever lists two layers per weapon slot: a temporary one (stones and oils, enchantType 2) and the imbue one
    -- (imbues, poisons, enchantType 3). The slot pseudo-aura is the imbue layer only, matched by contents, not position.
    it("puts the slot up for the imbue layer only: an oil or stone alone leaves it down", function()
        local OIL = { hasEnchant = true, enchantType = 2, timeLeft = 900000, charges = 0, enchantID = 2628 }
        local IMBUE = { hasEnchant = true, enchantType = 3, timeLeft = 1700000, charges = 0, enchantID = 1664 }
        local EMPTY = { hasEnchant = false, enchantType = 0, timeLeft = 0, charges = 0, enchantID = 0 }
        ctl.enchants[0] = { OIL, EMPTY }
        poll(10)
        assert.is_nil(VS.Aura("player", MH, 10))
        ctl.enchants[0] = { OIL, IMBUE }
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(11)
        assert.are.equal(1711, VS.Aura("player", MH, 11).est)
        ctl.enchants[0] = { IMBUE, OIL } -- by contents, never by position
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(12)
        assert.are.equal(1712, VS.Aura("player", MH, 12).est)
    end)

    it("puts an `enchants` aura up from its enchant ID on either hand, and down when no hand carries it", function()
        ctl.enchants[0] = { OIL, entry(1664, 1700000) }
        poll(10)
        assert.are.same({ 1710, 1710 }, { VS.Aura("player", RB, 10).est, VS.Aura("player", MH, 10).est })
        assert.is_nil(VS.Aura("player", DP, 10))
        ctl.enchants[0] = { OIL, NONE }
        ctl.enchants[1] = { NONE, entry(29, 600000) } -- the imbue moved to the off hand
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(11)
        assert.are.same({ 611, 611 }, { VS.Aura("player", RB, 11).est, VS.Aura("player", OH, 11).est })
        assert.is_nil(VS.Aura("player", MH, 11))
        ctl.enchants[0] = { NONE, entry(2630, 1800000, 3, 40) } -- a poison on the main hand: its charges as stacks
        ctl.enchants[1] = nil
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(12)
        local rec, stacks = VS.Aura("player", DP, 12)
        assert.are.same({ 1812, 40 }, { rec.est, stacks })
        assert.is_nil(VS.Aura("player", RB, 12))
        assert.is_nil(VS.Aura("player", OH, 12))
    end)

    it("takes no `enchants` aura down while either slot reads secret", function()
        ctl.enchants[1] = { NONE, entry(2630, 1800000) }
        poll(10)
        ctl.enchants[0] = { NONE, entry(fake.SECRET, 1800000) } -- a secret enchant ID reads nothing
        ctl.enchants[1] = nil
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(11)
        assert.are.equal(1810, VS.Aura("player", DP, 11).est)
        ctl.enchants[0] = fake.SECRET
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(12)
        assert.are.equal(1810, VS.Aura("player", DP, 12).est)
    end)

    -- Probe 2026-11-05: at login the imbue reads hasEnchant with timeLeft 0 for its first seconds; WEAPON_ENCHANT_CHANGED
    -- follows with the real time left.
    it("treats a 0 time left as unknown: nothing up or down until the next read", function()
        ctl.enchants[0] = { NONE, entry(1664, 1700000) }
        poll(10)
        ctl.enchants[0] = { NONE, entry(1664, 0) }
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(11)
        assert.are.same({ 1710, 1710 }, { VS.Aura("player", RB, 11).est, VS.Aura("player", MH, 11).est })
        local calls = ctl.enchantCalls
        poll(12)
        assert.are.equal(calls, ctl.enchantCalls) -- no retry per poll: the next event reads
        ctl.enchants[0] = { NONE, entry(1664, 1500000) }
        ctl.Fire("WEAPON_ENCHANT_CHANGED")
        poll(13)
        assert.are.same({ 1513, 1513 }, { VS.Aura("player", RB, 13).est, VS.Aura("player", MH, 13).est })
    end)

    it("is never taken down by an aura walk that cannot list it", function()
        ctl.enchants[0] = { NONE, entry(1664, 1800000, 3, 20) }
        poll(10)
        ctl.Fire("UNIT_AURA", "player") -- a clean, empty walk
        poll(11)
        assert.is_not_nil(VS.Aura("player", MH, 11))
        assert.is_not_nil(VS.Aura("player", RB, 11))
    end)
end)
