-- Game/State/Families/Modifiers.lua
-- Declarative resource modifiers (event-facade spec §12b): two fields of a resource definition, filled by the race
-- packs (Engine/Schema/Races.lua, through Engine/Schema/Tracked.lua) and open to talents and class auras alike.
-- - `maxMods`: { { pct = n, when = fn|nil }, ... }; the maximum is the declared `max` (a number, or a pack function run
--   in the belief's context, default 100) x the product of (1 + pct) over the modifiers whose `when` holds. Families/Resources.lua's
--   one maximum evaluator applies it (at the build, seeding the interval, and at each CombatEnd) until a plain maximum
--   read arrives, which wins from then on.
-- - `costMods`: { { aura = "<key>", talent = "<key>"|nil, pct = n | flat = n, charges = k|nil, spells = { IDs }|nil,
--   unless = "<key>"|nil }, ... }; with `talent` the modifier also needs that talent's believed rank above 0 and needs
--   no `aura` (a passive talent's cut), its `pct` or `flat` a list by rank or one number; an ability
--   paying that resource whose spell ID (or a `copy` rank) is in `spells` (every ability when `spells` is nil) costs
--   less while the aura is believed up on the player (I.CostOf). With `charges`, each cast whose declared cost is above
--   0 (even one the discount brought to 0) spends one of the aura's believed stacks (a modelled sample at the cast),
--   and the aura goes at 0; an observed aura read still wins. While the player's aura `unless` is believed up (at the
--   cast, before any of its charges go), the modifier neither prices nor takes a stack; a key the class did not
--   register is never up.
-- Allocates nothing per cast: the lists are the definitions' own tables, resolved to aura indices at the build.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal

local M = { costMods = {}, modAura = {}, modSpell = {}, modScope = {}, modUnless = {}, modHeld = {}, modTalent = {} }
I.mods = M

I.OnBuild(function(def)
    local auraByKey, talentByKey = {}, {} -- the build allocates
    for j = 1, #def.auras do
        if def.auras[j].key then
            auraByKey[def.auras[j].key] = j
        end
    end
    for i = 1, #(def.talents or {}) do
        talentByKey[def.talents[i].key] = def.talents[i].spell
    end
    for r = 1, #def.resources do
        local mods = def.resources[r].costMods
        M.costMods[r] = mods
        if mods then
            local ja, js, sc = M.modAura[r] or {}, M.modSpell[r] or {}, M.modScope[r] or {}
            local ju, held, jt = M.modUnless[r] or {}, M.modHeld[r] or {}, M.modTalent[r] or {}
            M.modAura[r], M.modSpell[r], M.modScope[r] = ja, js, sc
            M.modUnless[r], M.modHeld[r], M.modTalent[r] = ju, held, jt
            for k = 1, #mods do
                local j = auraByKey[mods[k].aura]
                ja[k], js[k] = j or 0, j and def.auraIds[j][1] or 0
                -- the talent's spell ID (VS.Talent), 0 without `talent`, -1 for a key the class did not register
                jt[k] = mods[k].talent == nil and 0 or talentByKey[mods[k].talent] or -1
                local u = mods[k].unless and auraByKey[mods[k].unless]
                ju[k], held[k] = u and def.auraIds[u][1] or 0, false
                -- the scope as ability indices: a listed ID matches an ability's id or a `copy` rank (I.ab.bySpell);
                -- an ID the class did not register is absent; no `spells`: every ability
                local spells = mods[k].spells
                if spells then
                    local set = {}
                    for _, id in ipairs(spells) do
                        local a = I.ab.bySpell[id]
                        if a then
                            set[a] = true
                        end
                    end
                    sc[k] = set
                else
                    sc[k] = false
                end
            end
        end
    end
end)

-- Whether modifier k of slot r covers ability a.
local function inScope(r, k, a)
    local set = M.modScope[r][k]
    return not set or set[a] == true
end

-- Whether modifier k of slot r is held at `now` by its `unless` aura, believed up on the player.
local function held(r, k, now)
    local u = M.modUnless[r][k]
    return u > 0 and VS.Aura("player", u, now) ~= nil
end

-- Modifier k of slot r's believed talent rank: 1 without `talent`, 0 for a key the class did not register.
local function rankOf(r, k)
    local t = M.modTalent[r][k]
    return t > 0 and VS.Talent(t) or t == 0 and 1 or 0
end

-- Whether modifier k of slot r (`mod`, its aura's spell ID `js`), at its talent rank `rank`, prices ability a at `now`:
-- a rank, its aura believed up on the player or a talent with no aura, a in its scope, not held by its `unless` aura.
local function prices(r, k, mod, js, a, rank, now)
    return rank > 0
        and (js > 0 and VS.Aura("player", js, now) or mod.aura == nil and mod.talent ~= nil)
        and inScope(r, k, a)
        and not held(r, k, now)
end

--- Ability a's cost `c` on slot r after the cost modifiers in its scope whose aura is believed up on the player at
--- `now` and whose talent (if any) has a rank, the value at that rank; one with a talent and no aura needs only the
--- rank. The simulation's M.Apply (Engine/Schema/Races.lua) alike. Allocates nothing.
function I.CostMod(a, r, c, now)
    local mods = r and M.costMods[r]
    if not mods or c <= 0 then
        return c
    end
    local js = M.modSpell[r]
    for k = 1, #mods do
        local mod = mods[k]
        local rank = rankOf(r, k)
        -- shortcut: modifiers apply in list order, so a flat listed after a pct lands after it; wowsims adds every flat
        -- to the base before any percent (spell.go:1055). Upgrade when a pack gives one ability both kinds.
        if prices(r, k, mod, js[k], a, rank, now) then
            local p, f = mod.pct, mod.flat
            p, f = type(p) == "table" and p[rank] or p, type(f) == "table" and f[rank] or f
            if type(p) == "number" then
                c = c * (1 + p)
            elseif type(f) == "number" then
                c = c + f
            end
        end
    end
    return c > 0 and c or 0
end

--- The factor the cost modifiers pricing ability a on slot r at `now` (I.CostMod) multiply its cost by, when each is a
--- passive talent's percent (a talent, no aura: always in scope while the rank stands): the product of (1 + pct) at
--- their ranks, 1 when none prices it; 0 when an aura's modifier (which comes and goes) or a flat one prices it, or the
--- product is not above 0. I.LearnBases inverts it. Allocates nothing.
function I.PassiveCostFactor(a, r, now)
    local mods = r and M.costMods[r]
    local m, js = 1, mods and M.modSpell[r]
    for k = 1, mods and #mods or 0 do
        local mod = mods[k]
        local rank = rankOf(r, k)
        if prices(r, k, mod, js[k], a, rank, now) then
            local p, f = mod.pct, mod.flat
            p, f = type(p) == "table" and p[rank] or p, type(f) == "table" and f[rank] or f
            if mod.aura ~= nil or type(p) ~= "number" and type(f) == "number" then
                return 0
            elseif type(p) == "number" then
                m = m * (1 + p)
            end
        end
    end
    return m > 0 and m or 0
end

--- A paid cast of ability a at t on slot r spends one believed stack of each charged modifier in its scope whose aura
--- is up and whose talent (if any) has a rank, but none of a modifier its `unless` aura holds as the cast starts
--- (decided before any stack goes); at 0 the aura goes. Called by the `now` family's cost step (Families/Now.lua).
--- Allocates nothing.
function I.SpendCostCharges(a, r, t, event)
    local mods = r and M.costMods[r]
    if not mods then
        return
    end
    local ja, js, hk = M.modAura[r], M.modSpell[r], M.modHeld[r]
    for k = 1, #mods do
        hk[k] = held(r, k, t)
    end
    for k = 1, #mods do
        if mods[k].charges and ja[k] > 0 and not hk[k] and rankOf(r, k) > 0 and inScope(r, k, a) then
            local rec, stacks, applied = VS.Aura("player", js[k], t)
            if rec then
                local left = (stacks or 1) - 1
                -- shortcut: a partial spend keeps the read-wins guard (a read in the frame may already show it); every
                -- shipped charged modifier has charges = 1. Upgrade with the read's stack count if one ships with more.
                if left > 0 then
                    I.AuraModel(1, ja[k], applied or t, rec.est, left, t, event, false)
                else
                    I.AuraModel(1, ja[k], 0, 0, 0, t, event, false, true)
                end
            end
        end
    end
end
