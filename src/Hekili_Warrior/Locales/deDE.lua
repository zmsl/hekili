-- Locales/deDE.lua
-- German (deDE) translation of Hekili Forever (Hekili_Warrior). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Warrior", "deDE")
if not L then
    return
end

-- Hekili_Warrior/Warrior.lua
L["Arms"] = "Waffen"
L["Fury"] = "Furor"
L["Protection"] = "Schutz"
L["Recklessness (wowsims.com)"] = "Tollkühnheit (wowsims.com)"
L["The wowsims.com priority's Recklessness ON/OFF switch (its default in wowsims's own APL)."] = "AN/AUS-Schalter der wowsims.com-Priorität für Tollkühnheit (Standard wie in der APL von wowsims)."
L["Stance Dance (wowsims.com)"] = "Haltungstanz (wowsims.com)"
L["The wowsims.com priority's Stance Dance ON/OFF switch (its default in wowsims's own APL)."] = "AN/AUS-Schalter der wowsims.com-Priorität für Haltungstanz (Standard wie in der APL von wowsims)."
L["Rend Weave (wowsims.com)"] = "Verwunden-Weaving (wowsims.com)"
L["The wowsims.com priority's Rend Weave ON/OFF switch (its default in wowsims's own APL)."] = "AN/AUS-Schalter der wowsims.com-Priorität für Verwunden-Weaving (Standard wie in der APL von wowsims)."
L["Maintain Demoralizing Shout"] = "Demoralisierungsruf halten"
L["Keep Demoralizing Shout on the target, as a raid tank does. Off: the priority never shows it."] = "Hält Demoralisierungsruf auf dem Ziel, wie es ein Raid-Tank tut. Aus: Die Priorität zeigt ihn nie."
L["Maintain Thunder Clap"] = "Donnerknall halten"
L["Keep Thunder Clap's slow on the target, recasting it only when it is missing (that includes the levels before Mortal Strike). Off: the priority never shows Thunder Clap."] = "Hält die Verlangsamung von Donnerknall auf dem Ziel und wirkt ihn nur neu, wenn sie fehlt (auch auf den Stufen vor Tödlicher Stoß). Aus: Die Priorität zeigt Donnerknall nie."
L["Protection (wowsims.com)"] = "Schutz (wowsims.com)"
L["Fury (wowsims.com)"] = "Furor (wowsims.com)"
L["Arms (wowsims.com)"] = "Waffen (wowsims.com)"
