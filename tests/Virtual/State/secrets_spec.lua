-- tests/Virtual/State/secrets_spec.lua (spec §4.5, §11): a static check that every client read in VirtualState's
-- sources goes through Plain, or says on its line (`-- secret:`) why the raw value is safe (tested with
-- issecretvalue, or handed straight to Plain by the caller); that client functions are never aliased or
-- string-indexed; and that a raw value (a `raw...` variable) is never compared before the secrecy check.
-- Ported from Taco Dog Forever, tests/game/secrets_spec.lua.
local fake = require("Virtual.State.helpers.fake_api")

local DIR = "src/Hekili/Virtual/State/Sources/"

local function discover()
    local out = {}
    local p =
        assert(io.popen("find " .. DIR .. " src/Hekili/Virtual/Events/Rows.lua src/Hekili/Virtual/Events/Attackers.lua -name '*.lua' | sort"))
    for path in p:lines() do
        out[#out + 1] = path
    end
    p:close()
    return out
end

-- Client functions whose answers are never secret.
local NEVER_SECRET = { GetTime = true, issecretvalue = true, CreateFrame = true }

-- Every function the fake client offers (top level and in C_* namespaces), minus the never-secret ones.
local function clientReads()
    local api = fake.new()
    local names = {}
    for k, v in pairs(api) do
        if type(v) == "function" and not NEVER_SECRET[k] then
            names[#names + 1] = k
        elseif type(v) == "table" and k:match("^C_") then
            for fk, fv in pairs(v) do
                if type(fv) == "function" then
                    names[#names + 1] = fk
                end
            end
        end
    end
    table.sort(names)
    return names
end

local function code(line)
    local comment = line:match("%-%-(.*)$") or ""
    local bare = line:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"):gsub("%-%-.*$", "")
    return bare, comment
end

local function problems(path, reads)
    local out = {}
    local function flag(n, fmt, ...)
        out[#out + 1] = string.format("%s:%d: " .. fmt, path, n, ...)
    end
    local n = 0
    for line in io.lines(path) do
        n = n + 1
        local bare, comment = code(line)
        local marked = comment:find("secret:", 1, true) ~= nil
        if line:find("%[%s*[\"'][%w_]+[\"']%s*%]%s*%(") then
            flag(n, "string-indexed call")
        end
        for _, name in ipairs(reads) do
            local s, e = bare:find("api%.[%w_.]-%f[%w_]" .. name .. "%f[^%w_]")
            while s do
                local after = bare:sub(e + 1):match("^%s*(.)")
                if after == "(" then
                    if not bare:sub(1, s - 1):find("Plain%(%s*[%w_]+%s*,%s*$") and not marked then
                        flag(n, "%s read without Plain", name)
                    end
                elseif not (after == "," and bare:find("pcall(", 1, true) and marked) then
                    flag(n, "%s aliased (call it where it's read)", name)
                end
                s, e = bare:find("api%.[%w_.]-%f[%w_]" .. name .. "%f[^%w_]", e + 1)
            end
        end
        if not marked and (bare:find("%f[%w_]raw[%w_]*%s*[=~]=") or bare:find("[=~]=%s*raw[%w_]*%f[^%w_]")) then
            flag(n, "raw value compared")
        end
    end
    return out
end

describe("secret values in VirtualState's sources (spec §4.5)", function()
    local reads = clientReads()

    it("knows the client reads from the fake client", function()
        local set = {}
        for _, r in ipairs(reads) do
            set[r] = true
        end
        for _, name in ipairs({ "IsSpellUsable", "UnitPower", "GetAuraDataByIndex", "GetSpellCooldown", "UnitGUID" }) do
            assert.is_true(set[name], name)
        end
    end)

    it("finds every source file", function()
        local files = discover()
        assert.is_true(#files >= 2, tostring(#files))
    end)

    it("every client read in the sources goes through Plain or says why not", function()
        local all = {}
        for _, path in ipairs(discover()) do
            for _, p in ipairs(problems(path, reads)) do
                all[#all + 1] = p
            end
        end
        assert.are.same({}, all)
    end)

    it("catches each kind of misuse (the check checks)", function()
        local tmp = os.tmpname()
        local f = assert(io.open(tmp, "w"))
        f:write("local n = api.UnitGUID('target')\n") -- unguarded
        f:write("local get = api.C_Spell.IsSpellUsable\n") -- aliased
        f:write('local c = api["UnitPower"](1)\n') -- string-indexed
        f:write("if rawExp ~= nil then end\n") -- a raw value compared
        f:write("local ok = Plain(api, api.UnitExists('target'))\n") -- fine
        f:write("local a = api.UnitPower(1) -- secret: Plain next\n") -- fine
        f:close()
        local text = table.concat(problems(tmp, reads), "\n")
        os.remove(tmp)
        assert.is_truthy(text:find(":1: UnitGUID read without Plain", 1, true), text)
        assert.is_truthy(text:find(":2: IsSpellUsable aliased", 1, true), text)
        assert.is_truthy(text:find(":3: string-indexed call", 1, true), text)
        assert.is_truthy(text:find(":4: raw value compared", 1, true), text)
        assert.is_falsy(text:find(":5:", 1, true), text)
        assert.is_falsy(text:find(":6:", 1, true), text)
    end)

    it("Plain asks issecretvalue before touching the value", function()
        local src = io.open(DIR .. "Sources.lua"):read("*a")
        local body = src:match("function S%.Plain%(api, v%)%s*\n(.-)\nend")
        assert.are.equal("if api.issecretvalue(v) then", body:match("^%s*(.-)\n"))
    end)

    it("the fake client's secret refuses what a real one refuses", function()
        local SECRET = fake.SECRET
        for _, op in ipairs({
            function()
                return SECRET < 1
            end,
            function()
                return SECRET + 1
            end,
            function()
                return SECRET .. "x"
            end,
            function()
                return SECRET.field
            end,
            function()
                return #SECRET
            end,
            function()
                return tostring(SECRET)
            end,
        }) do
            assert.has_error(op)
        end
    end)
end)
