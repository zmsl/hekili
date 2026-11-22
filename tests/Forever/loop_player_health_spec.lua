-- tests/Forever/loop_player_health_spec.lua (LibHiddenValues integration design 2.5, 5.4, 6.1 lane B3): the player's
-- health from the band in the loops. Each content's world with `heals` (scenarios.world: a healer's heal on us every
-- 6 s, so the band falls and rises), default arm vs the bands-health arm (no power band: lane B4's resources move the
-- rows by design) on that world, three 60 s fights on one boot (loop.tally):
-- - the rows, flicker per minute and react p90 side by side: no stock pack reads our own health (the wowsims
--   translations omit those lines), so they must be equal; a difference fails here and is traced, never re-floored;
-- - in combat, the core's read of our health (Facade.UnitHealth / UnitHealthMax: what state.health.pct takes at each
--   reset) lies in the truth's 1% cell: every whole-number `health.pct` threshold then answers as the truth does (full
--   is the library's own closed cell [100, 100], 99.x the cell [99, 100): ledger L1669).
--   `agree`: the truth's cell now; `lagged`: the cell at the band's stamp (the library reports a change 2 frames after
--   it fires); `wrong`: neither. The default arm reads full in combat (Families/Player.lua's "unknown"), right only
--   while the truth is full (`full`: the cell 100).
local loop = require("Game.harness.loop")
local ab = require("Game.harness.ab")
local ww = require("Forever.helpers.warrior_world")
local dlw = require("Forever.helpers.druid_loop_world")
local mw = require("Forever.helpers.mage_world")

local HEALS = { 6, 40 }
local KEYS = { "fights", "both", "agree", "conf", "react", "refused", "attempts", "episodes" }
local MORE = { "readyShort", "heldReady", "loOver", "A", "B", "gap", "selfCheck", "pressedBy" }

-- The content with the healer in its world (every other field the content's own).
local function healed(content)
    local world = setmetatable({ heals = HEALS }, { __index = content.WORLD })
    return setmetatable({ WORLD = world }, { __index = content })
end

-- The 1% cell of x percent as the library cuts it, full its own cell 100 (a band's middle reads 99.5 in [99, 100)).
local function cellOf(x)
    return math.floor(x + 1e-9)
end

-- A follow counter over the bands arm's ticks (loop.bandCheck runs after each of run A's driver's cycles).
local function follower(f)
    return function(run, H, lhv)
        local VI = H.ns.VirtualStateInternal
        if VI.inCombat and VI.bandLive[0] then
            local Facade = H.ns.Facade
            local mine = cellOf(100 * Facade.UnitHealth("player") / Facade.UnitHealthMax("player"))
            local function cell(t)
                local v, m = lhv:TruthAt("health", "player", nil, t)
                return v and cellOf(100 * v / m) -- nonzero: a health push carries its max
            end
            local now = cell(H.ctl.now)
            f.n = f.n + 1
            f.full = f.full + (now == 100 and 1 or 0)
            f.low = math.min(f.low, now or 100)
            if mine == now then
                f.agree = f.agree + 1
            elseif mine == cell(VI.bandT[0]) then
                f.lagged = f.lagged + 1
            else
                f.wrong = f.wrong + 1
                if #f.misses < 5 then
                    f.misses[#f.misses + 1] = ("%.3f: read %s truth %s"):format(H.ctl.now, mine, tostring(now))
                end
            end
        end
    end
end

local function tally(content, arm, f)
    local L = loop.new(content)
    local check, bandCheck = ab.check, loop.bandCheck
    ab.check = function()
        return true -- record-only lines: the rows are compared below
    end
    if f then
        local follow = follower(f)
        loop.bandCheck = function(run, H, lhv)
            follow(run, H, lhv)
            return bandCheck(run, H, lhv)
        end
    end
    local ok, m = pcall(loop.tally, L, 3, { arm = arm, duration = 60 })
    ab.check, loop.bandCheck = check, bandCheck
    assert(ok, m)
    return m, loop.summary(m)
end

describe("the player's health from the band in the loops (lane B3) #slow", function()
    for _, case in ipairs({
        { "Arms", ww },
        { "Guardian", dlw.Guardian },
        { "Feral", dlw.Feral },
        { "Frost", mw.Frost },
    }) do
        it(case[1] .. ": rows, flicker and react p90 the default's; in combat the read is the truth's cell", function()
            local C = healed(case[2])
            local base, rb = tally(C, "default")
            local f = { n = 0, agree = 0, lagged = 0, wrong = 0, full = 0, low = 100, misses = {} }
            local m, r = tally(C, "bands-health", f)
            for _, key in ipairs(KEYS) do
                assert.are.same(base[key], m[key], key)
            end
            for _, key in ipairs(MORE) do
                assert.are.same(base[key], m[key], key)
            end
            print(
                (
                    "B3 %s: flicker/min %.2f | %.2f, dips+flashes %d | %d, retracted %d | %d, react p90 %d | %d,"
                    .. " agreement %.3f | %.3f; health in combat %d checks: agree %d lagged %d wrong %d"
                    .. " (default right %d), lowest cell %d"
                ):format(
                    case[1],
                    rb.flicker,
                    r.flicker,
                    rb.led.dips + rb.led.flashes,
                    r.led.dips + r.led.flashes,
                    rb.retracted,
                    r.retracted,
                    rb.reactP90,
                    r.reactP90,
                    rb.agreement,
                    r.agreement,
                    f.n,
                    f.agree,
                    f.lagged,
                    f.wrong,
                    f.full,
                    f.low
                )
            )
            assert.are.same({ rb.flicker, rb.reactP90, rb.led }, { r.flicker, r.reactP90, r.led })
            assert.are.same({}, f.misses)
            assert.are.equal(f.n, f.agree + f.lagged)
            assert.is_true(f.n > 100, f.n)
        end)
    end
end)
