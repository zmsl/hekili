-- Locales/esES.lua
-- Spanish (esES, esMX) translation of Hekili Forever (Hekili_Shaman). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local Locale = LibStub("AceLocale-3.0")
local L = Locale:NewLocale("Hekili_Shaman", "esES") or Locale:NewLocale("Hekili_Shaman", "esMX")
if not L then
    return
end

-- Hekili_Shaman/Shaman.lua
L["Elemental"] = "Elemental"
L["Enhancement"] = "Mejora"
L["Restoration"] = "Recuperación"
L["Elemental (wowsims.com)"] = "Elemental (wowsims.com)"
L["Enhancement (wowsims.com)"] = "Mejora (wowsims.com)"
