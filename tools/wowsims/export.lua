-- tools/wowsims/export.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 2): the
-- wowsims/forever side of the "(wowsims.com)" packs. Run from the repository root with the toolchain's Lua:
--   .lua/bin/lua tools/wowsims/export.lua export <spec>  the request tests/Forever/wowsims/<spec>.json from the recipe
--       tools/wowsims/specs/<spec>.lua and the wowsims checkout's preset files, wowsimcli run on it, and
--       tests/Forever/wowsims/<spec>.log: the debug log (noise lines dropped) under a header (the pin, the spec, the
--       seed, the duration, the target level, the build's talents). Needs the checkout at the spec's pin (M.pin) and its oracle CLI
--       (`make wowsims-sim-cli`). A recipe with `siml` runs the siml step first.
--   .lua/bin/lua tools/wowsims/export.lua siml <spec>    tests/Forever/wowsims/<spec>.build.json: the recipe's `siml`
--       build (a .siml path in the checkout) as protojson, from the CLI's `siml parse -json`; request() reads it as
--       the recipe's `build`
--   .lua/bin/lua tools/wowsims/export.lua rerun <spec>   the log only: the checked-in request, unchanged, on the
--       oracle CLI (`make wowsims-sim-cli`) of a checkout at the spec's pin
--   .lua/bin/lua tools/wowsims/export.lua learn <CLASS>  tests/Forever/wowsims/learn_<class>.lua: the DB2 learn level
--       of every rank of every ability in the class's ability set: kit, shared content, racials (wowdb)
--   .lua/bin/lua tools/wowsims/export.lua pack <spec>    the spec's pack .simc from its checked-in request (Task 4;
--       CI-safe: no checkout needed)
-- Loaded with loadfile(...)() it returns M. Env: WOWSIMS (the checkout [~/src/wowsims-forever]), WOWSIMS_CLI
-- [$WOWSIMS/wowsimcli-sim-pin], WOWSIMS_OUT (M.OUT [tests/Forever/wowsims/]), WOWDB [~/.local/share/wow-db2/bin/wowdb]. Credit: the request shape, the presets,
-- the talent trees and the APLs are wowsims/forever's (MIT, https://github.com/wowsims/forever); no code copied.
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path
local json = require("dkjson")

local M = {}

--- The two wowsims/forever commits of the per-spec pin (docs/dev/wowsims-packs.md "Moving the pin"): OLD, the 11-02
--- re-pin's, and NEW, upstream/master at the 0.7 re-pin (e5a9cd2a2d, 2026-11-07; moved from 4b0030a44b, CN18). Each
--- has its oracle patch set in tools/wowsims/sim-pin/<first 12 hex>/.
local OLD, NEW = "e2842f0a784d2f329dde0bc682a6b84202a780f2", "e5a9cd2a2dfc9e29e63fd6ec1fc7245ad4b44664"
M.OLD_PIN, M.NEW_PIN = OLD, NEW
--- The commit each spec's recipe, request and log come from (its checkout and oracle CLI;
--- tests/Forever/wowsims_pin_spec.lua). A class lane flips its spec by re-exporting it at NEW and changing its own
--- line to NEW; once every line says NEW, OLD and its patch set go. One spec per line, a blank line between: two
--- lanes flipping neighbours then merge without a conflict.
M.SPEC_PIN = {
    druid_balance = NEW,

    druid_feral = NEW,

    druid_guardian = NEW,

    hunter_beast_mastery = NEW,

    hunter_marksmanship = NEW,

    hunter_survival = NEW,

    mage_arcane = NEW,

    mage_fire = NEW,

    mage_frostfire = NEW,

    paladin_protection = NEW,

    paladin_retribution = NEW,

    priest_shadow = NEW,

    priest_smite = NEW,

    rogue_assassination = NEW,

    rogue_combat = NEW,

    rogue_subtlety = NEW,

    shaman_elemental = NEW,

    shaman_enhancement = NEW,

    warlock_affliction = NEW,

    warlock_demonology = NEW,

    warlock_destruction = NEW,

    warlock_shadow_brand = NEW,

    warlock_sm_ruin = NEW,

    warrior_arms = NEW,

    warrior_fury = NEW,

    warrior_protection = NEW,
}

