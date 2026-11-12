-- Engine/Schema/Spec/Regen.lua
-- RegisterResource for the spec mixin (Engine/Schema/Spec.lua's ns.SpecMixin), with the sim's generated `__decay` and
-- `__taken` regen entries. Loads before Spec/All.lua, which copies the mixin into spec 0 at load.

local addon, ns = ...
local Hekili = _G[ addon ]
local state = Hekili.State
local CommitKey, GetResourceKey = ns.commitKey, ns.GetResourceKey
local insert = table.insert
local floor = math.floor
local mt_resource = ns.metatables.mt_resource

-- RegisterResource( resourceID, regen, model, meta ): `regen` is Hekili's regen model (named entries); `meta` holds
-- state-bound functions (each setfenv'd to `state`): `max`, `decay`, `decayInterval`, and two fields the belief reads
-- (Game/State/Families/Resources.lua):
--   fsr = { spirit = fn, mp5 = fn,   The five-second rule (C3): continuous regen in two parts, each a rate per second
--           share = c }              (a number or a function, read at the build) and calibrated on its own; after our
--                                    own spend of the resource the spirit part pauses for 5 s, the mp5 part never does.
--                                    The belief's only: no APL field (`mana.fsr` would call the table and raise). Out
--                                    of combat GetPowerRegenForPowerType's two returns (not casting, casting) are read
--                                    as spirit + mp5 and mp5 (Sources/Power.lua). Mana is secret even out of combat:
--                                    its lower bound (`mana.current`, `mana.pct`) is the build's rest (full), moved by
--                                    our spends and the regen, until a short answer below it drops it to the ladder's.
-- A regen entry of rate fields (C3b), `{ aura = key, mult = n, spirit = m, share = s, mp5 = x }`, any of the four,
-- each one of wowsims's mana PseudoStats while the player's aura `key` is up (sim/core/mana.go:186-211): `mult` the
-- whole rate x n (MultiplyManaRegenSpeed; an energy surge; 0 stops it: a form that pauses the pool); `spirit` the
-- spirit regen x m (DB2 aura 110,
-- SpiritRegenMultiplier); `share` + s of the spirit regen while casting (aura 134, SpiritRegenRateCasting), the total
-- with the `fsr` meta's `share` capped at all of it; `mp5` + x a second in and out of the window (an MP5 aura). On an
-- `fsr` resource the four combine as wowsims does: inside the window (MP5 + S x m x min(c + s, 1)) x f, outside
-- (MP5 + S x m) x f. Rate fields are no forecast event: they move out of the regen model into `state.regenMult` here.
-- `fsr`'s `share` (c, 0-1) is the static casting share the learned split already holds (talents, a pre-buffed armor).
-- An `fsr` part may be a function, read once at the build (Tracked.lua: it may name the spec's tree). A rate field's
-- `spirit` or `mp5` and an aura regen's `value` may be functions (no arguments), read at the build and at each combat
-- start, in the belief's context as well as the sim's; a result that is not a valid number makes the field inert.
-- shortcut: the sim's forecast takes the belief's regen rate at `now` as a constant (Game/API/Facade.lua's
-- GetPowerRegenForPowerType), so it sees neither a rate aura expire mid-forecast nor a simulated cast apply one;
-- upgrade with a per-forecast multiplier when a pack's pooling misjudges across a rate aura's edge.
-- refundOnAvoid = n (a number, 0-1)  The class's default share of an ability's cost of this resource given back when
--                                    the target dodges, parries or misses it, for an ability declaring
--                                    `refundOnAvoid = true` (RegisterAbility below): the belief's only (Families/Now.lua,
--                                    Obs.Avoided); the sim does not predict avoidance and never reads it.
-- base = n (a number)               The pool's base power at the class's top level (wowsims's base stats): a cost
--                                    between 0 and 1 (or any cost of an ability declaring `spendBase = true`) is
--                                    that fraction of it, floored, as the client prices a percent-of-base cost, in
--                                    both layers (ns.SpendPoints, Families/Casts.lua). The
--                                    belief learns the player's own from a plain out-of-combat cost read (login,
--                                    level-up, spell changes); without `base` a fraction is of the maximum (Hekili's).

-- The sim's two generated regen entries (border batch 2 Part C, E3; until it Game/State/Adapter.lua wrote them into
-- the model): `__decay`, the stepped out-of-combat decay from the meta's `decay` and `decayInterval` (stepped-decay
-- design §3.3), and `__taken`, the resource from hits on the player while a main-hand swing entry has a `taken`
-- (tank design §1.2.5). Both read the reset's regen tail (`decay_anchor`, `taken_rate`: GetPowerRegenForPowerType's
-- fourth and fifth values, Engine/Sim/State.lua) and nothing of the belief; the belief's walk skips the two names.
local function eval( v )
    if type( v ) == "function" then return v() end
    return v
end


