-- src/Hekili_Druid/APLs/packs.lua: the Forever Druid's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua druid): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it);
-- the pack date lives in Druid.lua's generated blocks, and `make packs` sets it to today only when a pack changed.
-- Each pack is generated from its recipe (tools/wowsims/specs/druid_*.lua, `make wowsims-packs`): wowsims/forever's
-- default APLs (MIT, https://github.com/wowsims/forever). The hand-built Feral, Guardian and Balance lists are retired
-- (Druid.lua's spec:RetirePacks).
-- Feral and Guardian follow the form (owner 2026-11-10): each imports the other's lists at every build, entered while
-- that form is up, so a re-translation of either updates both; caster form runs the pack's own list. Druid.lua shows
-- the setting the imported lines read on the importing spec's page too.

return {
    class = "DRUID",
    packs = { "Feral (wowsims.com)", "Balance (wowsims.com)", "Guardian (wowsims.com)" },
    specs = {
        ["Feral (wowsims.com)"] = "feral",
        ["Balance (wowsims.com)"] = "balance",
        ["Guardian (wowsims.com)"] = "guardian",
    },
    imports = {
        ["Feral (wowsims.com)"] = { from = "Guardian (wowsims.com)", as = "bear", aura = "bear_form" },
        ["Guardian (wowsims.com)"] = { from = "Feral (wowsims.com)", as = "cat", aura = "cat_form" },
    },
}
