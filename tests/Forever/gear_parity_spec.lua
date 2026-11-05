-- tests/Forever/gear_parity_spec.lua (gear-aware spec §10.4, R32d): the core's `state` and the belief's `now` context
-- answer the same gear reads with the same values at the same times. One probe function is evaluated in both
-- environments (setfenv to Hekili.State, and I.Eval) at each scenario, together with the Insect Swarm aura's own
-- duration function, and both must equal each other and the scenario's literal row. Real headless Balance instances.
-- R38a: relics and armour never change in combat, so an in-combat equipment change is not a supported scenario (a
-- weapon-keyed effect gets Amendment A's scenarios the day one exists); the in-combat scenario pins that the worn row
-- holds through combat.
local headless = require("Game.harness.headless")
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.druid_loop_world")
local sameKeys = require("Forever.helpers.gear_keys")

local IDOL, SET, FAKE, BONUS = 272430, { 273884, 273885, 273886, 273887 }, { 990001, 990002 }, 1301242

-- The Druid pack declares the idol, the four shipped pieces (db.json setId 2114) and the 5-piece aura; the test adds
-- two fake ids for the head and chest (not in the game files; test only), appended to the pack's set.
local function declare(H)
    H.Hekili.Class.kit:RegisterGear("grovekeeper_eclipse", FAKE[1], FAKE[2])
    H.Hekili:SpecializationChanged() -- class.gear, def.gear, the belief rebuilt
end

-- luacheck: push ignore 113 (the probe reads its environment's names)
local function PROBE()
    return {
        set_bonus.swarming_idol,
        set_bonus.grovekeeper_eclipse,
        set_bonus.grovekeeper_eclipse_2pc,
        set_bonus.grovekeeper_eclipse_4pc,
        set_bonus.grovekeeper_eclipse_5pc,
        set_bonus.grovekeeper_eclipse_6pc,
        set_bonus.not_declared,
        equipped.swarming_idol,
        equipped.grovekeeper_eclipse,
        equipped.not_declared,
    }
end
-- luacheck: pop

-- The probe and the aura's duration, under the core's `state` and in the belief's context.
local function both(H)
    local I = H.ns.VirtualStateInternal
    local engine = setfenv(PROBE, H.Hekili.State)()
    local belief, ok = I.Eval(PROBE, H.ctl.now, true)
    assert.is_true(ok, tostring(I.nowError))
    local dur -- the record's function: the object both environments run (spec §8)
    for _, rec in ipairs(I.def.auras) do
        dur = rec.key == "insect_swarm" and rec.duration or dur
    end
    assert.are.equal("function", type(dur))
    local env = getfenv(dur)
    engine[#engine + 1] = setfenv(dur, H.Hekili.State)()
    setfenv(dur, env)
    local d, dok = I.Eval(dur, H.ctl.now, true)
    assert.is_true(dok, tostring(I.nowError))
    belief[#belief + 1] = d
    return engine, belief
end

-- One frame now (the game runs one every few ms: the build's player walk, poll 10, runs at the first), then the clock
-- past the 1 s debounce in both: the core's timer, the belief's poll 8 at the frame's Drain.
local function settle(H)
    assert.is_true(headless.cycle(H, H.ctl.now))
    H.ctl.now = H.ctl.now + 1.1
    H.RunTimers(H.ctl.now)
    assert.is_true(headless.cycle(H, H.ctl.now))
end

local function wear(H, items)
    for slot, id in pairs(items) do
        H.ctl.inventory[slot] = id
        H.Fire("PLAYER_EQUIPMENT_CHANGED", slot, true)
    end
    settle(H)
end

local function strip(H)
    for slot in pairs(H.ctl.inventory) do
        H.ctl.inventory[slot] = nil
        H.Fire("PLAYER_EQUIPMENT_CHANGED", slot, false)
    end
    settle(H)
end

local function bonusAura(H, up)
    local list = H.ctl.auras.player.HELPFUL
    for i = #list, 1, -1 do
        if list[i].spellId == BONUS then
            table.remove(list, i)
        end
    end
    if up then
        list[#list + 1] = { spellId = BONUS, expirationTime = H.ctl.now + 3600, applications = 0 }
    end
    H.Fire("UNIT_AURA", "player")
    assert.is_true(headless.cycle(H, H.ctl.now))
end

-- `login`: no test registration and no rebuild, only the login path's own read (scenario 8).
local function boot(items, login)
    local c = W.Balance.character()
    c.items = items
    c.talents[1223083] = 1 -- Nature's Splendor rank 1: the duration's talent term in both
    local H = headless.new({ character = c, pack = W.Balance.PACK })
    if not login then
        declare(H)
    end
    settle(H)
    return H
end

-- Nature's Splendor rank 1 in the Balance character: 12 + 2 = 14 s; the idol +2 s, the 5-piece +3 s (R32).
local DUR = 14
-- (idol, set, 2pc, 4pc, 5pc, 6pc, undeclared, eq.idol, eq.set, eq.undeclared, insect_swarm duration)
local NONE = { 0, 0, 0, 0, 0, 0, 0, false, false, false, DUR }
local IDOL_ROW = { 1, 0, 0, 0, 0, 0, 0, true, false, false, DUR + 2 }
local FOUR = { 0, 4, 1, 1, 0, 0, 0, false, true, false, DUR }
local SIX = { 0, 6, 1, 1, 1, 1, 0, false, true, false, DUR + 3 }
local BONUS_ROW = { 0, 0, 0, 0, 1, 0, 0, false, false, false, DUR + 3 }

local FOUR_ITEMS = { [3] = SET[1], [7] = SET[2], [8] = SET[3], [10] = SET[4] }

local function expect(H, row)
    local engine, belief = both(H)
    assert.are.same(engine, belief)
    assert.are.same(row, engine)
end

describe("gear parity between the core and the belief #slow", function()
    it("0. the declared keys are the same on both sides", function()
        local H = boot(nil)
        local I = H.ns.VirtualStateInternal
        local keys = {}
        for _, d in ipairs(I.def.gear) do
            keys[d.key] = d.aura or #d.items
        end
        assert.are.same({ 1, 6, BONUS }, { keys.swarming_idol, keys.grovekeeper_eclipse, keys.grovekeeper_eclipse_5pc })
        sameKeys(H.Hekili.Class, I.def, I)
    end)

    it("1. nothing worn", function()
        expect(boot(nil), NONE)
    end)

    it("2. the idol in slot 18", function()
        local H = boot(nil)
        wear(H, { [18] = IDOL })
        expect(H, IDOL_ROW)
    end)

    it("3. the four real pieces", function()
        local H = boot(nil)
        wear(H, FOUR_ITEMS)
        expect(H, FOUR)
    end)

    it("4. the four plus the two fake ids, then the idol too, then 6. unequip everything", function()
        local H = boot(nil)
        wear(H, FOUR_ITEMS)
        wear(H, { [1] = FAKE[1], [5] = FAKE[2] })
        expect(H, SIX)
        wear(H, { [18] = IDOL }) -- the idol and the 5-piece together: 12 + 2 + 2 + 3
        expect(H, { 1, 6, 1, 1, 1, 1, 0, true, true, false, DUR + 5 })
        strip(H)
        expect(H, NONE)
    end)

    it("5. the bonus aura alone, then removed", function()
        local H = boot(nil)
        bonusAura(H, true)
        H.Fire("PLAYER_EQUIPMENT_CHANGED", 1, false) -- the read's trigger
        settle(H)
        expect(H, BONUS_ROW)
        bonusAura(H, false)
        H.Fire("PLAYER_EQUIPMENT_CHANGED", 1, false)
        settle(H)
        expect(H, NONE)
    end)

    it("7. a spec rebuild with the four pieces worn", function()
        local H = boot(nil)
        wear(H, FOUR_ITEMS)
        H.Hekili:SpecializationChanged()
        settle(H)
        expect(H, FOUR)
    end)

    it("7b. a spec rebuild while the bonus aura is up (the build's player walk, Q2)", function()
        local H = boot(nil)
        bonusAura(H, true)
        H.Fire("PLAYER_EQUIPMENT_CHANGED", 1, false)
        settle(H)
        expect(H, BONUS_ROW)
        H.Hekili:SpecializationChanged() -- no UNIT_AURA after it
        settle(H)
        expect(H, BONUS_ROW)
    end)

    it("8. login before the item cache: the four pieces read with no name and no event", function()
        local H = boot({ [3] = { SET[1] }, [7] = { SET[2] }, [8] = { SET[3] }, [10] = { SET[4] } }, true)
        for _, id in ipairs(SET) do
            assert.is_nil(H.ctl.items[id][1]) -- not cached: no name
        end
        expect(H, FOUR)
    end)

    it("9. in combat the worn row holds (R38a: no relic or armour change in combat)", function()
        local H = boot(nil)
        wear(H, { [18] = IDOL })
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        settle(H)
        expect(H, IDOL_ROW)
        settle(H)
        expect(H, IDOL_ROW)
    end)

    it("10. an oracle skip leaves the idol unequipped in the replay's gear", function()
        local items = ws.gear("druid_balance", { swarming_idol = { IDOL } })
        assert.is_nil(items[18])
        local H = boot(items)
        local row = { 0, 0, 0, 0, 0, 0, 0, false, false, false, DUR }
        expect(H, row)
        -- the same build without the skip wears the idol in both
        expect(boot(ws.gear("druid_balance", {})), IDOL_ROW)
    end)
end)
