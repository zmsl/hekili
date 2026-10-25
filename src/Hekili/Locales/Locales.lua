-- Locales/Locales.lua
-- ns.L: the core's string table, the AceLocale-3.0 app "Hekili" (silent: a key no table holds answers itself). Every
-- piece of text a player sees is written L["English text"]. Locales/enUS.lua (generated) loads first in the TOC's
-- locale block and holds every key; each language file next to it fills the table only on its own client; this file
-- loads last. After changing any text, run `python3 tools/locales.py` (docs/dev/architecture.md, "Localization").

local _, ns = ...

ns.L = LibStub("AceLocale-3.0"):GetLocale("Hekili")
