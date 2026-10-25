-- Locales/zhCN.lua
-- Simplified Chinese (zhCN) translation of Hekili Forever (Hekili_Druid). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Druid", "zhCN")
if not L then
    return
end

-- Hekili_Druid/Druid.lua
L["Balance"] = "平衡"
L["Feral"] = "野性"
L["Guardian"] = "守护"
L["Restoration"] = "恢复"
L["Always Behind"] = "始终在背后"
L["When enabled, Shred is recommended over Claw as if you always stand behind the target."] = "启用后，将始终推荐撕碎而非爪击，视同你一直站在目标背后。"
L["Maintain Demoralizing Roar"] = "保持挫志咆哮"
L["Keep Demoralizing Roar on the target, as a raid tank does (and use it as the leveling filler before Lacerate). Off: the priority never shows it, and Berserk no longer waits for it."] = "像团队坦克那样在目标身上保持挫志咆哮（在学会割伤之前也作为练级填充技能）。关闭时：优先级永不显示它，狂暴也不再等待它。"
-- L["Feral (wowsims.com)"] = ""
-- L["Balance (wowsims.com)"] = ""
-- L["Guardian (wowsims.com)"] = ""
