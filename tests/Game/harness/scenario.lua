-- tests/Game/harness/scenario.lua (refactor plan lane 2, L1827): the scenario builder. A spec states WHAT happens WHEN
-- (a swing, a cast and its outcome, an own or taken row, a power read, a usable answer, a band) on one time-ordered
-- queue; the builder fires the client events at their own times through the client it is given and runs the frames
-- between them. It drives the existing pieces and copies none of them: the client is a headless instance
-- (headless.new: H.Fire, H.RunTimers) or a fake_api one ({ ctl, ns }: ctl.Fire, ctl.Tick); its frame step is
-- headless.frame or ctl.Tick.
--
--   local B = scenario.new(H, { plain = false, dt = 1 / 60, frame = nil, rows = false })
--   B:swing(t, { act = "DODGE", lag = 0.474 })     PLAYER_SWING at t, its row `lag` s later
--   B:cast(t, spellID, { act = "MISS", row = 0.004 }) SENT 0.08 s before, the success at t, its row at t + row
--   B:cast(t, spellID, { fail = true })              ... or UNIT_SPELLCAST_FAILED at t
--   B:row(t, "PARRY") / B:taken(t, "WOUND", { amount = 300 })   an own (target) / taken (player) UNIT_COMBAT row
--   B:power(t, 4, 5)                                 the plain read (ctl.power) and its UNIT_POWER_FREQUENT
--   B:usable(t, spellID, true, false)                IsSpellUsable's answer from t (ctl.usable)
--   B:band(t, r, lo, hi)                             a band source's poll of resource slot r: [lo, hi) stamped t
--   B:tick(t) / B:drain(t)                           a frame (no loop: `dt` false) / VS.Drain(t), scheduled
--   B:at(t, what, fn, bg)                            anything else: fn(B, t) at t
--   B:run(to)                                        everything due by `to`, in time order (ties: the order given)
-- Every verb takes absolute times and returns B. Each event is a fact named `what` (B.facts { t, what }) unless `bg`
-- (background: a white swing's wound, a tick); the verbs take `o.bg`, `o.name` (the facts' prefix) and `o.amount`.
-- Amounts are secret, as live, unless `plain`. The frame loop: with `dt` (default 1/60) B:run steps the clock a frame at
-- a time and after each frame's events calls `frame(B, t)` (default: headless.frame, or ctl.Tick on a fake_api
-- client); with `dt` false it only fires the events and the scheduled ticks and drains (the hand-built specs' shape).
-- `rows`: B.rows keeps every row the belief emits on its combat log ({ sub, a12, a15, stamp }: a12 a spell row's ID or
-- a swing row's amount or miss type, a15 a spell row's amount or miss type, stamp the row's time), the pairing's outcome.
local headless = require("Game.harness.headless")
local SECRET = require("Game.State.helpers.fake_api").SECRET

local M = {}
M.SENT = 0.08 -- a cast's SENT before its success (finisher_world)
M.LAND = 0.474 -- a white swing's row after PLAYER_SWING (observer.lua DEFAULTS.main.med, P log 2)

local B = {}
B.__index = B

--- A builder over client `H` (a headless instance, or { ctl, ns } of fake_api). `o`: plain, dt, frame, rows.
function M.new(H, o)
    o = o or {}
    local self = setmetatable({ H = H, ctl = H.ctl, ns = H.ns, o = o, queue = {}, facts = {}, seq = 0 }, B)
    self.now = self.ctl.now
    self.dt = o.dt == nil and 1 / 60 or o.dt
    self.step = o.frame
        or (H.RunTimers and function(b, t)
            headless.frame(b.H, t)
        end)
        or function(b, t)
            b.ctl.Tick(t)
        end
    if o.rows then
        self.rows = {}
        local I = self.ns.VirtualStateInternal
        local f = I.Events.CreateFrame("Frame")
        f:SetScript("OnEvent", function()
            local stamp, sub, _, _, _, _, _, _, _, _, _, a12, _, _, a15 = self.ns.Facade.CombatLogGetCurrentEventInfo()
            self.rows[#self.rows + 1] = { sub, a12, a15, stamp }
        end)
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
    return self
end

function B:at(t, what, fn, bg)
    self.seq = self.seq + 1
    self.queue[#self.queue + 1] = { t = t, what = what, fn = fn, bg = bg, seq = self.seq }
    return self
end

function B:fire(event, ...)
    self.ctl.Fire(event, ...)
end

function B:amount(v)
    return self.o.plain and v or SECRET
end

--- An own row on the target (o.unit "player": a taken one; o.flag, o.amount [0]).
function B:row(t, act, o)
    o = o or {}
    return self:at(t, o.name or ("row " .. act), function(b)
        b:fire("UNIT_COMBAT", o.unit or "target", act, o.flag or "", b:amount(o.amount or 0), 1)
    end, o.bg)
end

function B:taken(t, act, o)
    o = o or {}
    o.unit = "player"
    return self:row(t, act, o)
end

--- Our white swing at t (o.speed [1.0], o.hand [0]) and its row `o.act` ("WOUND"; false: none) `o.lag` s later
--- (M.LAND), amount o.amount (60 a wound). A wound's pair is background unless o.bg is false.
function B:swing(t, o)
    o = o or {}
    local act = o.act == nil and "WOUND" or o.act
    local bg = o.bg
    if bg == nil then
        bg = act == "WOUND"
    end
    self:at(t, o.name or "swing", function(b)
        b:fire("PLAYER_SWING", o.speed or 1.0, o.hand or 0)
    end, bg)
    if act then
        local amount = o.amount or (act == "WOUND" and 60 or 0)
        self:row(t + (o.lag or M.LAND), act, { name = (o.name or "swing") .. " row " .. act, amount = amount, bg = bg })
    end
    return self
end

--- Our cast of `id` succeeding at t: UNIT_SPELLCAST_SENT `o.sent` s before (M.SENT; false: none) on o.target ["Mob"],
--- then the success (o.fail: UNIT_SPELLCAST_FAILED instead) with o.success(B, t) after it, then the outcome row `o.act`
--- at t + o.row (nil: none; negative: logged before the success), amount o.amount (50 a wound). o.guid ["Cast-<name>-t"].
function B:cast(t, id, o)
    o = o or {}
    local name = o.name or tostring(id)
    local guid = o.guid or ("Cast-" .. name .. "-" .. t)
    if o.sent ~= false then
        self:at(t - (o.sent or M.SENT), name .. " sent", function(b)
            b:fire("UNIT_SPELLCAST_SENT", "player", o.target or "Mob", guid, id)
        end)
    end
    self:at(t, name .. (o.fail and " failed" or " success"), function(b, tt)
        b:fire(o.fail and "UNIT_SPELLCAST_FAILED" or "UNIT_SPELLCAST_SUCCEEDED", "player", guid, id)
        if o.success then
            o.success(b, tt)
        end
    end)
    if o.row then
        local landed = o.act == "WOUND"
        self:row(t + o.row, o.act, { name = name .. " row " .. o.act, amount = o.amount or (landed and 50 or 0) })
    end
    return self
end

--- The plain read of power type `pt` (ctl.power) set to v (or v(B) then) at t and its UNIT_POWER_FREQUENT (o.token
--- ["COMBO_POINTS"]); o.set(B, value) runs with it (a world's truth).
function B:power(t, pt, v, o)
    o = o or {}
    return self:at(t, o.name or "power", function(b)
        local n = type(v) == "function" and v(b) or v
        b.ctl.power[pt] = n
        if o.set then
            o.set(b, n)
        end
        b:fire("UNIT_POWER_FREQUENT", "player", o.token or "COMBO_POINTS")
    end, o.bg)
end

--- IsSpellUsable(id) answers (ok, noMana) from t on (ctl.usable; nil ok: the fake's default false, false).
function B:usable(t, id, ok, noMana, o)
    return self:at(t, (o and o.name) or "usable", function(b)
        b.ctl.usable[id] = ok ~= nil and { ok, noMana or false } or nil
    end, o and o.bg)
end

--- A band source's poll of resource slot r at t: [lo, hi) stamped bt (default t), as resources_spec's band() does it
--- (what the belief logged before reads the old stamp; I.bandShows 1/6, a watch at 60 fps).
function B:band(t, r, lo, hi, bt)
    return self:at(t, "band", function(b)
        local I = b.ns.VirtualStateInternal
        if I.log.n > 0 and I.bandT[r] ~= (bt or t) then
            I.Fold(t - 1e-9)
        end
        I.bandT[r], I.bandShows[r] = bt or t, 1 / 6
        I.Sources.Direct(b.ns.VirtualState.Obs.Band, t, r, lo, hi)
    end)
end

function B:tick(t)
    return self:at(t, "tick", function(b)
        b.step(b, t)
    end, true)
end

function B:drain(t)
    return self:at(t, "drain", function(b)
        b.ns.VirtualState.Drain(t)
    end, true)
end

-- The due events at or before t, in time order (ties: the order given), each at its own time.
local function due(self, t)
    table.sort(self.queue, function(a, b)
        return a.t < b.t or (a.t == b.t and a.seq < b.seq)
    end)
    while self.queue[1] and self.queue[1].t <= t do
        local e = table.remove(self.queue, 1)
        self.ctl.now = e.t
        e.fn(self, e.t)
        if not e.bg then
            self.facts[#self.facts + 1] = { t = e.t, what = e.what }
        end
    end
end

--- Runs to `to` (with no `dt`: every queued event when `to` is nil). Returns B.
function B:run(to)
    if not self.dt then
        due(self, to or math.huge)
        return self
    end
    while self.now + self.dt <= to + 1e-9 do
        self.now = self.now + self.dt
        due(self, self.now)
        self.ctl.now = self.now
        self.step(self, self.now)
    end
    return self
end

return M
