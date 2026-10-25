-- ForeverProbe: is the player's attack power readable in combat?
-- /apsecret start [seconds]   sample every 0.25 s (default 60 s), then print a summary
-- /apsecret stop               stop early and print
-- /apsecret                    print the current tallies
-- /apsecret show               toggle a frame that draws AP via SetFormattedText (works on a secret value)
--
-- Samples, each tick, in and out of combat separately: UnitAttackPower("player") (base, positive buff, negative buff),
-- UnitRangedAttackPower("player"), UnitStat("player", 1) (strength) and UnitStat("player", 2) (agility). Nothing
-- compares or does maths on a secret: only issecretvalue() and type() are applied to reads.

local tallies, ticker, started

local function newTally()
    return { n = 0, secret = 0, plain = 0, nilv = 0, min = nil, max = nil }
end

local READS = { "ap_base", "ap_pos", "ap_neg", "rap_base", "rap_pos", "rap_neg", "strength", "agility" }

local function newSide()
    local s = {}
    for _, k in ipairs( READS ) do s[ k ] = newTally() end
    return s
end

local function reset()
    tallies = { combat = newSide(), ooc = newSide() }
end

local function note( t, v )
    t.n = t.n + 1
    if v == nil then t.nilv = t.nilv + 1 return end
    if issecretvalue and issecretvalue( v ) then t.secret = t.secret + 1 return end
    t.plain = t.plain + 1
    if type( v ) == "number" then
        if not t.min or v < t.min then t.min = v end
        if not t.max or v > t.max then t.max = v end
    end
end

local function sample()
    local side = InCombatLockdown() and tallies.combat or tallies.ooc
    local ok, a, b, c
    ok, a, b, c = pcall( UnitAttackPower, "player" )
    if ok then note( side.ap_base, a ); note( side.ap_pos, b ); note( side.ap_neg, c )
    else note( side.ap_base, nil ); note( side.ap_pos, nil ); note( side.ap_neg, nil ) end
    ok, a, b, c = pcall( UnitRangedAttackPower, "player" )
    if ok then note( side.rap_base, a ); note( side.rap_pos, b ); note( side.rap_neg, c )
    else note( side.rap_base, nil ); note( side.rap_pos, nil ); note( side.rap_neg, nil ) end
    ok, a = pcall( UnitStat, "player", 1 ); note( side.strength, ok and a or nil )
    ok, a = pcall( UnitStat, "player", 2 ); note( side.agility, ok and a or nil )
end

local function line( name, t )
    return string.format( "  %s: n=%d plain=%d secret=%d nil=%d range=%s..%s", name, t.n, t.plain, t.secret, t.nilv,
        tostring( t.min ), tostring( t.max ) )
end

local function report()
    for _, k in ipairs( { "combat", "ooc" } ) do
        print( string.format( "|cff00ff00AP secrecy|r %s:", k ) )
        for _, r in ipairs( READS ) do print( line( r, tallies[ k ][ r ] ) ) end
    end
end

-- /apsecret show: a small frame that renders the raw reads through FontString:SetFormattedText, which the client
-- marks "secretArguments: AllowedWhenTainted": a secret AP still draws, while the addon never inspects it.
local panel
local function showPanel()
    if not panel then
        panel = CreateFrame( "Frame", "ForeverProbeAP", UIParent, "BackdropTemplate" )
        panel:SetSize( 260, 70 )
        panel:SetPoint( "CENTER", 0, 200 )
        panel:SetBackdrop( { bgFile = "Interface\\Buttons\\WHITE8X8" } )
        panel:SetBackdropColor( 0, 0, 0, 0.7 )
        panel:SetMovable( true ); panel:EnableMouse( true ); panel:RegisterForDrag( "LeftButton" )
        panel:SetScript( "OnDragStart", panel.StartMoving )
        panel:SetScript( "OnDragStop", panel.StopMovingOrSizing )
        panel.ap = panel:CreateFontString( nil, "OVERLAY", "GameFontNormalLarge" )
        panel.ap:SetPoint( "TOP", 0, -8 )
        panel.rap = panel:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
        panel.rap:SetPoint( "TOP", panel.ap, "BOTTOM", 0, -4 )
        panel.flag = panel:CreateFontString( nil, "OVERLAY", "GameFontHighlightSmall" )
        panel.flag:SetPoint( "BOTTOM", 0, 6 )
        panel:SetScript( "OnUpdate", function( self, elapsed )
            self.t = ( self.t or 0 ) + elapsed
            if self.t < 0.25 then return end
            self.t = 0
            local a, b, c = UnitAttackPower( "player" )
            local okA = pcall( self.ap.SetFormattedText, self.ap, "AP %d  (+%d / -%d)", a, b, c )
            if not okA then pcall( self.ap.SetText, self.ap, "AP: SetFormattedText refused" ) end
            local r1, r2, r3 = UnitRangedAttackPower( "player" )
            pcall( self.rap.SetFormattedText, self.rap, "RAP %d  (+%d / -%d)", r1, r2, r3 )
            local secret = issecretvalue and ( issecretvalue( a ) or issecretvalue( b ) or issecretvalue( c ) )
            self.flag:SetText( ( InCombatLockdown() and "combat" or "ooc" ) .. "  AP read is " .. ( secret and "SECRET" or "plain" ) )
        end )
    end
    panel:SetShown( not panel:IsShown() )
end

SLASH_APSECRET1 = "/apsecret"
SlashCmdList.APSECRET = function( msg )
    local cmd, arg = msg:match( "^(%S*)%s*(.-)$" )
    if cmd == "start" then
        reset()
        if ticker then ticker:Cancel() end
        local secs = tonumber( arg ) or 60
        started = GetTime()
        ticker = C_Timer.NewTicker( 0.25, function()
            sample()
            if GetTime() - started >= secs then ticker:Cancel(); ticker = nil; report() end
        end )
        print( string.format( "|cff00ff00AP secrecy|r sampling for %d s; get into combat for part of it.", secs ) )
    elseif cmd == "show" then
        showPanel()
    elseif cmd == "stop" then
        if ticker then ticker:Cancel(); ticker = nil end
        if tallies then report() end
    else
        if tallies then report() else print( "/apsecret start [seconds] | stop | show" ) end
    end
end
