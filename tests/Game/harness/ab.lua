-- tests/Game/harness/ab.lua (providers spec §4.1, decision 83): the arm (HEKILI_AB) and the floor assertions every gate
-- routes through: the default arm asserts; a provider arm records each cell in .ab/<arm>.tsv and never fails.
local M = {}

M.ARMS = {
    default = { outcomes = "default", presence = "router", viewer = false },
    -- `observe`: the observer knobs the arm turns on (the meter's events; added events only, providers spec §4.2)
    meter = { outcomes = "meter", presence = "router", viewer = false, observe = { meter = true } },
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

--- Sets the current arm's observer knobs on `k` (none in the default arm: its stream is today's).
function M.observe(k)
    for key, v in pairs(M.ARMS[M.arm()].observe or {}) do
        k[key] = v
    end
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
