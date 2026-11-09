-- tools/wowsims/dry.lua (re-pin plan, docs/superpowers/plans/2026-11-03-wowsims-repin.md, Task 2): the dry run.
--   .lua/bin/lua tools/wowsims/dry.lua <spec>...
-- prints `<spec> omitted <N> lines <M> [sequence=a wait=b waitUntil=c move=d other=e]` per spec: export.lua's request
-- built from the wowsims checkout (WOWSIMS, at the spec's pin, export.lua M.pin; a `siml` recipe reads its checked-in M.OUT/<spec>.build.json),
-- translated as `export.lua pack` does (with the checked-in log), N its `# Omitted:` entries, M its non-empty .simc
-- lines, the bracket N by the omit reason's node kind (its first word; `resetSequence`, `never`, `hidden` ... are
-- other). A spec whose build or translation raises prints `<spec> error <message>`. Writes nothing.
-- Loaded with no arguments it returns M (M.kinds, for tests/Forever/wowsims_dry_spec.lua).
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path

local M = {}
M.KINDS = { "sequence", "wait", "waitUntil", "move" }

--- The bracket of omitted list `omitted` (translate's: "<list> #<i>: <reason>" or "<list>: empty group <name>").
function M.kinds(omitted)
    local n = { other = 0 }
    for _, k in ipairs(M.KINDS) do
        n[k] = 0
    end
    for _, o in ipairs(omitted) do
        local k = o:match("^[^:]*#%d+: ([%w_]+)")
        k = n[k] and k ~= "other" and k or "other"
        n[k] = n[k] + 1
    end
    local out = {}
    for _, k in ipairs(M.KINDS) do
        out[#out + 1] = k .. "=" .. n[k]
    end
    out[#out + 1] = "other=" .. n.other
    return "[" .. table.concat(out, " ") .. "]"
end

local function dry(ex, apl, root, spec)
    local r = ex.recipe(spec)
    local req = ex.request(r, root, spec)
    local player = req.raid.parties[1].players[1]
    local lf = io.open(ex.OUT .. spec .. ".log", "rb")
    local log = lf and lf:read("*a")
    if lf then
        lf:close()
    end
    local set = require("Forever.helpers.engine").abilitySet(r.class)
    local text, omitted = apl.translate(player.rotation, apl.context(set, r, log, player, req.encounter))
    local lines = 0
    for _ in text:gmatch("[^\n]+") do
        lines = lines + 1
    end
    return ("%s omitted %d lines %d %s"):format(spec, #omitted, lines, M.kinds(omitted))
end

local specs = { ... }
if #specs == 0 then
    return M
end
local ex = loadfile("tools/wowsims/export.lua")()
local apl = require("tools.wowsims.apl")
for _, spec in ipairs(specs) do
    local ok, line = pcall(function() -- each spec from a checkout at its own pin (export.lua M.pin)
        return dry(ex, apl, (ex.checkout(spec)), spec)
    end)
    print(ok and line or ("%s error %s"):format(spec, (tostring(line):gsub("\n", " "))))
end
