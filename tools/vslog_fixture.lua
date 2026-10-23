-- tools/vslog_fixture.lua: turns a ForeverProbe /vslog dump (the in-game checkpoint's captures, combat harness design
-- §5; the 2026-10-22 captures, unit-registry spec §6.3) into a harness fixture (tests/Game/harness/fixtures/): every
-- token row kept, in ms since the first event; our spells as the fake spec's names (by the IDs given: STRIKE, DOT,
-- BOLT, DOTI, HIT; else OTHER), another player's (secret) as `SECRET`; a row that is not raw /vslog raises. Run from
-- the repository root:
--   lua5.1 tools/vslog_fixture.lua dump.txt "min,max,min,max" BOLT=<id> ... > tests/Game/harness/fixtures/x.lua
-- then write the fixture's header comment. Loaded with the argument "rows" (loadfile(...)("rows", text, ids)) it
-- returns the parsed rows instead, for the specs.
-- Rows: { ms, "S", duration, swingType }; { ms, "U", unit, action, flag, amount, school }; { ms, "C", unit, spell }
-- (the old recorder's UNIT_SPELLCAST_SUCCEEDED); { ms, "SC", sub, unit, castGUID, spell, bar, a5 } (SENT's `bar` is
-- the target's name); { ms, "T", guid } ("" none); { ms, "B", token, guid } (a plate or soft token's binding,
-- inferred: the captures record no plate GUID); { ms, "P+" | "P-", token, guid }; { ms, "D", guid } UNIT_DIED;
-- { ms, "K", killer, victim } PARTY_KILL (a player killer is ours: `ME`); { ms, "TD" }; { ms, "E", event }.

local mode, a2, a3 = ...

local EVENTS = {
    PLAYER_ENTER_COMBAT = true,
    PLAYER_LEAVE_COMBAT = true,
    PLAYER_REGEN_DISABLED = true,
    PLAYER_REGEN_ENABLED = true,
}
local SKIP = { NOTE = true, UNIT_TARGET = true, Recorder = true }

local function parse(text, ids)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        local p = {}
        for w in line:gmatch("%S+") do
            p[#p + 1] = w
        end
        p.line = line
        lines[#lines + 1] = p
    end
    local rows, target, corpse, bound, state = {}, "", nil, {}, {}
    local first = tonumber(lines[1] and lines[1][1])
    if first and lines[1][2] ~= "TARGET" then
        target = "Creature-fixture-1" -- a capture with no opening TARGET line
        rows[1] = { first, "T", target }
    end
    local function castFields(p)
        for k = 3, #p do
            if p[k]:match("^Cast%-") then
                return p[k], p[k + 1], p[k + 2], p[k + 3]
            end
        end
    end
    -- whether line n's ms holds a `target` UNIT_COMBAT row with the same payload
    local function withTarget(n)
        local p = lines[n]
        for m = n - 3, n + 3 do
            local q = lines[m]
            if
                q
                and q[1] == p[1]
                and q[2] == "UNIT_COMBAT"
                and q[3] == "target"
                and q[4] == p[4]
                and q[#q] == p[#p]
            then
                return true
            end
        end
        return false
    end
    for n, p in ipairs(lines) do
        local ms, ev = tonumber(p[1]), p[2]
        if not ms or SKIP[ev] then
            -- the dump's summary line, a note, a target-of change
        elseif ev == "PLAYER_SWING" then
            rows[#rows + 1] = { ms, "S", math.floor(tonumber(p[3]) * 10 + 0.5) / 10, tonumber(p[4]) }
        elseif ev == "UNIT_COMBAT" then
            local unit, flag, amount, school = p[3], "", p[5], p[6]
            if #p >= 7 then
                flag, amount, school = p[5], p[6], p[7]
            end
            assert(tonumber(amount) and tonumber(school), "not a raw /vslog row: " .. p.line)
            if unit:match("^nameplate") or unit:match("^soft") then
                local g
                if withTarget(n) then
                    g = target ~= "" and target or corpse
                else
                    g = bound[unit] or corpse or (target ~= "" and target or nil)
                end
                if g and bound[unit] ~= g then
                    bound[unit] = g
                    rows[#rows + 1] = { ms, "B", unit, g }
                end
            end
            rows[#rows + 1] = { ms, "U", unit, p[4], flag, tonumber(amount), tonumber(school) }
        elseif ev == "TARGET" then
            local g = p.line:match("guid=(%S+)") or ""
            if g == "" and target ~= "" then
                corpse = target
            end
            target = g
            rows[#rows + 1] = { ms, "T", g }
        elseif (ev == "UNIT_SPELLCA" or ev:match("^SC_")) and not castFields(p) then
            -- no castGUID: another unit's secret cast, not ours
        elseif ev:match("^SC_") then
            local g, id, a4, a5 = castFields(p)
            local spell = ids[id] or "OTHER"
            if ev == "SC_SENT" then
                rows[#rows + 1] = { ms, "SC", "SENT", p[3], g, spell, p.line:match(p[3] .. " (.-) Cast%-") }
            else
                rows[#rows + 1] = {
                    ms,
                    "SC",
                    ev:sub(4),
                    p[3],
                    g,
                    spell,
                    a4 ~= "nil" and a4 or false,
                    a5 ~= "nil" and a5 or false,
                }
            end
        elseif ev == "UNIT_SPELLCA" then -- the truncated recorder: decoded by payload (captures README)
            local g, id, a4, a5 = castFields(p)
            local key, sub = p[3] .. g, nil
            if a4 == "nil" then
                sub = a5 == "nil" and "FAILED" or "INTERRUPTED"
            elseif not state[key] then
                sub, state[key] = "START", 1
            elseif state[key] == 1 then
                sub, state[key] = "SUCCEEDED", 2
                for m = n + 1, #lines do
                    local q = lines[m]
                    if tonumber(q[1]) and tonumber(q[1]) - ms > 300 then
                        break
                    elseif q[2] == "UNIT_SPELLCA" and q.line:find(g, 1, true) and q[#q - 1] == "nil" then
                        sub = "FAILED"
                    end
                end
            else
                sub, state[key] = "STOP", 3
            end
            rows[#rows + 1] = {
                ms,
                "SC",
                sub,
                p[3],
                g,
                ids[id] or "OTHER",
                a4 ~= "nil" and a4 or false,
                a5 ~= "nil" and a5 or false,
            }
        elseif ev == "PLATE+" or ev == "PLATE-" then
            local g = p.line:match("guid=(%S+)")
            bound[p[3]] = ev == "PLATE+" and g or nil
            rows[#rows + 1] = { ms, ev == "PLATE+" and "P+" or "P-", p[3], g }
        elseif ev == "UNIT_DIED" then
            rows[#rows + 1] = { ms, "D", p[3] }
        elseif ev == "PARTY_KILL" then
            rows[#rows + 1] = { ms, "K", p[3]:match("^Player%-") and "ME" or p[3], p[4] }
        elseif ev == "PLAYER_TARGET_DIED" then
            rows[#rows + 1] = { ms, "TD" }
        elseif EVENTS[ev] then
            rows[#rows + 1] = { ms, "E", ev }
        elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then -- the first recorder's success line
            rows[#rows + 1] = { ms, "C", p[3], p[4] == "S" and "SECRET" or (ids[p[5]] or "OTHER") }
        else
            error("not a raw /vslog row: " .. p.line)
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
