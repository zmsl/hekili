-- tools/wowsims/drift.lua (dev-only): how far wowsims/forever has drifted since each spec's pin (export.lua M.pin), as markdown on
-- stdout. Read-only against both wowsims trees. Run from the repository root:
--   WOWSIMS_NEW_TREE=<checkout at the new rev> [WOWSIMS_NEW_CLI=<its wowsimcli>] \
--       .lua/bin/lua tools/wowsims/drift.lua all|<spec>... > drift.md   (all: every recipe in tools/wowsims/specs/)
-- Env: WOWSIMS (the git repo the pin lives in [~/src/wowsims-forever]; only `git show`/`diff`/`log` run there),
-- WOWSIMS_NEW (the rev to compare [upstream/master]; WOWSIMS_NEW_TREE's HEAD must be it), WOWSIMS_NEW_CLI (a CLI built
-- at the new rev, for `siml parse -json`; without it a recipe whose files moved to .siml is reported, not translated).
-- Per spec: the recipe's source files (changed / gone), its talent string decoded on both trees, the pack lines that
-- would change (the pin side is the checked-in request, checked equal to the shipped .simc; the new side is
-- export.lua's request from the new tree, translated with the pin's log, so automatic-action lines are the pin's),
-- the store records (assets/db_inputs/spell_store_inputs.json) of the kit's spell IDs, the class's generated rank
-- ladders and the class's commits. Then once: the store's builds and hotfixes, and the sim/core + sim/common commits.
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path

local M = {}

local function sh(cmd)
    local p = assert(io.popen(cmd))
    local s = p:read("*a")
    p:close()
    return s
end
local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end
local function spit(path, s)
    local f = assert(io.open(path, "wb"))
    f:write(s)
    f:close()
end
local function slurp(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local s = f:read("*a")
    f:close()
    return s
end

--- `path: old -> new` lines for every leaf where tables (or values) `a` and `b` differ, appended to `out` (returned).
--- A key only one side has reads `nil` on the other; a table against a scalar is one line.
function M.changes(a, b, path, out)
    out = out or {}
    path = path or ""
    if type(a) == "table" and type(b) == "table" then
        local keys, seen = {}, {}
        for _, t in ipairs({ a, b }) do
            for k in pairs(t) do
                if not seen[k] then
                    seen[k], keys[#keys + 1] = true, k
                end
            end
        end
        table.sort(keys, function(x, y)
            return tostring(x) < tostring(y)
        end)
        for _, k in ipairs(keys) do
            M.changes(a[k], b[k], path == "" and tostring(k) or path .. "." .. tostring(k), out)
        end
    elseif a ~= b then
        local function show(v)
            return type(v) == "table" and "{...}" or tostring(v)
        end
        out[#out + 1] = path .. ": " .. show(a) .. " -> " .. show(b)
    end
    return out
end

--- The `Name: spelldata.Kind(args)` entries of a spell_data_auto_gen.go text, { [name] = "Kind(args)" }, and its
--- "Not generated" comment lines as `# <text>` keys.
function M.ladders(text)
    local out = {}
    for name, def in (text or ""):gmatch("\n%s*([%w_]+):%s*spelldata%.([%w_]+%b())") do
        out[name] = def
    end
    for line in (text or ""):gmatch("//   ([^\n]+)") do
        out["# " .. line] = true
    end
    return out
end

local REPO = (os.getenv("WOWSIMS") or "~/src/wowsims-forever"):gsub("^~", os.getenv("HOME") or "~")
local function git(args)
    return sh("git -C " .. q(REPO) .. " " .. args .. " 2>/dev/null")
end
local function show(rev, path)
    local s = git("show " .. q(rev .. ":" .. path))
    return s ~= "" and s or nil
end

local function storeOf(rev, json)
    local tmp = os.tmpname()
    os.execute(
        ("git -C %s show %s | zcat > %s"):format(q(REPO), q(rev .. ":assets/db_inputs/spell_store_inputs.json"), tmp)
    )
    local s = slurp(tmp)
    os.remove(tmp)
    return assert(json.decode(s), "store at " .. rev)
end

-- the kit's spell IDs: every ability's id and copy, every aura's, every talent's spell (export.lua's learn() set)
local function kitIds(set, ex)
    local ids, seen = {}, {}
    local function add(id)
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id], ids[#ids + 1] = true, id
        end
    end
    for key, a in pairs(set.abilities) do
        if type(key) == "string" and type(a) == "table" and a.key == key then
            for _, id in ipairs(ex.ids(a)) do
                add(id)
            end
        end
    end
    for _, a in pairs(set.auras) do
        if type(a) == "table" then
            for _, id in ipairs(ex.ids(a)) do
                add(id)
            end
        end
    end
    for _, t in pairs(set.talents or {}) do
        if type(t) == "table" then
            add(t[2])
        end
    end
    table.sort(ids)
    return ids, seen
end

local STORE_TABLES = { "Names", "Subtexts", "Misc", "Levels", "Cooldowns", "Powers", "AuraOptions", "Effects" }

local function textDiff(a, b)
    local fa, fb = os.tmpname(), os.tmpname()
    spit(fa, a)
    spit(fb, b)
    local d = sh(("diff -U0 %s %s | tail -n +3"):format(fa, fb))
    os.remove(fa)
    os.remove(fb)
    return d
end

local function emit(...)
    print(string.format(...))
end

local function fence(s)
    if s == "" then
        return
    end
    print("```")
    io.write(s, s:sub(-1) == "\n" and "" or "\n")
    print("```")
end

-- the new side's request: the recipe's paths read under the new tree; a `.json` path gone there but with a `.siml`
-- sibling (2fe0846044's Paladin move), a `.siml` path and a recipe `siml` build, parsed with the new CLI (export.lua's
-- M.simlParse / M.simlBuild; not M.request's own .siml read, which wants the CLI at the spec's pin)
local function newRequest(ex, r, spec, tree, cli, notes)
    local r2 = {}
    for k, v in pairs(r) do
        r2[k] = v
    end
    local function needCli(path)
        if not cli then
            error(path .. ": needs WOWSIMS_NEW_CLI (siml)", 0)
        end
    end
    local function parse(path)
        needCli(path)
        local out = os.tmpname()
        spit(out, select(2, ex.simlParse(cli, tree .. "/" .. path, "new rev")))
        return out
    end
    local function exists(path)
        local f = io.open(tree .. "/" .. path)
        return f and f:close()
    end
    local function resolve(path)
        if not path then
            return nil
        end
        if exists(path) then
            return path:find("%.siml$") and parse(path) or tree .. "/" .. path
        end
        local siml = path:gsub("%.json$", ".siml")
        if siml ~= path and exists(siml) then
            notes[#notes + 1] = ("%s is gone at the new rev; read %s"):format(path, siml)
            return parse(siml)
        end
        error(path .. " is gone at the new rev", 0)
    end
    r2.apl, r2.gear = resolve(r.apl), resolve(r.gear)
    -- a .siml build or a recipe `siml` build: over its defaults, as M.request reads one
    local whole = r.siml or (r.build and r.build:find("%.siml$") and r.build)
    r2.build = not whole and resolve(r.build) or nil
    if r.player then
        r2.player = {}
        for k, v in pairs(r.player) do
            r2.player[k] = v
        end
        r2.player.gear = resolve(r.player.gear)
    end
    if whole then
        needCli(whole)
        local path = os.tmpname()
        spit(path, select(2, ex.simlBuild(cli, tree, r, "new rev", whole)))
        r2.siml, r2.build = nil, path
    end
    return ex.request(r2, "", spec)
end

M.newRequest = newRequest -- tests/Forever/wowsims_siml_spec.lua

local function translate(apl, set, r, log, player, encounter)
    local text, omitted = apl.translate(player.rotation, apl.context(set, r, log, player, encounter))
    return text, omitted
end

function M.spec(ctx, spec)
    local ex, apl, json = ctx.ex, ctx.apl, ctx.json
    local r = ex.recipe(spec)
    local pin = ex.pin(spec) -- each spec drifts from its own pin (export.lua M.SPEC_PIN)
    local oldStore = ctx.storeAt(pin)
    local cls = r.class:lower()
    emit("\n## %s (%s)\n", spec, r.pack)

    emit("### Sources")
    local paths = {}
    for _, k in ipairs({ "apl", "build", "gear", "siml", "defaults" }) do
        paths[#paths + 1] = r[k]
    end
    paths[#paths + 1] = r.player and r.player.gear
    local dir = (paths[1] or ""):match("^(ui/specs/[^/]+/[^/]+/)")
    for _, p in ipairs(paths) do
        local gone = git("cat-file -t " .. q(ctx.new .. ":" .. p)) == ""
        local n = git(("diff --numstat %s %s -- %s"):format(pin, ctx.new, q(p))):match("^(%d+%s+%d+)")
        emit("- `%s`: %s", p, gone and "GONE at new rev" or n and ("changed +/- " .. n:gsub("%s+", "/")) or "same")
    end
    if dir then
        local log =
            git(("log --no-merges --format='%%h %%ad %%s' --date=short %s..%s -- %s"):format(pin, ctx.new, q(dir)))
        emit("- commits under `%s`:", dir)
        fence(log)
        for _, f in ipairs({ "presets.ts", "spec.ts", "defaults.siml" }) do
            local d = git(("diff -U1 %s %s -- %s | head -80"):format(pin, ctx.new, q(dir .. f)))
            if d ~= "" then -- shortcut: capped at 80 lines; run the git diff by hand for the rest
                emit("- `%s%s` diff:", dir, f)
                fence(d)
            end
        end
    end

    local req = json.decode(slurp(ex.OUT .. spec .. ".json"))
    local player = req.raid.parties[1].players[1]
    emit("\n### Talents (the request's string on both trees)")
    local tree = "ui/sim/talents/trees/" .. r.talentTree .. ".json"
    local function decode(rev)
        local ok, t = pcall(ex.talents, player.talentsString or "", json.decode(show(rev, tree)))
        if not ok then
            return "error: " .. tostring(t)
        end
        local out = {}
        for _, x in ipairs(t) do
            out[#out + 1] = ("%d=%d@%d"):format(x[1], x[2], x[3])
        end
        return table.concat(out, " ")
    end
    local a, b = decode(pin), decode(ctx.new)
    emit("- string `%s`: %s", tostring(player.talentsString), a == b and "decodes the same" or "DECODES DIFFERENTLY")
    if a ~= b then
        fence("pin: " .. a .. "\nnew: " .. b)
    end
    local tdiff = git(("diff --numstat %s %s -- %s"):format(pin, ctx.new, q(tree)))
    emit("- tree `%s`: %s", tree, tdiff == "" and "same" or "changed " .. tdiff:gsub("%s+", " "))

    emit("\n### Pack lines (translator on both revs)")
    local set = require("Forever.helpers.engine").abilitySet(r.class)
    local log = slurp(ex.OUT .. spec .. ".log")
    local ok, old, oldOmit = pcall(translate, apl, set, r, log, player, req.encounter)
    if not ok then
        emit("- pin translation error: %s", tostring(old))
        old = nil
    else
        local Class = r.class:sub(1, 1) .. r.class:sub(2):lower()
        local shipped = slurp(("src/Hekili_%s/APLs/%s.simc"):format(Class, r.pack)) or ""
        local same = shipped:sub(-(#old + 1)) == old .. "\n"
        emit("- pin translation equals the shipped .simc body: %s", same and "yes" or "NO (harness mismatch)")
    end
    -- shipped -> pin: the checked-in request against the recipe's request built from the pin's own files (a stale
    -- export, or a request edit the re-pin made by hand); pin -> new: the drift itself
    -- a .siml recipe path at a spec flipped to the new rev parses with WOWSIMS_NEW_CLI (its pin's CLI)
    local okp, preq = pcall(ex.request, r, ctx.treeAt(pin), spec, pin == ctx.new and ctx.cli or nil)
    local notes = {}
    local ok2, nreq = pcall(newRequest, ex, r, spec, ctx.tree, ctx.cli, notes)
    for _, n in ipairs(notes) do
        emit("- %s", n)
    end
    local function compare(label, pa, pb)
        emit("\n#### %s", label)
        if pa.talentsString ~= pb.talentsString then
            emit("- request talents differ: `%s` -> `%s`", tostring(pa.talentsString), tostring(pb.talentsString))
        end
        -- the encounter is export.lua's M.ENCOUNTER on every side: the checked-in request's
        local oka, ta, oa = pcall(translate, apl, set, r, log, pa, req.encounter)
        local okb, tb, ob = pcall(translate, apl, set, r, log, pb, req.encounter)
        if not (oka and okb) then
            emit("- TRANSLATION ERROR: %s", tostring(oka and tb or ta))
        else
            local d = textDiff(ta, tb)
            emit("- pack lines changed: %s", d == "" and "none" or "yes")
            fence(d)
            local od = textDiff(table.concat(oa, "\n") .. "\n", table.concat(ob, "\n") .. "\n")
            if od ~= "" then
                emit("- omitted entries changed:")
                fence(od)
            end
        end
        local rd = M.changes(pa.rotation, pb.rotation) -- order-free: dkjson writes keys in pairs() order
        emit("- rotation JSON leaves changed: %d", #rd)
        fence(table.concat(rd, "\n", 1, math.min(#rd, 40)) .. (#rd > 40 and ("\n... " .. (#rd - 40) .. " more") or ""))
        local ed = M.changes(pa.equipment, pb.equipment)
        emit(
            "- equipment fields changed: %d%s",
            #ed,
            #ed > 0 and (" (" .. table.concat(ed, "; ", 1, math.min(#ed, 8)) .. ")") or ""
        )
        local cd = M.changes(pa.consumables, pb.consumables)
        emit("- consumables changed: %d%s", #cd, #cd > 0 and (" (" .. table.concat(cd, "; ") .. ")") or "")
        local rest = {}
        for k in pairs(pb) do
            if k ~= "rotation" and k ~= "equipment" and k ~= "consumables" and k ~= "talentsString" then
                for _, c in ipairs(M.changes(pa[k], pb[k], k)) do
                    rest[#rest + 1] = c
                end
            end
        end
        for k in pairs(pa) do
            if pb[k] == nil then
                rest[#rest + 1] = k .. ": {...} -> nil"
            end
        end
        table.sort(rest)
        emit(
            "- other player fields changed: %d%s",
            #rest,
            #rest > 0 and (" (" .. table.concat(rest, "; ", 1, math.min(#rest, 12)) .. ")") or ""
        )
    end
    if not okp then
        emit("- pin request error: %s", tostring(preq))
    elseif old then
        compare(
            "shipped -> pin (the checked-in request vs the recipe at the pin)",
            player,
            preq.raid.parties[1].players[1]
        )
    end
    if not ok2 then
        emit("- new request error: %s", tostring(nreq))
    elseif okp then
        compare("pin -> new (the drift)", preq.raid.parties[1].players[1], nreq.raid.parties[1].players[1])
    end

    emit("\n### Spell data of the kit's IDs (spell_store_inputs.json)")
    local ids = ctx.kit[r.class]
    if not ids then
        ids = { kitIds(set, ex) }
        ctx.kit[r.class] = ids
    end
    local lines = {}
    for _, id in ipairs(ids[1]) do
        local k = tostring(id)
        for _, t in ipairs(STORE_TABLES) do
            local ch = M.changes(oldStore[t][k], ctx.newStore[t][k])
            if #ch > 0 then
                local name = ctx.newStore.Names[k] or oldStore.Names[k] or "?"
                local sub = ctx.newStore.Subtexts[k] or ""
                lines[#lines + 1] = ("%d %s %s [%s] %s"):format(id, name, sub, t, table.concat(ch, "; "))
            end
        end
    end
    emit("- kit IDs: %d, changed records: %d", #ids[1], #lines)
    fence(table.concat(lines, "\n"))

    if not ctx.classDone[cls .. pin] then
        ctx.classDone[cls .. pin] = true
        emit("\n### Class `%s` (once per class)", cls)
        local gen = "sim/" .. cls .. "/spell_data_auto_gen.go"
        local la, lb = M.ladders(show(pin, gen)), M.ladders(show(ctx.new, gen))
        local out = {}
        for _, ch in ipairs(M.changes(la, lb)) do
            local name = ch:match("^([^:]+):")
            local def = tostring(lb[name] or la[name])
            local kit = ""
            for id in def:gmatch("%d+") do
                if ids[2][tonumber(id)] then
                    kit = "  [KIT]"
                end
            end
            out[#out + 1] = ch .. kit
        end
        emit("- generated ladders changed (`%s`):", gen)
        fence(table.concat(out, "\n"))
        -- the records of IDs a ladder gained (a new rank the kit does not hold yet)
        local recs = {}
        for name, def in pairs(lb) do
            local had = {}
            for id in tostring(la[name] or ""):gmatch("%d+") do
                had[id] = true
            end
            for id in tostring(def):gmatch("%d+") do
                if not had[id] and ctx.newStore.Names[id] then
                    for _, t in ipairs({ "Subtexts", "Levels", "Powers", "Cooldowns", "Misc" }) do
                        local v = ctx.newStore[t][id]
                        if v ~= nil then
                            recs[#recs + 1] = ("%s %s [%s] %s"):format(id, ctx.newStore.Names[id], t, json.encode(v))
                        end
                    end
                end
            end
        end
        table.sort(recs)
        emit("- records of IDs new to a ladder:")
        fence(table.concat(recs, "\n"))
        local ra, rb = {}, {}
        for _, id in ipairs(oldStore.SpellDataGroupRoots[cls] or {}) do
            ra[id] = true
        end
        local added, removed = {}, {}
        for _, id in ipairs(ctx.newStore.SpellDataGroupRoots[cls] or {}) do
            rb[id] = true
            if not ra[id] then
                added[#added + 1] = ("%d %s %s"):format(
                    id,
                    ctx.newStore.Names[tostring(id)] or "?",
                    ctx.newStore.Subtexts[tostring(id)] or ""
                )
            end
        end
        for id in pairs(ra) do
            if not rb[id] then
                removed[#removed + 1] = ("%d %s"):format(id, oldStore.Names[tostring(id)] or "?")
            end
        end
        table.sort(added)
        table.sort(removed)
        emit("- store roots added: %s", #added == 0 and "none" or table.concat(added, ", "))
        emit("- store roots removed: %s", #removed == 0 and "none" or table.concat(removed, ", "))
        emit("- `sim/%s` commits:", cls)
        fence(git(("log --no-merges --format='%%h %%ad %%s' --date=short %s..%s -- sim/%s"):format(pin, ctx.new, cls)))
    end
end

function M.main(specs)
    local ex = loadfile("tools/wowsims/export.lua")()
    local json = require("dkjson")
    local newRev = os.getenv("WOWSIMS_NEW") or "upstream/master"
    local tree = assert(os.getenv("WOWSIMS_NEW_TREE"), "set WOWSIMS_NEW_TREE (a checkout at the new rev)")
    local new = git("rev-parse " .. q(newRev)):gsub("%s+$", "")
    local head = sh("git -C " .. q(tree) .. " rev-parse HEAD"):gsub("%s+$", "")
    assert(new ~= "" and head == new, ("WOWSIMS_NEW_TREE is at %s, %s is %s"):format(head, newRev, new))
    if #specs == 0 then
        for f in sh("ls tools/wowsims/specs/*.lua"):gmatch("specs/([%w_]+)%.lua") do
            specs[#specs + 1] = f
        end
    end
    -- the oldest pin any spec is at (export.lua M.SPEC_PIN): the class-neutral section drifts from it
    local base = ex.NEW_PIN
    for _, spec in ipairs(specs) do
        base = ex.pin(spec) == ex.OLD_PIN and ex.OLD_PIN or base
    end
    -- each pin's ui/ files in a scratch directory (git archive: the repo's checkout is never touched), and its store
    local trees, stores = {}, {}
    local function treeAt(pin)
        if not trees[pin] then
            local dir = os.tmpname()
            os.remove(dir)
            assert(
                os.execute(
                    ("mkdir -p %s && git -C %s archive %s ui/specs ui/sim/talents | tar -x -C %s"):format(
                        q(dir),
                        q(REPO),
                        pin,
                        q(dir)
                    )
                ) == 0
            )
            trees[pin] = dir
        end
        return trees[pin]
    end
    local function storeAt(pin)
        stores[pin] = stores[pin] or storeOf(pin, json)
        return stores[pin]
    end
    local ctx = {
        ex = ex,
        apl = require("tools.wowsims.apl"),
        json = json,
        new = new,
        tree = tree,
        cli = os.getenv("WOWSIMS_NEW_CLI"),
        treeAt = treeAt,
        storeAt = storeAt,
        newStore = storeOf(new, json),
        kit = {},
        classDone = {},
    }
    emit(
        "# wowsims drift: pin %s -> %s (%s commits)",
        base:sub(1, 10),
        new:sub(1, 10),
        git(("rev-list --count %s..%s"):format(base, new)):gsub("%s+", "")
    )
    emit("\n## Class-neutral\n")
    emit("- store builds: pin %s, new %s", json.encode(storeAt(base).Builds), json.encode(ctx.newStore.Builds))
    emit("- store hotfixes: pin %s, new %s", json.encode(storeAt(base).Hotfixes), json.encode(ctx.newStore.Hotfixes))
    emit("- `sim/core` + `sim/common` commits:")
    fence(git(("log --no-merges --format='%%h %%ad %%s' --date=short %s..%s -- sim/core sim/common"):format(base, new)))
    for _, spec in ipairs(specs) do
        local ok, err = pcall(M.spec, ctx, spec)
        if not ok then
            emit("- %s: drift error %s", spec, tostring(err))
        end
    end
    for _, dir in pairs(trees) do
        os.execute("rm -rf " .. q(dir))
    end
end

local specs = { ... }
if #specs == 0 then
    return M -- loaded by tests/Forever/wowsims_drift_spec.lua
end
M.main(specs[1] == "all" and {} or specs)
