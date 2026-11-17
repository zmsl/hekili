<!--
Purpose: Build a WeakAura icon that shows the Primary display's first recommendation and its keybind.
Type: How-to
Audience: WeakAura authors
Prerequisites: [Integration reference](Integration-Reference#hekili_recommendation_update).
-->
This page shows how to build a WeakAura icon that shows the first recommendation of the `Primary` display, with its keybind, from the `HEKILI_RECOMMENDATION_UPDATE` event. It is for players who want Hekili Forever's next ability inside their own WeakAuras layout. The [Integration overview](Integration-Overview) explains what the event promises.

<!-- UNVERIFIED: the WeakAuras option names and the trigger state updater's calling convention are WeakAuras's, not checked in this repository or in game on Forever. -->

## Before you start

- WeakAuras is installed and enabled.
- The `Primary` display is shown. A hidden display is not updated, so it sends no event.

## Steps

1. Type `/wa` and create a new Icon aura.
2. On the Trigger tab, set the type to Custom, then choose Trigger State Updater (TSU).
3. In the event list, enter `HEKILI_RECOMMENDATION_UPDATE`.
4. Paste this as the trigger function:

   ```lua
   function(allstates, event, display, actionID, indicator, _, payload)
       if event ~= "HEKILI_RECOMMENDATION_UPDATE" or display ~= "Primary" then
           return false
       end
       local rec = payload[1]
       local state = allstates[""]
       if not rec.actionID then
           -- the display has no recommendation: hide the icon
           if state and state.show then
               state.show = false
               state.changed = true
               return true
           end
           return false
       end
       if not state then
           state = {}
           allstates[""] = state
       end
       -- copy the values: the payload's tables change on the next update
       state.show = true
       state.changed = true
       state.icon = rec.texture
       state.name = rec.actionName
       state.keybind = rec.keybind
       state.wait = rec.time
       return true
   end
   ```

5. In the custom variables box, enter `{ keybind = "string", wait = "number" }` so the display can use the two extra values.
6. On the Display tab, add a text with `%keybind` to show the key bound to the ability.

`rec.time` is the number of seconds from the update until the recommendation is due, 0 when it is ready. `rec.keybind` is the same key text Hekili Forever's own display shows. The other fields a recommendation carries are listed in [the recommendation record](Contributing-Display-Styles-And-Integrations#the-recommendation-record).

## Check that it worked

Target an enemy and enter combat. The WeakAura's icon matches the first icon of the `Primary` display and changes with it. When the display has nothing to recommend, the icon hides.

## See also

- [Integration reference](Integration-Reference): every argument of the event and the payload
- [Setting up displays](Setting-Up-Displays): how to show or hide a display
