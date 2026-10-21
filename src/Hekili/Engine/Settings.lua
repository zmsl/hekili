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
    specChoice = false,
    specMigrated = false,
    -- copied
    enabled = false,
    autoSnapshot = false,
    screenshot = false,
}
Engine.settings = settings
-- The scenario the settings' defaults are for: nil in game; "sim" under the test harness (the replay and the loops:
-- wowsims's boss, one target, full buffs), where a setting registered with `sim` defaults to that value instead.
Engine.scenario = nil

--- The default a setting entry (Spec.lua RegisterSetting's { name, default, sim, info }) fills an unset profile value
--- with: its `sim` under `Engine.scenario == "sim"` when it has one, else its `default`.
function Engine.SettingDefault(entry)
    if Engine.scenario == "sim" and entry.sim ~= nil then -- an `if`: `sim` may be false
        return entry.sim
    end
    return entry.default
end

--- Point the engine at `profile`: its subtables by reference, its scalars copied; bumps `settings.version`.
function Engine.Configure(profile)
    settings.specs = profile.specs
    settings.packs = profile.packs
    settings.toggles = profile.toggles
    settings.displays = profile.displays
    settings.performance = profile.performance
    settings.notifications = profile.notifications
    settings.specChoice = profile.specChoice
    settings.specMigrated = profile.specMigrated
    settings.enabled = profile.enabled
    settings.autoSnapshot = profile.autoSnapshot
    settings.screenshot = profile.screenshot
    settings.version = settings.version + 1
end

--- The settings group `group` (range, flash, keybindings: what the engine and the shared resolve act on) of the style
--- `display` (a display's config) draws with: `display[ style ][ group ]`, or classic's when that style offers none.
function Engine.StyleGroup(display, group)
    local own = display[display.style or "classic"]
    local g = type(own) == "table" and own[group]
    if type(g) == "table" then
        return g
    end
    return display.classic[group]
end
