-- tests/Game/State/gear_spec.lua (gear-aware spec §4, §7, §10.1, §12, §13): the belief's gear family and source. The
-- declared gear (def.gear) read from the equipment (C_Item.IsEquippedItem) and the belief's own player auras, with the
-- core's `set_bonus` semantics in the `now` context: counts, bonus auras, `<key>_<n>pc`, the 1 s coalesce, in-combat
-- reads, the rebuild carry-over and the player aura walk at each build, the Gear log rows, a raising or secret read,
-- and zero allocation per read and per lookup.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

local ITEM = 900001
local SET = { 900011, 900012, 900013, 900014, 900015 }

describe("the gear family and source", function()
    local ns, VS, I, S, api, ctl, def

    before_each(function()
        api, ctl = fake.new()
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S = I.Sources
        ctl.now = 10
        VS.Start(api) -- login, then the build (PLAYER_ENTERING_WORLD)
        def = fs.def(fs.new(9))
        def.gear = { { key = "idol", items = { ITEM } }, { key = "set", items = SET } }
    end)

    local function fire(t, event, ...)
        ctl.now = t
        ctl.Fire(event, ...)
    end
    local function drain(t)
        ctl.now = t
        fs.fold(ns, t)
    end
    -- a build at t, then a drain past its re-read (t + 1 s), so later reads start clean
    local function build(t)
        ctl.now = t
        I.Build(def, t)
        drain(t + 1)
    end
    local function wearSet(n)
        local slots = { 3, 7, 8, 1, 5 }
        for k = 1, 5 do
            ctl.inventory[slots[k]] = k <= n and SET[k] or nil
        end
    end
    local function withBonus()
        def.gear[3] = { key = "set_5pc", aura = fs.SPENDER_A } -- a tracked aura's id
    end
    local function auraUp(on)
        ctl.auras.player.HELPFUL[1] = on and { spellId = fs.SPENDER_A, expirationTime = 0, applications = 0 } or nil
    end
    local function gearRows()
        local n = 0
        for i = 1, I.log.n do
            if I.ObsLog.At(I.log, i).kind == VS.Obs.Gear then
                n = n + 1
            end
        end
        return n
    end

    it("counts the equipped pieces; derives <key>_<n>pc; any other key reads 0; equipped is set_bonus > 0", function()
        ctl.items[5] = { "Shield", "INVTYPE_SHIELD" }
        ctl.inventory[17] = 5
        ctl.inventory[18] = ITEM
        wearSet(3)
        build(100)
        local sb, eq = I.nowCtx.set_bonus, I.nowCtx.equipped
        assert.are.same({ 1, 3, 1, 0, 0, 0 }, { sb.idol, sb.set, sb.set_3pc, sb.set_4pc, sb.nope, sb[12345] })
        assert.are.same({ true, false, true }, { eq.idol, eq.nope, eq.shield }) -- shield: Sources/Player.lua's raw key
    end)

    it("reads 1 s after an equipment change, restarted by each event", function()
        build(100)
        local sb = I.nowCtx.set_bonus
        ctl.inventory[18] = ITEM
        fire(110, "PLAYER_EQUIPMENT_CHANGED", 18, false)
        drain(110.5)
        assert.equal(0, sb.idol)
        drain(111)
        assert.equal(1, sb.idol)
        ctl.inventory[18] = nil
        fire(120, "PLAYER_EQUIPMENT_CHANGED", 18, true)
        fire(120.8, "PLAYER_EQUIPMENT_CHANGED", 18, true)
        drain(121)
        assert.equal(1, sb.idol)
        drain(121.8)
        assert.equal(0, sb.idol)
    end)

    it("reads in combat too, with no deferral", function()
        build(100)
        ctl.combat = true
        fire(110, "PLAYER_REGEN_DISABLED")
        assert.is_true(I.inCombat)
        wearSet(2)
        fire(111, "PLAYER_EQUIPMENT_CHANGED", 3, false)
        drain(112)
        assert.are.same({ 2, 1 }, { I.nowCtx.set_bonus.set, I.nowCtx.set_bonus.set_2pc })
    end)

    it("a bonus key is 1 while its aura is believed up; <set>_<n>pc is the bonus or the count", function()
        withBonus()
        build(100)
        local sb = I.nowCtx.set_bonus
        auraUp(true)
        fire(110, "UNIT_AURA", "player")
        drain(110)
        assert.equal(0, sb.set_5pc) -- read at the next trigger
        fire(111, "PLAYER_EQUIPMENT_CHANGED", 18, false)
        drain(112)
        assert.equal(1, sb.set_5pc)
        auraUp(false)
        fire(120, "UNIT_AURA", "player")
        drain(120)
        fire(121, "PLAYER_EQUIPMENT_CHANGED", 18, false)
        drain(122)
        assert.equal(0, sb.set_5pc)
        wearSet(5)
        fire(130, "PLAYER_EQUIPMENT_CHANGED", 5, false)
        drain(131)
        assert.are.same({ 5, 1 }, { sb.set, sb.set_5pc }) -- no aura: five pieces worn
    end)

    it("walks the player at the first drain after a build, so the bonus is read at +1 s", function()
        withBonus()
        build(100)
        auraUp(true) -- no UNIT_AURA: a passive aura that never changes
        ctl.now = 200
        I.Build(def, 200)
        drain(200.1)
        drain(201)
        assert.equal(1, I.nowCtx.set_bonus.set_5pc)
    end)

    it("unequipping returns every value and every <key>_<n>pc to 0", function()
        ctl.inventory[18] = ITEM
        wearSet(5)
        build(100)
        local sb = I.nowCtx.set_bonus
        assert.are.same({ 1, 1, 5, 1, 1 }, { sb.idol, sb.idol_1pc, sb.set, sb.set_1pc, sb.set_5pc })
        ctl.inventory[18] = nil
        wearSet(0)
        fire(110, "PLAYER_EQUIPMENT_CHANGED", 18, true)
        drain(111)
        assert.are.same({ 0, 0, 0 }, { sb.idol, sb.idol_1pc, sb.set })
        for n = 1, 5 do
            assert.equal(0, sb["set_" .. n .. "pc"])
        end
        assert.is_false(I.nowCtx.equipped.idol)
    end)

    it("a rebuild holds the item values at once and carries the bonus value", function()
        withBonus()
        ctl.inventory[18] = ITEM
        wearSet(3)
        auraUp(true)
        build(100)
        fire(110, "UNIT_AURA", "player")
        drain(110)
        fire(111, "PLAYER_EQUIPMENT_CHANGED", 18, false)
        drain(112)
        local sb = I.nowCtx.set_bonus
        assert.are.same({ 1, 3, 1 }, { sb.idol, sb.set, sb.set_5pc })
        ctl.now = 200
        I.Build(def, 200)
        assert.is_nil(VS.Aura("player", fs.SPENDER_A, 200)) -- the build cleared the records
        assert.are.same({ 1, 3, 1 }, { sb.idol, sb.set, sb.set_5pc })
        drain(200.1)
        drain(201)
        assert.are.same({ 1, 3, 1 }, { sb.idol, sb.set, sb.set_5pc })
    end)

    it("logs one Gear row per changed value, none for an unchanged read", function()
        build(100)
        ctl.inventory[18] = ITEM
        fire(110, "PLAYER_EQUIPMENT_CHANGED", 18, false)
        ctl.now = 111
        S.RunPolls(111)
        assert.equal(1, gearRows())
        local o = I.ObsLog.At(I.log, I.log.n)
        assert.are.same({ VS.Obs.Gear, 1, 1 }, { o.kind, o.a, o.b }) -- gear index 1 (idol), value 1
        I.Fold(111)
        I.Settle(111)
        fire(120, "PLAYER_EQUIPMENT_CHANGED", 18, false)
        ctl.now = 121
        S.RunPolls(121)
        assert.equal(0, gearRows())
    end)

    it("a raising IsEquippedItem costs the gear values only, never the build", function()
        ctl.inventory[18] = ITEM
        api.C_Item.IsEquippedItem = function()
            error("no such API")
        end
        assert.has_no.errors(function()
            I.Build(def, 100)
            drain(101)
        end)
        assert.equal("error", S.status["gear reads"])
        assert.equal(0, I.nowCtx.set_bonus.idol)
    end)

    it("a secret answer keeps the previous value", function()
        ctl.inventory[18] = ITEM
        build(100)
        assert.equal(1, I.nowCtx.set_bonus.idol)
        api.C_Item.IsEquippedItem = function()
            return fake.SECRET
        end
        ctl.inventory[18] = nil
        fire(110, "PLAYER_EQUIPMENT_CHANGED", 18, true)
        drain(111)
        assert.equal(1, I.nowCtx.set_bonus.idol)
        assert.equal("secret", S.status["gear reads"])
    end)

    it("allocates nothing per read, per lookup and per publish", function()
        withBonus()
        build(100)
        local clock, on = 200, false
        assert.equal(
            0,
            alloc.bytes(function()
                clock = clock + 2
                on = not on
                ctl.inventory[18] = on and ITEM or nil
                fire(clock, "PLAYER_EQUIPMENT_CHANGED", 18, not on)
                drain(clock + 1)
            end, 500)
        )
        local sb, eq = I.nowCtx.set_bonus, I.nowCtx.equipped
        local x
        assert.equal(
            0,
            alloc.bytes(function()
                x = sb.set_4pc
                x = eq.idol
                x = sb.nope
            end, 1000)
        )
        assert.equal(0, alloc.bytes(I.GearPublish, 1000))
    end)
end)
