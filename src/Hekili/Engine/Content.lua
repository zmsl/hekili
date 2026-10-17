-- Engine/Content.lua
-- The class content loader (restructure plan, Task 8). The Forever content lives in separate addons: Hekili_Forever
-- (the shared and race content, a hard dependency of every pack, so the client loads it after the core) and one
-- load-on-demand pack per class, Hekili_Forever_<Class>. At OnEnable (PLAYER_LOGIN, before PLAYER_ENTERING_WORLD's
-- SpecializationChanged picks the spec up) ns.LoadContent loads the player's class pack when its TOC's
-- X-Hekili-ContentAPI is this core's CONTENT_API: the version of the content surface (the Register* API, Hekili.Client,
-- the belief's environment names), bumped only when that surface changes. Missing pack, mismatch or failed load: one
-- notice, and the core runs with no class spec.
-- Pattern after Taco Dog Forever's Boot.lua class-pack loader (a pcall'd LoadAddOn, a notice for a class without one).

local addon, ns = ...
local Facade = ns.Facade
local C_AddOns, UnitClass = Facade.C_AddOns, Facade.UnitClass
local Hekili = _G[addon]

local CONTENT_API = 1

--- Loads the player's class pack (once, from OnEnable); Notifies when it is not installed, declares another content
--- API (then it is not loaded) or fails to load.
function ns.LoadContent()
    local token = select(2, UnitClass("player"))
    if type(token) ~= "string" or token == "" then
        return
    end
    local class = token:sub(1, 1) .. token:sub(2):lower() -- WARRIOR -> Warrior
    local name = "Hekili_Forever_" .. class

    -- an addon that is not installed answers nil, or raises on some clients
    local ok, api = pcall(C_AddOns.GetAddOnMetadata, name, "X-Hekili-ContentAPI")
    if not ok or api == nil then
        Hekili:Notify("no Forever pack for " .. class .. "; install " .. name)
        return
    end
    if tonumber(api) ~= CONTENT_API then
        Hekili:Notify(
            name
                .. " is for content API "
                .. tostring(api)
                .. ", this Hekili for "
                .. CONTENT_API
                .. "; update the older one"
        )
        return
    end

    local loaded, reason
    ok, loaded, reason = pcall(C_AddOns.LoadAddOn, name)
    if not ok then
        reason = loaded
    end
    if not ok or not loaded then
        Hekili:Notify("could not load " .. name .. " (" .. tostring(reason) .. ")")
        return
    end
    Hekili:RegisterSpecDefaults() -- Options/Profile.lua: the new spec's profile defaults
end
