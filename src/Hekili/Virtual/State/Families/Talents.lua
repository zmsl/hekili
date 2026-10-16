-- Virtual/State/Families/Talents.lua
-- The talents family (spec §6.6): ranks by the talent's registered spell ID (Hekili's `class.talents[key][2]`), from
-- one C_Traits walk per talent event (Sources/Talents.lua). Ranks are plain facts: the walk writes them at once (so
-- Hekili's ns.updateTalents reads fresh ranks) and logs a `Talent` observation per changed rank.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Talents.lua (Applier Talent :39).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal

-- unmatched: the last walk's definition spells no talent or alias names (cap UNMATCHED, the walk resets nUnmatched)
local T = { n = 0, key = {}, spell = {}, max = {}, rank = {}, bySpell = {}, alias = {}, unmatched = {}, nUnmatched = 0 }
I.TALENT_UNMATCHED = 32
I.talents = T
I.talentGen = 0

I.OnBuild(function(def)
    for k in pairs(T.bySpell) do
        T.bySpell[k] = nil
    end
    for k in pairs(T.alias) do
        T.alias[k] = nil
    end
    local list = def.talents
    T.n = #list
    for k = 1, T.n do
        local d = list[k]
        T.key[k], T.spell[k], T.max[k], T.rank[k] = d.key, d.spell, d.max or 1, 0
        T.bySpell[d.spell] = k
    end
    -- the pack's aliases (VirtualState.Track{ talents = { [rankSpell] = registeredSpell } })
    for alias, spell in pairs(I.extra.talents) do
        local k = T.bySpell[spell]
        if k then
            T.bySpell[alias], T.alias[alias] = k, true
        end
    end
end)

--- Sets talent k's rank (the walk, Sources/Talents.lua); bumps TalentGen when it changed. True when it changed.
function I.SetTalentRank(k, rank)
    if T.rank[k] ~= rank then
        T.rank[k] = rank
        I.talentGen = I.talentGen + 1
        return true
    end
    return false
end

--- (spec §3.1) The rank of the talent registered with spell ID `talentID` (0 when not taken or not tracked).
function VS.Talent(talentID)
    local k = T.bySpell[talentID]
    return k and T.rank[k] or 0
end

--- (spec §3.1) Bumped when any rank changes.
function VS.TalentGen()
    return I.talentGen
end

I.OnSnapshot(function(out)
    local line = string.format("talent walk unmatched: %d", T.nUnmatched)
    if T.nUnmatched > 0 then
        line = line .. " [" .. table.concat(T.unmatched, " ", 1, math.min(T.nUnmatched, I.TALENT_UNMATCHED)) .. "]"
    end
    out[#out + 1] = line
    for k = 1, T.n do
        out[#out + 1] = string.format("talent %s spell=%d rank=%d/%d", tostring(T.key[k]), T.spell[k], T.rank[k], T.max[k])
    end
end)
