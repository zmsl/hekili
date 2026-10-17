-- tools/packs/druid.lua: the Forever Druid's pack manifest for tools/make_pack.lua (lua5.1 tools/make_pack.lua druid):
-- the pack date and pseudo-spec (Hekili_Druid/Druid.lua's DRUID_SPEC; run `make packs` when it changes), and the
-- packs in RegisterPack order, each one's text in tools/packs/druid/<Pack>.simc.
-- Ported from Taco Dog Forever's src/TacoDogForever_Druid/APLs/feral.simc (Nerdegghead's priority, via the user),
-- bear.simc and balance.simc (after the guides they cite), with Classic's precombat buffs
-- (origin/classic:Classic/APLs/DruidFeral.simc). Left out on purpose: Tiger's Fury, powershifting and the
-- cat_ps/innervate_or_shift lists, Omen of Clarity's precombat line, `ttd` guards (target health is secret), Faerie
-- Fire in cat, the ranged Moonfire opener, and the consumables.

return { date = 20261017, spec = 1499, packs = { "Feral", "Guardian", "Balance" } }
