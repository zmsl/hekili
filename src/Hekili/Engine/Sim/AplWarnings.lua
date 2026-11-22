-- Engine/Sim/AplWarnings.lua
-- An action-list condition reading the player's own health (`health.pct`, ...; owner L1462) is dead or misled: the
-- client hides it in combat, where it reads full (Families/Player.lua), so a low-health check never passes there. Not
-- warned: target health, read from the hidden-value band (Game/State/Families/TargetHealth.lua, hidden-values lane
-- B2; with no band it falls back to the health gates, unwarned: FABLE-FOR-OWNER 7), and time to die, which answers
-- "unknown" (Targets.lua's FOREVER, 3600 s: the fight never ends soon), as a priority written for a long fight expects. ns.AplSecretToken finds such a token in a condition string; Hekili:LoadScript (Scripts.lua)
-- writes one warning per entry from it. A load-time text scan of the core's (border batch 3, E20): pure Lua, no
-- belief state, no client read, no allocation.

local _, ns = ...
local find, byte = string.find, string.byte

local OWN_HP = "your health is hidden in combat"
local NEVER = "your health reads full in combat, so a low-health check never passes there"

-- { token, subject, what it reads }: the names Hekili's state resolves through the player's health (state.health).
-- Qualified tokens come first; a token ending in "_" is a prefix (a number follows).
local ROWS = {
    { "health.pct", OWN_HP, NEVER },
    { "health.percent", OWN_HP, NEVER },
    { "health.current", OWN_HP, NEVER },
    { "health.actual", OWN_HP, NEVER },
    { "health.deficit", OWN_HP, NEVER },
    { "health", OWN_HP, NEVER, true }, -- bare: Scripts.lua expands it to health.current; not health.max
}

local DOT, UNDERSCORE, LOWER_Z = 46, 95, ("z"):byte()

local function isIdent(b) -- a letter, digit or "_"
    return b ~= nil and (b == UNDERSCORE or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= LOWER_Z))
end

--- The first listed health token `condition` reads as a whole name (`pet.health.pct` is not
--- `health.pct`), with what the reading is about and what it reads;
--- nil for anything else, a non-string included. Allocates nothing.
---@param condition any
---@return string? token
---@return string? subject
---@return string? reads
function ns.AplSecretToken(condition)
    if type(condition) ~= "string" then
        return nil
    end
    for i = 1, #ROWS do
        local row = ROWS[i]
        local token = row[1]
        local prefix = byte(token, #token) == UNDERSCORE
        local s, e = find(condition, token, 1, true)
        while s do
            local before = s > 1 and byte(condition, s - 1) or nil
            if before ~= DOT and not isIdent(before) and (prefix or not isIdent(byte(condition, e + 1)))
                and not (row[4] and byte(condition, e + 1) == DOT) then
                return token, row[2], row[3]
            end
            s, e = find(condition, token, e + 1, true)
        end
    end
    return nil
end
