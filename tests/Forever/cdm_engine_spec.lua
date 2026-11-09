-- tests/Forever/cdm_engine_spec.lua (cdm-default plan Tasks 4b and 8; 4b review m4): the Cooldown Manager facts through
-- the whole engine, on the Arms loop world with the viewer arms' layouts (scenarios.viewerLayout): an item that flaps,
-- a layout re-mapped mid-fight, a target swap, refreshes before expiry one poll late (I-B) and D14's worst case. Each
-- compares a fight with the viewer to the same seed without it (or without the event), per tick.
local loop = require("Game.harness.loop")
local ww = require("Forever.helpers.warrior_world")

local ICON = "BuffIconCooldownViewer"
local DUR = 60

local function jOf(H, key)
    for j, a in ipairs(H.ns.VirtualStateInternal.def.auras) do
        if a.key == key then
            return j
        end
    end
end

-- the layout's item for aura j in the Buff icon viewer (scenarios' buffs preset: one an aura)
local function itemOf(H, j)
    local ctl, ids = H.ctl, H.ns.VirtualStateInternal.def.auraIds[j]
    for _, item in ipairs(ctl.viewer.items[ICON]) do
        local info = item.base and ctl.viewer.infos[item.base]
        if info and info.spellID == ids[1] then
            return item
        end
    end
end

-- Is aura j up in the world's truth on `e` at world time t (any rank the pack names)?
local function truth(e, ids, t)
    for _, id in ipairs(ids) do
        local a = e and e.auras[id]
        if a and a.stacks > 0 and (a.expires == 0 or a.expires > t + 1e-6) then
            return id
        end
    end
end

