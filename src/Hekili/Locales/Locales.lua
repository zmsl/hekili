-- Locales/Locales.lua
-- ns.L: every piece of text a player sees is written L["English text"]. The key is the English text, so English needs
-- no table of its own and a key a language has not translated shows in English. Each language file next to this one
-- (zhCN.lua) fills ns.L only on its own client. Hekili.L (Hekili.lua) is the same table, for the class packs.
-- Text built from parts is a format string, so a translation can reorder it: L["%s is now %s."]:format(name, value).
-- After changing any text, run `python3 tools/locales.py` (docs/dev/architecture.md, "Localization").

local _, ns = ...

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

ns.L = L
ns.Locale = ns.Facade.GetLocale() or "enUS"