--- The pin of spec `spec` (raises on a spec with no line in M.SPEC_PIN).
function M.pin(spec)
    return M.SPEC_PIN[spec] or error(tostring(spec) .. ": no pin in M.SPEC_PIN (tools/wowsims/export.lua)", 0)
end
M.OUT = os.getenv("WOWSIMS_OUT") or "tests/Forever/wowsims/"
M.SEED, M.DURATION, M.TARGET_LEVEL = 101, 180, 63

-- The encounter of every export (the spike's: wowsims's default target, one, 180 s, execute at 20%; the pin's sim
-- reads only the 20% and 35% phases).
M.ENCOUNTER = {
    duration = M.DURATION,
    executeProportion20 = 0.2,
    executeProportion35 = 0.35,
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
local function q(s) -- one shell word
    return "'" .. s:gsub("'", "'\\''") .. "'"
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

--- The RaidSimRequest of recipe `r` (spec `spec`), its files read under the wowsims checkout `root` ("" : paths as
--- given). A `siml` recipe's build is M.OUT/<spec>.build.json (the siml step's output, in this repo). A `build`
--- recipe's `gear` (a gear-set JSON path) replaces the build's equipment; a build with none needs it. A tank
--- recipe (`r.tank`) makes the player the raid's tank and `r.healingModel` its incoming healing, as wowsims's UI does
--- for a tank spec (ui/features/settings/model/apply_defaults.ts:108-122: `setHealingModel` from the spec's
--- OtherDefaults, `setTanks([player])`): without a tank the target swings at no one.
--- An `apl`, `gear`, `player.gear` or `build` path ending in `.siml` is read with `siml parse -json` (M.simlParse; a
--- `.siml` build over its `defaults`, M.simlBuild) of `cli` [WOWSIMS_CLI, else <root>/wowsimcli-sim-pin], whose directory
--- must be a checkout at the spec's pin: an older CLI cannot parse a newer pin's siml.
function M.request(r, root, spec, cli)
    local checked -- the CLI, once its checkout is at the spec's pin
    local function pinnedCli(path)
        if checked then
            return checked
        end
        local pin, c = M.pin(spec), cli or env("WOWSIMS_CLI", join(root, "wowsimcli-sim-pin"))
        local head = capture("git -C " .. q(c:match("^(.*)/") or ".") .. " rev-parse HEAD 2>/dev/null"):gsub("%s+$", "")
        if head ~= pin then
            error(
                ("%s is pinned at %s: %s needs the CLI of a checkout at that pin, and %s is at %s"):format(
                    spec,
                    pin,
                    path,
                    c,
                    head == "" and "no commit" or head
                ),
                0
            )
        end
        checked = c
        return c
    end
    local function read(path)
        if path:find("%.siml$") then
            return (M.simlParse(pinnedCli(path), join(root, path), ("%s (pin %s)"):format(spec, M.pin(spec))))
        end
        return decode(slurp(join(root, path)), path)
    end
    local p
    local build = r.siml and M.OUT .. spec .. ".build.json" or r.build
    if build then
        if r.siml then
            p = decode(slurp(build), build).player
        elseif build:find("%.siml$") then
            p = M.simlBuild(pinnedCli(build), root, r, ("%s (pin %s)"):format(spec, M.pin(spec)), build).player
        else
            p = read(build).player
        end
        if r.gear then -- a build file may carry no gear (Warlock's): wowsimcli crashes on a player without equipment
            p.equipment = read(r.gear)
        elseif not p.equipment then
            error(build .. " has no equipment: set the recipe's `gear` (a gear-set JSON path)", 0)
        end
    else
        local pl = r.player
        p = {
            race = pl.race,
            class = pl.class,
            equipment = read(pl.gear),
            talentsString = pl.talentsString,
            profession1 = pl.profession1,
            profession2 = pl.profession2,
            reactionTimeMs = pl.reactionTimeMs,
            inFrontOfTarget = pl.inFrontOfTarget,
            distanceFromTarget = pl.distanceFromTarget,
        }
        p[pl.specKey] = { options = pl.options }
    end
    if r.apl then
        p.rotation = read(r.apl)
    end
    -- `vars` (name -> const string) sets the APL variables a build's simple rotation writes (upstream's
    -- `simpleRotation`, e.g. ui/specs/rogue/dps/spec.ts:195; ruling R29); every other variable stays as the APL has it;
    -- a name the APL lacks raises (an upstream rename would otherwise play the raw APL again)
    if r.vars then
        local seen = {}
        for _, v in ipairs(p.rotation.valueVariables or {}) do
            if r.vars[v.name] ~= nil then
                v.value = { const = { val = r.vars[v.name] } }
                seen[v.name] = true
            end
        end
        for name in pairs(r.vars) do
            if not seen[name] then
                error(r.name .. ': vars names "' .. name .. '", which the APL lacks')
            end
        end
    end
    -- a greater blessing is a rank state (sim/core/buffs/meta.go rankStates.at): the builds' 1 is rank 1, so send the
    -- top rank, 2 (ruling R25); Kings and the other boolean buffs pass as they are
    for k, v in pairs(p.buffs or {}) do
        if type(v) == "number" and v > 0 and k:find("^greaterBlessingOf") then
            p.buffs[k] = 2
        end
    end
    p.name = r.name
    p.healingModel = r.healingModel
    return {
        raid = { parties = { { players = { p } } }, tanks = r.tank and { { type = "Player", index = 0 } } or nil },
        encounter = M.ENCOUNTER,
        simOptions = { iterations = 1, randomSeed = tostring(M.SEED), debug = true },
        type = "SimTypeIndividual",
    }
