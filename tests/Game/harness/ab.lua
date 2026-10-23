-- tests/Game/harness/ab.lua (providers spec §4.1, decision 83): the arm (HEKILI_AB) and the floor assertions every gate
-- routes through: the default arm asserts; a provider arm records each cell in .ab/<arm>.tsv and never fails.
local M = {}

M.ARMS = {
    default = { outcomes = "default", presence = "router", viewer = false },
    meter = { outcomes = "meter", presence = "router", viewer = false },
    viewer = { outcomes = "default", presence = "router", viewer = true },
}

function M.arm()
    local a = os.getenv("HEKILI_AB")
    return (a and M.ARMS[a]) and a or "default"
end

--- def.providers for the current arm (a fresh table: the build keeps it).
function M.providers(arm)
    local p = M.ARMS[arm or M.arm()]
    return { outcomes = p.outcomes, presence = p.presence, viewer = p.viewer }
end

function M.check(ok, label, line, arm)
    arm = arm or M.arm()
    if arm == "default" then
        assert(ok, label .. ": " .. tostring(line))
        return
    end
    assert(io.popen("mkdir -p .ab")):close() -- popen: `execute` is a content key (tests/boundary_spec.lua)
    local fh = assert(io.open(".ab/" .. arm .. ".tsv", "a"))
    fh:write(label, "\t", ok and "ok" or "MISS", "\t", tostring(line), "\n")
    fh:close()
end

return M
