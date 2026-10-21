-- tests/Forever/publication_spec.lua (publication plan, docs/superpowers/plans/2026-10-18-publication.md):
-- the offline publication rules: the GPLv3 LICENSE ships, no user-facing link to the old project survives,
-- the TOCs carry the fork's name/author/credit, .pkgmeta packs the seven src/ folders, and CHANGELOG.md exists.

local function read(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a")
    f:close()
    return s
end

local function tracked(...)
    local p = assert(io.popen("git ls-files -- " .. table.concat({ ... }, " ")))
    local out = {}
    for line in p:lines() do
        out[#out + 1] = line
    end
    p:close()
    return out
end

local TOCS = {
    "src/Hekili/Hekili.toc",
    "src/Hekili_Shared/Hekili_Shared.toc",
    "src/Hekili_Druid/Hekili_Druid.toc",
    "src/Hekili_Warrior/Hekili_Warrior.toc",
    "src/Hekili_Rogue/Hekili_Rogue.toc",
    "src/Hekili_Paladin/Hekili_Paladin.toc",
    "src/Hekili_Shaman/Hekili_Shaman.toc",
    "src/Hekili_Hunter/Hekili_Hunter.toc",
    "src/Hekili_Mage/Hekili_Mage.toc",
    "src/Hekili_Priest/Hekili_Priest.toc",
}

local function field(toc, key)
    key = key:gsub("%-", "%%-") -- keys like X-Website are matched literally
    return read(toc):match("\n## " .. key .. ": ([^\r\n]*)") or read(toc):match("^## " .. key .. ": ([^\r\n]*)")
end

describe("licence", function()
    it("ships the full GPLv3 text at the root and in src/Hekili, byte-identical", function()
        local root = read("LICENSE")
        assert.truthy(root:find("GNU GENERAL PUBLIC LICENSE", 1, true))
        assert.truthy(root:find("Version 3, 29 June 2007", 1, true))
        assert.truthy(root:find("END OF TERMS AND CONDITIONS", 1, true))
        assert.are.equal(root, read("src/Hekili/LICENSE"))
    end)

    it("ships wowsims/forever's MIT notice in src/Hekili for the translated (wowsims.com) priorities", function()
        local mit = read("src/Hekili/LICENSE-wowsims.txt")
        assert.truthy(mit:find("Copyright (c) 2022 wowsims team", 1, true))
        assert.truthy(mit:find("The above copyright notice and this permission notice shall be included", 1, true))
        local credits = read("src/Hekili/Libs/CREDITS.md")
        assert.truthy(credits:find("LICENSE-wowsims.txt", 1, true))
        assert.truthy(credits:find("https://github.com/wowsims/forever", 1, true))
    end)

    it("states the modification notice in the core's header", function()
        local head = read("src/Hekili/Hekili.lua"):sub(1, 1200)
        assert.truthy(head:find("based on the original work by Hekili", 1, true))
        assert.truthy(head:find("Modified for WoW Forever by defzach", 1, true))
        assert.truthy(head:find("GNU General Public License", 1, true))
    end)
end)

-- lowercase patterns; a hit is "path:line: text"
local FORBIDDEN = {
    "discord",
    "wowinterface",
    "patreon",
    "paypal",
    "ko%-fi",
    "curseforge%.com/wow/addons/hekili$",
    "curseforge%.com/wow/addons/hekili[^%-]",
    "hekili#0001",
}
local ALLOW = {
    ["src/Hekili/Engine/Sim/Targets.lua"] = "github%.com/hekili/hekili/issues/4845",
    ["README.md"] = "discord%.gg/jac6w4pkur", -- the fork's own server, not the old project's
    ["docs/publishing/README.md"] = "discord webhook", -- the fork's own release webhook (Cutting a release)
}

local function scan(files, upstream)
    local hits = {}
    for _, path in ipairs(files) do
        if not path:find("/Libs/", 1, true) then
            local n = 0
            for line in (read(path) .. "\n"):gmatch("([^\n]*)\n") do
                n = n + 1
                local l = line:lower()
                if ALLOW[path] and l:find(ALLOW[path]) then
                    l = ""
                end
                for _, pat in ipairs(FORBIDDEN) do
                    if l:find(pat) then
                        hits[#hits + 1] = path .. ":" .. n .. ": " .. line
                    end
                end
                if l:find(upstream) then
                    hits[#hits + 1] = path .. ":" .. n .. ": " .. line
                end
            end
        end
    end
    return hits
end

describe("upstream links", function()
    it("has none in shipped files (src/: no github.com/Hekili at all)", function()
        local files = tracked("'src/*.lua'", "'src/*.toc'", "'src/*.xml'")
        assert.is_true(#files > 50)
        assert.are.same({}, scan(files, "github%.com/hekili"))
    end)

    it("has only the bare upstream repo link in issue templates and the publishing record", function()
        local files = tracked("'.github/ISSUE_TEMPLATE/*'", "docs/publishing/README.md")
        assert.is_true(#files >= 4)
        assert.are.same({}, scan(files, "github%.com/hekili/hekili/"))
    end)

    it("credits and links the original in the publishing record", function()
        local s = read("docs/publishing/README.md")
        assert.truthy(s:lower():find("based on the original work by hekili", 1, true))
        assert.truthy(s:find("https://github.com/Hekili/hekili", 1, true))
        assert.truthy(s:find("explicit permission", 1, true))
    end)

    it("puts the fork notice on the General page", function()
        local s = read("src/Hekili/Options/Options.lua")
        assert.truthy(s:find("is a fork of the original |cFFFFD100Hekili|r project", 1, true))
        assert.truthy(s:find("explicit permission of its original author", 1, true))
        assert.truthy(s:find('name = "Hekili Forever " .. Hekili.Version', 1, true))
        assert.falsy(s:find("ns.Patrons", 1, true))
    end)
end)

describe("readme", function()
    it("has no old-project link but the bare upstream repo", function()
        assert.are.same({}, scan({ "README.md" }, "github%.com/hekili/hekili/"))
        assert.falsy(read("README.md"):lower():find("wiki", 1, true))
    end)

    it("credits the original, states the permission, the fork's tracker and the licence", function()
        local s = read("README.md")
        for _, want in ipairs({
            "docs/publishing/icon-512.png",
            "based on the original work by Hekili",
            "explicit permission",
            "https://github.com/Hekili/hekili",
            "https://github.com/zmsl/hekili/issues",
            "https://github.com/zmsl/hekili/releases",
            "GNU General Public License version 3 or later",
            "Modified for WoW Forever by defzach",
            "Libs/CREDITS.md",
        }) do
            assert.truthy(s:find(want, 1, true), want)
        end
    end)
end)

describe("tocs", function()
    it("name the fork, its author and the original in every TOC", function()
        for _, toc in ipairs(TOCS) do
            assert.are.equal("defzach", field(toc, "Author"), toc)
            assert.truthy(field(toc, "Title"):find("^Hekili Forever"), toc)
            assert.truthy(field(toc, "Notes"):lower():find("based on the original work by hekili", 1, true), toc)
            assert.are.equal("https://github.com/zmsl/hekili", field(toc, "X-Website"), toc)
            assert.are.equal("Interface\\AddOns\\Hekili\\Textures\\HekiliForever", field(toc, "IconTexture"), toc)
        end
        assert.are.equal("Hekili Forever", field(TOCS[1], "Title"))
        assert.are.equal("Hekili Forever - Shared", field(TOCS[2], "Title"))
        assert.are.equal("1753387", field(TOCS[1], "X-Curse-Project-ID"))
        assert.truthy(io.open("src/Hekili/Textures/HekiliForever.tga"))
    end)

    it("keep the Keep-as-is fields", function()
        assert.are.equal("HekiliDB", field(TOCS[1], "SavedVariables"))
        for i = 2, 4 do
            assert.truthy(field(TOCS[i], "Dependencies"):find("^Hekili"), TOCS[i])
            assert.are.equal("Hekili", field(TOCS[i], "Group"), TOCS[i])
            assert.truthy(field(TOCS[i], "X-Hekili-ContentAPI"), TOCS[i])
        end
    end)
    it("let the packager stamp the version in every TOC", function()
        for _, toc in ipairs(TOCS) do
            assert.are.equal("@project-version@", field(toc, "Version"), toc)
        end
    end)
end)

describe("pkgmeta", function()
    it("moves the ten src/ folders to the zip root and ignores the dev tree", function()
        local s = read(".pkgmeta")
        assert.truthy(s:find("\npackage%-as: Hekili\n") or s:find("^package%-as: Hekili\n"))
        for _, a in ipairs({
            "Hekili",
            "Hekili_Shared",
            "Hekili_Druid",
            "Hekili_Warrior",
            "Hekili_Rogue",
            "Hekili_Paladin",
            "Hekili_Shaman",
            "Hekili_Hunter",
            "Hekili_Mage",
            "Hekili_Priest",
        }) do
            assert.truthy(s:find("\n    Hekili/src/" .. a .. ": " .. a .. "\n", 1, true), a)
        end
        for _, p in ipairs({ "tests", "tools", "docs", "scripts", "archive", ".superpowers", ".github" }) do
            assert.truthy(s:find("\n    - " .. p .. "\n", 1, true), p)
        end
        assert.falsy(s:find("LICENSE", 1, true)) -- never ignored
        assert.falsy(s:find("externals", 1, true)) -- libraries are vendored
        -- a generated changelog would ship as Hekili/CHANGELOG.md; the tracked one is ignored for copying
        assert.truthy(s:find("\nmanual-changelog:\n    filename: CHANGELOG.md\n", 1, true))
    end)
end)

describe("changelog", function()
    it("is tracked and opens with the Unreleased heading", function()
        assert.are.same({ "CHANGELOG.md" }, tracked("CHANGELOG.md"))
        assert.truthy(read("CHANGELOG.md"):find("^# Hekili Forever changelog\n\n## Unreleased\n"))
    end)
end)
