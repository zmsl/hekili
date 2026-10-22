-- tests/Game/State/units_spec.lua (unit-registry spec §2): the unit registry. Tokens bind to unit slots by plain GUID;
-- one outcome's fan-out (plate, target, soft) dispatches once; a cleared target's slot resolves the killing blow while
-- held and GRACE after; death events, the kill-tell fallback, eviction and the combat-end reset; the SENT pin.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

describe("the unit registry", function()
    local api, ctl, ns, VS, I, U, saved, rows, gone, mute, muted

    local function boot(unknown)
        api, ctl = fake.new()
        for _, e in ipairs(unknown or {}) do
            ctl.unknownEvents[e] = true
        end
        for k, v in pairs(saved or {}) do -- a second boot in one case puts the globals back first
            _G[k] = v or nil
        end
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        U = I.Units
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        rows, gone, mute, muted = {}, {}, false, 0
        U.OnRow(function(t, guid, uid, act, flag, amount, school)
            if mute then
                muted = muted + 1
                return -- the allocation case measures the registry, not this recorder
            end
            rows[#rows + 1] = { t = t, guid = guid, uid = uid, act = act, amount = amount, school = school }
        end)
        U.OnGone(function(uid, guid, why, t)
            gone[#gone + 1] = { uid = uid, guid = guid, why = why, t = t }
        end)
    end

    local function combat(unit, act, amount, school)
        ctl.Fire("UNIT_COMBAT", unit, act, "", amount, school)
    end

    before_each(function()
        boot()
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        saved = nil
    end)

    it("dispatches one outcome's plate, target and soft rows once, counting the duplicates", function()
        ctl.guid.nameplate1, ctl.guid.softenemy = "Creature-1", "Creature-1"
        ctl.now = 10
        combat("nameplate1", "WOUND", 14, 8)
        combat("target", "WOUND", 14, 8)
        combat("softenemy", "WOUND", 14, 8)
        assert.are.equal(1, #rows)
        assert.are.same({ "Creature-1", "WOUND", 14, 8 }, { rows[1].guid, rows[1].act, rows[1].amount, rows[1].school })
        assert.are.equal(2, U.dup)
    end)

    it("keeps two equal outcomes that share a token as two rows", function()
        ctl.now = 10
        combat("target", "WOUND", 20, 1)
        ctl.now = 10.001
        combat("target", "WOUND", 20, 1)
        assert.are.equal(2, #rows)
        assert.are.equal(0, U.dup)
    end)

    it("ignores targettarget, party and player rows", function()
        combat("targettarget", "WOUND", 5, 1)
        combat("party1", "WOUND", 5, 1)
        combat("player", "WOUND", 5, 1)
        assert.are.equal(0, #rows)
    end)

    it("resolves the killing blow after the clear to the old unit, within GRACE", function()
        ctl.now = 20
        ctl.Fire("PLAYER_TARGET_CHANGED") -- binds Creature-1 again (the same slot)
        local uid = U.Uid(1)
        ctl.guid.target = nil
        ctl.now = 20.003
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.are.equal("", U.Bound(1))
        ctl.now = 20.04
        combat("target", "WOUND", 16, 8)
        assert.are.same({ "Creature-1", uid }, { rows[1].guid, rows[1].uid })
    end)

    it("ends a released unit GRACE after its last token left: GONE, unresolvable", function()
        ctl.guid.target = nil
        ctl.now = 30
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.Tick(30.2)
        assert.are.equal(1, #gone)
        assert.are.same({ "Creature-1", U.GONE }, { gone[1].guid, gone[1].why })
        combat("target", "WOUND", 16, 8)
        assert.are.equal(0, #rows)
        assert.are.equal(1, U.unresolved)
    end)

    it("keeps a held unit resolvable past GRACE until its ticket releases it", function()
        local uid = U.Uid(1)
        U.Hold(uid)
        ctl.guid.target = nil
        ctl.now = 40
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.Tick(40.4)
        assert.are.equal(0, #gone)
        ctl.now = 40.37 + 0.1
        combat("target", "WOUND", 5, 1) -- a melee killing blow about 370 ms after the clear
        assert.are.equal(1, #rows)
        U.Release(uid, 40.5)
        ctl.Tick(40.65)
        assert.are.equal(U.GONE, gone[1].why)
    end)

    it("checks a removed plate's live GUID against its binding before unbinding", function()
        ctl.guid.nameplate2 = "Creature-7"
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        assert.are.equal("Creature-7", U.Bound(U.INDEX.nameplate2))
        ctl.guid.nameplate2 = "Creature-8" -- a missed ADDED: the removal still answers the plate's GUID
        ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
        assert.are.equal("", U.Bound(U.INDEX.nameplate2))
        assert.is_true(U.Find("Creature-8") > 0)
    end)

    it("revives a churned plate's unit in the same slot", function()
        ctl.guid.nameplate3 = "Creature-9"
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
        local uid = U.Find("Creature-9")
        ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
        ctl.Tick(ctl.now + 0.5)
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
        assert.are.equal(uid, U.Find("Creature-9"))
        assert.is_true(U.Alive(uid))
    end)

    it("marks UNIT_DIED's unit DEAD at once, PARTY_KILL's as ours, and notifies once", function()
        local uid = U.Uid(1)
        ctl.Fire("PARTY_KILL", "Player-1", "Creature-1")
        ctl.Fire("UNIT_DIED", "Creature-1")
        ctl.Fire("PLAYER_TARGET_DIED")
        assert.is_true(U.IsDead(uid) and U.Ours(uid))
        assert.are.equal(1, #gone)
        assert.are.same({ U.DEAD, 1 }, { gone[1].why, U.deaths.event })
    end)

    it("uses the FAILED-then-clear tell only when the client refused the death events", function()
        boot({ "UNIT_DIED", "PLAYER_TARGET_DIED" })
        local uid = U.Uid(1)
        ctl.now = 50
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2-0-0-0", 1)
        ctl.guid.target = nil
        ctl.now = 50.003
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.is_true(U.IsDead(uid))
        assert.are.equal(1, U.deaths.tell)
    end)

    it("does not use the tell while the death events are delivered", function()
        local uid = U.Uid(1)
        ctl.now = 50
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2-0-0-0", 1)
        ctl.guid.target = nil
        ctl.now = 50.003
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.is_false(U.IsDead(uid))
    end)

    it("reports a poll's plain death once", function()
        local uid = U.Uid(1)
        U.Dead(uid, 60)
        U.Dead(uid, 61)
        assert.are.equal(1, U.deaths.poll)
        assert.are.equal(1, #gone)
    end)

    it("evicts only a released GONE or DEAD unit when every slot is taken", function()
        for k = 1, U.UNIT_CAP do
            ctl.guid.nameplate1 = "Creature-x" .. k
            ctl.now = 100 + k
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
            ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
            ctl.Tick(ctl.now + 0.2)
        end
        assert.is_true(U.evicted >= 1)
        assert.is_true(U.Find("Creature-1") > 0) -- the target is bound: never evicted
        assert.are.equal(0, U.Find("Creature-x1")) -- the oldest released one gave way
    end)

    it("pins the target, else the soft enemy, and keeps the SENT pin by castGUID", function()
        assert.are.equal("Creature-1", U.Pin(api, 1))
        ctl.guid.target, ctl.guid.softenemy = nil, "Creature-5"
        assert.are.equal("Creature-5", U.Pin(api, 1))
        ctl.guid.target = "Creature-6"
        ctl.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-9", 1)
        ctl.guid.target = "Creature-7" -- swapped mid-cast
        assert.are.equal("Creature-6", U.Sent("Cast-9"))
        assert.is_nil(U.Sent("Cast-10"))
    end)

    it("frees every unbound unit at combat end and keeps the bound target", function()
        ctl.guid.nameplate4 = "Creature-4"
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
        ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate4")
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(0, U.Find("Creature-4"))
        assert.are.equal("Creature-1", U.Bound(1))
        assert.are.equal(U.RESET, gone[#gone].why)
    end)

    it("reads the player's GUID for the rows' source", function()
        assert.are.equal("Player-1", U.player)
        assert.are.equal("Player-1", I.Log.player)
    end)

    it("allocates nothing resolving, deduplicating and dispatching rows", function()
        ctl.guid.nameplate1 = "Creature-1"
        mute = true
        local bytes = alloc.bytes(function(i)
            ctl.now = 200 + i * 0.01
            combat("nameplate1", "WOUND", 10 + i % 7, 1)
            combat("target", "WOUND", 10 + i % 7, 1)
        end, 2000)
        assert.are.equal(0, bytes)
        -- alloc.bytes runs 200 warm-up calls, 1 regrow call and the 2000 measured: one row and one target dup each
        assert.are.same({ 2201, 2201 }, { muted, U.dup })
    end)

    it("drops a target row whose old slot was evicted and reused by another mob", function()
        ctl.guid.target = nil
        ctl.now = 30
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.Tick(30.2) -- Creature-1 is GONE and released: the oldest eviction candidate
        for k = 1, U.UNIT_CAP do
            ctl.guid.nameplate1 = "Creature-x" .. k
            ctl.now = 100 + k
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
            if k < U.UNIT_CAP then
                ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
                ctl.Tick(ctl.now + 0.2)
            end
        end
        assert.are.equal(0, U.Find("Creature-1"))
        local before = U.unresolved
        combat("target", "WOUND", 16, 8) -- live read nil: no previous slot to fall back to
        assert.are.equal(0, #rows)
        assert.are.equal(before + 1, U.unresolved)
        assert.is_false(U.IsTarget(U.Find("Creature-x" .. U.UNIT_CAP), ctl.now))
    end)

    it("leaves a row unresolved, allocating nothing, when every slot is bound or held", function()
        for k = 1, U.UNIT_CAP - 1 do -- slot 1 is the bound target
            ctl.guid.nameplate1 = "Creature-h" .. k
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
            U.Hold(U.Uid(U.INDEX.nameplate1))
            ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        end
        ctl.guid.nameplate2 = "Creature-new"
        mute = true
        local before = U.unresolved
        local bytes = alloc.bytes(function(i)
            ctl.now = 300 + i * 0.01
            combat("nameplate2", "WOUND", 10 + i % 7, 1)
        end, 2000)
        assert.are.equal(0, bytes)
        assert.are.same({ 0, 2201 }, { muted, U.unresolved - before })
    end)
end)
