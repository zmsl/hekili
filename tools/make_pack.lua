-- tools/make_pack.lua: prints a Hekili priority in the share format RegisterPack takes ("Hekili:" + LibDeflate print
-- encoding of the AceSerializer'd package), built headless with the vendored libraries. Run from the repository root:
--   lua5.1 tools/make_pack.lua
-- Edit PACK below, run it, and paste the printed string into the class file's spec:RegisterPack( ... [[ ]] ).
_G.strbyte, _G.strchar, _G.strsub, _G.strfind, _G.format = string.byte, string.char, string.sub, string.find, string.format
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")
dofile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
local LibDeflate, Serializer = LibStub("LibDeflate"), LibStub("AceSerializer-3.0")

local function entry(action, criteria)
    return { action = action, enabled = true, criteria = criteria }
end

local DATE = 20261015
local PACK = {
    type = "package",
    name = "Warrior",
    date = DATE,
    payload = {
        spec = 1491,
        builtIn = false,
        hidden = false,
        date = DATE,
        version = DATE,
        author = "Hekili (Forever)",
        desc = "Forever Warrior for the VirtualState Phase 1 checkpoint: Battle Shout up, Rend kept up, Heroic Strike "
            .. "with spare rage.",
        profile = table.concat({
            "actions.precombat=battle_shout,if=!buff.battle_shout.up",
            "actions=battle_shout,if=!buff.battle_shout.up",
            "actions+=/rend,if=!debuff.rend.up",
            "actions+=/heroic_strike,if=rage>=30",
        }, "\n"),
        lists = {
            precombat = { entry("battle_shout", "!buff.battle_shout.up") },
            default = {
                entry("battle_shout", "!buff.battle_shout.up"),
                entry("rend", "!debuff.rend.up"),
                entry("heroic_strike", "rage>=30"),
            },
        },
    },
}

local compressed = LibDeflate:CompressDeflate(Serializer:Serialize(PACK), { level = 5 })
print("Hekili:" .. LibDeflate:EncodeForPrint(compressed))
