-- Locales/frFR.lua
-- French (frFR) translation of Hekili Forever (Hekili_Druid). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Druid", "frFR")
if not L then
    return
end

-- Hekili_Druid/Druid.lua
L["Balance"] = "Équilibre"
L["Feral"] = "Farouche"
L["Guardian"] = "Gardien"
L["Restoration"] = "Restauration"
L["Always Behind"] = "Toujours dans le dos"
L["Hekili assumes you are always behind the target. Below 2 ranks of Shredding Attacks, Claw is still preferred unless Clearcasting makes Shred free."] = "Hekili suppose que tu es toujours dans le dos de la cible. Sous 2 rangs d’Attaques lacérantes, Griffe reste préférée, sauf si Idées claires rend Lambeau gratuit."
L["Maintain Demoralizing Roar"] = "Maintenir Rugissement démoralisant"
L["Keep Demoralizing Roar on the target, as a raid tank does, and recast it only when it is missing (that includes the levels before Lacerate). Off: the priority never shows it, and Berserk no longer waits for it."] = "Garde Rugissement démoralisant sur la cible, comme un tank de raid, et relance-le seulement quand il manque (y compris aux niveaux avant Lacérer). Désactivé : la priorité ne le montre jamais, et Berserk ne l’attend plus."
L["Bear Form (Guardian)"] = "Forme d’ours (Gardien)"
L["These settings come from the Guardian priority. They apply only while you are in Bear Form."] = "Ces réglages viennent de la priorité Gardien. Ils s’appliquent seulement en Forme d’ours."
L["Cat Form (Feral)"] = "Forme de félin (Farouche)"
L["These settings come from the Feral priority. They apply only while you are in Cat Form."] = "Ces réglages viennent de la priorité Farouche. Ils s’appliquent seulement en Forme de félin."
L["Feral (wowsims.com)"] = "Farouche (wowsims.com)"
L["Balance (wowsims.com)"] = "Équilibre (wowsims.com)"
L["Guardian (wowsims.com)"] = "Gardien (wowsims.com)"
