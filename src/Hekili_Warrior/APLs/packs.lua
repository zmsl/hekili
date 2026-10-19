-- src/Hekili_Warrior/APLs/packs.lua: the Forever Warrior's pack manifest for tools/make_pack.lua (its default class):
-- the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside this file) and each pack's
-- spec key. Dev-only (no TOC lists it); the pack date lives in Warrior.lua's generated blocks, and `make packs` sets it
-- to today only when a pack changed.
-- The Arms and Fury lists are ported from Hekili's Classic profile (origin/classic:Classic/APLs/WarriorArms.simc,
-- WarriorFury.simc); the Protection list's shape is archive/TheWarWithin/Priorities/WarriorProtection.simc's.

return {
    class = "WARRIOR",
    packs = { "Arms", "Fury", "Protection" },
    specs = { Arms = "arms", Fury = "fury", Protection = "protection" },
}
