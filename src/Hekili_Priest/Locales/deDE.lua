-- Locales/deDE.lua
-- German (deDE) translation of Hekili Forever (Hekili_Priest). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Priest", "deDE")
if not L then
    return
end

-- Hekili_Priest/Priest.lua
L["Discipline"] = "Disziplin"
L["Holy"] = "Heilig"
L["Shadow"] = "Schatten"
L["Prefer Starshards"] = "Sternensplitter bevorzugen"
L["Shadow only, and only when you know Starshards (the Night Elf racial). When enabled, the priority shows Starshards before Mind Flay whenever Mind Blast is 4 seconds or more from ready. Off: the priority never shows Starshards."] = "Nur Schatten, und nur wenn du Sternensplitter kennst (die Volksfähigkeit der Nachtelfen). Wenn aktiviert, zeigt die Priorität Sternensplitter vor Gedankenschinden, sobald Gedankenschlag noch 4 Sekunden oder länger braucht. Aus: Die Priorität zeigt Sternensplitter nie."
L["Shadow (wowsims.com)"] = "Schatten (wowsims.com)"
L["Smite (wowsims.com)"] = "Göttliche Pein (wowsims.com)"
