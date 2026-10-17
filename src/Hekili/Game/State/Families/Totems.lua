-- Game/State/Families/Totems.lua
-- The totems family (spec §6.7): the four slots. An out-of-combat read is `observed` (with the slot's facts); a
-- PLAYER_TOTEM_UPDATE in combat with no own cast just before it is a `pinned` destruction. Conf as an aura.
-- Ported from Taco Dog Forever, the totem half of src/TacoDogForever/Model/Belief/Pets.lua (Applier Totem :57).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs

-- By slot 1-4: the believed expiry (0: empty) and the facts of the last plain read.
local exp0, rec = { 0, 0, 0, 0 }, {}
I.totemSpell, I.totemName, I.totemIcon, I.totemStart =
    { 0, 0, 0, 0 }, { "", "", "", "" }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }

I.OnBuild(function(def, now)
    for s = 1, 4 do
        rec[s] = I.NewBelief("totem " .. s)
        I.Sample(rec[s], "default", 0, now, 0)
    end
end)

I.On(Obs.Totem, function(o, t)
    local s = o.a
    if s < 1 or s > 4 then
        return
    end
    if o.c == 1 then
        exp0[s] = o.b
        I.Sample(rec[s], "observed", o.b, t, Obs.Totem)
    elseif o.t - I.lastCastT > I.CAST_GRACE then
        exp0[s] = 0
        I.totemSpell[s] = 0
        I.Sample(rec[s], "pinned", 0, t, Obs.Totem)
    end
end)

--- (spec §3.2) Belief expiry of totem slot 1-4; nil when empty.
function VS.Totem(slot, now)
    local r = rec[slot]
    if not r or exp0[slot] <= now then
        return nil
    end
    r.est, r.lo, r.hi = exp0[slot], exp0[slot], exp0[slot]
    I.AgeConf(r, now)
    return r
end

--- (spec §3.1) spellID, name, icon, start, duration of totem slot 1-4; nil when the slot is empty.
function VS.TotemFacts(slot)
    local e = exp0[slot]
    if not e or e <= 0 then
        return nil
    end
    return I.totemSpell[slot], I.totemName[slot], I.totemIcon[slot], I.totemStart[slot], e - I.totemStart[slot]
end
