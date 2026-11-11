-- Game/State/Sources/Target.lua
-- Target sources (spec §4.2): PLAYER_TARGET_CHANGED keeps a GUID -> memory slot map (TARGET_CAP slots, the least
-- recently used reused) and logs `TargetSwap` (a: the slot, 0 no target; b: 1 a slot newly taken; c: 1 plain
-- UnitCanAttack) straight to the log, then walks the new target's auras; poll 4 logs `TargetGone` for a dead target;
-- the target's UNIT_SPELLCAST_* events become `TargetCast` observations by castBarID (plain; the spellID and castGUID
-- are secret on the target).
-- The target's UNIT_COMBAT WOUND amounts become `TargetDamage` (b: the amount; target-health design §2.3c).
-- Poll 14 keeps each tracked ability's plain C_Spell.IsSpellInRange (plain in combat, probe W PR7; Spellbook.lua's
-- rMax: 0 is never asked) for action.<key>.in_range, and logs LibRangeCheck's bracket of the target's distance
-- (the facade's RangeLib, range plan R2) as `TargetRange`.
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
I.targetSlot = 0 -- the memory slot the last swap logged (0: no target)
local answer = {} -- by ability index: this poll's plain answer (true, false, or 0 for none)
I.rangeAnswer = answer -- Families/Now.lua's action.<key>.in_range reads it

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
    -- the registry bound it first (its PLAYER_TARGET_CHANGED handler is registered earlier); the pin binds it for a
    -- build before Start (headless), and its soft-enemy fallback never reaches token 1
    I.Units.Pin(api, t)
    local g = I.Units.Bound(1)
    local s, fresh = 0, false
    if g ~= "" then
        s, fresh = slotFor(g, t)
    end
    local attackable = s > 0 and Plain(api, api.UnitCanAttack("player", "target")) == true
    dead, lastLo, lastHi = false, -1, -1
    Direct(Obs.TargetSwap, t, s, fresh and 1 or 0, attackable and 1 or 0)
    I.targetSlot = s -- the slot this swap names; I.curSlot follows at its fold (Sources/Auras.lua waits for it)
    if s > 0 and I.auras.n >= 2 then
        I.WalkAuras(api, 2, "target", t)
    end
end

S.On("PLAYER_TARGET_CHANGED", nil, function(api, t)
    swap(api, t)
end)
S.OnStart(swap)
I.OnBuild(function(def, now)
    if I.api then
        swap(I.api, now)
    end
end)

-- Poll 4: the target's plain death goes to the registry, which tells every listener once (OnGone DEAD, below).
S.Poll(4, function(api, t)
    if I.curSlot == 0 then
        return
    end
    local d = Plain(api, api.UnitIsDead("target")) == true
    if d and not dead then
        I.Units.Dead(I.Units.Uid(1), t)
    end
    dead = d
end)

-- Poll 14: each tracked ability's plain range answer (action.<key>.in_range) while the target holds a memory slot,
-- and the target's distance bracket, LibRangeCheck's (range plan R2: the facade's RangeLib; asked whenever there is
-- a target, a secret GUID's too, which takes no slot under the Map restriction). Logged when it changes; a poll with
-- no plain answer keeps the last. Allocates nothing once `answer` has grown to the ability count.
S.Poll(14, function(api, t)
    if I.curSlot ~= 0 then
        local A = I.ab
        for a = 1, A.n do
            local r
            if A.rMax[a] > 0 and A.known[a] then
                r = Plain(api, api.C_Spell.IsSpellInRange(A.qid[a], "target"))
            end
            if r == nil then
                r = 0 -- never nil: a hole drops the key at the next rehash and re-adding it grows the table again (gap CD)
            end
            answer[a] = r
        end
    end
    local lo, hi = ns.Facade.RangeLib("target") -- nil without a target (the library's own UnitExists test)
    lo, hi = Plain(api, lo), Plain(api, hi)
    if type(lo) == "number" then
        hi = type(hi) == "number" and hi or HUGE -- no upper bound: past the library's last check
        if lo ~= lastLo or hi ~= lastHi then
            lastLo, lastHi = lo, hi
            Direct(Obs.TargetRange, t, lo, hi)
        end
    end
end)

-- The target's damage taken (target-health design §2.3c): the registry's rows about the current target's unit, any
-- token (every attacker's hits count). A dead unit's memory slot forgets it at its death (unit-registry spec §4.3),
-- from whichever tell came first. Registered at Start: Rows' listener (loaded later) must see each row first.
-- A secret amount (live, L67): no TargetDamage; the health estimate moves only on its plain reads, never a guess.
local function damage(t, g, uid, act, flag, amount)
    if act == "WOUND" and type(amount) == "number" and amount > 0 and uid == I.Units.Uid(1) then
        Direct(Obs.TargetDamage, t, 0, amount) -- logged straight, as the swap: a same-frame WOUND keeps its target
    end
end
local function died(uid, g, why, t)
    if why ~= I.Units.DEAD then
        return
    end
    for s = 1, I.TARGET_CAP do
        if guid[s] == g then
            Direct(Obs.TargetGone, t, s)
            return
        end
    end
end
S.OnStart(function()
    I.Units.OnRow(damage)
    I.Units.OnGone(died)
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
