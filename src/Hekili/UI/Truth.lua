local _, ns = ...
-- UI/Truth.lua: the truth layer behind a display's Modern toggle (Modern display spec §5.1-5.2, decision M2). Core
-- attaches it to the bound style's buttons (UI/UI.lua bindStyle) and calls it right after each style member, only
-- while displays[ id ].truth.enabled is on; no style wraps another. It is the only reader of Facade.Display
-- (tools/check_api_reads.sh). It reads the optional button contract (recIndex, isFocus, round, timersHidden, Cooldown;
-- UI/Styles.lua), the published records, d.resolved, plain facade rows and conf.truth; never a style's subtable.
-- Its glow helper use follows Classic's (UI/Styles/Classic.lua): Hekili code by Hekili's authors and maintainers.
-- Phase 1, Task 3: lifecycle only (overlays, events); Tasks 4-6 add the swipe, the edge and the proc mark.

local Truth = {}

-- Overlays gated on an in-game probe stay off in code until the ledger row passes (M1).
Truth.VERIFIED = { strip = false, execute = false, ride = false, cdm = false }

Truth.EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE" }

local function register( d )
    for _, e in ipairs( Truth.EVENTS ) do d:RegisterEvent( e ) end
end

local function reset( ov )
    ov.spell = 0
    ov.press = false
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
        if not set[ c ] then set[ c ] = { spell = 0, press = false } end
        reset( set[ c ] )
    end
    S.ov = set
    register( d )
    S.cleared = false
end

function Truth.Tick( d, conf, out, now )
end

-- After a Clear (an unsubscribe), the next draw brings the events back.
function Truth.Draw( d, conf, out )
    local S = d.truthState
    if S.cleared then
        register( d )
        S.cleared = false
    end
end

function Truth.OnGameEvent( d, conf, event, ... )
end

function Truth.Clear( d )
    local S = d.truthState
    if not S then return end
    for _, e in ipairs( Truth.EVENTS ) do d:UnregisterEvent( e ) end
    for c = 1, #S.ov do reset( S.ov[ c ] ) end
    S.cleared = true
end

ns.UI.Truth = Truth
