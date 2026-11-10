-- Game/State/Sources/Presence/Router.lua
-- The Presence router (providers spec §2.5, decisions 88-90; cdm-default §2.4, decisions 92-94). It hosts one reduced
-- fact per aura and unit: the leaf's sweep calls back for every thing it moved, the router reduces its counts through
-- I.ReduceFact and sends a reduced UP or DOWN change to onEdge. At activation, out of combat, it marks each aura the leaf
-- can map as tracked (leaf.Mappable, cdm-default §3.1); a tracked aura is answered by its fact, an untracked one
-- I.UNDECIDED (the belief's modelled timer). The experimental switch (cfg.viewer) decides whether it has the leaf:
-- without it every answer is I.UNDECIDED. The tracked set and the leaf's build change only out of combat; a leaf that
-- turned itself off (an error in its sweep, our reduction or onEdge: they run inside its one pcall) is dropped at once.
-- Knows the leaf only through the contract (I.PRESENCE.viewer).

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources

-- fact.* by k = (u - 1) * I.AURA_UNIT + j (§2.4): state (I.UP, I.DOWN or I.UNDECIDED), n (nLive of the deciding
-- standing), agree, t (the last UNKNOWN/DOWN -> UP time), from (the deciding standing: 1 the viewer leaf, 0 none).
-- disagree[k] and lost[k] are per fight. Preallocated for both units at activation.
-- The edge (owner rulings L348-L351): fact.edge[k] the t of the UP change when one of the thing's slots had an edge in
-- that sweep (lit -> dark -> lit on one unit, each seen: the leaf's eT), 0 for a SEED (any other first light: unknown
-- age); fact.dark[k] the leaf's last dark-after-light t; seedN[k] and edgeN[k] count the UP changes per fight.
-- fact.pdark[k] (cdm-verdict §2.3, decision 119): a proven item of the thing dark on a monitored sweep and none lit;
-- fact.pdarkT[k] since when (the leaf's tDark: the latest first dark sweep among its dark slots, 0 none). Both set at
-- every reduction (no state change, no edge, no fact.t); read by poll 15's verdict only.
local fact = { state = {}, n = {}, agree = {}, t = {}, from = {}, edge = {}, dark = {}, pdark = {}, pdarkT = {} }
local R = {
    name = "router", -- l10n: verbatim
    scope = nil,
    covered = 0,
    onEdge = nil,
    tracked = {},
    fact = fact,
    disagree = {},
    lost = {},
    seedN = {},
    edgeN = {},
}
local tracked, disagree, lost, seedN, edgeN = R.tracked, R.disagree, R.lost, R.seedN, R.edgeN
local fState, fN, fAgree, fT, fFrom, fEdge, fDark, fPdark, fPdarkT =
    fact.state, fact.n, fact.agree, fact.t, fact.from, fact.edge, fact.dark, fact.pdark, fact.pdarkT
local leaf, want, api0, def0, pending = nil, nil, nil, nil, false
local edges = { up = 0, down = 0 } -- the edges passed on this fight (Snapshot)
I.presenceEdges = edges

-- A tracked aura's edge only, counted; a target DOWN included (decision 111 as amended: the CDM's "now" state has
-- precedence on the target; Sources/Auras.lua closes only a record our evidence opened). Allocates nothing.
local function forward(j, u, up, t)
    if tracked[j] then
        if up then
            edges.up = edges.up + 1
        else
            edges.down = edges.down + 1
        end
        if R.onEdge then
            R.onEdge(j, u, up, t)
        end
    end
end

-- One thing the leaf's sweep moved (§2.3-§2.4), called inside its pcall: its counts reduced; disagree counts a
-- transition to disagreement; on a state change, t (to UP), lost (to UNKNOWN while the record is up) and the edge
-- (UP or DOWN). Allocates nothing.
local function thing(k, t)
    local u = k > I.AURA_UNIT and 2 or 1
    local j = k - (u - 1) * I.AURA_UNIT
    local nLive, nUp, nNone, nStale, tUp, tNone, nDark, tDark = leaf.Counts(j, u)
    local st, agree = I.ReduceFact(nLive, nUp, nNone, nStale, tUp, tNone)
    fN[k], fPdark[k], fPdarkT[k] = nLive, (nDark or 0) > 0 and nUp == 0, tDark or 0
    if nUp == 0 then -- the thing is dark only once none of its slots is lit (a cycle closes on the last dark)
        fDark[k] = leaf.darkT[k] or 0
    end
    fFrom[k] = nLive > 0 and 1 or 0
    if fAgree[k] and not agree then
        disagree[k] = disagree[k] + 1
    end
    fAgree[k] = agree
    if st == fState[k] then
        return
    end
    fState[k] = st
    if st ~= I.UP then
        fEdge[k] = 0
    end
    if st == I.UNDECIDED then
        local U = I.auras
        -- it had a fact and lost it while its record is up; (4a review m5) an in-combat rebuild may shrink the set
        if u <= U.n and j <= U.nAura and U.exp0[u][j] > t then
            lost[k] = lost[k] + 1
        end
        return
    end
    if st == I.UP then
        fT[k] = t
        if (leaf.edgeT[k] or 0) == t then -- one of its slots had an edge in this sweep
            fEdge[k], edgeN[k] = t, edgeN[k] + 1
        else
            seedN[k] = seedN[k] + 1
        end
    end
    forward(j, u, st == I.UP, t)
end

-- Every fact UNKNOWN, the per-fight counters zeroed (preallocated for both units of the def's auras).
local function clear()
    for k in pairs(fState) do
        fState[k], fN[k], fAgree[k], fT[k], fFrom[k], disagree[k], lost[k] = I.UNDECIDED, 0, true, 0, 0, 0, 0
        fEdge[k], fDark[k], seedN[k], edgeN[k], fPdark[k], fPdarkT[k] = 0, 0, 0, 0, false, 0
    end
    for j = 1, def0 and #def0.auraIds or 0 do
        for u = 1, 2 do
            local k = (u - 1) * I.AURA_UNIT + j
            fState[k], fN[k], fAgree[k], fT[k], fFrom[k], disagree[k], lost[k] = I.UNDECIDED, 0, true, 0, 0, 0, 0
            fEdge[k], fDark[k], seedN[k], edgeN[k], fPdark[k], fPdarkT[k] = 0, 0, 0, 0, false, 0
        end
    end
end

-- The leaf turned itself off (§3.5): nothing it mapped is tracked any more, every fact UNKNOWN, at once.
local function drop()
    leaf, R.covered = nil, 0
    for j = 1, #tracked do
        tracked[j] = false
    end
    for k in pairs(fState) do
        fState[k], fN[k], fFrom[k], fEdge[k], fPdark[k] = I.UNDECIDED, 0, 0, 0, false
    end
end

-- Out of combat: takes the wanted leaf, clears the map (preallocated to the def's auras) and the facts, activates the
-- leaf (its first sweep reduces here) and marks the map. In combat it changes nothing and waits for
-- PLAYER_REGEN_ENABLED (decision 89: no path change mid-fight).
local function activate(t)
    if I.inCombat then
        pending = true
        return
    end
    leaf = want
    for j = 1, #tracked do
        tracked[j] = false
    end
    for j = 1, def0 and #def0.auraIds or 0 do
        tracked[j] = false
    end
    clear()
    R.covered, R.scope, pending = 0, nil, false
    if not leaf then
        return
    end
    leaf.onThing = thing
    local errors = leaf.errors
    leaf.Activate(api0, t, def0, nil)
    if leaf.errors ~= errors then
        drop()
        return
    end
    for j = 1, def0 and #def0.auraIds or 0 do
        tracked[j] = leaf.Mappable(j) -- the leaf's map (cdm-default §3.1): every candidate, ambiguous ones included
    end
    R.covered, R.scope = leaf.covered, leaf.scope
end

-- The viewer's events reach the client only while the router has the leaf: switch off is the Default to the digit
-- (decision 88), so it registers nothing new.
local VIEWER_EVENTS = {
    "COOLDOWN_VIEWER_DATA_LOADED",
    "COOLDOWN_VIEWER_TABLE_HOTFIXED",
    "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
}
local function listen(on)
    for n = 1, #VIEWER_EVENTS do
        S.Dormant(VIEWER_EVENTS[n], not on)
        I.Events.Sync(VIEWER_EVENTS[n])
    end
end

--- Takes the leaf when cfg.viewer; builds the map and activates the leaf out of combat (else at combat end).
function R.Activate(api, t, def, cfg)
    listen(cfg and cfg.viewer)
    api0, def0, want = api, def, nil
    if cfg and cfg.viewer then
        want = I.PRESENCE.viewer
    end
    activate(t)
end

--- Answers I.UNDECIDED from now on.
function R.Deactivate(t)
    listen(false)
    if leaf then
        leaf.Deactivate(t)
    end
    leaf, want, pending, R.covered, R.scope = nil, nil, false, 0, nil
    for k in pairs(fPdark) do -- (review M1) no leaf, no positive dark: poll 15's verdict must not read a stale one
        fPdark[k] = false
    end
end

--- Poll 15's sweep: the leaf reads its items (cdm-default §3.2) and the moved things are reduced here; covered follows
--- it. A leaf that turned itself off in this sweep is dropped. Allocates nothing.
function R.Sweep(t)
    if leaf then
        local errors = leaf.errors
        leaf.Sweep(t)
        if leaf.errors ~= errors then
            drop()
        else
            R.covered = leaf.covered
        end
    end
end

--- A wrong verdict for aura j on unit u (cdm-verdict §2.5): the leaf strikes the items lit for it now. Allocates nothing.
function R.Strike(j, u)
    if leaf then
        leaf.Strike(j, u)
    end
end

--- A verdict closed the record of aura j on unit u (cdm-verdict §2.5): the leaf counts it against the items dark for
--- it (silent verdicts suspend a proof). Allocates nothing.
function R.Silent(j, u)
    if leaf then
        leaf.Silent(j, u)
    end
end

--- A tracked aura's reduced fact as I.UP or I.DOWN, else I.UNDECIDED. Allocates nothing.
function R.Presence(j, u)
    if leaf and tracked[j] then
        local a = fState[(u - 1) * I.AURA_UNIT + j]
        if a == I.UP or a == I.DOWN then
            return a
        end
    end
    return I.UNDECIDED
end

--- The active leaf, nil without one (the snapshot's per-slot reads: Via, Ambiguous, Unmapped).
function R.Leaf()
    return leaf
end

--- The leaf's state for the snapshot (cdm-default §6). An error may come from the belief code onEdge runs inside the
--- leaf's pcall, not only from the CDM reading (4a review m3).
function R.LeafState()
    if leaf then
        return "on"
    elseif I.PRESENCE.viewer and I.PRESENCE.viewer.errors > 0 then
        return "off(error in the CDM sweep or the belief code it calls: see the error line)"
    elseif want then
        return "pending" -- waits for combat end
    end
    return "off(debug)"
end

-- The viewer's sets changed (CV §3): rebuild out of combat, else at combat end (decision 89: no change mid-fight).
local function changed(_, t)
    if leaf and leaf.ForgetEdges then -- the data reloaded: every slot's lit/dark starts over, even while the rebuild waits
        leaf.ForgetEdges()
    end
    if want and I.presence == R then
        activate(t)
    end
end
for n = 1, #VIEWER_EVENTS do
    S.On(VIEWER_EVENTS[n], nil, changed)
    S.Dormant(VIEWER_EVENTS[n], true)
end
-- Player.lua's handler runs first (TOC order) and clears I.inCombat.
S.On("PLAYER_REGEN_ENABLED", nil, function(_, t)
    if pending and I.presence == R then
        activate(t)
    end
end)
-- A target change (cdm-default §3.4): the target's facts start over, UNKNOWN, so the next sweep that sees mob B's
-- light is an UNKNOWN -> UP change with its own fact.t (rule 4's t0), even when no sweep falls in the switch's frame
-- (the leaf's settle; review I1). The leaf has reset its target slots in the same event. Allocates nothing.
S.On("PLAYER_TARGET_CHANGED", nil, function()
    for j = 1, def0 and #def0.auraIds or 0 do
        local k = I.AURA_UNIT + j
        if fState[k] ~= nil then
            fState[k], fT[k], fEdge[k], fPdark[k] = I.UNDECIDED, 0, 0, false
        end
    end
end)
S.On("PLAYER_REGEN_DISABLED", nil, function()
    edges.up, edges.down = 0, 0
    for k in pairs(disagree) do
        disagree[k], lost[k], seedN[k], edgeN[k] = 0, 0, 0, 0
    end
end)

I.PRESENCE.router = R
