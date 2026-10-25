-- Locales/zhCN.lua
-- Simplified Chinese (zhCN) translation of Hekili Forever (Hekili_Paladin). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Paladin", "zhCN")
if not L then
    return
end

-- Hekili_Paladin/Paladin.lua
L["Holy"] = "神圣"
L["Protection"] = "防护"
L["Retribution"] = "惩戒"
