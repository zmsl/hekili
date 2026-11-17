<!--
Purpose: The public functions and events another addon or a WeakAura can use, with signatures and examples.
Type: Reference
Audience: addon and WeakAura authors
Prerequisites: [Integration overview](Integration-Overview).
-->
The **integration reference** lists every function and event of Hekili Forever's integration surface, with its arguments, what it returns, when it runs and an example. The [Integration overview](Integration-Overview) explains what the surface promises and how to detect Hekili Forever. Nothing on this page is generated.

| Name | Kind | Source |
|---|---|---|
| `Hekili:RegisterDisplayStyle` | Function | `src/Hekili/UI/Styles.lua` |
| `Hekili.DisplayStyleAPI` | Number | `src/Hekili/UI/Styles.lua` |
| `Hekili:RegisterSnapshotListener` | Function | `src/Hekili/Engine/Snapshot.lua` |
| `Hekili:UnregisterSnapshotListener` | Function | `src/Hekili/Engine/Snapshot.lua` |
| `Hekili:RegisterRecommendationListener` | Function | `src/Hekili/Integrations/Recommendations.lua` |
| `Hekili:UnregisterRecommendationListener` | Function | `src/Hekili/Integrations/Recommendations.lua` |
| `HEKILI_RECOMMENDATION_UPDATE` | WeakAuras event | `src/Hekili/Integrations/Recommendations.lua` |
| `Hekili:GetToggleState` | Function | `src/Hekili/Options/Options.lua` |
| `HEKILI_TOGGLE` | WeakAuras event | `src/Hekili/Options/Options.lua` |
| `Hekili.IsForever` | Function | `src/Hekili/Hekili.lua` |
| `Hekili.Version` | String | `src/Hekili/Hekili.lua` |
| `Hekili` (LibDataBroker) | Data source name | `src/Hekili/UI/UI.lua` |

## Display styles

`Hekili:RegisterDisplayStyle(name, impl)` registers a display style: the code that draws one display's recommendations. It returns `true` when the style is registered and `false` when it is refused. `Hekili.DisplayStyleAPI` is the interface version, 1 in this release. [Contributing display styles and integrations](Contributing-Display-Styles-And-Integrations#registerdisplaystyle) describes every member of `impl`, the button contract and the fields of a recommendation record.

## RegisterSnapshotListener

`Hekili:RegisterSnapshotListener(fn)` adds `fn` to the functions called each time a snapshot is taken: with `/hekili snapshot`, its keybinding, or by pausing the displays. A snapshot is the report the **Snapshots** tab shows ([Reading a snapshot](Reading-A-Snapshot)). The listener can add its own text to that report.

| Part | Value |
|---|---|
| `fn` | A function. Anything else raises an error. |
| Returns | Nothing |
| Registering the same `fn` again | Has no effect |
| Called | Once per snapshot, after the snapshot's records are stored, in the order the listeners were registered |

The listener is called as `fn(index, record, isAuto)`:

| Argument | Meaning |
|---|---|
| `index` | The position of the snapshot's first record in `Hekili.Snapshots`. The snapshot has one record per display; the others follow it, up to `#Hekili.Snapshots`. |
| `record` | That first record. `record.log` is its text, the report the Snapshots tab shows. |
| `isAuto` | `false` for a snapshot taken by the player |

- A string the listener returns is added to the text of every record of the snapshot, under a `## External` heading. Each listener's text is cut at 4000 characters.
- The listener runs inside `pcall`. When it raises an error, the snapshot is kept and the error message is added under `## External` in place of its text.
- A snapshot that stores no record calls no listener.

Example, an addon that adds its own state to every snapshot:

```lua
-- In an addon with "## Dependencies: Hekili" in its TOC
local function AddMyState(index, record, isAuto)
    return "MyAddon: tracking " .. tostring(MyAddonDB and MyAddonDB.tracking)
end

Hekili:RegisterSnapshotListener(AddMyState)
```

## UnregisterSnapshotListener

