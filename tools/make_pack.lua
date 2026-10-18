-- tools/make_pack.lua: builds a Forever class's priorities in the share format RegisterPack takes ("Hekili:" +
-- LibDeflate print encoding of the AceSerializer'd package) headless with the vendored libraries, and keeps the
-- class file's RegisterPack blocks in step with them. Each class has a manifest tools/packs/<class>.lua
-- ({ date, spec, packs = { "<Pack>", ... } } in block order) and one tools/packs/<class>/<Pack>.simc per pack: its
-- leading `#` lines are the description, other `#` lines and blank lines are dropped, the rest is SimC-style text.
-- Run from the repository root (the class defaults to warrior):
--   lua5.1 tools/make_pack.lua [class]          prints "<version> <string>" per pack, in order
--   lua5.1 tools/make_pack.lua write [class]    rewrites the class file's RegisterPack blocks (`make packs` runs it)
--   lua5.1 tools/make_pack.lua decode <string>  prints a share string's description and lists as SimC
-- Loaded with loadfile(...)("lists"[, class]) it returns the class's pack records ({ name, desc, simc, lists,
-- version, spec }); with ("lib") the functions { parse, unparse, encode, decode, sync, load }, for the specs.
-- The version is date * 1000 + a checksum of the pack's SimC text % 1000, so any text change reloads a saved profile
-- (Engine/Schema/Spec.lua RestoreDefaults reloads on `~=`; a lower number on a same-day edit still reloads but reports
-- the pack "reverted" rather than "updated": bump the manifest's date to avoid that).

local CLASS_FILES = "src/Hekili_" -- <Class>/<Class>.lua (the class pack addon) holds the RegisterPack blocks

local OPTIONS = { name = "list_name", use_off_gcd = "use_off_gcd", focus = "focus" } -- plus if=, which runs to the end of the line

-- SimC-style lines into their lists and entries:
-- actions[.list](=|+=/)action[,name=list][,use_off_gcd=N][,focus=N][,if=criteria].
local function parse(simc)
    local lists = {}
    for line in simc:gmatch("[^\n]+") do
        local list, body = line:match("^actions%.?([%w_]*)%+?=/?(.+)$")
        if not body then
            error("bad line: " .. line, 0)
        end
        list = list == "" and "default" or list
        local action, opts = body:match("^([%w_]+),?(.*)$")
        local e = { action = action, enabled = true }
        e.criteria = opts:match("if=(.*)$")
        opts = opts:gsub(",?if=.*$", "")
        for opt in opts:gmatch("[^,]+") do
            local k, v = opt:match("^([%w_]+)=(.+)$")
            if not OPTIONS[k] then
                error("unknown option " .. (k or opt) .. " in: " .. line, 0)
            end
            local value = k == "name" and v or tonumber(v)
            if value == nil then
                error("bad value " .. opt .. " in: " .. line, 0)
            end
            e[OPTIONS[k]] = value
        end
        lists[list] = lists[list] or {}
        table.insert(lists[list], e)
    end
    return lists
end

-- parse's inverse: the default list first, the others sorted by name.
local function unparse(lists)
    local names, out = {}, {}
    for name in pairs(lists) do
        if name ~= "default" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    if lists.default then
        table.insert(names, 1, "default")
    end
    for _, name in ipairs(names) do
        local head = name == "default" and "actions" or "actions." .. name
        for i, e in ipairs(lists[name]) do
            out[#out + 1] = head
                .. (i == 1 and "=" or "+=/")
                .. e.action
                .. (e.list_name and ",name=" .. e.list_name or "")
                .. (e.use_off_gcd and ",use_off_gcd=" .. e.use_off_gcd or "")
                .. (e.focus and ",focus=" .. e.focus or "")
                .. (e.criteria and ",if=" .. e.criteria or "")
        end
    end
    return table.concat(out, "\n") .. "\n"
end

-- A rotating byte checksum of the SimC text, 0-999.
local function checksum(text)
    local h = 0
    for i = 1, #text do
        h = (h * 31 + text:byte(i)) % 1000003
    end
    return h % 1000
end

local function slurp(path)
    local f, err = io.open(path, "rb")
    if not f then
        error(err, 0)
    end
    local s = f:read("*a")
    f:close()
    return s
end

-- The class's pack records, in the manifest's order; a listed pack without a file or a file not listed is refused, and
-- a line parse refuses is reported with its .simc file. `root` (default "tools/packs/") is for the specs.
local function load(class, root)
    root = root or "tools/packs/"
    local def = dofile(root .. class .. ".lua")
    local files = {}
    local pipe = assert(io.popen("ls " .. root .. class .. "/ 2>/dev/null"))
    for file in pipe:lines() do
        files[file] = true
    end
    pipe:close()
    local packs = {}
    for i, name in ipairs(def.packs) do
        local file = name .. ".simc"
        if not files[file] then
            error("pack " .. name .. " has no " .. root .. class .. "/" .. file, 0)
        end
        files[file] = nil
        local desc, simc, head = {}, {}, true
        local path = root .. class .. "/" .. file
        for line in slurp(path):gmatch("([^\n]*)\n?") do
            head = head and line:sub(1, 1) == "#"
            if head then
                desc[#desc + 1] = line:gsub("^#%s?", ""):gsub("%s+$", "")
            elseif line:sub(1, 1) ~= "#" and line:find("%S") then
                simc[#simc + 1] = line
            end
        end
        local p = { name = name, desc = table.concat(desc, " "), simc = table.concat(simc, "\n") .. "\n" }
        local ok, lists = pcall(parse, p.simc)
        if not ok then
            error(path .. ": " .. lists, 0)
        end
        p.lists = lists
        p.version = def.date * 1000 + checksum(p.simc)
        p.spec = def.spec
        packs[i] = p
    end
    local stray = next(files)
    if stray then
        error(root .. class .. "/" .. stray .. " is not in " .. root .. class .. ".lua", 0)
    end
    return packs
end

-- The vendored libraries, loaded into a private environment on first use so requiring this file touches no globals.
local LibDeflate, Serializer
local function libs()
    if not LibDeflate then
        local env = setmetatable({
            strbyte = string.byte,
            strchar = string.char,
            strsub = string.sub,
            strfind = string.find,
            format = string.format,
        }, { __index = _G })
        env._G = env
        for _, lib in ipairs({ "LibStub/LibStub", "LibDeflate/LibDeflate", "AceSerializer-3.0/AceSerializer-3.0" }) do
            setfenv(assert(loadfile("src/Hekili/Libs/" .. lib .. ".lua")), env)()
        end
        LibDeflate, Serializer = env.LibStub("LibDeflate"), env.LibStub("AceSerializer-3.0")
    end
    return LibDeflate, Serializer
end

local function encode(p)
    local deflate, serializer = libs()
    local pack = {
        type = "package",
        name = p.name,
        date = p.version,
        payload = {
            spec = p.spec,
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
    return "Hekili:" .. deflate:EncodeForPrint(deflate:CompressDeflate(serializer:Serialize(pack), { level = 5 }))
end

-- encode's inverse, as Options.lua's StringToTable reads a chat string; returns the package's payload.
local function decode(s)
    local deflate, serializer = libs()
    local decoded = deflate:DecodeForPrint((s:gsub("^Hekili:", "")))
    local decompressed = decoded and deflate:DecompressDeflate(decoded)
    if not decompressed then
        error("unable to decode or decompress the string", 0)
    end
    local ok, pack = serializer:Deserialize(decompressed)
    if not ok or type(pack) ~= "table" or type(pack.payload) ~= "table" then
        error("not a Hekili package: " .. tostring(pack), 0)
    end
    return pack.payload
end

local function block(p)
    return 'spec:RegisterPack(\n    "' .. p.name .. '",\n    ' .. p.version .. ",\n    [[" .. encode(p) .. "]]\n)\n"
end

-- Rewrites src's RegisterPack blocks (one contiguous run of them, in StyLua's layout) as packs, in order. Returns
-- the new source and { { name, "added" | "updated" | "removed" | "unchanged" }, ... }; errors on anything else.
local function sync(src, packs)
    local old, first, last = {}, nil, nil
    local at = src:find("RegisterPack(", 1, true)
    if not at then
        error("no RegisterPack block", 0)
    end
    while at do
        local s, e, name =
            src:find('^spec:RegisterPack%(\n    "([^"\n]+)",\n    %d+,\n    %[%[Hekili:[^%]\n]*%]%]\n%)\n', at - 5)
        if not s then
            local line = select(2, src:sub(1, at):gsub("\n", "")) + 1
            error("line " .. line .. ": a RegisterPack( not in the generated block layout", 0)
        end
        if old[name] then
            error("duplicate RegisterPack " .. name, 0)
        end
        if last and s ~= last + 1 then
            error("non-block content between RegisterPack blocks before " .. name, 0)
        end
        old[name], old[#old + 1] = src:sub(s, e), name
        first, last = first or s, e
        at = src:find("RegisterPack(", e + 1, true)
    end
    local new, report, listed = {}, {}, {}
    for i, p in ipairs(packs) do
        new[i], listed[p.name] = block(p), true
        local status = not old[p.name] and "added" or old[p.name] == new[i] and "unchanged" or "updated"
        report[#report + 1] = { p.name, status }
    end
    for _, name in ipairs(old) do
        if not listed[name] then
            report[#report + 1] = { name, "removed" }
        end
    end
    return src:sub(1, first - 1) .. table.concat(new) .. src:sub(last + 1), report
end

local lib = { parse = parse, unparse = unparse, encode = encode, decode = decode, sync = sync, load = load }

local mode, arg2 = ...
if mode == "lib" then
    return lib
elseif mode == "lists" then
    return load(arg2 or "warrior")
elseif mode == "decode" then
    local payload = decode(assert(arg2, "usage: lua5.1 tools/make_pack.lua decode <string>"))
    for line in (payload.desc or ""):gmatch("[^\n]+") do
        print("# " .. line)
    end
    local text = unparse(payload.lists)
    io.write(text)
    if payload.profile and text ~= unparse(parse(payload.profile)) then
        io.stderr:write("warning: the lists differ from the payload's profile text\n")
    end
elseif mode == "write" then
    local class = arg2 or "warrior"
    local Class = class:sub(1, 1):upper() .. class:sub(2)
    local path = CLASS_FILES .. Class .. "/" .. Class .. ".lua"
    local src = slurp(path)
    local ok, out, report = pcall(function()
        return sync(src, load(class))
    end)
    if not ok then
        io.stderr:write(path .. ": " .. out .. "\n")
        os.exit(1)
    end
    for _, r in ipairs(report) do
        print(class .. " " .. r[1] .. " " .. r[2])
    end
    if out ~= src then
        local f = assert(io.open(path, "wb"))
        f:write(out)
        f:close()
    end
else
    for _, p in ipairs(load(mode or "warrior")) do
        print(p.version .. " " .. encode(p))
    end
end
