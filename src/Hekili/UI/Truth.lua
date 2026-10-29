local _, ns = ...
-- UI/Truth.lua: the truth layer behind a display's Modern toggle (Modern display spec §5.1-5.2, decision M2). Core
-- attaches it to the bound style's buttons (UI/UI.lua bindStyle) and calls it right after each style member, only
-- while displays[ id ].truth.enabled is on; no style wraps another. It is the only reader of Facade.Display
-- (tools/check_api_reads.sh). It reads the optional button contract (recIndex, isFocus, round, timersHidden, Cooldown;
-- UI/Styles.lua), the published records, d.resolved, plain facade rows and conf.truth; never a style's subtable.
-- Its glow helper use follows Classic's (UI/Styles/Classic.lua): Hekili code by Hekili's authors and maintainers.
-- Phase 1: lifecycle, overlays and events (Task 3), the real cooldown swipe (Task 4); Tasks 5-6 add the edge and mark.

local Facade = ns.Facade
local CreateFrame, C_Spell = Facade.CreateFrame, Facade.C_Spell
local Display = ns.Facade.Display
local Registry = Hekili.Engine.Registry

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local Truth = {}

-- Overlays gated on an in-game probe stay off in code until the ledger row passes (M1).
Truth.VERIFIED = { strip = false, execute = false, ride = false, cdm = false }

Truth.EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE" }

local function register( d )
    for _, e in ipairs( Truth.EVENTS ) do d:RegisterEvent( e ) end
end

-- Puts the swipe the button should show on screen, when it changed: the real one while it runs and the style shows
-- timers (RM1: none while b.timersHidden), else the style's own back.
local function apply( ov )
    if not ov.dirty then return end
    ov.dirty = false
    local b = ov.b
    if ov.real and not b.timersHidden then
        ov.cdShown = true
        ov.cd:Show()
        b.Cooldown:Hide()
        -- last: an already-ended duration fires ov.done inside this call, which hands back to the style's swipe
        ov.cd:SetCooldownFromDurationObject( ov.dur ) -- the held duration object goes only here (spec §3.3)
    elseif ov.cdShown then
        ov.cd:Hide()
        b.Cooldown:Show()
        ov.cdShown = false
    end
end

-- The only fetch: on a spell or press change and on the cooldown events. The real cooldown shows only while the plain
-- flags say it runs past the GCD (R2); the press icon's includes the GCD, a queued icon's does not (§3.4, ruling 4).
local function swipe( ov, conf )
    ov.real, ov.dur, ov.dirty = false, nil, true
    if not ( conf.truth.swipes and ov.cd and ov.spell > 0 and not ov.charged ) then return end
    local info = C_Spell.GetSpellCooldown( ov.spell ) -- the hybrid: isActive and isOnGCD are plain
    if info and info.isActive and not info.isOnGCD then
        ov.dur = Display.C_Spell.GetSpellCooldownDuration( ov.spell, not ov.press )
        ov.real = ov.dur ~= nil -- a duration object is userdata, not a secret value (spec §3.3): nil-testing it is safe
    end
end

-- A charge spell (its swipe stays modelled until MD-CH): the spec schema defaults charges to 1 and keeps a function
-- value in funcs, so a plain 1 is the only uncharged value.
local function charged( def )
    if not def then return false end
    local funcs = rawget( def, "funcs" )
    return ( rawget( def, "charges" ) or 1 ) ~= 1 or ( funcs ~= nil and funcs.charges ~= nil )
end

local function reset( ov )
    if ov.cd then ov.cd:Hide() end
    if ov.cdShown then ov.b.Cooldown:Show() end
    ov.spell, ov.press, ov.charged = 0, false, false
    ov.real, ov.dur, ov.cdShown, ov.dirty, ov.hid = false, nil, false, false, false
end

-- One real-swipe frame per button that has a Cooldown (contract §5.1), its look copied from the style's.
local function makeSwipe( ov, b )
    local cd = CreateFrame( "Cooldown", nil, b, "CooldownFrameTemplate" )
    cd:SetAllPoints( b )
    cd:SetFrameLevel( b.Cooldown:GetFrameLevel() )
    cd:SetDrawBling( false )
    cd:SetDrawEdge( false )
    cd:SetHideCountdownNumbers( b.Cooldown:GetHideCountdownNumbers() )
    if b.round then
        cd:SetSwipeTexture( CIRCLE )
        cd:SetUseCircularEdge( true )
    end
    ov.done = function()
        ov.real, ov.dur, ov.dirty = false, nil, true
        apply( ov )
    end
    cd:SetScript( "OnCooldownDone", ov.done )
    cd:Hide()
    ov.cd = cd
end

-- Attaches to `buttons` (the bound style's list): one overlay per button, kept per list in S.sets so a switch back to
-- a style reuses its overlays (WoW cannot free frames).
function Truth.Build( d, conf, buttons )
    local S = d.truthState
    if not S then
        S = { sets = {} }
        d.truthState = S
    end
    S.buttons = buttons
    local set = S.sets[ buttons ]
    if not set then
        set = {}
        S.sets[ buttons ] = set
    end
    for c = 1, #buttons do
        local ov, b = set[ c ], buttons[ c ]
        if not ov then
            ov = {}
            set[ c ] = ov
        end
        ov.b = b
        if b.Cooldown and not ov.cd then makeSwipe( ov, b ) end
        reset( ov )
    end
    S.ov = set
    register( d )
    S.cleared = false
end

function Truth.Tick( d, conf, out, now )
end

-- Runs after the style's Draw. After a Clear (an unsubscribe), the next draw brings the events back.
function Truth.Draw( d, conf, out )
    local S = d.truthState
    if S.cleared then
        register( d )
        S.cleared = false
    end
    local blank = out.count == 0 or out.version == d.blankVersion
    local set, abilities = S.ov, Registry.Abilities()
    for c = 1, #set do
        local ov = set[ c ]
        local b = ov.b
        local i = blank and 0 or b.recIndex or 0
        local press = i == 1
        local rec = i >= 1 and i <= out.count and out.recs[ i ] or nil
        local spell = 0
        if rec and rec.actionName and rec.exact_time and not rec.item and ( rec.actionID or 0 ) > 0 then spell = rec.actionID end
        if spell ~= ov.spell or press ~= ov.press then
            ov.spell, ov.press = spell, press
            ov.charged = spell > 0 and charged( abilities[ rec.actionName ] )
            swipe( ov, conf )
        end
        local hid = b.timersHidden == true
        if hid ~= ov.hid then ov.hid, ov.dirty = hid, true end
        apply( ov )
        if ov.cdShown then b.Cooldown:Hide() end -- a style may re-show its own (Timeline's reveal)
    end
end

function Truth.OnGameEvent( d, conf, event, ... )
    if event ~= "SPELL_UPDATE_COOLDOWN" and event ~= "SPELL_UPDATE_CHARGES" then return end
    local set = d.truthState.ov
    for c = 1, #set do
        local ov = set[ c ]
        if ov.spell > 0 then
            swipe( ov, conf )
            apply( ov )
        end
    end
end

function Truth.Clear( d )
    local S = d.truthState
    if not S then return end
    for _, e in ipairs( Truth.EVENTS ) do d:UnregisterEvent( e ) end
    for c = 1, #S.ov do reset( S.ov[ c ] ) end
    S.cleared = true
end

ns.UI.Truth = Truth
