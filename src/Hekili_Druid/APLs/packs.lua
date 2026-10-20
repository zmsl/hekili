-- src/Hekili_Druid/APLs/packs.lua: the Forever Druid's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua druid): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it);
-- the pack date lives in Druid.lua's generated blocks, and `make packs` sets it to today only when a pack changed.
-- Ported from Taco Dog Forever's src/TacoDogForever_Druid/APLs/feral.simc (Nerdegghead's priority, via the user),
-- bear.simc and balance.simc (after the guides they cite), with Classic's precombat buffs
-- (origin/classic:Classic/APLs/DruidFeral.simc). Left out on purpose: Tiger's Fury, powershifting and the
-- cat_ps/innervate_or_shift lists, Omen of Clarity's precombat line, `ttd` guards (target health is secret), Faerie
-- Fire in cat, the ranged Moonfire opener, and the consumables.

return {
    class = "DRUID",
    packs = { "Feral (wowsims.com)", "Feral", "Guardian", "Balance" },
    specs = {
        ["Feral (wowsims.com)"] = "feral",
        Feral = "feral",
        Guardian = "guardian",
        Balance = "balance",
    },
}
