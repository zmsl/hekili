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
local WHITE = "Interface\\Buttons\\WHITE8X8"
local VEIL_ALPHA = 0.5
local SETTLE = 0.1 -- spec §3.2: how long a "back to ready" must hold

local Truth = {}

-- Overlays gated on an in-game probe stay off in code until the ledger row passes (M1).
Truth.VERIFIED = { strip = false, execute = false, ride = false, cdm = false }

Truth.EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE" }

local function register( d )
    for _, e in ipairs( Truth.EVENTS ) do d:RegisterEvent( e ) end
end

-- Less ready shows at once; back to ready once the wanted state held SETTLE seconds or Output.hold publishes, or at
-- once after our own cast (out.acts moved) (spec §3.2). `g.ready` is the shown state.
local function settle( g, want, now, ver, acts )
    if want ~= g.want then g.want, g.since, g.ver, g.acts = want, now, ver, acts end
    if not want then g.ready = false
    elseif not g.ready and ( now - g.since >= SETTLE or ver - g.ver >= ns.Output.hold or acts ~= g.acts ) then g.ready = true end
    return g.ready
end

-- A spell change: the new state is shown with no debounce.
local function reset( g, want, now, ver, acts )
    g.want, g.ready, g.since, g.ver, g.acts = want, want, now, ver, acts
end

-- Shows or hides the veil when the dim changed.
local function applyDim( ov, conf )
    local dim = conf.truth.edge and ov.spell > 0 and not ov.dim.ready or false
    if dim ~= ov.dimShown then
        ov.dimShown = dim
        ov.veil:SetShown( dim )
    end
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

local function clearOv( ov )
    if ov.veil then ov.veil:Hide() end
    ov.dimShown, ov.usable = false, true
    reset( ov.dim, true, 0, 0, 0 )
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
        if not ov.top then
            ov.dim = { ready = true, want = true, since = 0, ver = 0, acts = 0 }
            ov.top = CreateFrame( "Frame", nil, b )
            ov.top:SetAllPoints( b )
            ov.top:SetFrameLevel( b:GetFrameLevel() + 3 )
            ov.veil = ov.top:CreateTexture( nil, "OVERLAY" )
            ov.veil:SetAllPoints( ov.top )
            ov.veil:SetTexture( b.round and CIRCLE or WHITE )
            ov.veil:SetVertexColor( 0, 0, 0, VEIL_ALPHA )
            ov.veil:Hide()
        end
        if b.Cooldown and not ov.cd then makeSwipe( ov, b ) end
        clearOv( ov )
    end
    S.ov = set
    register( d )
    S.cleared = false
end

function Truth.Tick( d, conf, out, now )
    local S = d.truthState
    S.out = out -- for OnGameEvent, which is handed none
    local set, ver, acts = S.ov, out.version, out.acts
    for c = 1, #set do
        local ov = set[ c ]
        settle( ov.dim, ov.usable, now, ver, acts )
        applyDim( ov, conf )
    end
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
            ov.usable = spell == 0 or ( C_Spell.IsSpellUsable( spell ) ) and true or false
            reset( ov.dim, ov.usable, Facade.GetTime(), out.version, out.acts )
            applyDim( ov, conf )
        end
        local hid = b.timersHidden == true
        if hid ~= ov.hid then ov.hid, ov.dirty = hid, true end
        apply( ov )
        if ov.cdShown then b.Cooldown:Hide() end -- a style may re-show its own (Timeline's reveal)
    end
end

function Truth.OnGameEvent( d, conf, event, ... )
    local S = d.truthState
    local set, out, now = S.ov, S.out, Facade.GetTime()
    if event == "SPELL_UPDATE_USABLE" then
        if not out then return end
        for c = 1, #set do
            local ov = set[ c ]
            if ov.spell > 0 then
                ov.usable = ( C_Spell.IsSpellUsable( ov.spell ) ) and true or false
                settle( ov.dim, ov.usable, now, out.version, out.acts )
                applyDim( ov, conf )
            end
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        for c = 1, #set do
            local ov = set[ c ]
            if ov.spell > 0 then
                swipe( ov, conf )
                apply( ov )
            end
        end
    end
end

function Truth.Clear( d )
    local S = d.truthState
    if not S then return end
    for _, e in ipairs( Truth.EVENTS ) do d:UnregisterEvent( e ) end
    for c = 1, #S.ov do clearOv( S.ov[ c ] ) end
    S.cleared = true
end

ns.UI.Truth = Truth
