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

local CONTENT_API = 1

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
            .. ", this Hekili for "
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
