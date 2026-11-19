-- Locales/esES.lua
-- Spanish (esES, esMX) translation of Hekili Forever (Hekili_Priest). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local Locale = LibStub("AceLocale-3.0")
local L = Locale:NewLocale("Hekili_Priest", "esES") or Locale:NewLocale("Hekili_Priest", "esMX")
if not L then
    return
end

-- Hekili_Priest/Priest.lua
L["Discipline"] = "Disciplina"
L["Holy"] = "Sagrado"
L["Shadow"] = "Sombra"
L["Prefer Starshards"] = "Preferir Fragmentos estelares"
L["Shadow only, and only when you know Starshards (the Night Elf racial). When enabled, the priority shows Starshards before Mind Flay whenever Mind Blast is 4 seconds or more from ready. Off: the priority never shows Starshards."] = "Solo Sombra, y solo si conoces Fragmentos estelares (la racial de elfo de la noche). Si está activado, la prioridad muestra Fragmentos estelares antes que Despelleje mental siempre que a Explosión mental le falten 4 segundos o más para estar lista. Desactivado: la prioridad nunca muestra Fragmentos estelares."
L["Shadow (wowsims.com)"] = "Sombra (wowsims.com)"
L["Smite (wowsims.com)"] = "Acometida (wowsims.com)"
