-- tests/Game/State/helpers/rule_trace.lua (refactor lane 9, Pr-2, L1827): the pairing rules Rows.lua's RULES marked
-- while a test ran, and each ticket a row paid ("=cast", "=swing<hand>"), as one string in order. M.on(I) starts a
-- fresh trace on that belief; M.chain(key) returns it for the test to assert (RULES_CAPTURE=<file> appends "key<TAB>chain").
local M = {}
local out = {}

function M.on(I)
    out = {}
    local RULES, x = I.Rows.RULES, I.Tickets.x
    I.Rows.trace = function(what, a)
        if what == "rule" then
            out[#out + 1] = RULES[a][1]
        elseif what == "cast" then
            out[#out + 1] = "=cast"
        elseif what == "swing" then
            out[#out + 1] = "=swing" .. x[a]
        end
    end
end

function M.chain(key)
    local got = table.concat(out, ">")
    local capture = os.getenv("RULES_CAPTURE")
    if capture then
        local f = assert(io.open(capture, "a"))
        f:write(key, "\t", got, "\n")
        f:close()
    end
    return got
end

return M
