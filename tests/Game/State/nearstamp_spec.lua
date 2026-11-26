-- tests/Game/State/nearstamp_spec.lua: I.NearStamp, "a known change near a band stamp" (refactor plan Pr-9 step 1, lane 5,
-- L1827). The five band-margin sites of Families/Resources.lua each call it with today's side and slack, so every call
-- is the boolean its hand-written line was: the three-window table pins each site's side (before the stamp, within the
-- margin after it, past it), the literal check compares each call with the line it replaced at and around every edge,
-- and the source check holds each site to its call.
local load = require("Game.State.helpers.load")

describe("NearStamp (refactor lane 5)", function()
    local I, M

    before_each(function()
        I = load.module().VirtualStateInternal
        M = I.BAND_MARGIN
    end)

    -- Today's lines (base origin/r4-floors 7a216450d) as functions of the change's time t and the stamp s.
    local function untilSlack(t, s) -- seen: t - R.bandAt[r] <= margin; closeWindow: e - bt <= I.BAND_MARGIN + 1e-6
        return t - s <= M + 1e-6
    end
    local function notAfter(t, s) -- shownGain: since < 0 or since > I.BAND_MARGIN + 1e-6 (since = t - R.roseT[r])
        local since = t - s
        return since < 0 or since > M + 1e-6
    end
    local function sinceExact(t, s) -- crossing: R.movedT[r] > bt - I.BAND_MARGIN
        return t > s - M
    end
    local function pastExact(t, s) -- rise: bt - R.roseT[r] > I.BAND_MARGIN
        return t - s > M
    end
    -- Each site: its call's side and slack, whether the site reads "not near", and its old line.
    local SITES = {
        { name = "seen", side = "until", exact = false, neg = false, old = untilSlack },
        { name = "shownGain", side = "after", exact = false, neg = true, old = notAfter },
        { name = "crossing", side = "since", exact = true, neg = false, old = sinceExact },
        { name = "closeWindow", side = "until", exact = false, neg = false, old = untilSlack },
        { name = "rise", side = "until", exact = true, neg = true, old = pastExact },
    }

    local function call(site, t, s)
        local near = I.NearStamp(t, s, site.side, site.exact)
        if site.neg then
            return not near
        end
        return near
    end

    -- The three windows (and the edges between them), as offsets from the stamp; M is 0.05 (the band.margin row).
    -- Columns: well before, inside the margin before, at the stamp, inside after, in the 1e-6 slack, past it.
    local COLS = { "before", "near before", "at", "near after", "slack", "after" }
    local function offsets()
        return { -0.2, -M / 2, 0, M / 2, M + 5e-7, M + 0.05 }
    end
    -- Each site's near (the call's own boolean, before any negation) per column: today's sides.
    local TABLE = {
        seen = { true, true, true, true, true, false }, -- until, with slack
        shownGain = { false, false, true, true, true, false }, -- after, with slack
        crossing = { false, true, true, true, true, true }, -- since, exact
        closeWindow = { true, true, true, true, true, false }, -- until, with slack
        rise = { true, true, true, true, false, false }, -- until, exact
    }

    it("pins each site's side in the three-window table", function()
        for _, site in ipairs(SITES) do
            for k, d in ipairs(offsets()) do
                for _, s in ipairs({ 0, 12.345, 3600.5 }) do
                    assert.are.equal(
                        TABLE[site.name][k],
                        I.NearStamp(s + d, s, site.side, site.exact),
                        ("%s, %s, stamp %s"):format(site.name, COLS[k], s)
                    )
                end
            end
        end
    end)

    it("gives each site's call the boolean of the line it replaced, at and around every edge", function()
        local n = 0
        for _, site in ipairs(SITES) do
            for _, s in ipairs({ -1e9, 0, 1 / 3, 7.1, 250.75, 3600.5, 86400.123 }) do
                -- the edges in doubles: each edge, its neighbours one ulp-ish away, and the window's middle
                for _, e in ipairs({ -M, 0, M, M + 1e-6 }) do
                    for _, eps in ipairs({ -1e-9, -1e-12, 0, 1e-12, 1e-9 }) do
                        local t = s + e + eps
                        assert.are.equal(
                            site.old(t, s),
                            call(site, t, s),
                            ("%s t %.17g s %.17g"):format(site.name, t, s)
                        )
                        n = n + 1
                    end
                end
                for i = -40, 40 do
                    local t = s + i * M / 16
                    assert.are.equal(site.old(t, s), call(site, t, s), ("%s t %.17g s %.17g"):format(site.name, t, s))
                end
            end
        end
        assert.is_true(n > 0)
    end)

    it("raises on a side it does not know", function()
        local ok, err = pcall(I.NearStamp, 1, 0, "untill")
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("unknown side untill", 1, true), tostring(err))
    end)

    it("is what the five sites call, each with its side and slack", function()
        local f = assert(io.open(load.ROOT .. "Game/State/Families/Resources.lua"))
        local src = f:read("*a")
        f:close()
        local code = src:gsub("%-%-[^\n]*", "")
        for _, call in ipairs({
            'local near = nearStamp(t, R.bandAt[r], "until")', -- seen
            'not nearStamp(t, R.roseT[r], "after")', -- shownGain
            'nearStamp(R.movedT[r], bt, "since", true)', -- crossing
            '(n > 1 or nearStamp(e, bt, "until"))', -- closeWindow
            'not nearStamp(bt, R.roseT[r], "until", true)', -- rise
        }) do
            assert.is_truthy(code:find(call, 1, true), call)
        end
        -- no hand-written margin test is left but the helper's and seen's sample loop (out of this lane's five)
        local _, uses = code:gsub("I%.BAND_MARGIN", "")
        assert.are.equal(3, uses)
    end)
end)
