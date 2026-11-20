-- Locales/frFR.lua
-- French (frFR) translation of Hekili Forever (Hekili_Priest). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Priest", "frFR")
if not L then
    return
end

-- Hekili_Priest/Priest.lua
L["Discipline"] = "Discipline"
L["Holy"] = "Sacré"
L["Shadow"] = "Ombre"
L["Prefer Starshards"] = "Préférer Éclats stellaires"
L["Shadow only, and only when you know Starshards (the Night Elf racial). When enabled, the priority shows Starshards before Mind Flay whenever Mind Blast is 4 seconds or more from ready. Off: the priority never shows Starshards."] = "Ombre uniquement, et seulement si tu connais Éclats stellaires (le racial des elfes de la nuit). Si activé, la priorité montre Éclats stellaires avant Fouet mental chaque fois qu’Attaque mentale est à 4 secondes ou plus d’être prête. Désactivé : la priorité ne montre jamais Éclats stellaires."
L["Shadow (wowsims.com)"] = "Ombre (wowsims.com)"
L["Smite (wowsims.com)"] = "Châtiment (wowsims.com)"
