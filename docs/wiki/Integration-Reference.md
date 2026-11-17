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
| `HEKILI_RECOMMENDATION_UPDATE` | WeakAuras event | `src/Hekili/Integrations/WeakAuras.lua` |

## Display styles

`Hekili:RegisterDisplayStyle(name, impl)` registers a display style: the code that draws one display's recommendations. It returns `true` when the style is registered and `false` when it is refused. `Hekili.DisplayStyleAPI` is the interface version, 1 in this release. [Contributing display styles and integrations](Contributing-Display-Styles-And-Integrations#registerdisplaystyle) describes every member of `impl`, the button contract and [the fields of a recommendation record](Contributing-Display-Styles-And-Integrations#the-recommendation-record).

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
| `record` | That first record. `record.header` is its title line and `record.log` its full text. |
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

## HEKILI_RECOMMENDATION_UPDATE

`HEKILI_RECOMMENDATION_UPDATE` is a WeakAuras event: Hekili Forever sends it through WeakAuras, so only a WeakAura can receive it. It is sent when WeakAuras is loaded as the player enters the world, after every update of the `Primary`, `AOE`, `Cooldowns`, `Defensives` and `Interrupts` displays. In combat a shown display updates several times a second. A hidden display is not updated, so it sends nothing.

| Argument | Meaning |
|---|---|
| 1 | The display's name, such as `Primary` |
| 2 | The first recommendation's `actionID`: the ability's spell ID, or a negative number for an item. nil when the display has no recommendation. |
| 3 | The first recommendation's `indicator`, such as `cycle` for a target swap, or nil |
| 4 | Always nil |
| 5 | The payload: a table of the display's recommendations |

The payload:

- `payload[i]` is a copy of recommendation `i`, with the fields of a [recommendation record](Contributing-Display-Styles-And-Integrations#the-recommendation-record). It has 12 entries; those past the display's last recommendation are empty tables, so `payload[i].actionID` is nil there.
- The payload's own fields read recommendation 1, so `payload.actionName` is `payload[1].actionName`.
- When the display has no recommendation, the event is still sent, with every entry empty.
- The copy is shallow. The tables inside a recommendation, such as `resources` and `alts`, are Hekili Forever's own and change on the next update. The payload and its entries are also the same tables on every event of a display. A WeakAura copies the values it keeps.

Example, a trigger function that tests for a recommendation on the `Primary` display:

```lua
function(event, display, actionID, indicator, _, payload)
    return event == "HEKILI_RECOMMENDATION_UPDATE" and display == "Primary" and actionID ~= nil
end
```

[Show the next recommendation in a WeakAura](Integration-WeakAuras-Example) builds a complete icon from this event.

## Chat commands in macros

Every public chat command also works in a macro. A macro can change a toggle, the display mode, a specialization setting, the priority or the profile:

```text
/hekili set cooldowns on
/hekili set mode single
/hekili priority default
```

[Slash commands](Slash-Commands) lists every command and what it takes.

## See also

- [Integration overview](Integration-Overview)
- [Toggles](Toggles): the names `/hekili set` takes
