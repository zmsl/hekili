-- tools/wiki/collect/commands.lua: the /hekili commands (Options/ChatCommands.lua's ns.ChatCommands, read in a
-- booted instance) against the reviewed list docs/wiki/data/commands.lua: every handler is public or internal, and
-- only the public ones are published.
local boot = require("tools.wiki.boot")

local M = {}

M.DATA = "docs/wiki/data/commands.lua"

local function data()
    return dofile(M.DATA)
end

--- The command table, the reviewed list and the problems between them (a list of strings).
function M.load()
    local cc = boot.get().ns.ChatCommands
    local d = data()
    local problems = {}
    for name in pairs(cc.handlers) do
        if not d.public[name] and not d.internal[name] then
            problems[#problems + 1] = "command /hekili " .. name .. " is neither public nor internal in " .. M.DATA
        end
    end
    for _, list in ipairs({ "public", "internal" }) do
        for name in pairs(d[list]) do
            if not cc.handlers[name] and not (d.builtin or {})[name] then
                problems[#problems + 1] = ("%s lists /hekili %s as %s, but there is no such command"):format(
                    M.DATA,
                    name,
                    list
                )
            end
        end
    end
    for i, map in ipairs(cc.aliases) do
        for alias, word in pairs(map) do
            if
                not (d.wordAliases[word] or d.hiddenWords[word] or (i == 1 and (d.public[word] or d.internal[word])))
            then
                problems[#problems + 1] = ("alias %s -> %s is neither published nor hidden in %s"):format(
                    alias,
                    word,
                    M.DATA
                )
            end
        end
    end
    table.sort(problems)
    return cc, d, problems
end

--- The published commands and words, as a set: "set", "snap", "cooldowns" ...
function M.words()
    local cc, d = M.load()
    local out = {}
    for name in pairs(d.public) do
        out[name] = true
    end
    for alias, word in pairs(cc.aliases[1]) do
        if d.public[word] then
            out[alias] = true
        end
    end
    return out
end

--- Command, aliases, what it does: one row per public command, in the reviewed list's order.
function M.rows()
    local cc, d = M.load()
    local rows = {}
    for _, name in ipairs(d.order) do
        local aliases = {}
        for alias, word in pairs(cc.aliases[1]) do
            if word == name then
                aliases[#aliases + 1] = "`/hekili " .. alias .. "`"
            end
        end
        table.sort(aliases)
        rows[#rows + 1] = {
            "`/hekili " .. (d.public[name].usage or name) .. "`",
            #aliases > 0 and table.concat(aliases, ", ") or "n/a",
            d.public[name].does,
        }
    end
    return rows
end

--- Word aliases inside a command (`/hekili set cds`): alias, the word it stands for, published words only.
function M.wordRows()
    local cc, d = M.load()
    local rows = {}
    for i = 2, #cc.aliases do
        for alias, word in pairs(cc.aliases[i]) do
            if d.wordAliases[word] then
                rows[#rows + 1] = { "`" .. alias .. "`", "`" .. word .. "`", d.wordAliases[word] }
            end
        end
    end
    table.sort(rows, function(a, b)
        return a[2] .. a[1] < b[2] .. b[1]
    end)
    return rows
end

return M
