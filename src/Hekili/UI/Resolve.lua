local _, ns = ...
-- UI/Resolve.lua: "what to show", shared by every display style (display styles plan, Task 3). Before a display's
-- Draw, core calls ns.UI.Resolve( d, conf, out, now ), which asks the client once per published record and leaves the
-- answers on d.resolved[ i ]: range, usability, the delay and its earliest possible time, the clamped target count and
-- the overlay glow. The queries were classic's (UI/Styles/Classic.lua, from Hekili's UI.lua, by Hekili's authors and
-- maintainers), moved here unchanged; how a style shows them (and its config) stays in the style.

local Facade = ns.Facade
local C_Item, C_Spell = Facade.C_Item, Facade.C_Spell
local UnitCanAttack, UnitCastingInfo = Facade.UnitCanAttack, Facade.UnitCastingInfo

local Registry = Hekili.Engine.Registry
local Status = Hekili.Engine.Output.status
local StyleGroup = Hekili.Engine.StyleGroup

local IsUsableItem = C_Item.IsUsableItem
local IsUsableSpell = C_Spell.IsSpellUsable
local IsSpellOverlayed = Facade.C_SpellActivationOverlay.IsSpellOverlayed
local GetItemCooldown = C_Item.GetItemCooldown

local GetSpellCooldown = function( spellID )
    local spellCooldownInfo = C_Spell.GetSpellCooldown( spellID )
    if spellCooldownInfo then
        return spellCooldownInfo.startTime, spellCooldownInfo.duration, spellCooldownInfo.isEnabled, spellCooldownInfo.modRate
    end
    return 0, 0, false, 0
end

local RC = Facade.LibRangeCheck -- the one range source (range plan R2): LibRangeCheck through the facade
local LSR = LibStub( "SpellRange-1.0" )
local max, min = math.max, math.min

local SLOTS = 12 -- Output's records per display

--- Fills d.resolved[ 1 .. out.count ] (preallocated on the first call), per record: `inRange` (the ability's range),
--- `inMelee` (the target within 7 yd or its range unknown, asked only while the bound style's range check is `melee`, true otherwise),
--- `usable`, `delay` (exact_time - now), `earliest` (when the GCD, the cast and the ability's cooldown allow it, from
--- now), `desaturate` (delay past earliest: a wait to show), `targets` (the count shown, clamped by the toggle mode),
--- `detected` (the count seen), `single` (clamped to one) and `glow` (overlayed). Classic's spirals reuse this frame's
--- client answers: `res.gcdStart`, and `cdAsked` with `cdStart`, `cdDuration`, `cdEnabled`, `cdModRate` on a record whose
--- cooldown was asked (only while it waits).
--- A record with no action or time answers in range, usable, no delay and no glow.
function ns.UI.Resolve( d, conf, out, now )
    local res = d.resolved
    if not res then
        res = {}
        for i = 1, SLOTS do
            res[ i ] = { inRange = true, inMelee = true, usable = true, delay = 0, earliest = 0, desaturate = false, targets = 0, detected = 0, single = false, glow = false, cdAsked = false, cdStart = 0, cdDuration = 0, cdEnabled = false, cdModRate = 0 }
        end
        d.resolved = res
    end

    local profile = Hekili.DB.profile
    local abilities = Registry.Abilities()

    -- Per display: the target count, the target's range, the GCD and the cast.
    local tMin, tMax = 0, 0
    local mode = profile.toggles.mode.value
    local spec = Status.specID and profile.specs[ Status.specID ]

    if d.id == 'Primary' then
        if ( mode == 'dual' or mode == 'single' or mode == 'reactive' ) then tMax = 1
        elseif mode == 'aoe' then tMin = spec and spec.aoe or 3 end
    elseif d.id == 'AOE' then tMin = spec and spec.aoe or 3 end

    local detected = Status.numTargets
    local shown = detected
    if tMin > 0 then shown = max( tMin, shown ) end
    if tMax > 0 then shown = min( tMax, shown ) end

    local hostile = UnitCanAttack( "player", "target" )
    local range = StyleGroup( conf, "range" )
    local inMelee = true
    if hostile and range.enabled and range.type == "melee" then -- the only range check that asks LibRangeCheck
        local lo = RC:GetRange( "target" )
        inMelee = lo == nil or lo <= 7 -- unknown never blocks: in melee
    end

    local gStart, gDuration = GetSpellCooldown( Registry.GCD_SPELL )
    res.gcdStart = gStart
    local cStart, cEnd = select( 4, UnitCastingInfo( "player" ) )

    for i = 1, out.count do
        local rec, r = out.recs[ i ], res[ i ]
        local def = rec.actionName and abilities[ rec.actionName ]
        local exact_time = rec.exact_time

        r.targets, r.detected, r.single, r.inMelee = shown, detected, tMax == 1, inMelee
        r.cdAsked = false

        if def and exact_time then
            local name = def.rangeSpell or def.itemSpellName or def.actualName or def.name
            r.inRange = not ( hostile and name and LSR.IsSpellInRange( name, "target" ) == 0 )

            local _, unusable
            if def.itemCd or rec.item then
                unusable = not IsUsableItem( def.itemCd or rec.item )
            else
                _, unusable = IsUsableSpell( def.actualName or def.name )
            end
            r.usable = not unusable

            local delay = exact_time - now
            local earliest_time = 0

            if delay > 0 then
                if not rec.offGCD and gStart > 0 then earliest_time = gStart + gDuration - now end

                if cStart and cStart > 0 then earliest_time = max( ( cStart / 1000 ) + ( cEnd / 1000 ) - now, earliest_time ) end

                local rStart, rDuration, rEnabled, rModRate = 0, 0, nil, nil
                if rec.item then
                    rStart, rDuration, rEnabled, rModRate = GetItemCooldown( rec.item )
                    r.cdAsked = true
                elseif def.cooldown > 0 or def.spendType ~= "runes" then
                    rStart, rDuration, rEnabled, rModRate = GetSpellCooldown( rec.actionID )
                    r.cdAsked = true
                end
                r.cdStart, r.cdDuration, r.cdEnabled, r.cdModRate = rStart, rDuration, rEnabled, rModRate
                if rStart > 0 then earliest_time = max( earliest_time, rStart + rDuration - now ) end
            end

            r.delay, r.earliest, r.desaturate = delay, earliest_time, delay > earliest_time + 0.05
            r.glow = rec.actionID > 0 and IsSpellOverlayed( rec.actionID )
        else
            r.inRange, r.usable, r.delay, r.earliest, r.desaturate, r.glow = true, true, 0, 0, false, false
        end
    end
end
