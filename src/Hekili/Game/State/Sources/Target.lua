-- Game/State/Sources/Target.lua
-- Target sources (spec §4.2): PLAYER_TARGET_CHANGED keeps a target -> memory slot map (TARGET_CAP slots, the least
-- recently used reused) keyed by GUID, or under Map (the GUID secret) by the target's plate index, forgotten at either
-- edge of that plate (tab-targeting T2m; no plate: no memory), and logs `TargetSwap` (a: the slot, 0 no target; b: 1 a
-- slot newly taken by a GUID; c: 1 plain UnitCanAttack) straight to the log, then walks the new target's auras; each
-- swap bumps I.targetSwapN (the pending-swap serial, lane A); poll 4 logs `TargetGone` for a dead target;
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

-- By memory slot: its key and when it was last the target. The key: the target's GUID (a string) while it reads plain;
-- under Map (the GUID secret) the index 1..40 of the plate that is the target (a number: never equal to a GUID, so the
-- two key spaces cannot collide; a friendly target read plain under Map is keyed by its GUID); "" free; false: an
-- orphan, the current target's slot whose plate left (no key finds it again; forgotten at the next swap).
local guid, used = {}, {}
for s = 1, I.TARGET_CAP do
    guid[s], used[s] = "", 0
end
local tokenMode = false -- the key space (true: plate indices): set by a secret target, cleared by a hostile plain one
local forgetN, noPlateN = 0, 0 -- slots forgotten by plate edges and flips; Map swaps no plate answered (snapshot)
I.targetKeys = guid -- read-only, for tests

-- Forgets slot s: the current target's becomes an orphan with no log entry (a TargetGone on the current slot reads as
-- its death, Families/Auras.lua and TargetHealth.lua: review F4), any other is logged gone and freed.
local function forget(s, t)
    forgetN = forgetN + 1
    if s == I.targetSlot then
        guid[s] = false
    else
        Direct(Obs.TargetGone, t, s)
        guid[s] = ""
    end
end
local function forgetAll(t)
    for s = 1, I.TARGET_CAP do
        if guid[s] ~= "" then
            forget(s, t)
        end
    end
end
local dead = false
local HUGE = math.huge
local lastLo, lastHi = -1, -1 -- the bracket last logged (-1: none since the swap or the age-out)
local plainT = 0 -- the last plain range answer's time
local RANGE_AGE = 1.5 -- seconds with no plain answer before a held bracket goes unknown (batch review I1)
I.targetSlot = 0 -- the memory slot the last swap logged (0: no target)
I.targetSwapN = 0 -- each swap's serial; Families/Auras.lua copies it at the fold (a slot is 0 for every secret GUID)
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

-- The index of the active plate whose unit is the target (a plain UnitIsUnit true), 0 none. At most 40 reads, once per
-- target change, never in a poll; a secret or false answer is "not this one".
local function plateOfTarget(api)
    local P = I.Plates
    for k = 1, #P.token do
        if P.active[k] and Plain(api, api.UnitIsUnit("target", P.token[k])) == true then
            return k
        end
    end
    return 0
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
    local secret = g == "" and I.Units.Secret(api, 1) -- Map: a target is there, its GUID unreadable
    local mode = tokenMode -- no target: the key space stands
    if secret then
        mode = true
    elseif g ~= "" and (not tokenMode or Plain(api, api.UnitCanAttack("player", "target")) == true) then
        -- (review m1) under Map only a hostile plain GUID leaves the plate keys: self or a party member (if plain,
        -- probe TP6) keeps them, keyed by its GUID string
        mode = false
    end
    if mode ~= tokenMode then -- (review F6) the key spaces never meet: a flip forgets every slot
        forgetAll(t)
        tokenMode = mode
    end
    local key = g
    if secret then
        key = plateOfTarget(api) -- 0: no plate answers (plates off, out of plate range): no memory
        if key == 0 then
            noPlateN = noPlateN + 1
        end
    end
    local old = I.targetSlot
    local s, fresh = 0, false
    if key ~= "" and key ~= 0 then
        s, fresh = slotFor(key, t)
    end
    local attackable = s > 0 and Plain(api, api.UnitCanAttack("player", "target")) == true
    dead, lastLo, lastHi = false, -1, -1
    -- (review F11) a plate slot is never "fresh": a plate index newly keyed says nothing of the mob's health
    Direct(Obs.TargetSwap, t, s, fresh and not tokenMode and 1 or 0, attackable and 1 or 0)
    if old > 0 and guid[old] == false then -- the orphan: its record was saved by this swap's fold, then forgotten
        Direct(Obs.TargetGone, t, old)
        guid[old] = ""
    end
    I.targetSlot = s -- the slot this swap names; I.curSlot follows at its fold
    I.targetSwapN = I.targetSwapN + 1 -- I.curSwapN copies it at the fold (Sources/Auras.lua waits for it)
    if s > 0 and I.auras.n >= 2 then
        I.WalkAuras(api, 2, "target", t)
    end
