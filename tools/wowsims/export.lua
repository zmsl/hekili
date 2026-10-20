-- tools/wowsims/export.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 2): the
-- wowsims/forever side of the "(wowsims.com)" packs. Run from the repository root with the toolchain's Lua:
--   .lua/bin/lua tools/wowsims/export.lua export <spec>  the request tests/Forever/wowsims/<spec>.json from the recipe
--       tools/wowsims/specs/<spec>.lua and the wowsims checkout's preset files, wowsimcli run on it, and
--       tests/Forever/wowsims/<spec>.log: the debug log (noise lines dropped) under a header (the pin, the spec, the
--       seed, the duration, the target level, the build's talents). Needs the checkout at M.PIN and its CLI.
--   .lua/bin/lua tools/wowsims/export.lua learn <CLASS>  tests/Forever/wowsims/learn_<class>.lua: the DB2 learn level
--       of every rank of every ability the class kit registers (wowdb)
--   .lua/bin/lua tools/wowsims/export.lua pack <spec>    the spec's pack .simc from its checked-in request (Task 4;
--       CI-safe: no checkout needed)
-- Loaded with loadfile(...)() it returns M. Env: WOWSIMS (the checkout [~/src/wowsims-forever]), WOWSIMS_CLI
-- [$WOWSIMS/wowsimcli-amd64-linux], WOWDB [~/.local/share/wow-db2/bin/wowdb]. Credit: the request shape, the presets,
-- the talent trees and the APLs are wowsims/forever's (MIT, https://github.com/wowsims/forever); no code copied.
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path
local json = require("dkjson")

local M = {}

--- The wowsims/forever commit every checked-in request and log comes from (tests/Forever/wowsims_pin_spec.lua).
M.PIN = "d33930d04030c3f556582f31949f1f22c17da0e4"
M.OUT = "tests/Forever/wowsims/"
M.SEED, M.DURATION, M.TARGET_LEVEL = 101, 180, 63

-- The encounter of every export (the spike's: wowsims's default target, one, 180 s, execute at 20%).
M.ENCOUNTER = {
    duration = M.DURATION,
    executeProportion20 = 0.2,
    executeProportion25 = 0.25,
    executeProportion35 = 0.35,
    executeProportion45 = 0.45,
    executeProportion90 = 0.9,
    targets = {
        {
            level = M.TARGET_LEVEL,
            -- index 15 (1-based) is attack power 320, index 28 armour 3731: wowsims's default target
            stats = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 320, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3731 },
            mobType = "MobTypeMechanical",
            swingSpeed = 2,
            minBaseDamage = 2601,
            parryHaste = true,
            canCrush = true,
            damageSpread = 0.5,
        },
    },
}

-- Log lines no reader uses (about two thirds of a log).
M.NOISE = { "No available actions", "Pausing rotation", "Dynamic stat change", "[DEBUG]" }

local function home(p)
    return (p:gsub("^~", os.getenv("HOME") or "~"))
end
local function env(name, default)
    return home(os.getenv(name) or default)
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
local function spit(path, s)
    local f = assert(io.open(path, "wb"))
    f:write(s)
    f:close()
end
local function decode(s, where)
    local v, _, err = json.decode(s)
    if v == nil then
        error(where .. ": " .. tostring(err), 0)
    end
    return v
end
local function capture(cmd)
    local p = assert(io.popen(cmd))
    local s = p:read("*a")
    p:close()
    return s
end
local function join(root, path)
    return root == "" and path or root .. "/" .. path
end

--- The recipe of spec `spec` (tools/wowsims/specs/<spec>.lua).
function M.recipe(spec)
    return dofile("tools/wowsims/specs/" .. spec .. ".lua")
end

