-- Game/State/Sources/Forms.lua
-- Shapeshift form sources: stances are forms, not buffs, so the aura walk never lists them. At the first poll after
-- build and the poll after each UPDATE_SHAPESHIFT_FORM, the plain form reads (GetShapeshiftForm,
-- GetShapeshiftFormInfo's 4th return: the form's spell ID) put each tracked player aura that is a form up with no
-- expiry (the active one) or down (the rest), as the walk's own `Read`s. The walk leaves a form aura it did not find
-- alone (I.formAura): the form reads own it, until a read that is not plain hands it back to the walk. A form the walk
-- also lists (Druid forms) reads the same from both: no expiry, 1 stack.
-- Stealth (C5) follows the same pattern: a player aura flagged `isStealthed` is put up with no expiry or down from
-- IsStealthed (no SecretWhen* flag in the API docs, but unprobed in combat: Rogue Q5) at the same polls and after
-- UPDATE_STEALTH; a secret answer reads nothing and hands the aura back to the walk.
-- Credits: secret-value handling after Catnip's (Durts) research.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, ReadOf = VS.Obs, I.ReadOf
local Plain, Direct = S.Plain, S.Direct

-- By player aura index: true once a form read named it. Sources/Auras.lua's walk skips these when logging misses.
local isForm = {}
I.formAura = isForm
local pending = false
-- By spell ID: true once this build warned that the form's spell matches no registered aura.
local warned = {}
local UNTRACKED = "Forever: shapeshift form %d (spell %d) matches no registered aura; the belief cannot see this form"
-- The player auras flagged `isStealthed`: their indices 1..n (the facade's IsStealthed policy reads them too).
local stealth = { n = 0 }
I.stealthAuras = stealth

I.OnBuild(function(def)
    for j in pairs(isForm) do
        isForm[j] = nil
    end
    stealth.n = 0
    for j = 1, #def.auras do
        if rawget(def.auras[j], "isStealthed") == true then
            stealth.n = stealth.n + 1
            stealth[stealth.n] = j
        end
    end
    for id in pairs(warned) do
        warned[id] = nil
    end
    pending = true
end)

-- The client calls, where they are read (the secrets check sees them); each is pcall'd and its answer Plained.
local function activeForm(api)
    return api.GetShapeshiftForm() -- secret: Plain by the caller
end
local function numForms(api)
    return api.GetNumShapeshiftForms() -- secret: Plain by the caller
end

-- Logs every tracked form aura up (the active form) or down at t; warns once per build about an untracked form.
-- Allocates nothing but that warning.
local function read(api, t)
    local okA, rawActive = pcall(activeForm, api)
    local okN, rawN = pcall(numForms, api)
    local active, n = okA and Plain(api, rawActive), okN and Plain(api, rawN)
    if type(active) ~= "number" or type(n) ~= "number" then
        for j in pairs(isForm) do -- unread forms: the walk owns those auras again
            isForm[j] = nil
        end
        return
    end
    local bySpell = I.auras.bySpell
    for i = 1, n do
        local ok, _, _, _, rawSpell = pcall(api.GetShapeshiftFormInfo, i) -- secret: Plain next
        local spell = ok and Plain(api, rawSpell)
        local j = bySpell[spell or false]
        if j then
            isForm[j] = true
            Direct(Obs.Read, t, j, i == active and -1 or 0, ReadOf.Aura) -- a = j: unit 1, the player
        elseif type(spell) == "number" and not warned[spell] and ns.Error then -- Utils.lua loads after Game/
            warned[spell] = true
            ns.Error(UNTRACKED, i, spell) -- formats only here: once per spell per build
        end
    end
end

local function stealthed(api)
    return api.IsStealthed() -- secret: Plain by the caller
end

-- Logs every `isStealthed` aura up (no expiry) or down at t from one plain IsStealthed read; a secret or failed read
-- logs nothing and hands those auras back to the walk. Allocates nothing.
local function readStealth(api, t)
    if stealth.n == 0 then
        return
    end
    local ok, raw = pcall(stealthed, api)
    local on = ok and Plain(api, raw)
    for k = 1, stealth.n do
        local j = stealth[k]
        if type(on) == "boolean" then
            isForm[j] = true
            Direct(Obs.Read, t, j, on and -1 or 0, ReadOf.Aura)
        else
            isForm[j] = nil
        end
    end
end

-- The read waits for the poll, which runs after the frame's staged casts are flushed: a stance cast's modelled
-- expiry folds first and the read's no-expiry lands after it.
local function changed()
    pending = true
end
S.On("UPDATE_SHAPESHIFT_FORM", nil, changed)
S.On("UPDATE_STEALTH", nil, changed)

-- Poll 9: the first read after a build or a form or stealth event.
S.Poll(9, function(api, t)
    if pending then
        pending = false
        read(api, t)
        readStealth(api, t)
    end
end)
