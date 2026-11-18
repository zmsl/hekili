-- Locales/zhCN.lua
-- Simplified Chinese (zhCN) translation of Hekili Forever (Hekili_Hunter). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Hunter", "zhCN")
if not L then
    return
end

-- Hekili_Hunter/Hunter.lua
L["Beast Mastery"] = "野兽控制"
L["Marksmanship"] = "射击"
L["Survival"] = "生存"
L["Survival (wowsims.com)"] = "生存（wowsims）"
L["Beast Mastery Turret (wowsims.com)"] = "野兽控制站桩（wowsims）"
L["Marksmanship Turret (wowsims.com)"] = "射击站桩（wowsims）"
L["Survival Turret (wowsims.com)"] = "生存站桩（wowsims）"
L["Survival Melee (wowsims.com)"] = "生存近战（wowsims）"

-- No longer used (the English changed or went away): reuse or delete
L["Beast Mastery (wowsims.com)"] = "野兽控制（wowsims）"
L["Marksmanship (wowsims.com)"] = "射击（wowsims）"
