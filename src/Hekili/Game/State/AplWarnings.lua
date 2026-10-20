-- Game/State/AplWarnings.lua
-- Target health is secret on Forever (spec §6.5, §7.4): it reads 100 until a health-gated ability pins it
-- (Families/TargetHealth.lua), always on a spec without one. An action-list condition that reads it is dead or
-- misled. Not warned: time to die, which answers "unknown" (Targets.lua's FOREVER, 3600 s: the fight never ends soon),
-- as a priority written for a long fight expects; and the player's health (`health.pct`, ...), which reads the plain
-- value when the client gives one and full while it is secret (Families/Player.lua), so a defensive line never fires
-- on an unknown and a gate on high health passes. VS.AplSecretToken finds
-- such a token in a condition string; Hekili:LoadScript (Scripts.lua) writes one warning per entry from it. Pure Lua:
-- no client read, no allocation.

local _, ns = ...
local VS = ns.VirtualState
local find, byte = string.find, string.byte

local TARGET_HP = "target health is secret"
local ALWAYS_100 = "reads 100 until a health-gated ability pins it, always on a spec without one"

-- { token, subject, what it reads }: the names Hekili's state resolves through target health (State.lua: mt_target's
-- health_*; mt_target_health). Qualified
-- tokens come first; a token ending in "_" is a prefix (a number follows).
local ROWS = {
    { "target.health.pct", TARGET_HP, ALWAYS_100 },
    { "target.health.percent", TARGET_HP, ALWAYS_100 },
    { "target.health.current", TARGET_HP, ALWAYS_100 },
    { "target.health.actual", TARGET_HP, ALWAYS_100 },
    { "target.health_pct", TARGET_HP, ALWAYS_100 },
    { "target.health_percent", TARGET_HP, ALWAYS_100 },
    { "target.health_current", TARGET_HP, ALWAYS_100 },
}

local DOT, UNDERSCORE = 46, 95

local function isIdent(b) -- a letter, digit or "_"
    return b ~= nil and (b == UNDERSCORE or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

--- The first listed health token `condition` reads as a whole name (`pet.health.pct` is not
--- `health.pct`), with what the reading is about and what it reads;
--- nil for anything else, a non-string included. Allocates nothing.
---@param condition any
---@return string? token
---@return string? subject
---@return string? reads
function VS.AplSecretToken(condition)
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
            if before ~= DOT and not isIdent(before) and (prefix or not isIdent(byte(condition, e + 1))) then
                return token, row[2], row[3]
            end
            s, e = find(condition, token, e + 1, true)
        end
    end
    return nil
end