end

S.On("PLAYER_TARGET_CHANGED", nil, function(api, t)
    swap(api, t)
end)
S.OnStart(swap)
I.OnBuild(function(def, now)
    if tokenMode then -- the build made the memory arrays anew and cleared the log: no plate key survives it
        for s = 1, I.TARGET_CAP do
            guid[s] = ""
        end
    end
    -- the build cleared the log: no swap waits. Set here, before this hook's swap bumps I.targetSwapN, so it holds
    -- whatever order the build hooks run in (review m6)
    I.curSwapN = I.targetSwapN
    if I.api then
        swap(I.api, now)
    end
end)
-- A world entry that is no rebuild (a zone change): the plates are new, so is every plate key.
S.On("PLAYER_ENTERING_WORLD", nil, function(api, t)
    if tokenMode then
        forgetAll(t)
    end
end)

--- Snapshot's line (allocates; debugging only): the key space, the current slot, the keys held, an orphan, and the
--- counters (slots forgotten by plate edges and flips; Map target changes no plate answered).
I.OnSnapshot(function(out)
    local keys, orphan = 0, 0
    for s = 1, I.TARGET_CAP do
        if guid[s] == false then
            orphan = 1
        elseif guid[s] ~= "" then
            keys = keys + 1
        end
    end
    out[#out + 1] = string.format(
        "target slots mode=%s cur=%d keys=%d orphan=%d forget=%d noPlate=%d",
        tokenMode and "token" or "guid",
        I.curSlot,
        keys,
        orphan,
        forgetN,
        noPlateN
    )
end)

-- A plate's ADDED or REMOVED (review F3: both edges, a token may change mob at either): the memory keyed by it is
-- forgotten. A GUID key never equals a plate index. Allocates nothing.
local function plateEdge(api, t, unit)
    local i = unit and I.Units.INDEX[unit]
    if not i then
        return
    end
    local k = i - 2 -- nameplateK is the registry's token K + 2
    for s = 1, I.TARGET_CAP do
        if guid[s] == k then
            forget(s, t)
            return
        end
    end
end
S.On("NAME_PLATE_UNIT_ADDED", nil, plateEdge)
S.On("NAME_PLATE_UNIT_REMOVED", nil, plateEdge)

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
-- no plain answer keeps the last for under RANGE_AGE s, then logs it unknown once (TargetRange a = -1: a secret,
-- raising or silent library never freezes the bracket for the fight). Allocates nothing once `answer` has grown to
-- the ability count.
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
        plainT = t
        hi = type(hi) == "number" and hi or HUGE -- no upper bound: past the library's last check
        if lo ~= lastLo or hi ~= lastHi then
            lastLo, lastHi = lo, hi
            Direct(Obs.TargetRange, t, lo, hi)
        end
    elseif lastLo >= 0 and t - plainT >= RANGE_AGE then -- a bracket held: a target since the last swap
        lastLo, lastHi = -1, -1 -- the next plain answer is logged, the same bracket too
        Direct(Obs.TargetRange, t, -1, HUGE)
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
