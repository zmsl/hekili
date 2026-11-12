-- tests/Forever/weapon_kind_spec.lua: the gear scan's weapon kind (owner 2026-11-11, ledger L587). main_hand, off_hand
-- and ranged answer dagger, sword, axe, mace, fist (fist_weapon), staff, polearm, bow, gun, crossbow, thrown and wand
-- from the worn item's class and subclass (C_Item.GetItemInfoInstant), beside the size keys (two_handed, one_handed).
-- A real headless Balance instance; the numbers are the client's Enum.ItemWeaponSubclass values, written literally.
local headless = require("Game.harness.headless")
local W = require("Forever.helpers.druid_loop_world")

local WEAPON, ARMOR = 2, 4
local KINDS = {
    "dagger",
    "sword",
    "axe",
    "mace",
    "fist",
    "fist_weapon",
    "staff",
    "polearm",
    "bow",
    "gun",
    "crossbow",
    "thrown",
    "wand",
}
local HANDS = { [16] = "main_hand", [17] = "off_hand", [18] = "ranged" }

-- One frame, then past the gear scan's 1 s debounce (gear_parity_spec's settle).
local function settle(H)
    assert.is_true(headless.cycle(H, H.ctl.now))
    H.ctl.now = H.ctl.now + 1.1
    H.RunTimers(H.ctl.now)
    assert.is_true(headless.cycle(H, H.ctl.now))
end

local function boot()
    local c = W.Balance.character()
    c.items = nil
    local H = headless.new({ character = c, pack = W.Balance.PACK })
    settle(H)
    return H
end

local nextID = 990100
-- Wears a fresh item in `slot` (nil: empties the slot); `uncached` keeps C_Item.GetItemInfo silent for it.
local function wear(H, slot, loc, classID, subClassID, uncached)
    local id
    if loc then
        nextID = nextID + 1
        id = nextID
        H.ctl.items[id] = { "Item " .. id, loc, classID, subClassID, uncached = uncached }
    end
    H.ctl.inventory[slot] = id
    H.Fire("PLAYER_EQUIPMENT_CHANGED", slot, id ~= nil)
    settle(H)
    return id
end