`Hekili:UnregisterSnapshotListener(fn)` removes a listener added with `Hekili:RegisterSnapshotListener`. It returns nothing. A function that is not registered is ignored.

```lua
Hekili:UnregisterSnapshotListener(AddMyState)
```

## RegisterRecommendationListener

`Hekili:RegisterRecommendationListener(fn)` adds `fn` to the functions called after every update of the `Primary`, `AOE`, `Cooldowns`, `Defensives` and `Interrupts` displays. It is the way for an addon that is not a WeakAura to follow the recommendations, without drawing a display.

| Part | Value |
|---|---|
| `fn` | A function. Anything else raises an error. |
| Returns | `true` when `fn` is registered, also when it already was; `false` when 16 listeners are already registered |
| Registering the same `fn` again | Has no effect |
| Called | After every update of each of the five displays, in the order the listeners were registered |

The listener is called as `fn(display, payload)`:

| Argument | Meaning |
|---|---|
| `display` | The display's name, such as `Primary` |
| `payload` | The display's recommendations: the same table as the payload of [`HEKILI_RECOMMENDATION_UPDATE`](#payload) |

- A display is updated only while it is worked out: while it is shown, or while the action bar glow follows it. In combat that is several times a second. A hidden display sends nothing, so check `display` and expect long gaps.
- When the display has no recommendation, the listener is still called, with every entry of the payload empty.
- The listener runs inside `pcall`. Its first error is passed to the game's error handler, so it shows like any other Lua error; its later errors are not shown. The listener stays registered and the other listeners and Hekili Forever's displays keep running.
- The listener runs inside Hekili Forever's update. Keep it short: copy the values it needs and do the work elsewhere.

Example, an addon that keeps the name of the next ability of the `Primary` display:

```lua
-- In an addon with "## Dependencies: Hekili" in its TOC
local nextAbility

local function OnRecommendation(display, payload)
    if display == "Primary" then
        nextAbility = payload[1].actionName -- nil when the display has no recommendation
    end
end

Hekili:RegisterRecommendationListener(OnRecommendation)
```

## UnregisterRecommendationListener

`Hekili:UnregisterRecommendationListener(fn)` removes a listener added with `Hekili:RegisterRecommendationListener`. It returns nothing. A function that is not registered is ignored. A listener may unregister itself or another listener while it runs; the listeners after it are still called for that update.

```lua
Hekili:UnregisterRecommendationListener(OnRecommendation)
```

## HEKILI_RECOMMENDATION_UPDATE

`HEKILI_RECOMMENDATION_UPDATE` is a WeakAuras event: Hekili Forever sends it through WeakAuras, so only a WeakAura can receive it. It is sent when WeakAuras is loaded as the player enters the world, after every update of the `Primary`, `AOE`, `Cooldowns`, `Defensives` and `Interrupts` displays. In combat a shown display updates several times a second. A hidden display is not updated, so it sends nothing.

| Argument | Meaning |
|---|---|
| 1 | The display's name, such as `Primary` |
| 2 | The first recommendation's `actionID`: the ability's spell ID, or a negative number for an item. nil when the display has no recommendation. |
| 3 | The first recommendation's `indicator`, such as `cycle` for a target swap, or nil |
| 4 | Always nil |
| 5 | The payload: a table of the display's recommendations |

### Payload

