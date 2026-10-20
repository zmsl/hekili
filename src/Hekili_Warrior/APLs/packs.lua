-- src/Hekili_Warrior/APLs/packs.lua: the Forever Warrior's pack manifest for tools/make_pack.lua (its default class):
-- the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside this file) and each pack's
-- spec key. Dev-only (no TOC lists it); the pack date lives in Warrior.lua's generated blocks, and `make packs` sets it
-- to today only when a pack changed.
-- Arms, Fury and Protection (wowsims.com) are generated (`make wowsims-packs`) from tools/wowsims/specs/warrior_arms.lua,
-- warrior_fury.lua and warrior_protection.lua.
-- The hand-built Arms, Fury and Protection lists are retired (Warrior.lua's spec:RetirePacks).

return {
    class = "WARRIOR",
    packs = {
        "Protection (wowsims.com)",
        "Fury (wowsims.com)",
        "Arms (wowsims.com)",
    },
    specs = {
        ["Protection (wowsims.com)"] = "protection",
        ["Fury (wowsims.com)"] = "fury",
        ["Arms (wowsims.com)"] = "arms",
    },
}
