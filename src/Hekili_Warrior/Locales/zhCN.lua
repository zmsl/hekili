-- Locales/zhCN.lua
-- Simplified Chinese (zhCN) translation of Hekili Forever (Hekili_Warrior). Written by tools/locales.py, which keeps the translations and adds
-- new text as it appears: only edit the L[...] lines, other changes here are lost.
--
-- To translate a line, remove the "-- " in front and type the translation between the empty quotes:
--     -- L["Reset"] = ""
-- becomes
--     L["Reset"] = "..."
-- The key in L["..."] is the English text: leave it exactly as it is. Untranslated lines show in English. Keep every
-- format code (%s, %d, %.1f...), colour (|cFFFFD100...|r), texture (|T...|t) and line break (\n) of the English text.

local L = LibStub("AceLocale-3.0"):NewLocale("Hekili_Warrior", "zhCN")
if not L then
    return
end

-- Hekili_Warrior/Warrior.lua
L["Arms"] = "武器"
L["Fury"] = "狂怒"
L["Protection"] = "防护"
L["Recklessness (wowsims.com)"] = "鲁莽（wowsims.com）"
L["The wowsims.com priority's Recklessness ON/OFF switch (its default in wowsims's own APL)."] = "wowsims.com 优先级的鲁莽开/关选项（默认值与 wowsims 自身 APL 相同）。"
L["Stance Dance (wowsims.com)"] = "切姿态（wowsims.com）"
L["The wowsims.com priority's Stance Dance ON/OFF switch (its default in wowsims's own APL)."] = "wowsims.com 优先级的“切姿态 开/关”选项（默认值与 wowsims 自身 APL 相同）。"
L["Rend Weave (wowsims.com)"] = "穿插撕裂（wowsims.com）"
L["The wowsims.com priority's Rend Weave ON/OFF switch (its default in wowsims's own APL)."] = "wowsims.com 优先级的穿插撕裂开/关选项（默认值与 wowsims 自身 APL 相同）。"
L["Maintain Demoralizing Shout"] = "保持挫志怒吼"
L["Keep Demoralizing Shout on the target, as a raid tank does. Off: the priority never shows it."] = "像团队坦克那样在目标身上保持挫志怒吼。关闭时：优先级永不显示它。"
L["Maintain Thunder Clap"] = "保持雷霆一击"
L["Keep Thunder Clap's slow on the target (the leveling filler before Mortal Strike). Off: the priority never shows Thunder Clap."] = "在目标身上保持雷霆一击的减速效果（在学会致死打击之前作为练级填充技能）。关闭时：优先级永不显示雷霆一击。"
