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
-- same drain (an edge, then the poll, or a clamp) is held back: a stage can be due at two polls in a row (a debounce
-- that elapsed, then a re-open after a close).
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
-- Rules 3-4 (C2, decision 112 as amended by the owner's rule, L310: trust the belief's duration). A CDM UP with no model
-- record behind it opens one at once: its registered duration (DUR[j], -1 none) from max(fact.t, applied) when that
-- outlasts HOLD, else LONG. A record believed up is never extended: at the model's expiry it goes down on its own;
-- only an item lit continuously HOLD past that expiry re-establishes it, once, LONG (a permanent player aura: -1, as
-- before; LONG is finite where a duration exists: inf - inf is NaN), closed by the observed down (rule 1). A LONG
-- record whose CDM stops answering UP (UNKNOWN, a hidden viewer, the leaf off, a target change) is clamped to HOLD
-- once.
-- shortcut: HOLD 1.0 s is a guess (spec D9; the owner's 0.6/1.0/1.5): set it from the LAT probe (ledger CDM-LAT).
-- The rule's alternatives (4b's re-stage within LAPSE of the expiry, L309's LONG re-stage) were measured and removed
-- (cdm-default Task 9, review S2).
local HOLD, LONG = 1.0, 3600
-- D14: after our cast wrote an application, its NONE closes it only once the fact read UP REFRESH_LAG after the write: an
-- item still showing the old application inside the client's latency says nothing of the new one.
-- shortcut: 0.5 s is unmeasured; the LAT probe (cast success vs the item's light) sets it.
local REFRESH_LAG = 0.5
local DUR = {}
-- By key (L310): lastE the model's expiry the last time an UP answer found the record up (0: none, or the item went
-- dark since), lastSt its stacks; longE the expiry of the LONG write still standing (0 none). anyLong, anyLast: some
-- longE, lastE set since the last poll with no live slot.
local lastE, lastSt, longE = {}, {}, {}
local anyLong, anyLast = false, false
-- Decision 114: 1 while the player's reduced fact is UP, else 0. Its one reader is the hit consumer (Families/Auras.lua's
-- Obs.PlayerHit handler): a `consumedBy` aura keeps its last stack while it is 1.
local floor = I.auraFloor or {}
I.auraFloor = floor
local floorSet = false -- some floor[j] is 1
-- The edge (owner rulings L345-L351): the router's fact.edge is the t of an observed dark -> lit flip (an EDGE, 0 a
-- SEED). By key: anAp the applied time of the cast-opened application last matched to an edge (once each);
-- emcN/emcSum/emcLast the edge minus our cast's start; cyT/cyD/cyAp/cyE the open cycle (edge, the
-- record's own duration, applied, expiry), cyN/cySum/cyObs/cyMod the closed cycles (observed dark - edge against the
-- modelled duration); seedAp the applied time of a record a SEED opened (unknown age while it is still the record's).
-- Diagnostics only: the cast's start stands (L347). Anchoring the expiry at the edge was measured and lost on agreement
-- (cdm-edge-anchor lane: the edge is a sweep's t, late against the truth by the viewer's latency and up to a poll).
-- shortcut: EDGE_WIN 1.0 s bounds edge-cast adjacency (cast events late up to 0.3 s, viewer lag up to 0.5 s, a poll
-- gap); a refresh cast within it of a fresh light is matched too; set it from the LAT probe (Task 10).
local EDGE_WIN = 1.0
local anAp, emcN, emcSum, emcLast = {}, {}, {}, {}
local cyT, cyD, cyAp, cyE, cyN, cySum, cyObs, cyMod, seedAp = {}, {}, {}, {}, {}, {}, {}, {}, {}
-- Per fight: polls an UP waited on the debounce past the model's expiry, and the re-establishes it made.
local holdN = { waits = 0, fires = 0 }
I.presenceHold = holdN
-- The verdict (cdm-verdict §2.3-§2.5, decisions 119-122): an up record our evidence opened, its proven item dark
-- (fact.pdark) and not UP for W past the latest of the write, the last UP and the dark's start (fact.pdarkT), is
-- closed once. By key: W[k] its window
-- (W0 for a walk or CDM opener, max(W0, travel + TOL) for our cast), verdictAt[k] the last verdict's t while a light
-- within STRIKE_WIN may still prove it wrong (0 none); per fight verdictN, strikeN, and darkN (1: pdark seen). A verdict
-- is counted when its close folds (I.AuraVerdictClosed), never at the stage.
-- shortcut: W0 1.0 s, TOL 0.3 s and STRIKE_WIN 2.0 s are the spec's (§6) from the 2026-11-09 sample; Task 10's P1 tunes them.
local W0, TOL, STRIKE_WIN = 1.0, 0.3, 2.0
-- strikePend[k]: the t of a light within STRIKE_WIN of a verdict (0 none), decided at the next poll, after this drain's
-- fold has run our recast's write (the first Opus round's M2: the polls run before the fold).
local W, verdictAt, verdictN, strikeN, darkN, strikePend = {}, {}, {}, {}, {}, {}
I.auraVerdict = { W = W, at = verdictAt, n = verdictN, strikes = strikeN } -- read-only views for the tests
I.presenceVerdict, I.presenceStrike = verdictN, strikeN -- the harness's names (loop.lua sums them per unit)
local function zeroVerdict(k)
    W[k], verdictAt[k], verdictN[k], strikeN[k], darkN[k], strikePend[k] = W0, 0, 0, 0, 0, 0
