<!--
Purpose: Every field of the Priorities editor, and which do nothing on Forever.
Type: Reference
Audience: theorycrafters
Prerequisites: [APL overview](APL-Overview).
-->
The **priority editor** is the part of the options where a priority is viewed, copied, edited, imported and exported. Each priority has its own page under **/hekili > Priorities**, inside its specialization, with four tabs: **Summary**, **Source**, **Action Lists** and **Export**. This page lists every field of those tabs and marks the ones that have no effect on Forever. The text form behind the fields is described in [APL syntax reference](APL-Syntax-Reference).

A built-in priority is replaced by the shipped version whenever the addon updates, so changes made to it are not kept, and its name and specialization are locked. To change one, copy it first ([APL tutorial: your first custom priority](APL-Tutorial-Your-First-Custom-Priority)).

<!-- TODO-SCREENSHOT: the Action Lists tab of a copied Feral priority, one entry selected -->

## The tabs

| Tab | What it holds |
|---|---|
| **Summary** | Whether the priority is active, its name and specialization, its description, and buttons to copy it and to reload a built-in priority or delete a custom one |
| **Source** | The author, the date, the source link, and the SimulationCraft text with its **Import** button and **Import Log** |
| **Action Lists** | One list and one entry at a time, with the fields of the selected entry |
| **Export** | The **Priority Export String**, to share the priority |

The buttons beside **Priority Name** on the **Summary** tab are icons. Hover over one for its name: Copy Priority, Reload Priority (built-in priorities only) or Delete Priority (custom priorities only).

The **Priorities** page itself has **Create a New Priority**, with **Priority Name**, **Specialization** and **Create New Pack**, and **Import / Export** for share strings.

## Every field

The table below lists every field, for one specialization. The **Action Lists** fields shown depend on the entry's action: for example **Variable Name** appears only on a `variable` line. The field that pools for the next entry is shown as "Pool for Next Entry" followed by the next line's ability.

<!-- GENERATED:options-editor -->
<!-- /GENERATED -->

Each **Action Lists** field stores one line option. [APL line options](APL-Line-Options) gives the option behind each field.

### Editing an entry

- Choose the list in **Action List** and the line in **Entry**. A new list is added with **Add List** and a new line with **Create New Entry**.
- A change to a field takes effect at once, without an import. The **Conditions** box keeps the text exactly as typed, so the importer's conversions do not apply there ([Line edge cases](APL-Syntax-Reference#line-edge-cases)).
- **Enabled** switches one line off without deleting it.

### Importing text

**Import** on the **Source** tab clears the priority's lists and rebuilds them from the text in **Priority (SimulationCraft Action Priority List)**. It is available only while the character is in the priority's specialization. Every change the importer made, and every line it could not use, is listed in **Import Log**.

## Fields that do nothing on Forever

These fields are shown and saved, but nothing in Hekili Forever reads them:

| Field | Shown for | Note |
|---|---|---|
| **Max Energy** | A Ferocious Bite line | Left from an older pooling option |
| **Pooling Time** | A `pool_resource` line without pooling for the next entry | Pooling for a fixed time is not implemented. |
| **Use While Casting** | Every ability line | |
| **Test Conditions Immediately**, **Additional Immediate Criteria** | Every line | They act only on `call_action_list`, `run_action_list` and `use_items` lines. |

> [!WARNING]
> **Different from retail Hekili:** Pooling options carried over from the original Hekili are not needed. Each line already waits for its own cost in the forecast.

## See also

- [APL line options](APL-Line-Options)
- [APL tutorial: your first custom priority](APL-Tutorial-Your-First-Custom-Priority)
- [Profiles and sharing](Profiles-And-Sharing)
