-- tests/Game/harness/ab.lua (providers spec §4.1, decision 83): the arm (HEKILI_AB) and the floor assertions every gate
-- routes through: the default arm asserts; a provider arm records each cell in .ab/<arm>.tsv and never fails.
local M = {}

M.ARMS = {
    default = { outcomes = "default", presence = "router", viewer = false },
    -- `observe`: the observer knobs the arm turns on (providers spec §4.2): the meter's events, and the hit row on us
    -- 0.48 +-0.09 s after its taken group (DM §3's measured lead; it moves those rows, so only a provider arm sets it)
    meter = { outcomes = "meter", presence = "router", viewer = false, observe = { meter = true, takenLag = 0.48 } },
    viewer = { outcomes = "default", presence = "router", viewer = true },
    -- the meter arm's baseline (measured by hand, not by make gate-ab): the Default with the meter arm's taken lead, so
    -- the two differ only by the leaf and its assumptions
    lagged = { outcomes = "default", presence = "router", viewer = false, observe = { takenLag = 0.48 } },
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
