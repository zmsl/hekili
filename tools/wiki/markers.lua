-- tools/wiki/markers.lua: the generated regions of a wiki page. A page asks for a table with the pair
--   <!-- GENERATED:<name> -->
--   <!-- /GENERATED -->
-- (each on its own line); rewrite() replaces only the lines between the pair and never reads or writes the rest.
local M = {}

M.NOTE = "<!-- Do not edit: written by `make wiki-build` (tools/wiki/manifest.lua). -->"

local OPEN = "^<!%-%- GENERATED:([%w_%-]+) %-%->$"
local CLOSE = "^<!%-%- /GENERATED %-%->$"

local function lines(text)
    local out = {}
    for l in (text .. "\n"):gmatch("([^\n]*)\n") do
        out[#out + 1] = l
    end
    if text:sub(-1) == "\n" then
        out[#out] = nil -- the final newline ends the last line; it opens no new one
    end
    return out
end

--- The region names of `text`, in order (a name may repeat). Raises on a nested, unclosed or stray marker.
function M.names(text, where)
    local out, open = {}, nil
    for i, l in ipairs(lines(text)) do
        local name = l:match(OPEN)
        if name then
            assert(
                not open,
                ("%s:%d: GENERATED:%s opens inside GENERATED:%s"):format(where or "?", i, name, open or "")
            )
            open = name
            out[#out + 1] = name
        elseif l:match(CLOSE) then
            assert(open, ("%s:%d: a /GENERATED with no GENERATED before it"):format(where or "?", i))
            open = nil
        elseif l:lower():find("<!%-%-%s*/?generated") and l ~= M.NOTE then
            error(("%s:%d: a malformed GENERATED marker: %s"):format(where or "?", i, l), 0)
        end
    end
    assert(not open, ("%s: GENERATED:%s is never closed"):format(where or "?", open or ""))
    return out
end

--- `text` with each region's body replaced by render(name) (a string, no trailing newline), after the do-not-edit
--- note. Everything outside the regions is kept byte for byte.
function M.rewrite(text, render, where, bare)
    M.names(text, where) -- the shape first: a broken pair never half-rewrites a page
    local out, skipping = {}, false
    for _, l in ipairs(lines(text)) do
        local name = l:match(OPEN)
        if name then
            out[#out + 1] = l
            if not bare then
                out[#out + 1] = M.NOTE
            end
            local body = render(name)
            if body ~= "" then
                out[#out + 1] = body
            end
            skipping = true
        elseif skipping and l:match(CLOSE) then
            out[#out + 1] = l
            skipping = false
        elseif not skipping then
            out[#out + 1] = l
        end
    end
    local s = table.concat(out, "\n")
    if text:sub(-1) == "\n" then
        s = s .. "\n"
    end
    return s
end

--- `text` with every region emptied (the committed form: the markers alone, no note, no body).
function M.strip(text, where)
    return M.rewrite(text, function()
        return ""
    end, where, true)
end

return M
