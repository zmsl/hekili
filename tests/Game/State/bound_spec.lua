-- tests/Game/State/bound_spec.lua: the bounded writer and the bound helper (refactor plan Pr-8, lane 11, L1827).
-- I.Bound states the three band rulings once (owner L1672, L1675; lhv-live-band-is-fact): a live band sets the floor
-- and the ceiling; a usable answer is a one-sided bound about now and wins; an exact read, a death or our own spend
-- refines it. The ruling table pins each case; the literal check compares every call with the lines it replaced (base
-- aca0ff977: applyBand's interval, ladder()'s two sides) at and around every edge, exactly; the refine table pins the
-- third ruling where the family carries it (#pin: green on base); the writer's table pins apply's four ops and three
-- orders; the source check holds every write of est0/lo0/hi0 to apply, and the refund's nine clamps to nine named steps.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")

local MAX = 1000

describe("the bound helper (refactor lane 11)", function()
    local I, EPS

    before_each(function()
        I = load.module().VirtualStateInternal
        EPS = I.EPS
    end)

    -- Each case: the range before (e, l, h), the source (band [bLo, bTop], or a usable answer at c: yes or short, with
    -- or without a live band; `edge`: the floor's own regen explains a short answer, L1946), and the range after.
    local function cases()
        return {
            -- (1) a live band sets the floor and the ceiling
            {
                "band: a wider range narrows to the band",
                { 455, 400, 500 },
                "band",
                nil,
                { 450, 460 },
                { 455, 450, 460 },
            },
            { "band: bounds inside it stand", { 455, 453, 458 }, "band", nil, { 450, 460 }, { 455, 453, 458 } },
            {
                "band: one end inside, the other clipped",
                { 440, 430, 455 },
                "band",
                nil,
                { 450, 460 },
                { 450, 450, 455 },
            },
            {
                "band: disjoint above, the band wins both ends",
                { 485, 480, 490 },
                "band",
                nil,
                { 450, 460 },
                { 460, 450, 460 },
            },
            {
                "band: disjoint below, the band wins both ends",
                { 400, 380, 420 },
                "band",
                nil,
                { 450, 460 },
                { 450, 450, 460 },
            },
            { "band: touching its top meets it", { 470, 460, 480 }, "band", nil, { 450, 460 }, { 460, 460, 460 } },
            -- (2) a usable answer is a one-sided bound about now and wins: a yes raises lo and est to c
            { "yes, no band: lo and est up to c", { 30, 20, 60 }, "yes", 40, nil, { 40, 40, 60 } },
            { "yes, no band: a top under c opens to the maximum", { 30, 20, 35 }, "yes", 40, nil, { 40, 40, MAX } },
            {
                "yes, a band: a top under c opens to the band's top",
                { 30, 20, 35 },
                "yes",
                40,
                { 30, 50 },
                { 40, 40, 50 },
            },
            { "yes, c past the band: lo = hi = c", { 30, 20, 35 }, "yes", 60, { 30, 50 }, { 60, 60, 60 } },
            { "yes under the floor: nothing moves", { 30, 20, 60 }, "yes", 10, nil, { 30, 20, 60 } },
            -- a short answer lowers hi and est under c; lo past it yields to the bound, or to the band's low end
            { "short, no band: hi and est under c", { 50, 20, 60 }, "short", 40, nil, { 40 - EPS, 20, 40 - EPS } },
            {
                "short, no band: lo past it to the bound",
                { 50, 45, 60 },
                "short",
                40,
                nil,
                { 40 - EPS, 40 - EPS, 40 - EPS },
            },
            { "short, no band: a bound under 0 is 0", { 0.5, 0.5, 1 }, "short", 0, nil, { -EPS, 0, -EPS } },
            {
                "short, a band: lo to the band's low end",
                { 50, 45, 60 },
                "short",
                40,
                { 30, 50 },
                { 40 - EPS, 30, 40 - EPS },
            },
            {
                "short, a band at the edge (L1946): lo to the bound",
                { 50, 45, 60 },
                "short",
                40,
                { 30, 50 },
                { 40 - EPS, 40 - EPS, 40 - EPS },
                true,
            },
            {
                "short, a band whose low end is over the bound: the bound",
                { 50, 45, 60 },
                "short",
                40,
                { 42, 50 },
                { 40 - EPS, 40 - EPS, 40 - EPS },
            },
        }
    end

    local function run(c)
        local before, ruling, cost, band, edge = c[2], c[3], c[4], c[5], c[7]
        local bLo, bTop = band and band[1] or 0, band and band[2] or 0
        return I.Bound(before[1], before[2], before[3], ruling, cost, band ~= nil, bLo, bTop, edge == true, MAX)
    end

    it("states the three rulings once (the ruling table)", function()
        for _, c in ipairs(cases()) do
            local e, l, h = run(c)
            local want = c[6]
            assert.are.same(want, { e, l, h }, c[1])
        end
    end)

    it("names its ruling: any other value raises, so a nil never means the band", function()
        for _, ruling in ipairs({ "nope", true, false }) do
            assert.error_matches(function()
                I.Bound(30, 20, 60, ruling, 40, false, 0, 0, false, MAX)
            end, "bound: unknown ruling")
        end
        assert.error_matches(function()
            I.Bound(30, 20, 60, nil, 40, false, 0, 0, false, MAX)
        end, "bound: unknown ruling nil")
    end)

    -- Today's lines (base aca0ff977) as functions of the range before and the source.
    local function oldBand(e, l, h, lo, top) -- applyBand
        local floor0, ceil0 = lo, top
        if l <= top and h >= lo then
            floor0, ceil0 = l > lo and l or lo, h < top and h or top
        end
        local est = e < floor0 and floor0 or (e > ceil0 and ceil0 or e)
        return est, floor0, ceil0
    end
    local function oldYes(e, l, h, c, band, bLo, bTop, max) -- ladder(), affordable
        if l < c then
            l = c
        end
        if e < c then
            e = c
        end
        if h < c then
            local v = max
            if band then
                v = bTop
                v = v > c and v or c
            end
            h = v
        end
        return e, l, h
    end
    local function oldShort(e, l, h, c, band, bLo, edge) -- ladder(), short
        local top = c - EPS
        if h > top then
            h = top
        end
        if e > top then
            e = top
        end
        if l > top then
            local v = top < 0 and 0 or top
            if band and bLo < v and not edge then
                v = bLo
            end
            l = v
        end
        return e, l, h
    end

    it("each call is the line it replaced, at and around every edge", function()
        local V =
            { -1, 0, 1e-12, 29.999, 30, 30.0000001, 39.9999999, 40 - EPS, 40, 40.0000001, 50 - EPS, 50, 50.1, MAX }
        local n, bad = 0, {}
        local function check(name, want, ...)
            local a, b, c = ...
            n = n + 1
            if a ~= want[1] or b ~= want[2] or c ~= want[3] then
                bad[#bad + 1] = ("%s: want %s %s %s, got %s %s %s"):format(name, want[1], want[2], want[3], a, b, c)
            end
        end
        for _, l in ipairs(V) do
            for _, h in ipairs(V) do
                for _, e in ipairs(V) do
                    for _, c in ipairs({ 0, 30, 40, 50, 60 }) do
                        for _, band in ipairs({ false, true }) do
                            for _, edge in ipairs({ false, true }) do
                                local bLo, bTop = 30, 50 - EPS
                                check(
                                    "yes",
                                    { oldYes(e, l, h, c, band, bLo, bTop, MAX) },
                                    I.Bound(e, l, h, "yes", c, band, bLo, bTop, edge, MAX)
                                )
                                check(
                                    "short",
                                    { oldShort(e, l, h, c, band, bLo, edge) },
                                    I.Bound(e, l, h, "short", c, band, bLo, bTop, edge, MAX)
                                )
                            end
                        end
                    end
                    for _, b in ipairs({ { 30, 50 - EPS }, { 40, 40 }, { 0, 1e-12 }, { 50, MAX } }) do
                        check(
                            "band",
                            { oldBand(e, l, h, b[1], b[2]) },
                            I.Bound(e, l, h, "band", nil, true, b[1], b[2], false, MAX)
                        )
                    end
                end
            end
        end
        assert.are.same({}, { unpack(bad, 1, 5) })
        assert.is_true(n > 50000)
    end)
end)

describe("the third ruling: an exact read or our own spend refines a band (refactor lane 11)", function()
    local VS, I, R, S, Obs
    local NRG, MANA = 1, 2
    local SHOWS = 1 / 6

    before_each(function()
        local api = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs, R = I.Sources, VS.Obs, I.res
        I.Build({
            school = load.school(),
            fsr = load.constant("FSR"),
            gcdSpell = load.constant("GCD_SPELL"),
            oracleMin = load.constant("ORACLE_MIN"),
            abilities = { { key = "stab", spend = 40 } },
            abilityIds = { { 1001 } },
            abilitySlot = { NRG },
            resources = {
                { key = "energy", type = 3, token = "ENERGY", max = 100, rest = true, regen = 10 },
                { key = "mana", type = 0, token = "MANA", max = 1000, rest = true, regen = 10 },
            },
            reactions = {},
            auras = {},
            auraIds = {},
            talents = {},
            units = { "player", "target" },
        }, 1)
        I.api = api
        I.Fold(10)
        I.Settle(10)
    end)

    local function band(t, r, lo, hi, bt)
        if I.log.n > 0 and I.bandT[r] ~= (bt or t) then
            I.Fold(t - 1e-9)
        end
        I.bandT[r], I.bandShows[r] = bt or t, SHOWS
        S.Direct(Obs.Band, t, r, lo, hi)
    end
    local function is(r, lo, est, hi)
        local got = { R.lo0[r], R.est0[r], R.hi0[r] }
        for i, want in ipairs({ lo, est, hi }) do
            assert.is_true(
                math.abs(got[i] - want) < 1e-6,
                ("want %s %s %s, got %s %s %s"):format(lo, est, hi, unpack(got))
            )
        end
    end

    it("a band at most a point wide is an exact read: lo = est = hi #pin", function()
        band(10, NRG, 42, 43)
        I.Fold(10)
        is(NRG, 42, 42, 42)
    end)

    it("a plain read in the band's drain wins over it #pin", function()
        S.Direct(Obs.Read, 10, MANA, 702, I.ReadOf.Resource)
        band(10, MANA, 450, 460)
        I.Fold(10)
        is(MANA, 702, 702, 702)
    end)

    it("our own spend after the band's stamp holds it: the spend stands #pin", function()
        band(10, NRG, 80, 81)
        I.Fold(10)
        is(NRG, 80, 80, 80)
        I.ResourceShift(NRG, -40, 10.05, Obs.CastSuccess)
        band(10.1, NRG, 80, 81, 10) -- the same stamp, re-asserted: it cannot show the spend yet
        I.Fold(10.1)
        assert.is_true(R.est0[NRG] < 80 - 30, "the spend stands, est " .. R.est0[NRG])
    end)
end)

describe("the bounded writer (refactor lane 11)", function()
    local I, R

    before_each(function()
        I = load.module().VirtualStateInternal
        R = I.res
        R.n, R.max[1], R.rest[1] = 1, 100, 10
    end)

    local function put(e, l, h)
        R.est0[1], R.lo0[1], R.hi0[1] = e, l, h
    end
    local function got()
        return { R.est0[1], R.lo0[1], R.hi0[1] }
    end

    it("ADD clamps each side's change to [0, max]; nil leaves a side", function()
        put(50, 40, 90)
        I.ResourceApply(1, "shift", 20, -50, nil)
        assert.are.same({ 70, 0, 90 }, got())
        I.ResourceApply(1, "shift", 40, 0, 20)
        assert.are.same({ 100, 0, 100 }, got())
    end)

    it("PUT clamps values to [0, max]; SET writes them as given", function()
        put(50, 40, 90)
        I.ResourceApply(1, "pin", 120, -5, 130)
        assert.are.same({ 100, 0, 100 }, got())
        I.ResourceApply(1, "rung", 120, -5, nil)
        assert.are.same({ 120, -5, 100 }, got())
    end)

    it("FALL takes each side above rest down, never below it", function()
        put(30, 12, 5)
        I.ResourceApply(1, "decay", 5, 5, 5)
        assert.are.same({ 25, 10, 5 }, got())
    end)

    it("an order kind keeps lo <= est <= hi its own way", function()
        put(30, 40, 20)
        I.ResourceApply(1, "refund.est_over_lo")
        assert.are.same({ 40, 40, 20 }, got()) -- est up to lo
        I.ResourceApply(1, "refund.hi_over_est")
        assert.are.same({ 40, 40, 40 }, got()) -- hi up to est
        put(30, 40, 20)
        I.ResourceApply(1, "unrefund", 0, 0, 0)
        assert.are.same({ 30, 30, 30 }, got()) -- lo down to est, then hi up to est
        put(30, 20, 25)
        I.ResourceApply(1, "retract", nil, 20, 25)
        assert.are.same({ 30, 20, 30 }, got()) -- hi up to est
        put(10, 20, 25)
        I.ResourceApply(1, "debt", 10)
        assert.are.same({ 20, 20, 25 }, got()) -- est up to lo
    end)

    it("an unknown kind raises", function()
        assert.error_matches(function()
            I.ResourceApply(1, "nope", 1)
        end, "unknown kind nope")
    end)
end)

describe("the writer's source check (refactor lane 11)", function()
    local function lines(path)
        local out = {}
        for l in assert(io.open(path)):lines() do
            out[#out + 1] = l
        end
        return out
    end
    local SLOTS = { "est0", "lo0", "hi0" }
    -- Whether the code from p on ends an assignment's target list: `=` (no `==`), or `,` and a further target first.
    local function assigned(code, p)
        while true do
            p = select(2, code:find("^%s*", p)) + 1
            local ch = code:sub(p, p)
            if ch == "=" then
                return code:sub(p + 1, p + 1) ~= "="
            elseif ch ~= "," then
                return false
            end
            local _, q = code:find("^%s*[%a_][%w_]*", p + 1)
            if not q then
                return false
            end
            p = q + 1
            while true do -- the target's fields, indexes and calls
                local _, m = code:find("^%s*%.%s*[%a_][%w_]*", p)
                if not m then
                    _, m = code:find("^%s*%b[]", p)
                end
                if not m then
                    _, m = code:find("^%s*:%s*[%a_][%w_]*%s*%b()", p)
                end
                if not m then
                    _, m = code:find("^%s*%b()", p)
                end
                if not m then
                    break
                end
                p = m + 1
            end
        end
    end
    -- What in a source (comments cut, lines kept) writes est0/lo0/hi0 or lets the array escape: an indexed slot that is
    -- an assignment's target, even split over lines or after a first statement on its line; the array itself
    -- un-indexed (an alias `local E = R.est0`, a call `f(R.est0)`); a string key (`R["est0"]`); rawset on it.
    -- TargetHealth's own est0/lo0/hi0 are scalars (H, I.th), not slots.
    -- shortcut: an alias of I.res named H or th escapes the alias rule (none exists); upgrade if one ever does.
    local function escapes(src)
        local code = src:gsub("%-%-[^\n]*", "")
        local hits = {}
        local function hit(at, what)
            local _, n = code:sub(1, at):gsub("\n", "")
            hits[#hits + 1] = (n + 1) .. ": " .. what
        end
        for _, name in ipairs(SLOTS) do
            local pat = "%f[%w_]" .. name .. "%f[^%w_]"
            local i = 1
            while true do
                local s, e = code:find(pat, i)
                if not s then
                    break
                end
                i = e + 1
                local _, b = code:find("^%s*%b[]", e + 1)
                if b then
                    if assigned(code, b + 1) then
                        hit(s, "write " .. name)
                    end
                else
                    local base = code:sub(1, s - 1):match("([%w_]+)%s*[%.:]%s*$")
                    if base and base ~= "H" and base ~= "th" then
                        hit(s, "alias " .. name)
                    end
                end
            end
            for at in code:gmatch("()%[%s*[\"']" .. name .. "[\"']%s*%]") do
                hit(at, "string key " .. name)
            end
            for at in code:gmatch("()rawset%s*%([^,%)]-" .. pat) do
                hit(at, "rawset " .. name)
            end
        end
        return hits
    end

    it("the check catches each way out, and passes reads and comparisons", function()
        for _, c in ipairs({
            { "R.est0[r] = v", true },
            { "R.est0[r], R.lo0[r] = e, l", true },
            { "x, R.hi0[r] = 1, 2", true },
            { "R.est0[r],\n    R.lo0[r] = e, l", true }, -- a target list over two lines
            { "R.est0[r]\n    = v", true },
            { "local x = 1; R.lo0[r] = v", true }, -- a second statement on the line
            { "local x = R.max[r] R.hi0[r] = v", true },
            { "local E = R.est0", true }, -- an alias
            { "local E = I.res.lo0", true },
            { "f(R.hi0)", true },
            { 'R["est0"][r] = v', true }, -- a string key
            { "R['lo0'][r] = v", true },
            { "rawset(R.hi0, r, v)", true },
            { 'rawset(R["est0"], r, v)', true },
            { "local e, l, h = R.est0[r], R.lo0[r], R.hi0[r]", false },
            { "local e = R.est0[r]\nx = 1", false },
            { "if R.est0[r] == x or R.lo0[r] <= x or R.hi0[r] >= x or R.est0[r] ~= x then end", false },
            { "f(R.est0[r], y)", false },
            { "H.est0, H.lo0, H.hi0 = 1, 0, 1", false }, -- TargetHealth's scalars
            { "v = I.th.est0", false },
            { "local R = { est0 = {}, lo0 = {}, hi0 = {} }", false }, -- the arrays' constructor
            { "-- R.est0[r] = v", false },
        }) do
            assert.are.equal(c[2], #escapes(c[1]) > 0, c[1])
        end
    end)

    it("every write of est0, lo0 and hi0 in Families/Resources.lua is apply's", function()
        local out, inApply = {}, false
        for _, l in ipairs(lines(load.ROOT .. "Game/State/Families/Resources.lua")) do
            if l:find("^local function apply%(") then
                inApply = true
            elseif inApply and l:find("^end") then
                inApply = false
            end
            out[#out + 1] = inApply and "" or l -- apply's own lines blanked, the rest kept at their line numbers
        end
        assert.are.same({}, escapes(table.concat(out, "\n")))
    end)

    it("no other belief file writes a resource slot's est0, lo0 or hi0 #pin", function()
        local found = {}
        for _, path in ipairs(load.files()) do
            if not path:find("Families/Resources%.lua$") then
                for _, h in ipairs(escapes(table.concat(lines(path), "\n"))) do
                    found[#found + 1] = path .. ":" .. h
                end
            end
        end
        assert.are.same({}, found)
    end)

    it("the refund's nine clamps are nine named steps, in order, each its own kind", function()
        local src = table.concat(lines(load.ROOT .. "Game/State/Families/Resources.lua"), "\n")
        local body = assert(src:match("\nfunction I%.Refund%(.-\nend\n"), "I.Refund")
        local names, kinds = {}, {}
        for k, name, kind in body:gmatch('%-%- step (%d) (%u[%u ]*%u):.-apply%(r, "([^"]+)"') do
            names[#names + 1] = k .. " " .. name
            kinds[#kinds + 1] = kind
            assert.are.equal("refund." .. name:lower():gsub(" ", "_"), kind, "step " .. k .. "'s kind")
            local _, uses = src:gsub('apply%(r, "' .. kind:gsub("%.", "%%.") .. '"', "")
            assert.are.equal(1, uses, kind .. " is step " .. k .. "'s alone")
        end
        assert.are.equal(9, #kinds)
        assert.are.same({
            "1 KEEP LO",
            "2 KEEP EST",
            "3 FLOOR LO",
            "4 FLOOR EST",
            "5 TOP HI",
            "6 TOP EST",
            "7 TOP LO",
            "8 EST OVER LO",
            "9 HI OVER EST",
        }, names)
    end)
end)
