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
-- Whether the last player walk completed (plain): then it wins over the overlay reads.
local playerPlain = true
-- The player auras with a numeric `overlay`: their aura indices and overlay spell IDs (built at OnBuild).
local OVL_J, OVL_ID, OVL_N = {}, {}, 0

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
    playerPlain = true
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
        local on = Plain(api, api.C_SpellActivationOverlay.IsSpellOverlayed(OVL_ID[k])) -- plain [W PR11]; tested anyway
        if on == true and not playerPlain and e[j] <= t then
            Direct(Obs.Read, t, j, -1, ReadOf.Aura)
        elseif on == false and e[j] > t and (not playerPlain or e[j] == HUGE) then
            Direct(Obs.Read, t, j, 0, ReadOf.Aura)
        end
    end
end)