end

--- The wowsims checkout (WOWSIMS) and its HEAD, which must be spec `spec`'s pin.
local function checkout(spec)
    local root = env("WOWSIMS", "~/src/wowsims-forever")
    local head = capture("git -C '" .. root .. "' rev-parse HEAD"):gsub("%s+$", "")
    if head ~= M.pin(spec) then
        error(
            ("wowsims checkout at %s, %s is pinned at %s: export it from a checkout at its pin (docs/dev/wowsims-packs.md)"):format(
                head,
                spec,
                M.pin(spec)
            ),
            0
        )
    end
    return root, head
end
M.checkout = checkout -- tools/wowsims/dry.lua

--- Converts spec `spec`'s `siml` build (a .siml path in the checkout at the spec's pin) to M.OUT/<spec>.build.json with the
--- CLI's `siml parse -json` (see the header). A recipe `defaults` (the spec's defaults.siml) fills what the build
--- leaves unset (M.overDefaults).
function M.siml(spec)
    local r = M.recipe(spec)
    local root = checkout(spec)
    assert(r.siml, spec .. ": the recipe has no `siml`")
    local _, s = M.simlBuild(env("WOWSIMS_CLI", root .. "/wowsimcli-sim-pin"), root, r, spec)
    spit(M.OUT .. spec .. ".build.json", s)
end

