-- tests/Forever/forms_spec.lua
-- Every kit declares a form or stance requirement with the engine's `form` field (Engine/Sim/State.lua's IsUsable:
-- "required form (...) not active"), never through `buff` or inside a `usable` body; `nobuff` stays upstream's "not
-- in this form". A form is a content aura key ending `_form` or `_stance` (boundary_lib's nameWords rule), so the
-- check is generic over every kit, the shared content and the races.
local B = require("boundary_lib")

-- The form keys a function's source names (its own lines, tokenized: comments skipped).
local function formsIn(f, forms)
    local info = debug.getinfo(f, "S")
    local path = assert(info.source:match("^@(.+)$"), "a function from a file: " .. info.source)
    local lines, out = {}, {}
    local i = 0
    for line in io.lines(path) do
        i = i + 1
        if i >= info.linedefined and i <= info.lastlinedefined then
            lines[#lines + 1] = line
        end
    end
    for _, t in ipairs(B.tokens(table.concat(lines, "\n"))) do
        if forms[t[2]] then
            out[#out + 1] = t[2]
        end
    end
    return out
end

describe("form and stance requirements", function()
    local c = B.content()
    local forms = {}
    for k in pairs(c.keys) do
        if k:match("_form$") or k:match("_stance$") then
            forms[k] = true
        end
    end

    it("finds the kits' forms and abilities", function()
        assert.is_true(next(forms) ~= nil)
        assert.is_true(#c.abilities > 100, #c.abilities)
    end)

    it("are the `form` field: no `buff` names a form, no `usable` reads one", function()
        local bad = {}
        for _, a in ipairs(c.abilities) do
            local key, d, where = a[1], a[2], a[3]
            if type(d) == "table" then
                local name = where .. " " .. tostring(key)
                if type(d.buff) == "string" and forms[d.buff] then
                    bad[#bad + 1] = name .. ": buff = " .. d.buff
                elseif type(d.buff) == "function" and #formsIn(d.buff, forms) > 0 then
                    bad[#bad + 1] = name .. ": buff function names " .. table.concat(formsIn(d.buff, forms), ", ")
                end
                if type(d.usable) == "function" and #formsIn(d.usable, forms) > 0 then
                    bad[#bad + 1] = name .. ": usable names " .. table.concat(formsIn(d.usable, forms), ", ")
                end
                if type(d.form) == "string" then
                    assert.is_true(forms[d.form] ~= nil, name .. ": form = " .. d.form .. " is no form aura")
                end
            end
        end
        table.sort(bad)
        assert.are.same({}, bad)
    end)
end)
