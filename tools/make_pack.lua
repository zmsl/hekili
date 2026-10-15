-- tools/make_pack.lua: prints a Forever class's priorities in the share format RegisterPack takes ("Hekili:" +
-- LibDeflate print encoding of the AceSerializer'd package), one line per pack in the class's order, built headless
-- with the vendored libraries. Each class's packs are in tools/packs/<class>.lua ({ date, spec, packs = { { name,
-- desc, simc } } }). Run from the repository root, the class defaulting to warrior:
--   lua5.1 tools/make_pack.lua [class]
-- Edit a pack's SimC-style text there, run this, and paste each printed string into its spec:RegisterPack( ... [[ ]] )
-- in Forever/Classes/<Class>.lua (the class's spec fails until they match). Loaded with the argument "lists"
-- (loadfile(...)("lists"[, class])) it returns the class's packs with each pack's parsed lists instead, for the specs.

local first, second = ...
local class = first == "lists" and (second or "warrior") or (first or "warrior")
local def = dofile("tools/packs/" .. class .. ".lua")
local PACKS, DATE = def.packs, def.date

-- One SimC-style line into its list and entry: actions[.list](=|+=/)action[,name=list][,use_off_gcd=1][,if=criteria].
local function parse(simc)
    local lists = {}
    for line in simc:gmatch("[^\n]+") do
        local list, body = line:match("^actions%.?([%w_]*)%+?=/?(.+)$")
        assert(body, "bad line: " .. line)
        list = list == "" and "default" or list
        local action, opts = body:match("^([%w_]+),?(.*)$")
        local e = { action = action, enabled = true }
        local criteria = opts:match("if=(.*)$")
        opts = opts:gsub(",?if=.*$", "")
        for k, v in opts:gmatch("([%w_]+)=([^,]+)") do
            if k == "name" then
                e.list_name = v
            elseif k == "use_off_gcd" then
                e.use_off_gcd = tonumber(v)
            end
        end
        e.criteria = criteria
        lists[list] = lists[list] or {}
        table.insert(lists[list], e)
    end
    return lists
end

for _, p in ipairs(PACKS) do
    p.lists = parse(p.simc)
end

if first == "lists" then
    return PACKS
end

_G.strbyte, _G.strchar, _G.strsub, _G.strfind, _G.format = string.byte, string.char, string.sub, string.find, string.format
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")
dofile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
local LibDeflate, Serializer = LibStub("LibDeflate"), LibStub("AceSerializer-3.0")

for _, p in ipairs(PACKS) do
    local pack = {
        type = "package",
        name = p.name,
        date = DATE,
        payload = {
            spec = def.spec,
            builtIn = false,
            hidden = false,
            date = DATE,
            version = DATE,
            author = "Hekili (Forever)",
            desc = p.desc,
            profile = p.simc,
            lists = p.lists,
        },
    }
    print("Hekili:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(Serializer:Serialize(pack), { level = 5 })))
end
