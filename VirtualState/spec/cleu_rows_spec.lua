-- VirtualState/spec/cleu_rows_spec.lua (event-facade spec §2.4, §3, §4): the synthesized combat log. Each row reaches
-- a COMBAT_LOG_EVENT_UNFILTERED subscriber after the client event that completed it, with the slot table's tuple (no
-- nil up to its last slot, so ns.callHook's rebuild keeps it whole), and with Facade.GetTime answering the row's
-- observed time while it is delivered.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local alloc = require("VirtualState.spec.helpers.alloc")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("the synthesized combat log", function()
    local api, ctl, ns, VS, I, L, Facade, saved, got, order, cleu

    -- ns.callHook's rebuild (Classes.lua:2858-2877): load_args into a wiped table, then unpack( vars ).
    local function viaCallHook(...)
        local vars = {}
        for i = 1, select("#", ...) do
            vars[i] = select(i, ...)
        end
        return #vars, vars
    end

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I, Facade = ns.VirtualState, ns.VirtualStateInternal, ns.Facade
        L = I.Log
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        got, order = {}, 0
        cleu = I.Events.CreateFrame("Frame") -- CLEU_HANDLER's registration (Events.lua)
        cleu:SetScript("OnEvent", function(_, event, ...)
            order = order + 1
            local n, vars = viaCallHook(Facade.CombatLogGetCurrentEventInfo())
            got[#got + 1] = { event = event, args = select("#", ...), n = n, row = vars, now = Facade.GetTime(), at = order }
        end)
        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("emits SPELL_CAST_SUCCESS after the cast event's subscribers, in the client's shape", function()
        local seen
        local f = I.Events.CreateFrame("Frame")
        f:SetScript("OnEvent", function()
            order = order + 1
            seen = order
        end)
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
        assert.are.equal(1, #got)
        local r = got[1]
        assert.are.equal("COMBAT_LOG_EVENT_UNFILTERED", r.event)
        assert.are.equal(0, r.args) -- no payload, as the client delivers it
        assert.are.equal(14, r.n) -- no nil up to the last slot
        assert.are.same(
            { 10, "SPELL_CAST_SUCCESS", false, "Player-1", "", L.PLAYER_FLAGS, 0, "Creature-1", "", L.HOSTILE_FLAGS, 0, fs.REND, "", 1 },
            r.row
        )
        assert.is_true(seen < r.at)
        assert.is_nil(Facade.CombatLogGetCurrentEventInfo()) -- nothing outside a delivery
    end)

    it("emits SPELL_CAST_START with an empty target when the sent GUID is unknown, reading no GUID", function()
        local calls, unitGUID = 0, api.UnitGUID
        api.UnitGUID = function(unit)
            calls = calls + 1
            return unitGUID(unit)
        end
        I.sentGUID = nil
        ctl.casting = { 50000, 51500 }
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-7", fs.REND)
        api.UnitGUID = unitGUID
        assert.are.equal(0, calls)
        assert.are.equal("SPELL_CAST_START", got[1].row[2])
        assert.are.equal("", got[1].row[8])
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-7", fs.REND)
        assert.are.same({ "SPELL_CAST_FAILED", 15, "" }, { got[2].row[2], got[2].n, got[2].row[15] })
    end)

    it("ends a channel with its SPELL_AURA_REMOVED on us", function()
        ctl.channel = { 20000, 23000 }
        ctl.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4", fs.REND)
        assert.are.equal(0, #got) -- its success row comes from UNIT_SPELLCAST_SUCCEEDED
        ctl.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-4", fs.REND)
        assert.are.same({ "SPELL_AURA_REMOVED", "Player-1", 16, "BUFF", 0 }, {
            got[1].row[2],
            got[1].row[8],
            got[1].n,
            got[1].row[15],
            got[1].row[16],
        })
    end)

    it("answers a back-dated row's time from Facade.GetTime while it is delivered, the clock after", function()
        local r = L.Emit("SWING_DAMAGE", 21, 7.25, true, "swing", "observed", "Player-1", 1, "Creature-1", 2)
        for k = 12, 21 do
            r[k] = 0
        end
        ctl.now = 7.4
        L.Deliver()
        assert.are.equal(7.25, got[1].now)
        assert.are.equal(7.4, Facade.GetTime())
        L.Emit("SPELL_CAST_SUCCESS", 14, 7.3, false, "cast", "modelled", "Player-1", 1, "", 1)
        L.Deliver()
        assert.are.equal(7.4, got[2].now) -- a purely modelled row is stamped at delivery
    end)

    it("delivers a row emitted during a delivery after the current one, never nested, and counts it", function()
        local depth, maxDepth = 0, 0
        local f = I.Events.CreateFrame("Frame")
        f:SetScript("OnEvent", function()
            depth = depth + 1
            maxDepth = math.max(maxDepth, depth)
            if #got == 1 then
                L.Cast("SPELL_CAST_SUCCESS", 2, fs.SHOUT, "")
            end
            depth = depth - 1
        end)
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        L.Cast("SPELL_CAST_SUCCESS", 1, fs.REND, "")
        L.Deliver()
        assert.are.equal(2, #got)
        assert.are.equal(fs.SHOUT, got[2].row[12])
        assert.are.equal(1, maxDepth)
        assert.are.equal(1, L.requeued)
    end)

    it("drops the oldest row when the pool is full, and counts it", function()
        for i = 1, L.POOL + 6 do
            L.Cast("SPELL_CAST_SUCCESS", i, fs.REND, "")
        end
        L.Deliver()
        assert.are.equal(L.POOL, #got)
        assert.are.equal(7, got[1].row[1])
        assert.are.equal(6, L.dropped)
    end)

    it("keeps the row being delivered intact when the pool fills during its delivery", function()
        local seen
        local f = I.Events.CreateFrame("Frame")
        f:SetScript("OnEvent", function()
            if not seen then
                seen = "pending"
                for i = 1, L.POOL do
                    L.Cast("SPELL_CAST_SUCCESS", 100 + i, fs.SHOUT, "")
                end
                seen = select(12, Facade.CombatLogGetCurrentEventInfo())
            end
        end)
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        L.Cast("SPELL_CAST_SUCCESS", 1, fs.REND, "")
        L.Deliver()
        assert.are.equal(fs.REND, seen)
        assert.are.equal(1, L.dropped) -- 64 emitted into 63 free slots: the last one gave way
    end)

    it("makes no row without a spell ID, and delivers nothing inside a coroutine", function()
        L.Cast("SPELL_CAST_SUCCESS", 1, nil, "")
        assert.are.equal(0, L.emitted)
        L.Cast("SPELL_CAST_SUCCESS", 2, fs.REND, "")
        coroutine.wrap(L.Deliver)() -- Hekili.Update's coroutine
        assert.are.equal(0, #got)
        L.Deliver()
        assert.are.equal(1, #got)
    end)

    it("allocates nothing per row emitted and delivered", function()
        local sink = I.Events.CreateFrame("Frame")
        local GetInfo = Facade.CombatLogGetCurrentEventInfo
        sink:SetScript("OnEvent", function()
            GetInfo()
        end)
        sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- the capturing one allocates by design
        local bytes = alloc.bytes(function(i)
            ctl.now = i
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
            I.Sources.Flush()
        end, 10000)
        assert.are.equal(0, bytes)
    end)
end)
