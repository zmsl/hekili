-- tools/wiki/text.lua: the game's text as plain Markdown table text.
local M = {}

--- `s` without the client's escapes (colours, textures, atlases, the |W|w no-wrap pair), on one line.
function M.strip(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|[Ww]", "")
    s = s:gsub("|n", " "):gsub("\n", " "):gsub(" ?%(%s*%)", ""):gsub("%s+", " ") -- "()": an icon's place
    return (s:gsub("^ ", ""):gsub(" $", ""))
end

--- The first sentence of `s` (stripped): up to the first ". ", "? " or "! ", or all of it.
function M.sentence(s)
    s = M.strip(s)
    local i = s:find("[%.%?!] ")
    if i then
        s = s:sub(1, i)
    end
    return s
end

--- `s` safe inside a Markdown table cell; "n/a" for an empty one.
function M.cell(s)
    s = tostring(s == nil and "" or s):gsub("\n", " "):gsub("|", "\\|")
    if s == "" then
        return "n/a"
    end
    return s
end

--- `s` in code style.
function M.code(s)
    return "`" .. tostring(s) .. "`"
end

--- A Markdown table: `headers` (strings) and `rows` (lists of cell strings, escaped by M.cell).
function M.table(headers, rows)
    local out = { "| " .. table.concat(headers, " | ") .. " |" }
    local rule = {}
    for i = 1, #headers do
        rule[i] = "---"
    end
    out[2] = "|" .. table.concat(rule, "|") .. "|"
    for _, r in ipairs(rows) do
        local cells = {}
        for i = 1, #headers do
            cells[i] = M.cell(r[i])
        end
        out[#out + 1] = "| " .. table.concat(cells, " | ") .. " |"
    end
    return table.concat(out, "\n")
end

--- A number with up to `places` decimals, trailing zeros dropped ("10", "0.25").
function M.num(n, places)
    if type(n) ~= "number" then
        return n ~= nil and tostring(n) or nil
    end
    local s = ("%." .. (places or 2) .. "f"):format(n)
    if not s:find("%.") then
        return s
    end
    return (s:gsub("0+$", ""):gsub("%.$", ""))
end

return M
