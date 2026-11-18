-- tools/make_pack.lua: builds a Forever class's priorities in the share format RegisterPack takes ("Hekili:" +
-- LibDeflate print encoding of the AceSerializer'd package) headless with the vendored libraries, and keeps the
-- class file's RegisterPack blocks in step with them. Each class pack addon has a manifest
-- src/Hekili_<Class>/APLs/packs.lua ({ class, packs = { "<Pack>", ... } in block order,
-- specs = { [<Pack>] = <spec key> } }) and one <Pack>.simc per pack beside it (dev-only: no TOC lists them): its
-- leading `#` lines are the description, other `#` lines and blank lines are dropped, the rest is SimC-style text.
-- The manifest's optional `imports = { [<Pack>] = { from = <Pack>, as = <prefix>, aura = <key> } }` merges another
-- pack's lists in at every build (see import), so a re-generated source pack updates both.
-- A pack's version has one source, its class file's block.
-- Run from the repository root (the class defaults to warrior):
--   lua5.1 tools/make_pack.lua [class]          prints "<version> <string>" per pack, in order
--   lua5.1 tools/make_pack.lua write [class]    rewrites the class file's RegisterPack blocks (`make packs` runs it)
--   lua5.1 tools/make_pack.lua decode <string>  prints a share string's description and lists as SimC
-- Loaded with loadfile(...)("lists"[, class]) it returns the class's pack records ({ name, desc, simc, lists,
-- version, spec }); with ("lib") the functions { parse, unparse, encode, decode, sync, load, write }, for the specs.
-- The version is date * 1000 + a same-day sequence: `write` keeps a pack's version while its block is unchanged, and
-- when it changed sets it to today * 1000 (PACK_DATE, else os.date) on a later day than the old version's, else the old
-- version + 1, so a version only ever rises (Engine/Schema/Spec/Packs.lua RestoreDefaults reloads on `~=` and reports
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
    cycle_targets = "cycle_targets", -- the target-swap modifiers (Recommend Target Swaps): numbers
    max_cycle_targets = "max_cycle_targets",
    other_target = "other_target",
    focus = "focus",
    label = "label",
    label_if = "label_if",
    icon = "icon",
    icon_if = "icon_if",
    value = "value", -- a `variable` line's (CN25: name= is then its var_name)
    pure = "pure", -- a `variable` line read in place (CN25, Scripts.lua MarkPure): 1
    mode = "mode", -- a `sequence` line's (windows design v6 §3.3): skip, wait or continue
    start_on_first = "start_on_first", -- a `strict_sequence` line's flags: 1
    hold_off_gcd = "hold_off_gcd",
} -- plus if=, which runs to the end of the line (a sequence line: to its first member)
-- kept as the line wrote them: text shown with the pick (label, icon) and its condition (label_if, icon_if)
local VERBATIM = {
    name = true,
    buff_name = true,
    label = true,
    label_if = true,
    icon = true,
    icon_if = true,
    value = true,
    mode = true,
}
-- name= by action, as Options.lua ParseActionList's nameMap (any other action's is its list_name)
local NAMES = {
    variable = "var_name",
    sequence = "window_name",
    strict_sequence = "window_name",
    restart_sequence = "window_name",
    open_window = "window_name",
    close_window = "window_name",
}
-- a line whose members follow its options, one per `:` outside parentheses (Options.lua splitSequence)
local SEQ = { sequence = true, strict_sequence = true }

-- a literal | as the in-game importer stores it: || (a lone | starts a WoW colour escape in the editor); the engine
-- reads either form (Scripts.lua)
local function piped(s)
    return (s:gsub("(|)([^|])", "%1|%2"):gsub("|||", "||"))
end

-- SimC-style lines into their lists and entries:
-- actions[.list](=|+=/)action[,name=list][,buff_name=aura][,use_off_gcd=N][,cycle_targets=N][,max_cycle_targets=N]
-- [,other_target=N][,focus=N][,label=text][,label_if=cond][,icon=texture file id or path][,icon_if=cond][,if=criteria];
-- variable,name=var[,pure=1],value=expression (CN25: a translated wowsims variable; pure=1: read in place);
-- focus is a tier, 1 highest; buff_name is cancel_buff's aura.
-- (strict_)sequence,name=window[,mode=m][,start_on_first=1][,hold_off_gcd=1][,if=criteria]:member[:member...], each
-- member an entry of its own (its `steps`, as Options.lua ParseActionList builds them); a window line's name= is its
-- window_name.

