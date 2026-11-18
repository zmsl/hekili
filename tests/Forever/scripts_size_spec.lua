-- tests/Forever/scripts_size_spec.lua (CN25): Engine/Sim/Scripts.lua on long conditions. SimToLua turned at most 100
-- bare `!` into `not` and left the rest in the Lua text, so a longer condition never compiled ("unexpected symbol near
-- '!'", the re-pinned Feral pack's builders).
local headless = require("Game.harness.headless")

describe("Scripts.lua on a long condition (CN25)", function()
    local Sc
    setup(function()
        Sc = headless.new({}).Hekili.Scripts
    end)

    it("turns every bare ! into not, past 100 of them", function()
        local t = {}
        for i = 1, 150 do
            t[i] = "!buff.b" .. i .. ".up"
        end
        local lua = Sc.SimToLua(table.concat(t, "&"))
        assert.is_nil(lua:find("!", 1, true))
        assert.is_function((loadstring("return " .. lua)))
    end)
end)

-- A pure variable (Scripts.lua MarkPure: a `variable` line marked pure=1, with a value and nothing else, the only one of
-- its name, in a list reached only by unconditional calls from default) reads as its value inlined at the read would:
-- the translator hoists a large wowsims variable into one (CN25). Without pure=1 a line is a stock variable.
describe("a pure variable reads as its inlined text (CN25)", function()
    local ww = require("Forever.helpers.warrior_world")

    -- Headless Arms; `hoist`: every condition of the pack moved into a variable line heading the default list and
    -- read by name (`variable,name=vN,pure=1,value=<condition>`, the condition `variable.vN`; `stock`: without pure=1).
    local function boot(hoist, stock)
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        if hoist then
            local lists, defs = H.Hekili.DB.profile.packs[ww.PACK].lists, {}
            for _, name in ipairs({ "precombat", "default" }) do
                for _, e in ipairs(lists[name] or {}) do
                    if (e.criteria or "") ~= "" then
                        defs[#defs + 1] =
                            { action = "variable", enabled = true, var_name = "v" .. #defs + 1, value = e.criteria }
                        defs[#defs].pure = not stock and 1 or nil
                        e.criteria = "variable.v" .. #defs
                    end
                end
            end
            assert.is_true(#defs > 5)
            for i = #defs, 1, -1 do
                table.insert(lists.default, 1, defs[i])
            end
            H.Hekili:LoadScripts()
            H.Hekili:ReviewPacks() -- the moved entries active (actsActive is keyed by index)
        end
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        H.Fire("PLAYER_REGEN_DISABLED")
        return H
    end

    -- Bytes `H` allocates per cycle over n cycles, the collector stopped (tests/Game/State/helpers/alloc.lua's way).
    local function perCycle(H, t, n)
        collectgarbage("collect")
        collectgarbage("collect")
        collectgarbage("stop")
        headless.cycle(H, t)
        local b = collectgarbage("count")
        for i = 1, n do
            headless.cycle(H, t + i * 0.2)
        end
        local d = (collectgarbage("count") - b) * 1024 / n
        collectgarbage("restart")
        return d
    end

    it("recommends the same actions at the same times, registers nothing and allocates nothing more", function()
        local A, B = boot(false), boot(true)
        assert.are.equal(A.ctl.now, B.ctl.now)
        local t = A.ctl.now
        for i = 1, 40 do
            t = t + 0.5
            for _, H in ipairs({ A, B }) do
                H.ctl.power[1] = (i * 17) % 100
                headless.cycle(H, t)
            end
            local ra, rb = A.Hekili.Engine.Output.Primary.recs, B.Hekili.Engine.Output.Primary.recs
            for j = 1, 3 do
                local a, b = ra[j] or {}, rb[j] or {}
                assert.are.same({ i, j, a.actionName, a.time }, { i, j, b.actionName, b.time })
            end
        end
        assert.are.same({}, B.errors)
        assert.is_nil(next(B.Hekili.State.varDB)) -- read in place: never registered
        for id, s in pairs(B.Hekili.Scripts.DB) do -- a read's own time is its value's, never `safenum(variable.vN)`
            assert.is_nil((s.RecheckScript or ""):find("variable", 1, true), id)
        end
        assert.are.equal(perCycle(A, t + 1, 30), perCycle(B, t + 1, 30))
    end)

    -- The read path alone (State.lua state.variable on a pure name: its compiled value called in place), measured as
    -- driver_alloc_spec measures an Update: the collector stopped across the window, one Update and one round of reads
    -- absorb what the collect dropped, then each of 20 Updates (a new query time each) is followed by 10 reads of every
    -- pure variable; only the reads' bytes count, and they are 0.
    it("reads a pure variable in place: 10 reads of each per Update allocate 0 B", function()
        local H = boot(true)
        local t = H.ctl.now + 0.5
        assert(headless.cycle(H, t))
        local S, names = H.Hekili.State, {}
        for name, id in pairs(H.Hekili.Scripts.PackInfo[ww.PACK].pure) do
            if id then
                names[#names + 1] = name
            end
        end
        assert.is_true(#names > 5)
        local function readAll(n)
            for _ = 1, n do
                for i = 1, #names do
                    local _ = S.variable[names[i]]
                end
            end
        end
        collectgarbage("collect")
        collectgarbage("collect")
        collectgarbage("stop")
        headless.cycle(H, t + 0.2)
        readAll(1)
        local bytes = 0
        for i = 2, 21 do
            headless.cycle(H, t + i * 0.2)
            local b = collectgarbage("count")
            readAll(10)
            bytes = bytes + (collectgarbage("count") - b) * 1024
        end
        collectgarbage("restart")
        assert.are.equal(0, bytes)
        assert.is_nil(next(S.varDB))
        assert.are.same({}, H.errors)
    end)

    -- CN25 fix round 2 (L1211): purity is explicit. The same lines without pure=1 are stock variables (registered,
    -- cached), whatever their shape, and recommend the same.
    it("reads a variable line without pure=1 through the stock path", function()
        local A, B = boot(false), boot(true, true)
        local t = A.ctl.now
        for i = 1, 10 do
            t = t + 0.5
            for _, H in ipairs({ A, B }) do
                H.ctl.power[1] = (i * 17) % 100
                headless.cycle(H, t)
            end
            local ra, rb = A.Hekili.Engine.Output.Primary.recs, B.Hekili.Engine.Output.Primary.recs
            assert.are.same({ i, (ra[1] or {}).actionName }, { i, (rb[1] or {}).actionName })
        end
        assert.is_false(B.Hekili.Scripts.PackInfo[ww.PACK].pure.v1)
        for _, v in pairs(B.Hekili.Scripts.PackInfo[ww.PACK].pure) do
            assert.is_false(v)
        end
        assert.is_truthy(B.Hekili.State.varDB.v1) -- registered: the stock path
        assert.are.same({}, B.errors)
    end)

    -- A pure=1 line that cannot be read in place raises at load, naming the line and the reason, and is read as a stock
    -- variable (never silently).
    for _, case in ipairs({
        { "an if=", { criteria = "active_enemies>1" }, "if= is set" },
        { "a value_else=", { value_else = "2" }, "value_else= is set" },
        { "an op other than set", { op = "max" }, "op=max" },
        { "a second line of its name", { second = true }, "2 lines of the name" },
        { "a list reached through a conditional call", { list = "cond" }, "reached through a conditional call" },
    }) do
        it("raises at load on a pure=1 line with " .. case[1], function()
            local H = boot(false)
            local lists = H.Hekili.DB.profile.packs[ww.PACK].lists
            local e = { action = "variable", enabled = true, var_name = "x", value = "1", pure = 1 }
            for k, v in pairs(case[2]) do
                e[k] = v
            end
            local list, at = e.list or "default", nil
            e.list, e.second = nil, nil
            if list ~= "default" then
                lists[list] = { e }
                table.insert(
                    lists.default,
                    1,
                    { action = "call_action_list", enabled = true, list_name = list, criteria = "active_enemies>1" }
                )
                at = ww.PACK .. ":" .. list .. ":1"
            else
                table.insert(lists.default, 1, e)
                at = ww.PACK .. ":default:1"
            end
            if case[2].second then
                table.insert(lists.default, 2, { action = "variable", enabled = true, var_name = "x", value = "2" })
            end
            H.Hekili:LoadScripts()
            local Sc = H.Hekili.Scripts
            assert.is_false(Sc.PackInfo[ww.PACK].pure.x)
            local found
            for _, err in ipairs(H.errors) do
                found = found or (err:find(at, 1, true) and err:find(case[3], 1, true) and err)
            end
            assert.is_truthy(found, table.concat(H.errors, "\n"))
        end)
    end

    -- CN25 fix round 3 (I-A): editing a list call in the priority editor (Hekili:LoadScript of that line) changes where
    -- a pure=1 line may sit: an if= or strict_if= on the call, the call disabled, or pointed at another list makes the
    -- pure=1 line in the called list a stock variable at once, with the load error.
    for _, case in ipairs({
        { "an if=", { criteria = "active_enemies>1" } },
        { "a strict_if=", { strict_if = "active_enemies>1" } },
        { "disabled", { enabled = false } },
        { "pointed at another list", { list_name = "other" } },
    }) do
        it("follows the editor: a call to a pure=1 line's list given " .. case[1], function()
            local H = boot(false)
            local lists = H.Hekili.DB.profile.packs[ww.PACK].lists
            lists.sub = { { action = "variable", enabled = true, var_name = "x", value = "1", pure = 1 } }
            lists.other = { { action = "variable", enabled = true, var_name = "y", value = "2" } }
            table.insert(lists.default, 1, { action = "call_action_list", enabled = true, list_name = "sub" })
            H.Hekili:LoadScripts()
            local Sc = H.Hekili.Scripts
            assert.is_truthy(Sc.PackInfo[ww.PACK].pure.x)
            assert.are.same({}, H.errors)
            for k, v in pairs(case[2]) do
                lists.default[1][k] = v
            end
            H.Hekili:LoadScript(ww.PACK, "default", 1)
            assert.is_false(Sc.PackInfo[ww.PACK].pure.x)
            assert.is_truthy(H.errors[1] and H.errors[1]:find(ww.PACK .. ":sub:1: its list is reached", 1, true))
        end)
    end

    -- A pure value edited in the editor reloads its readers: a list call's time-sensitivity reads through it.
    it("follows the editor: a pure value edited to read time reloads its readers", function()
        local H = boot(false)
        local lists = H.Hekili.DB.profile.packs[ww.PACK].lists
        local list = lists.default
        lists.sub = { { action = "heroic_strike", enabled = true } }
        table.insert(list, 1, { action = "variable", enabled = true, var_name = "a", value = "1", pure = 1 })
        table.insert(
            list,
            2,
            { action = "call_action_list", enabled = true, list_name = "sub", criteria = "variable.a" }
        )
        H.Hekili:LoadScripts()
        local Sc, at = H.Hekili.Scripts, ww.PACK .. ":default:"
        assert.is_falsy(Sc:IsTimeSensitive(at .. 2))
        list[1].value = "buff.battle_shout.remains<=10"
        H.Hekili:LoadScript(ww.PACK, "default", 1)
        assert.is_truthy(Sc:IsTimeSensitive(at .. 2))
        assert.are.same({}, H.errors)
    end)

    -- L1329: the reload also covers a sequence's generated lines (windows design v6 §6): their rechecks read purity too.
    it("follows the editor: a pure variable made stock reloads a sequence's generated lines", function()
        local H = boot(false)
        local list = H.Hekili.DB.profile.packs[ww.PACK].lists.default
        table.insert(
            list,
            1,
            { action = "variable", enabled = true, var_name = "a", value = "buff.battle_shout.remains<=10", pure = 1 }
        )
        table.insert(list, 2, {
            action = "strict_sequence",
            enabled = true,
            window_name = "s",
            steps = { { action = "bloodrage", criteria = "variable.a" } },
        })
        H.Hekili:LoadScripts()
        local Sc, at = H.Hekili.Scripts, ww.PACK .. ":seq:s:1"
        assert.is_nil(Sc.DB[at].RecheckScript) -- a pure read has no recheck of its own (State.lua reads its value's)
        list[1].criteria = "active_enemies>1" -- an if= given: raised, `a` read as a stock variable
        H.Hekili:LoadScript(ww.PACK, "default", 1)
        assert.are.equal("safenum(variable.a)", Sc.DB[at].RecheckScript)
    end)

    -- CN25 fix round 3 (m7): a pure value reading itself, directly or through another pure variable, would recurse at
    -- every read: each such line raises at load and is a stock variable.
    it("raises at load on pure=1 lines whose values read each other in a loop", function()
        local H = boot(false)
        local list = H.Hekili.DB.profile.packs[ww.PACK].lists.default
        table.insert(list, 1, { action = "variable", enabled = true, var_name = "p", value = "variable.q+1", pure = 1 })
        table.insert(list, 2, { action = "variable", enabled = true, var_name = "q", value = "variable.p", pure = 1 })
        table.insert(list, 3, { action = "variable", enabled = true, var_name = "s", value = "variable.s", pure = 1 })
        table.insert(list, 4, { action = "variable", enabled = true, var_name = "t", value = "variable.q", pure = 1 })
        H.Hekili:LoadScripts()
        local pure = H.Hekili.Scripts.PackInfo[ww.PACK].pure
        assert.are.same({ false, false, false }, { pure.p, pure.q, pure.s })
        assert.is_truthy(pure.t) -- reads a loop's variable (now stock), but is in none itself
        local all = table.concat(H.errors, "\n")
        for _, n in ipairs({ "p", "q", "s" }) do
            assert.is_truthy(all:find("Pure variable '" .. n .. "' at .-: its value reads itself"), all)
        end
    end)

    -- Batch 0.9 item 1: a traced read of a pure variable reading another, 4 deep, evaluates each value a bounded number
    -- of times (the debug line once rebuilt every term's text, re-reading the nested ones: 1/2/4/8), and the log still
    -- names each pure read with its value (CN25 review M4).
    it("evaluates each value of a 4-deep pure chain a bounded number of times in a traced read", function()
        local H = boot(false)
        local list = H.Hekili.DB.profile.packs[ww.PACK].lists.default
        for i = 4, 1, -1 do
            local value = i == 4 and "1" or ("variable.d" .. (i + 1) .. "+1")
            table.insert(list, 1, { action = "variable", enabled = true, var_name = "d" .. i, value = value, pure = 1 })
        end
        H.Hekili:LoadScripts()
        H.Hekili:ReviewPacks()
        headless.cycle(H, H.ctl.now + 0.5)
        assert.are.same({}, H.errors)
        local S, Sc, hk = H.Hekili.State, H.Hekili.Scripts, H.Hekili
        local pure, calls, lines = Sc.PackInfo[ww.PACK].pure, {}, {}
        for i = 1, 4 do
            assert.is_truthy(pure["d" .. i], "d" .. i)
            local m = Sc.DB[pure["d" .. i]].Modifiers
            local f = m.value
            calls[i] = 0
            m.value = function()
                calls[i] = calls[i] + 1
                return f()
            end
        end
        local debug = hk.Debug
        hk.Debug = function(_, fmt, ...)
            lines[#lines + 1] = fmt:format(...)
        end
        hk.ActiveDebug = true
        local v = S.variable.d1
        hk.ActiveDebug, hk.Debug = false, debug
        assert.are.equal(4, v)
        for i = 1, 4 do
            assert.is_true(calls[i] <= 2, "calls " .. table.concat(calls, "/"))
        end
        local all = table.concat(lines, "\n")
        for i = 1, 4 do
            assert.is_truthy(all:find(" - variable.d" .. i .. " = " .. (5 - i), 1, true), all)
        end
    end)

    -- CN25 fix round 1 (I2): the priority editor moves a line (Options.lua: the list reordered, then
    -- scripts:SwapScripts) or edits one option (Hekili:LoadScript); which variables are pure follows the pack as it is.
    it("follows the editor: a moved line, an if= given, a name given twice", function()
        local H = boot(false)
        local list = H.Hekili.DB.profile.packs[ww.PACK].lists.default
        table.insert(list, 1, { action = "variable", enabled = true, var_name = "b", value = "2", pure = 1 })
        table.insert(list, 1, { action = "variable", enabled = true, var_name = "a", value = "1", pure = 1 })
        H.Hekili:LoadScripts()
        H.Hekili:ReviewPacks()
        headless.cycle(H, H.ctl.now + 0.5)
        local S, Sc, at = H.Hekili.State, H.Hekili.Scripts, ww.PACK .. ":default:"
        local function pure()
            local p = Sc.PackInfo[ww.PACK].pure
            return { a = p.a and true or false, b = p.b and true or false }
        end
        assert.are.same({ 1, 2 }, { S.variable.a, S.variable.b })

        table.insert(list, 2, table.remove(list, 1)) -- move a down, as the editor's button does
        Sc:SwapScripts(at .. 1, at .. 2)
        assert.are.same({ 1, 2 }, { S.variable.a, S.variable.b })
        assert.are.same({ a = true, b = true }, pure())

        list[1].criteria = "active_enemies>1" -- b (now first) gets an if=: raised, read as a stock variable
        H.Hekili:LoadScript(ww.PACK, "default", 1)
        assert.are.same({ a = true, b = false }, pure())
        assert.are.equal(1, S.variable.a)

        list[1].criteria, list[1].var_name = nil, "a" -- b renamed a: two lines of one name, neither pure
        H.Hekili:LoadScript(ww.PACK, "default", 1)
        assert.are.same({ a = false, b = false }, pure())
        local all = table.concat(H.errors, "\n")
        assert.is_truthy(all:find(at .. "1: if= is set", 1, true), all)
        assert.is_truthy(all:find(at .. "2: 2 lines of the name", 1, true), all)
    end)

    -- A line's recheck times are a set, built from its own time comparisons and those of every variable it
    -- reads (State.lua recurseRechecks). A pack's variants of one variable repeat most comparisons, inside one value and
    -- across values (the re-pinned Feral pack: 8 to 13 functions, 86 to 146 values, 23 to 27 distinct): each distinct
    -- comparison is evaluated once per recheck, and the times are the same.
    it("evaluates each distinct time comparison once per recheck, across the pure variables a line reads", function()
        local H = boot(false)
        local reads = 0
        H.Hekili.Class.stateExprs.probe_remains = function()
            reads = reads + 1
            return 10
        end
        local list = H.Hekili.DB.profile.packs[ww.PACK].lists.default
        local a, b = "probe_remains<=3&probe_remains<=3&probe_remains<=4", "probe_remains<=3|probe_remains<=4"
        table.insert(list, 1, { action = "bloodrage", enabled = true, criteria = "variable.a&variable.b" })
        table.insert(list, 1, { action = "variable", enabled = true, var_name = "b", value = b, pure = 1 })
        table.insert(list, 1, { action = "variable", enabled = true, var_name = "a", value = a, pure = 1 })
        H.Hekili:LoadScripts()
        H.Hekili:ReviewPacks()
        assert(headless.cycle(H, H.ctl.now + 0.5))
        local S, Sc = H.Hekili.State, H.Hekili.Scripts
        local own = Sc.DB[ww.PACK .. ":default:1"] -- a value's own recheck: each comparison once
        reads = 0
        assert.are.same({ 7, 6 }, { own.Recheck() })
        assert.are.equal(2, reads)
        S.system.packName, S.delayMin, S.delayMax = ww.PACK, 0, 3600
        for _ = 1, 2 do -- the first call builds the line's rechecks, the second reuses them
            reads = 0
            S.recheck("bloodrage", Sc.DB[ww.PACK .. ":default:3"])
            assert.are.same({ 6, 7 }, S.recheckTimes)
            assert.are.equal(2, reads)
        end
        assert.are.same({}, H.errors)
    end)

    -- The join falls back to each function on its own when one Lua function cannot return them all (Lua 5.1's register
    -- limit, about 250 values): the times are the same and nothing raises.
    it("keeps a line's recheck times when its variables' distinct times are too many to join", function()
        local H = boot(false)
        H.Hekili.Class.stateExprs.probe_remains = function()
            return 10
        end
        local function value(from)
            local t = {}
            for k = from, from + 149 do
                t[#t + 1] = "probe_remains<=" .. k
            end
            return table.concat(t, "|")
        end
        local list = H.Hekili.DB.profile.packs[ww.PACK].lists.default
        table.insert(list, 1, { action = "bloodrage", enabled = true, criteria = "variable.a&variable.b" })
        table.insert(list, 1, { action = "variable", enabled = true, var_name = "b", value = value(151), pure = 1 })
        table.insert(list, 1, { action = "variable", enabled = true, var_name = "a", value = value(1), pure = 1 })
        H.Hekili:LoadScripts()
        H.Hekili:ReviewPacks()
        assert(headless.cycle(H, H.ctl.now + 0.5))
        local S, Sc = H.Hekili.State, H.Hekili.Scripts
        S.system.packName, S.delayMin, S.delayMax = ww.PACK, 0, 3600
        S.recheck("bloodrage", Sc.DB[ww.PACK .. ":default:3"])
        assert.are.same({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, S.recheckTimes)
        assert.is_false(Sc.DB[ww.PACK .. ":default:3"].JoinedRecheck) -- 300 distinct times: not joined
        assert.are.same({}, H.errors)
    end)

    -- Boots with the pure variables a (<=3) and b (<=4) read by a bloodrage line whose criteria begin with `own`.
    local function joined(own, a)
        local H = boot(false)
        H.Hekili.Class.stateExprs.probe_remains = function()
            return 10
        end
        local list = H.Hekili.DB.profile.packs[ww.PACK].lists.default
        table.insert(list, 1, { action = "bloodrage", enabled = true, criteria = own .. "variable.a&variable.b" })
        table.insert(
            list,
            1,
            { action = "variable", enabled = true, var_name = "b", value = "probe_remains<=4", pure = 1 }
        )
        table.insert(list, 1, { action = "variable", enabled = true, var_name = "a", value = a, pure = 1 })
        H.Hekili:LoadScripts()
        H.Hekili:ReviewPacks()
        assert(headless.cycle(H, H.ctl.now + 0.5))
        local S = H.Hekili.State
        S.system.packName, S.delayMin, S.delayMax = ww.PACK, 0, 3600
        return H, list, S, H.Hekili.Scripts.DB[ww.PACK .. ":default:3"]
    end

    it("joins a line's own recheck times with those of the variables it reads", function()
        local H, _, S, line = joined("probe_remains<=1&", "probe_remains<=3")
        S.recheck("bloodrage", line)
        assert.is_function(line.JoinedRecheck)
        assert.are.same({ 6, 7, 9 }, S.recheckTimes)
        assert.are.same({}, H.errors)
    end)

    it("rebuilds a line's joined recheck after a reload: the times follow the new value", function()
        local H, list, S, line = joined("", "probe_remains<=3")
        S.recheck("bloodrage", line)
        assert.are.same({ 6, 7 }, S.recheckTimes)
        list[1].value = "probe_remains<=2"
        H.Hekili:LoadScript(ww.PACK, "default", 1)
        S.system.packName, S.delayMin, S.delayMax = ww.PACK, 0, 3600
        S.recheck("bloodrage", H.Hekili.Scripts.DB[ww.PACK .. ":default:3"])
        assert.are.same({ 6, 8 }, S.recheckTimes)
        assert.are.same({}, H.errors)
    end)
end)
