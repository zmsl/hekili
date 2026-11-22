-- Engine/Sim/AplWarnings.lua
-- Neither health is warned now (FABLE-FOR-OWNER 7): target health reads the hidden-value band
-- (Game/State/Families/TargetHealth.lua, lane B2) and the player's own reads it in combat (Families/Player.lua, lane
-- B3); with no band each falls back to its old read, unwarned. Time to die answers "unknown" (Targets.lua's FOREVER,
-- 3600 s: the fight never ends soon), as a priority written for a long fight expects: unwarned. ROWS is empty; the scan
-- stays for a future secret token. ns.AplSecretToken finds such a token in a condition string; Hekili:LoadScript
-- (Scripts.lua) writes one warning per entry from it. A load-time text scan of the core's (border batch 3, E20): pure
-- Lua, no belief state, no client read, no allocation.

local _, ns = ...
local find, byte = string.find, string.byte

-- { token, subject, what it reads }: a name Hekili's state resolves through a secret value. Qualified tokens come
-- first.
local ROWS = {}

local DOT, UNDERSCORE, LOWER_Z = 46, 95, ("z"):byte()

local function isIdent(b) -- a letter, digit or "_"
    return b ~= nil and (b == UNDERSCORE or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= LOWER_Z))
end

--- The first listed token `condition` reads as a whole name (`pet.health.pct` is not
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
        local s, e = find(condition, token, 1, true)
        while s do
            local before = s > 1 and byte(condition, s - 1) or nil
            if before ~= DOT and not isIdent(before) and not isIdent(byte(condition, e + 1)) then
                return token, row[2], row[3]
            end
            s, e = find(condition, token, e + 1, true)
        end
    end
    return nil
end
