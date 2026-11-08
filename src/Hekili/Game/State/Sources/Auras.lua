-- Game/State/Sources/Auras.lua
-- Aura sources (spec §4.5): one C_UnitAuras.GetAuraDataByIndex walk per tracked unit per UNIT_AURA, helpful then
-- harmful, each call pcall'd; the walk stops at the first error, secret or nil (in combat that is one call per
-- filter). Entries whose spellId is tracked become `Read` observations straight to the log (remaining time, stacks).
-- After a complete walk, a believed-up aura it did not find is logged down, but in combat only once that aura was
-- seen readable in combat (before that, a miss may be the client hiding it). Combat's end queues one more walk (poll 10).
-- A player aura with `overlay = spellID` (C2) is also read from C_SpellActivationOverlay.IsSpellOverlayed (poll 11)
-- while the player walk is secret or stopped: on is a `Read` with no expiry, off a `Read` down.
-- Credits: the pcall-then-issecretvalue handling and the "seen readable in combat" rule follow Catnip's (Durts)
-- secret-value research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Auras.lua (:42, :58-61, :74, :148).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, ReadOf = VS.Obs, I.ReadOf
local Plain, Direct, Note = S.Plain, S.Direct, S.Note
local HUGE = math.huge

-- A safety cap: the walk stops at the first empty slot, so the cap costs nothing; a unit with more auras than the cap
-- in one filter would hide a tracked aura past it.
local SCAN = 128
local FILTERS = { "HELPFUL", "HARMFUL" }
-- The walk status per unit index ("aura walk <unit>", built at OnBuild for every tracked unit), so Snapshot tells
-- them apart.
local WALK = {}

