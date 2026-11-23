-- Locales/esES.lua
-- Spanish (esES, esMX) translation of Hekili Forever (Hekili_Shared). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local Locale = LibStub("AceLocale-3.0")
local L = Locale:NewLocale("Hekili_Shared", "esES") or Locale:NewLocale("Hekili_Shared", "esMX")
if not L then
    return
end

-- Hekili_Shared/Shared/Consumables.lua
L["Healthstone"] = "Piedra de salud"
L["Healing Potion"] = "Poción de sanación"
