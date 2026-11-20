-- Locales/deDE.lua
-- German (deDE) translation of Hekili Forever (Hekili_Druid). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Druid", "deDE")
if not L then
    return
end

-- Hekili_Druid/Druid.lua
L["Balance"] = "Gleichgewicht"
L["Feral"] = "Wildheit"
L["Guardian"] = "Wächter"
L["Restoration"] = "Wiederherstellung"
L["Always Behind"] = "Immer hinter dem Ziel"
L["Hekili assumes you are always behind the target. Below 2 ranks of Shredding Attacks, Claw is still preferred unless Clearcasting makes Shred free."] = "Hekili geht davon aus, dass du immer hinter dem Ziel stehst. Unter 2 Rängen Schreddernde Angriffe wird weiter Klaue bevorzugt, außer Freizaubern macht Schreddern kostenlos."
L["Maintain Demoralizing Roar"] = "Demoralisierendes Gebrüll halten"
L["Keep Demoralizing Roar on the target, as a raid tank does, and recast it only when it is missing (that includes the levels before Lacerate). Off: the priority never shows it, and Berserk no longer waits for it."] = "Hält Demoralisierendes Gebrüll auf dem Ziel, wie es ein Raid-Tank tut, und wirkt es nur neu, wenn es fehlt (auch auf den Stufen vor Aufschlitzen). Aus: Die Priorität zeigt es nie, und Berserker wartet nicht mehr darauf."
L["Bear Form (Guardian)"] = "Bärengestalt (Wächter)"
L["These settings come from the Guardian priority. They apply only while you are in Bear Form."] = "Diese Einstellungen stammen aus der Priorität „Wächter“. Sie gelten nur, solange du in Bärengestalt bist."
L["Cat Form (Feral)"] = "Katzengestalt (Wildheit)"
L["These settings come from the Feral priority. They apply only while you are in Cat Form."] = "Diese Einstellungen stammen aus der Priorität „Wildheit“. Sie gelten nur, solange du in Katzengestalt bist."
L["Feral (wowsims.com)"] = "Wildheit (wowsims.com)"
L["Balance (wowsims.com)"] = "Gleichgewicht (wowsims.com)"
L["Guardian (wowsims.com)"] = "Wächter (wowsims.com)"