end
local function zeroEdge(k)
    anAp[k], emcN[k], emcSum[k], emcLast[k] = 0, 0, 0, 0
    cyT[k], cyD[k], cyAp[k], cyE[k], cyN[k], cySum[k], cyObs[k], cyMod[k], seedAp[k] = 0, 0, 0, 0, 0, 0, 0, 0, 0
end

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
        lastE[j], lastSt[j], longE[j], lastE[k], lastSt[k], longE[k] = 0, 0, 0, 0, 0, 0
        zeroEdge(j)
        zeroEdge(k)
        zeroVerdict(j)
        zeroVerdict(k)
    end
    floorSet, anyLong, anyLast = false, false, false
    holdN.waits, holdN.fires = 0, 0
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
                            ours[k], oursAp[k], W[k] = BY_WALK, foldApplied(u, j, t), W0
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

--- Our cast wrote record (u, j) (Families/Now.lua's aura()): this application is ours (rule 2.5.1); `travel` (seconds,
--- 0 or nil none) widens its verdict window (cdm-verdict §2.3). Allocates nothing.
function I.AuraOurs(u, j, travel)
    if u <= 2 then
        local k = (u - 1) * I.AURA_UNIT + j
        local w = (travel or 0) + TOL
        ours[k], oursAp[k], W[k] = BY_CAST, I.auras.applied[u][j], w > W0 and w or W0
    end
end

-- The LONG write's remaining for (j, u): -1 (math.huge) only for a player aura with no numeric duration (as before).
local function long(j, u)
    if u == 1 and DUR[j] < 0 then
        return -1 -- closed by rule 1's NONE: a CDM UP made it ours
    end
    return LONG
end

-- Rule 4's remaining for an UP of (j, u) at t (decision 112): never math.huge on the target or with a duration.
local function hold(j, u, k, t)
    if DUR[j] >= 0 then
        local F = I.presence.fact
        local ft = F and F.t[k] or 0
        local ap = I.auras.applied[u][j]
        local r = (ft > ap and ft or ap) + DUR[j] - t
        if r > HOLD then
            return r
        end
    end
    return long(j, u)
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

-- Whether a reduced fact may act on record (u, j) now: a plain walk wins out of combat (I7); forms and enchants are
-- skipped on the player (M5); nothing on the target while a swap waits to fold (review m3). apply's and the verdict's
-- guards (cdm-verdict §2.3). Allocates nothing.
local function judgeable(j, u)
    local U = I.auras
    if u > U.n or j > U.nAura then -- (4a review m5) an in-combat rebuild may shrink the set under the router's map
        return false
    elseif not I.inCombat and ((u == 1 and playerPlain) or (u == 2 and targetPlain)) then
        return false -- the walk answers
    elseif u == 1 and (I.formAura[j] or I.enchantAura[j]) then
        return false -- Sources/Forms.lua's and Sources/Enchants.lua's records
    end
    -- (review m3) a target change's TargetSwap folds after this drain's polls: until then the record is the old mob's,
    -- so nothing is applied on the target; the next poll answers
    return u ~= 2 or I.targetSlot == I.curSlot
end

