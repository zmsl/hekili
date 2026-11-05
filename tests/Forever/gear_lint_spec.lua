-- tests/Forever/gear_lint_spec.lua (gear-aware spec §3, §10.6): a pack reads only gear it declared, as a number.
-- shortcut: line-level patterns over the pack sources (comments stripped); a split expression needs review.
local function files()
    local out, p = {}, assert(io.popen("find src -path 'src/Hekili_*' -name '*.lua' | sort"))
    for path in p:lines() do
        out[#out + 1] = path
    end
    p:close()
    return out
end
local function source(path)
    local f = assert(io.open(path))
    local s = f:read("*a"):gsub("%-%-[^\n]*", "")
    f:close()
    return s
end

describe("the packs' gear reads", function()
    local declared, all = {}, {}
    for _, path in ipairs(files()) do
        local dir, s = path:match("^src/([^/]+)/"), source(path)
        all[#all + 1] = { path = path, dir = dir, s = s }
        declared[dir] = declared[dir] or {}
        for kind, key in s:gmatch(':Register(%a+)%(%s*"([%w_]+)"') do
            if kind == "Gear" or kind == "SetBonus" then
                declared[dir][key] = true
            end
        end
    end
    local shared = declared.Hekili_Shared or {}
    it("reads only declared keys", function()
        local bad = {}
        for _, f in ipairs(all) do
            for key in f.s:gmatch("set_bonus%.([%w_]+)") do
                local prefix = key:match("^(.+)_%d+pc$")
                local d = declared[f.dir]
                if not (d[key] or shared[key] or (prefix and (d[prefix] or shared[prefix]))) then
                    bad[#bad + 1] = f.path .. ": set_bonus." .. key
                end
            end
        end
        assert.are.same({}, bad)
    end)
    it("never indexes by item ID, tests bare truthiness or iterates", function()
        local bad = {}
        for _, f in ipairs(all) do
            for _, pat in ipairs({
                "set_bonus%[",
                "set_bonus%.[%w_]+%s+and%s",
                "set_bonus%.[%w_]+%s+or%s",
                "set_bonus%.[%w_]+%s+then",
                "not%s+set_bonus",
                "pairs%(%s*set_bonus",
            }) do
                if f.s:find(pat) then
                    bad[#bad + 1] = f.path .. ": " .. pat
                end
            end
        end
        assert.are.same({}, bad)
    end)
    it("registers gear on the kit only", function()
        local bad = {}
        for _, f in ipairs(all) do
            for _, verb in ipairs({ "RegisterGear", "RegisterSetBonus" }) do
                for recv in f.s:gmatch("([%w_%.%[%]]+):" .. verb .. "%(") do
                    if recv ~= "spec" then
                        bad[#bad + 1] = f.path .. ": " .. recv .. ":" .. verb
                    end
                end
            end
        end
        assert.are.same({}, bad)
    end)
    it("catches what it is meant to catch", function() -- the patterns are not vacuous
        for _, s in ipairs({ "set_bonus[272430]", "set_bonus.x and 1", "not set_bonus.x", "pairs(set_bonus)" }) do
            local hit = false
            for _, pat in ipairs({
                "set_bonus%[",
                "set_bonus%.[%w_]+%s+and%s",
                "not%s+set_bonus",
                "pairs%(%s*set_bonus",
            }) do
                hit = hit or s:find(pat) ~= nil
            end
            assert.is_true(hit, s)
        end
    end)
end)
