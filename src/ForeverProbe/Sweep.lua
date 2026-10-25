-- Sweep.lua: /vsprobe sweep [tag] calls every Hekili facade read still tagged "unprobed" and reports, per read,
-- whether each of its first 4 returns is plain or secret, into the copy box (Copy.lua) and
-- ForeverProbeDB.sweep[tag] (written to disk on /reload).
--   /vsprobe sweep oc   out of combat;   /vsprobe sweep ic   in combat at a dummy.
-- Codes per name: one letter per return (max 4): S secret, n number, s string, b boolean, t table, f function,
-- x nil, u userdata; "-" no returns; "missing" not in _G; "skip" not called (changes state); "err:<msg>" it raised.
local ADDON_NAME, ns = ...

local isSecret = issecretvalue or function() return false end

-- Copied from hekili src/Hekili/Virtual/API/Facade.lua, PASSTHROUGH rows tagged "unprobed" (2026-10-16, 72 names).
local NAMES = {
    "C_AddOns.GetAddOnMetadata", "C_AddOns.IsAddOnLoaded", "C_AddOns.LoadAddOn", "C_ClassColor.GetClassColor",
    "C_ClassTalents.GetActiveConfigID", "C_ClassTalents.GetHeroTalentSpecsForClassSpec", "C_PetBattles.IsInBattle",
    "C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier", "C_PvP.IsWarModeDesired",
    "C_SpecializationInfo.GetTalentInfo", "C_Spell.GetSpellDescription", "C_Spell.GetSpellInfo",
    "C_Spell.GetSpellTexture", "C_Spell.IsSpellDataCached", "C_Spell.IsSpellHarmful", "C_Spell.IsSpellHelpful",
    "C_Spell.IsSpellPassive", "C_Spell.RequestLoadSpellData", "C_SpellBook.FindSpellBookSlotForSpell",
    "C_SpellBook.GetNumSpellBookSkillLines", "C_SpellBook.GetSpellBookItemInfo",
    "C_SpellBook.GetSpellBookSkillLineInfo", "C_SpellBook.IsSpellInSpellBook", "C_SpellBook.IsSpellKnown",
    "C_Texture.GetAtlasInfo", "C_TooltipInfo.GetInventoryItem", "C_TooltipInfo.GetItemByID",
    "C_TooltipInfo.GetSpellByID", "C_VideoOptions.GetCurrentGameWindowSize", "GetBuildInfo", "GetCVar",
    "GetClassInfo", "GetCursorInfo", "GetFrameCPUUsage", "GetFramerate", "GetInstanceInfo", "GetNetStats",
    "GetNumClasses", "GetNumGroupMembers", "GetNumSubgroupMembers", "GetRealmName", "GetSpecializationInfoByID",
    "GetStablePetInfo", "HasOverrideActionBar", "HasVehicleActionBar", "IsInGroup", "IsInInstance",
    "IsInJailersTower", "IsInRaid", "IsMounted", "IsPlayerSpell", "IsResting", "IsSpellKnown",
    "IsSpellKnownOrOverridesKnown", "SecureCmdOptionParse", "SpellIsSelfBuff", "UnitCanAssist",
    "UnitEffectiveLevel", "UnitFactionGroup", "UnitHasVehicleUI", "UnitInParty", "UnitInRaid", "UnitInVehicle",
    "UnitIsConnected", "UnitIsDeadOrGhost", "UnitIsPVP", "UnitIsTrivial", "UnitOnTaxi", "UnitPhaseReason",
    "UnitRace", "UnitSex", "UnitTokenFromGUID",
}

-- Not called: loads code (state change).
local SKIP = { ["C_AddOns.LoadAddOn"] = true }

