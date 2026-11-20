-- Locales/esES.lua
-- Spanish (esES, esMX) translation of Hekili Forever (Hekili_Druid). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local Locale = LibStub("AceLocale-3.0")
local L = Locale:NewLocale("Hekili_Druid", "esES") or Locale:NewLocale("Hekili_Druid", "esMX")
if not L then
    return
end

-- Hekili_Druid/Druid.lua
L["Balance"] = "Equilibrio"
L["Feral"] = "Feral"
L["Guardian"] = "Guardián"
L["Restoration"] = "Recuperación"
L["Always Behind"] = "Siempre por detrás"
L["Hekili assumes you are always behind the target. Below 2 ranks of Shredding Attacks, Claw is still preferred unless Clearcasting makes Shred free."] = "Hekili da por hecho que siempre estás detrás del objetivo. Con menos de 2 rangos de Ataques trituradores se sigue prefiriendo Zarpa, salvo que Conjuro libre deje Triturar sin coste."
L["Maintain Demoralizing Roar"] = "Mantener Clamor desmoralizador"
L["Keep Demoralizing Roar on the target, as a raid tank does, and recast it only when it is missing (that includes the levels before Lacerate). Off: the priority never shows it, and Berserk no longer waits for it."] = "Mantén Clamor desmoralizador en el objetivo, como hace un tanque de banda, y vuelve a lanzarlo solo cuando falte (también en los niveles anteriores a Lacerar). Desactivado: la prioridad nunca lo muestra y Rabia ya no lo espera."
L["Bear Form (Guardian)"] = "Forma de oso (Guardián)"
L["These settings come from the Guardian priority. They apply only while you are in Bear Form."] = "Estos ajustes vienen de la prioridad Guardián. Solo se aplican mientras estás en Forma de oso."
L["Cat Form (Feral)"] = "Forma felina (Feral)"
L["These settings come from the Feral priority. They apply only while you are in Cat Form."] = "Estos ajustes vienen de la prioridad Feral. Solo se aplican mientras estás en Forma felina."
L["Feral (wowsims.com)"] = "Feral (wowsims.com)"
L["Balance (wowsims.com)"] = "Equilibrio (wowsims.com)"
L["Guardian (wowsims.com)"] = "Guardián (wowsims.com)"
