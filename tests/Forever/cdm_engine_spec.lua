-- tests/Forever/cdm_engine_spec.lua (cdm-default plan Tasks 4b and 8; 4b review m4): the Cooldown Manager facts through
-- the whole engine, on the Arms loop world with the viewer arms' layouts (scenarios.viewerLayout): an item that flaps,
-- a layout re-mapped mid-fight, a target swap, and refreshes before expiry with the item one poll late (D14, I-B). Each
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

    -- CDM Task 8 FINDING F1 (cdm-task8-report.md), a belief defect this harness found, kept visible as pending until a
    -- belief task fixes it: back on mob 1 at 40 s, the item re-read gives fact.t 40.2 (4b's I1 reset), so near the end of
    -- our old Sunder Armor (applied 18.6) the hold re-stages it from 40.2 for a full 30 s (est 70.2), and the item's NONE
    -- at 48.6 cannot close it (`ours` did not survive the swaps): seed 2, 72 ticks of false UP, 0 with the viewer off.
    pending(
        "a target swap: the viewer adds no false UP on the mob we come back to (F1: fails at seed 2, 72 > 0)",
        function()
            for _, seed in ipairs({ 1, 2, 3 }) do
                local off = fight("default", seed, KEYS, nil, swaps())
                local on = fight("viewer-buffs", seed, KEYS, nil, swaps())
                assert.is_true(
                    on.falseUp <= off.falseUp,
                    ("seed %d false UP %d > %d"):format(seed, on.falseUp, off.falseUp)
                )
            end
        end
    )

    it("refreshes before expiry, the item one poll late (I-B): no wrong DOWN the model alone does not make", function()
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
    end)

    -- D14's window, the worst case: under lag (I-B) a refresh's light lands a poll late, and here its clear lands at once
    -- (the client's pair is one call, BD:368-380, so the fake keeps a refresh held; this wraps it to show the one-poll
    -- silence D14's REFRESH_LAG guards). Each refresh of ours before expiry: a NONE at the next sweep, after our cast.
    -- CDM Task 8 FINDING F2 (cdm-task8-report.md), pending: the guard compares the fact's last UP with the record's
    -- APPLICATION (oursAp), and a refresh that keeps its application time (Sunder Armor's stack) moves neither, so the
    -- NONE closes for a poll at every such refresh (seed 1: 13 wrong-DOWN ticks vs 4 viewer off, the same with the
    -- guard removed). Only a client that shows the refresh's clear a poll before its set reaches it (the fake does not).
    pending(
        "refreshes before expiry, the item one poll late and silent between (D14): no wrong DOWN the model alone does not make",
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
            local refreshed = 0
            for _, seed in ipairs({ 1, 2, 3 }) do
                local off = fight("default", seed, KEYS)
                local on = fight("viewer-buffs", seed, KEYS, worst)
                refreshed = refreshed + on.refresh
                local msg = ("seed %d wrong DOWN %d > %d"):format(seed, on.wrongDown, off.wrongDown)
                assert.is_true(on.wrongDown <= off.wrongDown, msg)
            end
            assert.is_true(refreshed > 0, "no refresh before expiry in the fights")
        end
    )
end)
