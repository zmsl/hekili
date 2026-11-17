-- Locales/zhCN.lua
-- Simplified Chinese (zhCN) translation of Hekili Forever (Hekili_Priest). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Priest", "zhCN")
if not L then
    return
end

-- Hekili_Priest/Priest.lua
L["Discipline"] = "戒律"
L["Holy"] = "神圣"
L["Shadow"] = "暗影"
L["Prefer Starshards"] = "优先星辰碎片"
L["Shadow only, and only when you know Starshards (the Night Elf racial). When enabled, the priority shows Starshards before Mind Flay whenever Mind Blast is 4 seconds or more from ready. Off: the priority never shows Starshards."] = "仅限暗影，且仅在你学会星辰碎片（暗夜精灵种族技能）时生效。启用后，只要心灵震爆还需 4 秒或更久才冷却完毕，优先级就会把星辰碎片排在精神鞭笞之前。关闭时：优先级永不显示星辰碎片。"
L["Shadow (wowsims.com)"] = "暗影（wowsims）"
L["Smite (wowsims.com)"] = "惩击（wowsims）"
