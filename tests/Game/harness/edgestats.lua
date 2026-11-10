-- tests/Game/harness/edgestats.lua (cdm-edge-anchor lane, harness only): per fight of a viewer arm, the driver's
-- believed expiry against the Cooldown Manager's own down (each item's dark edge, from the fake's ViewerAuraBySpell),
-- the seconds the belief is up while the viewer is dark (staleUp) and down while it is lit (earlyDown), over the
-- router's tracked auras in combat but the player's forms and enchants (the leaf never judges them), player and target
-- apart, and the router's seeds and edges and the belief's debounce counts. One
-- line per fight for the arm's .ab file (loop.lua). Class-neutral: aura indices and the client's units only.
local M = {}
local NONE = {}

-- Wraps the fake's viewer drivers once per instance: each call reports to ctl.edgeEm (the running fight's, if any).
local function attach(ctl)
    if ctl.edgeWrapped then
        return
    end
    ctl.edgeWrapped = true
    local by, re = ctl.ViewerAuraBySpell, ctl.ViewerRetarget
    ctl.ViewerAuraBySpell = function(unit, spellID, up, source)
        local em = ctl.edgeEm
        if em and source == "player" then
            em.on(unit, spellID, up, ctl.now)
        end
        return by(unit, spellID, up, source)
    end
    ctl.ViewerRetarget = function(...)
        local em = ctl.edgeEm
        if em then
            em.retarget()
        end
        return re(...)
    end
end

--- Starts a fight's record on instance H (its belief internals VI).
function M.start(H, VI)
    local ctl = H.ctl
    attach(ctl)
    local U = VI.auras
    local em = { vup = {}, lastUp = {}, errs = {}, stale = { 0, 0 }, early = { 0, 0 }, missed = 0, long = 0, downs = 0 }
    local function key(unit, spellID)
        local u, j = U.index[unit], U.bySpell[spellID]
        if u and j and u <= 2 then
            return (u - 1) * VI.AURA_UNIT + j, u, j
        end
    end
    function em.on(unit, spellID, up, now)
        local k, u, j = key(unit, spellID)
        if not k then
            return
        end
        if up then
            if not em.vup[k] then
                em.vup[k], em.lastUp[k] = true, 0 -- a new lit period
            end
            return
        elseif not em.vup[k] then
            return
        end
        em.vup[k] = false
        em.downs = em.downs + 1
        local e = U.exp0[u][j]
        local b = e > 0 and e or em.lastUp[k] -- the believed expiry: the record's, else its last while lit
        if b == 0 then
            em.missed = em.missed + 1 -- never believed up while lit
        elseif b - now > 600 then
            em.long = em.long + 1 -- a long record (an open with no duration, a re-establish): closed by the down
        else
            em.errs[#em.errs + 1] = b - now
        end
    end
    function em.retarget()
        for k in pairs(em.vup) do
            if k > VI.AURA_UNIT then
                em.vup[k], em.lastUp[k] = false, 0
            end
        end
    end
    ctl.edgeEm = em
    return em
end

--- One tick at `now` (instance clock) of `dt` s: the belief against the viewer per tracked aura (in combat only).
function M.tick(H, VI, now, dt, inCombat)
    local em = H.ctl.edgeEm
    local U, P = VI.auras, VI.presence
    if not em or not U or not P or not P.tracked then
        return
    end
    local form, enchant = VI.formAura or NONE, VI.enchantAura or NONE
    for u = 1, (U.n < 2 and U.n or 2) do
        for j = 1, U.nAura do
            local k = (u - 1) * VI.AURA_UNIT + j
            local e = U.exp0[u][j]
            if em.vup[k] and e > 0 then
                em.lastUp[k] = e
            end
            -- a form or enchant is never judged by the leaf (Auras.lua's formAura/enchantAura): no phantom of the verdict's
            if inCombat and P.tracked[j] and not (u == 1 and (form[j] or enchant[j])) then
                local bel, vu = e > now, em.vup[k] == true
                if bel and not vu then
                    em.stale[u] = em.stale[u] + dt
                elseif vu and not bel then
                    em.early[u] = em.early[u] + dt
                end
            end
        end
    end
end

--- The fight's line (and the record dropped): counts, then the expiry errors (believed - viewer down, s) rounded.
function M.line(H, VI)
    local em = H.ctl.edgeEm
    H.ctl.edgeEm = nil
    if not em then
        return nil
    end
    local P, hold = VI.presence, VI.presenceHold or {}
    local function sum(c)
        local p, tg = 0, 0
        for k, n in pairs(c or {}) do
            if k > VI.AURA_UNIT then
                tg = tg + n
            else
                p = p + n
            end
        end
        return p .. "/" .. tg
    end
    local errs = {}
    for i, x in ipairs(em.errs) do
        errs[i] = ("%.3f"):format(x)
    end
    return (
        "seeds %s edges %s waits %d fires %d downs %d staleUp %.2f/%.2f earlyDown %.2f/%.2f missed %d"
        .. " long %d errs %s"
    ):format(
        sum(P and P.seedN),
        sum(P and P.edgeN),
        hold.waits or 0,
        hold.fires or 0,
        em.downs,
        em.stale[1],
        em.stale[2],
        em.early[1],
        em.early[2],
        em.missed,
        em.long,
        #errs > 0 and table.concat(errs, ",") or "-"
    )
end

return M
