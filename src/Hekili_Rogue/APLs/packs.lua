-- src/Hekili_Rogue/APLs/packs.lua: the Forever Rogue's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua rogue): the pseudo-spec (Hekili_Rogue/Rogue.lua's ROGUE_SPEC; run `make packs` when it changes)
-- and the packs in RegisterPack order, each one's text in <Pack>.simc beside this file. Dev-only (no TOC lists it);
-- the pack date lives in Rogue.lua's generated blocks, and `make packs` sets it to today only when a pack changed.
-- After wowsims/forever's one Rogue APL (ui/specs/rogue/dps/apls/default.apl.json, MIT, reference only), split by
-- build. Left out on purpose: the racials (Blood Fury), potions and trinkets, Kidney Shot, Cheap Shot, Riposte,
-- the "fight about to end" lines (no time to die on Forever) and the Thousand Cuts cost discount.

return { spec = 1500, packs = { "Combat", "Assassination", "Subtlety" } }
