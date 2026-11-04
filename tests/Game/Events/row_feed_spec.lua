-- tests/Game/Events/row_feed_spec.lua (one-event-feed plan, Step 0: the row replay diff): every synthesized combat-log
-- row a COMBAT_LOG_EVENT_UNFILTERED subscriber of the event facade receives, one line each (delivery index, GetTime()
-- while delivered, every slot up to the row's last, the client event or OnUpdate tick that delivered it), through the
-- drive harness (scenarios.oracle solo, party and busy, seeds 1-20; the log2 fixture) and the headless loop on three
-- wowsims replays (one melee, one caster, Protection; wowsims/forever (MIT)). Each run is written to debug/row_feed/
-- (gitignored) and compared row for row with the committed baseline in fixtures/row_feed/ (ROWFEED=record rewrites
-- it); a difference prints its first line and the per-subtype counts. The summary line counts the classes the feed
-- plan measured (§1.4): TENT credits replaced, oracle retractions, duplicate swing rows (same hand and stamp),
-- swings settled twice; and the TENT spell payments (the plan's §6 risk 1).
local drive = require("Game.harness.drive")
local scenarios = require("Game.harness.scenarios")

local BASE = "tests/Game/Events/fixtures/row_feed/"
local OUT = "debug/row_feed/"
local SEEDS = 20

local function fmt(v)
    if type(v) == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return ("%d"):format(v)
        end
        return ("%.4f"):format(v)
    end
    return v == "" and '""' or tostring(v)
end

local function pack(...)
    return select("#", ...), { ... }
end

-- A recorder on booted namespace `ns`: its lines and counters, tagged `tag` (a fight's seed) until retagged.
local function recorder()
    return {
        lines = {},
        sub = {},
        tag = "",
        replaced = 0,
        retracted = 0,
        dup = 0,
        unanchored = 0,
        settled = 0,
        twice = 0,
        spellPays = 0,
        spellTent = 0,
        spellReplaced = 0,
        swingTent = 0,
        reopenAvoids = 0,
        heldMain = 0,
        heldMainStale = 0,
        heldMainZero = 0,
        heldMaxHold = 0,
        heldMaxTrue = 0,
    }
end

-- Subscribes `rec` to namespace `ns`'s rows and counters (the boot's own module: a fresh one per fight).
local function attach(rec, ns)
    local I, F, VS = ns.VirtualStateInternal, ns.Facade, ns.VirtualState
    local E, S, T, L = I.Events, I.Sources, I.Tickets, I.Log
    local MELEE = I.Expect.MELEE
    local via, seen, settledKey = "-", {}, {}
    -- R24: the core's main-hand swing clock as Engine/Sim/Events.lua's swing branch keeps it from the rows (mh_actual,
    -- the speed the hand's PLAYER_SWING carries)
    local mhActual, mhSpeed = 0, 0
    local f = E.frame
    local onEvent, onUpdate = f:GetScript("OnEvent"), f:GetScript("OnUpdate")
    f:SetScript("OnEvent", function(fr, ev, ...)
        local prev = via
        via = ev
        local d, st = ...
        if ev == "PLAYER_SWING" and st == 0 and type(d) == "number" then
            mhSpeed = d
        end
        onEvent(fr, ev, ...)
        via = prev
    end)
    f:SetScript("OnUpdate", function(fr, ...)
        local prev = via
        via = "tick"
        onUpdate(fr, ...)
        via = prev
    end)
    local sink = E.CreateFrame("Frame")
    sink:SetScript("OnEvent", function()
        local n, r = pack(F.CombatLogGetCurrentEventInfo())
        local parts = { rec.tag, "#" .. (#rec.lines + 1), ("%.4f"):format(F.GetTime()) }
        for k = 1, n do
            parts[#parts + 1] = fmt(r[k])
        end
        parts[#parts + 1] = "via=" .. via
        rec.lines[#rec.lines + 1] = table.concat(parts, " ")
        local ev = r[2]
        rec.sub[ev] = (rec.sub[ev] or 0) + 1
        local off = (ev == "SWING_DAMAGE" and r[21]) or (ev == "SWING_MISSED" and r[13])
        if (ev == "SWING_DAMAGE" or ev == "SWING_MISSED") and r[4] == L.player and not off and r[1] > mhActual then
            mhActual = r[1]
        end
    end)
    sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    -- R23: a retraction's re-open closing on a real avoid settles again, by ruling: counted apart, not as a double
    local reopen = false
    local stage = S.Stage
    S.Stage = function(kind, t, a, b, c)
        if kind == VS.Obs.SwingSettled and reopen then
            rec.settled = rec.settled + 1
        elseif kind == VS.Obs.SwingSettled then
            local key = a .. "/" .. ("%.4f"):format(b)
            rec.settled = rec.settled + 1
            if settledKey[key] then
                rec.twice = rec.twice + 1
            end
            settledKey[key] = true
        end
        return stage(kind, t, a, b, c)
    end
    -- duplicates: two own swing rows emitted for one swing (hand and anchor), keyed on the swing the emitting hook
    -- names (a row's stamp may be re-stamped to its hand's newer row, Rows.lua emit, so the stamp cannot key it)
    local ctxHand, ctxAt, recHand, recAt = 0, 0, {}, {}
    local function swingRow(src, miss)
        if src ~= L.player then
            return -- a hit on us (Attackers.lua's onus rows)
        end
        if ctxHand == 0 then
            rec.unanchored = rec.unanchored + 1
            return
        end
        local key = ctxHand .. "/" .. ("%.4f"):format(ctxAt)
        if reopen and miss then
            rec.reopenAvoids = rec.reopenAvoids + 1
        elseif seen[key] then
            rec.dup = rec.dup + 1
        end
        seen[key], ctxHand = true, 0
    end
    local swing, miss = L.Swing, L.Miss
    L.Swing = function(t, family, src, ...)
        swingRow(src)
        return swing(t, family, src, ...)
    end
    L.Miss = function(t, family, src, srcFlags, dst, dstFlags, spellID, ...)
        if spellID == nil then
            swingRow(src, true)
        end
        return miss(t, family, src, srcFlags, dst, dstFlags, spellID, ...)
    end
    local function around(owner, name, anchor)
        local fn = owner[name]
        if not fn then
            return
        end
        owner[name] = function(i, ...)
            ctxHand, ctxAt = anchor(i)
            local a, b = fn(i, ...)
            ctxHand = 0
            return a, b
        end
    end
    local function ticket(i)
        if T.kind[i] == MELEE then
            return T.x[i], T.at[i]
        end
        return 0, 0
    end
    around(T, "onExpire", ticket)
    local onExpire = T.onExpire
    T.onExpire = function(i, ...)
        reopen = T.kind[i] == MELEE and T.retry[i] and T.avoid[i] ~= "" and T.state[i] == T.PROV
        onExpire(i, ...)
        reopen = false
    end
    around(T, "onFinal", ticket)
    around(I, "CreditVerdict", function(id)
        return recHand[id] or 0, recAt[id] or 0
    end)
    local payTentative = T.PayTentative
    T.PayTentative = function(i, ...)
        if T.kind[i] == MELEE then -- creditSwing: its row follows (the record id is set)
            ctxHand, ctxAt = T.x[i], T.at[i]
            recHand[T.rec[i]], recAt[T.rec[i]] = ctxHand, ctxAt
        end
        local held = payTentative(i, ...)
        if T.kind[i] ~= MELEE then
            rec.spellPays = rec.spellPays + 1
            rec.spellTent = rec.spellTent + (held and 1 or 0)
        elseif held then
            rec.swingTent = rec.swingTent + 1
            if T.x[i] == 1 and mhSpeed > 0 then -- R24: the core's mainhand_remains while this row is held
                local now = F.GetTime()
                local core, truth = mhActual + mhSpeed - now, T.at[i] + mhSpeed - now
                rec.heldMain = rec.heldMain + 1
                -- stale: the clock still runs from an older swing; zero: it reads 0 (no swing yet, or past it)
                rec.heldMainStale = rec.heldMainStale + (mhActual < T.at[i] and 1 or 0)
                rec.heldMainZero = rec.heldMainZero + ((mhActual == 0 or core <= 0) and 1 or 0)
                rec.heldMaxHold = math.max(rec.heldMaxHold, T.fin[i] - now)
                rec.heldMaxTrue = math.max(rec.heldMaxTrue, truth)
            end
        end
        return held
    end
    local replace = T.Replace
    T.Replace = function(i, t)
        if T.kind[i] ~= MELEE then
            rec.spellReplaced = rec.spellReplaced + 1
        end
        return replace(i, t)
    end
    -- the module's own counters, read at the end of its run
    return function()
        rec.replaced = rec.replaced + T.replaced
        rec.retracted = rec.retracted + L.oracle.retracted
    end
end

local function summary(name, rec)
    local subs = {}
    for k, v in pairs(rec.sub) do
        subs[#subs + 1] = k .. "=" .. v
    end
    table.sort(subs)
    local tentPct = rec.spellPays > 0 and 100 * rec.spellTent / rec.spellPays or 0
    return (
        "[row feed %s] rows=%d | replaced=%d retracted=%d duplicates=%d unanchored=%d settled=%d settledTwice=%d | spell pays=%d "
        .. "tent=%d (%.2f%%) tentReplaced=%d swingTent=%d reopenAvoids=%d | held main=%d stale=%d zero=%d maxHold=%.3f "
        .. "maxTrue=%.3f | %s"
    ):format(
        name,
        #rec.lines,
        rec.replaced,
        rec.retracted,
        rec.dup,
        rec.unanchored,
        rec.settled,
        rec.twice,
        rec.spellPays,
        rec.spellTent,
        tentPct,
        rec.spellReplaced,
        rec.swingTent,
        rec.reopenAvoids,
        rec.heldMain,
        rec.heldMainStale,
        rec.heldMainZero,
        rec.heldMaxHold,
        rec.heldMaxTrue,
        table.concat(subs, " ")
    )
end

local function write(path, lines)
    local f = assert(io.open(path, "wb"))
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
end

local function counts(lines)
    local out = {}
    for _, l in ipairs(lines) do
        local ev = l:match("^%S* #%d+ %S+ %S+ (%S+)")
        out[ev] = (out[ev] or 0) + 1
    end
    return out
end

-- Compares `rec` with baseline `name` (ROWFEED=record writes it) and prints the summary.
local function check(name, rec)
    print("\n" .. summary(name, rec))
    -- one row and one settle per swing (8a-6 review M5); a re-open's real avoid is its own fact (R23, reopenAvoids)
    assert.are.same({ 0, 0 }, { rec.dup, rec.twice }, name .. ": duplicates, settledTwice")
    os.execute("mkdir -p " .. OUT)
    write(OUT .. name .. ".txt", rec.lines)
    local path = BASE .. name .. ".txt"
    if os.getenv("ROWFEED") == "record" then
        os.execute("mkdir -p " .. BASE)
        write(path, rec.lines)
    end
    local want = {}
    for l in assert(io.open(path, "rb"), "no baseline " .. path):lines() do
        want[#want + 1] = l
    end
    local first
    for i = 1, math.max(#want, #rec.lines) do
        if want[i] ~= rec.lines[i] then
            first = i
            break
        end
    end
    if first then
        local cw, cg, keys, out = counts(want), counts(rec.lines), {}, {}
        for k in pairs(cw) do
            keys[k] = true
        end
        for k in pairs(cg) do
            keys[k] = true
        end
        for k in pairs(keys) do
            out[#out + 1] = ("%s %d -> %d"):format(k, cw[k] or 0, cg[k] or 0)
        end
        table.sort(out)
        error(
            ("%s: rows differ from line %d\n  baseline: %s\n  now:      %s\n  per subtype: %s"):format(
                name,
                first,
                tostring(want[first]),
                tostring(rec.lines[first]),
                table.concat(out, "; ")
            )
        )
    end
end

local function drives(o)
    local rec = recorder()
    for seed = 1, SEEDS do
        local s = scenarios.stream(o, seed)
        local c = drive.boot({ max = o.max, oracle = o.oracle })
        c.ctl.inGroup = o.group ~= false and o.others ~= nil and #o.others > 0
        rec.tag = "s" .. seed
        local done = attach(rec, c.ns)
        drive.run(c, s)
        done()
        drive.restore(c)
    end
    return rec
end

describe("the row feed #slow", function()
    it("solo", function()
        check("solo", drives(scenarios.oracle({})))
    end)
    it("party", function()
        local rec = drives(scenarios.oracle({ others = { "melee", "caster" } }))
        check("party", rec)
        -- R24 (owner 2026-11-04, gaps.md CS): while a TENT main-hand swing's row is held (to T.fin), the core's swing
        -- clock still runs from the previous swing, so mainhand_remains reads 0 (or that older swing's remains, after a
        -- short swing) though the true clock is running. This pins the stale window as it stands; one-event-feed Step 2
        -- feeds the clock at the swing's time and flips it (stale 0)
        assert.is_true(rec.heldMain > 0, "party: no held main-hand swing")
        assert.are.equal(rec.heldMain, rec.heldMainStale)
    end)
    it("busy", function()
        local others = { "melee", "melee", "melee", "caster", "caster", "pet", "pet" }
        check("busy", drives(scenarios.oracle({ others = others, group = false })))
    end)
    it("log2", function()
        local rec = recorder()
        local c = drive.boot()
        local done = attach(rec, c.ns)
        drive.run(c, drive.fixtureStream(require("Game.harness.fixtures.log2"), 10, true))
        done()
        drive.restore(c)
        check("log2", rec)
    end)

    -- the wowsims replays, as their gates build them; copied (the gate specs keep them local), keep in step:
    -- warrior_arms = tests/Forever/wowsims_warrior_spec.lua ARMS, ARMS_REPLAY, ARMS_CHAR (:25-42); mage_fire =
    -- tests/Forever/wowsims_mage_spec.lua REPLAY.fire (:23-24); warrior_protection = wowsims_warrior_spec.lua
    -- PROT, PROT_REPLAY (:57-66)
    local ws = require("Forever.helpers.wowsims")
    local loop = require("Game.harness.loop")
    local replay = require("Game.harness.replay")
    local function wowsims(spec, base, pack, token, extra, knobs)
        local o = { pack = pack, level = 60, talents = ws.header(spec).talents, learn = ws.learn(token) }
        o.race = ws.race(spec)
        for k, v in pairs(extra or {}) do
            o[k] = v
        end
        local C = ws.logged(ws.content(base, o), spec)
        local L = loop.new(C)
        local R = replay.new(ws.log(spec), L.oracle, ws.replayOptions(C, spec, knobs))
        local rec = recorder()
        local done = attach(rec, L.us.ns)
        loop.replay(L, R)
        done()
        check(spec, rec)
    end
    local ww = require("Forever.helpers.warrior_world")
    it("warrior_arms (melee)", function()
        local char = setmetatable({
            character = function()
                local c = ww.character()
                c.speed = { 3.8 }
                return c
            end,
        }, { __index = ww })
        wowsims("warrior_arms", char, "Arms (wowsims.com)", "WARRIOR", {
            kit = { "spearing_strike", "berserker_rage" },
            requires = {
                overpower = function(_, e)
                    return e.auras[1282733] ~= nil and e.form == 1, "no window"
                end,
            },
        }, { hidden = { [1282733] = true }, procs = {} })
    end)
    it("mage_fire (caster)", function()
        local mw = require("Forever.helpers.mage_world")
        wowsims(
            "mage_fire",
            mw.Fire,
            "Fire (wowsims.com)",
            "MAGE",
            nil,
            { procs = { ["10151:1"] = true, ["18809:1"] = true } }
        )
    end)
    it("warrior_protection (Protection)", function()
        wowsims("warrior_protection", ww.Protection, "Protection (wowsims.com)", "WARRIOR", {
            kit = { "berserker_rage", "revenge", "shield_block", "shield_slam", "shield_wall", "shield_bash", "taunt" },
            requires = {
                revenge = function(_, e)
                    return (e.auras[5302] ~= nil or e.auras[25288] ~= nil) and e.form == 2, "no window"
                end,
            },
        }, { hidden = { [5302] = true, [25288] = true, [25286] = true }, procs = {}, speed = 2.35 })
    end)
end)