local SPELL = 100 -- Charge (the user's Warrior knows it)
local GCD = 29515 -- the GCD spell
local ITEM = 5512 -- Healthstone

-- Canned arguments; a function value is called at sweep time for its args. Absent name: no args.
local ARGS = {
    ["C_AddOns.GetAddOnMetadata"] = { "Hekili", "Version" }, -- arg: Hekili may not be installed (then x)
    ["C_AddOns.IsAddOnLoaded"] = { "Hekili" },
    ["C_ClassColor.GetClassColor"] = { "WARRIOR" },
    -- arg: none; Hekili passes (configID, specID); no args may return x or error
    ["C_SpecializationInfo.GetTalentInfo"] = { { tier = 1, column = 1 } }, -- arg: TalentInfoQuery row 1 col 1
    ["C_Spell.GetSpellDescription"] = { SPELL },
    ["C_Spell.GetSpellInfo"] = { SPELL },
    ["C_Spell.GetSpellTexture"] = { SPELL },
    ["C_Spell.IsSpellDataCached"] = { SPELL },
    ["C_Spell.IsSpellHarmful"] = { SPELL },
    ["C_Spell.IsSpellHelpful"] = { SPELL },
    ["C_Spell.IsSpellPassive"] = { GCD }, -- arg: the GCD spell, a non-player spell
    ["C_Spell.RequestLoadSpellData"] = { SPELL }, -- arg: only queues a cache load; returns nothing (expect -)
    ["C_SpellBook.FindSpellBookSlotForSpell"] = { SPELL },
    ["C_SpellBook.GetSpellBookItemInfo"] = function()
        return 1, Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0 -- arg: slot 1, player bank
    end,
    ["C_SpellBook.GetSpellBookSkillLineInfo"] = { 1 },
    ["C_SpellBook.IsSpellInSpellBook"] = { SPELL },
    ["C_SpellBook.IsSpellKnown"] = { SPELL },
    ["C_Texture.GetAtlasInfo"] = { "UI-HUD-ActionBar-IconFrame" }, -- arg: a stock action-bar atlas; x if absent
    ["C_TooltipInfo.GetInventoryItem"] = { "player", 16 }, -- arg: main-hand slot
    ["C_TooltipInfo.GetItemByID"] = { ITEM },
    ["C_TooltipInfo.GetSpellByID"] = { SPELL },
    ["GetCVar"] = { "autoLootDefault" }, -- arg: any stock CVar
    ["GetClassInfo"] = { 1 },
    ["GetFrameCPUUsage"] = function() return UIParent end, -- arg: UIParent; may error without CPU profiling
    ["GetSpecializationInfoByID"] = { 71 }, -- arg: Arms spec ID
    ["GetStablePetInfo"] = { 1 }, -- arg: stable slot 1 (x for a Warrior)
    ["IsPlayerSpell"] = { SPELL },
    ["IsSpellKnown"] = { SPELL },
    ["IsSpellKnownOrOverridesKnown"] = { SPELL },
    ["SecureCmdOptionParse"] = { "[combat] a; b" }, -- arg: a macro conditional; parses only
    ["SpellIsSelfBuff"] = { SPELL },
    ["UnitCanAssist"] = { "player", "target" },
    ["UnitEffectiveLevel"] = { "target" },
    ["UnitFactionGroup"] = { "target" },
    ["UnitHasVehicleUI"] = { "player" },
    ["UnitInParty"] = { "player" },
    ["UnitInRaid"] = { "player" },
    ["UnitInVehicle"] = { "player" },
    ["UnitIsConnected"] = { "target" },
    ["UnitIsDeadOrGhost"] = { "target" },
    ["UnitIsPVP"] = { "target" },
    ["UnitIsTrivial"] = { "target" },
    ["UnitOnTaxi"] = { "player" },
    ["UnitPhaseReason"] = { "target" },
    ["UnitRace"] = { "target" },
    ["UnitSex"] = { "target" },
    -- arg: the target's GUID read just before (if that GUID is secret the call still runs on it)
    ["UnitTokenFromGUID"] = function() return UnitGUID("target") end,
}

local LETTER = { number = "n", string = "s", boolean = "b", table = "t", ["function"] = "f", ["nil"] = "x" }

local function resolve(path)
    local v = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    if type(v) == "function" then return v end
    return nil
end

local function classify(ok, ...)
    if not ok then
        local msg = ...
        if isSecret(msg) then return "err:<secret>" end
        msg = string.gsub(string.sub(tostring(msg), 1, 40), "%s", "_")
        return "err:" .. msg
    end
    local n = select("#", ...)
    if n == 0 then return "-" end
    if n > 4 then n = 4 end
    local code = ""
    for i = 1, n do
        local v = select(i, ...)
        if isSecret(v) then
            code = code .. "S"
        else
            code = code .. (LETTER[type(v)] or "u")
        end
    end
    return code
end

local function sweepOne(name)
    if SKIP[name] then return "skip" end
    local fn = resolve(name)
    if not fn then return "missing" end
    local a = ARGS[name]
    if type(a) == "function" then
        local ok, x, y = pcall(a)
        if not ok then return classify(false, x) end
        return classify(pcall(fn, x, y))
    end
    if a then return classify(pcall(fn, unpack(a))) end
    return classify(pcall(fn))
end

local function sweep(tag)
    if tag == "" then tag = "default" end
    local combat = InCombatLockdown and InCombatLockdown() == true
    local results = {}
    VSCopy("sweep " .. tag .. " combat=" .. tostring(combat) .. " t=" .. string.format("%.1f", GetTime())
        .. " n=" .. #NAMES)
    local line = tag
    local called, skipped = 0, 0
    for i = 1, #NAMES do
        local name = NAMES[i]
        local code = sweepOne(name)
        if code == "skip" then skipped = skipped + 1 else called = called + 1 end
        results[name] = code
        local part = name .. "=" .. code
        if #line + 1 + #part > 238 then
            VSCopy(line)
            line = tag
        end
        line = line .. " " .. part
    end
    VSCopy(line)
    VSCopy("sweep " .. tag .. " done: called=" .. called .. " skipped=" .. skipped .. " (/vscopy to copy)")
    if ForeverProbeDB then
        ForeverProbeDB.sweep = ForeverProbeDB.sweep or {}
        ForeverProbeDB.sweep[tag] = results
    end
    return results
end
ns.Sweep = sweep

SLASH_VSPROBE1 = "/vsprobe"
SlashCmdList.VSPROBE = function(msg)
    local cmd, rest = string.match(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    if cmd == "sweep" then
        sweep(rest)
    else
        print("/vsprobe sweep [tag]: call every unprobed facade read; results to /vscopy and ForeverProbeDB.sweep")
    end
end
