-- tools/wiki/manifest.lua: every generated table. A page asks for one with
--   <!-- GENERATED:<name> -->
--   <!-- /GENERATED -->
-- and `make wiki-build` fills the pair in a copy under build/wiki/ and docs/wiki/ keeps the pair empty (tools/wiki/gen.lua). Each entry names its
-- collector (tools/wiki/collect/<collector>.lua), the collector's arguments, the table's headers and, for an "n/a"
-- cell, the note under the table that says what it means. A name a page uses that is not here is an error.
local OPTION_COLUMNS = { "section", "label", "type", "shown", "default", "range", "description" }
local OPTION_HEADERS = { "Section", "Option", "Type", "Shown", "Default", "Values", "Description" }
local SHOWN_NOTE = "Shown: In some cases means the option appears only in some cases, for example while another "
    .. "option is on, for a class with a pet, for one kind of entry, or with Advanced checked."
local OPTION_NOTE = "n/a: no fixed default (a keybind not set, or a value that follows the game or another option), "
    .. "no range, or no description. "
    .. SHOWN_NOTE
local RESOURCE_ORDER = {
    "current",
    "lo",
    "hi",
    "max",
    "pct",
    "pct_lo",
    "deficit",
    "deficit_pct",
    "regen",
    "time_to_max",
    "time_to_<N>",
    "time_to_deficit_<N>",
}
local EXPRESSION_HEADERS = { "Expression", "Type", "Meaning", "On Forever", "Example" }

local function display(path)
    return {
        collector = "options",
        path = { "displays", "Primary", path },
        columns = OPTION_COLUMNS,
        headers = OPTION_HEADERS,
        note = OPTION_NOTE,
    }
end

return {
    -- APL-Expression-Reference
    ["expressions-resource"] = {
        collector = "expressions",
        root = "mt_resource", -- the scan: Engine/Sim/State.lua's mt_resource __index branches
        prefix = "<resource>",
        order = RESOURCE_ORDER,
        headers = EXPRESSION_HEADERS,
    },
    ["expressions-time-to-die"] = {
        collector = "expressions",
        keys = { "fight_remains", "target.time_to_die", "target.time_to_pct_<N>" },
        headers = EXPRESSION_HEADERS,
    },

    -- Slash-Commands
    ["slash-commands"] = {
        collector = "commands",
        fn = "rows",
        headers = { "Command", "Aliases", "What it does" },
        note = "n/a: the command has no shorter form.",
    },
    ["slash-command-words"] = {
        collector = "commands",
        fn = "wordRows",
        headers = { "Alias", "Stands for", "Names" },
    },

    -- Toggles, Specializations-Reference, APL-Priority-Editor, Displays-Reference
    ["options-toggles"] = {
        collector = "options",
        path = { "toggles" },
        columns = { "section", "label", "type", "default", "description" },
        headers = { "Section", "Option", "Type", "Default", "Description" },
        note = "n/a: no keybind is set by default, or no description.",
    },
    ["options-spec"] = {
        collector = "options",
        path = { "packs", "<spec>" },
        exclude = { "<pack>", "cycleGroup" }, -- the priority editor: options-editor; Filter by Time-to-Die, always hidden
        noSettings = true, -- the class settings: spec-settings
        perSpec = { "package", "potion" },
        columns = OPTION_COLUMNS,
        headers = OPTION_HEADERS,
        note = OPTION_NOTE,
    },
    ["options-editor"] = {
        collector = "options",
        path = { "packs", "<spec>", "<pack>" },
        columns = { "section", "label", "type", "shown", "range", "description" },
        headers = { "Section", "Field", "Type", "Shown", "Values", "Description" },
        note = "n/a: free text, or no description. " .. SHOWN_NOTE,
    },
    ["options-displays-all"] = {
        collector = "options",
        path = { "displays" },
        depth = 1,
        columns = { "label", "type", "default", "range", "description" },
        headers = { "Option", "Type", "Default", "Values", "Description" },
        note = "n/a: no default value (a button), no range, or no description.",
    },
    ["options-display-icons"] = display("main"),
    ["options-display-classic"] = display("classic"),
    ["options-display-timeline"] = display("timeline"),
    ["options-display-modern"] = display("truth"),
    ["options-display-visibility"] = display("visibility"),

    -- Setting-Up-Target-Counting
    ["spec-defaults-nameplate"] = {
        collector = "specs",
        fn = "nameplate",
        headers = { "Class", "Specializations", "Default (yards)" },
    },

    -- Supported-Classes-And-Priorities
    ["supported-priorities"] = {
        collector = "specs",
        fn = "packs",
        headers = { "Class", "Specialization", "Default priority", "Other built-in priorities" },
        note = "n/a: the specialization has no other built-in priority.",
    },

    -- Specializations-Reference (players: no key column) and Pack-Settings (authors)
    ["spec-settings"] = {
        collector = "specs",
        fn = "settings",
        pick = { 1, 2, 3, 5, 6, 7 },
        headers = { "Class", "Specializations", "Setting", "Type", "Default", "Description" },
        note = "n/a: no description.",
    },
    ["pack-settings"] = {
        collector = "specs",
        fn = "settings",
        pick = { 1, 2, 4, 3, 5, 6 },
        headers = { "Class", "Specializations", "Key", "Label", "Type", "Default" },
    },

    -- Pack-API-Reference
    ["register-api"] = {
        collector = "api",
        fn = "rows",
        headers = { "Call", "Parameters", "Offered by", "Used by" },
        note = "Offered by: the registration object (class: Hekili:NewClass; shared: Hekili:NewShared; race: "
            .. "Hekili:NewRace). n/a: no parameters, or no content addon calls it.",
    },

    -- Accuracy
    ["accuracy-meta"] = {
        collector = "accuracy",
        fn = "meta",
        headers = { "Accuracy measurements", "" },
    },
    accuracy = {
        collector = "accuracy",
        fn = "rows",
        headers = {
            "Class",
            "Specialization or priority",
            "Matches wowsims",
            "Hidden values, solo",
            "Hidden values, crowded target",
        },
        note = "n/a: wowsims has no fight log for this case.",
    },
}
