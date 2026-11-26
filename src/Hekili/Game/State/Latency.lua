-- Game/State/Latency.lua
-- The latency table (refactor plan Pr-1, L1827; belief-purpose-taxonomy 3.1): one row per CHANNEL of the client, how
-- late (or early) it shows a change, with its unit, source, ledger row and purpose. The files that used a copy of a
-- value read its row by name, so a measurement changes one row. Loaded after VirtualState.lua, before the families.
-- Sources: measured (a capture or log), wowsims, ruling (owner or review), design (a margin chosen over a core value),
-- unmeasured (guessed or carried over from TDF with no Forever measurement: the probe list). Purposes are the
-- taxonomy's (ATT attribution, STALE-P an answer older than our change, STALE-A age, EXCL kept out of learning, HOLD,
-- CLAMP, DL a verdict deadline, SUPER superseded by a measurement). Learned channels (a travelling spell's flight lag,
-- Events/Tickets.lua; the band library's Latency(), Sources/Bands.lua) have no constant and no row.

local _, ns = ...
local I = ns.VirtualStateInternal

local Lat = { rows = {}, names = {} }
I.Lat = Lat

Lat.SOURCES = { measured = true, wowsims = true, ruling = true, design = true, unmeasured = true }

--- Adds channel `name`: its lag (seconds, or a list by hand or reference), unit, source, ledger row and purposes.
--- Load time only.
local function row(name, lag, unit, source, ledger, purpose)
    assert(not Lat.rows[name] and Lat.SOURCES[source], name)
    Lat.rows[name] = { lag = lag, unit = unit, source = source, ledger = ledger, purpose = purpose }
    Lat.names[#Lat.names + 1] = name
end

--- Channel `name`'s lag (its i-th entry for a list). An unknown name raises. Load and build time only: callers keep
--- the value in a local or a field.
function Lat.lag(name, i)
    local v = assert(Lat.rows[name], name).lag
    if i then
        return v[i]
    end
    return v
end

-- Ours: our cast, its rows and its reads.
row("own.row.early", 0.025, "s", "measured", "L361, L1763 (1-22 ms lead)", "ATT") -- Events/Rows.lua EARLY
row("wound.frame", 0.05, "s", "measured", "capture G 177249/177250", "ATT") -- Events/Melee.lua M.SAME_FRAME
-- The three one-frame rows are equal by value only (taxonomy 7.3): merging them needs a measurement.
row("aura.read", 0.05, "s", "unmeasured", "L576 (carried over)", "STALE-P") -- I.SAME_FRAME
row("own.tick", 0.1, "s", "unmeasured", "TDF Belief.OWN_TICK (carried over)", "ATT") -- Families/Swing.lua
row("gcd.edge", 0.1, "s", "unmeasured", "checkpoint G3", "ATT") -- Families/Casts.lua GCD_EDGE
row("channel.stop", 0.05, "s", "unmeasured", "aura audit C11 (no probe)", "ATT") -- Families/Now.lua FINISH_TOL
-- A builder's combo point after its success: 29 of 33 in its frame, 4 at 0.102-0.119 s; 0.3 covers the tail.
row("cp.avoid", 0.3, "s", "measured", "L1847 (n = 33), L1840", "ATT, DL") -- Families/Now.lua PT_AVOID

-- Swings.
row("swing.lag", { 0.474, 0.703, 1.686 }, "s", "measured", "P log 2, G5 (seeds, learned online)", "ATT, SUPER")
row("swing.lag.spread", { 0.060, 0.020, 0.020 }, "s", "measured", "P log 2, G5 (seeds, learned online)", "ATT")
-- the longest landing lag per hand (measured 1287 / 1686 ms plus a margin): L.PAIR_WINDOW_MS, I.LIFT_WINDOW
row("swing.land", { 1.5, 2.0 }, "s", "measured", "P log 2", "ATT, STALE-A")
row("combat.first", 0.01, "s", "ruling", "U10 (second Rogue capture)", "ATT") -- Events/Rows.lua first swing

-- The client's answers.
-- The usability answers' lag: the core's def.oracleMin at the build (the harness's usableDelay); 0.1 until then.
row("usable.shows", 0.1, "s", "unmeasured", "L1784 (probe G7)", "STALE-P, SUPER, ATT") -- I.GAIN_SHOWS
row("usable.flip", 0.15, "s", "unmeasured", "TDF Belief.PIN_EXACT (carried over)", "CLAMP") -- I.PIN_EXACT
-- The client's delay before a band fires, past the library's Latency(): three frames at 60 fps.
row("band.margin", 0.05, "s", "unmeasured", "L1670 (design bound), probe L1800", "STALE-P, EXCL") -- I.BAND_MARGIN
-- How late a band crossing's stamp can be against the value's own crossing: one regen step if the bar moves in
-- server steps (the harness's world.lua: 0.1 s), else the firing delay above. A regen pair's floor side reads with it.
row("band.stamp", 0.1, "s", "unmeasured", "L1794, probe L1800 (band-edge round 2)", "CLAMP") -- I.BAND_STAMP
-- Cast to Cooldown Manager light p99 27 ms, max 109, one 323 ms debuff (L448, L361): Sources/Auras.lua HOLD and
-- REFRESH_LAG.
row("cdm.light", 0.35, "s", "measured", "L448, L361", "HOLD, STALE-P, CLAMP")
-- A light polled a drain before our cast's event was logged: this drain's fold or the one before (Families/Auras.lua).
row("cdm.lead", 2, "drains", "ruling", "review S3 (cdm-default)", "STALE-P")
-- Seconds of regen a capped read sits under the cost: past the core's READY 0.05 (Engine/Output.lua), by hand. Kept a
-- belief row: READY + 0.01 is not 0.06 in doubles, and reading READY would be a new core number in def (lane 1 page).
row("display.cap", 0.06, "s", "design", "L1827 (plan: CAP_WAIT vs READY)", "HOLD, CLAMP") -- I.CAP_WAIT

-- Rows and units (docs/research/2026-10-23-damagemeter-api.md, DM 2-4, 7).
row("wound.taken", 0.6, "s", "measured", "DM research (389-565 ms)", "EXCL, DL") -- I.TAKEN_ROW_LAG
row("meter.merge", 0.003, "s", "measured", "DM research", "ATT") -- Outcomes/Meter.lua
row("meter.swing", 0.015, "s", "measured", "DM research", "ATT")
row("meter.spell.taken", 0.005, "s", "measured", "DM research", "ATT")
row("meter.taken.far", 0.6, "s", "measured", "DM research", "ATT")
row("meter.taken.near", 0.3, "s", "measured", "DM research", "ATT")
row("unit.dup", 0.005, "s", "unmeasured", "unit-registry spec (none stated)", "ATT") -- Sources/Units.lua
row("unit.kill", 0.010, "s", "unmeasured", "unit-registry spec (none stated)", "ATT")

-- a plain aura read at most this long before our cast, or after it, shows its effect (Auras.lua)
I.SAME_FRAME = Lat.lag("aura.read")
I.CAP_WAIT = Lat.lag("display.cap")

-- The core's usability lag replaces the load value at the build (Families/Resources.lua re-reads I.GAIN_SHOWS then).
I.OnBuild(function(def)
    if def.oracleMin then
        Lat.rows["usable.shows"].lag = def.oracleMin
    end
end)