-- Rules 2.5.1-7 for one reduced fact (UP or DOWN) of aura j on unit u: a plain walk wins out of combat (I7); forms and
-- enchants are skipped on the player (M5); an UP stages only while the record is down: at once with no model record,
-- after HOLD lit past the model's expiry otherwise (rules 3-4, L310); a DOWN
-- closes only by rule 1. An edge is a fact; a poll answer is one only when it stages (spec §4.3). Returns whether
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
    if not judgeable(j, u) then
        return false
    end
    if up and verdictAt[k] > 0 and strikePend[k] == 0 then -- a light after a verdict (cdm-verdict §2.5)
        if t - verdictAt[k] <= STRIKE_WIN then
            strikePend[k] = t -- judged at the next poll, once this drain's fold wrote any recast of ours (review M2)
        else
            verdictAt[k] = 0
        end
    end
    local e = U.exp0[u][j]
    local stage, rem, kind = false, 0, ReadOf.Aura
    local deb, seed = false, false -- the debounce decided; a SEED opens (unknown age)
    if up and e > t then
        if e ~= HUGE then
            lastE[k], lastSt[k], anyLast = e, U.stacks[u][j], true -- the model's expiry stands: the debounce counts from it
        end
    elseif up then
        kind = ReadOf.AuraOpen -- our cast's write folded first in this drain wins (F3)
        if lastE[k] > 0 then -- lit through the model's expiry: overridden only once lit HOLD past it
            local F = I.presence.fact
            local ft = F and F.t[k] or 0
            stage, rem, deb = t - (ft > lastE[k] and ft or lastE[k]) >= HOLD, long(j, u), true
        else
            local F = I.presence.fact
            stage, rem, seed = true, hold(j, u, k, t), not (F and F.edge and (F.edge[k] or 0) > 0)
        end
    else
        stage = e > t and closes(k, u, j)
    end
    if not stage then
        if edge then
            facts[k] = facts[k] + 1
        end
        if deb then
            holdN.waits = holdN.waits + 1
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
    if up then -- an UP stages only on a record still down
        ours[k], oursAp[k], W[k] = BY_CDM, foldApplied(u, j, t), W0 -- a CDM UP opened it
        stacks = lastSt[k] -- re-established: the model's last stacks (else 0)
        if seed then
            seedAp[k] = oursAp[k]
        end
        if deb then
            holdN.fires = holdN.fires + 1
        end
    end
    Direct(Obs.Read, t, k, rem, kind + stacks * I.AURA_STACK)
    if up and (rem == LONG or rem < 0) then
        longE[k], anyLong = rem < 0 and HUGE or t + rem, true -- the fold's expiry (Families/Auras.lua: o.t + o.b)
    end
    return true
end

