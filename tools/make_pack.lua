-- tools/make_pack.lua: builds a Forever class's priorities in the share format RegisterPack takes ("Hekili:" +
-- LibDeflate print encoding of the AceSerializer'd package) headless with the vendored libraries, and keeps the
-- class file's RegisterPack blocks in step with them. Each class pack addon has a manifest
-- src/Hekili_<Class>/APLs/packs.lua ({ class, packs = { "<Pack>", ... } in block order,
-- specs = { [<Pack>] = <spec key> } }) and one <Pack>.simc per pack beside it (dev-only: no TOC lists them): its
-- leading `#` lines are the description, other `#` lines and blank lines are dropped, the rest is SimC-style text.
-- A pack's version has one source, its class file's block.
-- Run from the repository root (the class defaults to warrior):
--   lua5.1 tools/make_pack.lua [class]          prints "<version> <string>" per pack, in order
--   lua5.1 tools/make_pack.lua write [class]    rewrites the class file's RegisterPack blocks (`make packs` runs it)
--   lua5.1 tools/make_pack.lua decode <string>  prints a share string's description and lists as SimC
-- Loaded with loadfile(...)("lists"[, class]) it returns the class's pack records ({ name, desc, simc, lists,
-- version, spec }); with ("lib") the functions { parse, unparse, encode, decode, sync, load, write }, for the specs.
-- The version is date * 1000 + a same-day sequence: `write` keeps a pack's version while its block is unchanged, and
-- when it changed sets it to today * 1000 (PACK_DATE, else os.date) on a later day than the old version's, else the old
-- version + 1, so a version only ever rises (Engine/Schema/Spec.lua RestoreDefaults reloads on `~=` and reports
-- "reverted" only for a lower one) and a rebuild is a no-op.

local function Class(class)
    return class:sub(1, 1):upper() .. class:sub(2)
end

-- src/Hekili_<Class>/<Class>.lua (the class pack addon) holds the RegisterPack blocks; APLs/ beside it, the sources.
local function classFile(class)
    return "src/Hekili_" .. Class(class) .. "/" .. Class(class) .. ".lua"
end
local function aplRoot(class)
    return "src/Hekili_" .. Class(class) .. "/APLs/"
end

local OPTIONS = {
    name = "list_name",
    buff_name = "buff_name",
    use_off_gcd = "use_off_gcd",
    focus = "focus",
} -- plus if=, which runs to the end of the line

-- SimC-style lines into their lists and entries:
-- actions[.list](=|+=/)action[,name=list][,buff_name=aura][,use_off_gcd=N][,focus=N][,if=criteria];
-- focus is a tier, 1 highest; buff_name is cancel_buff's aura.
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
        if e.criteria then
            -- stored as the in-game importer stores it: a literal | is || (a lone | starts a WoW colour escape in the
            -- editor); the engine reads either form (Scripts.lua)
            e.criteria = e.criteria:gsub("(|)([^|])", "%1|%2"):gsub("|||", "||")
        end
        opts = opts:gsub(",?if=.*$", "")
        for opt in opts:gmatch("[^,]+") do
            local k, v = opt:match("^([%w_]+)=(.+)$")
            if not OPTIONS[k] then
                error("unknown option " .. (k or opt) .. " in: " .. line, 0)
            end
            local value = (k == "name" or k == "buff_name") and v or tonumber(v)
            if k == "focus" and not v:match("^[1-9]%d*$") then
                value = nil -- a focus tier is a positive integer, 1 highest
            end
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
                .. (e.buff_name and ",buff_name=" .. e.buff_name or "")
                .. (e.use_off_gcd and ",use_off_gcd=" .. e.use_off_gcd or "")
                .. (e.focus and ",focus=" .. e.focus or "")
                .. (e.criteria and ",if=" .. e.criteria:gsub("||", "|") or "")
        end
    end
    return table.concat(out, "\n") .. "\n"
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

-- The versions a class file's RegisterPack blocks carry, by pack name.
local function versions(src)
    local out = {}
    for name, version in src:gmatch('spec:RegisterPack%(\n    "([^"\n]+)",\n    (%d+),') do
        out[name] = tonumber(version)
    end
    return out
end

-- The next version of a changed pack: today * 1000 on a later day than `old`'s, else old + 1 (the sequence).
local function bump(old, today)
    if math.floor(old / 1000) < today then
        return today * 1000
    end
    if old % 1000 == 999 then
        error("pack version " .. old .. ": more than 999 same-day regenerations", 0)
    end
    return old + 1
end

-- The class's pack records, in the manifest's order, each keeping the version the class file (`from.src`, default the
-- file on disk) gives it; a pack in `from.bump` (a set of names) gets the next one for `from.today`, a new one
-- `from.today` * 1000. A listed pack
-- without a file or a .simc file not listed is refused, and a line parse refuses is reported with its .simc file.
-- `root` (default src/Hekili_<Class>/APLs/) is for the specs.
local function load(class, root, from)
    root = root or aplRoot(class)
    from = from or {}
    local old = versions(from.src or slurp(classFile(class)))
    local def = dofile(root .. "packs.lua")
    local files = {}
    local pipe = assert(io.popen("ls " .. root .. " 2>/dev/null"))
    for file in pipe:lines() do
        if file:match("%.simc$") then
            files[file] = true
        end
    end
    pipe:close()
    local packs = {}
    for i, name in ipairs(def.packs) do
        local file = name .. ".simc"
        if not files[file] then
            error("pack " .. name .. " has no " .. root .. file, 0)
        end
        files[file] = nil
        local desc, simc, head = {}, {}, true
        local path = root .. file
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
        local v = old[name]
        if from.bump and from.bump[name] then
            v = bump(v, from.today)
        end
        p.version = v or (from.today or 0) * 1000
        -- the manifest: { class = "WARRIOR", packs = {...}, specs = { Arms = "arms", ... } }
        if not def.class then
            error(root .. "packs.lua: no class", 0)
        end
        local key = def.specs and def.specs[name]
        if not key then
            error(root .. "packs.lua: pack " .. name .. " has no spec key", 0)
        end
        p.spec = def.class .. ":" .. key
        packs[i] = p
    end
    local stray = next(files)
    if stray then
        error(root .. stray .. " is not in " .. root .. "packs.lua", 0)
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

-- sync with the class file's own versions; a pack that differs then gets its next version (see bump) for `today`
-- (YYYYMMDD), so an unchanged pack keeps its version and a rewrite of an unchanged file is a no-op.
local function write(src, class, today, root)
    local from = { src = src, today = today }
    local out, report = sync(src, load(class, root, from))
    local changed = {}
    for _, r in ipairs(report) do
        if r[2] == "updated" then
            changed[r[1]] = true
        end
    end
    if next(changed) then
        from.bump = changed
        out, report = sync(src, load(class, root, from))
    end
    return out, report
end

local lib = {
    parse = parse,
    unparse = unparse,
    encode = encode,
    decode = decode,
    sync = sync,
    load = load,
    write = write,
}

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
    local path = classFile(class)
    local src = slurp(path)
    local ok, out, report = pcall(write, src, class, tonumber(os.getenv("PACK_DATE") or os.date("%Y%m%d")))
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
