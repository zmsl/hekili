-- Locales/esES.lua
-- Spanish (esES, esMX) translation of Hekili Forever (Hekili_Warrior). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local Locale = LibStub("AceLocale-3.0")
local L = Locale:NewLocale("Hekili_Warrior", "esES") or Locale:NewLocale("Hekili_Warrior", "esMX")
if not L then
    return
end

-- Hekili_Warrior/Warrior.lua
L["Arms"] = "Armas"
L["Fury"] = "Furia"
L["Protection"] = "Protección"
L["Recklessness (wowsims.com)"] = "Temeridad (wowsims.com)"
L["The wowsims.com priority's Recklessness ON/OFF switch (its default in wowsims's own APL)."] = "La opción ON/OFF Temeridad de la prioridad de wowsims.com (su valor predeterminado en el propio APL de wowsims)."
L["Stance Dance (wowsims.com)"] = "Baile de actitudes (wowsims.com)"
L["The wowsims.com priority's Stance Dance ON/OFF switch (its default in wowsims's own APL)."] = "La opción ON/OFF Stance Dance (baile de actitudes) de la prioridad de wowsims.com (su valor predeterminado en el propio APL de wowsims)."
L["Rend Weave (wowsims.com)"] = "Desgarrar intercalado (wowsims.com)"
L["The wowsims.com priority's Rend Weave ON/OFF switch (its default in wowsims's own APL)."] = "La opción ON/OFF Rend Weave (Desgarrar intercalado) de la prioridad de wowsims.com (su valor predeterminado en el propio APL de wowsims)."
L["Maintain Demoralizing Shout"] = "Mantener Grito desmoralizador"
L["Keep Demoralizing Shout on the target, as a raid tank does. Off: the priority never shows it."] = "Mantén Grito desmoralizador en el objetivo, como hace un tanque de banda. Desactivado: la prioridad nunca lo muestra."
L["Maintain Thunder Clap"] = "Mantener Trueno"
L["Keep Thunder Clap's slow on the target, recasting it only when it is missing (that includes the levels before Mortal Strike). Off: the priority never shows Thunder Clap."] = "Mantén la ralentización de Trueno en el objetivo y vuelve a lanzarlo solo cuando falte (también en los niveles anteriores a Golpe mortal). Desactivado: la prioridad nunca muestra Trueno."
L["Protection (wowsims.com)"] = "Protección (wowsims.com)"
L["Fury (wowsims.com)"] = "Furia (wowsims.com)"
L["Arms (wowsims.com)"] = "Armas (wowsims.com)"
