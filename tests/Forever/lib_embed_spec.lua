-- tests/Forever/lib_embed_spec.lua (LibHiddenValues integration design 5.5, lane B0): the core embeds LibHiddenValues
-- and LibTimeToDie in its package and lists both as OptionalDeps. In the linked development tree each library is its
-- own addon folder and src/Hekili/Libs has neither, so the embed lines sit in a packager guard: commented out in the
-- source (nothing to load, and the headless loader strips comments), opened by the packager's debug filter in the zip
-- (tools/check_package.sh checks the zip). Each library's check_standalone allows exactly the two host files.
local function read(path)
    local f = assert(io.open(path))
    local s = f:read("*a")
    f:close()
    return s
end

local function sh(cmd)
    local p = assert(io.popen(cmd .. " 2>&1; echo rc=$?"))
    local out = p:read("*a")
    p:close()
    return out, tonumber(out:match("rc=(%d+)%s*$"))
end

describe("the embedded libraries", function()
    it("embeds.xml includes both libraries after LibStub, inside the packager's non-debug guard", function()
        local xml = read("src/Hekili/embeds.xml")
        local guard = assert(xml:match("<!%-%-@non%-debug@(.-)@end%-non%-debug@%-%->"), "no non-debug guard")
        local a = guard:find('<Include file="Libs\\LibHiddenValues\\LibHiddenValues.xml"/>', 1, true)
        local b = guard:find('<Include file="Libs\\LibTimeToDie\\LibTimeToDie.xml"/>', 1, true)
        assert.is_truthy(a and b and a < b, guard)
        assert.is_nil(guard:find("<!--", 1, true)) -- one comment: nothing inside closes it early
        assert.is_truthy(xml:find('LibStub.lua"/>%s*<!%-%-@non%-debug@'))
        -- outside the guard nothing names them: the development tree loads no missing file
        local outside = xml:gsub("<!%-%-.-%-%->", "")
        assert.is_nil(outside:find("LibHiddenValues", 1, true))
        assert.is_nil(outside:find("LibTimeToDie", 1, true))
    end)

    it("Hekili.toc lists both as OptionalDeps, so a standalone copy loads first", function()
        local deps = assert(read("src/Hekili/Hekili.toc"):match("\n## OptionalDeps: ([^\r\n]+)"))
        local seen = {}
        for name in deps:gmatch("[^,%s]+") do
            seen[name] = true
        end
        assert.is_true(seen.LibHiddenValues)
        assert.is_true(seen.LibTimeToDie)
    end)

    it(".pkgmeta moves both into Hekili/Libs after the core and leaves their Testing/ out", function()
        local meta = read(".pkgmeta")
        local core = assert(meta:find("\n    Hekili/src/Hekili: Hekili\n", 1, true))
        local lhv = assert(meta:find("\n    Hekili/src/LibHiddenValues: Hekili/Libs/LibHiddenValues\n", 1, true))
        local ttd = assert(meta:find("\n    Hekili/src/LibTimeToDie: Hekili/Libs/LibTimeToDie\n", 1, true))
        assert.is_true(core < lhv and lhv < ttd)
        assert.is_truthy(meta:find("\n    - src/LibHiddenValues/Testing\n", 1, true))
        assert.is_truthy(meta:find("\n    - src/LibTimeToDie/Testing\n", 1, true))
        assert.is_nil(meta:find("\n    - src/LibHiddenValues\n", 1, true))
        assert.is_nil(meta:find("\n    - src/LibTimeToDie\n", 1, true))
    end)

    -- Each check runs on a copy of what it scans, with the host's two files and one more file of the core's.
    for _, lib in ipairs({ { "LibHiddenValues", "libhiddenvalues" }, { "LibTimeToDie", "libtimetodie" } }) do
        local name, tool = lib[1], lib[2]
        it("tools/" .. tool .. "/check_standalone.sh allows exactly the embed and the TOC, by full path", function()
            local tmp = assert(assert(sh("mktemp -d")):match("^(%S+)"))
            finally(function() -- also when an assert below fails
                sh("rm -rf " .. tmp)
            end)
            local copy = table.concat({
                "mkdir -p " .. tmp .. "/src/Hekili/Libs " .. tmp .. "/tools " .. tmp .. "/tests",
                "cp -r src/LibHiddenValues src/LibTimeToDie " .. tmp .. "/src",
                "cp -r tests/LibHiddenValues tests/LibTimeToDie " .. tmp .. "/tests",
                "cp -r tools/libhiddenvalues tools/libtimetodie " .. tmp .. "/tools",
                "cp src/Hekili/embeds.xml src/Hekili/Hekili.toc " .. tmp .. "/src/Hekili",
                'ln -s "$(pwd)/.lua" ' .. tmp .. "/.lua",
            }, " && ")
            local out, rc = sh(copy)
            assert.are.equal(0, rc, out)
            local check = "bash " .. tmp .. "/tools/" .. tool .. "/check_standalone.sh"
            out, rc = sh(check)
            assert.are.equal(0, rc, out)
            -- the same name in another file of the core, also one whose basename is allowed, fails
            for _, rogue in ipairs({ "src/Hekili/Rogue.lua", "src/Hekili/Libs/embeds.xml" }) do
                local f = assert(io.open(tmp .. "/" .. rogue, "w"))
                f:write("-- " .. name .. "\n")
                f:close()
                out, rc = sh(check)
                assert.are.equal(1, rc, out)
                assert.is_truthy(out:find(rogue .. ":1:", 1, true), out)
                os.remove(tmp .. "/" .. rogue)
            end
        end)
    end
end)
