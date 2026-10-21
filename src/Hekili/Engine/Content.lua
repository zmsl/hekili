-- Engine/Content.lua
-- The class content loader (restructure plan, Task 8). The Forever content lives in separate addons, all
-- load-on-demand: Hekili_Shared (the shared and race content, a dependency of every pack) and one pack per class,
-- Hekili_<Class>. At OnInitialize, before InitializeProfile, ns.LoadContent loads Hekili_Shared itself first
-- (a class with no pack still gets the shared and race content), then the player's class pack when its TOC's
-- X-Hekili-ContentAPI is this core's CONTENT_API: the version of the content surface (the Register* API,
-- Hekili.Client, the belief's environment names), bumped only when that surface changes. So the profile's defaults
-- (GetDefaults) and OnInitialize's RestoreDefaults see the class's spec and packs, as when the class files were in the
-- core's TOC. Missing pack, mismatch or failed load: one notice, shown by ns.ContentNotice at OnEnable (Hekili:Notify
-- reads the profile, which does not exist yet), and the core runs with no class spec.
-- Pattern after Taco Dog Forever's Boot.lua class-pack loader (its shared data addon is load-on-demand and loaded
-- explicitly before the class pack; a pcall'd LoadAddOn; a notice for a class without a pack).

local addon, ns = ...
local Facade = ns.Facade
local C_AddOns, UnitClass = Facade.C_AddOns, Facade.UnitClass
local Hekili = _G[addon]

-- 2 (2026-10-18): the ability fields `ladder` and `missable`, Shared:RegisterStateExpr, the aura fields `overlay`,
-- `isStealthed` and `weaponEnchant`, and Hekili_Shared's main_hand_enchant and off_hand_enchant pseudo-auras.
-- 3 (2026-10-19): a resource meta's `fsr` (the five-second rule's parts) and a regen entry's `mult`.
-- 4 (2026-10-19): the `now` verb `summonTotem` (Families/Now.lua), Hekili's signature.
-- 5 (2026-10-19): the `now` verb `summonPet` (Families/Now.lua), RegisterPets' `cap` (a counted guardian), the
-- simulation's `pet.<key>.count`, the ability field `rangedSwing` and the simulation's swings.ranged_actual,
-- swings.ranged_speed, swings.ranged_projected and swing.ranged.
-- 6 (2026-10-2x): Hekili:NewClass (one kit, one spec per talent tree, ids of the core's), RegisterTalents' first field
-- is the talent tree, kit:RegisterSetting's trailing spec keys (per-spec plan).
-- 7 (2026-10-2x): kit:RetirePacks (wowsims packs plan, Task 1).
-- 8 (2026-10-20): the ability field `refundOnAvoid` and a resource meta's number `refundOnAvoid` (central fix 7): an
-- older core's RegisterResource setfenv's every meta value, and a number raises there.
--   Since then, without a bump: the ability field `spendBase` (central fix 22); an older core ignores the key and
--   prices such a cost at or above 1 as points, silently.
local CONTENT_API = 8

local done, notice = false, nil

-- LoadAddOn(name) through a pcall (some clients raise): nil when it loaded, else the notice.
local function load(name)
    local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, name)
    if not ok then
        reason = loaded
    end
    if not ok or not loaded then
        return "could not load " .. name .. " (" .. tostring(reason) .. ")"
    end
end

--- Loads Hekili_Shared, then the player's class pack, once per session (OnInitialize, its only caller; a later call
--- does nothing). Keeps a notice when the shared content fails to load (then no pack is tried: it depends on it), the
--- class cannot be read, or the pack is not installed, declares another content API (then it is not loaded) or fails
--- to load.
function ns.LoadContent()
    if done then
        return
    end
    done = true
    notice = load("Hekili_Shared")
    if notice then
        return
    end
    local token = select(2, UnitClass("player"))
    if type(token) ~= "string" or token == "" then
        notice = "could not read your class at load; /reload" -- OnInitialize runs once, so nothing retries
        return
    end
    local class = token:sub(1, 1) .. token:sub(2):lower() -- WARRIOR -> Warrior
    local name = "Hekili_" .. class

    -- an addon that is not installed answers nil, or raises on some clients
    local ok, api = pcall(C_AddOns.GetAddOnMetadata, name, "X-Hekili-ContentAPI")
    if not ok or api == nil then
        notice = "no Forever pack for " .. class .. "; install " .. name
        return
    end
    if tonumber(api) ~= CONTENT_API then
        notice = name
            .. " is for content API "
            .. tostring(api)
            .. ", this Hekili Forever for "
            .. CONTENT_API
            .. "; update the older one"
        return
    end

    notice = load(name)
end

--- Shows LoadContent's notice, once (OnEnable: the profile and the notice frame exist by then).
function ns.ContentNotice()
    if notice then
        Hekili:Notify(notice)
        notice = nil
    end
end
