<!--
Purpose: RegisterDisplayStyle, the recommendation record, the WeakAuras bridge.
Type: Reference
Audience: contributors
Prerequisites: [Contributing architecture](Contributing-Architecture).
-->
The **display style and integration interface** is the public way for another addon to draw Hekili Forever's recommendations or react to them. A display style draws one display's queue and is registered with `Hekili:RegisterDisplayStyle`. An integration, such as the built-in WeakAuras bridge, listens to the published recommendation records. This page lists the style interface, the fields of a recommendation record and the WeakAuras event. The full reference is section 7 of [docs/dev/architecture.md](https://github.com/zmsl/hekili/blob/forever/docs/dev/architecture.md).

| Display style interface | |
|---|---|
| Call | `Hekili:RegisterDisplayStyle(name, impl)` |
| Version | `Hekili.DisplayStyleAPI`, 1 as of the current release |
| Built-in styles | Classic (`src/Hekili/UI/Styles/Classic.lua`) and Timeline (`src/Hekili/UI/Styles/Timeline.lua`) |
| Source | `src/Hekili/UI/Styles.lua` |

## RegisterDisplayStyle

Each display names one style, so the Primary display can use Timeline while the Cooldowns display stays Classic. The built-in styles register through the same call as an external one. An addon that adds a style lists Hekili as a dependency in its TOC and calls:

```lua
Hekili:RegisterDisplayStyle("mystyle", {
    api = Hekili.DisplayStyleAPI,
    label = "My Style",
    Build = function(d, conf) return {} end,
    Draw = function(d, conf, out, status) end,
    Tick = function(d, conf, out, now, elapsed) end,
    OnGameEvent = function(d, conf, event, ...) end,
    Clear = function(d) end,
    Perimeter = function(d) return nil end,
    UpdateKeybindings = function(d) end,
    Options = function(id, conf) return {} end,
})
```

The call returns `true` when the style is registered. It returns `false`, with one notice to the player, when `impl.api` is not the current `Hekili.DisplayStyleAPI`, or when `name` is already a core display setting or options tab, such as `style`, `enabled` or `numIcons`. It raises an error when a required member is missing or of the wrong type.

| Member | Required | Called | Does |
|---|---|---|---|
| `api` | Yes | At registration | The interface version the style was written for |
| `label` | Yes | Options | The name in the style dropdown |
| `defaults` | No | At registration | The template of the style's settings, kept per display in `displays[id].<name>` |
| `needs` | No | Subscribing | `{ alts = true }` asks the engine for alternative picks on records 1 and 2, which costs extra simulation |
| `NeedsFor(id, conf)` | No | Subscribing | Answers `needs` per display, in place of the `needs` table |
| `Build(d, conf)` | Yes | Every UI rebuild | Creates or reuses its frames; returns the button list |
| `Draw(d, conf, out, status)` | Yes | On a publish, and on a 0.25 s pulse | Draws the records |
| `Tick(d, conf, out, now, elapsed)` | Yes | Every frame, before `Draw` | Timers, flashes, range |
| `OnGameEvent(d, conf, event, ...)` | Yes | Every display event | Reacts to game events |
| `Clear(d)` | Yes | A style switch, and whenever the display hides | Hides everything the style shows |
| `Perimeter(d)` | Yes | Moving the displays | The left, right, top and bottom frames of the mover backdrop, or nil |
| `UpdateKeybindings(d)` | Yes | Keybinding changes | Redraws keybind text |
| `Options(id, conf)` | Yes | Building the options | The style's option tabs, as new tables on each call |

A registration made after Hekili Forever has loaded still reaches every display: its defaults are added, the options are rebuilt on their next opening, and a display whose profile names the style binds it.

### What a style may read

- `conf`, the display's settings, with the style's own under `conf[name]`. A style never reads another style's settings.
- `out`, the display's published output: `out.count`, `out.version` and the records `out.recs[1]` to `out.recs[out.count]`.
- `d.resolved[i]`, the range, usability, desaturation, glow and target count already worked out for record `i`. Read them there instead of asking the game again.

A style never reads the simulation (`Hekili.State`, `Hekili.Class` or the engine's internals). Inside Hekili Forever a check enforces this; an external style keeps it by convention. `Draw` and `Tick` allocate nothing after the first publish, and `Clear` leaves none of the style's frames shown. `Build` is not run again after `Clear` when the display only hid, so `Draw` must show again what `Clear` hid.

### The button contract

A style can set optional fields on its buttons so that the display's **Modern** layer can draw over them: `b.recIndex` (the record the button draws, 0 for none), `b.isFocus`, `b.Cooldown` (the button's cooldown frame), `b.round` (a round icon) and `b.timersHidden`. A style that sets none of them draws as before and gets no overlays.

## The recommendation record

Each record in `out.recs` describes one recommendation. The fields:

| Field | Meaning |
|---|---|
| `actionName` | The ability's key |
| `actionID` | The ability's spell ID |
| `texture` | Its icon |
| `caption`, `indicator` | The line's caption, and an indicator such as a target swap |
| `focus` | The line's focus tier, or nil ([APL line options](APL-Line-Options#focus)) |
| `label`, `iconOverride` | The line's label and icon override, while their conditions hold |
| `keybind` | The key bound to the ability |
| `offGCD` | The ability is off the global cooldown |
| `time`, `exact_time` | When the recommendation is due: seconds from now, and the game time |
| `delay`, `since`, `wait` | Timing details of the wait before it |
| `resource_type`, `cost` | The resource the ability spends, and how much |
| `resources` | The estimated amount of each resource at that time |
| `busy` | Seconds the ability keeps the player busy: its GCD, or its cast when longer |
| `pack`, `list`, `action`, `script` | The priority, list and entry that chose it |
| `alts` | Up to two alternative picks, filled only when a style asks for `needs.alts` |

The output reuses its record tables. Copy what you need to keep; never hold a reference to a record past the call.

## The WeakAuras bridge

When WeakAuras is loaded, Hekili Forever fires the WeakAuras event `HEKILI_RECOMMENDATION_UPDATE` on every publish of the Primary, AOE, Cooldowns, Defensives and Interrupts displays. Its arguments:

| Argument | Meaning |
|---|---|
| 1 | The display's name, such as `Primary` |
| 2 | The first recommendation's `actionID` |
| 3 | The first recommendation's `indicator` |
| 4 | Always nil (unused) |
| 5 | A payload table: `payload[i]` is a copy of record `i`, and the payload's own fields read record 1 |

The bridge listens passively: a display that is hidden is not computed only for WeakAuras. When a display publishes no recommendation, the event still fires, with empty records. The bridge is in `src/Hekili/Integrations/WeakAuras.lua`.

## See also

- [Reading the displays](Reading-The-Displays)
- [Displays reference](Displays-Reference)
- [Contributing architecture](Contributing-Architecture)
