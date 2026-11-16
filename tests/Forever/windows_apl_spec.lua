-- tests/Forever/windows_apl_spec.lua (windows design v6 Phase 2, free-form windows): the compiler of the reserved
-- `windows` list (E1-E7 for windows, keys per display, records for the belief), the lines as commands (the per-slot
-- fired mark, the restart with no cap, operations sent from slot 1 at now only) and the core's forecast of an OPEN
-- against the oracle M.apply (tests/Game/State/helpers/windows_matrix.lua). Headless Arms with a test priority.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local mx = require("Game.State.helpers.windows_matrix")
local fake = require("Game.State.helpers.fake_api")

local OPEN, CLOSE = mx.OP.OPEN, mx.OP.CLOSE
local DISPLAYS = { "Primary", "AOE", "Cooldowns", "Interrupts", "Defensives" }

local H, S, VS, VSI, ops, t
local flags = {}
local flaps = 0 -- the one-time flapping-pair warnings seen (L1205), taken out of H.errors by tick()
local FLAP = "opened and closed by lines in the same recommendation"

-- Boots Arms, registers the Lua windows `lua` (name -> RegisterWindow data) and the test flags (state expressions
-- reading `flags`), targets a mob and records every WindowOp the core sends.
local function boot(lua)
    H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    local kit = H.Hekili.Class.kit
    for name, data in pairs(lua or {}) do
        kit:RegisterWindow(name, data)
    end
    for _, f in ipairs({ "fa", "fb" }) do
        flags[f] = false
        kit:RegisterStateExpr("test_" .. f, function()
            return flags[f]
        end)
    end
    kit:RegisterStateExpr("test_swing_remains", function()
        local v = 1.2 - (query_time - now) -- luacheck: ignore 113 (state's fields: the expression runs under state)
        return v > 0 and v or 0
    end)
    H.Hekili:SpecializationChanged()
    S, VS, VSI = H.Hekili.State, H.ns.VirtualState, H.ns.VirtualStateInternal
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    t = H.ctl.now + 0.2
    assert(headless.cycle(H, t))
    ops = {}
    local op = VS.WindowOp
    VS.WindowOp = function(key, code, arg)
        ops[#ops + 1] = { key, code }
        return op(key, code, arg)
    end
end

local function parse(text)
    local lines, warnings = H.Hekili:ParseActionList(text, true)
    assert.are.same({}, warnings or {})
    for _, l in ipairs(lines) do
        l.enabled = true
    end
    return lines
end

-- The pack's lists from simc text by list name; loads the scripts and enters combat.
local function load(lists)
    local out = { precombat = {} }
    for name, text in pairs(lists) do
        out[name] = parse(text)
    end
    H.Hekili.DB.profile.packs[ww.PACK].lists = out
    H.Hekili:LoadScripts()
    H.Hekili:ReviewPacks() -- the lists and entries the walk may run (UI.lua), as an edit in the options does
    -- the edit applied out of combat (§9): the belief builds the new rows at a Drain out of combat; in combat they
    -- would wait for combat end (L01)
    H.Hekili.Scripts:ApplyWindows(ww.PACK)
    S:BuildWindows()
    VS.Drain(H.ctl.now)
    H.Fire("PLAYER_REGEN_DISABLED")
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
end

-- One update 0.2 s on; returns Primary's records and the operations it sent (in order, as { key, op }).
local function tick()
    ops = {}
    t = t + 0.2
    assert(headless.cycle(H, t))
    for i = #H.errors, 1, -1 do
        if H.errors[i]:find(FLAP, 1, true) then
            flaps = flaps + 1
            table.remove(H.errors, i)
        end
    end
    assert.are.same({}, H.errors)
    return H.Hekili.Engine.Output.Primary.recs, ops
end

local function key(name, display)
    return ww.PACK .. ":" .. name .. "#" .. (display or "Primary")
end

local function belief(name)
    local up, openedAt, expiresAt, refreshes, step = VS.Window(key(name))
    return { up = up, openedAt = openedAt, expiresAt = expiresAt, refreshes = refreshes, step = step }
end

describe("the windows compiler (windows design v6 §3.4, §9)", function()
    before_each(function()
        boot({ luaw = { duration = 6 } })
    end)

    local function check(lists)
        local out = {}
        for name, text in pairs(lists) do
            out[name] = parse(text)
        end
        return H.Hekili.Scripts.CheckWindows(out, "pk"), out
    end

    local function codes(cw)
        local c = {}
        for _, e in ipairs(cw.errors) do
            c[#c + 1] = e.code .. " " .. e.list .. ":" .. e.line
        end
        return c
    end

    it(
        "C09: two declared windows give ten keys, each <pack>:<name>#<display>, with a positive duration or combat",
        function()
            local cw = check({
                windows = "actions+=/window,name=burst,duration=12\nactions+=/window,name=pool,duration=combat,refresh=1,max_refresh=2,max_duration=15",
                default = "actions+=/open_window,name=burst\nactions+=/close_window,name=pool,if=test_fa",
            })
            assert.are.same({}, codes(cw))
            assert.are.equal(10, #cw.records)
            local seen = {}
            for _, r in ipairs(cw.records) do
                seen[r.key] = r
                assert.is_true(r.duration == "combat" or type(r.duration) == "number" and r.duration > 0, r.key)
            end
            for _, d in ipairs(DISPLAYS) do
                assert.are.same({ key = "pk:burst#" .. d, duration = 12 }, seen["pk:burst#" .. d])
                assert.are.same(
                    { key = "pk:pool#" .. d, duration = "combat", refresh = true, max_refresh = 2, max_duration = 15 },
                    seen["pk:pool#" .. d]
                )
            end
            assert.are.equal(10, cw.cap) -- two window lines, five displays (§5.5)
        end
    )

    it("C08: a priority with no windows list and no window line declares nothing", function()
        local cw = check({ default = "actions+=/berserker_stance" })
        assert.are.same({}, codes(cw))
        assert.are.same({}, cw.records)
        assert.are.equal(0, cw.cap)
    end)

    it("C01: an undeclared window is E1; a class (Lua) window is accepted on a line", function()
        local cw = check({
            default = "actions+=/open_window,name=x\nactions+=/open_window,name=luaw\nactions+=/berserker_stance",
        })
        assert.are.same({ "E1 default:1" }, codes(cw))
    end)

    it("C02: a name declared twice is E2 on the second", function()
        local cw = check({ windows = "actions+=/window,name=x,duration=3\nactions+=/window,name=x,duration=4" })
        assert.are.same({ "E2 windows:2" }, codes(cw))
        assert.are.equal(5, #cw.records)
    end)

    it("C04: a declared name a class registers in Lua is E3", function()
        local cw = check({ windows = "actions+=/window,name=luaw,duration=3" })
        assert.are.same({ "E3 windows:1" }, codes(cw))
        assert.are.same({}, cw.records)
    end)

    it("C05/P26/P27: anything but name= and if= on a window line is E4, for a list window and a Lua window", function()
        local cw = check({
            windows = "actions+=/window,name=x,duration=3",
            default = "actions+=/open_window,name=x,duration=3\nactions+=/open_window,name=luaw,duration=3,if=test_fa\n"
                .. "actions+=/open_window,name=x,refresh=1\nactions+=/close_window,name=x,duration=1\nactions+=/open_window,name=luaw,if=test_fa",
        })
        assert.are.same({ "E4 default:1", "E4 default:2", "E4 default:3", "E4 default:4" }, codes(cw))
        assert.are.equal(0, cw.cap) -- error lines are disabled; the Lua window's line sends nothing
    end)

    it(
        "C06/C11: window entries outside the list, other entries inside it, a call of it and if= on an entry are E5",
        function()
            local cw = check({
                windows = "actions+=/berserker_stance\nactions+=/window,name=z,duration=3,if=test_fa",
                default = "actions+=/window,name=y,duration=3\nactions+=/call_action_list,name=windows\nactions+=/run_action_list,name=windows",
            })
            -- the `windows` list is read first ("before use", §3.1), then the other lists by name
            assert.are.same(
                { "E5 windows:1", "E5 windows:2", "E5 default:1", "E5 default:2", "E5 default:3" },
                codes(cw)
            )
        end
    )

    it("C07: a missing or non-positive duration and bad caps are E6", function()
        local cw = check({
            windows = "actions+=/window,name=a\nactions+=/window,name=b,duration=0\nactions+=/window,name=c,duration=3,max_refresh=-1\n"
                .. "actions+=/window,name=d,duration=3,max_duration=0\nactions+=/window,name=e,duration=3,refresh=2\nactions+=/window,duration=3",
        })
        assert.are.same(
            { "E6 windows:1", "E6 windows:2", "E6 windows:3", "E6 windows:4", "E6 windows:5", "E6 windows:6" },
            codes(cw)
        )
    end)

    it("E7: an option a window entry does not take", function()
        local cw = check({
            windows = "actions+=/window,name=a,duration=3,close_on_false=1\nactions+=/window,name=b,duration=3,target_change=end",
        })
        assert.are.same({ "E7 windows:1", "E7 windows:2" }, codes(cw))
    end)

    it("disables a line with an error when the scripts load and lists it once", function()
        load({ default = "actions+=/open_window,name=nope\nactions+=/berserker_stance" })
        local script = H.Hekili.Scripts.DB[ww.PACK .. ":default:1"]
        assert.is_truthy(script.Error and script.Error:find("E1", 1, true))
        local function reported() -- the window compile errors reported (the harness keeps Error's format string)
            local n = 0
            for _, e in ipairs(H.errors) do
                n = n + (e:find("the line is skipped", 1, true) and 1 or 0)
            end
            return n
        end
        assert.are.equal(1, reported())
        H.Hekili:LoadScripts() -- an options edit loads the scripts again: marked again, not reported again (M3)
        assert.is_truthy(H.Hekili.Scripts.DB[ww.PACK .. ":default:1"].Error)
        assert.are.equal(1, reported())
        -- a CHANGED error on the same line is a new report
        local lists = H.Hekili.DB.profile.packs[ww.PACK].lists
        lists.default = parse("actions+=/open_window,name=x,duration=3\nactions+=/berserker_stance")
        H.Hekili:LoadScripts()
        assert.are.equal(2, reported())
        for k in pairs(H.errors) do
            H.errors[k] = nil
        end
        local recs, sent = tick()
        assert.are.equal("berserker_stance", recs[1].actionName)
        assert.are.same({}, sent)
    end)

    it("a window another priority declares reads closed, done included (M4)", function()
        H.Hekili.Scripts.declaredWindows.other = true
        local w = S.window.other
        assert.is_false(w.up)
        assert.is_true(w.down)
        assert.is_false(w.done)
        assert.are.equal(0, w.remains)
        H.Hekili.Scripts.declaredWindows.other = nil
    end)

    it("C10: every shipped pack compiles with no window error", function()
        for name, pack in pairs(H.Hekili.DB.profile.packs) do
            local cw = H.Hekili.Scripts.CheckWindows(pack.lists or {}, name)
            assert.are.same({}, codes(cw), name)
        end
    end)

    it("an import keeps a list-declared window's lines and warns E1 for an undeclared one", function()
        local out, warnings = H.Hekili:ImportSimcAPL(
            "t",
            "t",
            "actions.windows=window,name=x,duration=6\nactions=open_window,name=x\nactions+=/open_window,name=y\nactions+=/berserker_stance"
        )
        assert.are.equal(1, #out.windows)
        assert.are.equal("x", out.windows[1].window_name)
        assert.is_true(out.default[1].enabled)
        assert.is_false(out.default[2].enabled)
        assert.is_truthy(warnings:find("E1", 1, true))
        assert.is_falsy(warnings:find("Unknown window 'x'", 1, true))
    end)
end)

describe("APL window lines as commands (windows design v6 §4, §5)", function()
    before_each(function()
        boot({ luaw = { duration = 6 } })
    end)

    it("writes the active pack's records into the belief's def and seeds each display from its own key", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x\nactions+=/berserker_stance",
        })
        local _, sent = tick()
        assert.are.same({ { key("x"), OPEN } }, sent)
        assert.is_false(belief("x").up) -- sent by this pass, replayed at the next Drain
        tick()
        local def = VSI.def
        assert.are.equal(5, #def.aplWindows)
        assert.are.equal(5, def.aplOpCap)
        assert.are.equal(key("x"), def.aplWindows[1].key)
        assert.is_true(belief("x").up)
        assert.is_false((VS.Window(key("x", "AOE")))) -- AOE was not walked: its key stays closed
    end)

    it(
        "W09/R10: open on top and close at the bottom send OPEN then CLOSE; two restarts in slot 1 and in slot 2",
        function()
            load({
                windows = "actions+=/window,name=x,duration=6",
                default = "actions+=/open_window,name=x\nactions+=/close_window,name=x\nactions+=/berserker_stance",
            })
            for _ = 1, 3 do
                local recs, sent = tick()
                assert.are.same({ { key("x"), OPEN }, { key("x"), CLOSE } }, sent)
                assert.are.equal("berserker_stance", recs[1].actionName)
                assert.are.equal(2, recs[1].restarts)
                assert.are.equal(2, recs[2].restarts)
                assert.is_false(belief("x").up) -- the previous pass's pair, replayed: closed
            end
        end
    )

    it("W12: a ready pick between the lines ends the pass with the window open; only OPEN is sent", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x\nactions+=/bloodrage\nactions+=/close_window,name=x\nactions+=/berserker_stance",
        })
        local recs, sent = tick()
        assert.are.same({ { key("x"), OPEN } }, sent)
        assert.are.equal("bloodrage", recs[1].actionName)
        assert.are.equal(1, recs[1].restarts)
        tick()
        assert.is_true(belief("x").up)
    end)

    it("R02/held: a held-true open on an open window causes no restart and no operation", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x\nactions+=/bloodrage,if=window.x.up",
        })
        local recs, sent = tick()
        assert.are.same({ { key("x"), OPEN } }, sent)
        assert.are.equal(1, recs[1].restarts)
        assert.are.equal("bloodrage", recs[1].actionName)
        recs, sent = tick()
        assert.are.same({}, sent)
        assert.are.equal(0, recs[1].restarts)
        assert.are.equal("bloodrage", recs[1].actionName)
    end)

    it("R03: a chain of three windows restarts three times and sends three OPENs in chain order", function()
        load({
            windows = "actions+=/window,name=a,duration=6\nactions+=/window,name=b,duration=6\nactions+=/window,name=c,duration=6",
            default = "actions+=/open_window,name=c,if=window.b.up\nactions+=/open_window,name=b,if=window.a.up\n"
                .. "actions+=/open_window,name=a\nactions+=/berserker_stance",
        })
        local recs, sent = tick()
        assert.are.same({ { key("a"), OPEN }, { key("b"), OPEN }, { key("c"), OPEN } }, sent)
        assert.are.equal(3, recs[1].restarts)
    end)

    it("R05: a restart unwinds a called list; the reader above the call sees the window", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/bloodrage,if=window.x.up\nactions+=/call_action_list,name=sub\nactions+=/berserker_stance",
            sub = "actions+=/open_window,name=x",
        })
        local recs, sent = tick()
        assert.are.same({ { key("x"), OPEN } }, sent)
        assert.are.equal("bloodrage", recs[1].actionName)
        assert.are.equal(1, recs[1].restarts)
    end)

    -- forecast == apply (L1180-L1182): the core sends an OPEN exactly when its forecast changes the copy, and the
    -- belief's apply of what was sent equals the oracle over the previous belief state (OP5 excluded: no expiry here)
    local function refreshRun(decl, n)
        load({
            windows = "actions+=/window,name=x," .. decl,
            default = "actions+=/open_window,name=x\nactions+=/berserker_stance",
        })
        local rec = {}
        for k, v in decl:gmatch("([%w_]+)=([%w_]+)") do
            rec[k] = tonumber(v) or v
        end
        rec.refresh = rec.refresh == 1 or nil
        local _, sent = tick()
        local sends = { #sent }
        for _ = 2, n do
            -- this pass's operations, stamped at this Drain's cut-off, meet the belief's state there at the next Drain
            local want, T, prev = belief("x"), VSI.clock, sent
            _, sent = tick()
            sends[#sends + 1] = #sent
            for _, o in ipairs(prev) do
                mx.apply(want, o[2], nil, rec, T)
            end
            if want.up and want.expiresAt <= VSI.clock then
                want = mx.CLOSED
            end
            local got = belief("x")
            for _, f in ipairs({ "up", "openedAt", "expiresAt", "refreshes" }) do
                local a, b = want[f], got[f]
                assert.is_true(a == b or type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6, f)
            end
        end
        return sends
    end

    it(
        "W05/R09: a held-true open on a refresh=1 window refreshes every pass until max_refresh, then sends nothing",
        function()
            local sends = refreshRun("duration=3,refresh=1,max_refresh=2", 6)
            -- the first pass opens, two refreshes, then refused: nothing sent (the belief's last OPEN is the 3rd)
            assert.are.same({ 1, 1, 1, 0, 0, 0 }, sends)
            assert.are.equal(2, belief("x").refreshes)
        end
    )

    it("W06: at the max_duration cap the refresh is refused and nothing is sent", function()
        local sends = refreshRun("duration=3,refresh=1,max_duration=4", 9)
        -- opened, then a refresh per pass until the expiry sits at openedAt + 4 (APL rows refuse there, L1182)
        assert.are.same({ 1, 1, 1, 1, 1, 1, 0, 0, 0 }, sends)
    end)

    it("W07: a combat window is never refreshed", function()
        local sends = refreshRun("duration=combat,refresh=1", 3)
        assert.are.same({ 1, 0, 0 }, sends)
    end)

    it("W13: an open line true only at a recheck time opens the copy then, sends nothing", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x,if=test_swing_remains<0.5\nactions+=/bloodrage,if=window.x.up",
        })
        local recs, sent = tick()
        assert.are.same({}, sent)
        assert.are.equal("bloodrage", recs[1].actionName)
        assert.is_true(recs[1].wait > 0.5)
        tick()
        assert.is_false(belief("x").up)
    end)

    it(
        "W16/P26: a line on a Lua window changes the copy only: one restart, nothing sent, the belief untouched",
        function()
            load({
                default = "actions+=/open_window,name=luaw\nactions+=/bloodrage,if=window.luaw.up\nactions+=/berserker_stance",
            })
            local recs, sent = tick()
            assert.are.same({}, sent)
            assert.are.equal("bloodrage", recs[1].actionName)
            assert.are.equal(1, recs[1].restarts)
            assert.is_false((VS.Window("luaw")))
        end
    )

    it("a pack switch writes the new pack's records (none) under a new generation", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x\nactions+=/berserker_stance",
        })
        tick()
        local gen = VSI.def.aplGen
        load({ default = "actions+=/berserker_stance" })
        tick()
        assert.are.same({}, VSI.def.aplWindows)
        assert.are.equal(0, VSI.def.aplOpCap)
        assert.are_not.equal(gen, VSI.def.aplGen)
    end)

    it("L03: a spec change builds the belief from the active pack's records", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x\nactions+=/berserker_stance",
        })
        tick()
        H.Hekili:SpecializationChanged()
        assert.are.equal(key("x"), VSI.def.aplWindows[1].key)
        local recs, sent = tick()
        assert.are.same({ { key("x"), OPEN } }, sent) -- the rows exist (no drop), closed after the Build
        assert.are.equal(1, recs[1].restarts)
    end)