The payload, the same for this event and for a [recommendation listener](#registerrecommendationlistener):

- `payload[i]` is a copy of recommendation `i`, with the fields of a recommendation record. It has 12 entries; those past the display's last recommendation are empty tables, so `payload[i].actionID` is nil there.
- The payload's own fields read recommendation 1, so `payload.actionName` is `payload[1].actionName`.
- When the display has no recommendation, the event is still sent and the listeners are still called, with every entry empty.
- The copy is shallow. The tables inside a recommendation, such as `resources` and `alts`, are Hekili Forever's own and change on the next update. The payload and its entries are also the same tables on every update of a display. Copy the values you keep, and never change the payload.

WeakAuras runs a trigger on the frame after the event is sent, so the payload it sees holds the display's latest recommendations then.

Example, a WeakAuras custom trigger with "Event Type" set to "Status" and `HEKILI_RECOMMENDATION_UPDATE` in "Event(s)", true while the `Primary` display has a recommendation. WeakAuras calls it with the event's name first, then the event's arguments:

```lua
function(event, display, actionID, indicator, _, payload)
    -- a Status trigger runs again on the other displays' events: keep the Primary answer between them
    if event == "HEKILI_RECOMMENDATION_UPDATE" and display == "Primary" then
        aura_env.hasRecommendation = actionID ~= nil
    end
    return aura_env.hasRecommendation == true
end
```

[Show the next recommendation in a WeakAura](Integration-WeakAuras-Example) builds a complete icon from this event.

## GetToggleState

`Hekili:GetToggleState(name)` returns the state of a toggle. It only reads: an addon changes a toggle with a chat command (below), never by writing to Hekili Forever's tables.

| `name` | Returns |
|---|---|
| `mode` | The display mode: `automatic`, `single`, `aoe`, `dual` or `reactive` ([Display modes](Toggles#display-modes)) |
| `pause` | `true` while the displays are paused, else `false` |
| `cooldowns`, `minor_cooldowns`, `defensives`, `interrupts`, `potions`, `movement`, `custom1`, `custom2` | `true` when the toggle is on, `false` when it is off |
| Any other name | nil |

```lua
if Hekili:GetToggleState("cooldowns") then
    -- major cooldowns may be recommended
end
```

## HEKILI_TOGGLE

`HEKILI_TOGGLE` is a WeakAuras event, so only a WeakAura can receive it; another addon reads `Hekili:GetToggleState` when it needs the state. Its arguments are the toggle's name and its new state, the same value `Hekili:GetToggleState(name)` returns.

| Argument | Meaning |
|---|---|
| 1 | The toggle's name, as in the `GetToggleState` table |
| 2 | Its new state |

It is sent:

- after every change of a toggle that Hekili Forever accepts, from a keybinding, a chat command or macro, the minimap menu or the options. A change that sets the state the toggle already has is sent too. A command that is refused, such as `/hekili set mode` with a word that is not a mode, changes nothing and sends nothing;
- each time the displays are paused or resumed, with the name `pause`. `/hekili set pause on` pauses them and `/hekili set pause off` resumes them; when they already are in that state, it is sent without pausing or resuming again;
- once for each toggle, `pause` included, when Hekili Forever starts and when the profile is switched, copied or reset.

It is sent only when WeakAuras is loaded at that moment. Taking a snapshot does not send it.

Example, a WeakAuras custom trigger with "Event Type" set to "Status" and `HEKILI_TOGGLE` in "Event(s)", true while the major cooldowns toggle is on. WeakAuras runs it again on each `HEKILI_TOGGLE`, and it reads the state itself, so it is also right when the aura loads:

```lua
function(event, name, value)
    return Hekili ~= nil and Hekili:GetToggleState("cooldowns") == true
end
```

## IsForever and Version

`Hekili.IsForever()` takes no argument and returns `true`; retail Hekili has no such function. `Hekili.Version` is the version string, such as `v0.9.0`. [Detecting Hekili Forever](Integration-Overview#detecting-hekili-forever) shows the test to use and the shapes of the version.

## The LibDataBroker data source

Hekili Forever registers a LibDataBroker data source named `Hekili`. A display addon for LibDataBroker, such as a panel bar, lists it under that name, shows the display mode and the main toggles as its text, and opens Hekili Forever's menu when it is clicked. Only the name is promised: the data source's fields are internal.

## Chat commands in macros

Every public chat command also works in a macro. A macro can change a toggle, pause, the display mode, a specialization setting, the priority or the profile. A toggle or pause changed this way sends `HEKILI_TOGGLE` like any other change:

```text
/hekili set cooldowns on
/hekili set pause off
/hekili set mode single
/hekili priority default
```

[Slash commands](Slash-Commands) lists every command and what it takes.

## See also

- [Toggles](Toggles): the names `/hekili set` takes