-- One clamp of a LONG record whose CDM stopped answering UP: HOLD from t, once (the record's expiry no longer the
-- LONG write's, by a cast, a walk or a close, needs none). Allocates nothing.
local function clamp(j, u, t)
    local k = (u - 1) * I.AURA_UNIT + j
    local e = I.auras.exp0[u][j]
    if longE[k] == e and e > t + HOLD and staged[k] ~= t then
        staged[k] = t
        Direct(Obs.Read, t, k, HOLD, ReadOf.AuraHeld + I.auras.stacks[u][j] * I.AURA_STACK)
    end
    longE[k] = 0
end
-- The edge for an UP of aura j on unit u at t (te: the edge's t, L346-L348): a cast-opened application whose start lies
-- within EDGE_WIN of the edge is matched once (anAp): edge minus cast counted, the cycle opened (its modelled duration:
-- the record's own, no pack call). Diagnostics only. Allocates nothing.
local function edgeMatch(j, u, k, te, t)
    local U = I.auras
    local e, ap = U.exp0[u][j], U.applied[u][j]
    if e <= t or e == HUGE or longE[k] == e or ap == anAp[k] then
        return
    -- ap == te: a cast stamped at the edge's own sweep (or an applied the CDM open set): no lag to measure
    elseif ours[k] ~= BY_CAST or oursAp[k] ~= ap or ap == te or ap - te > EDGE_WIN or te - ap > EDGE_WIN then
        return
    end
    local dur = e - ap
    anAp[k], emcN[k], emcSum[k], emcLast[k] = ap, emcN[k] + 1, emcSum[k] + te - ap, te - ap
    cyT[k], cyD[k], cyAp[k], cyE[k] = te, dur, ap, e
end

-- The open cycle of key k closes at its thing's first dark after the edge (the leaf's darkT through fact.dark): the
-- observed duration against the modelled one, when it is still the matched application (unchanged, or ended by the
-- model first, or re-established long); a reading that is no UP without a dark drops it. Allocates nothing.
local function cycle(j, u, k, a, F)
    local dk = F.dark[k] or 0
    if dk > cyT[k] then
        local U = I.auras
        local e, ap = U.exp0[u][j], U.applied[u][j]
        if e <= dk or longE[k] == e or ap == cyAp[k] and e - cyE[k] < 1e-6 and cyE[k] - e < 1e-6 then
            local obs = dk - cyT[k]
            cyN[k], cySum[k], cyObs[k], cyMod[k] = cyN[k] + 1, cySum[k] + obs - cyD[k], obs, cyD[k]
        end
        cyT[k] = 0
    elseif a ~= I.UP then
        cyT[k] = 0
    end
end

-- The verdict for (j, u) at poll t (cdm-verdict §2.3), `a` its reduced answer: a record up that our evidence opened,
-- not UP, its proven item dark (fact.pdark), W past the latest of the write, the last UP and the start of the watched
-- dark (fact.pdarkT: continuously dark for W, Fable 5.2 review M2): closed once (no refund). Allocates nothing.
local function verdict(j, u, k, a, t, F)
    if strikePend[k] > 0 and t > strikePend[k] then -- the light a drain ago: wrong unless our cast came since (§2.5)
        -- >=: a cast stamped at the verdict's own time (its event in the frame of the closing poll, staged after
        -- that drain) is a new cast too; the judged application is at least W older than verdictAt, never equal
        if not (ours[k] == BY_CAST and oursAp[k] >= verdictAt[k]) then
            strikeN[k] = strikeN[k] + 1
            local P = I.presence
            if P.Strike then
                P.Strike(j, u)
            end
        end
        strikePend[k], verdictAt[k] = 0, 0
    elseif strikePend[k] == 0 and verdictAt[k] > 0 and t - verdictAt[k] > STRIKE_WIN then
        verdictAt[k] = 0
    end
    if not F.pdark[k] then
        return
    end
    darkN[k] = 1
    if I.verdictOff or a == I.UP or not judgeable(j, u) then
        return
    end
    local U = I.auras
    local ap = U.applied[u][j]
    if U.exp0[u][j] <= t or ours[k] == 0 or oursAp[k] ~= ap or staged[k] == t then
        return
    end
    local from, since = upAt[k] > ap and upAt[k] or ap, F.pdarkT[k]
    if since > from then
        from = since -- a swap back, a viewer shown again, a re-point: W counts from when the watching began
    end
    if t >= from + W[k] then
        staged[k] = t
        Direct(Obs.Read, t, k, ap, ReadOf.AuraVerdict) -- names the application judged; counted when it folds
    end
end

--- The fold closed record k by the verdict staged at t (Families/Auras.lua: the record was still the application the
--- verdict judged). Counted here, not at the stage: a close the fold drops (our recast folded first in the same
--- drain, Fable 5.2 review M1) is no verdict, opens no strike window and counts nothing. Like any close it drops the
--- debounce's memory, so a late light re-opens at once (rule 4) instead of waiting on the old expiry. The provider
--- counts it against the items dark for the thing (review M3: silent verdicts suspend a proof). Allocates nothing.
function I.AuraVerdictClosed(k, t)
    verdictAt[k], verdictN[k] = t, verdictN[k] + 1
    lastE[k], lastSt[k], longE[k] = 0, 0, 0
    local P = I.presence
    if P and P.Silent then
        local u = k > I.AURA_UNIT and 2 or 1
        P.Silent(k - (u - 1) * I.AURA_UNIT, u)
    end
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
    local F = P.fact
    -- the router's facts carry pdark (cdm-verdict §2.3); Default has none; (review M1) no leaf, no verdict
    local vF = F and F.pdark and P.Leaf and P.Leaf() ~= nil and F
    if P.covered == 0 then
        -- a dark item is never live: with no live slot the verdict still runs (cdm-verdict §2.2)
        for u = 1, vF and (U.n < 2 and U.n or 2) or 0 do
            for j = 1, U.nAura do
                verdict(j, u, (u - 1) * I.AURA_UNIT + j, I.UNDECIDED, t, vF)
            end
        end
        if floorSet then
            for j = 1, U.nAura do
                floor[j] = 0
            end
            floorSet = false
        end
        if anyLong or anyLast then -- no live slot (the leaf off, every viewer hidden, nothing lit): no answer at all
            for u = 1, (U.n < 2 and U.n or 2) do
                for j = 1, U.nAura do
                    local k = (u - 1) * I.AURA_UNIT + j
                    if longE[k] > 0 then
                        clamp(j, u, t)
                    end
                    lastE[k], lastSt[k] = 0, 0 -- not lit continuously: a record still up sets it again
                end
            end
            anyLong, anyLast = false, false
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
            local k = (u - 1) * I.AURA_UNIT + j
            if vF then
                verdict(j, u, k, a, t, vF)
            end
            if F and F.edge then
                local te = F.edge[k] or 0
                if a == I.UP and te > 0 then
                    edgeMatch(j, u, k, te, t)
                end
                if cyT[k] > 0 then
                    cycle(j, u, k, a, F)
                end
            end
            if a ~= I.UP and longE[k] > 0 then
                clamp(j, u, t)
            end
            if a ~= I.UP and lastE[k] > 0 and U.exp0[u][j] <= t then
                -- dark past the model's expiry (a NONE counts only for a record up: UNKNOWN here): no debounce, a
                -- later light is a new application
                lastE[k], lastSt[k] = 0, 0
            end
        end
    end
end)

