-- Locales/deDE.lua
-- German (deDE) translation of Hekili Forever (Hekili_Warlock). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Warlock", "deDE")
if not L then
    return
end

-- Hekili_Warlock/Warlock.lua
L["Affliction"] = "Gebrechen"
L["Demonology"] = "Dämonologie"
L["Destruction"] = "Zerstörung"
L["Assigned Curse"] = "Zugewiesener Fluch"
L["The curse the wowsims.com priority keeps on the target (wowsims's Curses option). No Curse: none."] = "Der Fluch, den die Priorität von wowsims.com auf dem Ziel hält (die Option „Curses“ von wowsims). Kein Fluch: keiner."
L["Curse of the Elements"] = "Fluch der Elemente"
L["Curse of Recklessness"] = "Fluch der Tollkühnheit"
L["Curse of Weakness"] = "Fluch der Schwäche"
L["No Curse"] = "Kein Fluch"
L["Affliction (wowsims.com)"] = "Gebrechen (wowsims.com)"
L["Demonology (wowsims.com)"] = "Dämonologie (wowsims.com)"
L["Destruction (wowsims.com)"] = "Zerstörung (wowsims.com)"
L["SM Ruin (wowsims.com)"] = "SM Ruin (wowsims.com)"
L["Shadow Brand (wowsims.com)"] = "Shadow Brand (wowsims.com)"
