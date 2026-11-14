-- docs/wiki/data/commands.lua: the reviewed list of /hekili commands (tools/wiki/collect/commands.lua). Every command
-- in Options/ChatCommands.lua must be listed here as public (published on Slash-Commands) or internal (not
-- published); `make wiki-check` fails on a command in neither list, and on a listed command that no longer exists.
return {
    -- the public commands, in the order the table lists them: what /hekili help lists, plus spec, snapshot, lock and
    -- unlock
    order = { "help", "set", "priority", "spec", "profile", "move", "unlock", "lock", "enable", "disable", "snapshot" },
    public = {
        help = { does = "Lists the chat commands, with your specialization's settings and their current values." },
        set = {
            usage = "set <toggle | mode | cycle | spec> [value]",
            does = "Turns a toggle on or off, changes the display mode or target swaps, or changes a specialization setting.",
        },
        priority = {
            usage = "priority [name | default]",
            does = "Lists your specialization's priorities, switches to one by name, or returns to the built-in default.",
        },
        spec = {
            usage = "spec [name]",
            does = "Lists your class's specializations, or activates one for your current talent tree.",
        },
        profile = { usage = "profile [name]", does = "Lists your profiles, or switches to one by name." },
        move = { does = "Unlocks the displays so they can be moved. Not available in combat." },
        unlock = { does = "The same as `/hekili move`." },
        lock = { does = "Locks the displays in place." },
        enable = { does = "Turns Hekili Forever on." },
        disable = { does = "Turns Hekili Forever off." },
        snapshot = { does = "Takes a snapshot of the current recommendations, shown on the Snapshots tab." },
    },
    -- handled by Hekili:CmdLine itself, not a handler in the table
    builtin = { help = true },
    -- commands that are not published: developer tools and repairs
    internal = {
        stress = "a stress test of the priorities",
        dotinfo = "a developer dump of damage-over-time data",
        recover = "restores the default displays and priorities",
        fix = "repairs for specific broken settings",
        skeleton = "a developer tool that gathers specialization data",
    },
    -- words a command accepts under another name (`/hekili set cds`): the word, and what it names
    wordAliases = {
        cooldowns = "The Major Cooldowns toggle",
        potions = "The Potions toggle",
        mode = "The display mode",
        cycle = "Target swaps",
        automatic = "The Automatic display mode",
    },
    -- words only an internal command reads, or that no command reads: their aliases are not published
    hiddenWords = {
        pack = "read by /hekili fix",
        lostmyui = "read by /hekili fix",
        infusion = "read by no public command",
    },
}
