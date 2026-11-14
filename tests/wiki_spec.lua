-- tests/wiki_spec.lua: the wiki generator (tools/wiki): the marker rewrite leaves prose alone and is idempotent, and
-- wiki-check fails both ways: on a stale region, and on a page or data entry that names something that does not exist.
local markers = require("tools.wiki.markers")
local check = require("tools.wiki.check")
local expressions = require("tools.wiki.collect.expressions")

local PAGE = table.concat({
    "Lead with **Bold Term** and `code`.",
    "",
    "## Table",
    "",
    "<!-- GENERATED:one -->",
    "old row",
    "<!-- /GENERATED -->",
    "",
    "Prose after, kept *as is*.",
    "",
}, "\n")

local function render(name)
    return "| A |\n|---|\n| " .. name .. " |"
end

describe("the wiki's marker rewrite", function()
    it("replaces only the region's body and keeps every other byte", function()
        local out = markers.rewrite(PAGE, render, "P")
        local want = PAGE:gsub("old row", markers.NOTE .. "\n| A |\n|---|\n| one |")
        assert.are.equal(want, out)
    end)

    it("is idempotent", function()
        local once = markers.rewrite(PAGE, render, "P")
        assert.are.equal(once, markers.rewrite(once, render, "P"))
    end)

    it("keeps a page with no final newline as it is", function()
        local s = PAGE:sub(1, -2)
        assert.are.equal(s:sub(-1), markers.rewrite(s, render, "P"):sub(-1))
    end)

    it("refuses an unclosed, nested or malformed marker", function()
        assert.has_error(function()
            markers.rewrite("<!-- GENERATED:a -->\nx\n", render, "P")
        end)
        assert.has_error(function()
            markers.rewrite("<!-- GENERATED:a -->\n<!-- GENERATED:b -->\n<!-- /GENERATED -->\n", render, "P")
        end)
        assert.has_error(function()
            markers.rewrite("<!-- GENERATED: a -->\n<!-- /GENERATED -->\n", render, "P")
        end)
    end)
end)

describe("wiki-check", function()
    it("fails on a stale region and passes once it is regenerated", function()
        assert.are.same({ "P: a generated table is stale (run `make wiki-tables`)" }, check.stale({ P = PAGE }, render))
        assert.are.same({}, check.stale({ P = markers.rewrite(PAGE, render, "P") }, render))
    end)

    it("fails on a region the manifest does not name", function()
        local errs = check.stale({ P = PAGE }, function(name)
            error("GENERATED:" .. name .. " is not in tools/wiki/manifest.lua", 0)
        end)
        assert.are.equal(1, #errs)
        assert.truthy(errs[1]:find("not in tools/wiki/manifest.lua", 1, true))
    end)

    it("fails on a bold label or path segment that names no option, and passes a real one", function()
        local labels = { ["Targeting"] = true, ["Enemy Range Radius"] = true, ["Priorities"] = true }
        local enus = labels
        local page = table.concat({
            "**Page Term** is the title term, never checked.",
            "",
            "## Set it",
            "",
            "1. Set **Enemy Range Radius** in **/hekili > Priorities > *your specialization* > Targeting**.",
            "2. Check **Count Plates Nearby** and open **/hekili > Priorities > Targetting**.",
            "- **On Forever:** a lead-in, never checked; nor is **a sentence-case term**.",
        }, "\n")
        assert.are.same({
            "P: the label **Count Plates Nearby** names no option",
            "P: the path segment **Targetting** names no option",
        }, check.labels({ P = page }, labels, enus))
        assert.are.same(
            { "P: the label **Enemy Range Radius** is not an English string in Locales/enUS.lua" },
            check.labels({ P = "## H\n\n**Enemy Range Radius**" }, labels, {})
        )
    end)

    it("fails on a command that is not published", function()
        local words = { set = true, snap = true }
        assert.are.same(
            { "P: `/hekili stress` is not a published command" },
            check.commands({ P = "Type `/hekili set cd on`, `/hek snap` or `/hekili stress`." }, words)
        )
    end)

    it("fails on a dead page link or anchor and an outside site, and warns on a missing image", function()
        local pages = {
            P = "## Here\n\n[ok](Q) [ok](#here) [ok](Q#there) [dead](Nope) [dead](Q#nowhere) [far](https://example.com/x)"
                .. "\n![shot](images/P-1.png)",
            Q = "## There\n",
        }
        local errors, warnings = check.links(pages, function()
            return false
        end)
        assert.are.same({
            "P: a link to Nope, which is no page",
            "P: a link to Q#nowhere, which is no heading",
            "P: a link to https://example.com/x, not wowsims.com, CurseForge or GitHub",
        }, errors)
        assert.are.same({ "P: image images/P-1.png is not in docs/wiki/ yet" }, warnings)
    end)

    it("fails on local paths, hidden switches and internal IDs", function()
        local errs = check.banned({ P = "see /home/x\nHekili.cdmOff\nper L123 and R41\nFury L60 and 0.958 are fine" })
        assert.are.same({
            "P:1: a home-directory path",
            "P:2: a hidden switch",
            "P:3: an internal ledger ID",
            "P:3: an internal ruling ID",
        }, errs)
    end)
end)

describe("the expression check", function()
    local SOURCE = table.concat({
        "",
        "local mt_x = {",
        '    __index = function( t, k ) if k == "lo" then return 1 elseif k:sub(1, 8) == "time_to_" then return 2 end end',
        "}",
        "ns.metatables.mt_x = mt_x",
    }, "\n")

    it("scans a root's keys from its __index branches", function()
        assert.are.same({ ["<r>.lo"] = true, ["<r>.time_to_<N>"] = true }, expressions.scan(SOURCE, "mt_x", "<r>"))
    end)

    it("fails both ways: a scanned key with no meaning, and a meaning whose key does not evaluate", function()
        local mt = {
            __index = function(_, k)
                if k == "lo" then
                    return 1
                end
            end,
        }
        local H = {
            Hekili = { State = { pool = setmetatable({ actual_lo = 1 }, mt) } },
            ns = { metatables = { mt_resource = mt, mt_x = mt } },
        }
        local scanned = expressions.scan(SOURCE, "mt_x", "<resource>")
        local d = {
            ["<resource>.lo"] = { type = "number", meaning = "The low end" },
            ["<resource>.gone"] = { type = "number", meaning = "A key the code no longer has" },
        }
        assert.are.same({
            "docs/wiki/data/expressions.lua: <resource>.gone does not evaluate (pool.gone)",
            "docs/wiki/data/expressions.lua: <resource>.time_to_<N> (scanned in mt_x) has no entry",
        }, expressions.problems({ root = "mt_x", prefix = "<resource>" }, H, scanned, d))
        d["<resource>.time_to_<N>"] = { omit = "not for priorities" }
        d["<resource>.gone"] = nil
        assert.are.same({}, expressions.problems({ root = "mt_x", prefix = "<resource>" }, H, scanned, d))
    end)
end)
