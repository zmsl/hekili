-- tests/Forever/windows_apl_spec.lua (windows design v6 Phase 2, free-form windows): the compiler of the reserved
-- `windows` list (E1-E7 for windows, keys per display, records for the belief), the lines as commands (the per-slot
-- fired mark, the restart with no cap, operations sent from slot 1 at now only) and the core's forecast of an OPEN
-- against the oracle M.apply (tests/Game/State/helpers/windows_matrix.lua). Headless Arms with a test priority.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local mx = require("Game.State.helpers.windows_matrix")
local fake = require("Game.State.helpers.fake_api")

local OPEN, CLOSE, STEP = mx.OP.OPEN, mx.OP.CLOSE, mx.OP.STEP
local DISPLAYS = { "Primary", "AOE", "Cooldowns", "Interrupts", "Defensives" }

local H, S, VS, VSI, ops, t
local opArgs = {} -- each sent operation's argument (STEP's step), by its index in `ops`
local flags = {}
local flaps = 0 -- the one-time flapping-pair warnings seen (L1205), taken out of H.errors by tick()
local flapMsg -- the last of them
local FLAP = "opened and closed by lines in the same recommendation"
-- a sequence's (Fable L1286): closed by a close_window line and started again in one slot
local FLAP_SEQ = "was closed by a close_window line and started again in the same recommendation"

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
        opArgs[#ops] = arg or false
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

-- The pack's lists (entries by list name); loads the scripts and enters combat.
local function install(out)
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

-- The pack's lists from simc text by list name, installed as above.
local function load(lists)
    local out = { precombat = {} }
    for name, text in pairs(lists) do
        out[name] = parse(text)
    end
    install(out)
end

-- One update 0.2 s on; returns Primary's records and the operations it sent (in order, as { key, op }).
local function tick()
    ops = {}
    t = t + 0.2
    assert(headless.cycle(H, t))
    for i = #H.errors, 1, -1 do
        if H.errors[i]:find(FLAP, 1, true) or H.errors[i]:find(FLAP_SEQ, 1, true) then
            flaps, flapMsg = flaps + 1, H.errors[i]
            table.remove(H.errors, i)
        end
    end
    assert.are.same({}, H.errors)
    return H.Hekili.Engine.Output.Primary.recs, ops
end

local function key(name, display)
    return ww.PACK .. ":" .. name .. "#" .. (display or "Primary")
end

local function belief(name, display)
    local up, openedAt, expiresAt, refreshes, step = VS.Window(key(name, display))
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

    it(
        "a one-line reload of a line with a window error keeps it disabled, with no new report (L1329 sibling)",
        function()
            load({ default = "actions+=/open_window,name=nope\nactions+=/berserker_stance" })
            local n = #H.errors
            H.Hekili:LoadScript(ww.PACK, "default", 1) -- an editor edit of the line's if=, say
            local script = H.Hekili.Scripts.DB[ww.PACK .. ":default:1"]
            assert.is_truthy(script.Error and script.Error:find("E1", 1, true))
            assert.are.equal(n, #H.errors)
        end
    )

    it("a line the editor moves takes its window error with it, and the line moved past it has none", function()
        load({ default = "actions+=/open_window,name=nope\nactions+=/berserker_stance" })
        local lines = H.Hekili.DB.profile.packs[ww.PACK].lists.default
        lines[1], lines[2] = lines[2], lines[1] -- the editor's move down (Options.lua moveDownBtn)
        local at = ww.PACK .. ":default:"
        H.Hekili.Scripts:SwapScripts(at .. 1, at .. 2)
        H.Hekili:LoadScript(ww.PACK, "default", 1) -- then an edit of the stance line, now first
        assert.is_nil(H.Hekili.Scripts.DB[at .. 1].Error)
        local moved = H.Hekili.Scripts.DB[at .. 2]
        assert.is_truthy(moved.Error and moved.Error:find("E1", 1, true))
    end)

    it("an editor edit of a window line checks the priority's windows again", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x\nactions+=/berserker_stance",
        })
        assert.is_nil(H.Hekili.Scripts.DB[ww.PACK .. ":default:1"].Error)
        -- the editor on default line 1 (its default selection) names a window this priority does not declare
        H.Hekili:SetActionOption({ "packs", ww.PACK, "lists", "entry", "x", "window_name" }, "nope")
        local script = H.Hekili.Scripts.DB[ww.PACK .. ":default:1"]
        assert.is_truthy(script.Error and script.Error:find("E1", 1, true))
    end)

    it("an editor edit of a call line away from the windows list clears its E5, and one to it shows E5", function()
        load({
            default = "actions+=/call_action_list,name=windows\nactions+=/berserker_stance",
            aoe = "actions+=/berserker_stance",
        })
        local at = ww.PACK .. ":default:"
        assert.is_truthy(H.Hekili.Scripts.DB[at .. 1].Error:find("E5", 1, true))
        H.Hekili:SetActionOption({ "packs", ww.PACK, "lists", "entry", "x", "list_name" }, "aoe")
        assert.is_nil(H.Hekili.Scripts.DB[at .. 1].Error)
        H.Hekili:SetActionOption({ "packs", ww.PACK, "lists", "entry", "x", "list_name" }, "windows")
        assert.is_truthy(H.Hekili.Scripts.DB[at .. 1].Error:find("E5", 1, true))
    end)

    it("an editor edit of a non-window entry in the windows list is a full load", function()
        load({
            windows = "actions+=/window,name=x,duration=6\nactions+=/berserker_stance",
            default = "actions+=/berserker_stance",
        })
        -- the editor selects the windows list, line 2 (the stance line): an edit of its if= is a full load
        H.Hekili:SetPackOption({ "packs", ww.PACK, "listName" }, "windows")
        H.Hekili:SetPackOption({ "packs", ww.PACK, "actionID" }, "0002")
        local full = 0
        local ls = H.Hekili.LoadScripts
        H.Hekili.LoadScripts = function(...)
            full = full + 1
            return ls(...)
        end
        H.Hekili:SetActionOption({ "packs", ww.PACK, "lists", "entry", "x", "criteria" }, "1")
        H.Hekili.LoadScripts = ls
        H.Hekili:SetPackOption({ "packs", ww.PACK, "listName" }, "default")
        assert.are.equal(1, full)
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

    it(
        "an import comment above a sequence line is the line's description, a colon in it included (review M8)",
        function()
            local out = H.Hekili:ImportSimcAPL(
                "t",
                "t",
                "# Opener: on pull\nactions=sequence,name=p,mode=continue:bloodrage:berserker_stance\n"
                    .. "# Burst::the big one: go\nactions+=/strict_sequence,name=s:bloodrage:berserker_stance\n"
                    .. "actions+=/defensive_stance"
            )
            local p, s = out.default[1], out.default[2]
            assert.are.same(
                { "sequence", true, 2, "Opener, on pull" },
                { p.action, p.enabled, #p.steps, p.description }
            )
            assert.is_nil(p.steps[2].description)
            assert.are.same(
                { "strict_sequence", true, 2, "Burst", "the big one, go" },
                { s.action, s.enabled, #s.steps, s.caption, s.description }
            )
            assert.is_nil(s.steps[2].caption)
            assert.are.same({}, codes(H.Hekili.Scripts.CheckWindows(out, "t")))
            -- an unclosed ( in the text does not hide the members' colons from the split
            out = H.Hekili:ImportSimcAPL(
                "t",
                "t",
                "# Burst (big\nactions=sequence,name=p:bloodrage:berserker_stance\n"
                    .. "# Burst (big::the opener\nactions+=/strict_sequence,name=s:bloodrage:berserker_stance\n"
            )
            for i = 1, 2 do
                assert.are.same({ true, 2 }, { out.default[i].enabled, #out.default[i].steps }, i)
            end
        end
    )
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

    it("a rebuild drops the old lines' per-slot marks: WIN.fired does not grow over a session (L1324)", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x\nactions+=/berserker_stance",
        })
        tick()
        local WIN
        for i = 1, 200 do
            local name, v = debug.getupvalue(S.WindowSlot, i)
            if not name then
                break
            elseif name == "WIN" then
                WIN = v
            end
        end
        assert.is_not_nil(next(WIN.fired))
        load({ default = "actions+=/berserker_stance" })
        assert.is_nil(next(WIN.fired))
    end)

    it("L05: export then import: plain names and the windows list in the string; the same operations on W09", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x\nactions+=/close_window,name=x\n"
                .. "actions+=/strict_sequence,name=s:bloodrage:berserker_stance\nactions+=/defensive_stance",
        })
        local function run()
            local got = {}
            for i = 1, 3 do
                local _, sent = tick()
                got[i] = sent
            end
            return got
        end
        local before = run()
        local hk = H.Hekili
        local lists = hk.DeserializeActionPack(hk.SerializeActionPack(ww.PACK)).payload.lists
        local function walk(v) -- no display key in the exported lists: plain names only
            if type(v) == "string" then
                assert.is_nil(v:find("#", 1, true), v)
            elseif type(v) == "table" then
                for k, x in pairs(v) do
                    walk(k)
                    walk(x)
                end
            end
        end
        walk(lists)
        assert.are.same({ "window", "x" }, { lists.windows[1].action, lists.windows[1].window_name })
        assert.are.equal(2, #lists.default[3].steps)
        boot()
        install(lists)
        assert.are.same(before, run())
        assert.are.equal(OPEN, before[1][1][2])
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
local FIELDS = { "up", "openedAt", "expiresAt", "step" }

local BR, BS = 2687, 2458 -- Bloodrage, Berserker Stance: the casts the belief observes

local function cast(id)
    H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-seq-" .. id .. "-" .. t, id)
end

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
    return string.format(
        "up=%s opened=%s expires=%s step=%s",
        tostring(s.up),
        tostring(s.openedAt),
        tostring(s.expiresAt),
        tostring(s.step)
    )
end

-- Runs `c.lists` for `c.ticks` ticks (flags per tick from `c.flags[i]`, a cast the belief observes before tick i from
-- `c.casts[i]`); returns the operations sent per tick. Candidates are { name, code, arg } (arg: STEP's step); the
-- sends are compared with their arguments, the copy and the belief with their step (sequences, §6).
local function forecastRun(c)
    local disp = c.display or "Primary" -- the display whose keys are checked; Primary walks (and sends) too
    load(c.lists)
    if disp ~= "Primary" then
        assert.is_true(H.Hekili.Engine.Subscribe(disp, function() end))
    end
    flaps = 0
    assert.are.equal(c.loadErrors or 0, #H.errors) -- C01: its compile errors, reported once at load
    for k in pairs(H.errors) do
        H.errors[k] = nil
    end
    local decl, names = {}, {}
    for _, r in ipairs(VSI.def.aplWindows) do
        local name = r.key:match("^[^:]+:([^#]+)#" .. disp .. "$")
        if name then
            decl[name], names[#names + 1] = r, name
        end
    end
    local copy, captured, tail = {}, false, false
    local function snap()
        local delay = S.delay
        S.delay = 0 -- read at now (query_time = now + offset + delay; slot 1's offset is 0)
        for _, n in ipairs(names) do
            local win = S.window[n]
            local up = win.up
            copy[n] = {
                up = up,
                openedAt = up and S.now - win.elapsed or 0,
                expiresAt = up and S.now + win.remains or 0,
                step = up and win.step or 0,
            }
        end
        S.delay = delay
    end
    local gnp, wop = H.Hekili.GetNextPrediction, VS.WindowOp
    H.Hekili.GetNextPrediction = function(self, dispName, packName, slot)
        tail = false
        local a, w, d = gnp(self, dispName, packName, slot)
        if not captured and dispName == disp and slot.index == 1 then -- slot 1's now walk, before any wait
            captured, tail = true, true
            snap()
        end
        return a, w, d
    end
    -- a strict sequence's chosen OPEN (and an allow_skip STEP) is sent once slot 1 is final, after its walk
    VS.WindowOp = function(k, code, arg)
        local r = wop(k, code, arg)
        if tail and k:sub(-#disp - 1) == "#" .. disp then
            snap()
        end
        return r
    end
    local Q, prev, perTick = VSI.winOps, nil, {}
    for i = 1, c.ticks do
        for f, v in pairs(c.flags and c.flags[i] or {}) do
            flags[f] = v
        end
        local refused, dropped = Q.refused, Q.dropped
        captured = false
        local moved = c.casts and c.casts[i]
        if moved then
            cast(moved)
        end
        local _, sent = tick()
        local sentA = {}
        for j, o in ipairs(sent) do
            if o[1]:sub(-#disp - 1) == "#" .. disp then
                sentA[#sentA + 1] = { o[1], o[2], opArgs[j] }
            end
        end
        local T = VSI.clock
        assert.are.equal(T, S.now, "the pass's now is the Drain's stamp (OP5 cannot arise)")
        local seed = {}
        for _, n in ipairs(names) do
            local b = belief(n, disp)
            seed[n] = b
            if prev and not moved then -- the replay invariant: the previous pass's copy, its expiry run at this stamp
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
            mx.apply(s[n], code, o[3], decl[n], T)
            local changed = false
            for k, v in pairs(s[n]) do
                changed = changed or before[k] ~= v
            end
            if changed then
                want[#want + 1] = { key(n, disp), code, o[3] or false }
            end
        end
        assert.are.same(want, sentA, c.id .. " tick " .. i .. ": sends")
        for _, n in ipairs(names) do
            assert.is_true(
                sameState(s[n], copy[n]),
                string.format("%s tick %d %s: oracle %s copy %s", c.id, i, n, show(s[n]), show(copy[n]))
            )
        end
        assert.are.equal(refused, Q.refused, c.id .. " tick " .. i .. ": refused")
        assert.are.equal(dropped, Q.dropped, c.id .. " tick " .. i .. ": dropped")
        prev, perTick[i] = copy, #sentA
        copy = {}
    end
    H.Hekili.GetNextPrediction, VS.WindowOp = gnp, wop
    -- L1205: a window opened and closed by lines within one slot warns once per pack and window a session
    assert.are.equal(c.flaps or 0, flaps, c.id .. ": flapping-pair warnings")
    -- the last tick's sends too: one more Drain (no pass) must leave the belief equal to the last copy
    t = t + 0.2
    H.ctl.now = t
    VS.Drain(t)
    for _, n in ipairs(names) do
        local want, b = closedAt(prev[n], VSI.clock), belief(n, disp)
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
    -- sequences (§6): STEP with its argument, the copy's step, the chosen OPEN, the give-up, a close line (S24)
    {
        id = "SEQ-skip (S15)",
        lists = {
            default = "actions+=/sequence,name=x:bloodrage,if=test_fa:berserker_stance\nactions+=/defensive_stance",
        },
        ticks = 3,
        cand = always({ { "x", OPEN }, { "x", STEP, 2 } }), -- open, then the skip line drops bloodrage once
        sends = { 2, 0, 0 },
    },
    {
        id = "SEQ-loop (S19)",
        lists = {
            default = "actions+=/restart_sequence,name=x,if=window.x.done\nactions+=/sequence,name=x:bloodrage,if=test_fa\n"
                .. "actions+=/defensive_stance",
        },
        ticks = 3,
        cand = always({ { "x", OPEN }, { "x", STEP, 2 }, { "x", STEP, 1 } }), -- burnt out, then sent back, every slot
        sends = { 3, 2, 2 },
        flaps = 0,
    },
    {
        id = "SEQ-strict (S01/S04)",
        lists = {
            default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance,if=!test_fa\nactions+=/defensive_stance",
        },
        ticks = 3,
        flags = { {}, {}, { fa = true } },
        casts = { [2] = BR },
        cand = function(i)
            return i == 1 and { { "s", OPEN } } or i == 3 and { { "s", CLOSE } } or {}
        end,
        sends = { 1, 0, 1 }, -- chosen; held at step 2 after the cast; given up (berserker_stance's if= false)
    },
    {
        id = "SEQ-allow_skip (P09)",
        lists = {
            default = "actions+=/strict_sequence,name=s,allow_skip=1:bloodrage,if=test_fa:berserker_stance\nactions+=/defensive_stance",
        },
        ticks = 2,
        cand = function(i)
            return i == 1 and { { "s", OPEN }, { "s", STEP, 2 } } or {}
        end,
        sends = { 2, 0 },
    },
    {
        id = "SEQ-close (S24)",
        lists = {
            default = "actions+=/close_window,name=s,if=test_fa\nactions+=/strict_sequence,name=s,hold_off_gcd=1:bloodrage:"
                .. "berserker_stance,if=!test_fa\nactions+=/defensive_stance",
        },
        ticks = 3,
        flags = { {}, { fa = true } },
        cand = function(i)
            return i == 1 and { { "s", OPEN } } or i == 2 and { { "s", CLOSE } } or {}
        end,
        sends = { 1, 1, 0 },
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

    -- the same cases on AOE's keys (mode dual: Primary and AOE both walked, each sends to its own keys)
    for _, c in ipairs(FORECAST) do
        it(c.id .. " (AOE)", function()
            for k in pairs(flags) do
                flags[k] = false
            end
            H.Hekili.Engine.settings.toggles.mode.value = "dual"
            local d = setmetatable({ display = "AOE" }, { __index = c })
            assert.are.same(c.sends, forecastRun(d))
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

-- windows design v6 slice 2: sequences (§3.3, §6, §7). Members over the Arms kit: bloodrage (off the GCD, a cooldown)
-- and berserker_stance (no cost); in the walk tests defensive_stance is the line below that answers when nothing above does.
describe("the sequences compiler (windows design v6 §3.3, §3.4, §9)", function()
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

    it("parses the colon syntax: options in the first token, each member with its own options", function()
        local l = parse(
            "actions+=/strict_sequence,name=s,start_on_first=1,if=test_fa:bloodrage,use_off_gcd=1:battle_shout,if=test_fb"
        )
        assert.are.equal("strict_sequence", l[1].action)
        assert.are.equal("s", l[1].window_name)
        assert.are.equal("1", l[1].start_on_first)
        assert.are.equal("test_fa", l[1].criteria)
        assert.are.equal(2, #l[1].steps)
        assert.are.equal("bloodrage", l[1].steps[1].action)
        assert.are.equal(1, l[1].steps[1].use_off_gcd)
        assert.are.equal("battle_shout", l[1].steps[2].action)
        assert.are.equal("test_fb", l[1].steps[2].criteria)
    end)

    it("L07: a member that is not an ability is a parse warning and disables the line", function()
        local lines, warnings = H.Hekili:ParseActionList("actions+=/sequence,name=x:bloodrage:potion", true)
        assert.is_truthy(warnings and warnings[1]:find("not an ability", 1, true))
        assert.is_false(lines[1].enabled)
    end)

    it("P15/P16: unnamed plain sequences are default, default_2; an unnamed strict one strict_1", function()
        local cw = check({
            default = "actions+=/restart_sequence\nactions+=/sequence:bloodrage:battle_shout\nactions+=/sequence:battle_shout\n"
                .. "actions+=/strict_sequence:bloodrage:battle_shout",
        })
        assert.are.same({}, codes(cw))
        local names = {}
        for _, d in ipairs(cw.decls) do
            names[#names + 1] = d.name
        end
        assert.are.same({ "default", "default_2", "strict_1" }, names)
    end)

    it("C03/E2: a window entry and a sequence share a name; two sequences share one", function()
        local cw = check({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/sequence,name=x:bloodrage\nactions+=/sequence,name=y:bloodrage\nactions+=/strict_sequence,name=y:bloodrage",
        })
        assert.are.same({ "E2 default:1", "E2 default:3" }, codes(cw))
    end)

    it("P17/P25: options a sequence does not take are E7; a non-positive step_timeout is E6", function()
        local cw = check({
            default = "actions+=/sequence,name=a,unready=skip:bloodrage\nactions+=/sequence,name=b,mode=hold:bloodrage\n"
                .. "actions+=/strict_sequence,name=c,mode=wait:bloodrage\nactions+=/strict_sequence,name=d,wait_on_ready=1:bloodrage\n"
                .. "actions+=/sequence,name=e,mode=continue,wait_on_ready=1:bloodrage\nactions+=/sequence,name=f,step_timeout=2:bloodrage\n"
                .. "actions+=/strict_sequence,name=g,step_timeout=0:bloodrage\nactions+=/sequence,name=h,allow_skip=1:bloodrage\n"
                .. "actions+=/strict_sequence,name=i,step_timeout=2,allow_skip=1,start_on_first=1,hold_off_gcd=1,reset_on_target_change=1:bloodrage\n"
                .. "actions+=/sequence,name=j,wait_on_ready=1,reset_on_target_change=1:bloodrage",
        })
        assert.are.same({
            "E7 default:1",
            "E7 default:2",
            "E7 default:3",
            "E7 default:4",
            "E7 default:5",
            "E7 default:6",
            "E6 default:7",
            "E7 default:8",
        }, codes(cw))
    end)

    it("restart_sequence names a plain sequence of the priority (E1 otherwise)", function()
        local cw = check({
            default = "actions+=/restart_sequence,name=s\nactions+=/restart_sequence,name=nope\nactions+=/restart_sequence,name=p\n"
                .. "actions+=/strict_sequence,name=s:bloodrage\nactions+=/sequence,name=p:bloodrage",
        })
        assert.are.same({ "E1 default:1", "E1 default:2" }, codes(cw))
    end)

    it(
        "D12/C09/L1181/L1182: sequences keyed in Primary and AOE only; every record lasts a positive time or combat; strict ends on deviation",
        function()
            local cw = check({
                windows = "actions+=/window,name=w,duration=6",
                default = "actions+=/open_window,name=w\nactions+=/sequence,name=p:bloodrage:battle_shout\nactions+=/strict_sequence,name=s:bloodrage:battle_shout",
            })
            assert.are.same({}, codes(cw))
            local keys = {}
            for _, r in ipairs(cw.records) do
                keys[#keys + 1] = r.key
                assert.is_true(r.duration == "combat" or type(r.duration) == "number" and r.duration > 0, r.key)
                if r.key:find(":s#", 1, true) then
                    assert.are.equal("end", r.on_deviation)
                    assert.is_true(r.strict)
                    assert.are.same({ "bloodrage", "battle_shout" }, r.steps)
                else
                    assert.is_nil(r.on_deviation)
                end
            end
            assert.are.same({
                "pk:w#Primary",
                "pk:w#AOE",
                "pk:w#Cooldowns",
                "pk:w#Interrupts",
                "pk:w#Defensives",
                "pk:p#Primary",
                "pk:p#AOE",
                "pk:s#Primary",
                "pk:s#AOE",
            }, keys)
            -- (§7, L1315) Cooldowns, Interrupts and Defensives never sequence: a stored "on" there adds no key
            for _, disp in ipairs({ "Cooldowns", "Interrupts", "Defensives" }) do
                H.Hekili.Engine.settings.displays[disp].sequences = true
            end
            local cw2 = check({ default = "actions+=/sequence,name=p:bloodrage" })
            assert.are.equal(2, #cw2.records)
            assert.are.same({ "pk:p#Primary", "pk:p#AOE" }, { cw2.records[1].key, cw2.records[2].key })
            assert.are.equal(4 * 2, cw2.cap) -- the open, the skip, the chosen OPEN and its STEP per key (§5.5)
        end
    )
end)

local function seqState(name, display)
    local up, _, _, _, step = VS.Window(key(name, display))
    return up, step
end

describe("plain sequences (windows design v6 §6, rulings 12, 15, 26, 28)", function()
    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
    end)

    it("S17/P14: opens when reached, members in order, parks with done true and sends nothing more", function()
        load({
            default = "actions+=/sequence,name=x:bloodrage:berserker_stance\nactions+=/defensive_stance,if=!window.x.done|window.x.done",
        })
        local recs, sent = tick()
        assert.are.same({ { key("x"), OPEN } }, sent)
        assert.are.equal("bloodrage", recs[1].actionName)
        assert.are.equal(1, recs[1].restarts)
        recs, sent = tick()
        assert.are.same({}, sent)
        assert.are.same({ true, 1 }, { seqState("x") })
        cast(BR)
        recs = tick()
        assert.are.same({ true, 2 }, { seqState("x") })
        assert.are.equal("berserker_stance", recs[1].actionName)
        cast(BS)
        recs, sent = tick()
        assert.are.same({ true, 3 }, { seqState("x") }) -- parked: up, step past the last
        assert.are.same({}, sent)
        assert.are.equal("defensive_stance", recs[1].actionName)
        S.delay = 0
        assert.is_true(S.window.x.done)
        assert.is_true(S.window.x.up)
        assert.are.same({ false, 0 }, { seqState("x", "AOE") }) -- AOE was not walked
    end)

    it(
        "S15/P01 skip (default): a due member that cannot be cast is dropped with STEP, the next one is shown",
        function()
            load({
                default = "actions+=/sequence,name=x:bloodrage,if=test_fa:berserker_stance\nactions+=/defensive_stance",
            })
            local recs, sent = tick()
            assert.are.same({ { key("x"), OPEN }, { key("x"), 3 } }, sent)
            assert.are.equal("berserker_stance", recs[1].actionName)
            assert.are.equal(2, recs[1].restarts)
            tick()
            assert.are.same({ true, 2 }, { seqState("x") })
        end
    )

    it("P23: skip with no later member castable burns the sequence out (STEP past the last: parked)", function()
        load({
            default = "actions+=/sequence,name=x:bloodrage,if=test_fa:berserker_stance,if=test_fb\nactions+=/defensive_stance",
        })
        local recs, sent = tick()
        assert.are.same({ { key("x"), OPEN }, { key("x"), 3 } }, sent)
        assert.are.equal("defensive_stance", recs[1].actionName)
        tick()
        assert.are.same({ true, 3 }, { seqState("x") })
    end)

    it("S14/P01 continue: stays on the due member and the list carries on below; no STEP", function()
        load({
            default = "actions+=/sequence,name=x,mode=continue:bloodrage,if=test_fa:berserker_stance\nactions+=/defensive_stance",
        })
        local recs, sent = tick()
        assert.are.same({ { key("x"), OPEN } }, sent)
        assert.are.equal("defensive_stance", recs[1].actionName)
        tick()
        assert.are.same({ true, 1 }, { seqState("x") })
    end)

    it(
        "S14/P01/P24 wait and its wait_on_ready=1 alias: nothing below the line is recommended; a line above still is",
        function()
            for _, opt in ipairs({ "mode=wait", "wait_on_ready=1" }) do
                load({
                    default = "actions+=/berserker_stance,if=test_fb\nactions+=/sequence,name=x,"
                        .. opt
                        .. ":bloodrage,if=test_fa:berserker_stance\nactions+=/defensive_stance",
                })
                local recs, sent = tick()
                assert.are.same({ { key("x"), OPEN } }, sent)
                assert.is_nil(recs[1].actionName, opt)
                flags.fb = true
                recs = tick()
                assert.are.equal("berserker_stance", recs[1].actionName, opt)
                flags.fb = false
                H.Fire("PLAYER_REGEN_ENABLED") -- the next case starts closed
                H.Hekili.DB.profile.packs[ww.PACK].lists = { precombat = {}, default = {} }
            end
        end
    )

    -- review M5 (§6 mode=wait, risk 16; SimC: the line counts as ready, so every caller returns it): nothing below the
    -- sequence line is recommended, the lines below each call_action_list / run_action_list that reached it included
    it("M5: mode=wait two called lists deep stops every caller; mode=continue lets them carry on", function()
        for _, c in ipairs({
            { "call_action_list", "mode=wait" },
            { "run_action_list", "mode=wait" },
            { "call_action_list", "mode=continue" },
        }) do
            load({
                default = "actions+=/" .. c[1] .. ",name=a\nactions+=/defensive_stance",
                a = "actions+=/call_action_list,name=b\nactions+=/berserker_stance,if=test_fb",
                b = "actions+=/sequence,name=x,"
                    .. c[2]
                    .. ":bloodrage,if=test_fa:hamstring\nactions+=/rend,if=test_fb",
            })
            local recs, sent = tick()
            local what = c[1] .. " " .. c[2]
            assert.are.same({ { key("x"), OPEN } }, sent, what)
            if c[2] == "mode=wait" then
                assert.is_nil(recs[1].actionName, what)
                flags.fb = true -- the lines below the sequence line, in its list and in its caller, stay unreached
                recs = tick()
                assert.is_nil(recs[1].actionName, what)
            else
                assert.are.equal("defensive_stance", recs[1].actionName, what)
            end
            flags.fb = false
            H.Fire("PLAYER_REGEN_ENABLED") -- the next case starts closed
            H.Hekili.DB.profile.packs[ww.PACK].lists = { precombat = {}, default = {} }
        end
    end)

    it("P21: an inactive sequence line (if= false) opens, skips and shows nothing", function()
        load({
            default = "actions+=/sequence,name=x,if=test_fb:bloodrage,if=test_fa:berserker_stance\nactions+=/defensive_stance",
        })
        local recs, sent = tick()
        assert.are.same({}, sent)
        assert.are.equal("defensive_stance", recs[1].actionName)
        flags.fb = true
        recs, sent = tick()
        assert.are.same({ { key("x"), OPEN }, { key("x"), 3 } }, sent) -- active: opens, then the skip
        assert.are.equal("berserker_stance", recs[1].actionName)
    end)

    it("S18/P13: restart_sequence sends STEP 1 on a parked sequence and the first member is due again", function()
        load({
            default = "actions+=/restart_sequence,name=x,if=window.x.done&test_fa\nactions+=/sequence,name=x,mode=continue:berserker_stance\n"
                .. "actions+=/defensive_stance",
        })
        tick()
        tick()
        cast(BS)
        local recs, sent = tick()
        assert.are.same({ true, 2 }, { seqState("x") }) -- parked
        assert.are.same({}, sent)
        flags.fa = true
        recs, sent = tick()
        assert.are.same({ { key("x"), 3 } }, sent)
        assert.are.equal(1, recs[1].restarts)
        tick()
        assert.are.same({ true, 1 }, { seqState("x") })
    end)

    it("D16: a display with Sequences off skips every sequence line; free-form windows still work there", function()
        load({ default = "actions+=/sequence,name=x:bloodrage\nactions+=/defensive_stance" })
        local cw = H.Hekili.Scripts.appliedWindows
        assert.is_nil(cw.byName.x.keys.Cooldowns)
        S.CopyWindows("Cooldowns")
        S.delay = 0
        assert.is_false(S.openWindow("x"))
        assert.is_false(S.window.x.up)
    end)

    it("the Sequences toggle is on the Primary and AOE pages only (L1315; not Multi)", function()
        H.Hekili:EmbedDisplayOptions()
        local plugins = H.Hekili.Options.args.displays.plugins
        local function find(args)
            for k, v in pairs(args) do
                if k == "sequences" and v.type == "toggle" then
                    return v
                end
                local got = type(v) == "table" and v.args and find(v.args)
                if got then
                    return got
                end
            end
        end
        for _, disp in ipairs({ "Primary", "AOE" }) do
            local p = find(plugins[disp][disp].args)
            assert.is_truthy(p, disp)
            assert.is_nil(p.hidden, disp)
        end
        for _, disp in ipairs({ "Cooldowns", "Interrupts", "Defensives", "Multi" }) do
            assert.is_truthy(plugins[disp][disp].args, disp)
            assert.is_nil(find(plugins[disp][disp].args), disp)
        end
    end)
end)

describe("strict sequences (windows design v6 §6, rulings 4, 27, 29; L1181)", function()
    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
    end)

    it(
        "S01: chosen at now opens it (OPEN after slot 1 is final); the hold shows each member; closes after the last",
        function()
            load({
                default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance,if=!test_fa\nactions+=/defensive_stance",
            })
            local recs, sent = tick()
            assert.are.same({ { key("s"), OPEN } }, sent)
            assert.are.equal("bloodrage", recs[1].actionName)
            assert.are.equal("berserker_stance", recs[2].actionName) -- the forecast cast advanced the copy: slot 2 holds step 2
            recs, sent = tick()
            assert.are.same({}, sent)
            assert.are.same({ true, 1 }, { seqState("s") })
            assert.are.equal("bloodrage", recs[1].actionName)
            cast(BR)
            recs = tick()
            assert.are.same({ true, 2 }, { seqState("s") })
            assert.are.equal("berserker_stance", recs[1].actionName)
            cast(BS)
            recs = tick()
            assert.is_false((seqState("s")))
        end
    )

    it("S05/P04: the default start test fails while a member cannot be cast: never chosen, nothing sent", function()
        load({
            default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance,if=test_fa\nactions+=/defensive_stance",
        })
        local recs, sent = tick()
        assert.are.same({}, sent)
        assert.are.equal("defensive_stance", recs[1].actionName)
    end)

    it("P09: allow_skip starts on the first member that can be cast (OPEN then STEP)", function()
        load({
            default = "actions+=/strict_sequence,name=s,allow_skip=1:bloodrage,if=test_fa:berserker_stance\nactions+=/defensive_stance",
        })
        local recs, sent = tick()
        assert.are.same({ { key("s"), OPEN }, { key("s"), 3 } }, sent)
        assert.are.equal("berserker_stance", recs[1].actionName)
    end)

    it("S04: give-up: the due member cannot be cast with the GCD ready: CLOSE, the normal list answers", function()
        load({
            default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance,if=!test_fa\nactions+=/defensive_stance",
        })
        tick()
        tick()
        cast(BR)
        tick()
        assert.are.same({ true, 2 }, { seqState("s") })
        flags.fa = true
        local recs, sent = tick()
        assert.are.same({ { key("s"), CLOSE } }, sent)
        assert.are.equal("defensive_stance", recs[1].actionName)
    end)

    it(
        "S03/P06: the default hold lets an outside use_off_gcd=1 off-GCD line through; hold_off_gcd=1 holds it",
        function()
            for _, opt in ipairs({ "", ",hold_off_gcd=1" }) do
                load({
                    default = "actions+=/strict_sequence,name=s"
                        .. opt
                        .. ":berserker_stance:defensive_stance\nactions+=/bloodrage,use_off_gcd=1,if=test_fb\n"
                        .. "actions+=/defensive_stance",
                })
                tick()
                flags.fb = true
                local recs = tick() -- open at step 1 (berserker_stance, on the GCD)
                assert.are.same({ true, 1 }, { seqState("s") })
                -- default: the ready off-GCD line is weaved ahead of the member; hold_off_gcd=1: the member alone
                assert.are.equal(opt == "" and "bloodrage" or "berserker_stance", recs[1].actionName, opt)
                flags.fb = false
                H.Fire("PLAYER_REGEN_ENABLED")
            end
        end
    )

    it(
        "S24: a close_window line on the strict sequence closes it under the default hold and under hold_off_gcd=1",
        function()
            for _, opt in ipairs({ "", ",hold_off_gcd=1" }) do
                load({
                    default = "actions+=/close_window,name=s,if=test_fb\nactions+=/strict_sequence,name=s"
                        .. opt
                        .. ",if=!test_fb:bloodrage:berserker_stance\nactions+=/defensive_stance",
                })
                tick()
                tick()
                assert.are.same({ true, 1 }, { seqState("s") }, opt)
                flags.fb = true
                local recs, sent = tick()
                assert.are.same({ { key("s"), CLOSE } }, sent, opt)
                assert.are.equal("defensive_stance", recs[1].actionName, opt) -- the hold ended in the same pass
                flags.fb = false
                H.Fire("PLAYER_REGEN_ENABLED")
            end
        end
    )

    it("a plain sequence line below does nothing while a strict sequence holds (no OPEN, no member shown)", function()
        load({
            default = "actions+=/strict_sequence,name=s:berserker_stance:defensive_stance\n"
                .. "actions+=/sequence,name=p:bloodrage\nactions+=/defensive_stance",
        })
        tick()
        local recs, sent = tick()
        assert.are.same({ true, 1 }, { seqState("s") })
        assert.are.same({}, sent)
        assert.are.equal("berserker_stance", recs[1].actionName)
    end)

    it("the give-up judges a member reading variable.x after the variable lines are walked (both holds)", function()
        for _, opt in ipairs({ "", ",hold_off_gcd=1" }) do
            load({
                default = "actions+=/variable,name=v,value=1\nactions+=/strict_sequence,name=s"
                    .. opt
                    .. ",if=!test_fb:bloodrage:berserker_stance,if=variable.v>0\nactions+=/defensive_stance",
            })
            tick()
            tick()
            cast(BR)
            local recs, sent = tick()
            assert.are.same({ true, 2 }, { seqState("s") }, opt)
            assert.are.same({}, sent, opt)
            assert.are.equal("berserker_stance", recs[1].actionName, opt)
            H.Fire("PLAYER_REGEN_ENABLED")
        end
    end)

    -- (Fable Q1 (c), L1270) the default-list walks begun while a strict sequence holds Primary, over one tick
    local function heldWalks()
        local n, apl = 0, H.Hekili.GetPredictionFromAPL
        H.Hekili.GetPredictionFromAPL = function(self, dispName, packName, listName, ...)
            if listName == "default" and dispName == "Primary" and S.WindowHold() then
                n = n + 1
            end
            return apl(self, dispName, packName, listName, ...)
        end
        local ok, recs, sent = pcall(tick)
        H.Hekili.GetPredictionFromAPL = apl
        assert(ok, recs)
        return n, recs, sent
    end

    it("holdWalk: hold_off_gcd=1 in a priority with no window or variable line skips the normal lists", function()
        for _, opt in ipairs({ ",hold_off_gcd=1", "" }) do
            load({
                default = "actions+=/strict_sequence,name=s"
                    .. opt
                    .. ":berserker_stance:defensive_stance\nactions+=/defensive_stance",
            })
            assert.is_false(H.Hekili.Scripts.appliedWindows.holdWalk, opt)
            tick()
            local n, recs, sent = heldWalks()
            assert.are.same({ true, 1 }, { seqState("s") }, opt)
            assert.are.same({}, sent, opt)
            assert.are.equal("berserker_stance", recs[1].actionName, opt)
            -- hold_off_gcd=1 skips the walk; the default hold walks whatever the flag (ruling 29)
            if opt == "" then
                assert.is_true(n > 0, opt)
            else
                assert.are.equal(0, n, opt)
            end
            H.Fire("PLAYER_REGEN_ENABLED")
        end
    end)

    it("holdWalk: a variable line alone keeps the walk; the member reading it shows at step 2, no CLOSE", function()
        load({
            default = "actions+=/variable,name=v,value=1\nactions+=/strict_sequence,name=s,hold_off_gcd=1"
                .. ":bloodrage:berserker_stance,if=variable.v>0\nactions+=/defensive_stance",
        })
        assert.is_true(H.Hekili.Scripts.appliedWindows.holdWalk)
        tick()
        tick()
        cast(BR)
        local n, recs, sent = heldWalks()
        assert.are.same({ true, 2 }, { seqState("s") })
        assert.are.same({}, sent)
        assert.are.equal("berserker_stance", recs[1].actionName)
        assert.is_true(n > 0)
    end)

    it("holdWalk: a switched-off close_window line still sets the flag (a superset)", function()
        local default = parse(
            "actions+=/close_window,name=s,if=test_fb\nactions+=/strict_sequence,name=s,hold_off_gcd=1"
                .. ":berserker_stance:defensive_stance\nactions+=/defensive_stance"
        )
        default[1].enabled = false
        install({ precombat = {}, default = default })
        assert.is_true(H.Hekili.Scripts.appliedWindows.holdWalk)
        assert.is_false(H.Hekili.Scripts.NoWindows.holdWalk)
    end)

    -- Fable L1286 item 4: the L1205 warning covers a close line against the chosen OPEN (once, the sequence's text)
    it(
        "item 4: a held-true close line on a strict sequence chosen again sends CLOSE + OPEN every Update, warned once",
        function()
            load({
                default = "actions+=/close_window,name=s,if=test_fb\nactions+=/strict_sequence,name=s:berserker_stance:defensive_stance\n"
                    .. "actions+=/defensive_stance",
            })
            tick()
            flags.fb = true
            local before = flaps
            for i = 1, 3 do
                local _, sent = tick()
                assert.are.same({ { key("s"), CLOSE }, { key("s"), OPEN } }, sent)
                assert.are.equal(before + 1, flaps, i)
            end
            assert.is_truthy(flapMsg:find(FLAP_SEQ, 1, true))
            local keys = H.Hekili.ErrorKeys -- formatted (H.errors holds the template)
            assert.is_truthy(
                keys[#keys]:find("Priority '" .. ww.PACK .. "': sequence 's' was closed", 1, true),
                keys[#keys]
            )
        end
    )

    it("member lines get LoadScript's bookkeeping: use_off_gcd=1 marks the pack, a member item is listed", function()
        load({
            default = "actions+=/strict_sequence,name=s:bloodrage,use_off_gcd=1:berserker_stance\nactions+=/defensive_stance",
        })
        local info = H.Hekili.Scripts.PackInfo[ww.PACK]
        assert.is_true(info.hasOffGCD)
        local sid = H.Hekili.Scripts.appliedWindows.byName.s.hiddenIDs[1]
        local script = H.Hekili.Scripts.DB[sid]
        assert.are.equal("bloodrage", script.action)
        assert.is_true(script.ReadsWindow)
    end)

    it("L1181: a later member cast out of order ends a strict sequence", function()
        load({ default = "actions+=/strict_sequence,name=s:berserker_stance:bloodrage\nactions+=/defensive_stance" })
        tick()
        tick()
        assert.are.same({ true, 1 }, { seqState("s") })
        cast(BR) -- the second member, out of order (off the GCD)
        tick()
        assert.is_false((seqState("s")))
    end)

    it(
        "L1181: an outside use_off_gcd=1 line for a later member is weaved by the hold and ends it when pressed",
        function()
            load({
                default = "actions+=/strict_sequence,name=s:berserker_stance:bloodrage\nactions+=/bloodrage,use_off_gcd=1,if=test_fb\n"
                    .. "actions+=/defensive_stance",
            })
            tick()
            flags.fb = true
            local recs = tick()
            assert.are.same({ true, 1 }, { seqState("s") })
            assert.are.equal("bloodrage", recs[1].actionName) -- the known SimC difference (L1181): shown, and pressing it ends s
            cast(BR)
            tick()
            assert.is_false((seqState("s")))
        end
    )

    it("L1181: a plain sequence stays on its step when a later member is cast out of order", function()
        load({
            default = "actions+=/sequence,name=p,mode=continue:berserker_stance:bloodrage\nactions+=/defensive_stance",
        })
        tick()
        tick()
        assert.are.same({ true, 1 }, { seqState("p") })
        cast(BR)
        tick()
        assert.are.same({ true, 1 }, { seqState("p") })
    end)
end)

describe("strict sequences, more named cases (windows design v6 §13)", function()
    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
    end)

    it("S02: a line above the sequence becoming ready while it is open does not take slot 1 (the hold)", function()
        load({
            default = "actions+=/defensive_stance,if=test_fa\nactions+=/strict_sequence,name=s:bloodrage:berserker_stance\n"
                .. "actions+=/defensive_stance",
        })
        local _, sent = tick()
        assert.are.same({ { key("s"), OPEN } }, sent)
        flags.fa = true
        local recs = tick()
        assert.are.same({ true, 1 }, { seqState("s") })
        assert.are.equal("bloodrage", recs[1].actionName)
    end)

    it("P07: an outside zero-GCD line without use_off_gcd=1 is held under the default hold", function()
        load({
            default = "actions+=/strict_sequence,name=s:berserker_stance:defensive_stance\nactions+=/bloodrage,if=test_fb\n"
                .. "actions+=/defensive_stance",
        })
        tick()
        flags.fb = true
        local recs = tick()
        assert.are.same({ true, 1 }, { seqState("s") })
        assert.are.equal("berserker_stance", recs[1].actionName)
    end)

    it("S13: two strict sequences sharing a first member: only the chosen one's key gets OPEN", function()
        load({
            default = "actions+=/strict_sequence,name=a:bloodrage:berserker_stance\n"
                .. "actions+=/strict_sequence,name=b:bloodrage:defensive_stance\nactions+=/defensive_stance",
        })
        local _, sent = tick()
        assert.are.same({ { key("a"), OPEN } }, sent)
        assert.is_false((seqState("b")))
    end)

    it(
        "P08: a member that cannot be cast at step 2: give-up CLOSE; allow_skip STEP 3, and CLOSE with none left",
        function()
            for _, opt in ipairs({ "", ",allow_skip=1" }) do
                load({
                    default = "actions+=/strict_sequence,name=s"
                        .. opt
                        .. ":bloodrage:berserker_stance,if=!test_fa:defensive_stance,if=!test_fb\nactions+=/defensive_stance",
                })
                tick()
                cast(BR)
                tick()
                assert.are.same({ true, 2 }, { seqState("s") }, opt)
                flags.fa = true
                local recs, sent = tick()
                assert.are.equal(1, recs[1].restarts, opt) -- the give-up's CLOSE or STEP restarts the walk (Fable M2)
                if opt == "" then
                    assert.are.same({ { key("s"), CLOSE } }, sent)
                else
                    assert.are.same({ { key("s"), STEP } }, sent)
                    assert.are.equal(3, opArgs[1])
                    assert.are.equal("defensive_stance", recs[1].actionName)
                    tick()
                    assert.are.same({ true, 3 }, { seqState("s") })
                    flags.fb = true
                    _, sent = tick()
                    -- closed; unheld, the allow_skip start test passes on bloodrage again, so it is chosen and reopens
                    assert.are.same({ { key("s"), CLOSE }, { key("s"), OPEN } }, sent)
                end
                flags.fa, flags.fb = false, false
                H.Fire("PLAYER_REGEN_ENABLED")
            end
        end
    )

    it("D11: Primary and AOE both choose the same strict sequence: two keys open; one cast advances both", function()
        H.Hekili.Engine.settings.toggles.mode.value = "dual"
        load({ default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance\nactions+=/defensive_stance" })
        assert.is_true(H.Hekili.Engine.Subscribe("AOE", function() end))
        local _, sent = tick()
        local got = {}
        for _, o in ipairs(sent) do
            got[o[1]] = o[2]
        end
        assert.are.same({ [key("s")] = OPEN, [key("s", "AOE")] = OPEN }, got)
        cast(BR)
        tick()
        assert.are.same({ true, 2 }, { seqState("s") })
        assert.are.same({ true, 2 }, { seqState("s", "AOE") })
    end)
end)

describe("filter bypasses for sequence lines (windows design v6 §7, rulings 9, 25)", function()
    -- `bloodrage` plays the separated cooldown (`classcd`): its toggle is cooldowns, shown separately
    local cds
    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
        H.Hekili.Class.abilities.bloodrage.toggle = "cooldowns"
        cds = H.Hekili.Engine.settings.toggles.cooldowns
        cds.separate, cds.value = true, true
    end)

    it(
        "D14/D18: a strict classcd:nuke starts in Primary (the start line skips the separate test); an off toggle never",
        function()
            load({ default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance\nactions+=/defensive_stance" })
            local recs, sent = tick()
            assert.are.same({ { key("s"), OPEN } }, sent)
            assert.are.equal("bloodrage", recs[1].actionName)
            boot()
            H.Hekili.Class.abilities.bloodrage.toggle = "cooldowns"
            cds = H.Hekili.Engine.settings.toggles.cooldowns
            cds.separate, cds.value = true, false
            load({ default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance\nactions+=/defensive_stance" })
            recs, sent = tick()
            assert.are.same({}, sent)
            assert.are.equal("defensive_stance", recs[1].actionName)
        end
    )

    it("D07/D08: a strict nuke:classcd shows classcd in Primary at step 2; the toggle switched off gives up", function()
        load({ default = "actions+=/strict_sequence,name=s:berserker_stance:bloodrage\nactions+=/defensive_stance" })
        local _, sent = tick()
        assert.are.same({ { key("s"), OPEN } }, sent)
        cast(BS)
        local recs = tick()
        assert.are.same({ true, 2 }, { seqState("s") })
        assert.are.equal("bloodrage", recs[1].actionName)
        cds.value = false
        recs, sent = tick()
        assert.are.same({ { key("s"), CLOSE } }, sent)
        assert.are.equal("defensive_stance", recs[1].actionName)
    end)

    it("D06: once the window closes, the bypass ends: classcd's own line is hidden from Primary again", function()
        load({
            default = "actions+=/close_window,name=s,if=test_fa\n"
                .. "actions+=/strict_sequence,name=s,if=!test_fa:berserker_stance:bloodrage\n"
                .. "actions+=/bloodrage\nactions+=/defensive_stance",
        })
        tick()
        cast(BS)
        local recs = tick()
        assert.are.same({ true, 2 }, { seqState("s") })
        assert.are.equal("bloodrage", recs[1].actionName)
        flags.fa = true
        local sent
        recs, sent = tick()
        assert.are.same({ { key("s"), CLOSE } }, sent)
        assert.are.equal("defensive_stance", recs[1].actionName)
    end)

    it("D10: an outside use_off_gcd=1 line the display filters stays filtered while the hold is up", function()
        load({
            default = "actions+=/strict_sequence,name=s:berserker_stance:defensive_stance\nactions+=/bloodrage,use_off_gcd=1\n"
                .. "actions+=/defensive_stance",
        })
        tick()
        local recs = tick()
        assert.are.same({ true, 1 }, { seqState("s") })
        assert.are.equal("berserker_stance", recs[1].actionName)
    end)

    -- (§7, L1315) Cooldowns, Interrupts and Defensives never sequence: a stored Sequences "on" there (an old profile)
    -- is ignored. Primary, AOE and Cooldowns walked; the operations sent, as a set by key
    local function storedOn(text)
        H.Hekili.Engine.settings.toggles.mode.value = "dual"
        for _, disp in ipairs({ "Cooldowns", "Interrupts", "Defensives" }) do
            H.Hekili.DB.profile.displays[disp].sequences = true
        end
        load({ default = text })
        assert.is_true(H.Hekili.Engine.Subscribe("AOE", function() end))
        assert.is_true(H.Hekili.Engine.Subscribe("Cooldowns", function() end))
    end
    local function sentSet(sent)
        local s = {}
        for _, o in ipairs(sent) do
            s[o[1]] = o[2]
        end
        return s
    end
    -- nothing on Cooldowns' key, no copy there, and Cooldowns does not show the member Primary is at
    local function cooldownsQuiet(sent, name, member)
        assert.is_nil(sentSet(sent)[key(name, "Cooldowns")])
        assert.is_nil(H.Hekili.Scripts.appliedWindows.byName[name].keys.Cooldowns)
        assert.is_false((seqState(name, "Cooldowns")))
        local cd = H.Hekili.Engine.Output.Cooldowns.recs
        assert.are_not.equal(member, cd[1] and cd[1].actionName)
    end

    -- D02 (Fable Q2, L1270; L1315): ruling 25: Primary's and AOE's start lines skip the separate test, so a strict
    -- classcd:nuke starts in both (D14); Cooldowns never sequences, whatever is stored.
    it("D02: a strict classcd:nuke starts in Primary and AOE; Cooldowns (stored on) sends and shows nothing", function()
        storedOn("actions+=/strict_sequence,name=s:bloodrage:berserker_stance\nactions+=/defensive_stance")
        local recs, sent = tick()
        local s = sentSet(sent)
        assert.are.equal(OPEN, s[key("s")])
        assert.are.equal(OPEN, s[key("s", "AOE")])
        assert.are.equal("bloodrage", recs[1].actionName)
        cooldownsQuiet(sent, "s", "bloodrage")
        cast(BR)
        recs, sent = tick()
        assert.are.same({ true, 2 }, { seqState("s") })
        assert.are.same({ true, 2 }, { seqState("s", "AOE") })
        assert.are.equal("berserker_stance", recs[1].actionName)
        assert.are.equal("berserker_stance", H.Hekili.Engine.Output.AOE.recs[1].actionName)
        cooldownsQuiet(sent, "s", "berserker_stance")
    end)

    it(
        "D02 (plain, L1315): a plain classcd:filler runs in Primary; Cooldowns (stored on) sends and shows nothing",
        function()
            storedOn("actions+=/sequence,name=p,mode=continue:bloodrage:berserker_stance\nactions+=/defensive_stance")
            local _, sent = tick()
            cooldownsQuiet(sent, "p", "bloodrage")
            cast(BR)
            local recs
            recs, sent = tick()
            assert.are.same({ true, 2 }, { seqState("p") })
            assert.are.equal("berserker_stance", recs[1].actionName)
            cooldownsQuiet(sent, "p", "berserker_stance")
        end
    )

    it(
        "D13: Cooldowns separate (it never sequences): a strict nuke:classcd runs in Primary; Cooldowns skips it",
        function()
            load({ default = "actions+=/strict_sequence,name=s:berserker_stance:bloodrage\nactions+=/defensive_stance" })
            assert.is_true(H.Hekili.Engine.Subscribe("Cooldowns", function() end))
            local _, sent = tick()
            assert.are.same({ { key("s"), OPEN } }, sent)
            assert.is_false((seqState("s", "Cooldowns")))
            cast(BS)
            tick()
            assert.are.same({ true, 2 }, { seqState("s") })
            local cd = H.Hekili.Engine.Output.Cooldowns.recs
            assert.are_not.equal("berserker_stance", cd[1] and cd[1].actionName) -- no hold there, no bypass
        end
    )

    it("D19 (Primary): a plain classcd:filler shows classcd as its due first member in Primary", function()
        load({
            default = "actions+=/sequence,name=p,mode=continue:bloodrage:berserker_stance\nactions+=/defensive_stance",
        })
        tick()
        local recs = tick()
        assert.are.same({ true, 1 }, { seqState("p") })
        assert.are.equal("bloodrage", recs[1].actionName)
    end)

    it("D15: Cooldowns (no sequences there): an open_window line reached there opens under Cooldowns' key", function()
        load({
            windows = "actions+=/window,name=burst,duration=6",
            default = "actions+=/open_window,name=burst\nactions+=/bloodrage\nactions+=/defensive_stance",
        })
        assert.is_true(H.Hekili.Engine.Subscribe("Cooldowns", function() end))
        local _, sent = tick()
        assert.are.equal(OPEN, sentSet(sent)[key("burst", "Cooldowns")])
        tick()
        assert.is_true(VS.Window(key("burst", "Cooldowns")))
    end)

    it(
        "D17: Sequences switched on for Primary: keys at once out of combat, at combat end in combat; off removes them",
        function()
            H.Hekili.DB.profile.displays.Primary.sequences = false
            load({ default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance\nactions+=/defensive_stance" })
            local k, rows = key("s"), VSI.win.byKey
            assert.is_nil(H.Hekili.Scripts.appliedWindows.byName.s.keys.Primary)
            assert.is_nil(rows[k])
            -- in combat: the compile has the key at once, the belief's row waits for combat end
            H.Hekili.DB.profile.displays.Primary.sequences = true
            H.Hekili:LoadScripts()
            tick()
            assert.are.equal(k, H.Hekili.Scripts.appliedWindows.byName.s.keys.Primary)
            assert.is_nil(rows[k])
            H.Fire("PLAYER_REGEN_ENABLED")
            tick()
            assert.is_number(rows[k])
            -- out of combat, switched off: the key and its row go at once
            H.Hekili.DB.profile.displays.Primary.sequences = false
            H.Hekili:LoadScripts()
            tick()
            assert.is_nil(H.Hekili.Scripts.appliedWindows.byName.s.keys.Primary)
            assert.is_nil(rows[k])
        end
    )

    -- review M9 (L1315): an allow_skip start past member 1 (member 1's if= false, member 2 the separated cooldown) is
    -- shown and started in Primary and AOE (no display filter there, the start line skips the separate test): OPEN then
    -- STEP 2 on each key, member 2 in slot 1. Cooldowns (stored on) neither starts nor shows it.
    it("M9: an allow_skip start past member 1 shows and starts in Primary and AOE, never in Cooldowns", function()
        storedOn(
            "actions+=/strict_sequence,name=s,allow_skip=1:berserker_stance,if=test_fa:bloodrage\nactions+=/defensive_stance"
        )
        local _, sent = tick()
        for _, disp in ipairs({ "Primary", "AOE" }) do
            local got = {}
            for i, o in ipairs(sent) do
                if o[1] == key("s", disp) then
                    got[#got + 1] = o[2] == STEP and ("STEP " .. opArgs[i]) or o[2]
                end
            end
            assert.are.same({ OPEN, "STEP 2" }, got, disp)
            local recs = H.Hekili.Engine.Output[disp].recs
            assert.are.equal("bloodrage", recs[1] and recs[1].actionName, disp)
        end
        cooldownsQuiet(sent, "s", "bloodrage")
    end)
end)

describe("named cases, part D (windows design v6 §13)", function()
    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
    end)

    -- S12/P05 with a cooldown in the GCD's place: the line's delay is the first member's cooldown (nothing below it)
    it(
        "S12/P05: due in 0.3 s opens with start_on_first=1 (inside the queue window); 0.6 s never; unwritten at 0 only",
        function()
            local cd = H.Hekili.Class.abilities.bloodrage.cooldown
            for _, opt in ipairs({ "", ",start_on_first=1" }) do
                for _, due in ipairs({ 0.6, 0.3, 0 }) do
                    boot()
                    H.Fire("CVAR_UPDATE", "SpellQueueWindow", "400")
                    load({ default = "actions+=/strict_sequence,name=s" .. opt .. ":bloodrage:berserker_stance" })
                    cast(BR)
                    H.ctl.cooldown[BR] = { isActive = true, isOnGCD = false, startTime = t, duration = cd }
                    t = t + cd - due - 0.2
                    local recs, sent = tick()
                    local want = (due == 0 or (opt ~= "" and due == 0.3)) and { { key("s"), OPEN } } or {}
                    assert.are.same(
                        want,
                        sent,
                        opt
                            .. " "
                            .. due
                            .. " "
                            .. tostring(recs[1] and recs[1].actionName)
                            .. " "
                            .. tostring(recs[1] and recs[1].wait)
                    )
                end
            end
        end
    )

    it(
        "P10: allow_skip=1 with start_on_first=1 starts within the queue window, then skips a member that cannot",
        function()
            local cd = H.Hekili.Class.abilities.bloodrage.cooldown
            H.Fire("CVAR_UPDATE", "SpellQueueWindow", "400")
            load({
                default = "actions+=/strict_sequence,name=s,allow_skip=1,start_on_first=1"
                    .. ":bloodrage:berserker_stance,if=!test_fa:defensive_stance",
            })
            cast(BR)
            H.ctl.cooldown[BR] = { isActive = true, isOnGCD = false, startTime = t, duration = cd }
            t = t + cd - 0.3 - 0.2
            local _, sent = tick()
            assert.are.same({ { key("s"), OPEN } }, sent) -- due in 0.3 s
            H.ctl.cooldown[BR] = nil
            cast(BR)
            tick()
            assert.are.same({ true, 2 }, { seqState("s") })
            flags.fa = true
            _, sent = tick()
            assert.are.same({ { key("s"), STEP } }, sent)
            assert.are.equal(3, opArgs[1])
        end
    )

    it("D03: a display not walked at step 2: its key advances on casts; past the step timeout no stale hold", function()
        H.Hekili.Engine.settings.toggles.mode.value = "dual"
        load({
            default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance:defensive_stance\n"
                .. "actions+=/battle_shout",
        })
        local sub = function() end
        assert.is_true(H.Hekili.Engine.Subscribe("AOE", sub))
        tick()
        cast(BR)
        tick()
        assert.are.same({ true, 2 }, { seqState("s", "AOE") })
        H.Hekili.Engine.Unsubscribe("AOE", sub) -- AOE is not walked: it sends nothing
        cast(BS)
        tick()
        assert.are.same({ true, 3 }, belief("s", "AOE").up and { true, belief("s", "AOE").step })
        H.Hekili.Engine.Subscribe("AOE", sub)
        tick()
        assert.are.equal("defensive_stance", H.Hekili.Engine.Output.AOE.recs[1].actionName) -- held at step 3
        H.Hekili.Engine.Unsubscribe("AOE", sub)
        for _ = 1, 25 do -- 5 s: past the 4 s step timeout
            tick()
        end
        assert.is_false(belief("s", "AOE").up)
        H.Hekili.Engine.Subscribe("AOE", sub)
        tick()
        assert.are.equal("battle_shout", H.Hekili.Engine.Output.AOE.recs[1].actionName) -- no stale hold
    end)

    it("S10: the first member cast before the line is ever chosen: no window, step 2 not shown", function()
        load({
            default = "actions+=/strict_sequence,name=s,if=test_fa:bloodrage:berserker_stance\nactions+=/defensive_stance",
        })
        tick()
        cast(BR)
        local recs, sent = tick()
        assert.are.same({}, sent)
        assert.is_false((seqState("s")))
        assert.are.equal("defensive_stance", recs[1].actionName)
    end)

    it("D01/D05: Primary and AOE, a line true for AOE's target count only: OPEN under AOE's key; keys only", function()
        H.Hekili.Engine.settings.toggles.mode.value = "dual"
        load({
            default = "actions+=/strict_sequence,name=s,if=active_enemies>1:bloodrage:berserker_stance\n"
                .. "actions+=/defensive_stance",
        })
        assert.is_true(H.Hekili.Engine.Subscribe("AOE", function() end))
        local lines = {}
        VS.SetLog({
            active = function()
                return true
            end,
            write = function(fmt, ...)
                local s = string.format(fmt, ...)
                if s:find("windowop", 1, true) then
                    lines[#lines + 1] = s
                end
            end,
        })
        local _, sent = tick()
        tick()
        assert.are.same({ { key("s", "AOE"), OPEN } }, sent)
        assert.is_false((seqState("s")))
        assert.are.same({ true, 1 }, { seqState("s", "AOE") })
        -- D05: the belief hears key strings only: no display number, no line number
        assert.are.equal(1, #lines)
        assert.are.equal("[vs] windowop applied " .. key("s", "AOE") .. " OPEN 0", lines[1]:match("^(.-) t="))
        local snap = VS.Snapshot()
        assert.is_truthy(snap:find(key("s", "AOE"), 1, true), snap)
        assert.is_nil(snap:find(":default:", 1, true))
    end)

    it(
        "S21/P11: a target swap: unwritten nothing changes; reset_on_target_change=1 closes, a plain one reopens",
        function()
            for _, opt in ipairs({ "", ",reset_on_target_change=1" }) do
                load({
                    windows = "actions+=/window,name=w,duration=30" .. opt,
                    default = "actions+=/open_window,name=w,if=test_fb\nactions+=/strict_sequence,name=s"
                        .. opt
                        .. ":berserker_stance:defensive_stance\nactions+=/sequence,name=p,mode=continue"
                        .. opt
                        .. ":bloodrage:battle_shout\nactions+=/defensive_stance",
                })
                flags.fb = true
                tick()
                flags.fb = false
                tick()
                assert.is_true(belief("w").up, opt)
                assert.are.same({ true, 1 }, { seqState("s") }, opt)
                H.ctl.guid.target = "Creature-2" .. opt
                H.Fire("PLAYER_TARGET_CHANGED")
                if opt == "" then
                    tick()
                    assert.is_true(belief("w").up, opt)
                    assert.are.same({ true, 1 }, { seqState("s") }, opt)
                else
                    local _, sent = tick()
                    assert.is_false(belief("w").up, opt) -- reopens only by a line
                    local s = {}
                    for _, o in ipairs(sent) do
                        s[o[1]] = o[2]
                    end
                    assert.are.equal(OPEN, s[key("s")], opt) -- chosen again, from step 1
                    tick()
                    assert.are.same({ true, 1 }, { seqState("s") }, opt)
                end
                H.Fire("PLAYER_REGEN_ENABLED")
            end
        end
    )

    it("P22: a plain skip drops a member for the run; a restart and a new fight offer it again", function()
        load({
            default = "actions+=/restart_sequence,name=p,if=test_fb\n"
                .. "actions+=/sequence,name=p:bloodrage:berserker_stance,if=!test_fa:battle_shout\nactions+=/defensive_stance",
        })
        tick()
        cast(BR)
        tick()
        assert.are.same({ true, 2 }, { seqState("p") })
        flags.fa = true
        local _, sent = tick()
        assert.are.same({ { key("p"), STEP } }, sent)
        assert.are.equal(3, opArgs[1])
        flags.fa = false
        tick()
        local recs = tick()
        assert.are.same({ true, 3 }, { seqState("p") })
        assert.are_not.equal("berserker_stance", recs[1].actionName) -- not offered again in this run
        flags.fb = true
        tick()
        flags.fb = false
        cast(BR)
        recs = tick()
        assert.are.same({ true, 2 }, { seqState("p") })
        assert.are.equal("berserker_stance", recs[1].actionName) -- after the restart
        H.Fire("PLAYER_REGEN_ENABLED")
        tick()
        H.Fire("PLAYER_REGEN_DISABLED")
        tick()
        cast(BR)
        recs = tick()
        assert.are.same({ true, 2 }, { seqState("p") })
        assert.are.equal("berserker_stance", recs[1].actionName) -- a new fight
    end)

    it("S23: a strict sequence in precombat stays open across combat start; the hold applies in precombat", function()
        H.Hekili.DB.profile.packs[ww.PACK].lists = {
            precombat = parse("actions+=/strict_sequence,name=s:bloodrage:berserker_stance:defensive_stance"),
            default = parse("actions+=/battle_shout"),
        }
        H.Hekili:LoadScripts()
        H.Hekili:ReviewPacks()
        H.Hekili.Scripts:ApplyWindows(ww.PACK)
        S:BuildWindows()
        VS.Drain(H.ctl.now)
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        local _, sent = tick()
        assert.are.same({ { key("s"), OPEN } }, sent)
        cast(BR)
        tick()
        assert.are.same({ true, 2 }, { seqState("s") })
        H.Fire("PLAYER_REGEN_DISABLED")
        local recs
        recs, sent = tick()
        assert.are.same({}, sent)
        assert.are.same({ true, 2 }, { seqState("s") })
        assert.are.equal("berserker_stance", recs[1].actionName)
    end)

    it("P02: a plain skip member short for one tick: mode=skip steps past it; wait and continue do not", function()
        for _, mode in ipairs({ "", ",mode=wait", ",mode=continue" }) do
            load({
                default = "actions+=/sequence,name=p"
                    .. mode
                    .. ":bloodrage:berserker_stance,if=!test_fa:battle_shout\nactions+=/defensive_stance",
            })
            tick()
            cast(BR)
            tick()
            flags.fa = true
            local _, sent = tick()
            if mode == "" then
                assert.are.same({ { key("p"), STEP } }, sent, mode)
                assert.are.equal(3, opArgs[1])
            else
                assert.are.same({}, sent, mode)
                assert.are.same({ true, 2 }, { seqState("p") }, mode)
            end
            flags.fa = false
            H.Fire("PLAYER_REGEN_ENABLED")
        end
    end)
end)

describe("the snapshot's Windows section (windows design v6 §15; L06, R13)", function()
    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
    end)

    -- One tick with the debug log on, its lines captured (a debugged display is not debugged again within 0.5 s, so
    -- a caller spaces these ticks by plain ones).
    local function debugTick()
        local lines, dbg = {}, H.Hekili.Debug
        H.Hekili.Debug = function(_, a, ...)
            local ok, text
            if type(a) == "number" then
                ok, text = pcall(string.format, ...)
            else
                ok, text = pcall(string.format, a, ...)
            end
            lines[#lines + 1] = ok and text or tostring(a)
        end
        H.Hekili.Engine.settings.screenshot = false -- the snapshot's screenshot is a client call
        H.Hekili.ActiveDebug = true
        local ok, err = pcall(tick)
        H.Hekili.ActiveDebug = false
        H.Hekili.Debug = dbg
        assert(ok, err)
        return lines
    end
    local function has(lines, text)
        for _, l in ipairs(lines) do
            if l == text then
                return true
            end
        end
        return false
    end
    local function windowsLines(lines)
        local out = {}
        for _, l in ipairs(lines) do
            if l:find("^Windows") or l:find("^  %w+: ") then
                out[#out + 1] = l
            end
        end
        return out
    end

    it("S01: Sequences on, each window as seeded, slot 1's operations with their line, the 10 s counters", function()
        load({ default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance\nactions+=/defensive_stance" })
        local lines = debugTick()
        local pack = ww.PACK
        assert.is_true(has(lines, "Windows (Primary): Sequences on."), table.concat(windowsLines(lines), "\n"))
        assert.is_true(has(lines, "  s: closed; 0 operations / 10 s, 0 opens / 10 s."))
        assert.is_true(
            has(lines, "Windows: sent OPEN s (line " .. pack .. ":default:1)."),
            table.concat(windowsLines(lines), "\n")
        )
        tick()
        tick()
        lines = debugTick()
        assert.is_true(
            has(lines, "  s: up, step 1 of 2; strict, step timeout 4; 1 operations / 10 s, 1 opens / 10 s."),
            table.concat(windowsLines(lines), "\n")
        )
        for _, l in ipairs(windowsLines(lines)) do
            assert.is_nil(l:find("#", 1, true), l) -- plain names: no key suffix outside the belief's section
        end
    end)

    it("W09 (L06/R13): both operations in order with their lines, two restarts in the slot, the counters", function()
        load({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x\nactions+=/close_window,name=x\nactions+=/defensive_stance",
        })
        local lines = debugTick()
        local pack, at = ww.PACK, {}
        for i, l in ipairs(lines) do
            at[l] = at[l] or i
        end
        local o, c =
            at["Windows: sent OPEN x (line " .. pack .. ":default:1)."],
            at["Windows: sent CLOSE x (line " .. pack .. ":default:2)."]
        assert.is_true(o ~= nil and c ~= nil and o < c, table.concat(windowsLines(lines), "\n"))
        local restarts = false
        for _, l in ipairs(lines) do
            restarts = restarts or l:find("^Recommendation #1 is .*window restarts: 2%.") ~= nil
        end
        assert.is_true(restarts)
        tick()
        tick()
        lines = debugTick()
        assert.is_true(
            has(lines, "  x: closed; 6 operations / 10 s, 3 opens / 10 s."),
            table.concat(windowsLines(lines), "\n")
        )
    end)

    it("a mode=wait sequence names the member it waits on; Sequences off is said for the display", function()
        H.Hekili.Engine.settings.displays.Primary.sequences = false
        load({ default = "actions+=/sequence,name=p,mode=wait:bloodrage,if=test_fa\nactions+=/defensive_stance" })
        local lines = debugTick()
        assert.is_true(has(lines, "Windows (Primary): Sequences off."), table.concat(windowsLines(lines), "\n"))
        boot()
        load({ default = "actions+=/sequence,name=p,mode=wait:bloodrage,if=test_fa\nactions+=/defensive_stance" })
        tick()
        tick()
        tick()
        lines = debugTick()
        assert.is_true(
            has(lines, "  p: up, step 1 of 1; mode=wait, waiting on bloodrage; 1 operations / 10 s, 1 opens / 10 s."),
            table.concat(windowsLines(lines), "\n")
        )
    end)

    -- §15 risks 13 and 18 (review M6): the member a failed start test stopped at, and the member every STEP drops
    local function seqLines(lines)
        local out = {}
        for _, l in ipairs(lines) do
            if l:find("sequence ", 1, true) then
                out[#out + 1] = l
            end
        end
        return table.concat(out, "\n")
    end

    it("risk 18: a failed default start test names the member that cannot be cast", function()
        load({
            default = "actions+=/strict_sequence,name=s:bloodrage:berserker_stance,if=test_fa\nactions+=/defensive_stance",
        })
        local lines = debugTick()
        assert.is_true(
            has(lines, " - strict_sequence s: the start test fails at step 2 (berserker_stance)."),
            seqLines(lines)
        )
    end)

    it("risk 13: a plain skip STEP and the give-up's allow_skip STEP name the member they drop", function()
        load({ default = "actions+=/sequence,name=x:bloodrage,if=test_fa:berserker_stance\nactions+=/defensive_stance" })
        local lines = debugTick()
        assert.is_true(
            has(lines, " - sequence x: step 1 (bloodrage) cannot be cast, step 2, restart."),
            seqLines(lines)
        )
        boot()
        load({
            default = "actions+=/strict_sequence,name=s,allow_skip=1:bloodrage:berserker_stance,if=!test_fa:defensive_stance"
                .. "\nactions+=/defensive_stance",
        })
        tick()
        cast(BR)
        tick()
        tick()
        flags.fa = true
        lines = debugTick()
        assert.is_true(
            has(lines, "strict_sequence s: step 2 (berserker_stance) cannot be cast; step 3, restart."),
            seqLines(lines)
        )
    end)
end)

describe("the strict start test's ability fields (windows design v6 §3.6, ruling 36)", function()
    local GATES = {
        form = { "form", "defensive_stance" }, -- down: the gate fails
        buff = { "buff", "defensive_stance" },
        noform = { "noform", "battle_stance" }, -- up: the gate fails
        nobuff = { "nobuff", "battle_stance" }, -- up for an hour: the time to ready waits
    }
    local LINE = "actions+=/strict_sequence,name=s%s:bloodrage:berserker_stance%s\nactions+=/defensive_stance"
    local calls

    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
        calls = 0
    end)

    local function member(fields)
        local a = H.Hekili.Class.abilities.berserker_stance
        for k, v in pairs(fields) do
            if type(v) == "function" then
                setfenv(v, S)
            end
            a[k] = v
        end
        return a
    end

    local function opened(opt, own)
        load({ default = LINE:format(opt or "", own or "") })
        local _, sent = tick()
        return #sent > 0 and sent[1][2] == OPEN
    end

    it(
        "P28: each gate blocks the start; sequence_ignore naming it lets the line be chosen; another gate still blocks",
        function()
            for gate, g in pairs(GATES) do
                boot()
                member({ [g[1]] = g[2] })
                assert.is_false(opened(), gate)
                boot()
                member({ [g[1]] = g[2], sequence_ignore = { gate } })
                assert.is_true(opened(), gate)
                boot()
                local other = gate == "form" and "noform" or "form"
                member({ [g[1]] = g[2], [GATES[other][1]] = GATES[other][2], sequence_ignore = { gate } })
                assert.is_false(opened(), gate .. " + " .. other)
            end
        end
    )

    it("P29: only the named gate is skipped: the member's usable test still blocks", function()
        member({ form = "defensive_stance", sequence_ignore = { "form" }, usable = false })
        assert.is_false(opened())
    end)

    it(
        "P30: sequence_ready replaces readiness (chosen exactly when it is true); the member's own if= still blocks",
        function()
            for _, f in ipairs({ false, true }) do
                boot()
                member({
                    usable = false,
                    sequence_ready = function()
                        calls = calls + 1
                        return flags.fa
                    end,
                })
                flags.fa = f
                assert.are.equal(f, opened(), tostring(f))
            end
            assert.is_true(calls > 0)
            boot()
            member({
                sequence_ready = function()
                    return true
                end,
            })
            assert.is_false(opened(nil, ",if=test_fb"))
        end
    )

    it("P31: ready() inside sequence_ready is the gate-skipped normal test", function()
        local function readyAndFlag()
            return ready() and flags.fa -- luacheck: ignore 113 (ready: the state's accessor during the call)
        end
        for _, c in ipairs({ { false, false, false }, { true, false, true }, { true, true, false } }) do
            boot()
            member({
                form = "defensive_stance",
                sequence_ignore = { "form" },
                usable = not c[2],
                sequence_ready = readyAndFlag,
            })
            flags.fa = c[1]
            assert.are.equal(c[3], opened(), tostring(c[1]) .. " " .. tostring(c[2]))
        end
    end)

    it("P32/P33: start_on_first=1 and the first member ignore the fields; sequence_ready is never called", function()
        local fields = {
            form = "defensive_stance",
            sequence_ignore = { "form" },
            sequence_ready = function()
                calls = calls + 1
                return true
            end,
        }
        member(fields)
        assert.is_true(opened(",start_on_first=1")) -- only the first member is tested
        boot()
        member(fields)
        load({ default = "actions+=/strict_sequence,name=s:berserker_stance:bloodrage\nactions+=/defensive_stance" })
        local _, sent = tick()
        assert.are.same({}, sent) -- the first member uses normal readiness
        assert.are.equal(0, calls)
    end)

    it("P34: once open, a running step uses normal readiness: the gate it skipped at the start gives up", function()
        member({ form = "defensive_stance", sequence_ignore = { "form" } })
        assert.is_true(opened())
        tick()
        cast(BR)
        local _, sent = tick()
        -- give-up CLOSE; the start test (fields again) then chooses the line anew: OPEN (level, ruling 18)
        assert.are.same({ { key("s"), CLOSE }, { key("s"), OPEN } }, sent)
    end)

    it("a raising sequence_ready leaves no gate skipped for the next walk", function()
        member({
            form = "defensive_stance",
            sequence_ignore = { "form" },
            sequence_ready = function()
                error("handler raised")
            end,
        })
        load({ default = LINE:format("", "") })
        t = t + 0.2
        headless.cycle(H, t)
        for i = #H.errors, 1, -1 do
            table.remove(H.errors, i)
        end
        load({ default = "actions+=/berserker_stance\nactions+=/defensive_stance" })
        local recs = tick()
        assert.are.equal("defensive_stance", recs[1].actionName) -- the form gate holds again
        assert.is_false(rawget(S, "ready"))
    end)

    it("P35: a wrong field raises at registration with the ability's name", function()
        local kit = H.Hekili.Class.kit
        for _, bad in ipairs({
            { sequence_ignore = { "stance" } },
            { sequence_ignore = "form" },
            { sequence_ready = true },
        }) do
            bad.id = 999001
            local ok, err = pcall(kit.RegisterAbility, kit, "seq_bad_field", bad)
            assert.is_false(ok)
            assert.is_truthy(tostring(err):find("seq_bad_field", 1, true), tostring(err))
        end
    end)

    it("P36: a plain sequence and an ordinary line ignore the fields; the handler is not called", function()
        member({
            form = "defensive_stance",
            sequence_ignore = { "form" },
            sequence_ready = function()
                calls = calls + 1
                return true
            end,
        })
        load({
            default = "actions+=/sequence,name=p,mode=continue:berserker_stance\nactions+=/berserker_stance\n"
                .. "actions+=/defensive_stance",
        })
        tick()
        local recs = tick()
        assert.are.equal("defensive_stance", recs[1].actionName)
        assert.are.equal(0, calls)
    end)
end)

-- A running GCD in the rig (review I2): an on-GCD cast the belief observes opens its GCD, which the facade answers for
-- Forever's GCD spell; rage is set so the on-GCD members can be cast. `gcdSeen`: the GCD slot 1's walk read at now on
-- the last tick (each case asserts it ran, so no case passes without a GCD).
local gcdSeen = 0
local HS, RD, MS -- Hamstring, Rend, Mortal Strike: on-GCD members with no cooldown, and one with

local function gcdRig()
    H.ctl.power[1] = 100
    local a = H.Hekili.Class.abilities
    -- the known ranks' IDs: the client's answers (casts, cooldown flags) are the known rank's
    HS, RD, MS = VS.KnownID(a.hamstring.id), VS.KnownID(a.rend.id), VS.KnownID(a.mortal_strike.id)
    local gnp = H.Hekili.GetNextPrediction
    H.Hekili.GetNextPrediction = function(self, dispName, packName, slot)
        if dispName == "Primary" and slot.index == 1 then
            local delay = S.delay
            S.delay = 0
            gcdSeen = S.cooldown.global_cooldown.remains
            S.delay = delay
        end
        return gnp(self, dispName, packName, slot)
    end
end

describe("a running GCD (ruling 28: an on-GCD member is judged at the GCD's end; review I2)", function()
    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
        gcdRig()
    end)

    it(
        "P03: the due on-GCD member while the GCD runs is not dropped (skip, continue, wait): no STEP, shown at its end",
        function()
            -- the last arm: the client's flags for the due member say on the GCD (the facade answers the GCD's numbers)
            for _, arm in ipairs({ "skip", "continue", "wait", "skip+flag" }) do
                boot()
                gcdRig()
                load({
                    default = "actions+=/sequence,name=p,mode="
                        .. arm:match("^%a+")
                        .. ":hamstring:rend\nactions+=/battle_shout",
                })
                local recs, sent = tick()
                assert.are.same({ { key("p"), OPEN } }, sent, arm)
                assert.are.equal("hamstring", recs[1].actionName, arm)
                cast(HS)
                if arm == "skip+flag" then
                    H.ctl.cooldown[RD] = { isActive = true, isOnGCD = true, startTime = t, duration = 1.5 }
                end
                local seen = 0
                for _ = 1, 6 do
                    recs, sent = tick()
                    assert.are.same({}, sent, arm)
                    if gcdSeen > 0.05 then
                        seen = seen + 1
                        assert.are.equal("rend", recs[1].actionName, arm)
                        assert.is_true(
                            math.abs(recs[1].wait - gcdSeen) < 0.05,
                            arm .. " " .. recs[1].wait .. " " .. gcdSeen
                        )
                    end
                end
                assert.is_true(seen >= 3, arm .. " " .. seen) -- the GCD ran in the walk
                assert.are.same({ true, 2 }, { seqState("p") }, arm)
                H.ctl.cooldown[RD] = nil
            end
        end
    )

    it("a member short by time only (skip): ready before the GCD's end it stays due; after it, STEP past it", function()
        for _, x in ipairs({ 1.0, 2.2 }) do -- seconds from the GCD's start to the member's ready time (GCD 1.5 s)
            boot()
            gcdRig()
            load({ default = "actions+=/sequence,name=p:hamstring:mortal_strike:rend\nactions+=/battle_shout" })
            local cd = VS.CooldownLength(MS)
            cast(MS) -- out of order: a plain sequence stays on its step (L1181)
            H.ctl.cooldown[MS] = { isActive = true, isOnGCD = false, startTime = t, duration = cd }
            t = t + cd - x - 0.2
            local recs, sent = tick()
            assert.are.same({ { key("p"), OPEN } }, sent, x)
            assert.are.equal("hamstring", recs[1].actionName, x)
            cast(HS)
            local all, seen = {}, false
            for _ = 1, 3 do
                recs, sent = tick()
                seen = seen or gcdSeen > 0.05
                for _, s in ipairs(sent) do
                    all[#all + 1] = s
                end
            end
            assert.is_true(seen, x)
            if x < 1.5 then
                assert.are.same({}, all, x)
                assert.are.equal("mortal_strike", recs[1].actionName, x)
            else
                assert.are.same({ { key("p"), STEP } }, all, x)
                assert.are.equal(3, opArgs[1] or 0, x)
                assert.are.equal("rend", recs[1].actionName, x)
            end
        end
    end)

    it("the strict start test with a member short by time only (no GCD): not chosen until it is ready", function()
        load({ default = "actions+=/strict_sequence,name=s:hamstring:mortal_strike\nactions+=/battle_shout" })
        local cd = VS.CooldownLength(MS)
        cast(MS)
        H.ctl.cooldown[MS] = { isActive = true, isOnGCD = false, startTime = t, duration = cd }
        t = t + cd - 0.5 - 0.2 -- the GCD MS opened is over; MS ready in 0.5 s
        local recs, sent = tick()
        assert.is_true(gcdSeen == 0)
        assert.are.same({}, sent)
        assert.are.equal("battle_shout", recs[1].actionName)
        H.ctl.cooldown[MS] = nil
        t = t + 0.6
        recs, sent = tick()
        assert.are.same({ { key("s"), OPEN } }, sent)
        assert.are.equal("hamstring", recs[1].actionName)
    end)

    -- (review M3) the copy's park (State.lua advance): members with no cooldown, so a copy that closed instead would be
    -- reopened at step 1 by the open line in slot 2 and show its first member again
    it(
        "M3: the forecast cast of a plain sequence's last member parks the copy; slots 2 and 3 do not reopen it",
        function()
            load({ default = "actions+=/sequence,name=x:hamstring:rend\nactions+=/battle_shout" })
            tick()
            cast(HS)
            tick()
            local recs, sent = tick()
            assert.are.same({ true, 2 }, { seqState("x") })
            assert.are.same({}, sent)
            assert.are.equal("rend", recs[1].actionName)
            assert.are.equal("battle_shout", recs[2].actionName)
            assert.are.equal("battle_shout", recs[3].actionName)
        end
    )
end)

-- (review I1, Fable L1290) A member's own if= belongs to its position: the generated line of position K reads
-- window.<w>.step=K. Hamstring and Rend: on-GCD members with no cooldown, so a repeated one is castable at both.
describe("member lines keyed on their position (windows design v6 §6; review I1)", function()
    local REPEAT = ":hamstring,if=test_fa:rend:hamstring,if=!test_fa"

    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
        gcdRig()
    end)

    it("compiles window.<w>.step=<K> and the own condition; no script error, no recheck from the step term", function()
        load({ default = "actions+=/sequence,name=p,mode=continue" .. REPEAT })
        local d = H.Hekili.Scripts.appliedWindows.byName.p
        assert.are.same({ "window.p.step=1&(test_fa)", "window.p.step=2", "window.p.step=3&(! test_fa)" }, {
            d.hiddenEntries[1].criteria,
            d.hiddenEntries[2].criteria,
            d.hiddenEntries[3].criteria,
        })
        for k = 1, 3 do
            assert.is_nil(H.Hekili.Scripts.DB[d.hiddenIDs[k]].Error, k)
        end
        assert.is_nil(H.Hekili.Scripts.DB[d.hiddenIDs[2]].RecheckScript)
    end)

    it(
        "plain, continue and wait: a repeated member is judged by the condition at the due position (probe P2)",
        function()
            for _, mode in ipairs({ "continue", "wait" }) do
                boot()
                gcdRig()
                -- the reader below (test 3): next.<member> is true at every position holding hamstring
                load({
                    default = "actions+=/sequence,name=p,mode="
                        .. mode
                        .. REPEAT
                        .. "\nactions+=/battle_shout,if=window.p.next.hamstring",
                })
                local below = mode == "continue" and "battle_shout" or nil
                flags.fa = false -- step 1, its own condition false (position 3's true)
                local recs, sent = tick()
                local all = { sent }
                assert.are.equal(below, recs[1].actionName, mode .. " step 1")
                flags.fa = true
                recs, sent = tick()
                all[#all + 1] = sent
                assert.are.equal("hamstring", recs[1].actionName, mode .. " step 1 true")
                cast(HS)
                recs, sent = tick()
                all[#all + 1] = sent
                assert.are.same({ true, 2 }, { seqState("p") }, mode)
                assert.are.equal("rend", recs[1].actionName, mode .. " step 2")
                cast(RD)
                recs, sent = tick() -- step 3, test_fa true: its own condition false (position 1's true)
                all[#all + 1] = sent
                assert.are.same({ true, 3 }, { seqState("p") }, mode)
                assert.are.equal(below, recs[1].actionName, mode .. " step 3")
                flags.fa = false
                all[#all + 1] = select(2, tick()) -- a change between two picks that both wait on the GCD shows one poll late
                recs, sent = tick()
                all[#all + 1] = sent
                assert.are.equal("hamstring", recs[1].actionName, mode .. " step 3 true")
                cast(HS)
                tick()
                assert.are.same({ true, 4 }, { seqState("p") }, mode) -- parked
                S.delay = 0
                assert.is_true(S.window.p.done, mode)
                assert.are.same({ { { key("p"), OPEN } }, {}, {}, {}, {}, {} }, all, mode)
                H.Fire("PLAYER_REGEN_ENABLED")
            end
        end
    )

    it(
        "strict hold under a running GCD: no member shown under another position's condition; give-up at its end",
        function()
            load({
                default = "actions+=/strict_sequence,name=s,start_on_first=1,hold_off_gcd=1"
                    .. REPEAT
                    .. "\nactions+=/battle_shout",
            })
            flags.fa = true
            local _, sent = tick()
            assert.are.same({ { key("s"), OPEN } }, sent)
            cast(HS)
            tick()
            assert.are.same({ true, 2 }, { seqState("s") })
            cast(RD) -- step 3 (hamstring, if=!test_fa) with test_fa true; Rend's GCD runs
            local seen, closed = 0, false
            for _ = 1, 10 do
                local recs
                recs, sent = tick()
                if gcdSeen > 0.05 then
                    seen = seen + 1
                    assert.are_not.equal("hamstring", recs[1].actionName)
                    assert.are.same({}, sent)
                elseif not closed then -- the give-up's CLOSE; member 1's condition holds, so the line starts it again
                    assert.are.same({ { key("s"), CLOSE }, { key("s"), OPEN } }, sent)
                    assert.are.equal("hamstring", recs[1].actionName)
                    closed = true
                end
            end
            assert.is_true(seen >= 3, seen)
            assert.is_true(closed)
        end
    )

    it(
        "the shape that ships (10.2): a repeated member with no conditions shows at both positions, then done",
        function()
            load({
                default = "actions+=/sequence,name=h,mode=continue:hamstring:hamstring:rend\nactions+=/battle_shout",
            })
            local recs, sent = tick()
            assert.are.same({ { key("h"), OPEN } }, sent)
            for step, want in ipairs({ "hamstring", "hamstring", "rend" }) do
                recs, sent = tick()
                assert.are.same({}, sent, step)
                assert.are.same({ true, step }, { seqState("h") }, step)
                assert.are.equal(want, recs[1].actionName, step)
                cast(want == "rend" and RD or HS)
            end
            recs = tick()
            assert.are.same({ true, 4 }, { seqState("h") })
            assert.are.equal("battle_shout", recs[1].actionName)
        end
    )
end)

-- (review M2, Fable L1290) The give-up's allow_skip STEP restarts the walk, as its CLOSE does: the outside lines read
-- the new step in the same slot. P08's allow_skip shape, member 2 made uncastable at step 2.
describe("the give-up's allow_skip STEP restarts the walk (windows design v6 §4.3, §6; review M2)", function()
    local SHAPE = "actions+=/strict_sequence,name=s,allow_skip=1"
        .. ":bloodrage:berserker_stance,if=!test_fa:defensive_stance\nactions+=/defensive_stance"

    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
    end)

    local function toStep2(lists)
        load(lists)
        tick()
        cast(BR)
        tick()
        assert.are.same({ true, 2 }, { seqState("s") })
        flags.fa = true
    end

    it("an outside open_window line reading the step acts in the slot the give-up steps (STEP then OPEN)", function()
        toStep2({
            windows = "actions+=/window,name=x,duration=6",
            default = "actions+=/open_window,name=x,if=window.s.step=3\n" .. SHAPE,
        })
        local recs, sent = tick()
        assert.are.same({ { key("s"), STEP }, { key("x"), OPEN } }, sent)
        assert.are.equal(3, opArgs[1])
        assert.are.equal(2, recs[1].restarts)
        assert.are.equal("defensive_stance", recs[1].actionName)
    end)

    it(
        "the default hold's pick: an outside use_off_gcd=1 line on the old due member gives way to the new one",
        function()
            gcdRig() -- rage for heroic_strike, an off-GCD ability ready at now
            toStep2({
                default = "actions+=/heroic_strike,use_off_gcd=1,if=window.s.next.berserker_stance\n" .. SHAPE,
            })
            local recs, sent = tick()
            assert.are.same({ { key("s"), STEP } }, sent)
            assert.are.equal("defensive_stance", recs[1].actionName)
        end
    )
end)

-- (Fable L1286, item 4) The one-time flapping warning (L1205) also covers a sequence closed by a close_window line and
-- started again in one slot: the strict sequence's chosen OPEN and the plain sequence's generated open line. Engine
-- closes (the give-up, step_timeout) and STEPs do not count.
describe("the flapping warning for sequences (L1205; Fable L1286)", function()
    before_each(function()
        boot()
        flags.fa, flags.fb = false, false
    end)

    -- three ticks with test_fb held true; returns the operation codes sent per tick and the warnings counted
    local function held(lists)
        load(lists)
        tick()
        flags.fb = true
        local before, codes = flaps, {}
        for i = 1, 3 do
            local _, sent = tick()
            codes[i] = {}
            for _, s in ipairs(sent) do
                codes[i][#codes[i] + 1] = s[2]
            end
            table.sort(codes[i])
        end
        return codes, flaps - before
    end

    it("plain: a close line above or below the sequence (its due member not ready), warned once", function()
        for _, lists in ipairs({
            "actions+=/close_window,name=p,if=test_fb\nactions+=/sequence,name=p:berserker_stance:defensive_stance\n"
                .. "actions+=/defensive_stance",
            "actions+=/sequence,name=p,mode=continue:berserker_stance,if=test_fa:defensive_stance\n"
                .. "actions+=/close_window,name=p,if=test_fb\nactions+=/defensive_stance",
        }) do
            boot()
            local codes, n = held({ default = lists })
            assert.are.same({ { OPEN, CLOSE }, { OPEN, CLOSE }, { OPEN, CLOSE } }, codes, lists)
            assert.are.equal(1, n, lists)
            local keys = H.Hekili.ErrorKeys
            assert.is_truthy(
                keys[#keys]:find("Priority '" .. ww.PACK .. "': sequence 'p' was closed", 1, true),
                keys[#keys]
            )
            assert.is_truthy(flapMsg:find(FLAP_SEQ, 1, true))
        end
    end)

    it(
        "one token for both routes: warned through an open/close line pair, the item-4 shape is not warned again",
        function()
            -- one load, one session: test_fa drives the line pair alone, test_fb the item-4 shape (a close line + the start)
            load({
                default = "actions+=/open_window,name=s,if=test_fa\nactions+=/close_window,name=s,if=test_fa\n"
                    .. "actions+=/close_window,name=s,if=test_fb\n"
                    .. "actions+=/strict_sequence,name=s,if=test_fb:berserker_stance:defensive_stance\n"
                    .. "actions+=/defensive_stance",
            })
            local before = flaps
            local _, sent = tick()
            assert.are.same({}, sent) -- both false: nothing acts
            flags.fa = true
            tick()
            assert.are.equal(before + 1, flaps)
            assert.is_truthy(flapMsg:find(FLAP_SEQ, 1, true)) -- the text by the window's kind, not by the route
            flags.fa, flags.fb = false, true
            tick()
            local codes = {}
            for i = 1, 3 do
                _, sent = tick()
                codes[i] = {}
                for _, s in ipairs(sent) do
                    codes[i][#codes[i] + 1] = s[2]
                end
                table.sort(codes[i])
            end
            assert.are.same({ { OPEN, CLOSE }, { OPEN, CLOSE }, { OPEN, CLOSE } }, codes)
            assert.are.equal(before + 1, flaps)
        end
    )

    it("stays silent: the give-up's CLOSE with the sequence chosen again in the slot; S24's opposite term", function()
        gcdRig()
        load({
            default = "actions+=/strict_sequence,name=s,start_on_first=1:hamstring:rend,if=!test_fa\nactions+=/battle_shout",
        })
        tick()
        cast(HS)
        tick()
        assert.are.same({ true, 2 }, { seqState("s") })
        flags.fa = true
        local before, closed = flaps, false
        for _ = 1, 10 do
            local _, sent = tick()
            closed = closed or (sent[1] and sent[1][2] == CLOSE and sent[2] and sent[2][2] == OPEN) or false
        end
        assert.is_true(closed) -- CLOSE then the chosen OPEN in one slot
        assert.are.equal(before, flaps)
        for _, opt in ipairs({ "", ",hold_off_gcd=1" }) do
            boot()
            local codes, n = held({
                default = "actions+=/close_window,name=s,if=test_fb\nactions+=/strict_sequence,name=s"
                    .. opt
                    .. ",if=!test_fb:bloodrage:berserker_stance\nactions+=/defensive_stance",
            })
            assert.are.same({ { CLOSE }, {}, {} }, codes, opt)
            assert.are.equal(0, n, opt)
        end
    end)
end)

-- (review M4) The alternatives probe (needs.alts) walks with rage pinned to the band's bounds; its window and
-- sequence lines act on its copy only (State.WindowSlot(false)). Rage's band as alts_spec sets it: Core.lua's own
-- reads see the low bound, the client facade's the estimate.
describe("the alternatives probe sends nothing (windows design v6 §5.1; review M4)", function()
    it("M4: an open_window and a sequence line true only at the probe's high bound send no operation", function()
        boot()
        local power, fake = VS.Power, { est = 15, lo = 5, hi = 40, conf = 1 }
        VS.Power = function(pt, now)
            local r = power(pt, now)
            if pt ~= 1 then
                return r
            end
            local core = false
            for level = 2, 8 do
                local info = debug.getinfo(level, "S")
                if not info then
                    break
                end
                if info.what ~= "tail" and not info.source:find("Game/API/Facade.lua", 1, true) then
                    core = info.source:find("Engine/Sim/Core.lua", 1, true) ~= nil
                    break
                end
            end
            fake.lo = core and 5 or 15
            return fake
        end
        load({
            windows = "actions+=/window,name=w,duration=6",
            default = "actions+=/open_window,name=w,if=rage.current>=30\n"
                .. "actions+=/sequence,name=p,if=rage.current>=30:mortal_strike:battle_shout\n"
                .. "actions+=/mortal_strike\nactions+=/hamstring\nactions+=/berserker_stance",
        })
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end, true, { alts = true }))
        local probed = 0
        for _ = 1, 3 do
            local recs, sent = tick()
            assert.are.same({}, sent)
            assert.are.equal("hamstring", recs[1].actionName)
            probed = probed + recs[1].alts.n
        end
        assert.is_true(probed > 0) -- the probe ran and picked other actions
        assert.is_false(belief("w").up)
        assert.is_false(belief("p").up)
    end)
end)