--- The CLI `cli`'s `siml parse -json` of the .siml file `file`: the decoded table and the CLI's JSON text. A failed
--- parse raises `who` (the caller: a spec and its pin, drift's new rev), the path and the CLI's first error line.
function M.simlParse(cli, file, who)
    local f = io.open(cli, "rb")
    if not f then
        error(
            ("%s: no wowsims CLI at %s to parse %s (make wowsims-sim-cli WOWSIMS=<checkout>)"):format(who, cli, file),
            0
        )
    end
    f:close()
    local out, errs = os.tmpname(), os.tmpname()
    local rc = os.execute(("%s siml parse -json %s > %s 2> %s"):format(q(cli), q(file), q(out), q(errs)))
    local s, e = slurp(out), slurp(errs)
    os.remove(out)
    os.remove(errs)
    if rc ~= 0 then
        error(("%s: `siml parse -json %s` failed (%s): %s"):format(who, file, cli, e:match("[^\n]*")), 0)
    end
    return decode(s, file), s
end

--- Recipe `r`'s whole .siml build (`path` [r.siml] under checkout `root`) over its `defaults` (M.overDefaults), parsed
--- by `cli` (`who` as M.simlParse): the build and its JSON text (the CLI's own when there are no defaults).
function M.simlBuild(cli, root, r, who, path)
    path = path or r.siml
    local t, s = M.simlParse(cli, join(root, path), who)
    local function player(b, from)
        if type(b.player) ~= "table" then
            error(from .. ": `siml parse -json` gave no top-level player", 0)
        end
        return b.player
    end
    player(t, path)
    if r.defaults then
        M.overDefaults(t.player, player(M.simlParse(cli, join(root, r.defaults), who), r.defaults))
        s = json.encode(t, { indent = true }) .. "\n"
    end
    return t, s
end

--- Fills player `p`'s race, professions, consumables and player buffs from the spec defaults' player `d` where the
--- build leaves them unset, as wowsims's siml.LoadBuild layers a build over defaults.siml (sim/siml/build.go:25-30,
--- 54-62). Returns `p`. shortcut: only these five keys (the rest of LoadBuild's rules match what a build sets); widen
--- if a build ever leaves another player key to its defaults.
function M.overDefaults(p, d)
    for _, k in ipairs({ "race", "profession1", "profession2", "consumables", "buffs" }) do
        if p[k] == nil then
            p[k] = d[k]
        end
    end
    return p
end

--- Exports spec `spec`: its request and log under M.OUT (see the header).
function M.export(spec)
    local r = M.recipe(spec)
    local root, head = checkout(spec)
    if r.siml then
        M.siml(spec)
    end
    local req = M.request(r, root, spec)
    local reqPath = M.OUT .. spec .. ".json"
    spit(reqPath, json.encode(req, { indent = true }) .. "\n")
    M.run(spec, root, head)
end

--- Runs the checked-in request of `spec` on the CLI of the wowsims checkout `root` (at commit `head`) and writes its
--- log under M.OUT (see the header).
function M.run(spec, root, head, cli)
    local r = M.recipe(spec)
    local reqPath = M.OUT .. spec .. ".json"
    local req = decode(slurp(reqPath), reqPath)
    local resPath = os.tmpname()
    cli = cli or env("WOWSIMS_CLI", root .. "/wowsimcli-sim-pin")
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
        ("# wowsims %s %s seed %d %d s target %d"):format(head, spec, M.SEED, M.DURATION, M.TARGET_LEVEL),
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

--- Writes learn_<class>.lua: the DB2 learn level (SpellLevels.BaseLevel) of every positive spell ID of every ability in
--- class `token`'s ability set (tests/Forever/helpers/engine.lua abilitySet: the kit's, the shared content's, every
--- race's racials). IDs the DB2 lacks, or learns at 0, are left out (the replay content treats them as level 1).
function M.learn(token)
    local set = require("Forever.helpers.engine").abilitySet(token)
    local ids, seen = {}, {}
    for key, a in pairs(set.abilities) do
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

--- Re-runs the checked-in request of `spec` on the oracle CLI of the wowsims checkout at the spec's pin (the request
--- unchanged): its wowsimcli-sim-pin, `make wowsims-sim-cli`'s build with the oracle patches (tools/wowsims/sim-pin).
function M.rerun(spec)
    local root, head = checkout(spec)
    M.run(spec, root, head, env("WOWSIMS_CLI", root .. "/wowsimcli-sim-pin"))
end

local mode, arg = ...
if mode == "export" then
    M.export(assert(arg, "usage: export <spec>"))
elseif mode == "siml" then
    M.siml(assert(arg, "usage: siml <spec>"))
elseif mode == "rerun" then
    M.rerun(assert(arg, "usage: rerun <spec>"))
elseif mode == "learn" then
    M.learn(assert(arg, "usage: learn <CLASS>"))
elseif mode == "pack" then
    require("tools.wowsims.apl").write(assert(arg, "usage: pack <spec>"), M)
else
    return M
end
