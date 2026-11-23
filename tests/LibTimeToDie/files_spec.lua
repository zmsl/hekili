-- tests/LibTimeToDie/files_spec.lua: the TOC (an installed addon) and the XML (an embedder's include) list the same
-- files in the same order, LibStub first.
local ROOT = "src/LibTimeToDie/"

describe("LibTimeToDie file lists", function()
    it("lists the same files in the TOC and the XML", function()
        local toc, xml = {}, {}
        for line in io.lines(ROOT .. "LibTimeToDie.toc") do
            line = line:gsub("\r", ""):gsub("%s+$", "")
            if line ~= "" and not line:match("^#") then
                toc[#toc + 1] = line:gsub("\\", "/")
            end
        end
        for line in io.lines(ROOT .. "LibTimeToDie.xml") do
            local f = line:match('<Script file="([^"]+)"')
            if f then
                xml[#xml + 1] = f:gsub("\\", "/")
            end
        end
        assert.are.same(toc, xml)
        assert.are.equal("Libs/LibStub/LibStub.lua", toc[1])
    end)
end)
