-- tests/Game/State/latency_spec.lua: the latency table (refactor plan Pr-1, lane 1, L1827; Game/State/Latency.lua).
-- Every row has a lag, a unit, a source and a ledger row; every former copy of a channel's value reads its row (a
-- later measurement changes one row); the rows marked unmeasured are the probe list. Reads names, never numbers.
local load = require("Game.State.helpers.load")

local ROOT = load.ROOT .. "Game/"

local function source(path)
    local f = assert(io.open(ROOT .. path))
    local s = f:read("*a")
    f:close()
    return s
end

-- (L1913 M3) The read form in code: `Lat.lag("<name>")` or `Lat.lag("<name>", <rung>)` outside a comment; a name in a
-- comment, or any other spelling, is no read. Comments go first (a `--` inside a string is not a pattern any site has).
local function reads(src, name)
    local code = src:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
    local q = name:gsub("%p", "%%%0")
    return code:find('Lat%.lag%("' .. q .. '"%s*[,)]') ~= nil
end

describe("the latency table", function()
    local ns, I, Lat

    before_each(function()
        ns = load.module()
        I = ns.VirtualStateInternal
        Lat = I.Lat
    end)

    it("gives every row a lag, a unit, a known source, a ledger row and a purpose", function()
        assert.is_true(#Lat.names > 0)
        for _, name in ipairs(Lat.names) do
            local r = Lat.rows[name]
            local lags = type(r.lag) == "table" and r.lag or { r.lag }
            assert.is_true(#lags > 0, name)
            for _, v in ipairs(lags) do
                assert.are.equal("number", type(v), name)
                assert.is_true(v >= 0, name)
            end
            assert.is_truthy(({ s = true, drains = true })[r.unit], name)
            assert.is_truthy(Lat.SOURCES[r.source], name)
            assert.is_true(type(r.ledger) == "string" and r.ledger ~= "", name)
            assert.is_true(type(r.purpose) == "string" and r.purpose ~= "", name)
        end
    end)

    it("refuses an unknown channel name", function()
        assert.has_error(function() -- its own message (red_first: any raise passed on a tree with no table at all)
            Lat.lag("no.such.channel")
        end, "no.such.channel")
    end)

    it("marks the rows with no measurement unmeasured: the probe list", function()
        local got = {}
        for _, name in ipairs(Lat.names) do
            if Lat.rows[name].source == "unmeasured" then
                got[#got + 1] = name
            end
        end
        table.sort(got)
        assert.are.same({
            "aura.read",
            "band.margin",
            "channel.stop",
            "gcd.edge",
            "own.tick",
            "unit.dup",
            "unit.kill",
            "usable.flip",
            "usable.shows",
        }, got)
    end)

    it("keeps the three one-frame channels three rows (equal by value only, taxonomy 7.3)", function()
        assert.are.equal(Lat.lag("wound.frame"), Lat.lag("aura.read"))
        assert.are.equal(Lat.lag("wound.frame"), Lat.lag("band.margin"))
        local sources = { Lat.rows["wound.frame"].source, Lat.rows["aura.read"].source, Lat.rows["band.margin"].source }
        assert.are.same({ "measured", "unmeasured", "unmeasured" }, sources)
    end)

    it("makes every named copy an expression over its row", function()
        local L, M, U = I.Log, I.Melee, I.Units
        assert.are.equal(Lat.lag("wound.frame"), M.SAME_FRAME)
        assert.are.equal(Lat.lag("aura.read"), I.SAME_FRAME)
        assert.are.equal(Lat.lag("band.margin"), I.BAND_MARGIN)
        assert.are.equal(Lat.lag("usable.shows"), I.GAIN_SHOWS)
        assert.are.equal(Lat.lag("usable.flip"), I.PIN_EXACT)
        assert.are.equal(Lat.lag("wound.taken"), I.TAKEN_ROW_LAG)
        assert.are.equal(Lat.lag("display.cap"), I.CAP_WAIT)
        assert.are.equal(Lat.lag("unit.dup"), U.DUP_WINDOW)
        assert.are.equal(Lat.lag("unit.kill"), U.KILL_TELL)
        for h = 1, 2 do
            assert.are.equal(Lat.lag("swing.land", h), L.PAIR_WINDOW_MS[h] / 1000)
        end
        -- the lift a swing in flight owes lasts the longest (off-hand) landing lag: no second copy
        assert.are.equal(Lat.lag("swing.land", 2), I.LIFT_WINDOW)
        for k = 1, 3 do -- the seeds, before any learning
            assert.are.equal(Lat.lag("swing.lag", k), L.med[k])
            assert.are.equal(Lat.lag("swing.lag.spread", k), L.spr[k])
        end
        -- the learned seeds are copies: learning never moves the row
        assert.are_not.equal(Lat.rows["swing.lag"].lag, L.med)
        assert.are_not.equal(Lat.rows["swing.land"].lag, L.PAIR_WINDOW_MS)
    end)

    -- File-level locals no spec can reach: the former literal is gone and the file reads the row.
    local SITES = {
        { "Events/Rows.lua", "own.row.early", "local EARLY = 0.025" },
        { "Events/Rows.lua", "combat.first", "t - T.at[i] <= 0.01 then" },
        { "State/Sources/Auras.lua", "cdm.light", "local LAT = 0.35" },
        { "State/Families/Auras.lua", "cdm.lead", "U.openFold[u][j] >= I.folds - 1 and" },
        { "State/Families/Casts.lua", "gcd.edge", "local GCD_EDGE = 0.1" },
        { "State/Families/Swing.lua", "own.tick", "local OWN_TICK = 0.1" },
        { "State/Families/Now.lua", "channel.stop", "local FINISH_TOL = 0.05" },
        { "State/Families/Now.lua", "cp.avoid", "local PT_AVOID = 0.3" },
        { "State/Sources/Outcomes/Meter.lua", "meter.merge", "MERGE, SWING_WIN, WHITE_BACK = 64, 0.003, 0.015" },
        { "State/Sources/Outcomes/Meter.lua", "meter.swing", "MERGE, SWING_WIN, WHITE_BACK = 64, 0.003, 0.015" },
        { "State/Sources/Outcomes/Meter.lua", "meter.taken.far", "TAKEN_NEAR, SPELL_TAKEN, MUTE_AT, AUDIT_FOR = 0.6" },
        { "State/Sources/Outcomes/Meter.lua", "meter.taken.near", "TAKEN_NEAR, SPELL_TAKEN, MUTE_AT, AUDIT_FOR = 0.6" },
        {
            "State/Sources/Outcomes/Meter.lua",
            "meter.spell.taken",
            "TAKEN_NEAR, SPELL_TAKEN, MUTE_AT, AUDIT_FOR = 0.6",
        },
    }
    for _, s in ipairs(SITES) do
        it(("%s reads the row %s, not a literal"):format(s[1], s[2]), function()
            local src = source(s[1])
            assert.is_truthy(Lat.rows[s[2]], s[2])
            assert.is_true(reads(src, s[2]), s[2])
            assert.is_nil(src:find(s[3], 1, true), s[3])
        end)
    end

    it(
        "counts only the read form in code: a name in a comment or another spelling is no read (L1913 M3) #self",
        function()
            assert.is_true(reads('local X = I.Lat.lag("cp.avoid")', "cp.avoid"))
            assert.is_true(reads('local X = Lat.lag("swing.lag", 2)', "swing.lag"))
            assert.is_false(reads('-- local X = Lat.lag("cp.avoid")\nlocal X = 0.3', "cp.avoid"))
            assert.is_false(reads('--[[ Lat.lag("cp.avoid") ]] local X = 0.3', "cp.avoid"))
            assert.is_false(reads('local X = Lat.lag("cp.avoid.x")', "cp.avoid"))
            assert.is_false(reads('local X = "Lat.lag" -- ("cp.avoid")', "cp.avoid"))
        end
    )

    it("leaves every row read somewhere (no orphan row)", function()
        local files = {}
        for _, path in ipairs(load.files()) do
            local f = assert(io.open(path))
            files[#files + 1] = f:read("*a")
            f:close()
        end
        local all = table.concat(files, "\n")
        for _, name in ipairs(Lat.names) do
            assert.is_true(reads(all, name), name)
        end
    end)
end)
