-- Game/State/AplWarnings.lua
-- Target and player health are secret on Forever (spec §6.5, §7.4): the player's reads a constant; the target's reads
-- 100 until a health-gated ability pins it (Families/TargetHealth.lua), always on a spec without one; time to die is
-- not modelled, and for a few seconds after a pin Hekili's own tracker derives a transient junk value from that jump.
-- An action-list condition that reads them is dead or misled. VS.AplSecretToken finds
-- such a token in a condition string; Hekili:LoadScript (Scripts.lua) writes one warning per entry from it. Pure Lua:
-- no client read, no allocation.

local _, ns = ...
local VS = ns.VirtualState
local find, byte = string.find, string.byte

local TARGET_HP = "target health is secret"
local PLAYER_HP = "player health is secret"
local TTD = "time to die is not modelled"
local ALWAYS_100 = "reads 100 until a health-gated ability pins it, always on a spec without one"
local ALWAYS_DEFAULT = "reads a fixed default, or a transient junk value for a few seconds after a target health pin"
local MAX_WHILE = "reads the health maximum while player health is unreadable"
local PCT_WHILE = "reads 100 while player health is unreadable"
local ZERO_WHILE = "reads 0 while player health is unreadable"

-- { token, subject, what it reads }: the names Hekili's state resolves through health or time to die (State.lua:
-- mt_state's fight_remains, time_to_die, time_to_pct_, longest_ttd, shortest_ttd, expected_combat_length;
-- mt_target's health_*, time_to_die, time_to_pct_, real_ttd, true_ttd; mt_target_health; state.health). Qualified
-- tokens come first; a token ending in "_" is a prefix (a number follows).
local ROWS = {
    { "target.health.pct", TARGET_HP, ALWAYS_100 },
    { "target.health.percent", TARGET_HP, ALWAYS_100 },
    { "target.health.current", TARGET_HP, ALWAYS_100 },
    { "target.health.actual", TARGET_HP, ALWAYS_100 },
    { "target.health_pct", TARGET_HP, ALWAYS_100 },
    { "target.health_percent", TARGET_HP, ALWAYS_100 },
    { "target.health_current", TARGET_HP, ALWAYS_100 },
    { "target.time_to_die", TTD, ALWAYS_DEFAULT },
    { "target.time_to_pct_", TTD, ALWAYS_DEFAULT },
    { "target.real_ttd", TTD, ALWAYS_DEFAULT },
    { "target.true_ttd", TTD, ALWAYS_DEFAULT },
    { "health.pct", PLAYER_HP, PCT_WHILE },
    { "health.percent", PLAYER_HP, PCT_WHILE },
    { "health.current", PLAYER_HP, MAX_WHILE },
    { "health.actual", PLAYER_HP, MAX_WHILE },
    { "health.deficit", PLAYER_HP, ZERO_WHILE },
    { "health.deficit_pct", PLAYER_HP, ZERO_WHILE },
    { "health.deficit_percent", PLAYER_HP, ZERO_WHILE },
    { "time_to_die", TTD, ALWAYS_DEFAULT },
    { "interpolated_fight_remains", TTD, ALWAYS_DEFAULT },
    { "fight_remains", TTD, ALWAYS_DEFAULT },
    { "time_to_pct_", TTD, ALWAYS_DEFAULT },
    { "longest_ttd", TTD, ALWAYS_DEFAULT },
    { "shortest_ttd", TTD, ALWAYS_DEFAULT },
    { "expected_combat_length", TTD, ALWAYS_DEFAULT },
}

local DOT, UNDERSCORE = 46, 95

local function isIdent(b) -- a letter, digit or "_"
    return b ~= nil and (b == UNDERSCORE or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

--- The first listed health or time-to-die token `condition` reads as a whole name (`pet.health.pct` is not
--- `health.pct`, `time_to_die_x` is not `time_to_die`), with what the reading is about and what it reads;
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
