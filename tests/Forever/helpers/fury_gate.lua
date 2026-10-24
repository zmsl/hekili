-- tests/Forever/helpers/fury_gate.lua: the headless Fury (wowsims.com) 20-fight gates at level 60 and 24 (central
-- fix 21), shared by loop_warrior_fury_spec.lua and loop_warrior_fury24_spec.lua. Fury shows the on-next-swing
-- strike's wait (`rage.current>=40`), which Arms (`rage>=90`) never reaches; the loop has no snap-back metric, so its
-- flicker/min stands in for it. The content is wowsims_warrior_spec.lua's Fury: the dual-wield world, Berserker Rage
-- in the kit, Forever's Overpower window.
local ab = require("Game.harness.ab")
local assert = require("luassert")
local arms_gate = require("Forever.helpers.arms_gate")
local pack_gate = require("Forever.helpers.pack_gate")
local ws = require("Forever.helpers.wowsims")
local ww = require("Forever.helpers.warrior_world")

local M = {}

local REQUIRES = {
    overpower = function(_, e)
        return e.auras[1282733] ~= nil and e.form == 1, "no window"
    end,
}

--- The Fury (wowsims.com) content at `level`.
function M.content(level)
    return ws.content(ww.Fury, {
        pack = "Fury (wowsims.com)",
        level = level,
        talents = ws.header("warrior_fury").talents,
        learn = ws.learn("WARRIOR"),
        race = ws.race("warrior_fury"),
        kit = { "berserker_rage" },
        requires = REQUIRES,
    })
end

--- 20 fights at `level`, the `Fury L<level> solo:` line printed, pack_gate's gate, the Arms 20-fight gate's outcome
--- checks (never-reacts, idle, uptimes but arms_gate.REPORTED), then `floors` (agreement, reactP90, unmatched cost
--- refusals per 100, flicker/min, dps A/B).
function M.solo(level, floors)
    local label = "Fury L" .. level
    local r, line = pack_gate.solo(label, M.content(level), 20)
    -- the bars: asserted in the default arm, recorded in a provider arm (providers spec §4.1)
    ab.check(r.agreement >= floors.agreement, label, line)
    ab.check(r.reactP90 <= floors.reactP90, label, line)
    ab.check((r.per100U.cost or 0) <= floors.unmatched, label, line)
    ab.check(r.flicker <= floors.flicker, label, line)
    ab.check(r.dps >= floors.dps, label, line)
    -- the Arms bars; measured (fix 21): never 0.047 L24 / 0.027 L60, idle A/B 0.530/0.537 and 0.502/0.518, Sunder
    -- Armor up 0.94/0.96 and 0.93/0.95
    ab.check(r.never <= 0.08, label, line)
    ab.check(r.idleA <= r.idleB + 0.03, label, line)
    for key, up in pairs(r.upB) do
        if not arms_gate.REPORTED[key] then
            ab.check((r.upA[key] or 0) >= up - 0.03, label, key .. ": " .. line)
        end
    end
    assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    return r, line
end

return M