-- One DUR s fight of `seed` on a fresh boot of `content`, ours driving alone, under `arm`; `act(H, t)` after each tick.
-- Per in-combat tick: our first icon and, for each tracked { key, unit }, the belief's presence; counted over every
-- tick: wrong DOWN (the world has it up on our current target or us, the belief not) and false UP (the reverse).
local function fight(arm, seed, keys, act, content)
    local L = loop.new(content or ww)
    local r = { ours = {}, up = {}, wrongDown = 0, falseUp = 0, refresh = 0 }
    local js
    local run = loop.run(L, seed, {
        duration = DUR,
        arm = arm,
        on = function(run, steps, t)
            local H = steps[1].H
            local I, VS = H.ns.VirtualStateInternal, H.ns.VirtualState
            if not js then
                js = {}
                for i, k in ipairs(keys) do
                    js[i] = jOf(H, k[1])
                end
            end
            if act then
                act(H, t)
            end
            if t < 3.5 then -- the pull's first poll: both sides start from the client's plain answers
                return
            end
            local now = steps[1].base + t
            local first = H.Hekili.Engine.Output.Primary.recs[1]
            r.ours[#r.ours + 1] = first and first.actionName or false
            for i, k in ipairs(keys) do
                local ids = I.def.auraIds[js[i]]
                local e = k[2] == "player" and run.us or run.us.target
                local id = truth(e, ids, t)
                local believed = false
                for _, x in ipairs(ids) do
                    believed = believed or VS.Aura(k[2], x, now) ~= nil
                end
                r.up[#r.up + 1] = believed
                if id and not believed then
                    r.wrongDown = r.wrongDown + 1
                elseif believed and not id then
                    r.falseUp = r.falseUp + 1
                end
            end
        end,
    }, { { H = L.us } })
    assert.are.same({ 0, 0 }, { run.errors, run.raises })
    local held = {} -- refreshes before expiry: an aura applied again while it was up
    for _, ev in ipairs(run.W.truth) do
        if ev.kind == "aura" then
            local key = tostring(ev.dst) .. ev.aura
            if ev.stacks > 0 and held[key] and held[key] > ev.t then
                r.refresh = r.refresh + 1
            end
            held[key] = ev.stacks > 0 and ev.expires or nil
        end
    end
    r.H = L.us
    return r
end

local FLIP =
    "DEFECT %s NO LONGER REPRODUCES: the belief was fixed? Flip this test to assert the fixed behaviour (cdm-task8-report.md)"
local KEYS = { { "battle_shout", "player" }, { "rend", "target" }, { "sunder_armor", "target" } }

describe("Cooldown Manager facts through the engine #slow", function()
    it("an item that flaps (released, back from the pool) during one record changes nothing", function()
        local flapped = 0
        local function flap(H, t)
            local item = itemOf(H, jOf(H, "battle_shout"))
            local n = math.floor(t * 5 + 0.5) -- the tick: every 2 s from 20 s released, back 0.6 s later
            if n >= 100 and n < 200 and n % 10 == 0 and item.cooldownID then
                flapped = flapped + (item.auraInstanceID ~= nil and 1 or 0) -- a held item goes
                H.ctl.ViewerRelease(item)
            elseif n % 10 == 3 and not item.cooldownID then
                H.ctl.ViewerAcquire(ICON, item.base, nil, item)
            end
        end
        for _, seed in ipairs({ 1, 2 }) do
            local base = fight("viewer-buffs", seed, KEYS)
            local f = fight("viewer-buffs", seed, KEYS, flap)
            assert.are.same(base.ours, f.ours) -- the recommendation never moved
            assert.are.same(base.up, f.up) -- nor any belief
        end
        assert.is_true(flapped > 0, "no held item flapped")
    end)

    it("a re-map mid-fight: the old aura's belief stays (UNKNOWN), the re-pointed item follows the new aura", function()
        local Q, follows, keeps, wasUp = nil, 0, 0, nil
        local function remap(H, t)
            local I = H.ns.VirtualStateInternal
            local js, jr = jOf(H, "battle_shout"), jOf(H, "rend")
            local item, rend = itemOf(H, js), itemOf(H, jr)
            Q = I.PRESENCE.viewer
            local n = math.floor(t * 5 + 0.5)
            if n == 100 then
                wasUp = H.ns.VirtualState.Aura("player", I.def.auraIds[js][1], H.ctl.now) ~= nil
                H.ctl.ViewerRepoint(item, rend.base)
            elseif n > 101 and n < 150 then
                local P = I.presence
                assert.are.equal(I.UNDECIDED, P.Presence(js, 1), t) -- no item for it now: UNKNOWN
                local up = false
                for _, x in ipairs(I.def.auraIds[js]) do
                    up = up or H.ns.VirtualState.Aura("player", x, H.ctl.now) ~= nil
                end
                keeps = keeps + ((up == wasUp) and 1 or 0)
                local _, nUp = Q.Counts(jr, 2)
                follows = follows + (nUp == 2 and 1 or 0) -- Rend up: both items hold it
            end
        end
        fight("viewer-buffs", 1, KEYS, remap)
        assert.is_true(wasUp, "Battle Shout was not believed up at the re-map")
        assert.are.equal(48, keeps) -- every tick of 20.4-29.8: the belief kept
        assert.is_true(follows > 0, "the re-pointed item never held Rend")
    end)

    -- two mobs; our target goes to mob 2 at 25 s and back to mob 1 at 40 s
    local function swaps()
        local world = setmetatable({ extraMobs = 1, switchTo = { { 25, 2 }, { 40, 1 } } }, { __index = ww.WORLD })
        return setmetatable({ WORLD = world }, { __index = ww })
    end

    it("a target swap: the viewer adds no wrong DOWN on the new or the old mob", function()
        for _, seed in ipairs({ 1, 2, 3 }) do
            local off = fight("default", seed, KEYS, nil, swaps())
            local on = fight("viewer-buffs", seed, KEYS, nil, swaps())
            local msg = ("seed %d wrong DOWN %d > %d"):format(seed, on.wrongDown, off.wrongDown)
            assert.is_true(on.wrongDown <= off.wrongDown, msg)
        end
    end)

    -- CDM Task 8 FINDING F1 (cdm-task8-report.md), fixed by the owner's rule (L310): back on mob 1 at 40 s, the item
    -- re-read gave fact.t 40.2 (4b's I1 reset), and the 4b hold re-staged our old Sunder Armor (applied 18.6) near its
    -- end at 48.6 from 40.2 for a full 30 s; its NONE could not close it (`ours` did not survive the swaps): seed 2, 72
    -- ticks of false UP, 0 with the viewer off. Under the rule the model's expiry stands: no re-stage near it.
    it("F1: a target swap back adds no false UP on the mob we return to (seed 2)", function()
        local off = fight("default", 2, KEYS, nil, swaps())
        local on = fight("viewer-buffs", 2, KEYS, nil, swaps())
        assert.is_true(on.falseUp <= off.falseUp, ("false UP %d vs %d off"):format(on.falseUp, off.falseUp))
    end)

    -- CDM Task 8 FINDING F3 (cdm-task8-report.md): a CDM UP staged in the drain of our cast's write replaced the
    -- cast's expiry with HOLD for an aura whose pack duration is a function (Corruption, `duration =
    -- corruptionDuration`), re-staged near 1 s all fight. SM Ruin seed 1: believed remaining at 3.6 s >= 17 (truth 17.8),
    -- and over the first 14 s the believed remaining time of Corruption and of Immolate (numeric 15 s, the control)
    -- is the viewer-off run's.
    it("F3: a CDM UP in our cast's drain keeps the cast's expiry (SM Ruin seed 1: Corruption, Immolate)", function()
        local w = require("Forever.helpers.warlock_world")
        local function remains(arm)
            local L = loop.new(w.SMRuin)
            local out = {}
            loop.run(L, 1, {
                duration = 15,
                arm = arm,
                on = function(_, steps, t)
                    local H = steps[1].H
                    local I, VS = H.ns.VirtualStateInternal, H.ns.VirtualState
                    local now = steps[1].base + t
                    for _, key in ipairs({ "corruption", "immolate" }) do
                        local j = jOf(H, key)
                        local r = false
                        for _, id in ipairs(I.def.auraIds[j]) do
                            if VS.Aura("target", id, now) then
                                r = I.auras.exp0[I.auras.index.target][j] - now
                            end
                        end
                        out[("%s %.1f"):format(key, t)] = r
                    end
                end,
            }, { { H = L.us } })
            return out
        end
        local off, on = remains("default"), remains("viewer-buffs")
        local at = on["corruption 3.6"]
        assert.is_true(at and at >= 17, "believed Corruption remaining at 3.6 s: " .. tostring(at))
        local n = 0
        for k, r in pairs(off) do
            local s = on[k]
            if r then
                n = n + 1
            end
            assert.is_true(
                r == s or (r and s and math.abs(r - s) < 1e-6),
                ("%s: %s on vs %s off"):format(k, tostring(s), tostring(r))
            )
        end
        assert.is_true(n > 20, "too few believed-up ticks: " .. n)
    end)

    -- Not a D14 test (review m2): the faithful fake keeps a refresh held, so REFRESH_LAG is never exercised here (a
    -- mutation removing it passes); the worst-case shape below is the D14 one.
    it(
        "refreshes before expiry, the item one poll late (I-B, not D14): no wrong DOWN the model alone does not make",
        function()
            local function lag(H)
                H.ctl.viewer.lag = 1
            end
            local refreshed = 0
            for _, seed in ipairs({ 1, 2, 3 }) do
                local off = fight("default", seed, KEYS)
                local on = fight("viewer-buffs", seed, KEYS, lag)
                refreshed = refreshed + on.refresh
                local msg = ("seed %d wrong DOWN %d > %d"):format(seed, on.wrongDown, off.wrongDown)
                assert.is_true(on.wrongDown <= off.wrongDown, msg)
            end
            assert.is_true(refreshed > 0, "no refresh before expiry in the fights")
        end
    )

    -- D14's window, the worst case: under lag (I-B) a refresh's light lands a poll late, and here its clear lands at once
    -- (the client's pair is one call, BD:368-380, so the fake keeps a refresh held; this wraps it to show the one-poll
    -- silence D14's REFRESH_LAG guards). Each refresh of ours before expiry: a NONE at the next sweep, after our cast.
    -- CDM Task 8 FINDING F2 (cdm-task8-report.md), pinned as PRESENT (review m1): the guard compares the fact's last UP with the record's
    -- APPLICATION (oursAp), and a refresh that keeps its application time (Sunder Armor's stack) moves neither, so the
    -- NONE closes for a poll at every such refresh (seed 1: 13 wrong-DOWN ticks vs 4 viewer off, the same with the
    -- guard removed). Only a client that shows the refresh's clear a poll before its set reaches it (the fake does not).
    it(
        "KNOWN DEFECT F2: D14 worst case, a refresh's item silent for a poll closes the record (seed 1; flip when fixed)",
        function()
            local VIEWERS = require("Game.State.helpers.fake_api").VIEWERS
            local function worst(H)
                local ctl = H.ctl
                ctl.viewer.lag = 1
                if ctl.viewer.d14 then
                    return
                end
                local by = ctl.ViewerAuraBySpell
                ctl.viewer.d14 = by
                ctl.ViewerAuraBySpell = function(unit, id, up, src)
                    for _, name in ipairs(up and src == "player" and VIEWERS or {}) do
                        for _, item in ipairs(ctl.viewer.items[name]) do
                            if item.auraInstanceID ~= nil and item.litBy == id and item.litUnit == unit then
                                ctl.ViewerClear(item)
                            end
                        end
                    end
                    return by(unit, id, up, src)
                end
            end
            local off = fight("default", 1, KEYS)
            local on = fight("viewer-buffs", 1, KEYS, worst)
            assert.is_true(on.refresh > 0, "no refresh before expiry in the fight")
            local msg = ("%s (wrong DOWN %d vs %d off)"):format(FLIP:format("F2"), on.wrongDown, off.wrongDown)
            assert.is_true(on.wrongDown > off.wrongDown, msg)
        end
    )
end)