end)

-- (windows design v6 §13, L1180) The core's side of forecast == apply, per tick of a headless run: the operations the
-- pass sends are exactly the oracle's (M.apply folded over the belief's state at the pass's now, in the order the
-- lines fire: each one that changes the state is sent); the copy at the end of slot 1's now walk is the oracle's end
-- state; after the next Drain the belief equals that copy (the replay invariant); and the belief applies every
-- operation (refused and dropped stay 0). `cand(i)`: the lines true and reached at now on tick i, in firing order
-- (a line the walk evaluates again after a restart is listed again). Named exemptions: L01 (operations to a key
-- whose generation waits for combat end are dropped, asserted there) and OP5 (a window running out between the
-- Drain's stamp and the pass's now: the headless pass's now is the stamp, asserted every tick, so it cannot arise).
local FIELDS = { "up", "openedAt", "expiresAt" }

local function closedAt(s, T)
    if s.up and s.expiresAt <= T then
        return { up = false, openedAt = 0, expiresAt = 0, refreshes = 0, step = 0 }
    end
    return s
end

local function sameState(a, b)
    for _, f in ipairs(FIELDS) do
        local x, y = a[f], b[f]
        if not (x == y or type(x) == "number" and type(y) == "number" and math.abs(x - y) < 1e-6) then
            return false
        end
    end
    return true
end

local function show(s)
    return string.format("up=%s opened=%s expires=%s", tostring(s.up), tostring(s.openedAt), tostring(s.expiresAt))
end

-- Runs `c.lists` for `c.ticks` ticks (flags per tick from `c.flags[i]`); returns the operations sent per tick.
local function forecastRun(c)
    load(c.lists)
    flaps = 0
    assert.are.equal(c.loadErrors or 0, #H.errors) -- C01: its compile errors, reported once at load
    for k in pairs(H.errors) do
        H.errors[k] = nil
    end
    local decl, names = {}, {}
    for _, r in ipairs(VSI.def.aplWindows) do
        local name = r.key:match("^[^:]+:([^#]+)#Primary$")
        if name then
            decl[name], names[#names + 1] = r, name
        end
    end
    local copy, captured = {}, false
    local gnp = H.Hekili.GetNextPrediction
    H.Hekili.GetNextPrediction = function(self, dispName, packName, slot)
        local a, w, d = gnp(self, dispName, packName, slot)
        if not captured and dispName == "Primary" and slot.index == 1 then -- slot 1's now walk, before any wait
            captured = true
            local delay = S.delay
            S.delay = 0 -- read at now (query_time = now + offset + delay; slot 1's offset is 0)
            for _, n in ipairs(names) do
                local win = S.window[n]
                local up = win.up
                copy[n] =
                    { up = up, openedAt = up and S.now - win.elapsed or 0, expiresAt = up and S.now + win.remains or 0 }
            end
            S.delay = delay
        end
        return a, w, d
    end
    local Q, prev, perTick = VSI.winOps, nil, {}
    for i = 1, c.ticks do
        for f, v in pairs(c.flags and c.flags[i] or {}) do
            flags[f] = v
        end
        local refused, dropped = Q.refused, Q.dropped
        captured = false
        local _, sent = tick()
        local T = VSI.clock
        assert.are.equal(T, S.now, "the pass's now is the Drain's stamp (OP5 cannot arise)")
        local seed = {}
        for _, n in ipairs(names) do
            local b = belief(n)
            seed[n] = b
            if prev then -- the replay invariant: the previous pass's copy, its expiry run at this stamp
                local want = closedAt(prev[n], T)
                assert.is_true(
                    sameState(want, b),
                    string.format("%s tick %d %s: copy %s belief %s", c.id, i, n, show(want), show(b))
                )
            end
        end
        local want, s = {}, {}
        for _, n in ipairs(names) do
            s[n] = {}
            for k, v in pairs(closedAt(seed[n], T)) do
                s[n][k] = v
            end
        end
        for _, o in ipairs(c.cand(i)) do
            local n, code = o[1], o[2]
            local before = {}
            for k, v in pairs(s[n]) do
                before[k] = v
            end
            mx.apply(s[n], code, nil, decl[n], T)
            local changed = false
            for k, v in pairs(s[n]) do
                changed = changed or before[k] ~= v
            end
            if changed then
                want[#want + 1] = { key(n), code }
            end
        end
        assert.are.same(want, sent, c.id .. " tick " .. i .. ": sends")
        for _, n in ipairs(names) do
            assert.is_true(
                sameState(s[n], copy[n]),
                string.format("%s tick %d %s: oracle %s copy %s", c.id, i, n, show(s[n]), show(copy[n]))
            )
        end
        assert.are.equal(refused, Q.refused, c.id .. " tick " .. i .. ": refused")
        assert.are.equal(dropped, Q.dropped, c.id .. " tick " .. i .. ": dropped")
        prev, perTick[i] = copy, #sent
        copy = {}
    end
    H.Hekili.GetNextPrediction = gnp
    -- L1205: a window opened and closed by lines within one slot warns once per pack and window a session
    assert.are.equal(c.flaps or 0, flaps, c.id .. ": flapping-pair warnings")
    -- the last tick's sends too: one more Drain (no pass) must leave the belief equal to the last copy
    t = t + 0.2
    H.ctl.now = t
    VS.Drain(t)
    for _, n in ipairs(names) do
        local want, b = closedAt(prev[n], VSI.clock), belief(n)
        assert.is_true(
            sameState(want, b),
            string.format("%s final drain %s: copy %s belief %s", c.id, n, show(want), show(b))
        )
    end
    return perTick
end

local function always(list)
    return function()
        return list
    end
end

local W1 = "actions+=/window,name=x,duration=6"
local FORECAST = {
    {
        id = "W01",
        lists = {
            windows = "actions+=/window,name=x,duration=0.9",
            default = "actions+=/open_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 12,
        cand = always({ { "x", OPEN } }),
        sends = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 }, -- open, nothing while open, open again once it ran out
    },
    {
        id = "W02/W03",
        lists = {
            windows = W1,
            default = "actions+=/open_window,name=x,if=test_fa\nactions+=/close_window,name=x,if=!test_fa\nactions+=/berserker_stance",
        },
        ticks = 4,
        flags = { { fa = true }, { fa = false } },
        cand = function(i)
            return i == 1 and { { "x", OPEN } } or { { "x", CLOSE } }
        end,
        sends = { 1, 1, 0, 0 },
    },
    {
        id = "W02",
        lists = { windows = W1, default = "actions+=/open_window,name=x,if=test_fa\nactions+=/berserker_stance" },
        ticks = 3,
        flags = { { fa = true }, { fa = false } },
        cand = function(i)
            return i == 1 and { { "x", OPEN } } or {} -- no close line: the window just runs on
        end,
        sends = { 1, 0, 0 },
    },
    {
        id = "W05",
        lists = {
            windows = "actions+=/window,name=x,duration=3,refresh=1,max_refresh=2",
            default = "actions+=/open_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 6,
        cand = always({ { "x", OPEN } }),
        sends = { 1, 1, 1, 0, 0, 0 },
    },
    {
        id = "W06",
        lists = {
            windows = "actions+=/window,name=x,duration=3,refresh=1,max_duration=4",
            default = "actions+=/open_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 9,
        cand = always({ { "x", OPEN } }),
        sends = { 1, 1, 1, 1, 1, 1, 0, 0, 0 },
    },
    {
        id = "W07",
        lists = {
            windows = "actions+=/window,name=x,duration=combat,refresh=1",
            default = "actions+=/open_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 3,
        cand = always({ { "x", OPEN } }),
        sends = { 1, 0, 0 },
    },
    {
        id = "W08",
        lists = {
            windows = W1,
            default = "actions+=/open_window,name=x\nactions+=/open_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 3,
        cand = always({ { "x", OPEN }, { "x", OPEN } }),
        sends = { 1, 0, 0 },
    },
    {
        id = "W09",
        flaps = 1, -- one warning for the whole run (L1205)
        lists = {
            windows = W1,
            default = "actions+=/open_window,name=x\nactions+=/close_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 3,
        cand = always({ { "x", OPEN }, { "x", CLOSE } }),
        sends = { 2, 2, 2 },
    },
    {
        id = "W10",
        flaps = 1, -- one warning for the whole run (L1205)
        lists = {
            windows = W1,
            default = "actions+=/close_window,name=x\nactions+=/open_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 3,
        -- walk 1: the close finds it closed, the open fires; walk 2: the close fires; walk 3: both marked
        cand = always({ { "x", CLOSE }, { "x", OPEN }, { "x", CLOSE } }),
        sends = { 2, 2, 2 },
    },
    {
        id = "W11",
        flaps = 1, -- one warning for the whole run (L1205)
        lists = {
            windows = W1,
            default = "actions+=/open_window,name=x\nactions+=/close_window,name=x\nactions+=/open_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 3,
        cand = function(i)
            if i == 1 then -- closed: each line fires in its own walk
                return { { "x", OPEN }, { "x", CLOSE }, { "x", OPEN } }
            end
            -- open: walk 1, the first open finds it open, the close fires; walk 2, the first open fires, the last finds it open
            return { { "x", OPEN }, { "x", CLOSE }, { "x", OPEN }, { "x", OPEN } }
        end,
        sends = { 3, 2, 2 },
    },
    {
        id = "W12",
        flaps = 1, -- slot 1 ends at the ready pick; a later slot walks to the bottom line and flaps (L1205: any slot)
        lists = {
            windows = W1,
            default = "actions+=/open_window,name=x\nactions+=/bloodrage\nactions+=/close_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 3,
        cand = always({ { "x", OPEN } }), -- the ready pick ends each walk above the close
        sends = { 1, 0, 0 },
    },
    {
        id = "W13",
        lists = {
            windows = W1,
            default = "actions+=/open_window,name=x,if=test_swing_remains<0.5\nactions+=/bloodrage,if=window.x.up",
        },
        ticks = 2,
        cand = always({}), -- true only at a recheck time: the copy opens then, never at now
        sends = { 0, 0 },
    },
    {
        id = "W04",
        lists = {
            windows = W1,
            default = "actions+=/call_action_list,name=sub,if=test_swing_remains<0.5\nactions+=/berserker_stance",
            sub = "actions+=/open_window,name=x",
        },
        ticks = 2,
        cand = always({}), -- the call is true only at a recheck time: the line inside re-reads its stack at its own time, so no open at now
        sends = { 0, 0 },
    },
    {
        id = "R01",
        lists = {
            windows = W1,
            default = "actions+=/bloodrage,if=window.x.up\nactions+=/open_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 3,
        cand = function(i)
            return i == 1 and { { "x", OPEN } } or {} -- once open, the reader is picked above the line
        end,
        sends = { 1, 0, 0 },
    },
    {
        id = "R02",
        lists = { windows = W1, default = "actions+=/open_window,name=x\nactions+=/bloodrage,if=window.x.up" },
        ticks = 3,
        cand = always({ { "x", OPEN } }),
        sends = { 1, 0, 0 },
    },
    {
        id = "R03",
        lists = {
            windows = "actions+=/window,name=a,duration=6\nactions+=/window,name=b,duration=6\nactions+=/window,name=c,duration=6",
            default = "actions+=/open_window,name=c,if=window.b.up\nactions+=/open_window,name=b,if=window.a.up\n"
                .. "actions+=/open_window,name=a\nactions+=/berserker_stance",
        },
        ticks = 3,
        cand = function(i)
            return i == 1 and { { "a", OPEN }, { "b", OPEN }, { "c", OPEN } }
                or { { "c", OPEN }, { "b", OPEN }, { "a", OPEN } }
        end,
        sends = { 3, 0, 0 },
    },
    {
        id = "R05",
        lists = {
            windows = W1,
            default = "actions+=/bloodrage,if=window.x.up\nactions+=/call_action_list,name=sub\nactions+=/berserker_stance",
            sub = "actions+=/open_window,name=x",
        },
        ticks = 3,
        cand = function(i)
            return i == 1 and { { "x", OPEN } } or {}
        end,
        sends = { 1, 0, 0 },
    },
    {
        id = "C01",
        lists = {
            windows = W1,
            default = "actions+=/open_window,name=nope\nactions+=/open_window,name=x,duration=3\nactions+=/open_window,name=x\nactions+=/berserker_stance",
        },
        ticks = 2,
        cand = always({ { "x", OPEN } }), -- the E1 and E4 lines are marked and skipped
        sends = { 1, 0 },
        loadErrors = 2,
    },
}

describe("forecast == apply, the core's side (windows design v6 §13, L1180)", function()
    before_each(function()
        boot()
    end)

    for _, c in ipairs(FORECAST) do
        it(c.id, function()
            for k in pairs(flags) do
                flags[k] = false
            end
            local got = forecastRun(c)
            assert.are.same(c.sends, got)
        end)
    end

    it("L01: operations to a key whose generation waits for combat end are dropped, then applied after it", function()
        local got = forecastRun({
            id = "L01-before",
            lists = { windows = W1, default = "actions+=/open_window,name=x\nactions+=/berserker_stance" },
            ticks = 1,
            cand = always({ { "x", OPEN } }),
        })
        assert.are.same({ 1 }, got)
        -- an edit in combat adds window z (the options' edit: the scripts load again, Update applies the new generation)
        local lists = H.Hekili.DB.profile.packs[ww.PACK].lists
        lists.windows = parse("actions+=/window,name=x,duration=6\nactions+=/window,name=z,duration=6")
        table.insert(lists.default, 1, parse("actions+=/open_window,name=z")[1])
        H.Hekili:LoadScripts()
        H.Hekili:ReviewPacks()
        local Q = VSI.winOps
        local dropped = Q.dropped
        local _, sent = tick()
        assert.are.same({ { key("z"), OPEN } }, sent) -- the copy has z's key; the belief has no row for it yet
        tick()
        assert.are.equal(dropped + 1, Q.dropped) -- the named exemption: the waiting generation's key
        assert.is_false(belief("z").up)
        H.Fire("PLAYER_REGEN_ENABLED")
        tick() -- the generation applies at this Drain (out of combat); this pass's OPEN goes to the new row
        dropped = Q.dropped
        tick()
        assert.is_true(belief("z").up)
        assert.are.equal(dropped, Q.dropped)
    end)
end)

describe("a /reload in combat (windows design v6 §9; review M1)", function()
    it("the active priority's windows work in the fight the reload lands in", function()
        boot()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x\nactions+=/bloodrage,if=window.x.up\nactions+=/berserker_stance",
        })
        local saved = H.env.HekiliDB -- the profile as a /reload finds it
        local fakeNew = fake.new
        fake.new = function(...) -- the reload lands in combat: the client is in combat from the first event
            local api, ctl = fakeNew(...)
            ctl.combat = true
            return api, ctl
        end
        local ok, H2 = pcall(headless.new, { character = ww.character(), pack = ww.PACK, saved = saved })
        fake.new = fakeNew
        assert(ok, H2)
        assert.are.same({}, H2.loadErrors)
        H, S, VS, VSI = H2, H2.Hekili.State, H2.ns.VirtualState, H2.ns.VirtualStateInternal
        assert.is_true(VSI.inCombat)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        local dropped = VSI.winOps.dropped
        local recs = tick()
        assert.are.equal("bloodrage", recs[1].actionName)
        tick()
        assert.is_true(belief("x").up) -- the OPEN reached a row: the windows are live in this fight
        assert.are.equal(dropped, VSI.winOps.dropped)
    end)
end)
