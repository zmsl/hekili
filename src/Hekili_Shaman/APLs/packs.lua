-- src/Hekili_Shaman/APLs/packs.lua: the Forever Shaman's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua shaman): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it); the pack date lives in Shaman.lua's generated block,
-- and `make packs` sets it to today only when a pack changed.
-- After wowsims/forever's Enhancement APL (ui/specs/shaman/enhancement/apls/default.apl.json; MIT, reference only).
-- Left out on purpose: Windfury Totem (the party's, research §4), racials and trinkets (autocastOtherCooldowns).
-- Elemental joins in Task 17.

return { class = "SHAMAN", packs = { "Enhancement" }, specs = { Enhancement = "enhancement" } }
