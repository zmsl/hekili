-- tests/Virtual/Events/cleu_rows_spec.lua (event-facade spec §2.4, §3, §4): the synthesized combat log. Each row reaches
-- a COMBAT_LOG_EVENT_UNFILTERED subscriber after the client event that completed it, with the slot table's tuple (no
-- nil up to its last slot, so ns.callHook's rebuild keeps it whole), and with Facade.GetTime answering the row's
-- observed time while it is delivered.
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")
local alloc = require("Virtual.State.helpers.alloc")
local fs = require("Virtual.State.helpers.fake_spec")

describe("the synthesized combat log", function()
    local api, ctl, ns, VS, I, L, Facade, saved, got, order, cleu

    -- ns.callHook's rebuild (Engine/Spec.lua:1777-1789): load_args into a wiped table, then unpack( vars ).
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
            got[#got + 1] =
                { event = event, args = select("#", ...), n = n, row = vars, now = Facade.GetTime(), at = order }
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
        assert.are.same({
            10,
            "SPELL_CAST_SUCCESS",
            false,
            "Player-1",
            "",
            L.PLAYER_FLAGS,
            0,
            "Creature-1",
            "",
            L.HOSTILE_FLAGS,
            0,
            fs.REND,
            "",
            1,
        }, r.row)
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

    it("keeps delivering rows when the error handler itself raises", function()
        saved.geterrorhandler = rawget(_G, "geterrorhandler") or false
        _G.geterrorhandler = function()
            return function()
                error("handler boom")
            end
        end
        local f = I.Events.CreateFrame("Frame")
        f:SetScript("OnEvent", function()
            error("subscriber boom")
        end)
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        L.Cast("SPELL_CAST_SUCCESS", 1, fs.REND, "")
        L.Deliver()
        assert.are.equal(0, I.Events.depth)
        L.Cast("SPELL_CAST_SUCCESS", 2, fs.SHOUT, "")
        L.Deliver()
        assert.are.equal(2, #got)
        assert.are.equal(fs.SHOUT, got[2].row[12])
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

    it(
        "writes the rows credited, oracle and onus lines in Snapshot() (combat harness design §1.5, §2, §4)",
        function()
            ctl.guid.target = "Creature-1"
            ctl.unitIs.targettarget = "player"
            ctl.Fire("PLAYER_TARGET_CHANGED")
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.now = 10.47
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 40, 1)
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 12, 1)
            local snap = VS.Snapshot()
            for _, line in ipairs({
                "rows credited main=1 off=0 cast=0 background=0 avoidsBack=0 lag main=474/60 off=703/20 ref=1686/20 "
                    .. "lambda exact=0.01/0.01 avoid=0.01\n",
                "rows oracle judged=0 confirmed=0 retracted=0 soft=0 rescued=0 rescuedLate=0\n",
                "rows onus credited=1 unattributed=0 byBand=0\n",
            }) do
                assert.is_truthy(snap:find(line, 1, true), line)
            end
        end
    )

    describe("our swings and abilities on the target", function()
        local function row(i)
            return got[i] and got[i].row
        end

        it(
            "credits a swing the target's dodge at its lag: SWING_MISSED at the swing's time when its window closes",
            function()
                ctl.now = 10
                ctl.Fire("PLAYER_SWING", 2.6, 0)
                assert.are.equal(0, #got)
                ctl.now = 10.47 -- the main hand's lag (harness design §1.1: median 474 ms)
                ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
                assert.are.equal(0, #got) -- provisional: a wound of that swing could still take it
                ctl.Tick(11.55)
                assert.are.equal(1, #got)
                assert.are.same({
                    10,
                    "SWING_MISSED",
                    false,
                    "Player-1",
                    "",
                    L.PLAYER_FLAGS,
                    0,
                    "Creature-1",
                    "",
                    L.HOSTILE_FLAGS,
                    0,
                    "DODGE",
                    false,
                    0,
                    false,
                }, row(1))
                assert.are.equal(15, got[1].n)
                assert.are.equal(10, got[1].now) -- back-dated to the swing
            end
        )

        it("pairs a swing only with a wound that follows it: SWING_DAMAGE at the swing's time", function()
            ctl.now = 20
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 120, 1) -- before any swing: nobody's
            ctl.now = 20.04
            ctl.Fire("PLAYER_SWING", 1.8, 1)
            assert.are.equal(0, #got)
            ctl.now = 20.9 -- the off hand's lag (research: median 953 ms)
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 120, 1)
            assert.are.equal(21, got[1].n)
            assert.are.same({ "SWING_DAMAGE", 120, 0, 1, 0, 0, 0, true, false, false, true }, {
                row(1)[2],
                row(1)[12],
                row(1)[13],
                row(1)[14],
                row(1)[15],
                row(1)[16],
                row(1)[17],
                row(1)[18],
                row(1)[19],
                row(1)[20],
                row(1)[21],
            })
            assert.are.equal(20.04, got[1].now)
        end)

        it(
            "stages a swing paired with a wound as landed (Swing c = 1), and a CRITICAL one as a crit (c = 3)",
            function()
                local def = fs.def(fs.new(9))
                def.resources[1].swingCrit = 7
                I.Build(def, 1)
                ctl.now = 20
                ctl.Fire("PLAYER_SWING", 2.6, 0)
                ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 120, 1)
                ctl.now = 22.6
                ctl.Fire("PLAYER_SWING", 2.6, 0)
                ctl.now = 23
                ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 80, 1)
                ctl.Fire("PLAYER_SWING", 2.2, 1) -- swung, never landed: pays nothing
                ctl.Tick(25)
                I.Fold(25, false)
                assert.are.equal(9 + 7 + 9, VS.Power(fs.RAGE, 25).est)
            end
        )

        it("emits an unpaired swing as SWING_DAMAGE 0 once its window closes, at its own time", function()
            ctl.now = 30
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Tick(31.45) -- the main hand's window, 1.5 s (shorter than its 2.6 s period)
            assert.are.equal(0, #got)
            ctl.Tick(31.55)
            assert.are.equal(1, #got)
            assert.are.same({ "SWING_DAMAGE", 0, 0 }, { row(1)[2], row(1)[12], row(1)[13] })
            assert.are.equal(30, got[1].now)
        end)

        it("drops an outcome that follows nothing of ours", function()
            ctl.now = 40
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            ctl.Tick(40.3)
            ctl.now = 40.35
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Tick(41.9)
            assert.are.equal(1, #got)
            assert.are.same({ "SWING_DAMAGE", 0 }, { row(1)[2], row(1)[12] })
            ctl.Fire("UNIT_COMBAT", "nameplate1", "DODGE", "", 0, 1) -- another token: not the target's outcome
            ctl.Fire("PLAYER_SWING", 2.6, 0)
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
                row(2)[2],
                row(2)[12],
                row(2)[13],
                row(2)[14],
                row(2)[15],
                row(2)[16],
                row(2)[17],
                row(2)[18],
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

    describe("hits on us", function()
        local function onUs(unit, guid, speed)
            ctl.guid[unit] = guid
            ctl.unitIs[unit .. "target"] = "player"
            ctl.unitSpeed[unit] = speed
        end

        it("credits a dodge on us to the one hostile targeting us: SWING_MISSED from its GUID", function()
            onUs("target", "Creature-1", nil)
            ctl.Fire("PLAYER_TARGET_CHANGED")
            ctl.now = 5
            ctl.Fire("UNIT_COMBAT", "player", "DODGE", "", 0, 1)
            assert.are.same({
                5,
                "SWING_MISSED",
                false,
                "Creature-1",
                "",
                L.HOSTILE_FLAGS,
                0,
                "Player-1",
                "",
                L.PLAYER_FLAGS,
                0,
                "DODGE",
                false,
                0,
                false,
            }, got[1].row)
            assert.are.equal("readable", I.Sources.status["UnitIsUnit target-of"])
            assert.are.equal("secret", I.Sources.status["UnitAttackSpeed hostile"])
        end)

        it("emits no row when nobody is known to target us, or the answer is secret", function()
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 300, 1)
            ctl.guid.target = "Creature-1"
            ctl.unitIs.targettarget = fake.SECRET
            ctl.Fire("PLAYER_TARGET_CHANGED")
            ctl.Fire("UNIT_COMBAT", "player", "PARRY", "", 0, 1)
            assert.are.equal(0, #got)
            assert.are.equal(2, L.unattributed)
            assert.are.equal("secret", I.Sources.status["UnitIsUnit target-of"])
        end)

        it("credits each hit to the attacker whose plain swing speed predicts it, and none off both clocks", function()
            onUs("nameplate1", "Creature-A", 2.0)
            onUs("nameplate2", "Creature-B", 3.0)
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
            ctl.unitIs.nameplate2target = nil -- B not yet on us: A alone starts its clock
            ctl.Fire("UNIT_TARGET", "nameplate2")
            ctl.now = 10
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 100, 1)
            ctl.unitIs.nameplate2target = "player"
            ctl.unitIs.nameplate1target = nil
            ctl.Fire("UNIT_TARGET", "nameplate2")
            ctl.Fire("UNIT_TARGET", "nameplate1")
            ctl.now = 10.7
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 90, 1) -- B alone, no clock: B's anchor
            ctl.unitIs.nameplate1target = "player"
            ctl.Fire("UNIT_TARGET", "nameplate1")
            ctl.now = 12.05 -- A's clock: 10 + 2.0
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 80, 1)
            ctl.now = 13.65 -- B's clock: 10.7 + 3.0
            ctl.Fire("UNIT_COMBAT", "player", "BLOCK", "", 0, 1)
            ctl.now = 15.0 -- A predicts 14.05, B 16.7: off both
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 70, 1)
            assert.are.same({ "Creature-A", "Creature-B", "Creature-A", "Creature-B" }, {
                got[1].row[4],
                got[2].row[4],
                got[3].row[4],
                got[4].row[4],
            })
            assert.are.equal(4, #got)
            assert.are.equal("BLOCK", got[4].row[12])
            assert.are.equal(1, L.unattributed)
            assert.are.equal("readable", I.Sources.status["UnitAttackSpeed hostile"])
        end)

        it("follows a lone attacker whose swings shift off its clock, and forgets a removed plate", function()
            onUs("target", "Creature-1", nil)
            ctl.Fire("PLAYER_TARGET_CHANGED")
            for _, t in ipairs({ 20, 22, 24, 26.6, 28.6, 30.6 }) do -- learned 2.0, then a 0.6 s shift
                ctl.now = t
                ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1)
            end
            assert.are.equal(6, #got)
            assert.are.equal(0, L.unattributed)
            onUs("nameplate1", "Creature-2", nil) -- a second hostile: only the clock names Creature-1 now
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
            ctl.now = 32.6 -- on the new phase with the period unchanged
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1)
            ctl.now = 33.5 -- on nobody's
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1)
            assert.are.equal(7, #got)
            assert.are.equal("Creature-1", got[7].row[4])
            assert.are.equal(1, L.unattributed)
            ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1") -- the token still answers; the plate is gone
            ctl.now = 34.0 -- off the clock, but Creature-1 is alone again
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1)
            assert.are.equal(8, #got)
            assert.are.equal("Creature-1", got[8].row[4])
        end)

        it("learns an attacker's period from the gaps when its speed is secret", function()
            onUs("target", "Creature-1", nil)
            ctl.Fire("PLAYER_TARGET_CHANGED")
            for _, t in ipairs({ 20, 22, 24.02 }) do
                ctl.now = t
                ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1)
            end
            onUs("nameplate3", "Creature-2", nil) -- a second hostile joins, no clock
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
            ctl.now = 26.05
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1) -- on Creature-1's learned clock
            ctl.now = 27.0
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1) -- on nobody's
            assert.are.equal(4, #got)
            assert.are.equal("Creature-1", got[4].row[4])
            assert.are.equal(1, L.unattributed)
            ctl.Fire("PLAYER_REGEN_ENABLED") -- combat ends: anchors go, the learned period stays
            ctl.unitIs.nameplate3target = nil
            ctl.Fire("UNIT_TARGET", "nameplate3")
            ctl.now = 100
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1) -- alone again: re-anchors
            ctl.unitIs.nameplate3target = "player"
            ctl.Fire("UNIT_TARGET", "nameplate3")
            ctl.now = 102.02
            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1) -- two on us: the kept period names Creature-1
            assert.are.equal(6, #got)
            assert.are.equal("Creature-1", got[6].row[4])
        end)

        describe("per-attacker amount bands (combat harness design §4)", function()
            local function hit(t, amount, flag)
                ctl.now = t
                ctl.Fire("UNIT_COMBAT", "player", "WOUND", flag or "", amount, 1)
            end
            local function source(i)
                return got[i] and got[i].row[4]
            end
            -- A (the target) alone hits 20, 22, 24; then B (nameplate1) alone hits 60, 61, 62; then both are on us.
            local function twoBands(bAt)
                bAt = bAt or 25.9
                onUs("target", "Creature-A", nil)
                ctl.Fire("PLAYER_TARGET_CHANGED")
                hit(20, 20)
                hit(22, 22)
                hit(24, 24)
                ctl.unitIs.targettarget = nil
                ctl.Fire("UNIT_TARGET", "target")
                onUs("nameplate1", "Creature-B", nil)
                ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
                hit(bAt, 60)
                hit(bAt + 2, 61)
                hit(bAt + 4, 62)
                ctl.unitIs.targettarget = "player"
                ctl.Fire("UNIT_TARGET", "target")
            end

            it(
                "learns each attacker's band from three clean credits; a wound off both clocks goes to the band that holds it",
                function()
                    twoBands()
                    hit(31, 21) -- A's clock: 30, 32; B's: 31.9
                    hit(34.6, 63)
                    assert.are.same({ "Creature-A", "Creature-B" }, { source(7), source(8) })
                    assert.are.equal(2, L.onus.byBand)
                end
            )

            it("gives a wound inside two clocks' tolerance to the one whose band holds it", function()
                twoBands()
                hit(31.95, 59) -- A's clock (32) and B's (31.9): only B's band holds 59
                assert.are.same({ "Creature-B", 1 }, { source(7), L.onus.byBand })
            end)

            it("leaves a wound unattributed while a hostile on us has no band and no clock names it", function()
                onUs("target", "Creature-A", nil)
                onUs("nameplate1", "Creature-B", nil)
                ctl.Fire("PLAYER_TARGET_CHANGED")
                ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
                hit(20, 20)
                hit(21, 60)
                assert.are.same({ 0, 2 }, { #got, L.unattributed })
            end)

            it("credits a wound on one clock to the other whose band alone holds it", function()
                twoBands(25) -- B's clock 1 s off A's: A predicts 30, B 31
                hit(30, 61) -- A's clock only; A's band (up to 28.8) excludes 61, B's holds it
                assert.are.same({ "Creature-B", 1 }, { source(7), L.onus.byBand })
            end)

            for _, v in ipairs({
                { "a partly blocked wound", 5, "BLOCK_REDUCED" },
                { "a wound with a secret flag", 5, fake.SECRET },
                { "a wound with a secret amount", fake.SECRET, "" },
            }) do
                it("never learns a band from " .. v[1], function()
                    onUs("target", "Creature-A", nil)
                    ctl.Fire("PLAYER_TARGET_CHANGED")
                    hit(20, 20)
                    hit(22, 22)
                    hit(24, v[2], v[3]) -- the lone hostile's, on its clock: A's, but teaches nothing
                    hit(26, 24)
                    onUs("nameplate1", "Creature-B", nil)
                    ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
                    hit(27, 6) -- off A's clock; A's band [16, 28.8] excludes 6 (a learned 5 would hold it): B by elimination
                    assert.are.same({ "Creature-A", "Creature-B" }, { source(3), source(5) })
                end)
            end

            it("counts no band credit with one hostile on us (byBand: the bands chose between several)", function()
                onUs("target", "Creature-A", nil)
                ctl.Fire("PLAYER_TARGET_CHANGED")
                hit(20, 20)
                hit(22, 22)
                hit(24, 24)
                hit(25, 22) -- off A's clock (26), inside its band: the lone hostile's, not the band's
                assert.are.same({ "Creature-A", 0 }, { source(4), L.onus.byBand })
            end)

            it("never widens a band from its own credits", function()
                twoBands()
                hit(35.1, 28) -- off both clocks, inside A's band (up to 1.2 x 24 = 28.8): A's by band, not learned
                hit(37.6, 29.5) -- off both clocks (A re-anchored at 35.1), outside the band: it was not widened to 28
                assert.are.same({ "Creature-A" }, { source(7) })
                assert.are.equal(1, L.unattributed)
            end)
        end)

        it("allocates nothing per hit on us", function()
            local sink = I.Events.CreateFrame("Frame")
            local GetInfo = Facade.CombatLogGetCurrentEventInfo
            sink:SetScript("OnEvent", function()
                GetInfo()
            end)
            sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            onUs("target", "Creature-1", 2.0)
            ctl.Fire("PLAYER_TARGET_CHANGED")
            local bytes = alloc.bytes(function(i)
                ctl.now = i * 2
                ctl.Fire("UNIT_COMBAT", "player", i % 2 == 0 and "WOUND" or "PARRY", "", 40, 1)
                ctl.Fire("UNIT_TARGET", "target")
                ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
                ctl.Fire("PLAYER_FOCUS_CHANGED")
                I.Sources.Flush()
            end, 10000)
            assert.are.equal(0, bytes)
        end)
    end)
end)
