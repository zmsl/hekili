-- tools/vslog_fixture.lua: turns a ForeverProbe /vslog dump (the in-game checkpoint's captures, combat harness design
-- §5) into a harness fixture (tests/Virtual/harness/fixtures/): every token row kept, in ms since the first event; our
-- spells as the fake spec's (`STRIKE` the on-next-swing strike, `DOT`, else `OTHER`, by the IDs given), another
-- player's (secret) as `SECRET`. Run from the repository root:
--   lua5.1 tools/vslog_fixture.lua dump.txt "min,max,min,max" STRIKE=<id> DOT=<id> > tests/Virtual/harness/fixtures/x.lua
-- then write the fixture's header comment (what was captured, where it is described). Loaded with the argument "rows"
-- (loadfile(...)("rows", text, ids)) it returns the parsed rows instead, for the specs.

local mode, a2, a3 = ...

-- The dump's rows: { ms, "S", duration, swingType }, { ms, "U", unit, action, flag, amount, school }, { ms, "C", unit,
-- spell }; `ids` maps a spell ID (string) to STRIKE or DOT.
local function parse(text, ids)
    local rows = {}
    for line in text:gmatch("[^\n]+") do
        local p = {}
        for w in line:gmatch("%S+") do
            p[#p + 1] = w
        end
        local ms = tonumber(p[1])
        if ms and p[2] == "PLAYER_SWING" then
            rows[#rows + 1] = { ms, "S", math.floor(tonumber(p[3]) * 10 + 0.5) / 10, tonumber(p[4]) }
        elseif ms and p[2] == "UNIT_COMBAT" then
            local flag, amount, school = "", p[5], p[6]
            if #p >= 7 then
                flag, amount, school = p[5], p[6], p[7]
            end
            rows[#rows + 1] = { ms, "U", p[3], p[4], flag, tonumber(amount), tonumber(school) }
        elseif ms and p[2] == "UNIT_SPELLCA" then
            rows[#rows + 1] = { ms, "C", p[3], p[4] == "S" and "SECRET" or (ids[p[5]] or "OTHER") }
        end
    end
    return rows
end

if mode == "rows" then
    return parse(a2, a3 or {})
end

local ids = {}
for i = 3, select("#", ...) do
    local name, id = select(i, ...):match("^(%u+)=(%d+)$")
    if name then
        ids[id] = name
    end
end
local f = assert(io.open(mode, "r"))
local rows = parse(f:read("*a"), ids)
f:close()
local function cell(r)
    local out = {}
    for i, v in ipairs(r) do
        out[i] = type(v) == "string" and string.format("%q", v) or tostring(v)
    end
    return "{ " .. table.concat(out, ", ") .. " }"
end
print("-- stylua: ignore")
print("return {")
print("    damage = { " .. a2:gsub(",", ", ") .. " },")
print("    rows = {")
local line = "       "
for _, r in ipairs(rows) do
    local c = cell(r)
    if #line + #c + 2 > 118 then
        print(line)
        line = "       "
    end
    line = line .. " " .. c .. ","
end
print(line)
print("    },")
print("}")
