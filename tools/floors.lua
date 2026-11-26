-- tools/floors.lua (refactor lane 4, L1827): the gate floors' tooling, read-only. From the repository root:
--   .lua/bin/lua tools/floors.lua untraced              every floor field whose cause is "untraced" (the HAR-1 queue)
--   .lua/bin/lua tools/floors.lua moved BASE.log HEAD.log
--       the gate rows (arm, label) whose summary line moved between two `make gate` / gate-body logs, with the spec
--       file that prints each: the input of tools/first_divergence.sh. loOver is not in the summary line (use the
--       .ab power rows or the trace tools).
--   .lua/bin/lua tools/floors.lua diverge A.tsv B.tsv [clock]
--       per fight, the first in-combat tick where two tools/floors_trace.lua dumps differ, and what differs first:
--       the icon (ours / the oracle's / the press), the belief (power lo / est / hi) or the world (true power);
--       `clock` compares a chained run with seeds alone on fresh boots (tools/fight_clock.sh).
local M = {}

local PACK_GATE = "tests/Forever/helpers/pack_gate.lua"

--- pack_gate.lua's tables, its requires stubbed (only its data is read).
function M.load(path)
    local stub = setmetatable({}, {
        __index = function()
            return function() end
        end,
    })
    local f = assert(loadfile(path or PACK_GATE))
    setfenv(
        f,
        setmetatable({
            require = function()
                return stub
            end,
        }, { __index = _G })
    )
    return f()
end

--- "table\tlabel\tfield\tvalue" for every untraced floor field, sorted.
function M.untraced(G)
    local out, tables = {}, { FLICKER = G.FLICKER }
    for arm, rows in pairs(G.ARM_FLOORS) do
        tables[arm] = rows
    end
    for name, rows in pairs(tables) do
        for label, row in pairs(rows) do
            for k, c in pairs(row.cause or {}) do
                if c == "untraced" then
                    out[#out + 1] = ("%s\t%s\t%s\t%s"):format(name, label, k, tostring(row[k]))
                end
            end
        end
    end
    table.sort(out)
    return out
end

local METRICS = {
    { "agreement", "agreement ([%d.]+)" },
    { "readyShort", "ready while short (%d+)" },
    { "heldReady", "held while ready (%d+)" },
    { "flicker", "; flicker ([%d.]+)/min" },
    { "retracted", "retracted ([%d.]+)/min" },
}

--- A gate log's summary rows: { [arm .. "\t" .. label] = { spec, metric = value } } and their order.
function M.rows(text)
    local rows, order, arm, spec = {}, {}, "default", "?"
    for line in text:gmatch("[^\n]+") do
        arm = line:match("^gate: arm (%S+) from") or arm
        spec = line:match("^== (%S+) %(rc=") or spec
        local label, rest = line:match("^%+?(.-) solo: (fights=.*)$")
        if label then
            -- a tagged line (pack_gate.solo's " [seeds 1-3]", last but for " (reported)") is its own row
            label = label .. (rest:gsub(" %(reported%)$", ""):match(" (%[[^%[%]]*%])$") or "")
            local key, r = arm .. "\t" .. label, { spec = spec }
            for _, m in ipairs(METRICS) do
                r[m[1]] = rest:match(m[2])
            end
            if not rows[key] then
                order[#order + 1] = key
            end
            rows[key] = r
        end
    end
    return rows, order
end

--- "arm\tlabel\tmetric base -> head; ...\tspec" for each row that moved, or is in one log only.
function M.moved(baseText, headText)
    local A = M.rows(baseText)
    local B, order = M.rows(headText)
    local out = {}
    for _, key in ipairs(order) do
        local a, b, d = A[key], B[key], {}
        if not a then
            d[1] = "head only"
        else
            for _, m in ipairs(METRICS) do
                if a[m[1]] ~= b[m[1]] then
                    d[#d + 1] = ("%s %s -> %s"):format(m[1], tostring(a[m[1]]), tostring(b[m[1]]))
                end
            end
        end
        if d[1] then
            out[#out + 1] = key .. "\t" .. table.concat(d, "; ") .. "\t" .. b.spec
        end
    end
    for key, a in pairs(A) do
        if not B[key] then
            out[#out + 1] = key .. "\tbase only\t" .. a.spec
        end
    end
    return out
end

-- a dump's columns (tools/floors_trace.lua): T seed n t ours theirs pressed lo est hi truth
local T_COLS = { "seed", "n", "t", "ours", "theirs", "pressed", "lo", "est", "hi", "truth" }
local WHAT = { ours = "icon", theirs = "icon", pressed = "icon", lo = "belief", est = "belief", hi = "belief" }
WHAT.truth, WHAT.t = "world", "world"

--- A dump: { seeds (in run order), T = { [seed] = { rows } }, F = { [seed] = fight row } }.
function M.dump(text)
    local d = { seeds = {}, T = {}, F = {} }
    for line in text:gmatch("[^\n]+") do
        local f = {}
        for v in (line .. "\t"):gmatch("(.-)\t") do
            f[#f + 1] = v
        end
        if f[1] == "T" then
            local r = {}
            for i, c in ipairs(T_COLS) do
                r[c] = f[i + 1]
            end
            local s = r.seed
            if not d.T[s] then
                d.T[s], d.seeds[#d.seeds + 1] = {}, s
            end
            table.insert(d.T[s], r)
        elseif f[1] == "F" then
            d.F[f[2]] = { base = f[3], ticks = f[4], held = f[5], loOver = f[6], readyShort = f[7], flips = f[8] }
            if not d.T[f[2]] then -- a fight with no combat tick
                d.T[f[2]], d.seeds[#d.seeds + 1] = {}, f[2]
            end
        end
    end
    return d
end

local ICON = { "ours", "theirs", "pressed" }

--- The first differing tick of two fights' rows (over `cols`, default every column): index, the differing columns
--- (by kind), or nil when equal.
function M.first(a, b, cols)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i], b[i]
        if not x or not y then
            return i, { "length" }
        end
        local kinds = {}
        for _, c in ipairs(cols or T_COLS) do
            if x[c] ~= y[c] then
                kinds[#kinds + 1] = (WHAT[c] or c) .. ":" .. c
            end
        end
        if kinds[1] then
            return i, kinds
        end
    end
end

local function row(r)
    return r
            and ("t %s ours %s theirs %s pressed %s lo %s est %s hi %s truth %s"):format(
                r.t,
                r.ours,
                r.theirs,
                r.pressed,
                r.lo,
                r.est,
                r.hi,
                r.truth
            )
        or "(none)"
end

local function fight(f)
    return f
            and ("ticks %s held %s loOver %s readyShort %s flips %s (boot clock %s)"):format(
                f.ticks,
                f.held,
                f.loOver,
                f.readyShort,
                f.flips,
                f.base
            )
        or "(no fight)"
end

--- The report lines for dumps A (base / chained) and B (head / alone); `clock`: B holds seeds alone.
function M.diverge(A, B, clock)
    local out, firstSeed = {}, nil
    local seeds = clock and B.seeds or A.seeds
    for _, s in ipairs(seeds) do
        local a, b = A.T[s] or {}, B.T[s] or {}
        local i, kinds = M.first(a, b)
        local fa, fb = A.F[s], B.F[s]
        if not i then
            out[#out + 1] = ("seed %s: same (%d ticks)%s"):format(
                s,
                #a,
                clock and "; the carry from earlier fights changes nothing here" or ""
            )
        else
            firstSeed = firstSeed or s
            local why = ""
            if clock then
                why = " (alone on a fresh boot: the earlier fights' carry re-times this one)"
            elseif fa and fb and fa.base ~= fb.base then
                why = " (its boot clock moved: an earlier fight re-timed it)"
            end
            out[#out + 1] = ("seed %s: first divergence at tick %d%s, %s"):format(s, i, why, table.concat(kinds, " "))
            local k = M.first(a, b, ICON)
            if k and k ~= i then -- where the icons part, when the belief or the world parted first
                out[#out + 1] = ("  the icons part at tick %d (t %s)"):format(k, (a[k] or b[k]).t)
            end
            if a[i - 1] then
                out[#out + 1] = "  both    " .. row(a[i - 1]) .. "  (the tick before, the same on both)"
            end
            out[#out + 1] = "  " .. (clock and "chained " or "base ") .. row(a[i])
            out[#out + 1] = "  " .. (clock and "alone   " or "head ") .. row(b[i])
        end
        if fa or fb then
            out[#out + 1] = "  " .. (clock and "chained " or "base ") .. fight(fa)
            out[#out + 1] = "  " .. (clock and "alone   " or "head ") .. fight(fb)
        end
    end
    table.insert(
        out,
        1,
        firstSeed and ("first divergence: seed %s"):format(firstSeed)
            or "no divergence: every fight's in-combat ticks are the same"
    )
    return out
end

local function read(path)
    local fh = assert(io.open(path))
    local s = fh:read("*a")
    fh:close()
    return s
end

local function main(cmd, a, b, c)
    local out
    if cmd == "untraced" then
        out = M.untraced(M.load())
    elseif cmd == "moved" and b then
        out = M.moved(read(a), read(b))
    elseif cmd == "diverge" and b then
        out = M.diverge(M.dump(read(a)), M.dump(read(b)), c == "clock")
    else
        io.stderr:write("usage: tools/floors.lua untraced | moved BASE.log HEAD.log | diverge A.tsv B.tsv [clock]\n")
        os.exit(2)
    end
    print(table.concat(out, "\n"))
end

if arg and arg[0] and arg[0]:match("floors%.lua$") then
    main(...)
end
return M