-- The decay: `value` (negative, talent-scaled) every `interval`, never in combat. Its beats are the reset's anchor's
-- (the belief's last quantum), or start at a pausing aura's expiry (an entry flagged `pausesDecay`) while one is up in
-- the sim: the forecast removes an entry whose `stop` holds, so the pause is in `last`, not `stop`.
local function decayEntry( resource, res, model, meta )
    local e = { resource = resource, interval = meta.decayInterval }
    function e.value()
        return -eval( meta.decay ) * eval( meta.decayInterval )
    end
    function e.last()
        -- the forecast starts at now + offset and steps every beat after `last`; after an advance `actual` holds every
        -- beat to there already, so the anchor rolls forward to the last beat at or before it (as swing entries do)
        local iv, t, a = eval( meta.decayInterval ), state.now + state.offset, 0
        for _, m in pairs( model ) do
            -- a pausing aura present at the reset (up, or expired in the sim since): the beats start at its expiry
            local b = m.pausesDecay and m.aura and not ( m.swing or m.debuff ) and state.buff[ m.aura ]
            if b and b.expires > a then a = b.expires end
        end
        if a == 0 then
            a = rawget( res, "decay_anchor" ) or 0
            if a == 0 then return t - iv end -- the belief inactive: a quantum at the forecast's start
        end
        -- a beat at the expiry, with its last tick: State.lua keeps one point per instant, 10 - 1.25 in either order
        -- (not at a cap: above 99 or below 1.25 rage the order changes what the clamp keeps)
        if a > t then return a - iv end
        return a + floor( ( t - a ) / iv ) * iv
    end
    function e.stop()
        return state.time > 0
    end
    return e
end


-- The hits taken: the learned rate every second from the reset, removed out of combat. Its anchor rolls like the
-- decay's: a re-forecast keeps the reset's grid (the last whole beat at or before the forecast's start is in `actual`).
local function takenEntry( resource, res )
    local e = { resource = resource, interval = 1 }
    function e.value()
        return rawget( res, "taken_rate" ) or 0
    end
    function e.last()
        return state.now + floor( state.offset )
    end
    function e.stop()
        return state.time == 0
    end
    return e
end


local methods = {
    RegisterResource = function( self, resourceID, regen, model, meta )
        local resource = GetResourceKey( resourceID )

        if not resource then
            Hekili:Error( "Unable to identify resource with PowerType " .. resourceID .. "." )
            return
        end

        local r = self.resources[ resource ] or {}

        r.resource = resource
        r.type = resourceID
        r.state = model or setmetatable( {
            resource = resource,
            type = resourceID,

            forecast = {},
            fcount = 0,
            times = {},
            values = {},
            -- the believed band's streams beside the estimate's (border batch 2): the floor the press gates read
            -- (`lo`, `timeToLo`) and the ceiling, moved by the sim's deltas as `actual` is, each clamped on its own
            times_lo = {},
            values_lo = {},
            values_hi = {},

            actual = 0,
            actual_lo = 0,
            actual_hi = 0,
            max = 1,

            active_regen = 0.001,
            inactive_regen = 0.001,
            last_tick = 0,

            swingGen = false,

            add = function( amt, overcap )
                -- Bypasses forecast, useful in hooks.
                if overcap then r.state.amount = r.state.amount + amt
                else r.state.amount = max( 0, min( r.state.amount + amt, r.state.max ) ) end
            end,

            timeTo = function( x )
                return state:TimeToResource( r.state, x )
            end,

            timeToLo = function( x )
                return state:TimeToResource( r.state, x, true )
            end,
        }, mt_resource )
        r.state.regenModel = regen
        r.state.meta = meta or {}

        for _, v in pairs( r.state.meta ) do
            if type( v ) == "table" then -- `fsr`'s parts
                for _, func in pairs( v ) do
                    if type( func ) == "function" then setfenv( func, state ) end
                end
            elseif type( v ) == "function" then -- a number (`refundOnAvoid`) is data
                setfenv( v, state )
            end
        end

        if r.state.regenModel then
            for k, v in pairs( r.state.regenModel ) do
                if v.mult or v.spirit or v.share or v.mp5 then
                    r.state.regenMult = r.state.regenMult or {}
                    insert( r.state.regenMult, v )
                    r.state.regenModel[ k ] = nil -- clearing a field mid-traversal is allowed
                end
                v.resource = v.resource or resource
                -- the sim runs a regen entry's `value` under `state`; the belief, the same function in its own context
                if type( v.value ) == "function" then setfenv( v.value, state ) end
                self.resourceAuras[ v.resource ] = self.resourceAuras[ v.resource ] or {}

                if v.aura then
                    self.resourceAuras[ v.resource ][ v.aura ] = true
                end

                if v.channel then
                    self.resourceAuras[ v.resource ].casting = true
                end

                if v.swing then
                    r.state.swingGen = true
                end
            end

            local m = r.state.meta
            local iv = m.decay ~= nil and eval( m.decayInterval )
            if type( iv ) == "number" and iv > 0 then
                r.state.regenModel.__decay = decayEntry( resource, r.state, r.state.regenModel, m )
            end
            for _, v in pairs( r.state.regenModel ) do
                if v.swing == "mainhand" and type( v.taken ) == "function" then
                    r.state.regenModel.__taken = takenEntry( resource, r.state )
                    break
                end
            end
        end

        self.primaryResource = self.primaryResource or resource
        self.resources[ resource ] = r

        CommitKey( resource )
    end,
}

for k, f in pairs( methods ) do ns.SpecMixin[ k ] = f end