-- A target change, before Sources/Target.lua's swap logs its TargetSwap (Hekili.toc order): mob A's LONG record is
-- clamped while it is still the target's (it folds before the swap's save, so mob A is not remembered up for an hour),
-- and the debounce starts over. Allocates nothing.
S.On("PLAYER_TARGET_CHANGED", nil, function(_, t)
    if not I.built or I.auras.n < 2 then
        return
    end
    for j = 1, I.auras.nAura do
        local k = I.AURA_UNIT + j
        if longE[k] > 0 and I.targetSlot == I.curSlot then -- a second change in one drain: the first one clamped
            clamp(j, 2, t)
        end
        longE[k], lastE[k], lastSt[k], cyT[k] = 0, 0, 0, 0
        verdictAt[k], strikePend[k] = 0, 0 -- (review S1) a light on the next mob says nothing of mob A's verdict
    end
end)

S.On("PLAYER_REGEN_DISABLED", nil, function()
    for k in pairs(facts) do
        facts[k], disagree[k], staged[k], exitFix[k] = 0, 0, 0, 0
        lastE[k], lastSt[k], longE[k] = 0, 0, 0 -- out of combat the walk answered
        emcN[k], emcSum[k], emcLast[k], cyT[k], cyN[k], cySum[k], cyObs[k], cyMod[k] = 0, 0, 0, 0, 0, 0, 0, 0
        verdictAt[k], verdictN[k], strikeN[k], darkN[k], strikePend[k] = 0, 0, 0, 0, 0
    end
    holdN.waits, holdN.fires = 0, 0
    anyLong, anyLast = false, false
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
        for u = 1, (U.n < 2 and U.n or 2) do -- the edge (L345-L351): seeds, edges, age, edge minus cast, cycles
            local k = (u - 1) * I.AURA_UNIT + j
            local sN, eN = P.seedN and P.seedN[k] or 0, P.edgeN and P.edgeN[k] or 0
            local unknown = seedAp[k] ~= 0 and seedAp[k] == U.applied[u][j] and U.exp0[u][j] > now
            if sN + eN + emcN[k] + cyN[k] > 0 or unknown then
                out[#out + 1] = string.format(
                    "presence-edge %s unit=%s seeds=%d edges=%d age=%s edgeMinusCast n=%d mean=%.3f"
                        .. " last=%.3f cycles=%d observed=%.2f modeled=%.2f diffMean=%.3f",
                    KEY[j],
                    u == 1 and "player" or "target",
                    sN,
                    eN,
                    unknown and "unknown" or "known",
                    emcN[k],
                    emcN[k] > 0 and emcSum[k] / emcN[k] or 0,
                    emcLast[k],
                    cyN[k],
                    cyObs[k],
                    cyMod[k],
                    cyN[k] > 0 and cySum[k] / cyN[k] or 0
                )
            end
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
    if not leaf then
        return
    end
    out[#out + 1] = string.format("presence-edge debounceWaits=%d debounceFires=%d", holdN.waits, holdN.fires)
    local never = "" -- the verdict (cdm-verdict §3): per thing with a verdict, a strike or a pdark this fight
    for j = 1, U.nAura do
        for u = 1, (U.n < 2 and U.n or 2) do
            local k = (u - 1) * I.AURA_UNIT + j
            if verdictN[k] + strikeN[k] + darkN[k] > 0 then
                out[#out + 1] = string.format(
                    "presence-verdict %s unit=%s W=%.2f verdicts=%d strikes=%d pdark=%s darkSlots=%d",
                    KEY[j],
                    u == 1 and "player" or "target",
                    W[k],
                    verdictN[k],
                    strikeN[k],
                    tostring(F and F.pdark and F.pdark[k] == true),
                    select(7, leaf.Counts(j, u)) or 0
                )
            end
        end
        if leaf.NeverLit and leaf.NeverLit(j) then
            never = never == "" and KEY[j] or never .. "," .. KEY[j]
        end
    end
    out[#out + 1] = string.format("presence-proof mappedNeverLit=%s", never == "" and "-" or never)
    out[#out + 1] = string.format(
        "presence-proof repoints=%d struck=%d suspended=%d builds=%d",
        leaf.repoints or 0,
        leaf.struck or 0,
        leaf.suspended or 0,
        leaf.builds or 0
    )
end)