-- a sequence line's parts: its own options, then one per member (Options.lua splitSequence's rule)
local function split(body)
    local out, from, depth = {}, 1, 0
    for pos, c in body:gmatch("()([():])") do
        if c == "(" then
            depth = depth + 1
        elseif c == ")" then
            depth = depth - 1
        elseif depth == 0 then
            out[#out + 1] = body:sub(from, pos - 1)
            from = pos + 1
        end
    end
    out[#out + 1] = body:sub(from)
    return out
end

-- one entry's text (a line's body, or one sequence member) into its table; `line` names it in an error. `enabled`: a
-- line's true, a member's nil (as the engine's parser leaves it); set in the constructor, as ever, so a line's table,
-- and so its serialised bytes in the class file, stay as they were
local function entry(body, line, enabled)
    local action, opts = body:match("^([%w_]+),?(.*)$")
    local e = { action = action, enabled = enabled }
    opts = "," .. opts -- if= only as a whole option, never the tail of label_if= or icon_if=
    e.criteria = opts:match(",if=(.*)$")
    if e.criteria then
        e.criteria = piped(e.criteria)
    end
    opts = opts:gsub(",if=.*$", "")
    for opt in opts:gmatch("[^,]+") do
        local k, v = opt:match("^([%w_]+)=(.+)$")
        if not OPTIONS[k] then
            error("unknown option " .. (k or opt) .. " in: " .. line, 0)
        end
        local value = VERBATIM[k] and v or tonumber(v)
        if k == "focus" and not v:match("^[1-9]%d*$") then
            value = nil -- a focus tier is a positive integer, 1 highest
        end
        if value == nil then
            error("bad value " .. opt .. " in: " .. line, 0)
        end
        if k == "value" then
            value = piped(value)
        end
        e[(k == "name" and NAMES[action]) or OPTIONS[k]] = value
    end
    return e
end

local function parse(simc)
    local lists = {}
    for line in simc:gmatch("[^\n]+") do
        local list, body = line:match("^actions%.?([%w_]*)%+?=/?(.+)$")
        if not body then
            error("bad line: " .. line, 0)
        end
        list = list == "" and "default" or list
        local parts = SEQ[body:match("^[%w_]+")] and split(body) or { body }
        local e = entry(parts[1], line, true)
        if SEQ[e.action] then
            e.steps = {}
            for k = 2, #parts do
                e.steps[k - 1] = entry(parts[k], line)
            end
        end
        lists[list] = lists[list] or {}
        table.insert(lists[list], e)
    end
    return lists
end

-- entry's inverse: the action, its options in this order, if= last; a sequence line's members after it, each after a :
local function text(e)
    local s = e.action
        .. (e.list_name and ",name=" .. e.list_name or "")
        .. (e.var_name and ",name=" .. e.var_name or "")
        .. (e.window_name and ",name=" .. e.window_name or "")
        .. (e.mode and ",mode=" .. e.mode or "")
        .. (e.start_on_first and ",start_on_first=" .. e.start_on_first or "")
        .. (e.hold_off_gcd and ",hold_off_gcd=" .. e.hold_off_gcd or "")
        .. (e.buff_name and ",buff_name=" .. e.buff_name or "")
        .. (e.use_off_gcd and ",use_off_gcd=" .. e.use_off_gcd or "")
        .. (e.cycle_targets and ",cycle_targets=" .. e.cycle_targets or "")
        .. (e.max_cycle_targets and ",max_cycle_targets=" .. e.max_cycle_targets or "")
        .. (e.other_target and ",other_target=" .. e.other_target or "")
        .. (e.focus and ",focus=" .. e.focus or "")
        .. (e.label and ",label=" .. e.label or "")
        .. (e.label_if and ",label_if=" .. e.label_if or "")
        .. (e.icon and ",icon=" .. e.icon or "")
        .. (e.icon_if and ",icon_if=" .. e.icon_if or "")
        .. (e.pure and ",pure=" .. e.pure or "")
        .. (e.value and ",value=" .. e.value:gsub("||", "|") or "")
        .. (e.criteria and ",if=" .. e.criteria:gsub("||", "|") or "")
    for _, m in ipairs(e.steps or {}) do
        s = s .. ":" .. text(m)
    end
    return s
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
            out[#out + 1] = head .. (i == 1 and "=" or "+=/") .. text(e)
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

local function copy(e)
    local c = {}
    for k, v in pairs(e) do
        c[k] = v
    end
    return c
end

-- A manifest import ({ from = <pack>, as = <prefix>, aura = <key> }): `lists` plus `src`'s lists renamed (default ->
-- as, precombat -> as_precombat, x -> as_x, their calls too); the host's default and precombat start with a call of
-- the renamed one while buff.<aura>.up, and every host entry there gains !buff.<aura>.up, so in that aura only the
-- imported lists run (call_action_list: never a Block, unlike a strict run_action_list in precombat). `clash(list, to)`
-- raises when `to` is a list the host already has.
-- CN25: whether `e` is a pure=1 variable line (pure=0 or none: a stock one, as Scripts.lua MarkPure reads it)
local function isPure(e)
    return e.action == "variable" and tonumber(e.pure) == 1
end

-- CN25: the lists of `lists` where a pure=1 line is read in place (Scripts.lua MarkPure's placement rule): default, and
-- a list every call to which is enabled, unconditional and in a list already so
local function reached(lists)
    local reach, grew = { default = true }, true
    while grew do
        grew = false
        for list in pairs(lists) do
            if not reach[list] then
                local called, ok = false, true
                for from, entries in pairs(lists) do
                    for _, e in ipairs(entries) do
                        if e.list_name == list and e.action:match("^%a+_action_list$") and e.enabled ~= false then
                            called = true
                            ok = ok and reach[from] and (e.criteria or "") == ""
                        end
                    end
                end
                if called and ok then
                    reach[list], grew = true, true
                end
            end
        end
    end
    return reach
end

local function import(lists, src, imp, clash)
    local function rename(list)
        return list == "default" and imp.as or imp.as .. "_" .. list
    end
    local up = "buff." .. imp.aura .. ".up"
    local out, vars, pure, reach = {}, {}, {}, reached(src)
    for name, entries in pairs(lists) do
        out[name] = entries
        for _, e in ipairs(entries) do
            vars[e.var_name or ""] = true
        end
    end
    for name, entries in pairs(src) do
        local to = rename(name)
        if lists[to] then
            clash(name, to)
        end
        out[to] = {}
        for _, e in ipairs(entries) do
            if e.var_name and vars[e.var_name] then -- CN25: one variable per name in a pack
                error(("%s imports variable %s, which the host pack has too"):format(imp.from, e.var_name), 0)
            end
            local c = copy(e)
            if c.list_name and (c.action == "call_action_list" or c.action == "run_action_list") then
                c.list_name = rename(c.list_name)
            end
            -- CN25: a pure=1 line must sit where only unconditional calls reach it (Scripts.lua MarkPure), and the
            -- renamed lists are entered under the aura: one its own pack reads in place joins the host's default (its
            -- readers carry the guard); another keeps its list (the engine reads it as a stock variable, with an error)
            local move = isPure(c) and reach[name]
            if isPure(c) and not move then
                io.stderr:write(
                    ("warning: %s's variable %s (list %s) is not read in place there; it stays in %s\n"):format(
                        imp.from,
                        c.var_name,
                        name,
                        to
                    )
                )
            end
            local into = move and pure or out[to]
            into[#into + 1] = c
        end
        out[to] = out[to][1] and out[to] or nil
    end
    for _, name in ipairs({ "default", "precombat" }) do
        local guarded = {}
        if src[name] then
            guarded[1] = { action = "call_action_list", enabled = true, list_name = rename(name), criteria = up }
        end
        for _, e in ipairs(lists[name] or {}) do
            local c = copy(e)
            -- CN25: a pure=1 variable line stays unguarded (an if= would make it ineligible, Scripts.lua MarkPure): its
            -- readers carry the guard, and a pure read does not depend on where the line sits
            if not isPure(c) then
                c.criteria = (c.criteria or "") ~= "" and "(" .. c.criteria .. ")&!" .. up or "!" .. up
            end
            guarded[#guarded + 1] = c
        end
        for _, c in ipairs(name == "default" and pure or {}) do
            guarded[#guarded + 1] = c
        end
        out[name] = guarded[1] and guarded or nil
    end
    return out
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
    -- the manifest's imports, each from the source pack's own lists (parsed above, never another import's result)
    local own = {}
    for _, p in ipairs(packs) do
        own[p.name] = p.lists
    end
    for _, p in ipairs(packs) do
        local imp = def.imports and def.imports[p.name]
        if imp then
            local src = own[imp.from]
            if not src then
                error(
                    root
                        .. "packs.lua: pack "
                        .. p.name
                        .. " imports "
                        .. imp.from
                        .. ", which the manifest does not list",
                    0
                )
            end
            p.lists = import(p.lists, src, imp, function(list, to)
                error(
                    root
                        .. "packs.lua: pack "
                        .. p.name
                        .. " imports "
                        .. imp.from
                        .. "'s list "
                        .. list
                        .. " as "
                        .. to
                        .. ", a list it already has",
                    0
                )
            end)
            p.simc = unparse(p.lists)
            p.desc = p.desc
                .. " Imports "
                .. imp.from
                .. " as the "
                .. imp.as
                .. " lists, entered while buff."
                .. imp.aura
                .. ".up."
        end
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
