-- tools/floors_trace.lua (refactor lane 4, L1827): a busted --helper for tools/first_divergence.sh and
-- tools/fight_clock.sh. It changes no gate: it wraps pack_gate.solo and loop.run (through loop.run's own per-tick
-- hook, `on`) so one loop spec file writes a per-tick dump of one label's run A (ours driving, the oracle shadow beside
-- it) to FLOORS_OUT, and asserts nothing. Every other label's gate, and the label's short (< 20 fight) calls, raise
-- "skipped" so the run stays short. The arm is HEKILI_AB's, as in the gate; no .ab row is written.
--   FLOORS_LABEL  the label (pack_gate.solo's first argument, e.g. "Fury L24")
--   FLOORS_OUT    the dump file (tab-separated; tools/floors.lua diverge reads it)
--   FLOORS_MODE   chain (default): seeds 1..last on one boot, as the gate runs them, the clock and the pools carried
--                 from fight to fight; alone: each seed of FLOORS_SEEDS on its own fresh boot (a new clock, full pools,
--                 nothing learned): the per-fight clock
--   FLOORS_SEEDS  "a-b" or "s" (default 1-20; chain runs 1..b)
-- Dump rows: "T seed n t ours theirs pressed lo est hi truth" per in-combat tick n (t from the fight's start; the
-- belief's power lo / est / hi as the flicker ledger recorded it; truth the world's power), then "F seed boot ticks
-- held loOver readyShort flips agree" per fight (boot: the instance's clock at the fight's start; flips press-only).
local ab = require("Game.harness.ab")
local loop = require("Game.harness.loop")
local pack_gate = require("Forever.helpers.pack_gate")

local LABEL, OUT = os.getenv("FLOORS_LABEL"), os.getenv("FLOORS_OUT")
assert(LABEL and OUT, "tools/floors_trace.lua: FLOORS_LABEL and FLOORS_OUT")
local MODE = os.getenv("FLOORS_MODE") or "chain"
local s0, s1 = (os.getenv("FLOORS_SEEDS") or "1-20"):match("^(%d+)%-?(%d*)$")
s0 = assert(tonumber(s0), "FLOORS_SEEDS: a-b or s")
s1 = tonumber(s1) or s0

ab.check, ab.record = function() end, function() end -- a trace, not a gate: no assert, no .ab row

local fh
local function num(v)
    return type(v) == "number" and ("%.4f"):format(v) or tostring(v)
end

local run0 = loop.run
function loop.run(L, seed, o, drivers)
    if not fh or #drivers < 2 or (o and o.replay) then -- run A only: ours driving, the oracle shadow beside it
        return run0(L, seed, o, drivers)
    end
    local last, boot, inner = 0, nil, o and o.on
    local function on(run, steps, t)
        if inner then
            inner(run, steps, t)
        end
        boot = boot or steps[1].base
        local n = run.combat
        if n > last then
            last = n
            local f = run.frames and run.frames[1] or { lo = {}, est = {}, hi = {}, truth = {} }
            fh:write(
                table.concat({
                    "T",
                    seed,
                    n,
                    ("%.3f"):format(t),
                    tostring(run.ours[n]),
                    tostring(run.theirs[n]),
                    tostring(run.pressed[n]),
                    num(f.lo[n]),
                    num(f.est[n]),
                    num(f.hi[n]),
                    num(f.truth[n]),
                }, "\t"),
                "\n"
            )
        end
    end
    local run = run0(L, seed, setmetatable({ on = on }, { __index = o }), drivers)
    local agree = 0
    for i = 1, run.combat do
        agree = agree + ((run.ours[i] and run.ours[i] == run.theirs[i]) and 1 or 0)
    end
    fh:write(
        table.concat({
            "F",
            seed,
            num(boot),
            run.combat,
            run.heldReady,
            run.loOver,
            run.readyShort,
            loop.flips(run.ours, run.combat, run.pressed),
            agree,
        }, "\t"),
        "\n"
    )
    return run
end

local truthRate = loop.truthRate
function loop.truthRate(...) -- a ttd arm's calibration fights (loop.tally) are not the label's: no rows
    local f = fh
    fh = nil
    local r = truthRate(...)
    fh = f
    return r
end

function pack_gate.solo(label, world, n, seed0)
    assert((seed0 or 0) == 0, "floors_trace: the traced run starts at seed 1 (seed0 0); got seed0 " .. tostring(seed0))
    if label ~= LABEL or n < 20 then
        error("skipped by tools/floors_trace.lua (" .. LABEL .. " only)")
    end
    fh = assert(io.open(OUT, "w"))
    fh:write("# ", LABEL, " arm ", ab.arm(), " mode ", MODE, " seeds ", s0, "-", s1, "\n")
    local m
    if MODE == "alone" then
        for s = s0, s1 do
            local o = { seed0 = s - 1 }
            if s ~= 1 then
                o.trace = false -- as in the chain, only seed 1 runs traced
            end
            m = loop.tally(loop.new(world), 1, o)
        end
    else
        m = loop.tally(loop.new(world), s1, { seed0 = 0 })
    end
    fh:close()
    fh = nil
    return loop.summary(m), loop.line(m)
end
