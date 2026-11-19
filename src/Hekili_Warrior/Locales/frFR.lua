-- Locales/frFR.lua
-- French (frFR) translation of Hekili Forever (Hekili_Warrior). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Warrior", "frFR")
if not L then
    return
end

-- Hekili_Warrior/Warrior.lua
L["Arms"] = "Armes"
L["Fury"] = "Fureur"
L["Protection"] = "Protection"
L["Recklessness (wowsims.com)"] = "Témérité (wowsims.com)"
L["The wowsims.com priority's Recklessness ON/OFF switch (its default in wowsims's own APL)."] = "L’interrupteur Témérité ON/OFF de la priorité wowsims.com (sa valeur par défaut dans l’APL de wowsims)."
L["Stance Dance (wowsims.com)"] = "Danse des postures (wowsims.com)"
L["The wowsims.com priority's Stance Dance ON/OFF switch (its default in wowsims's own APL)."] = "L’interrupteur Danse des postures ON/OFF de la priorité wowsims.com (sa valeur par défaut dans l’APL de wowsims)."
L["Rend Weave (wowsims.com)"] = "Intercaler Pourfendre (wowsims.com)"
L["The wowsims.com priority's Rend Weave ON/OFF switch (its default in wowsims's own APL)."] = "L’interrupteur Intercaler Pourfendre ON/OFF de la priorité wowsims.com (sa valeur par défaut dans l’APL de wowsims)."
L["Maintain Demoralizing Shout"] = "Maintenir Cri démoralisant"
L["Keep Demoralizing Shout on the target, as a raid tank does. Off: the priority never shows it."] = "Garde Cri démoralisant sur la cible, comme un tank de raid. Désactivé : la priorité ne le montre jamais."
L["Maintain Thunder Clap"] = "Maintenir Coup de tonnerre"
L["Keep Thunder Clap's slow on the target, recasting it only when it is missing (that includes the levels before Mortal Strike). Off: the priority never shows Thunder Clap."] = "Garde le ralentissement de Coup de tonnerre sur la cible, et relance-le seulement quand il manque (y compris aux niveaux avant Frappe mortelle). Désactivé : la priorité ne montre jamais Coup de tonnerre."
L["Protection (wowsims.com)"] = "Protection (wowsims.com)"
L["Fury (wowsims.com)"] = "Fureur (wowsims.com)"
L["Arms (wowsims.com)"] = "Armes (wowsims.com)"
