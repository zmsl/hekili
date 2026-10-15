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
        assert.are.same({ 64, 63 }, { L.emitted, L.requeued }) -- the row given way is counted only as dropped
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

    describe("our swings and abilities on the target", function()
        local function row(i)
            return got[i] and got[i].row
        end

        it("pairs a swing with the target's dodge that follows it: SWING_MISSED at the swing's time", function()
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            assert.are.equal(0, #got)
            ctl.now = 10.05
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            assert.are.equal(1, #got)
            assert.are.same(
                { 10, "SWING_MISSED", false, "Player-1", "", L.PLAYER_FLAGS, 0, "Creature-1", "", L.HOSTILE_FLAGS, 0, "DODGE", false, 0, false },
                row(1)
            )
            assert.are.equal(15, got[1].n)
            assert.are.equal(10, got[1].now) -- back-dated to the swing
        end)

        it("pairs a wound that arrives before the swing: SWING_DAMAGE at the wound's time", function()
            ctl.now = 20
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 120, 1)
            ctl.now = 20.04
            ctl.Fire("PLAYER_SWING", 1.8, 1)
            assert.are.equal(21, got[1].n)
            assert.are.same({ "SWING_DAMAGE", 120, 0, 1, 0, 0, 0, true, false, false, true }, {
                row(1)[2], row(1)[12], row(1)[13], row(1)[14], row(1)[15], row(1)[16], row(1)[17],
                row(1)[18], row(1)[19], row(1)[20], row(1)[21],
            })
            assert.are.equal(20, got[1].now)
        end)

        it("emits an unpaired swing as SWING_DAMAGE 0 once its window closes, at its own time", function()
            ctl.now = 30
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Tick(30.15)
            assert.are.equal(0, #got)
            ctl.Tick(30.25)
            assert.are.equal(1, #got)
            assert.are.same({ "SWING_DAMAGE", 0, 0 }, { row(1)[2], row(1)[12], row(1)[13] })
            assert.are.equal(30, got[1].now)
        end)

        it("drops an outcome nothing of ours pairs within the window", function()
            ctl.now = 40
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            ctl.Tick(40.3)
            ctl.now = 40.35
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Tick(40.6)
            assert.are.equal(1, #got)
            assert.are.same({ "SWING_DAMAGE", 0 }, { row(1)[2], row(1)[12] })
            ctl.Fire("UNIT_COMBAT", "nameplate1", "DODGE", "", 0, 1) -- another token: not the target's outcome
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 40.65
            ctl.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 30, 1)
            assert.are.equal(1, #got)
        end)

        it("pairs our ability with the target's parry: SPELL_MISSED with the miss type in slot 15", function()
            ctl.now = 50
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", fs.REND)
            ctl.now = 50.02
            ctl.Fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1)
            assert.are.equal("SPELL_CAST_SUCCESS", row(1)[2])
            assert.are.same({ "SPELL_MISSED", fs.REND, "", 1, "PARRY", false, 0, false }, {
                row(2)[2], row(2)[12], row(2)[13], row(2)[14], row(2)[15], row(2)[16], row(2)[17], row(2)[18],
            })
            assert.are.equal(18, got[2].n)
        end)

        it("gives an on-next-swing strike its swing's outcome: SPELL_DAMAGE, no swing row", function()
            ctl.now = 60
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-10", fs.STRIKE)
            ctl.now = 60.03
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 250, 1)
            ctl.Tick(61)
            assert.are.equal(2, #got)
            assert.are.same({ "SPELL_DAMAGE", fs.STRIKE, 250, 24 }, { row(2)[2], row(2)[12], row(2)[15], got[2].n })
        end)

        it("gives the strike its swing's outcome when the success comes before the swing", function()
            ctl.now = 70
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-11", fs.STRIKE)
            ctl.now = 70.02
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 70.04
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            ctl.Tick(71)
            assert.are.equal(2, #got)
            assert.are.same({ "SPELL_MISSED", fs.STRIKE, "DODGE" }, { row(2)[2], row(2)[12], row(2)[15] })
        end)

        it("makes no row without a target", function()
            ctl.guid.target = nil
            ctl.now = 80
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Tick(81)
            assert.are.equal(0, #got)
        end)

        it("allocates nothing per paired swing", function()
            local sink = I.Events.CreateFrame("Frame")
            local GetInfo = Facade.CombatLogGetCurrentEventInfo
            sink:SetScript("OnEvent", function()
                GetInfo()
            end)
            sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            local bytes = alloc.bytes(function(i)
                ctl.now = i
                ctl.Fire("PLAYER_SWING", 2.6, 0)
                ctl.Fire("UNIT_COMBAT", "target", i % 2 == 0 and "WOUND" or "DODGE", "", 100, 1)
                ctl.Fire("PLAYER_SWING", 2.6, 1)
                ctl.Tick(i + 0.5)
                I.Sources.Flush()
            end, 10000)
            assert.are.equal(0, bytes)
        end)
    end)
end)
