-- tests/Game/harness/drive.lua (harness design §3.1): boots VirtualState on fake_api and the fake spec as
-- pairing_replay_spec does, fires an observed stream through `ctl`, ticks and folds every TICK seconds, and captures
-- what the addon concluded: each `Swing` c = 1 / c = 3 staged (through an S.Stage wrapper, tagged with the stream event
-- being fired), the combat-log rows (a COMBAT_LOG_EVENT_UNFILTERED sink), the believed rage at each 10 s window, each
-- tracked power type's believed value at every tick, each GCD as GcdInfo first answered it, and per stream index the
-- crits staged and the white wounds Rows.lua would score on timing alone (its stale-form test mirrored here, not its
-- path captured: a wound it skipped for another reason still counts). The run loop allocates
-- nothing: the stream and every capture array are built before it.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local COSTS = require("Game.harness.observer").COSTS

local M = {}

M.TICK = 0.1 -- seconds between OnUpdate + drain (in game every frame; poll 2 at 0.2 s in combat)
M.WINDOW = 10 -- seconds per rage window (harness design §3.3)
M.STEP = 9 -- one main-hand step: the overshoot bar
local CAP = 4096

local USABLE, SHORT, UNUSABLE = { true, false }, { false, true }, { false, false }
local PLAIN_READY = { isActive = false, isOnGCD = false, startTime = 0, duration = 0 } -- a secret-free client's

