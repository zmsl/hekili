local _, ns = ...
-- Engine/Settings.lua: the profile port (restructure plan, Task 6). The engine reads its configuration only through
-- Engine.settings; Options owns the AceDB profile and calls Engine.Configure(profile) at load, on every AceDB profile
-- change, and after any setter that writes one of the copied scalars. Subtables are assigned by reference (an edit
-- inside profile.specs[id] or profile.toggles is live with no call); scalars are copied (a scalar edit needs a call).

local Engine = Hekili.Engine

local settings = {
    version = 0,
    -- by reference
    specs = false,
    packs = false,
    toggles = false,
    displays = false,
    performance = false,
    notifications = false,
    -- copied
    enabled = false,
    autoSnapshot = false,
    screenshot = false,
}
Engine.settings = settings

--- Point the engine at `profile`: its subtables by reference, its scalars copied; bumps `settings.version`.
function Engine.Configure(profile)
    settings.specs = profile.specs
    settings.packs = profile.packs
    settings.toggles = profile.toggles
    settings.displays = profile.displays
    settings.performance = profile.performance
    settings.notifications = profile.notifications
    settings.enabled = profile.enabled
    settings.autoSnapshot = profile.autoSnapshot
    settings.screenshot = profile.screenshot
    settings.version = settings.version + 1
end
