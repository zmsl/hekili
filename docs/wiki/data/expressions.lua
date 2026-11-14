-- docs/wiki/data/expressions.lua: what each expression means, written by hand (tools/wiki/collect/expressions.lua).
-- The scan of src/Hekili/Engine/Sim/State.lua lists the keys of each root a wiki table covers; `make wiki-check`
-- fails on a scanned key with no entry here, and on an entry that no longer evaluates in a booted state or whose
-- example no longer compiles. `omit` leaves a key out of the tables, with the reason.
-- Fields: type, meaning, forever (what the value is on the Forever client), example (a condition that uses it).
return {
    -- resources: <resource> is a resource's name (energy, rage, mana, combo_points ...)
    ["<resource>.current"] = {
        type = "number",
        meaning = "The best estimate of the amount",
        forever = "Estimated while hidden",
        example = "combo_points.current>=5",
    },
    ["<resource>.lo"] = {
        type = "number",
        meaning = "The lowest amount there can be",
        forever = "Estimated while hidden",
        example = "energy.lo>=60",
    },
    ["<resource>.hi"] = {
        type = "number",
        meaning = "The highest amount there can be",
        forever = "Estimated while hidden",
        example = "rage.hi<30",
    },
    ["<resource>.max"] = {
        type = "number",
        meaning = "The maximum",
        forever = "Read",
        example = "energy.max>100",
    },
    ["<resource>.pct"] = {
        type = "percent",
        meaning = "`current` as a share of `max`",
        forever = "Estimated while hidden",
        example = "mana.pct<50",
    },
    ["<resource>.pct_lo"] = {
        type = "percent",
        meaning = "`lo` as a share of `max`",
        forever = "Estimated while hidden",
        example = "mana.pct_lo<30",
    },
    ["<resource>.deficit"] = {
        type = "number",
        meaning = "`max` minus `current`",
        forever = "Estimated while hidden",
        example = "energy.deficit<20",
    },
    ["<resource>.deficit_pct"] = {
        type = "percent",
        meaning = "`deficit` as a share of `max`",
        forever = "Estimated while hidden",
        example = "mana.deficit_pct>40",
    },
    ["<resource>.regen"] = {
        type = "number per second",
        meaning = "The regeneration rate now",
        forever = "Modelled",
        example = "energy.regen>10",
    },
    ["<resource>.time_to_max"] = {
        type = "seconds",
        meaning = "Time until full",
        forever = "Modelled",
        example = "energy.time_to_max<1",
    },
    ["<resource>.time_to_<N>"] = {
        type = "seconds",
        meaning = "Time until the amount reaches N",
        forever = "Modelled",
        example = "energy.time_to_40<0.5",
    },
    ["<resource>.time_to_deficit_<N>"] = {
        type = "seconds",
        meaning = "Time until the amount is N below `max`",
        forever = "Modelled",
        example = "energy.time_to_deficit_20<1",
    },
    ["<resource>.percent"] = { omit = "the same as pct" },
    ["<resource>.deficit_percent"] = { omit = "the same as deficit_pct" },
    ["<resource>.base_deficit"] = { omit = "the same as deficit" },
    ["<resource>.max_nonproc"] = { omit = "the same as max" },
    ["<resource>.modmax"] = { omit = "the same as max" },
    ["<resource>.base_time_to_max"] = { omit = "the same as time_to_max" },
    ["<resource>.time_to_max_combined"] = { omit = "the same as time_to_max" },
    ["<resource>.regen_combined"] = { omit = "kept from retail Hekili; the shipped priorities do not use it" },
    ["<resource>.model"] = { omit = "an engine field, not an expression" },
    ["<resource>.onAdvance"] = { omit = "an engine hook, not an expression" },

    -- time to die
    ["fight_remains"] = {
        type = "seconds",
        meaning = "Time until the longest-lived enemy dies",
        forever = "Always 3600 (unknown)",
        example = "fight_remains>60",
    },
    ["target.time_to_die"] = {
        type = "seconds",
        meaning = "Time until the target dies",
        forever = "Always 3600 (unknown)",
        example = "target.time_to_die>12",
    },
    ["target.time_to_pct_<N>"] = {
        type = "seconds",
        meaning = "Time until the target falls to N percent health",
        forever = "Always 3600 (unknown)",
        example = "target.time_to_pct_20>5",
    },
}
