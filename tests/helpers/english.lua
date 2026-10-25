-- tests/helpers/english.lua
-- The string table an English client gives every addon headless (Hekili:GetLocale's and ns.L's stand-in): each key
-- answers itself, as AceLocale-3.0's silent mode does for a key no table holds.
return setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
