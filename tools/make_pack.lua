-- tools/make_pack.lua: prints a Forever class's priorities in the share format RegisterPack takes ("Hekili:" +
-- LibDeflate print encoding of the AceSerializer'd package), one line per pack in the class's order, built headless
-- with the vendored libraries. Each class's packs are in tools/packs/<class>.lua ({ date, spec, packs = { { name,
-- desc, simc } } }). Run from the repository root, the class defaulting to warrior:
--   lua5.1 tools/make_pack.lua [class]
-- Edit a pack's SimC-style text there, run this, and paste each printed string into its spec:RegisterPack( ... [[ ]] )
-- in src/Hekili/Forever/Classes/<Class>.lua (the class's spec fails until they match). Loaded with the argument "lists"
-- (loadfile(...)("lists"[, class])) it returns the class's packs with each pack's parsed lists and version instead, for
-- the specs. Each printed line is "<version> <string>": the version is date * 1000 + a checksum of the pack's SimC text
-- % 1000, so any text change reloads a saved profile (Engine/Schema/Spec.lua RestoreDefaults reloads on `~=`; a lower number
-- on a same-day edit still reloads but reports the pack "reverted" rather than "updated": bump the date to avoid that).

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

-- A rotating byte checksum of the SimC text, 0-999.
local function checksum(text)
    local h = 0
    for i = 1, #text do
        h = (h * 31 + text:byte(i)) % 1000003
    end
    return h % 1000
end

for _, p in ipairs(PACKS) do
    p.lists = parse(p.simc)
    p.version = DATE * 1000 + checksum(p.simc)
end

if first == "lists" then
    return PACKS
end

_G.strbyte, _G.strchar, _G.strsub, _G.strfind, _G.format =
    string.byte, string.char, string.sub, string.find, string.format
dofile("src/Hekili/Libs/LibStub/LibStub.lua")
dofile("src/Hekili/Libs/LibDeflate/LibDeflate.lua")
dofile("src/Hekili/Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
local LibDeflate, Serializer = LibStub("LibDeflate"), LibStub("AceSerializer-3.0")

for _, p in ipairs(PACKS) do
    local pack = {
        type = "package",
        name = p.name,
        date = p.version,
        payload = {
            spec = def.spec,
            builtIn = false,
            hidden = false,
            date = p.version,
            version = p.version,
            author = "Hekili (Forever)",
            desc = p.desc,
            profile = p.simc,
            lists = p.lists,
        },
    }
    print(
        p.version
            .. " Hekili:"
            .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(Serializer:Serialize(pack), { level = 5 }))
    )
end
