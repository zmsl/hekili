-- tests/Game/State/helpers/upvals.lua
-- A family's private state, reached through its functions' upvalues (debug library): the reset-matrix specs
-- (scoped_spec.lua) read and seed a file's local arrays on any tree, before or after a refactor, with no export.
local M = {}

-- Walks `roots` and every function they hold as an upvalue, staying inside functions defined in a file whose path
-- ends with `suffix`; calls visit(f, i, name, value) for each upvalue.
local function walk(suffix, roots, visit)
    local seen = {}
    local function go(f)
        if seen[f] then
            return
        end
        seen[f] = true
        local src = debug.getinfo(f, "S").source
        if src:sub(-#suffix) ~= suffix then
            return
        end
        local i = 1
        while true do
            local name, v = debug.getupvalue(f, i)
            if not name then
                break
            end
            if visit(f, i, name, v) then
                return true
            end
            if type(v) == "function" then
                if go(v) then
                    return true
                end
            end
            i = i + 1
        end
    end
    for _, f in ipairs(roots) do
        if go(f) then
            return
        end
    end
end

--- name -> the first upvalue of that name (any type) found from `roots` inside the file.
function M.all(suffix, roots)
    local out = {}
    walk(suffix, roots, function(_, _, name, v)
        if out[name] == nil then
            out[name] = v
        end
    end)
    return out
end

--- Sets the upvalue `name` (shared by every closure of the file that holds it) to `value`.
function M.set(suffix, roots, name, value)
    local done = false
    walk(suffix, roots, function(f, i, n)
        if n == name then
            debug.setupvalue(f, i, value)
            done = true
            return true
        end
    end)
    assert(done, "no upvalue " .. name)
end

--- The handlers registered in `list` whose function is defined in the file ending with `suffix`.
function M.handlers(list, suffix)
    local out = {}
    for _, f in ipairs(list) do
        local src = debug.getinfo(f, "S").source
        if src:sub(-#suffix) == suffix then
            out[#out + 1] = f
        end
    end
    return out
end

return M
