-- Game/State/Sources/Power.lua
-- Power sources (spec §4.2, §4.3): UNIT_POWER_FREQUENT ticks, max reads, poll 1 (readable resources, their maxima,
-- the out-of-combat regen read) and poll 2 (the usability ladder: C_Spell.IsSpellUsable per tracked spender, a
-- secret in either return being no news), plus the usability events (urgent: a flip is news).
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Power.lua (the usability ladder :64-99, Sources.Usability at :70).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, ReadOf = VS.Obs, I.ReadOf
local Plain, Stage, Direct, Note = S.Plain, S.Stage, S.Direct, S.Note

-- By ability index: the last usability answer reported (-1 none, 0 not, 1 usable, 2 short).
local last = {}

-- Asks every tracked spender (an ability whose cost is paid from a tracked resource). `onlyChanged`: report only
-- the answers that changed (the events); `direct`: into the log (the poll) rather than staged. True when any
-- answer changed. Allocates nothing.
local function usability(api, t, onlyChanged, direct)
    local A = I.ab
    local any = false
    for a = 1, A.n do
        if A.slot[a] > 0 then
            local rawOk, rawShort = api.C_Spell.IsSpellUsable(A.qid[a]) -- secret: both tested with issecretvalue next
            if api.issecretvalue(rawOk) or api.issecretvalue(rawShort) then
                Note("IsSpellUsable", "secret")
            else
                local ok, short = Plain(api, rawOk), Plain(api, rawShort)
                if ok ~= nil then
                    Note("IsSpellUsable", "readable")
                    local state = ok and 1 or (short and 2 or 0)
                    if last[a] ~= state then
                        any = true
                    end
                    if not onlyChanged or last[a] ~= state then
                        last[a] = state
                        local b, c = ok and 1 or 0, (not ok and short) and 1 or 0
                        if direct then
                            Direct(Obs.Usable, t, a, b, c)
                        else
                            Stage(Obs.Usable, t, a, b, c)
                        end
                    end
                end
            end
        end
    end
    return any
end

I.OnBuild(function(def)
    for a = 1, #def.abilities do
        last[a] = -1
    end
end)

local function onUsable(api, t)
    if I.built and usability(api, t, true, false) then
        S.Urgent("VS_USABLE")
    end
end
S.On("SPELL_UPDATE_USABLE", nil, onUsable)
S.On("ACTION_USABLE_CHANGED", nil, onUsable)

S.On("UNIT_POWER_FREQUENT", "player", function(api, t, unit, token)
    local r = unit == "player" and token and I.res.slotOfToken[token]
    if r then
        Stage(Obs.PowerTick, t, r)
    end
end)

local function readMax(api, t, direct)
    local R = I.res
    for r = 1, R.n do
        local raw = api.UnitPowerMax("player", R.type[r]) -- secret: Plain next
        local max = Plain(api, raw)
        if type(max) == "number" and max > 0 and max ~= R.max[r] then
            if direct then
                Direct(Obs.Read, t, r, max, ReadOf.Max)
            else
                Stage(Obs.Read, t, r, max, ReadOf.Max)
            end
        end
    end
end

S.On("UNIT_MAXPOWER", "player", function(api, t, unit)
    if unit == "player" then
        readMax(api, t, false)
    end
end)

S.On("UNIT_DISPLAYPOWER", "player", function(api, t, unit)
    if unit == "player" then
        readMax(api, t, false)
    end
end)

-- Poll 1: readable resources (types plain in combat, e.g. combo points), maxima, the out-of-combat regen read.
S.Poll(1, function(api, t)
    local R = I.res
    readMax(api, t, true)
    for r = 1, R.n do
        local raw = api.UnitPower("player", R.type[r]) -- secret: Plain next
        Note("UnitPower", S.StatusOf(api, raw))
        local v = Plain(api, raw)
        if type(v) == "number" then
            Direct(Obs.Read, t, r, v, ReadOf.Resource)
        end
        if not I.inCombat and R.swing[r] == 0 then
            local rawIn, rawAct = api.GetPowerRegenForPowerType(R.type[r]) -- secret: Plain next
            local act = Plain(api, rawAct)
            -- A 0 for a slot resting at its maximum is a form that does not regenerate it (a pull from Bear Form): skip.
            if
                Plain(api, rawIn) ~= nil
                and type(act) == "number"
                and act ~= R.regE[r]
                and (act ~= 0 or not R.restMax[r])
            then
                Direct(Obs.Read, t, r, act, ReadOf.Regen)
            end
        end
    end
end)

-- Poll 2: the usability ladder, every answer a rung.
S.Poll(2, function(api, t)
    usability(api, t, false, true)
end)
