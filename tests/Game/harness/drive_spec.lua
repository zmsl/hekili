-- tests/Game/harness/drive_spec.lua (unit-registry plan, Task 10b): the drive's per-row ticket captures (payAt,
-- payKind) through I.Tickets.onPay, on a scenario's stream.
local drive = require("Game.harness.drive")
local scenarios = require("Game.harness.scenarios")
local fs = require("Game.State.helpers.fake_spec")

describe("the drive's ticket captures", function()
    it("records the paid swing ticket's anchor and kind on a white wound's row", function()
        local s = scenarios.stream({ duration = 10 }, 3)
        local c = drive.boot()
        drive.run(c, s)
        drive.restore(c)
        local X, n = c.I.Expect, 0
        for i = 1, s.n do
            if c.crHand[i] > 0 and c.payKind[i] == X.MELEE then
                n = n + 1
                assert.are.equal(c.crAt[i], c.payAt[i]) -- the credited swing is the ticket's anchor
            end
        end
        assert.is_true(n > 0)
    end)

    it("lands a bolt at its success + distance / 20 and pays a FLIGHT ticket anchored at that success", function()
        local s = scenarios.stream({ duration = 6, noMelee = true, spells = { { 2, "bolt" } }, distance = 30 }, 3)
        local c = drive.boot({
            boot = function(c)
                c.ctl.ranges[fs.SPENDER_P] = { 0, 30 } -- the bolt's max range sets its flight window (default 5: melee)
                c.I.Build(fs.def(fs.new(9, nil, nil, true)), 0.1)
                c.VS.Start(c.api)
            end,
        })
        drive.run(c, s)
        drive.restore(c)
        local success, row
        for i = 1, s.n do
            if s.ev[i] == "UNIT_SPELLCAST_SUCCEEDED" and s.a1[i] == "player" and s.a3[i] == fs.SPENDER_P then
                success = s.t[i]
            elseif s.ev[i] == "UNIT_COMBAT" and s.a1[i] == "target" and s.a5[i] == 8 then
                row = i
            end
        end
        assert.is_truthy(success and row)
        assert.is_true(math.abs(s.t[row] - (success + 30 / 20)) < 1e-6, "landed at " .. s.t[row] - success)
        assert.are.equal(c.I.Expect.FLIGHT, c.payKind[row])
        assert.are.equal(success, c.payAt[row])
    end)

    it("two boots in one process share no state: a Build through the first leaves the second unbuilt", function()
        local load = require("Game.State.helpers.load")
        local ns1, ns2 = load.module(), load.module()
        assert.are_not.equal(ns1, ns2)
        assert.are_not.equal(ns1.VirtualState, ns2.VirtualState)
        assert.are_not.equal(ns1.VirtualStateInternal, ns2.VirtualStateInternal)
        local I1, I2 = ns1.VirtualStateInternal, ns2.VirtualStateInternal
        local def = fs.def(fs.new(9))
        local clock2 = I2.clock
        I1.Build(def, 5)
        assert.is_true(I1.built)
        assert.are.equal(def, I1.def)
        assert.are.equal(5, I1.clock)
        assert.is_falsy(I2.built) -- the second boot saw none of it
        assert.is_nil(I2.def)
        assert.are.equal(clock2, I2.clock)
        assert.are_not.equal(5, clock2)
        local n = 0
        for _, pair in ipairs({ { ns1, ns2 }, { ns2, ns1 } }) do
            for k, fn in pairs(pair[1].VirtualState) do
                if type(fn) == "function" then
                    assert.are.equal(_G, getfenv(fn))
                    assert.are_not.equal(pair[2].VirtualState[k], fn) -- its own closure, so its own upvalues
                    n = n + 1
                end
            end
        end
        assert.is_true(n > 0)
    end)

    -- CDM Task 8 (decision 110): the viewer ops the loops' layouts drive
    describe("the Cooldown Manager ops", function()
        local fake = require("Game.State.helpers.fake_api")
        local ESS, ICON, BAR = fake.VIEWERS[1], fake.VIEWERS[3], fake.VIEWERS[4]
        local ctl
        before_each(function()
            local _
            _, ctl = fake.new()
            ctl.viewer.infos[501] = { spellID = 77 } -- a cooldown entry (Essential) of the aura's spell
            ctl.viewer.infos[502] = { spellID = 9, linkedSpellIDs = { 77 } } -- a buff entry linking it
            ctl.viewer.infos[503] = { spellID = 9078 } -- another aura's
        end)

        it(
            "@viewer lights every item in any viewer naming the spell, cooldown entries included, our auras only",
            function()
                local e = ctl.ViewerItem(ESS, 1, 501)
                local b = ctl.ViewerItem(ICON, 1, 502)
                local o = ctl.ViewerItem(BAR, 1, 503)
                drive.op({}, ctl, "@viewer", "target", 77, true, "party1") -- a partner's copy (CDM-P): nothing lights
                assert.are.same({ nil, nil, nil }, { e.auraInstanceID, b.auraInstanceID, o.auraInstanceID })
                drive.op({}, ctl, "@viewer", "target", 77, true, "player")
                assert.are.same(
                    { fake.SECRET, fake.SECRET, nil },
                    { e.auraInstanceID, b.auraInstanceID, o.auraInstanceID }
                )
                assert.are.same({ "target", "target" }, { e.auraDataUnit, b.auraDataUnit })
                drive.op({}, ctl, "@viewer", "target", 77, false, "player")
                assert.are.same({ nil, nil }, { e.auraInstanceID, b.auraInstanceID })
                drive.op({}, ctl, "@viewer", "player", 9078, true) -- no source: ours (the observer's older streams)
                assert.are.equal(fake.SECRET, o.auraInstanceID)
            end
        )

        it("@viewerLayout acquires (also in combat), releases, re-acquires the released frame, re-points", function()
            ctl.combat = true
            drive.op({}, ctl, "@viewer", "player", 77, true, "player")
            drive.op({}, ctl, "@viewerLayout", "acquire", ICON, 502)
            local item = ctl.viewer.items[ICON][1]
            assert.are.same({ 502, fake.SECRET }, { item.cooldownID, item.auraInstanceID }) -- lit at once (F13)
            drive.op({}, ctl, "@viewerLayout", "release", ICON, 502)
            assert.are.same({ nil, nil, 1 }, { item.cooldownID, item.auraInstanceID, #ctl.viewer.items[ICON] })
            drive.op({}, ctl, "@viewerLayout", "acquire", ICON, 502)
            assert.are.equal(item, ctl.viewer.items[ICON][1]) -- the pool's frame, no new child
            assert.are.same({ 1, 502, fake.SECRET }, { #ctl.viewer.items[ICON], item.cooldownID, item.auraInstanceID })
            drive.op({}, ctl, "@viewerLayout", "repoint", ICON, 502, 503)
            assert.are.same({ 503, nil }, { item.cooldownID, item.auraInstanceID }) -- 503 names no aura that is up
            drive.op({}, ctl, "@viewerLayout", "repoint", ICON, 503, 502)
            assert.are.same({ 502 }, { item.cooldownID })
        end)

        it("@viewerRetarget clears the items held for the target (our target changed)", function()
            local e = ctl.ViewerItem(ESS, 1, 501)
            drive.op({}, ctl, "@viewer", "target", 77, true, "player")
            drive.op({}, ctl, "@viewerRetarget")
            assert.is_nil(e.auraInstanceID)
        end)

        it("@viewerShown hides a viewer, or every viewer through the parent (name nil)", function()
            drive.op({}, ctl, "@viewerShown", ESS, false)
            assert.are.same({ false, true }, { ctl.viewer.shown[ESS] == nil, ctl.viewer.shown[ICON] == nil })
            drive.op({}, ctl, "@viewerShown", ESS, true)
            assert.is_nil(ctl.viewer.shown[ESS])
            drive.op({}, ctl, "@viewerShown", nil, false)
            assert.is_false(ctl.viewer.parentShown)
            drive.op({}, ctl, "@viewerShown", nil, true)
            assert.is_true(ctl.viewer.parentShown)
        end)
    end)
end)
