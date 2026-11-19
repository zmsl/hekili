-- Locales/esES.lua
-- Spanish (esES, esMX) translation of Hekili Forever (Hekili_Warlock). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local Locale = LibStub("AceLocale-3.0")
local L = Locale:NewLocale("Hekili_Warlock", "esES") or Locale:NewLocale("Hekili_Warlock", "esMX")
if not L then
    return
end

-- Hekili_Warlock/Warlock.lua
L["Affliction"] = "Aflicción"
L["Demonology"] = "Demonología"
L["Destruction"] = "Destrucción"
L["Assigned Curse"] = "Maldición asignada"
L["The curse the wowsims.com priority keeps on the target (wowsims's Curses option). No Curse: none."] = "La maldición que la prioridad de wowsims.com mantiene en el objetivo (la opción Curses de wowsims). Sin maldición: ninguna."
L["Curse of the Elements"] = "Maldición de los Elementos"
L["Curse of Recklessness"] = "Maldición de Temeridad"
L["Curse of Weakness"] = "Maldición de debilidad"
L["No Curse"] = "Sin maldición"
L["Affliction (wowsims.com)"] = "Aflicción (wowsims.com)"
L["Demonology (wowsims.com)"] = "Demonología (wowsims.com)"
L["Destruction (wowsims.com)"] = "Destrucción (wowsims.com)"
L["SM Ruin (wowsims.com)"] = "SM Ruin (wowsims.com)"
L["Shadow Brand (wowsims.com)"] = "Shadow Brand (wowsims.com)"
