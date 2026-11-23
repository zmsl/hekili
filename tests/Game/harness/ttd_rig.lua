-- tests/Game/harness/ttd_rig.lua (lane B8, design 2.7's jitter rule): the real LibTimeToDie in a headless instance,
-- over the bands arms' fake LibHiddenValues (fake_lhv.lua), on the instance's clock. The fake keeps its sinks and never
-- calls them (the belief polls); the library feeds its estimator from a sink, so it is handed a thin adapter: Watch
-- opens the fake's handle and remembers the library's sink, and `M.poll` (once per harness tick, before the cycle)
-- calls that sink when a handle's band moves, as the real one does (Bars.lua: sink(h, lo, hi, dir, t, q)), then runs
-- the library's driver (its frame's OnUpdate; the headless client runs only the belief's). The library loads in its
-- own environment over the instance's: its LibStub answers the adapter for LibHiddenValues and is the instance's for
-- the rest, so the core finds LibTimeToDie in the instance's LibStub as in game. The client's events reach its frame
-- through H.Fire (the target change, the pull). fake_lhv.lua is not changed.
local M = {}

local SRC = "src/LibTimeToDie/"
local LHV = "LibHiddenValues-1.0"

--- Installs the library into instance H over fake library `lhv`; returns the rig (its `lib`, its watches).
function M.install(H, lhv)
    local stub = rawget(H.env, "LibStub")
    local rig = { watches = {}, lhv = lhv, ctl = H.ctl }
    local adapter = {}
    function adapter.Watch(_, owner, spec, sink)
        local h, code = lhv:Watch(owner, spec)
        if h then
            rig.watches[#rig.watches + 1] = { h = h, sink = sink }
        end
        return h, code
    end
    function adapter.OnCapability() end
    function adapter.IsAvailable(_, kind, unit)
        return lhv:IsAvailable(kind, unit)
    end
    function adapter.GetMessage() end
    function adapter.GetVersion()
        return lhv:GetVersion()
    end
    local proxy = setmetatable({}, {
        __index = stub,
        __call = function(_, name, silent)
            if name == LHV then
                local _, minor = lhv:GetVersion()
                return adapter, minor
            end
            return stub(name, silent)
        end,
    })
    -- shortcut: the library's UnitIsUnit answers a target and a plate plainly from the fake client's GUIDs, so a past
    -- target's life moves to its plate (minor 5); live, under the Map restriction it may answer secret, which links
    -- nothing. The belief's UnitIsUnit (ctl.unitIs) is left as it was: no belief row moves for it.
    local ctl = H.ctl
    local function unitIsUnit(a, b)
        local ga, gb = ctl.guid[a], ctl.guid[b]
        if a ~= b and type(ga) == "string" and type(gb) == "string" then
            return ga == gb
        end
        return H.env.UnitIsUnit(a, b)
    end
    local env = setmetatable({ LibStub = proxy, UnitIsUnit = unitIsUnit }, { __index = H.env })
    for _, file in ipairs({ "LibTimeToDie.lua", "Estimator.lua" }) do -- LibTimeToDie.xml's order
        local f = assert(loadfile(SRC .. file))
        setfenv(f, env)
        f()
    end
    rig.lib = stub("LibTimeToDie-1.0")
    return rig
end

--- One harness tick: each watch's band change to the library's sink, then the library's driver. Allocates nothing.
function M.poll(rig)
    local ws = rig.watches
    for i = #ws, 1, -1 do
        local w = ws[i]
        local h = w.h
        if h:State() == "released" then
            table.remove(ws, i)
        else
            local lo, hi, t, q = h:Get()
            if lo ~= w.lo or hi ~= w.hi then
                local dir = (lo and w.lo) and ((lo > w.lo or hi > w.hi) and 1 or -1) or nil
                w.lo, w.hi = lo, hi
                if w.sink then
                    w.sink(h, lo, hi, dir, t or rig.ctl.now, q)
                end
            end
        end
    end
    local f = rig.lib.frame
    local u = f and f.__scripts.OnUpdate
    if u then
        u(f, 0)
    end
end

return M
