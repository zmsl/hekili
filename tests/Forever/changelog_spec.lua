-- tests/Forever/changelog_spec.lua (approved-release plan, docs/superpowers/plans/2026-10-19-approved-release.md):
-- CHANGELOG.md is the raw input of the generated release notes: an "## Unreleased" section first, carrying the five
-- headings implementers write under, and no released "## v..." section left empty.

local function read(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a")
    f:close()
    return s
end

-- { { name = "Unreleased", lines = { ... } }, ... } in file order; lines before the first "## " are the title
local function sections(text)
    local out, cur = {}, nil
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local name = line:match("^## (.-)%s*$")
        if name then
            cur = { name = name, lines = {} }
            out[#out + 1] = cur
        elseif cur then
            cur.lines[#cur.lines + 1] = line
        end
    end
    return out
end

local HEADINGS = { "New", "Changed", "Fixed", "Known issues", "Upgrade notes" }

describe("changelog", function()
    local all = sections(read("CHANGELOG.md"))

    it("opens with Unreleased, once", function()
        assert.are.equal("Unreleased", all[1] and all[1].name)
        for i = 2, #all do
            assert.are_not.equal("Unreleased", all[i].name)
        end
    end)

    it("gives Unreleased the five headings in order", function()
        local got = {}
        for _, line in ipairs(all[1].lines) do
            local h = line:match("^### (.-)%s*$")
            if h then
                got[#got + 1] = h
            end
        end
        assert.are.same(HEADINGS, got)
    end)

    it("names every other section after a tag and leaves none empty", function()
        assert.is_true(#all >= 2)
        for i = 2, #all do
            local s = all[i]
            assert.truthy(s.name:match("^v%d+%.%d+%.%d+"), s.name)
            local text = false
            for _, line in ipairs(s.lines) do
                if line:find("%S") and not line:match("^###") then
                    text = true
                end
            end
            assert.is_true(text, s.name .. " is empty")
        end
    end)
end)
