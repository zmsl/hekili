-- tests/wiki_spec.lua: the wiki generator (tools/wiki): the marker rewrite leaves prose alone and is idempotent, and
-- wiki-check fails both ways: on a malformed or unknown marker, and on a page or data entry that names something that does not exist.
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

    it("strips a region to its bare markers", function()
        local filled = markers.rewrite(PAGE, render, "P")
        local bare = PAGE:gsub("old row\n", "")
        assert.are.equal(bare, markers.strip(filled, "P"))
        assert.are.equal(bare, markers.strip(PAGE, "P"))
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
    it("fails on a region the manifest does not name or a malformed marker, and passes a known one", function()
        assert.are.same({}, check.markers({ P = PAGE }, { one = true }))
        assert.are.same(
            { "P: GENERATED:one is not in tools/wiki/manifest.lua" },
            check.markers({ P = PAGE }, { other = true })
        )
        local errs = check.markers({ P = "<!-- GENERATED:one -->\nx\n" }, { one = true })
        assert.are.equal(1, #errs)
        assert.truthy(errs[1]:find("never closed", 1, true))
    end)

    it("fails on a retired page name that collides with a page", function()
        assert.are.same({}, check.retired({ P = "" }, { "Old.md" }))
        assert.are.same(
            { "retired-pages.txt: P.md is retired but docs/wiki has that page" },
            check.retired({ P = "" }, { "P.md" })
        )
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

    it(
        "accepts a filled-in %s string, a choice's (Default) and a shared-library label, and still rejects others",
        function()
            local labels = {}
            local enus =
                { ["Show in Separate %s Cooldowns Display"] = true, ["Automatic"] = true, ["Active During %s"] = true }
            local lib = { ["Reset Profile"] = true }
            local page = table.concat({
                "## H",
                "",
                "**Show in Separate Defensives Cooldowns Display**, **Active During Combat**, **Automatic (Default)**,",
                "**Reset Profile**, **Show Elsewhere Cooldowns Display** and **Manual (Default)**.",
            }, "\n")
            assert.are.same({
                "P: the label **Manual (Default)** names no option",
                "P: the label **Show Elsewhere Cooldowns Display** names no option",
            }, check.labels({ P = page }, labels, enus, lib))
        end
    )

    it("keeps a bold path that ends in an italic placeholder whole", function()
        local labels = { ["Priorities"] = true, ["Targeting"] = true }
        local page =
            "## H\n\nSee **/hekili > Priorities > *your specialization***, then **/hekili > Priorities > Targetting > *x***."
        assert.are.same(
            { "P: the path segment **Targetting** names no option" },
            check.labels({ P = page }, labels, labels)
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
        assert.are.equal(2, #check.banned({ P = "L1000\nR123" }))
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

describe("make wiki-build", function()
    -- A per-run directory, so parallel worktrees running this spec never share one.
    local OUT = os.tmpname()
    os.remove(OUT)
    local function build(out)
        local ok = os.execute("make wiki-build WIKI_OUT=" .. (out or OUT) .. " >/dev/null 2>&1")
        return ok == 0 or ok == true
    end
    local function slurp(path)
        local f = assert(io.open(path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end
    local function tree()
        local p = assert(io.popen("cd docs/wiki && find . -name '*.md' -not -name README.md | sort | xargs cat"))
        local s = p:read("*a")
        p:close()
        return s
    end

    teardown(function()
        os.execute("rm -rf " .. OUT)
    end)

    it("keeps the source's regions empty, fills a copy outside the source and leaves the source alone", function()
        local before = tree()
        assert.is_true(build())
        assert.are.equal(before, tree())
        local src, out = slurp("docs/wiki/Slash-Commands.md"), slurp(OUT .. "/Slash-Commands.md")
        assert.are.equal(src, markers.strip(src, "S"), "docs/wiki/ holds only bare markers")
        assert.are_not.equal(src, out)
        assert.truthy(out:find(markers.NOTE, 1, true))
        assert.are.equal(src, markers.strip(out, "S"), "the copy differs only inside the regions")
        assert.is_nil(io.open(OUT .. "/README.md"))
        assert.is_nil(io.open(OUT .. "/data/commands.lua"))
    end)

    it("is idempotent", function()
        assert.is_true(build())
        local first = slurp(OUT .. "/Slash-Commands.md")
        assert.is_true(build())
        assert.are.equal(first, slurp(OUT .. "/Slash-Commands.md"))
    end)

    it("fills the accuracy facts from the version in accuracy.json", function()
        assert.is_true(build())
        assert.truthy(slurp(OUT .. "/Accuracy.md"):find("| Measured on | Hekili Forever v", 1, true))
    end)

    it("refuses an empty, root or docs output path and leaves the source alone", function()
        local before = tree()
        for _, bad in ipairs({ "''", "/", "docs/wiki", "./", ".." }) do
            assert.is_false(build(bad), bad)
        end
        assert.are.equal(before, tree())
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

describe("make wiki-build", function()
    local OUT = "/tmp/wiki-build-spec" -- not build/, so a gate run leaves the tree as it found it
    local function build()
        local ok = os.execute(".lua/bin/lua tools/wiki/gen.lua build " .. OUT .. " >/dev/null 2>&1")
        assert.is_true(ok == 0 or ok == true)
    end
    local function slurp(path)
        local f = assert(io.open(path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end
    local function tree()
        local p = assert(io.popen("cd docs/wiki && find . -name '*.md' -not -name README.md | sort | xargs cat"))
        local s = p:read("*a")
        p:close()
        return s
    end

    it("keeps the source's regions empty, fills a copy outside the source and leaves the source alone", function()
        local before = tree()
        build()
        assert.are.equal(before, tree())
        local src, out = slurp("docs/wiki/Slash-Commands.md"), slurp(OUT .. "/Slash-Commands.md")
        assert.are.equal(src, markers.strip(src, "S"), "docs/wiki/ holds only bare markers")
        assert.are_not.equal(src, out)
        assert.truthy(out:find(markers.NOTE, 1, true))
        assert.are.equal(src, markers.strip(out, "S"), "the copy differs only inside the regions")
        assert.is_nil(io.open(OUT .. "/README.md"))
        assert.is_nil(io.open(OUT .. "/data/commands.lua"))
    end)

    it("is idempotent", function()
        local first = slurp(OUT .. "/Slash-Commands.md")
        build()
        assert.are.equal(first, slurp(OUT .. "/Slash-Commands.md"))
    end)
end)

describe("the options collector", function()
    local options = require("tools.wiki.collect.options")

    local manifest = require("tools.wiki.manifest")
    local function byLabel(rows)
        local out = {}
        for _, r in ipairs(rows) do
            out[r.label] = out[r.label] or r
        end
        return out
    end

    it(
        "keeps an option hidden only in some states, and leaves out the always-hidden one named in the manifest",
        function()
            local rows = byLabel(options.rows(manifest["options-spec"]))
            assert.is_nil(rows["Filter by Time-to-Die"], "the always-hidden option is not a row")
            assert.is_true(options.labels()["Filter by Time-to-Die"], "its label is still a known option label")
            assert.are.equal("In some cases", rows["Enemy Range Radius"].shown)
            assert.are.equal("In some cases", rows["Count Targets Near Your Pet"].shown)
            assert.are.equal("Yes", rows["Frame Budget"].shown)
            local editor = byLabel(options.rows(manifest["options-editor"]))
            for _, field in ipairs({ "Use Off GCD", "Focus Tier", "Label", "Cycle Targets", "Variable Name" }) do
                assert.are.equal("In some cases", editor[field] and editor[field].shown, field)
            end
        end
    )

    it(
        "drops the never-shown display Enabled row, keeps the radius slider's range, and starts at a hidden node",
        function()
            for _, r in ipairs(options.rows(manifest["options-display-icons"])) do
                assert.is_false(r.section == "Icons" and r.label == "Enabled", "the display Enabled row never shows")
            end
            local spec = byLabel(options.rows(manifest["options-spec"]))
            assert.are.equal("Set per specialization", spec["Enemy Range Radius"].default)
            assert.are.equal("0 to 100, step 1", spec["Enemy Range Radius"].range)
            assert.is_nil(spec["Show Enemy Nameplates"].default)
            for _, r in ipairs(options.rows(manifest["options-display-timeline"])) do
                assert.are.equal("In some cases", r.shown, r.section .. " > " .. r.label) -- the tab is hidden by default
            end
        end
    )

    it("keeps a colour's alpha when it is not 1", function()
        local found
        for _, r in ipairs(options.rows(manifest["options-display-timeline"])) do
            found = found or (r.type == "colour" and tostring(r.default):find(" at %d+%%$"))
        end
        assert.truthy(found)
    end)

    it("prints a colour default as hex", function()
        local n = 0
        for _, r in ipairs(options.rows(manifest["options-display-classic"])) do
            if r.type == "colour" then
                n = n + 1
                assert.truthy(tostring(r.default):match("^#%x%x%x%x%x%x"), r.section .. " > " .. r.label)
            end
        end
        assert.is_true(n > 0)
    end)

    it("prints a font by its name and an unset toggle as Off", function()
        local all = byLabel(options.rows(manifest["options-displays-all"]))
        assert.are.equal("Arial Narrow", all["Font"].default)
        local pause
        for _, r in ipairs(options.rows(manifest["options-toggles"])) do
            if r.label == "Pause" and r.type == "toggle" then
                pause = r
            end
        end
        assert.are.equal("Off", pause and pause.default)
    end)

    it("does not end a description's first sentence at e.g. or i.e.", function()
        local text = require("tools.wiki.text")
        assert.are.equal(
            "Shown while it holds, e.g. a buff is up.",
            text.sentence("Shown while it holds, e.g. a buff is up. More.")
        )
        assert.are.equal("One.", text.sentence("One. Two."))
    end)
end)
