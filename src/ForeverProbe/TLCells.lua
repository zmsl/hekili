-- ForeverProbe: dump what the Timeline style's now circle and next box hold, to see why a sweep is missing.
-- /tlcells [display]   default Primary; prints one line per cell plus the GCD reads. Take it mid-fight.
-- Reads of the client are only passed to issecretvalue()/type(); nothing compares a possibly-secret value.

local function rel( t, now )
    if t == nil then return "nil" end
    if issecretvalue and issecretvalue( t ) then return "SECRET" end
    if type( t ) ~= "number" then return type( t ) end
    return string.format( "%+.2f", t - now )
end

local function cdInfo( id, now )
    local ok, info = pcall( C_Spell.GetSpellCooldown, id )
    if not ok or not info then return "cd=nil" end
    local s, d = info.startTime, info.duration
    local sS = issecretvalue and issecretvalue( s )
    local dS = issecretvalue and issecretvalue( d )
    return string.format( "cd start=%s dur=%s enabled=%s rate=%s",
        sS and "SECRET" or ( type( s ) == "number" and string.format( "%+.2f", s - now ) or tostring( s ) ),
        dS and "SECRET" or tostring( d ), tostring( info.isEnabled ), tostring( info.modRate ) )
end

SLASH_TLCELLS1 = "/tlcells"
SlashCmdList.TLCELLS = function( msg )
    local name = msg ~= "" and msg or "Primary"
    local d = Hekili and Hekili.DisplayPool and Hekili.DisplayPool[ name ]
    local T = d and d.styleFrames and d.styleFrames.timeline
    if not T then print( "|cff00ff00tlcells|r no Timeline frames for display " .. name ) return end
    local now = GetTime()
    local out = Hekili.Engine and Hekili.Engine.Output and Hekili.Engine.Output[ name ]
    local st = out and out.status
    print( string.format( "|cff00ff00tlcells|r %s combat=%s quiet=%s T.combat=%s readyAt=%s inCombat=%s", name,
        tostring( st and st.combat ), tostring( T.quiet ), tostring( T.combat ), rel( T.readyAt, now ),
        tostring( InCombatLockdown() ) ) )
    if out and out.recs then
        for i = 1, 3 do
            local r = out.recs[ i ]
            if r and r.actionName then
                print( string.format( "  rec%d %s time=%s exact=%s focus=%s", i, r.actionName, tostring( r.time ),
                    rel( r.exact_time, now ), tostring( r.focus ) ) )
            end
        end
    end
    for i = 1, 2 do
        local b = T.cells[ i ]
        if b then
            local cs, cdur = 0, 0
            if b.Cooldown and b.Cooldown.GetCooldownTimes then cs, cdur = b.Cooldown:GetCooldownTimes() end
            print( string.format( "  cell%d %s exact=%s held=%s..%s widget=%+.2f/%.2f shown=%s alpha=%.2f", i,
                tostring( b.Action ), rel( b.ExactTime, now ), rel( b.cdStart, now ), rel( b.cdEnd, now ),
                ( cs or 0 ) / 1000 - now, ( cdur or 0 ) / 1000, tostring( b.Cooldown and b.Cooldown:IsShown() ),
                b.Cooldown and b.Cooldown:GetAlpha() or -1 ) )
            if b.Ability and b.Ability.actionID then
                print( "    ability " .. cdInfo( b.Ability.actionID, now ) )
            end
        end
    end
    local gcd = Hekili.Engine.Registry and Hekili.Engine.Registry.GCD_SPELL
    print( "  gcd spell " .. tostring( gcd ) .. " " .. ( gcd and cdInfo( gcd, now ) or "" ) )
end