-- The kind keys that answer true, per hand: { main_hand = { ... }, off_hand = { ... }, ranged = { ... } }.
local function kinds(H)
    local state, out = H.Hekili.State, {}
    for _, hand in pairs(HANDS) do
        local t = {}
        for _, k in ipairs(KINDS) do
            if state[hand][k] == true then
                t[#t + 1] = k
            elseif state[hand][k] ~= false then
                error(hand .. "." .. k .. " answered " .. tostring(state[hand][k]))
            end
        end
        out[hand] = t
    end
    return out
end

local function only(hand, list)
    local out = { main_hand = {}, off_hand = {}, ranged = {} }
    out[hand] = list
    return out
end

describe("weapon kind conditions #slow", function()
    local H
    setup(function()
        H = boot()
    end)
    after_each(function()
        for slot in pairs(HANDS) do
            if H.ctl.inventory[slot] then
                wear(H, slot, nil)
            end
        end
    end)

    it("nothing worn: every kind and size key is false, an unknown key too", function()
        assert.are.same(only("main_hand", {}), kinds(H))
        local s = H.Hekili.State
        assert.is_false(s.main_hand.two_handed)
        assert.is_false(s.off_hand.one_handed)
        assert.is_false(s.main_hand.not_a_kind)
        assert.is_false(s.ranged.not_a_kind)
    end)

    it("each kind on the main hand", function()
        local cases = {
            { "INVTYPE_WEAPON", 15, { "dagger" } },
            { "INVTYPE_WEAPONMAINHAND", 7, { "sword" } },
            { "INVTYPE_WEAPON", 0, { "axe" } },
            { "INVTYPE_WEAPON", 4, { "mace" } },
            { "INVTYPE_WEAPON", 13, { "fist", "fist_weapon" } },
            { "INVTYPE_2HWEAPON", 10, { "staff" } },
            { "INVTYPE_2HWEAPON", 6, { "polearm" } },
        }
        for _, c in ipairs(cases) do
            wear(H, 16, c[1], WEAPON, c[2])
            assert.are.same(only("main_hand", c[3]), kinds(H))
        end
    end)

    it("each kind on the off hand", function()
        local cases = {
            { "INVTYPE_WEAPONOFFHAND", 15, { "dagger" } },
            { "INVTYPE_WEAPON", 7, { "sword" } },
            { "INVTYPE_WEAPONOFFHAND", 0, { "axe" } },
            { "INVTYPE_WEAPON", 4, { "mace" } },
            { "INVTYPE_WEAPONOFFHAND", 13, { "fist", "fist_weapon" } },
        }
        for _, c in ipairs(cases) do
            wear(H, 17, c[1], WEAPON, c[2])
            assert.are.same(only("off_hand", c[3]), kinds(H))
            assert.is_true(H.Hekili.State.off_hand.one_handed)
        end
    end)

    it("each kind on the ranged slot", function()
        local cases = {
            { "INVTYPE_RANGED", 2, { "bow" } },
            { "INVTYPE_RANGEDRIGHT", 3, { "gun" } },
            { "INVTYPE_RANGED", 18, { "crossbow" } },
            { "INVTYPE_THROWN", 16, { "thrown" } },
            { "INVTYPE_RANGEDRIGHT", 19, { "wand" } },
        }
        for _, c in ipairs(cases) do
            wear(H, 18, c[1], WEAPON, c[2])
            assert.are.same(only("ranged", c[3]), kinds(H))
        end
    end)

    it("the kind combines with the size: two-handed axe, sword, mace; one-handed axe", function()
        local s = H.Hekili.State
        for _, c in ipairs({ { 1, "axe" }, { 8, "sword" }, { 5, "mace" } }) do
            wear(H, 16, "INVTYPE_2HWEAPON", WEAPON, c[1])
            assert.is_true(s.main_hand[c[2]])
            assert.is_true(s.main_hand.two_handed)
            assert.is_true(s.main_hand["2h"])
            assert.is_false(s.main_hand.one_handed)
        end
        wear(H, 16, "INVTYPE_WEAPON", WEAPON, 0)
        assert.is_true(s.main_hand.axe)
        assert.is_true(s.main_hand.one_handed)
        assert.is_false(s.main_hand.two_handed)
    end)

    it("a shield, an off-hand item and a relic are no weapon kind", function()
        wear(H, 17, "INVTYPE_SHIELD", ARMOR, 6)
        wear(H, 18, "INVTYPE_RELIC", ARMOR, 11)
        assert.are.same(only("main_hand", {}), kinds(H))
        wear(H, 17, "INVTYPE_HOLDABLE", ARMOR, 0)
        assert.are.same(only("main_hand", {}), kinds(H))
    end)

    it("an item the client has not cached does not error and still answers its kind and size", function()
        wear(H, 16, "INVTYPE_WEAPON", WEAPON, 15, true)
        assert.are.same(only("main_hand", { "dagger" }), kinds(H))
        wear(H, 16, "INVTYPE_2HWEAPON", WEAPON, 1, true)
        assert.are.same(only("main_hand", { "axe" }), kinds(H))
        assert.is_true(H.Hekili.State.main_hand.two_handed)
        assert.is_false(H.Hekili.State.main_hand.one_handed)
    end)

    it("an item unknown to the client answers false, then its kind once a gear event re-reads it", function()
        nextID = nextID + 1
        local id = nextID
        H.ctl.inventory[16] = id -- worn, no item data yet
        H.Fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
        settle(H)
        assert.are.same(only("main_hand", {}), kinds(H))
        H.ctl.items[id] = { "Late", "INVTYPE_WEAPON", WEAPON, 7 }
        H.Fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
        settle(H)
        assert.are.same(only("main_hand", { "sword" }), kinds(H))
    end)

    it("a gear change mid-session follows: dagger, then sword, then nothing", function()
        wear(H, 16, "INVTYPE_WEAPON", WEAPON, 15)
        wear(H, 17, "INVTYPE_WEAPONOFFHAND", WEAPON, 15)
        assert.are.same({ main_hand = { "dagger" }, off_hand = { "dagger" }, ranged = {} }, kinds(H))
        wear(H, 16, "INVTYPE_WEAPON", WEAPON, 7)
        assert.are.same({ main_hand = { "sword" }, off_hand = { "dagger" }, ranged = {} }, kinds(H))
        wear(H, 16, nil)
        wear(H, 17, nil)
        assert.are.same(only("main_hand", {}), kinds(H))
        assert.is_false(H.Hekili.State.main_hand.one_handed)
    end)

    it("a priority condition reads the keys through the state", function()
        wear(H, 16, "INVTYPE_2HWEAPON", WEAPON, 6)
        wear(H, 18, "INVTYPE_RANGED", WEAPON, 2)
        -- luacheck: push ignore 113 (the probe reads the state's names)
        local probe = setfenv(function()
            return main_hand.polearm and main_hand.two_handed and ranged.bow and not off_hand.dagger
        end, H.Hekili.State)
        -- luacheck: pop
        assert.is_true(probe())
    end)
end)
