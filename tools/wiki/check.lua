-- tools/wiki/check.lua: the checks `make wiki-check` runs over the pages, as plain functions of the page texts and the
-- facts the collectors gather (so the tests drive them with small fixtures). Each returns a sorted list of messages.
-- `pages` maps a page name (its file name without .md: "Home", "_Sidebar") to its text.
local markers = require("tools.wiki.markers")

local M = {}

local function sorted(t)
    table.sort(t)
    return t
end

-- `s` without HTML comments, fenced code and the generated regions (text that comes from the code, not a writer).
local function prose(s)
    s = s:gsub("<!%-%- GENERATED:.-<!%-%- /GENERATED %-%->", "")
    s = s:gsub("<!%-%-.-%-%->", "")
    s = s:gsub("\n```.-\n```", "\n")
    return s
end

-- `s` without inline code spans.
local function nocode(s)
    return (s:gsub("`[^`\n]*`", "``"))
end

--- Markers that are malformed or that the manifest does not name (`known` is a set of table names). Tables are filled
--- only at publish time, so the check never compares a region's body.
function M.markers(pages, known)
    local out = {}
    for name, s in pairs(pages) do
        local ok, names = pcall(markers.names, s, name)
        if not ok then
            out[#out + 1] = tostring(names)
        else
            for _, region in ipairs(names) do
                if not known[region] then
                    out[#out + 1] = ("%s: GENERATED:%s is not in tools/wiki/manifest.lua"):format(name, region)
                end
            end
        end
    end
    return sorted(out)
end

--- GitHub's anchor for a heading.
function M.slug(heading)
    return (heading:lower():gsub("[^%w%- ]", ""):gsub(" ", "-"))
end

local function anchors(s)
    local out = {}
    for h in ("\n" .. s .. "\n"):gmatch("\n#+ ([^\n]+)") do
        out[M.slug(h)] = true
    end
    return out
end

M.HOSTS = { ["github.com"] = true, ["wowsims.com"] = true, ["www.curseforge.com"] = true, ["curseforge.com"] = true }

--- Dead page links and anchors, links to other sites, and (as warnings) images not yet in images/.
--- `exists(path)` answers whether a file under docs/wiki/ exists.
function M.links(pages, exists)
    local errors, warnings = {}, {}
    for name, s in pairs(pages) do
        local text = s:gsub("<!%-%-.-%-%->", ""):gsub("\n```.-\n```", "\n")
        for bang, target in text:gmatch("(!?)%[[^%]]*%]%(([^)%s]+)[^)]*%)") do
            local host = target:match("^https?://([^/]+)")
            if bang == "!" then
                if not exists(target) then
                    warnings[#warnings + 1] = ("%s: image %s is not in docs/wiki/ yet"):format(name, target)
                end
            elseif host then
                if not M.HOSTS[host] then
                    errors[#errors + 1] = ("%s: a link to %s, not wowsims.com, CurseForge or GitHub"):format(
                        name,
                        target
                    )
                elseif target:lower():match("github%.com/hekili/") and name ~= "_Footer" then
                    errors[#errors + 1] = ("%s: a link to the original project (only the footer credits it)"):format(
                        name
                    )
                end
            elseif not target:match("^mailto:") then
                local page, anchor = target:match("^([^#]*)#?(.*)$")
                local ts = page == "" and s or pages[page]
                if not ts then
                    errors[#errors + 1] = ("%s: a link to %s, which is no page"):format(name, target)
                elseif anchor ~= "" and not anchors(ts)[anchor] then
                    errors[#errors + 1] = ("%s: a link to %s, which is no heading"):format(name, target)
                end
            end
        end
    end
    return sorted(errors), sorted(warnings)
end

-- A bold span reads as a UI label when it is Title Case (its first word and every word of four letters or more start
-- with a capital), is not a lead-in (ending in, or followed by, a colon or full stop) and is not the page's title
-- term (the first bold before the first heading).
local function labelLike(span, after)
    if span:match("[:%.]$") or after == ":" then
        return false
    end
    if not span:match("^%u") then
        return false
    end
    for w in span:gmatch("%a+") do
        if #w >= 4 and not w:match("^%u") then
            return false
        end
    end
    return true
end

--- Bold UI labels and bold option paths (**/hekili > A > *placeholder* > B**) that name no option. `labels` is the
--- set of option labels in the walked tree, `enus` the set of English strings in Locales/enUS.lua (both stripped).
function M.labels(pages, labels, enus)
    local out = {}
    local function check(name, label, what)
        if not labels[label] then
            out[#out + 1] = ("%s: %s **%s** names no option"):format(name, what, label)
        elseif not enus[label] then
            out[#out + 1] = ("%s: %s **%s** is not an English string in Locales/enUS.lua"):format(name, what, label)
        end
    end
    for name, s in pairs(pages) do
        if name:sub(1, 1) ~= "_" then
            local text = nocode(prose(s))
            local firstHeading = ("\n" .. text):find("\n## ") or (#text + 1)
            local first = true
            for at, span, after in text:gmatch("()%*%*(.-)%*%*(.?)") do
                local title = first and at < firstHeading
                first = false
                if span:match("^/hekili >") then
                    for seg in (span .. " >"):gmatch("%s*(.-)%s*>") do
                        if seg ~= "/hekili" and not seg:match("^%*.*%*$") then
                            check(name, seg, "the path segment")
                        end
                    end
                elseif not title and labelLike(span, after) then
                    check(name, span, "the label")
                end
            end
        end
    end
    return sorted(out)
end

--- Chat commands in code (`/hekili x`, `/hek x`) whose first word is not a published command or alias.
function M.commands(pages, words)
    local out = {}
    for name, s in pairs(pages) do
        local text = s:gsub("<!%-%- GENERATED:.-<!%-%- /GENERATED %-%->", "")
        for code in text:gmatch("`([^`\n]+)`") do
            local word = code:match("^/hek%a* ([%w_]+)")
            if word and not words[word:lower()] then
                out[#out + 1] = ("%s: `%s` is not a published command"):format(name, code)
            end
        end
    end
    return sorted(out)
end

-- What no page may hold: local paths, the hidden switch, internal ruling and ledger IDs, links to Claude artifacts.
M.BANNED = {
    { "/home/", "a home-directory path" },
    { "~/src", "a home-directory path" },
    { "%a:\\Users", "a Windows user path" },
    { "\\\\wsl", "a WSL path" },
    { "cdmOff", "a hidden switch" },
    { "claude%.ai", "a link to a Claude artifact" },
    { "%f[%w]L%d%d%d%f[%W]", "an internal ledger ID" },
    { "%f[%w]R%d%d%f[%W]", "an internal ruling ID" },
}

--- Banned content anywhere in a page, comments included.
function M.banned(pages)
    local out = {}
    for name, s in pairs(pages) do
        local n = 0
        for line in (s .. "\n"):gmatch("([^\n]*)\n") do
            n = n + 1
            for _, b in ipairs(M.BANNED) do
                if line:find(b[1]) then
                    out[#out + 1] = ("%s:%d: %s"):format(name, n, b[2])
                end
            end
        end
    end
    return sorted(out)
end

--- Placeholders still open (TODO-SCREENSHOT, TODO-LINK, TODO): warnings, never failures.
function M.todos(pages)
    local out = {}
    for name, s in pairs(pages) do
        local n = 0
        for line in (s .. "\n"):gmatch("([^\n]*)\n") do
            n = n + 1
            local what = line:match("(TODO%-%u+)") or line:match("%f[%w](TODO)%f[%W]")
            if what then
                out[#out + 1] = ("%s:%d: %s"):format(name, n, what)
            end
        end
    end
    return sorted(out)
end

return M