-- By unit index and aura index: the walk serial that last found it, and whether it was seen plain in combat.
local found, seen = {}, {}
local serial = 0
-- Set when combat ends: the belief's in-combat down-states stand until a plain walk, and no UNIT_AURA comes while the
-- buffs stay unchanged.
local pending = false
-- Whether the last player walk completed (plain): then it wins over the overlay reads, except that a permanent aura with
-- `overlay` still goes down while its glow is off.
local playerPlain = true
local targetPlain = true -- its twin for the target's walk (presence, providers decision 80)
-- The player auras with a numeric `overlay`: their aura indices and overlay spell IDs (built at OnBuild).
local OVL_J, OVL_ID, OVL_N = {}, {}, 0
-- The per-aura presence audit (providers spec §4.3, decision 90), keyed (u - 1) * AURA_UNIT + j for the player and the
-- target: the provider's facts the consumer took and those that contradicted the belief. Preallocated at OnBuild,
-- zeroed at each fight's start.
local facts, disagree = {}, {}
-- By the same key: the time of the last Read staged (the drain's fold takes it), 0 none. Only a second stage in the
-- same drain (an edge, then the poll) is held back: a hold re-stage can be due at two polls in a row.
local staged = {}
-- By the same key: 1 when the first plain walk after combat corrected the believed presence (spec §2.6, decision 105),
-- per fight. At most one count per key: exp0 moves only at the fold, so every walk of the exit frame (a UNIT_AURA one,
-- then poll 10's) sees the same stale belief.
local exitFix = {}
local exiting = false -- from PLAYER_REGEN_ENABLED until poll 10's walk completes
I.presenceFacts, I.presenceDisagree, I.auraExitFix = facts, disagree, exitFix
local KEY = {} -- aura index -> its key, for the Snapshot lines
-- Who opened the record's current application (cdm-default rule 2.5.1, decision 111), by the same key: ours[k] 0 none,
-- BY_CAST our cast (Families/Now.lua, I.AuraOurs), BY_CDM a CDM UP that opened it, BY_WALK an out-of-combat walk read with source
-- player or pet; valid only while the record's applied time is still oursAp[k] (another application, a target swap's
-- other mob, an undone cast or a close all move it). upAt[k]: the last poll the reduced fact read UP.
local BY_CAST, BY_CDM, BY_WALK = 1, 2, 3
local ours, oursAp, upAt = {}, {}, {}
I.auraOurs = ours
-- Rule 4 (C2, decision 112): a CDM UP with no model behind it runs its registered duration (DUR[j], -1 none) from
-- max(fact.t, applied), then holds HOLD, re-staged when it would lapse before the slowest in-combat drain (LAPSE,
-- Engine/Driver.lua restRate's 0.5 s): about every HOLD - LAPSE while the fact stays UP, never per poll.
-- shortcut: HOLD 1.0 s is a guess (spec D9); Task 9's target-DoT-past-duration row measures it.
local HOLD, LAPSE = 1.0, 0.5
-- D14: after our cast wrote an application, its NONE closes it only once the fact read UP REFRESH_LAG after the write: an
-- item still showing the old application inside the client's latency says nothing of the new one.
-- shortcut: 0.5 s is unmeasured; the LAT probe (cast success vs the item's light) sets it.
local REFRESH_LAG = 0.5
-- A hold re-stage of an `icd` aura moves its expiry by at most this (I.AURA_REFRESH less a float margin), so the fold
-- keeps the application (its ICD and applied time; ours stays valid).
local REFRESH_HOLD = I.AURA_REFRESH * 0.99
local DUR = {}
-- Decision 114: 1 while the player's reduced fact is UP, else 0 (CN13's Obs.PlayerHit keeps one stack while it is 1).
local floor = I.auraFloor or {}
I.auraFloor = floor
local floorSet = false -- some floor[j] is 1

I.OnBuild(function(def)
    local U = I.auras
    for u = 1, U.n do
        WALK[u] = "aura walk " .. tostring(def.units[u])
        local f, s = {}, {}
        for j = 1, U.nAura do
            f[j], s[j] = 0, false
        end
        found[u], seen[u] = f, s
    end
    OVL_N = 0
    for j = 1, U.nAura do
        local id = rawget(def.auras[j], "overlay")
        if type(id) == "number" then
            OVL_N = OVL_N + 1
            OVL_J[OVL_N], OVL_ID[OVL_N] = j, id
        end
    end
    playerPlain, targetPlain = true, true
    for j = 1, U.nAura do
        KEY[j] = tostring(def.auras[j].key)
        local d = rawget(def.auras[j], "duration")
        DUR[j], floor[j] = type(d) == "number" and d or -1, 0
        facts[j], disagree[j], staged[j], exitFix[j], ours[j], oursAp[j], upAt[j] = 0, 0, 0, 0, 0, 0, 0
        local k = I.AURA_UNIT + j
        facts[k], disagree[k], staged[k], exitFix[k], ours[k], oursAp[k], upAt[k] = 0, 0, 0, 0, 0, 0, 0
    end
    floorSet = false
    exiting = false -- a walk after a build finds every record cleared: no correction to count
    pending = true -- a build cleared every record: walk the player at the next out-of-combat poll 10 (gear-aware spec §2)
end)

-- The applied time a Read staged at t gives record (u, j) once folded: an up record keeps its own (Families/Auras.lua).
local function foldApplied(u, j, t)
    local U = I.auras
    if U.exp0[u][j] > 0 then
        return U.applied[u][j]
    end
    return t
end

-- One unit's walk at t; returns whether it completed. Allocates nothing (the client allocates its aura tables).
local function walk(api, u, unit, t)
    local U = I.auras
    serial = serial + 1
    local complete = true
    local count = exiting and u <= 2 and not I.inCombat
    for f = 1, #FILTERS do
        local filter = FILTERS[f]
        for i = 1, SCAN do
            local ok, raw = pcall(api.C_UnitAuras.GetAuraDataByIndex, unit, i, filter) -- secret: tested next
            if not ok then
                Note(WALK[u], "error")
                complete = false
                break
            elseif api.issecretvalue(raw) then
                Note(WALK[u], "secret")
                complete = false
                break
            end
            local data = Plain(api, raw)
            if not data then
                break
            end
            local id = Plain(api, data.spellId)
            if id == nil then
                complete = false
                Note(WALK[u], "secret")
                break
            end
            local j = U.bySpell[id]
            if j then
                local exp, apps = Plain(api, data.expirationTime), Plain(api, data.applications)
                if type(exp) ~= "number" then
                    complete = false
                    Note(WALK[u], "secret")
                    break
                end
                Note(WALK[u], "readable")
                local again = found[u][j] == serial -- a second entry of the same aura in this walk
                found[u][j] = serial
                if I.inCombat then
                    seen[u][j] = true
                end
                local stacks = type(apps) == "number" and apps or 0
                local remaining = exp > 0 and exp - t or -1
                if remaining > 0 or exp == 0 then
                    if count and exitFix[(u - 1) * I.AURA_UNIT + j] == 0 and U.exp0[u][j] <= t then
                        exitFix[(u - 1) * I.AURA_UNIT + j] = 1
                    end
                    local k = (u - 1) * I.AURA_UNIT + j
                    if u <= 2 and not I.inCombat then -- rule 2.5.1: its source says whose it is (out of combat only)
                        local src = Plain(api, data.sourceUnit)
                        if src == "player" or src == "pet" then
                            ours[k], oursAp[k] = BY_WALK, foldApplied(u, j, t)
                        elseif not (again and ours[k] == BY_WALK) then -- ours and a partner's in one walk: ours
                            ours[k] = 0
                        end
                    end
                    Direct(Obs.Read, t, k, remaining, ReadOf.Aura + stacks * I.AURA_STACK)
                    U.harm[u][j] = filter == "HARMFUL"
                end
            end
        end
        if not complete then
            break
        end
    end
    if complete then
        Note(WALK[u], "readable") -- a clean walk, even with no tracked aura up
        if U.firstWalk[u] == 0 then
            U.firstWalk[u] = t -- an aura up in this walk was gained before it (Families/Auras.lua's ICD)
        end
        local e = U.exp0[u]
        for j = 1, U.nAura do
            -- a form or stealth aura is left to its reads (Sources/Forms.lua), a weapon enchant to Sources/Enchants.lua
            if
                e[j] > 0
                and found[u][j] ~= serial
                and (not I.inCombat or seen[u][j])
                and not (u == 1 and (I.formAura[j] or I.enchantAura[j]))
            then
                if count and exitFix[(u - 1) * I.AURA_UNIT + j] == 0 and e[j] > t then -- lapsed by time: no change
                    exitFix[(u - 1) * I.AURA_UNIT + j] = 1
                end
                Direct(Obs.Read, t, (u - 1) * I.AURA_UNIT + j, 0, ReadOf.Aura)
            end
        end
    end
    if u == 1 then
        playerPlain = complete
    elseif u == 2 then
        targetPlain = complete
    end
    return complete
end
I.WalkAuras = walk

S.On("UNIT_AURA", nil, function(api, t, unit)
    local u = unit and I.built and I.auras.index[unit]
    if u then
        if u ~= 1 and Plain(api, api.UnitExists(unit)) ~= true then
            return
        end
        walk(api, u, unit, t)
    end
end)

S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    if not I.built then
        return
    end
    local U = I.auras
    for u = 1, U.n do
        for j = 1, U.nAura do
            seen[u][j] = false
        end
    end
    pending, exiting = true, true
end)

-- Poll 10 (after the form read, 9, so a walk's form-aura skip sees this frame's form): once combat has ended, walk the
-- player and an existing target again; retried each poll until the player walk completes.
S.Poll(10, function(api, t)
    if not pending or I.inCombat or not I.built then
        return
    end
    pending = not walk(api, 1, "player", t)
    if I.auras.n >= 2 and Plain(api, api.UnitExists("target")) == true then
        walk(api, 2, "target", t)
    end
    exiting = exiting and pending
end)

-- Poll 11: the overlay reads, while the player walk is secret or stopped. An overlay-read proc (no expiry) is still taken
-- down by its overlay going off after the walk turns plain, since an in-combat walk miss is no down. Allocates nothing.
S.Poll(11, function(api, t)
    if OVL_N == 0 or not I.built then
        return
    end
    local e = I.auras.exp0[1]
    for k = 1, OVL_N do
        local j = OVL_J[k]
        local ok, raw = pcall(api.C_SpellActivationOverlay.IsSpellOverlayed, OVL_ID[k]) -- secret: Plain next (plain [W PR11])
        local on = nil
        if ok then
            on = Plain(api, raw)
        end
        if on == true and not playerPlain and e[j] <= t then
            Direct(Obs.Read, t, j, -1, ReadOf.Aura)
        elseif on == false and e[j] > t and (not playerPlain or e[j] == HUGE) then
            -- shortcut: a glow not yet lit in the frame of the cast that procs it drops the proc; upgrade by skipping reads within I.SAME_FRAME of our cast
            Direct(Obs.Read, t, j, 0, ReadOf.Aura)
        end
    end
end)

--- Our cast wrote record (u, j) (Families/Now.lua's aura()): this application is ours (rule 2.5.1). Allocates nothing.
function I.AuraOurs(u, j)
    if u <= 2 then
        local k = (u - 1) * I.AURA_UNIT + j
        ours[k], oursAp[k] = BY_CAST, I.auras.applied[u][j]
    end
end

-- Rule 4's remaining for an UP of (j, u) at t (decision 112): never math.huge on the target or with a duration.
local function hold(j, u, k, t)
    local F = I.presence.fact
    local ft = F and F.t[k] or 0
    local ap = I.auras.applied[u][j]
    local t0 = ft > ap and ft or ap
    if DUR[j] >= 0 then
        local r = t0 + DUR[j] - t
        if r > HOLD then
            return r
        end
        return HOLD
    end
    if u == 1 then
        return -1 -- closed by rule 1's NONE: a CDM UP made it ours
    end
    return HOLD
end

-- Rule 1 (decision 111 as amended): a reduced DOWN closes the record only if our evidence opened this application;
-- after our cast, only once the fact read UP REFRESH_LAG past it (D14).
local function closes(k, u, j)
    local c = ours[k]
    if c == 0 or oursAp[k] ~= I.auras.applied[u][j] then
        return false
    end
    return c ~= BY_CAST or upAt[k] >= oursAp[k] + REFRESH_LAG
end

-- Rules 2.5.1-7 for one reduced fact (UP or DOWN) of aura j on unit u: a plain walk wins out of combat (I7); forms and
-- enchants are skipped on the player (M5); an UP stages only while the record is down or about to lapse (rules 3-4); a
-- DOWN closes only by rule 1. An edge is a fact; a poll answer is one only when it stages (spec §4.3). Returns whether
-- it staged. Allocates nothing.
local function apply(j, u, up, t, edge)
    local U = I.auras
    if u > U.n or j > U.nAura then -- (4a review m5) an in-combat rebuild may shrink the set under the router's map
        return false
    end
    local k = (u - 1) * I.AURA_UNIT + j
    if up then
        upAt[k] = t
    end
    if not I.inCombat and ((u == 1 and playerPlain) or (u == 2 and targetPlain)) then
        return false -- the walk answers
    end
    if u == 1 and (I.formAura[j] or I.enchantAura[j]) then
        return false -- Sources/Forms.lua's and Sources/Enchants.lua's records
    elseif u == 2 and I.targetSlot ~= I.curSlot then
        -- (review m3) a target change's TargetSwap folds after this drain's polls: until then the record is the old
        -- mob's, so nothing is applied on the target; the next poll answers
        return false
    end
    local e = U.exp0[u][j]
    local stage, rem = false, 0
    if up then
        stage = e <= t or (e ~= HUGE and e - t <= LAPSE)
        if stage then
            rem = hold(j, u, k, t)
        end
    else
        stage = e > t and closes(k, u, j)
    end
    if not stage then
        if edge then
            facts[k] = facts[k] + 1
        end
        return false
    elseif staged[k] == t then
        return false -- staged already in this drain (an edge, then the poll): the fold has not taken it yet
    end
    facts[k], staged[k] = facts[k] + 1, t
    if (e > t) ~= up then
        disagree[k] = disagree[k] + 1
    end
    local stacks = 0
    if up and e <= t then
        ours[k], oursAp[k] = BY_CDM, foldApplied(u, j, t) -- a CDM UP opened it
    elseif up then -- a hold re-stage: the model's stacks stand (rule 3)
        stacks = U.stacks[u][j]
        if U.icd[j] > 0 and rem > e + REFRESH_HOLD - t then
            -- an icd aura's later expiry past AURA_REFRESH reads as a re-application (Families/Auras.lua): stay short
            rem = e + REFRESH_HOLD - t
        end
    end
    Direct(Obs.Read, t, k, rem, ReadOf.Aura + stacks * I.AURA_STACK)
    return true
end
local function onEdge(j, u, up, t)
    if apply(j, u, up, t, true) then
        -- the aura event the client would have fired (the unit's full update): Hekili's handler forces a cycle
        local token = I.auras.token[u]
        I.Events.Deliver("UNIT_AURA", token, I.Events.AURA_INFO[token])
    end
end
--- Called by whoever activates a presence provider: its edges come here.
function I.OnPresence(P)
    P.onEdge = onEdge
end

-- Poll 15: the provider's sweep first (cdm-default §3.2: its edges come to onEdge), then every pair it answers, each
-- poll, and the player's floor (decision 114). Allocates nothing.
S.Poll(15, function(_, t)
    local P = I.presence
    if not P or not I.built then
        return
    end
    P.Sweep(t)
    local U = I.auras
    if P.covered == 0 then
        if floorSet then
            for j = 1, U.nAura do
                floor[j] = 0
            end
            floorSet = false
        end
        return
    end
    for u = 1, (U.n < 2 and U.n or 2) do
        for j = 1, U.nAura do
            local a = P.Presence(j, u)
            if u == 1 then
                floor[j] = a == I.UP and 1 or 0
                floorSet = floorSet or a == I.UP
            end
            if a ~= I.UNDECIDED then
                apply(j, u, a == I.UP, t, false)
            end
        end
    end
end)

S.On("PLAYER_REGEN_DISABLED", nil, function()
    for k in pairs(facts) do
        facts[k], disagree[k], staged[k], exitFix[k] = 0, 0, 0, 0
    end
    exiting = false
end)

-- The CDM section (cdm-default §6): per aura and unit with evidence or a fact this fight one line (a tracked aura with
-- none, one `unit=-` line), then one summary line. beliefDisagree: facts that contradicted the belief (decision 90);
-- itemDisagree: the router's transitions of its items to disagreement (§2.3). Debugging only: it allocates.
local FROM = { [0] = "model", "viewer" }
local OURS = { [0] = "no", "cast", "cdm", "walk" }
local VIA = { "E", "U", "B", "R" } -- bit 1 Essential, 2 Utility, 4 Buff icon, 8 Buff bar (§2.4)
local function via(n)
    local s, b = "", 1
    for i = 1, #VIA do
        if n % (2 * b) >= b then
            s = s .. VIA[i]
        end
        b = 2 * b
    end
    return s == "" and "-" or s
end
I.OnSnapshot(function(out, now)
    local P, U = I.presence, I.auras
    if not U or not P or P.name == "default" then
        return
    end
    local F, leaf = P.fact, P.Leaf and P.Leaf()
    local nTracked = 0
    for j = 1, U.nAura do
        local tracked = P.tracked and P.tracked[j]
        nTracked = nTracked + (tracked and 1 or 0)
        local lines = #out
        for u = 1, (U.n < 2 and U.n or 2) do
            local k = (u - 1) * I.AURA_UNIT + j
            local st, n = F and F.state[k] or I.UNDECIDED, F and F.n[k] or 0
            local amb = leaf and leaf.Ambiguous(j, u) or 0
            local itemD, lost = P.disagree and P.disagree[k] or 0, P.lost and P.lost[k] or 0
            if facts[k] > 0 or exitFix[k] > 0 or n > 0 or st ~= I.UNDECIDED or amb + itemD + lost > 0 then
                local walk = not I.inCombat and (u == 1 and playerPlain or u == 2 and targetPlain)
                local mine = ours[k] ~= 0 and oursAp[k] == U.applied[u][j] and U.exp0[u][j] > now
                out[#out + 1] = string.format(
                    "presence %s unit=%s fact=%s from=%s n=%d via=%s agree=%s ours=%s facts=%d beliefDisagree=%d"
                        .. " itemDisagree=%d ambiguous=%d lost=%d exitFix=%d",
                    KEY[j],
                    u == 1 and "player" or "target",
                    st == I.UP and "up" or st == I.DOWN and "down" or "unknown",
                    walk and "walk" or FROM[F and F.from[k] or 0] or "model",
                    n,
                    via(leaf and leaf.Via(j, u) or 0),
                    tostring(not F or F.agree[k] ~= false),
                    mine and OURS[ours[k]] or "no",
                    facts[k],
                    disagree[k],
                    itemD,
                    amb,
                    lost,
                    exitFix[k]
                )
            end
        end
        if tracked and #out == lines then
            out[#out + 1] = string.format("presence %s unit=- fact=unknown", KEY[j])
        end
    end
    out[#out + 1] = string.format(
        "presence covered=%d/%d unmapped=%d ambiguous=%d overflow=%d leaf=%s",
        P.covered or 0,
        nTracked,
        leaf and leaf.Unmapped() or 0,
        leaf and leaf.ambiguous or 0,
        leaf and leaf.overflow or 0,
        P.LeafState and P.LeafState() or "on"
    )
end)
