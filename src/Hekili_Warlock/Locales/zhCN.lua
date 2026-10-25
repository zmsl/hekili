-- Locales/zhCN.lua
-- Simplified Chinese (zhCN) translation of Hekili Forever (Hekili_Warlock). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Warlock", "zhCN")
if not L then
    return
end

-- Hekili_Warlock/Warlock.lua
L["Affliction"] = "痛苦"
L["Demonology"] = "恶魔学识"
L["Destruction"] = "毁灭"
L["Assigned Curse"] = "指定诅咒"
L["The curse the wowsims.com priority keeps on the target (wowsims's Curses option). No Curse: none."] = "wowsims.com 优先级在目标身上保持的诅咒（即 wowsims 的“指定诅咒”选项）。无诅咒：不施放。"
L["Curse of the Elements"] = "元素诅咒"
L["Curse of Recklessness"] = "鲁莽诅咒"
L["Curse of Weakness"] = "虚弱诅咒"
L["No Curse"] = "无诅咒"
-- L["Affliction (wowsims.com)"] = ""
-- L["Demonology (wowsims.com)"] = ""
-- L["Destruction (wowsims.com)"] = ""
-- L["SM Ruin (wowsims.com)"] = ""
-- L["Shadow Brand (wowsims.com)"] = ""
