-- src/Hekili_Druid/APLs/packs.lua: the Forever Druid's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua druid): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it);
-- the pack date lives in Druid.lua's generated blocks, and `make packs` sets it to today only when a pack changed.
-- Each pack is generated from its recipe (tools/wowsims/specs/druid_*.lua, `make wowsims-packs`): wowsims/forever's
-- default APLs (MIT, https://github.com/wowsims/forever). The hand-built Feral and Balance lists are retired
-- (Druid.lua's spec:RetirePacks). Guardian keeps its hand-built list (Guardian.simc, ported from Taco Dog Forever's bear.simc after
-- the guides it cites) until its wowsims.com pack's shared gaps close.

return {
    class = "DRUID",
    packs = { "Feral (wowsims.com)", "Balance (wowsims.com)", "Guardian" },
    specs = {
        ["Feral (wowsims.com)"] = "feral",
        ["Balance (wowsims.com)"] = "balance",
        Guardian = "guardian",
    },
}