--- The build's talents from a wowsims talent string and the class's tree file (a list of trees, each `talents` in
--- the string's order): { { rank-1 spell ID, rank, tree }, ... } in the string's order.
function M.talents(str, trees)
    local out, t = {}, 0
    for part in (str .. "-"):gmatch("([^-]*)-") do
        t = t + 1
        local list = trees[t] and trees[t].talents or {}
        for i = 1, #part do
            local r = tonumber(part:sub(i, i))
            if r and r > 0 then
                local tal = assert(list[i], ("talent %d of tree %d"):format(i, t))
                out[#out + 1] = { tal.spellId, r, t }
            end
        end
    end
    return out
end

--- The RaidSimRequest of recipe `r`, its files read under the wowsims checkout `root` ("" : paths as given).
function M.request(r, root)
    local p
    if r.build then
        p = decode(slurp(join(root, r.build)), r.build).player
    else
        local pl = r.player
        p = {
            race = pl.race,
            class = pl.class,
            equipment = decode(slurp(join(root, pl.gear)), pl.gear),
            talentsString = pl.talentsString,
            profession1 = pl.profession1,
            profession2 = pl.profession2,
            reactionTimeMs = pl.reactionTimeMs,
            distanceFromTarget = pl.distanceFromTarget,
        }
        p[pl.specKey] = { options = pl.options }
    end
    if r.apl then
        p.rotation = decode(slurp(join(root, r.apl)), r.apl)
    end
    p.name = r.name
    return {
        raid = { parties = { { players = { p } } } },
        encounter = M.ENCOUNTER,
        simOptions = { iterations = 1, randomSeed = tostring(M.SEED), debug = true },
        type = "SimTypeIndividual",
    }
end

--- Exports spec `spec`: its request and log under M.OUT (see the header).
function M.export(spec)
    local r = M.recipe(spec)
    local root = env("WOWSIMS", "~/src/wowsims-forever")
    local head = capture("git -C '" .. root .. "' rev-parse HEAD"):gsub("%s+$", "")
    if head ~= M.PIN then
        error(
            ("wowsims checkout at %s, the pin is %s: check out the pin (or move M.PIN and re-export every spec)"):format(
                head,
                M.PIN
            ),
            0
        )
    end
    local req = M.request(r, root)
    local reqPath = M.OUT .. spec .. ".json"
    spit(reqPath, json.encode(req, { indent = true }) .. "\n")
    local resPath = os.tmpname()
    local cli = env("WOWSIMS_CLI", root .. "/wowsimcli-amd64-linux")
    if os.execute(("'%s' sim --infile '%s' --outfile '%s'"):format(cli, reqPath, resPath)) ~= 0 then
        error("wowsimcli failed on " .. reqPath, 0)
    end
    local res = decode(slurp(resPath), resPath)
    os.remove(resPath)
    if type(res.error) == "table" and next(res.error) then
        error("wowsimcli: " .. json.encode(res.error), 0)
    end
    local trees = decode(slurp(join(root, "ui/sim/talents/trees/" .. r.talentTree .. ".json")), r.talentTree)
    local talents = {}
    for _, t in ipairs(M.talents(req.raid.parties[1].players[1].talentsString, trees)) do
        talents[#talents + 1] = ("%d=%d@%d"):format(t[1], t[2], t[3])
    end
    local out = {
        ("# wowsims %s %s seed %d %d s target %d"):format(M.PIN, spec, M.SEED, M.DURATION, M.TARGET_LEVEL),
        "# talents " .. table.concat(talents, " "),
    }
    for line in res.logs:gmatch("[^\n]+") do
        local noise = false
        for _, n in ipairs(M.NOISE) do
            noise = noise or line:find(n, 1, true) ~= nil
        end
        if not noise then
            out[#out + 1] = line
        end
    end
    spit(M.OUT .. spec .. ".log", table.concat(out, "\n") .. "\n")
    print(("%s: %d log lines, %d talents"):format(spec, #out - 2, #talents))
end

--- Every spell ID of ability `a`: its `id`, then its `copy` (a list or one ID).
function M.ids(a)
    local out = { a.id }
    if type(a.copy) == "table" then
        for _, id in ipairs(a.copy) do
            out[#out + 1] = id
        end
    elseif a.copy then
        out[#out + 1] = a.copy
    end
    return out
end

--- Writes learn_<class>.lua: the DB2 learn level (SpellLevels.BaseLevel) of every positive spell ID of every ability
--- class `token`'s kit registers. IDs the DB2 lacks are left out (the replay content treats them as level 1).
function M.learn(token)
    local kit = assert(require("Forever.helpers.engine").load(token).class.kit, "no kit for " .. token)
    local ids, seen = {}, {}
    for key, a in pairs(kit.abilities) do
        if type(key) == "string" and type(a) == "table" and a.key == key then
            for _, id in ipairs(M.ids(a)) do
                if type(id) == "number" and id > 0 and not seen[id] then
                    seen[id], ids[#ids + 1] = true, id
                end
            end
        end
    end
    table.sort(ids)
    local wowdb = env("WOWDB", "~/.local/share/wow-db2/bin/wowdb")
    local name = token:lower()
    local out = {
        ("-- tests/Forever/wowsims/learn_%s.lua: generated by `make wowsims-learn CLASS=%s` (tools/wowsims/export.lua)"):format(
            name,
            token
        ),
        "-- from the Forever DB2 (SpellLevels.BaseLevel): the level each rank of each ability is learned at.",
        "return {",
    }
    for i = 1, #ids, 150 do
        local chunk = {}
        for j = i, math.min(i + 149, #ids) do
            chunk[#chunk + 1] = ids[j]
        end
        local tsv = capture(
            ("'%s' \"select SpellID, BaseLevel from SpellLevels where SpellID in (%s) order by SpellID\""):format(
                wowdb,
                table.concat(chunk, ",")
            )
        )
        for id, level in tsv:gmatch("\n(%d+)\t(%d+)") do
            if tonumber(level) > 0 then
                out[#out + 1] = ("    [%s] = %s,"):format(id, level)
            end
        end
    end
    out[#out + 1] = "}"
    spit(M.OUT .. "learn_" .. name .. ".lua", table.concat(out, "\n") .. "\n")
end

local mode, arg = ...
if mode == "export" then
    M.export(assert(arg, "usage: export <spec>"))
elseif mode == "learn" then
    M.learn(assert(arg, "usage: learn <CLASS>"))
elseif mode == "pack" then
    require("tools.wowsims.apl").write(assert(arg, "usage: pack <spec>"), M)
else
    return M
end
