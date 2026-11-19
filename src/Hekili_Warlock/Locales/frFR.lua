-- Locales/frFR.lua
-- French (frFR) translation of Hekili Forever (Hekili_Warlock). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Warlock", "frFR")
if not L then
    return
end

-- Hekili_Warlock/Warlock.lua
L["Affliction"] = "Affliction"
L["Demonology"] = "Démonologie"
L["Destruction"] = "Destruction"
L["Assigned Curse"] = "Malédiction assignée"
L["The curse the wowsims.com priority keeps on the target (wowsims's Curses option). No Curse: none."] = "La malédiction que la priorité wowsims.com garde sur la cible (l’option Curses de wowsims). Aucune malédiction : aucune."
L["Curse of the Elements"] = "Malédiction des éléments"
L["Curse of Recklessness"] = "Malédiction de témérité"
L["Curse of Weakness"] = "Malédiction de faiblesse"
L["No Curse"] = "Aucune malédiction"
L["Affliction (wowsims.com)"] = "Affliction (wowsims.com)"
L["Demonology (wowsims.com)"] = "Démonologie (wowsims.com)"
L["Destruction (wowsims.com)"] = "Destruction (wowsims.com)"
L["SM Ruin (wowsims.com)"] = "SM Ruin (wowsims.com)"
L["Shadow Brand (wowsims.com)"] = "Shadow Brand (wowsims.com)"
