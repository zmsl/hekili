-- tests/Forever/item_cooldown_secret_spec.lua (lane gear-1, G6 safety fix): an item's cooldown read through the facade
-- never hands the engine a secret. The one capture read C_Item.GetItemCooldown plain in combat, but only for idle items
-- (gear-1-feasibility.md); a secret start while the cooldown runs must not raise on an item line. A plain read passes
-- through; a secret one is the belief's (our cast of the item's use spell + its cooldown), and an item no tracked
-- ability uses reads not ready (no recommendation, no error).
local headless = require("Game.harness.headless")
local fake = require("Game.State.helpers.fake_api")
local C = require("Forever.helpers.mage_world").Frost

local SECRET = fake.SECRET
local POTION, POTION_SPELL = 13444, 17531 -- Major Mana Potion and its use spell (Hekili_Shared Consumables.lua)
local STONE = 5509 -- a Healthstone: no use spell declared, so no ability the belief tracks

local function boot()
    local H = headless.new({ character = C.character(), pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    local t = H.ctl.now + 0.2
    assert(headless.cycle(H, t))
    local lines = H.Hekili:ParseActionList("actions+=/major_mana_potion")
    lines[1].enabled = true
    lines[2] = { enabled = true, action = "frostbolt" }
    H.Hekili.DB.profile.packs[C.PACK].lists = { precombat = {}, default = lines }
    H.Hekili:LoadScripts()
    H.ctl.itemCount[POTION], H.ctl.itemUsable[POTION] = 1, true
    H.Hekili:FireToggle("potions", "on") -- off on a fresh profile
    H.Fire("PLAYER_REGEN_DISABLED")
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
    return H, t
end

local function first(H)
    local recs = H.Hekili.Engine.Output.Primary.recs
    return recs[1] and recs[1].actionName
end

describe("an item cooldown read secret in combat", function()
    it("recommends the item line from a plain read and raises nothing on a secret one", function()
        local H, t = boot()
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.equal("major_mana_potion", first(H)) -- plain 0, 0: ready
        H.ctl.itemCooldown[POTION] = { SECRET, 120 } -- running, its start secret
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.same({}, H.errors)
    end)

    it("answers a secret read from our cast of the item's use spell and its cooldown", function()
        local H, t = boot()
        H.ctl.itemCooldown[POTION] = { SECRET, SECRET }
        H.ctl.now = t + 0.1
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", POTION_SPELL)
        t = t + 10
        H.ctl.now = t - 0.1
        H.Fire("SPELL_UPDATE_COOLDOWN") -- the use spell's own flag reads ready (the fake's default): no item answer
        assert(headless.cycle(H, t))
        assert.are.same({}, H.errors)
        assert.are_not.equal("major_mana_potion", first(H))
        local st = H.Hekili.State
        st.reset("Primary", true)
        assert.is_true(math.abs(st.cooldown.major_mana_potion.remains - 110.1) < 0.5)
        assert.are.same({}, H.errors)
    end)

    it("answers a raising read as a secret one", function()
        local H, t = boot()
        H.ctl.itemCooldown[POTION] = "raise"
        H.ctl.now = t + 0.1
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", POTION_SPELL)
        t = t + 10
        assert(headless.cycle(H, t))
        assert.are.same({}, H.errors)
        assert.are_not.equal("major_mana_potion", first(H))
    end)

    it("reads an item no tracked ability uses as not ready, with no error", function()
        local H, t = boot()
        H.ctl.itemCount[STONE], H.ctl.itemUsable[STONE] = 1, true
        H.ctl.itemCooldown[STONE] = { SECRET, SECRET }
        t = t + 0.2
        assert(headless.cycle(H, t))
        local st = H.Hekili.State
        st.reset("Primary", true)
        assert.is_true(st.cooldown.healthstone.true_remains > 600) -- the Defensives toggle (off) feigns `remains`
        assert.are.same({}, H.errors)
    end)
end)
