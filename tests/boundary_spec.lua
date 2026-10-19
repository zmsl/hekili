-- tests/boundary_spec.lua
-- The core/content boundary (core leakage audit, docs/research/2026-10-16-core-leakage-audit.md): the core engine
-- (src/Hekili/Game/**, src/Hekili/Engine/Schema/**) and the harness core (tests/Game/harness/**, GCD kinds design D7)
-- name no ability, aura or talent key and no spell ID that the Forever content (src/Hekili_Shared/**, src/Hekili_<Class>/**: the class packs,
-- Races, Shared) registers, and no class or form/stance name. Ported from Taco Dog Forever's tests/boundary_spec.lua, which
-- scans for a fixed word list; here the keys and IDs are extracted from the content at test time, so a new ability is
-- checked without being listed.
-- Code only: comments are skipped, and so is a string with whitespace (a message or a description); each word of any
-- other string (`buff["rend"]`, `"buff.rend.up"`, `"772"`) is checked like an identifier or a number. A multi-part key
-- (`heroic_strike`) also matches as parts of an identifier (`HEROIC_STRIKE_COST`); a one-word key matches whole only.
local B = require("boundary_lib")

-- The harness core too (GCD kinds design D7), but its captured logs (tests/Game/harness/fixtures/): their numbers
-- are times in ms and amounts, never IDs.
local CORE = { "src/Hekili/Game", "src/Hekili/Engine/Schema", "tests/Game/harness" }
local SKIP = { "^tests/Game/harness/fixtures/" }
local SIM = { "src/Hekili/Engine/Sim" }
-- The content (restructure plan, Task 8): it reaches the engine through the public Hekili object only.
local CONTENT = {}
for _, name in ipairs(require("helpers.addons").CONTENT) do
    CONTENT[#CONTENT + 1] = require("helpers.addons").root(name)
end
local PUBLIC = {
    NewClass = true,
    NewSpecialization = true,
    NewShared = true,
    NewRace = true,
    State = true,
    Class = true,
    Client = true,
}
local PRIVATE = { "%f[%w_]ns%.", "ns%s*=%s*%.%.%.", "VirtualState", "Hekili%.Virtual", "Hekili%.Engine" }

describe("core/content boundary", function()
    local c = B.content()
    local words = B.nameWords(c.keys)

    it("extracts the content's keys and IDs from every Forever file kind", function()
        local n, m = 0, 0
        for _ in pairs(c.keys) do
            n = n + 1
        end
        for _ in pairs(c.ids) do
            m = m + 1
        end
        assert.is_true(n > 150, n)
        assert.is_true(m > 400, m)
        assert.are.equal("Hekili_Shared/Races/Orc.lua", c.keys.blood_fury)
        assert.is_not_nil(c.keys.bloodlust) -- Shared/Auras.lua
        assert.is_not_nil(words.cat and words.battle)
    end)

    it("tokenizes code only, and matches words as snake_case or CamelCase parts", function()
        local t = B.tokens('-- rend\n--[==[ rend ]==] local x = "a rend" .. [[rend]] .. "rend" + 0x1F + 1.5e3')
        local got = {}
        for _, k in ipairs(t) do
            got[#got + 1] = k[1] .. ":" .. k[2]
        end
        assert.are.same(
            { "name:local", "name:x", "string:a rend", "string:rend", "string:rend", "number:0x1F", "number:1.5e3" },
            got
        )
        assert.are.equal(2, t[#t][3])
        assert.is_true(
            B.hasWord("DRUID_SPEC", "druid") and B.hasWord("isCatForm", "cat") and B.hasWord("dire_bear", "bear")
        )
        assert.is_false(B.hasWord("scatter", "cat") or B.hasWord("magenta", "mage"))
        local probe = {
            "local a = buff.rend",
            'local b = "rend"',
            "local c = 772",
            'local d = "WARRIOR"',
            'f("buff.rend.up")',
            'x = "772"',
            'y = "WARRIOR,DRUID"',
            "local HEROIC_STRIKE_COST",
            "local heroicStrikeCost",
            'z = "a rend in a message"',
            "local GetShieldBlock",
            "local rendTicks",
        }
        local found = B.leaks("x.lua", table.concat(probe, "\n"), {
            keys = { rend = "R", heroic_strike = "R", shield_block = "R" },
            ids = { [772] = "R" },
        }, { warrior = "a class name", druid = "a class name" })
        local lines = {}
        for _, f in ipairs(found) do
            lines[#lines + 1] = tonumber(f:match("^x%.lua:(%d+):"))
        end
        -- one-word keys match whole only (`rendTicks` passes: `charge`, `form` are plain words in core)
        assert.are.same({ 1, 2, 3, 4, 5, 6, 7, 7, 8, 9 }, lines)
    end)

    it(
        "keeps content keys, spell IDs, class and form names out of Game/**, Engine/Schema/** and the harness core",
        function()
            local found = {}
            local files = B.coreFiles(CORE, SKIP)
            assert.is_true(#files > 30)
            for _, path in ipairs(files) do
                for _, hit in ipairs(B.leaks(path, B.read(path), c, words)) do
                    found[#found + 1] = hit
                end
            end
            assert.are.same({}, found)
        end
    )
    it("keeps the content on the public surface: the registration API, State, Class and Client", function()
        local found = {}
        local files = B.coreFiles(CONTENT, {})
        assert.is_true(#files >= 13)
        for _, path in ipairs(files) do
            local src = B.read(path):gsub("%[(=*)%[.-%]%1%]", "") -- a pack's share string is data
            for name in src:gmatch("Hekili[.:]([%w_]+)") do
                if not PUBLIC[name] then
                    found[#found + 1] = path .. ": Hekili." .. name
                end
            end
            for _, pat in ipairs(PRIVATE) do
                if src:find(pat) then
                    found[#found + 1] = path .. ": " .. pat
                end
            end
        end
        assert.are.same({}, found)
    end)

    -- Engine/Sim/** is stock Hekili with its inherited class branches and field names a Forever key shares (`charge`,
    -- `execute`, `form`): frozen per file by tests/boundary_baseline.lua (tools/boundary_baseline.lua). Shortcut: a
    -- per-file token ceiling, not a line lock; an edit that adds one `charge` and removes another passes.
    it("lets Engine/Sim/** keep no more of each content name than its baseline", function()
        local baseline = require("boundary_baseline")
        local found = {}
        local files = B.coreFiles(SIM, {})
        assert.is_true(#files >= 7)
        local seen = {}
        for _, path in ipairs(files) do
            seen[path] = true
            local base = baseline[path] or {}
            for token, n in pairs(B.counts(path, c, words)) do
                if n > (base[token] or 0) then
                    found[#found + 1] = ("%s: %s baseline %d found %d"):format(path, token, base[token] or 0, n)
                end
            end
        end
        for path in pairs(baseline) do
            if not seen[path] then
                found[#found + 1] = path .. ": in the baseline but missing"
            end
        end
        table.sort(found)
        assert.are.same({}, found)
    end)
end)
