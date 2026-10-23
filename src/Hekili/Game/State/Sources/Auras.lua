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
local staged = {} -- by the same key: 1 up or 2 down staged and not yet folded into the belief, else 0
I.presenceFacts, I.presenceDisagree = facts, disagree
local KEY = {} -- aura index -> its key, for the Snapshot lines

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
        facts[j], disagree[j], staged[j] = 0, 0, 0
        facts[I.AURA_UNIT + j], disagree[I.AURA_UNIT + j], staged[I.AURA_UNIT + j] = 0, 0, 0
    end
end)

-- One unit's walk at t; returns whether it completed. Allocates nothing (the client allocates its aura tables).
local function walk(api, u, unit, t)
    local U = I.auras
    serial = serial + 1
    local complete = true
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
                found[u][j] = serial
                if I.inCombat then
                    seen[u][j] = true
                end
                local stacks = type(apps) == "number" and apps or 0
                local remaining = exp > 0 and exp - t or -1
                if remaining > 0 or exp == 0 then
                    Direct(Obs.Read, t, (u - 1) * I.AURA_UNIT + j, remaining, ReadOf.Aura + stacks * I.AURA_STACK)
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
    pending = true
end)

-- Poll 10 (after the form read, 9, so a walk's form-aura skip sees this frame's form): once combat has ended, walk the
-- player and an existing target again; retried each poll until the player walk completes.
S.Poll(10, function(api, t)
    if not pending or I.inCombat or not I.built then
        return
    end
    if walk(api, 1, "player", t) then
        pending = false
    end
    if I.auras.n >= 2 and Plain(api, api.UnitExists("target")) == true then
        walk(api, 2, "target", t)
    end
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

-- (providers decision 80) Presence from the injected provider, with the overlay's rule: a plain walk wins; UP while
-- believed down stages up with no expiry, DOWN while believed up stages down. An edge is a fact; a poll answer is one
-- only when it contradicts the belief (spec §4.3). Returns whether it staged. Allocates nothing.
local function apply(j, u, up, t, edge)
    local U = I.auras
    if u > U.n then
        return false
    end
    local k = (u - 1) * I.AURA_UNIT + j
    if (u == 1 and playerPlain) or (u == 2 and targetPlain) then
        staged[k] = 0 -- the walk answers now; a read staged before it turned plain must not block a later edge
        return false
    end
    local differs = (U.exp0[u][j] > t) ~= up
    local v = up and 1 or 2
    if not differs then
        staged[k] = 0
    elseif staged[k] == v then
        return false -- staged already (an edge earlier this frame): the fold has not taken it yet
    end
    if edge or differs then
        facts[k] = facts[k] + 1
    end
    if differs then
        disagree[k], staged[k] = disagree[k] + 1, v
        Direct(Obs.Read, t, k, up and -1 or 0, ReadOf.Aura)
    end
    return differs
end
local function onEdge(j, u, up, t)
    if apply(j, u, up, t, true) then
        S.Urgent("VS_PRESENCE")
    end
end
--- Called by whoever activates a presence provider: its edges come here.
function I.OnPresence(P)
    P.onEdge = onEdge
end

-- Poll 15: every pair the provider answers, each poll (an edge the hook missed, a target swap). Allocates nothing.
S.Poll(15, function(_, t)
    local P = I.presence
    if not P or P.covered == 0 or not I.built then
        return
    end
    local U = I.auras
    for u = 1, (U.n < 2 and U.n or 2) do
        for j = 1, U.nAura do
            local a = P.Presence(j, u)
            if a ~= I.UNDECIDED then
                apply(j, u, a == I.UP, t, false)
            end
        end
    end
end)

S.On("PLAYER_REGEN_DISABLED", nil, function()
    for k in pairs(facts) do
        facts[k], disagree[k], staged[k] = 0, 0, 0
    end
end)

-- Per aura and unit with a fact this fight, one line; a tracked aura with none, one `unit=-` line (debugging only: it
-- allocates). Nothing without a presence provider or for the Default one.
I.OnSnapshot(function(out)
    local P, U = I.presence, I.auras
    if not U or not P or P.name == "default" then
        return
    end
    for j = 1, U.nAura do
        local path = (P.tracked and P.tracked[j]) and "viewer" or "model"
        local lines = #out
        for u = 1, (U.n < 2 and U.n or 2) do
            local k = (u - 1) * I.AURA_UNIT + j
            if facts[k] > 0 then
                out[#out + 1] = string.format(
                    "presence %s unit=%s path=%s facts=%d disagree=%d",
                    KEY[j],
                    u == 1 and "player" or "target",
                    path,
                    facts[k],
                    disagree[k]
                )
            end
        end
        if path == "viewer" and #out == lines then -- tracked, no fact yet: one line for the aura
            out[#out + 1] = string.format("presence %s unit=- path=viewer facts=0 disagree=0", KEY[j])
        end
    end
end)
