-- Game/State/Families/TargetCast.lua
-- The target's cast (spec §6.8): `TargetCast` observations by castBarID (plain on the target; its spellID and times
-- are secret). A start sets the start and a default end; a stop, an interrupt or a new castBarID ends it; the
-- interruptible events set the flag. Conf as an aura.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Target.lua (Applier TargetCast :103).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs, Of = VS.Obs, I.TargetCastOf

--- A target cast's believed length while its end is secret (G6).
I.TARGET_CAST_DEFAULT = 2

local active, channel, bar, start, kick = false, false, 0, 0, -1
local rec

I.OnBuild(function(def, now)
    rec = I.NewBelief("target cast")
    active = false
end)

I.On(Obs.TargetCast, function(o, t)
    local of = o.a
    if of == Of.Start or of == Of.ChannelStart then
        active, channel, bar, start, kick = true, of == Of.ChannelStart, o.b, o.t, o.c
        local e = o.t + I.TARGET_CAST_DEFAULT
        rec.est, rec.lo, rec.hi = e, e, e
        I.Sample(rec, "default", e, t, Obs.TargetCast)
        I.Sample(rec, "observed", o.t, t, Obs.TargetCast)
    elseif of == Of.End or of == Of.Interrupted then
        if active and (o.b == 0 or o.b == bar) then
            active = false
            I.Sample(rec, "observed", o.t, t, Obs.TargetCast)
        end
    elseif of == Of.Kickable then
        kick = o.c
    end
end)

I.On(Obs.TargetSwap, function()
    active = false
end)

local function up(now)
    return active and start + I.TARGET_CAST_DEFAULT + I.CAST_GRACE > now
end

--- (spec §3.1) channel, castBarID, start, interruptible (1 yes, 0 no, -1 unknown); nil when the target is not casting.
function VS.TargetCastFacts()
    if not active then
        return nil
    end
    return channel, bar, start, kick
end

--- (spec §3.2) Belief end of the target's cast; nil when it is not casting.
function VS.TargetCast(now)
    if not up(now) then
        return nil
    end
    local e = start + I.TARGET_CAST_DEFAULT
    rec.est, rec.lo, rec.hi = e, e, e
    I.AgeConf(rec, now)
    return rec
end
