-- Game/State/Sources/Target.lua
-- Target sources (spec §4.2): PLAYER_TARGET_CHANGED keeps a GUID -> memory slot map (TARGET_CAP slots, the least
-- recently used reused) and logs `TargetSwap` (a: the slot, 0 no target; b: 1 a slot newly taken; c: 1 plain
-- UnitCanAttack) straight to the log, then walks the new target's auras; poll 4 logs `TargetGone` for a dead target;
-- the target's UNIT_SPELLCAST_* events become `TargetCast` observations by castBarID (plain; the spellID and castGUID
-- are secret on the target).
-- The target's UNIT_COMBAT WOUND amounts become `TargetDamage` (b: the amount; target-health design §2.3c).
-- Poll 14 brackets the target's distance from each tracked ability's range (Spellbook.lua's rMin/rMax) and its plain
-- C_Spell.IsSpellInRange (plain in combat, probe W PR7; a secret or nil answer is skipped) into `TargetRange`.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Target.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, Of = VS.Obs, I.TargetCastOf
local Plain, Stage, Direct = S.Plain, S.Stage, S.Direct

-- By memory slot: the GUID it holds ("" free) and when it was last the target.
local guid, used = {}, {}
for s = 1, I.TARGET_CAP do
    guid[s], used[s] = "", 0
end
local dead = false
local HUGE = math.huge
local lastLo, lastHi = -1, -1 -- the bracket last logged (-1: none since the swap)
local answer = {} -- by ability index: this poll's plain answer (true, false, or nil)

local function slotFor(g, t)
    local free, oldest = 0, 1
    for s = 1, I.TARGET_CAP do
        if guid[s] == g then
            used[s] = t
            return s, false
        elseif guid[s] == "" and free == 0 then
            free = s
        elseif used[s] < used[oldest] then
            oldest = s
        end
    end
    local s = free > 0 and free or oldest
    if guid[s] ~= "" then
        Direct(Obs.TargetGone, t, s)
    end
    guid[s], used[s] = g, t
    return s, true -- newly taken: a GUID not held before (or forgotten)
end

-- A target swap: the new target's memory slot, then a walk of its auras. Also at Start and at each rebuild, so a
-- target already held at a /reload gets its slot (poll 4 then sees its death, a swap away keeps what was believed).
-- No "built" guard: in game Start (PLAYER_LOGIN) comes before the first build (PLAYER_ENTERING_WORLD), and I.Build
-- runs its hooks before it marks the set built; the slot map lives here, and a swap logged before a build is cleared
-- by that build, which logs its own.
local function swap(api, t)
    local g = Plain(api, api.UnitGUID("target"))
    local s, fresh = 0, false
    if type(g) == "string" then
        s, fresh = slotFor(g, t)
    end
    local attackable = s > 0 and Plain(api, api.UnitCanAttack("player", "target")) == true
    dead, lastLo, lastHi = false, -1, -1
    Direct(Obs.TargetSwap, t, s, fresh and 1 or 0, attackable and 1 or 0)
    if s > 0 and I.auras.n >= 2 then
        I.WalkAuras(api, 2, "target", t)
    end
end

S.On("PLAYER_TARGET_CHANGED", nil, function(api, t)
    swap(api, t)
    S.Urgent("PLAYER_TARGET_CHANGED")
end)
S.OnStart(swap)
I.OnBuild(function(def, now)
    if I.api then
        swap(I.api, now)
    end
end)

-- Poll 4: the target's death (plain UnitIsDead) forgets what we believed about it.
S.Poll(4, function(api, t)
    if I.curSlot == 0 then
        return
    end
    local d = Plain(api, api.UnitIsDead("target")) == true
    if d and not dead then
        Direct(Obs.TargetGone, t, I.curSlot)
    end
    dead = d
end)

-- Poll 14: the target's distance bracket. An answer in range puts it within [min, max]; out of a range from 0 past
-- max; out of a band (min > 0) on the side the others leave open (nearer than min when it is within max, else past
-- max). Logged when it changes. Allocates nothing once `answer` has grown to the ability count.
S.Poll(14, function(api, t)
    if I.curSlot == 0 then
        return
    end
    local A = I.ab
    local lo, hi, seen, band = 0, HUGE, false, false
    for a = 1, A.n do
        local r
        if A.rMax[a] > 0 and A.known[a] then
            r = Plain(api, api.C_Spell.IsSpellInRange(A.qid[a], "target"))
            if r == true then
                lo, hi = math.max(lo, A.rMin[a]), math.min(hi, A.rMax[a])
            elseif r == false and A.rMin[a] == 0 then
                lo = math.max(lo, A.rMax[a])
            elseif r == false then
                band = true
            end
            seen = seen or r ~= nil
        end
        answer[a] = r
    end
    if band then
        for a = 1, A.n do
            if answer[a] == false and A.rMin[a] > 0 then
                if hi <= A.rMax[a] then
                    hi = math.min(hi, A.rMin[a])
                elseif lo >= A.rMin[a] then
                    lo = math.max(lo, A.rMax[a])
                end
            end
        end
    end
    if lo > hi then -- the answers disagree (a melee reach beyond its 5 yd, say): the upper bound wins
        lo = hi
    end
    if seen and (lo ~= lastLo or hi ~= lastHi) then
        lastLo, lastHi = lo, hi
        Direct(Obs.TargetRange, t, lo, hi)
    end
end)

-- The target's damage taken (target-health design §2.3c): UNIT_COMBAT's WOUND amount, plain and victim-side (every
-- attacker's hits count: the health moves by everyone's damage). Registered for every unit, as Events/Rows.lua and
-- Attackers.lua register it: a "target" registration would narrow the client's to the target and starve Attackers.lua
-- of the player's.
S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount)
    if unit == "target" and act == "WOUND" and type(amount) == "number" and amount > 0 then
        Direct(Obs.TargetDamage, t, 0, amount) -- logged straight, as the swap: a same-frame WOUND keeps its target
    end
end)

-- `fifth`: the event carries interruptedBy before its castBarID (INTERRUPTED, CHANNEL_STOP).
local function cast(of, fifth)
    return function(api, t, unit, castGUID, spellID, a4, a5)
        if unit == "target" then
            local castBarID = fifth and a5 or a4
            local bar = type(castBarID) == "number" and castBarID or 0
            Stage(Obs.TargetCast, t, of, bar, (of == Of.Start or of == Of.ChannelStart) and -1 or 0)
        end
    end
end
S.On("UNIT_SPELLCAST_START", "target", cast(Of.Start))
S.On("UNIT_SPELLCAST_CHANNEL_START", "target", cast(Of.ChannelStart))
S.On("UNIT_SPELLCAST_STOP", "target", cast(Of.End))
S.On("UNIT_SPELLCAST_CHANNEL_STOP", "target", cast(Of.End, true))
S.On("UNIT_SPELLCAST_INTERRUPTED", "target", cast(Of.Interrupted, true))

S.On("UNIT_SPELLCAST_INTERRUPTIBLE", "target", function(api, t, unit)
    if unit == "target" then
        Stage(Obs.TargetCast, t, Of.Kickable, 0, 1)
    end
end)

S.On("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target", function(api, t, unit)
    if unit == "target" then
        Stage(Obs.TargetCast, t, Of.Kickable, 0, 0)
    end
end)
