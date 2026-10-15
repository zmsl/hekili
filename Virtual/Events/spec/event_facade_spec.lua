-- Virtual/Events/spec/event_facade_spec.lua (event-facade spec §2, §9): frames from the event facade's CreateFrame
-- subscribe to VirtualState's frame, the only one the fake client sees; the layer runs the sources first, then each
-- subscriber's current OnEvent with the game's payload shape (secret slots nil, UNIT_AURA's full update), filters
-- units per subscriber, never registers the combat log, and allocates nothing per event.
local load = require("Virtual.State.spec.helpers.load")
local fake = require("Virtual.State.spec.helpers.fake_api")
local alloc = require("Virtual.State.spec.helpers.alloc")

describe("the event facade", function()
    local api, ctl, ns, VS, I, E, S, saved

    -- A Hekili-like frame: its handler records (event, a1, a2) and an order stamp.
    local order
    local function subscriber(log)
        local f = E.CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event, a1, a2)
            order = order + 1
            log[#log + 1] = { event = event, a1 = a1, a2 = a2, at = order }
        end)
        return f
    end

    before_each(function()
        api, ctl = fake.new()
        saved = { CreateFrame = rawget(_G, "CreateFrame") or false, issecretvalue = rawget(_G, "issecretvalue") or false }
        _G.CreateFrame, _G.issecretvalue = api.CreateFrame, api.issecretvalue -- the client, as the game has it at load
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        E, S = I.Events, I.Sources
        order = 0
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("delivers from load, before Start, and adds the sources at Start without registering anything twice", function()
        local log = {}
        local f = subscriber(log)
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        assert.are.equal(E.frame, api.frame) -- the layer's frame exists from load
        assert.is_true(api.frame.events.PLAYER_ENTERING_WORLD)
        assert.is_nil(api.frame.events.PLAYER_SWING) -- a source event waits for Start
        assert.are.same({}, f.events) -- the subscriber is never registered with the client
        ctl.Fire("PLAYER_ENTERING_WORLD", true, false)
        assert.are.equal(1, #log) -- before Start: delivered, the sources skipped (I.api is nil)
        assert.are.equal(0, S.stN)
        VS.Start(api)
        assert.are.equal(E.frame, api.frame)
        assert.is_true(api.frame.events.PLAYER_SWING)
        assert.are.same({ "player" }, api.frame.units.UNIT_SPELLCAST_SUCCEEDED) -- the sources' player and ours: one unit
        local staged = S.stN
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        assert.are.equal(staged + 1, S.stN) -- the source ran
        assert.are.equal(0, E.errors)
    end)

    it("runs the source before the subscriber, and hands a secret slot over as nil", function()
        local sourceAt, got
        S.On("TEST_EVENT", nil, function(_, _, a1)
            order = order + 1
            sourceAt, got = order, a1
        end)
        VS.Start(api)
        local log = {}
        subscriber(log):RegisterEvent("TEST_EVENT")
        ctl.Fire("TEST_EVENT", fake.SECRET, "plain")
        assert.are.equal(1, sourceAt)
        assert.is_nil(got)
        assert.are.equal(2, log[1].at)
        assert.is_nil(log[1].a1)
        assert.are.equal("plain", log[1].a2)
    end)

    it("filters units per subscriber: the player's and the target's frame each hear their own unit once", function()
        local pl, tl = {}, {}
        subscriber(pl):RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        subscriber(tl):RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
        assert.are.same({ "player", "target" }, api.frame.units.UNIT_SPELLCAST_START)
        ctl.Fire("UNIT_SPELLCAST_START", "target", "Cast-1", 78)
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-2", 78)
        assert.are.equal(1, #pl)
        assert.are.equal("player", pl[1].a1)
        assert.are.equal(1, #tl)
        assert.are.equal("target", tl[1].a1)
    end)

    it("registers a third unit as the general event and still filters each subscriber", function()
        local a, b, c = {}, {}, {}
        subscriber(a):RegisterUnitEvent("UNIT_TARGET", "player", "target")
        subscriber(b):RegisterUnitEvent("UNIT_TARGET", "focus")
        subscriber(c):RegisterUnitEvent("UNIT_TARGET", "player")
        assert.is_true(api.frame.events.UNIT_TARGET)
        assert.is_nil(api.frame.units.UNIT_TARGET) -- general
        ctl.Fire("UNIT_TARGET", "nameplate3")
        ctl.Fire("UNIT_TARGET", "focus")
        ctl.Fire("UNIT_TARGET", "player")
        assert.are.equal(1, #a)
        assert.are.equal(1, #b)
        assert.are.equal(1, #c)
    end)

    it("hands an event with a secret unit only to general subscribers", function()
        local general, playerOnly = {}, {}
        subscriber(general):RegisterEvent("UNIT_TARGET")
        subscriber(playerOnly):RegisterUnitEvent("UNIT_TARGET", "player")
        ctl.Fire("UNIT_TARGET", fake.SECRET)
        assert.are.equal(1, #general)
        assert.is_nil(general[1].a1)
        assert.are.equal(0, #playerOnly)
    end)

    it("delivers UNIT_AURA with the layer's full update for the player and target, nil for other units", function()
        local log = {}
        subscriber(log):RegisterUnitEvent("UNIT_AURA", "player", "target")
        local other = {}
        subscriber(other):RegisterEvent("UNIT_AURA")
        ctl.Fire("UNIT_AURA", "player", fake.SECRET)
        ctl.Fire("UNIT_AURA", "nameplate2", { addedAuras = {} })
        assert.are.equal(1, #log)
        assert.is_true(log[1].a2.isFullUpdate)
        assert.are.equal(2, #other)
        assert.are.equal(log[1].a2, other[1].a2) -- the same preallocated table
        assert.is_nil(other[2].a2)
    end)

    it("stops on UnregisterEvent, dropping the client registration nobody needs, and on a cleared OnEvent", function()
        local log = {}
        local f = subscriber(log)
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        assert.is_true(f:IsEventRegistered("PLAYER_TARGET_CHANGED"))
        f:UnregisterEvent("PLAYER_TARGET_CHANGED")
        assert.is_false(f:IsEventRegistered("PLAYER_TARGET_CHANGED"))
        assert.is_nil(api.frame.events.PLAYER_TARGET_CHANGED)
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        f:SetScript("OnEvent", nil) -- ns.StopEventHandler
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.are.equal(0, #log)
    end)

    it("makes an event the client refuses a stub, never delivered", function()
        ctl.unknownEvents.NOT_AN_EVENT = true
        local log = {}
        assert.is_false(subscriber(log):RegisterEvent("NOT_AN_EVENT"))
        assert.is_true(E.STUB.NOT_AN_EVENT)
        assert.is_nil(api.frame.events.NOT_AN_EVENT)
    end)

    it("never registers the combat log with the client", function()
        local f = subscriber({})
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        VS.Start(api)
        assert.is_nil(api.frame.events.COMBAT_LOG_EVENT_UNFILTERED)
        assert.is_true(f:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
    end)

    it("delivers a client event fired from a handler in its own call, with its own payload", function()
        local outer, inner = {}, {}
        local first = E.CreateFrame("Frame")
        first:SetScript("OnEvent", function(_, event)
            if event == "OUTER" then
                ctl.Fire("INNER", "i1")
            end
        end)
        first:RegisterEvent("OUTER")
        subscriber(outer):RegisterEvent("OUTER")
        subscriber(inner):RegisterEvent("INNER")
        ctl.Fire("OUTER", "o1", "o2")
        assert.are.equal("i1", inner[1].a1)
        assert.are.equal("o1", outer[1].a1)
        assert.are.equal("o2", outer[1].a2)
        assert.is_true(inner[1].at < outer[1].at)
    end)

    it("keeps delivering after a handler raises or unregisters itself mid-delivery", function()
        local boot = E.CreateFrame("Frame")
        boot:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            error("boom")
        end)
        boot:RegisterEvent("PLAYER_LOGIN")
        local log = {}
        subscriber(log):RegisterEvent("PLAYER_LOGIN")
        ctl.Fire("PLAYER_LOGIN")
        ctl.Fire("PLAYER_LOGIN")
        assert.are.equal(2, #log)
        assert.are.equal(1, E.errors)
        assert.is_false(boot:IsEventRegistered("PLAYER_LOGIN"))
    end)

    it("starts a subscription made mid-delivery with the next event, even in a freed slot", function()
        local late = {}
        local lateFrame
        local trigger = E.CreateFrame("Frame")
        trigger:SetScript("OnEvent", function()
            if not lateFrame then
                lateFrame = subscriber(late)
                lateFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
            end
        end)
        trigger:RegisterEvent("PLAYER_TARGET_CHANGED")
        -- a freed slot after the trigger's
        local gap = subscriber({})
        gap:RegisterEvent("PLAYER_TARGET_CHANGED")
        gap:UnregisterEvent("PLAYER_TARGET_CHANGED")
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.are.equal(0, #late)
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.are.equal(1, #late)
        assert.are.equal(0, E.depth)
    end)

    it("makes an event the client declines with false a stub", function()
        api.frame.RegisterEvent = function()
            return false
        end
        assert.is_false(subscriber({}):RegisterEvent("DECLINED_EVENT"))
        assert.is_true(E.STUB.DECLINED_EVENT)
    end)

    it("re-registers on UnregisterAllEvents only the events the frame had", function()
        local a, b = subscriber({}), subscriber({})
        a:RegisterEvent("PLAYER_ENTERING_WORLD")
        b:RegisterEvent("SPELLS_CHANGED")
        local touched = {}
        local unregister = api.frame.UnregisterEvent
        api.frame.UnregisterEvent = function(self, e)
            touched[#touched + 1] = e
            unregister(self, e)
        end
        a:UnregisterAllEvents()
        assert.are.same({ "PLAYER_ENTERING_WORLD" }, touched)
        assert.is_true(api.frame.events.SPELLS_CHANGED)
    end)

    it("allocates nothing per delivered event", function()
        VS.Start(api)
        local sink = E.CreateFrame("Frame")
        sink:SetScript("OnEvent", function() end)
        sink:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        sink:RegisterUnitEvent("UNIT_AURA", "player", "target")
        sink:RegisterEvent("PLAYER_TARGET_CHANGED")
        local bytes = alloc.bytes(function(i)
            ctl.now = i
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 6673)
            ctl.Fire("UNIT_AURA", i % 2 == 0 and "player" or "target", fake.SECRET)
            ctl.Fire("PLAYER_TARGET_CHANGED")
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "target", fake.SECRET, fake.SECRET)
            S.Flush()
        end, 10000)
        assert.are.equal(0, bytes)
    end)
end)
