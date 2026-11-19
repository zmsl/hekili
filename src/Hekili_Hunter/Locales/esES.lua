-- Locales/esES.lua
-- Spanish (esES, esMX) translation of Hekili Forever (Hekili_Hunter). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local Locale = LibStub("AceLocale-3.0")
local L = Locale:NewLocale("Hekili_Hunter", "esES") or Locale:NewLocale("Hekili_Hunter", "esMX")
if not L then
    return
end

-- Hekili_Hunter/Hunter.lua
L["Beast Mastery"] = "Dominio de bestias"
L["Marksmanship"] = "Puntería"
L["Survival"] = "Supervivencia"
L["Survival (wowsims.com)"] = "Supervivencia (wowsims.com)"
L["Beast Mastery Turret (wowsims.com)"] = "Dominio de bestias en torreta (wowsims.com)"
L["Marksmanship Turret (wowsims.com)"] = "Puntería en torreta (wowsims.com)"
L["Survival Turret (wowsims.com)"] = "Supervivencia en torreta (wowsims.com)"
L["Survival Melee (wowsims.com)"] = "Supervivencia cuerpo a cuerpo (wowsims.com)"