--- A booted VirtualState: { api, ctl, ns, VS, I, L, captures }. `o.rage` { main, off } per landed swing [9, 5],
--- `o.max` the rage cap [1e6]; `o.damage` the UnitDamage cache's first values (default zeros: read at the pull);
--- `o.oracle == false` unregisters Rows' oracle hooks (the no-oracle run). `o.boot(c)`: the content builds the
--- definition and starts VirtualState itself (`c.ns`, `c.api`, `c.ctl`; default: the fake spec's, as today).
--- `o.track` { powerType... }: the types whose believed est and lo are captured at every tick (`c.trk[pt]`).
function M.boot(o)
    o = o or {}
    local api, ctl = fake.new()
    ctl.now = 0.1
    local c = { api = api, ctl = ctl, saved = {}, cur = 0 }
    for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
        c.saved[k] = rawget(_G, k) or false
        _G[k] = v
    end
    ctl.powerMax[fs.RAGE] = o.max or 1e6
    if o.damage then
        for i = 1, 4 do
            ctl.damage[i] = o.damage[i]
        end
    end
    local ns = load.module()
    c.ns, c.VS, c.I = ns, ns.VirtualState, ns.VirtualStateInternal
    c.L = c.I.Log
    if o.boot then
        o.boot(c)
    else
        local def = fs.def(fs.new((o.rage or { 9, 5 })[1]))
        def.resources[1].swingOff = (o.rage or { 9, 5 })[2]
        def.resources[1].max = o.max or 1e6
        c.I.Build(def, 0.1)
        c.VS.Start(api)
    end
    -- captures, by stream index: the hand credited and the swing time it was credited at (0: none)
    c.crHand, c.crAt, c.crTok, c.verdict, c.recIdx, c.onus = {}, {}, {}, {}, {}, {}
    c.lateHand, c.lateAt = {}, {} -- credits staged outside an event (the oracle's rescue)
    c.missHand, c.missAt = {}, {} -- the SWING_MISSED rows (hand, swing time): avoids credited to our swings
    c.avIdx, c.avHand, c.avAt = {}, {}, {} -- each provisional avoid taken: its stream index and the swing's hand, time
    c.win, c.winT, c.loOver, c.estOver, c.danger = {}, {}, {}, {}, {}
    for i = 1, CAP do
        c.crHand[i], c.crAt[i], c.crTok[i], c.lateHand[i], c.lateAt[i], c.win[i], c.winT[i] = 0, 0, false, 0, 0, 0, 0
        c.missHand[i], c.missAt[i], c.avIdx[i], c.avHand[i], c.avAt[i] = 0, 0, 0, 0, 0
        c.loOver[i], c.estOver[i], c.danger[i] = 0, 0, 0
        c.verdict[i], c.onus[i] = 0, ""
    end
    for k = 1, 8 do
        c.recIdx[k] = 0
    end
    c.crit3, c.unk = {}, {} -- by stream index: a c = 3 staged at it; a white wound of ours scored on timing alone
    for i = 1, CAP do
        c.crit3[i], c.unk[i] = 0, 0
    end
    c.trk = {} -- [pt] = { n, t[], est[], lo[] } per tick
    for _, pt in ipairs(o.track or {}) do
        local r = { n = 0, t = {}, est = {}, lo = {} }
        for i = 1, CAP do
            r.t[i], r.est[i], r.lo[i] = 0, 0, 0
        end
        c.trk[pt] = r
    end
    -- each GCD GcdInfo answered: its start and end, and whether an opener owned it at that tick
    c.gcdN, c.gcdS, c.gcdE, c.gcdOwned = 0, {}, {}, {}
    for i = 1, CAP do
        c.gcdS[i], c.gcdE[i], c.gcdOwned[i] = 0, 0, 0
    end
    c.crits, c.landed = { 0, 0 }, { 0, 0 }
    c.rows = { swing = 0, missed = 0, spell = 0, noDst = 0, order = 0 }
    c.lastRow = { 0, 0 }
    local S, Swing = c.I.Sources, c.VS.Obs.Swing
    local stage = S.Stage
    c.stream = nil
    c.I.On(c.VS.Obs.PlayerHit, function() -- every hit on us reaches the belief, attributed or not
        c.hits = c.hits + 1
    end)
    S.Stage = function(kind, t, a, b, cc)
        if kind == Swing and (cc == 1 or cc == 3) then
            local i = c.cur
            if cc == 3 then
                c.crits[a] = c.crits[a] + 1
                if i > 0 then
                    c.crit3[i] = c.crit3[i] + 1
                end
            elseif i > 0 then
                c.landed[a] = c.landed[a] + 1
                c.crHand[i], c.crAt[i], c.crTok[i] = a, t, c.stream.a1[i] == "target"
                if b >= 1 and b <= 8 then
                    c.recIdx[b] = i
                end
            end
        end
        return stage(kind, t, a, b, cc)
    end
    -- the oracle's verdicts by stream index (1 confirmed, 2 retracted, 3 soft) and its rescues (hand, swing time)
    local verdict, rescue = c.I.CreditVerdict, c.I.Rescue
    if o.oracle == false then
        c.I.CreditVerdict, c.I.Rescue = nil, nil
    elseif verdict then
        c.I.CreditVerdict = function(id, ok, t, firm)
            local v = verdict(id, ok, t, firm)
            local i = c.recIdx[id]
            if v and i > 0 then
                c.verdict[i] = ok and 1 or (firm and 2 or 3)
            end
            return v
        end
        c.I.Rescue = function(r, need, since, t)
            local h, crit, at = rescue(r, need, since, t)
            if h then
                c.landed[h] = c.landed[h] + 1
                c.nLate = c.nLate + 1
                c.lateHand[c.nLate], c.lateAt[c.nLate] = h, at
            end
            return h, crit, at
        end
    end
    local GetInfo = ns.Facade.CombatLogGetCurrentEventInfo
    local sink = c.I.Events.CreateFrame("Frame")
    local rows, last = c.rows, c.lastRow
    sink:SetScript("OnEvent", function()
        local t, ev, _, src, _, _, _, dst, _, _, _, a12, a13, _, _, _, _, _, _, _, a21 = GetInfo()
        if src ~= "Player-1" then
            if dst == "Player-1" and c.cur > 0 then
                c.onus[c.cur] = src -- a hit on us credited to an attacker
            end
            return
        end
        if dst == "" then
            rows.noDst = rows.noDst + 1
        end
        local hand = 0
        if ev == "SWING_DAMAGE" then
            rows.swing, hand = rows.swing + 1, a21 and 2 or 1
        elseif ev == "SWING_MISSED" then
            rows.missed, hand = rows.missed + 1, a13 and 2 or 1
            if rows.missed <= CAP then
                c.missHand[rows.missed], c.missAt[rows.missed] = hand, t
            end
        elseif ev == "SPELL_DAMAGE" or ev == "SPELL_MISSED" then
            rows.spell = rows.spell + 1
        end
        if hand > 0 then
            if t < last[hand] then
                rows.order = rows.order + 1
            end
            last[hand] = t
        end
    end)
    sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    c.nLate, c.nWin, c.truth, c.hits, c.nAv = 0, 0, 0, 0, 0
    return c
end

--- Puts back the globals the boot replaced.
function M.restore(c)
    for k, v in pairs(c.saved) do
        _G[k] = v or nil
    end
end

-- An aura list entry of `unit` (the player's helpful, the target's harmful), from the player. Allocates (headless
-- loop only: the 0-byte drives fire no aura).
local function aura(ctl, unit, id, stacks, expires, duration)
    local list = ctl.auras[unit][unit == "player" and "HELPFUL" or "HARMFUL"]
    for i, a in ipairs(list) do
        if a.spellId == id then
            if stacks == 0 then
                table.remove(list, i)
            else
                a.applications, a.expirationTime, a.duration = stacks, expires, duration
            end
            return
        end
    end
    if stacks > 0 then
        list[#list + 1] = {
            name = "Aura " .. id,
            icon = 0,
            spellId = id,
            applications = stacks,
            duration = duration,
            expirationTime = expires,
            sourceUnit = "player",
            isFromPlayerOrPlayerPet = true,
        }
    end
end

--- One client-answer change (or the truth's power for the metrics) on `ctl`; `c.truth` takes `@truth`. Allocates
--- nothing. The headless loop applies its streams' ops through this too.
local function op(c, ctl, ev, a1, a2, a3, a4, a5)
    if ev == "@truth" then
        c.truth = a1
    elseif ev == "@damage" then
        ctl.damage[1], ctl.damage[2], ctl.damage[3], ctl.damage[4] = a1, a2, a3, a4
    elseif ev == "@usable" then
        ctl.usable[a1] = a2 == 1 and USABLE or (a2 == 2 and SHORT or UNUSABLE)
    elseif ev == "@form" then
        ctl.form = a1
    elseif ev == "@guid" then
        ctl.guid[a1] = a2
    elseif ev == "@unitIs" then
        ctl.unitIs[a1] = a2
    elseif ev == "@speed" then
        ctl.unitSpeed[a1] = a2
    elseif ev == "@combat" then
        ctl.combat = a1
    elseif ev == "@auraError" then
        ctl.auraError[a1] = a2 or nil
    elseif ev == "@current" then
        ctl.current[a1] = a2 or nil
    elseif ev == "@dead" then
        ctl.dead[a1] = a2 or nil
    elseif ev == "@aura" then -- unit, spellID, stacks (0: gone), expires, duration: ours, from the player
        aura(ctl, a1, a2, a3, a4, a5)
    elseif ev == "@power" then
        ctl.power[a1] = a2
    elseif ev == "@health" then
        ctl.unitHealth[a1], ctl.unitHealthMax[a1] = a2, a3
    elseif ev == "@cooldown" then -- spellID, start, duration: on cooldown; start 0: ready (plain); nil: ready (secret)
        if a2 == nil then
            ctl.cooldown[a1] = nil
        elseif a2 == 0 then
            ctl.cooldown[a1] = PLAIN_READY
        else
            ctl.cooldown[a1] = { isActive = true, isOnGCD = false, startTime = a2, duration = a3 }
        end
    elseif ev == "@forms" then -- the client's forms, index to spell ID (the content's list)
        ctl.forms = a1
    elseif ev == "@regen" then -- powerType, the rate (nil: secret); allocates (no 0-byte drive fires one)
        ctl.regen[a1] = a2 and { a2, a2 } or nil
    elseif ev == "@attackSpeed" then -- the player's main and off hand
        ctl.speed[1], ctl.speed[2] = a1, a2
    end
end

M.op = op

local function tick(c, t)
    c.ctl.Tick(t)
    fs.fold(c.ns, t)
    local p = c.VS.Power(fs.RAGE, t)
    if t >= c.nextWin then
        c.nWin = c.nWin + 1
        c.win[c.nWin], c.winT[c.nWin], c.loOver[c.nWin] = p.est, t, 0
        c.estOver[c.nWin], c.danger[c.nWin] = 0, 0
        c.nextWin = c.nextWin + M.WINDOW
    end
    if c.nWin > 0 and p.lo - c.truth >= M.STEP then
        c.loOver[c.nWin] = 1 -- the dangerous sign: the floor a step above the true power
    end
    if c.nWin > 0 and p.est - c.truth >= M.STEP then
        c.estOver[c.nWin] = 1
    end
    for i = 1, c.nWin > 0 and #COSTS or 0 do -- a spender believed affordable that the true power cannot pay
        local cost = COSTS[i][2]
        if p.lo >= cost and c.truth < cost then
            c.danger[c.nWin] = 1
        end
    end
    for pt, r in pairs(c.trk) do
        if r.n < CAP then
            local b = c.VS.Power(pt, t)
            local n = r.n + 1
            r.n, r.t[n], r.est[n], r.lo[n] = n, t, b.est, b.lo
        end
    end
    -- the read engages the belief's claim guard (I.gcdRead), as Hekili's read every frame does in game
    local gs, gd = c.VS.GcdInfo(t)
    if gs > 0 and gs ~= c.gcdS[c.gcdN] and c.gcdN < CAP then
        local n = c.gcdN + 1
        c.gcdN, c.gcdS[n], c.gcdE[n], c.gcdOwned[n] = n, gs, gs + gd, c.I.gcdOwner > 0 and 1 or 0
    end
end

--- Fires stream `s` (observer.lua) through the booted VirtualState, `offset` seconds later than its times (a replay
--- on the same boot), ticking every TICK seconds, then 3 s past its end. The captures (crHand/crAt by stream index,
--- crits, landed, rows, win) are reset first. Allocates nothing.
function M.run(c, s, offset)
    offset = offset or 0
    assert(s.n <= CAP, "stream longer than the preallocated captures")
    local ctl = c.ctl
    c.stream = s
    for i = 1, s.n do
        c.crHand[i], c.crAt[i], c.verdict[i], c.onus[i], c.crit3[i], c.unk[i] = 0, 0, 0, "", 0, 0
    end
    for _, r in pairs(c.trk) do
        r.n = 0
    end
    c.gcdN = 0
    c.hits = 0
    c.crits[1], c.crits[2], c.landed[1], c.landed[2], c.nLate, c.nWin, c.truth, c.nAv = 0, 0, 0, 0, 0, 0, 0, 0
    local rows = c.rows
    rows.swing, rows.missed, rows.spell, rows.noDst, rows.order = 0, 0, 0, 0, 0
    c.lastRow[1], c.lastRow[2] = 0, 0
    local nextTick = M.TICK * math.floor((s.t[1] + offset) / M.TICK) + M.TICK
    c.nextWin = nextTick
    for i = 1, s.n do
        local t = s.t[i] + offset
        while nextTick < t do
            tick(c, nextTick)
            nextTick = nextTick + M.TICK
        end
        ctl.now = t
        local ev = s.ev[i]
        if ev:byte(1) == 64 then -- "@"
            op(c, ctl, ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
        else
            c.cur = i
            if ev == "UNIT_COMBAT" and s.src[i] == 1 and s.hand[i] > 0 and s.a1[i] == "target" and s.a4[i] > 0 then
                local _, maxMain = c.VS.Stat("UnitDamage") -- Rows.lua's stale-form test, as it reads it now
                c.unk[i] = (maxMain <= 0 or ctl.form ~= c.I.damageForm) and 1 or 0
            end
            local avoids = c.L.avoids
            ctl.Fire(ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
            if c.L.avoids > avoids and c.nAv < CAP then
                c.nAv = c.nAv + 1
                c.avIdx[c.nAv], c.avHand[c.nAv], c.avAt[c.nAv] = i, c.L.avoidX, c.L.avoidT
            end
            c.cur = 0
        end
    end
    local stop = s.t[s.n] + offset + 3
    while nextTick <= stop do
        tick(c, nextTick)
        nextTick = nextTick + M.TICK
    end
end

--- A fixture (fixtures/logN.lua) as a stream: its rows from `base` seconds, the cache read out of combat first.
--- `dedupe`: one row per outcome on the target, fed as "target" (the research doc's table: the target-side tokens of
--- one outcome within 1 ms collapse; an outcome only seen on a nameplate or soft token counts). Our casts as the fake
--- spec's (STRIKE, DOT), other spell IDs as 1; a secret ID as fake_api's SECRET.
function M.fixtureStream(fix, base, dedupe)
    local s = { n = 0, t = {}, ev = {}, a1 = {}, a2 = {}, a3 = {}, a4 = {}, a5 = {}, src = {}, hand = {}, swingT = {} }
    local function push(t, ev, a1, a2, a3, a4, a5)
        local n = s.n + 1
        s.n = n
        s.t[n], s.ev[n], s.a1[n], s.a2[n], s.a3[n], s.a4[n], s.a5[n] = t, ev, a1, a2, a3, a4, a5
        s.src[n], s.hand[n], s.swingT[n] = 0, 0, 0
    end
    local d = fix.damage
    push(base - 1, "@damage", d[1], d[2], d[3], d[4])
    push(base - 1, "PLAYER_EQUIPMENT_CHANGED")
    local IDS = { STRIKE = fs.SPENDER_B, DOT = fs.SPENDER_C, OTHER = 1, SECRET = fake.SECRET }
    local TARGET_SIDE = { target = true, softenemy = true, softinteract = true }
    local last = {}
    for _, r in ipairs(fix.rows) do
        local t = base + r[1] / 1000
        if r[2] == "S" then
            push(t, "PLAYER_SWING", r[3], r[4])
        elseif r[2] == "C" then
            push(t, "UNIT_SPELLCAST_SUCCEEDED", r[3], r[4] == "SECRET" and fake.SECRET or "Cast", IDS[r[4]])
        else
            local unit = r[3]
            if dedupe and (TARGET_SIDE[unit] or unit:match("^nameplate")) then
                local key = r[4] .. r[5] .. r[6] .. "/" .. r[7]
                if not (last.key == key and r[1] - last.ms <= 1) then
                    push(t, "UNIT_COMBAT", "target", r[4], r[5], r[6], r[7])
                end
                last.key, last.ms = key, r[1]
            elseif not dedupe then
                push(t, "UNIT_COMBAT", unit, r[4], r[5], r[6], r[7])
            end
        end
    end
    return s
end

return M
