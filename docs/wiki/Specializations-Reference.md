<!--
Purpose: Every option on a specialization page, plus each class's settings.
Type: Reference
Audience: everyone
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Every option on a specialization page, plus each class's settings.

## Specialization page options

- Shown for one specialization; every specialization has the same options, with its own name in place of *your specialization*.

<!-- GENERATED:options-spec -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Section | Option | Type | Default | Values | Description |
|---|---|---|---|---|---|
| Specialization Settings | Priority | choice | Set per specialization | The specialization's own | The addon will use the selected package when making its priority recommendations. |
| Specialization Settings | Activate *your specialization* | button | n/a | n/a | Recommend for *your specialization* from now on. |
| Specialization Settings | Potion | choice | Set per specialization | The specialization's own | Unless otherwise specified in the priority, the selected potion will be recommended. |
| Specialization Settings | Disable *your specialization* | toggle | Off | n/a | No recommendations while this specialization is active. |
| Targeting | Your Target | toggle | On | n/a | Your actual target is always counted as an enemy, even if you do not have a target. |
| Targeting | Count Nameplates Near You | toggle | On | n/a | If checked, enemy nameplates within the specified radius of your character will be counted as enemy targets. |
| Targeting > Nameplate Detection | Enemy Range Radius | slider | 10 | 0 to 100, step 1 | If Count Nameplates is enabled, enemies within this range will be included in target counts. |
| Targeting > Nameplate Detection | Show Enemy Nameplates | toggle | Off | n/a | If checked, enemy nameplates will be displayed and can be used to count enemy targets. |
| Targeting > Nameplate Detection | Show All Nameplates | toggle | Off | n/a | If checked, all enemy nameplates (rather than just your target) will be displayed and can be used to count enemy targets. |
| Targeting | Count Targets Near Your Pet | toggle | Off | n/a | If checked and properly configured, the addon will count targets near your pet as valid targets, when your target is also within range of your pet. |
| Targeting | Count Damaged Enemies | toggle | On | n/a | If checked, targets you've damaged will be counted as a valid enemy for several seconds, distinguishing them from other enemies that you have not attacked. |
| Targeting > Damage Detection | Timeout | slider | 8 | 3 to 10, step 0.1 | Enemies will be counted until they have been ignored/undamaged for this period of time (or they die). |
| Targeting > Damage Detection | Include Enemies Damaged by Your Pets and Minions | toggle | Off | n/a | If checked, the addon will count enemies that your pets or minions have hit (or hit you) within the past several seconds. |
| Targeting > Damage Detection | Include Enemies With Your DOTs / Debuffs | toggle | Off | n/a | When checked, enemies that have your debuffs or damage-over-time effects will be counted as targets, regardless of their location on the battlefield. |
| Targeting > Damage Detection | Filter Off-Screen (Nameplate-less) Enemies | toggle | On | n/a | If checked, the damage-based target system will only count enemies that are on screen. |
| Targeting | Allow Target Swaps | toggle | Off | n/a | When target swapping is enabled, an icon may be shown when you should use an ability on a different target. |
| Targeting > Secondary Targets | Filter by Time-to-Die | slider | 6 | 0 to 15, step 1 | When Recommend Target Swaps is checked, this value determines which targets are counted for target swapping purposes. |
| Targeting | Minimum Targets for Dedicated AOE Recommendations | slider | 2 | 2 to 10, step 1 | When the AOE display is shown (or AOE mode is active), its recommendations will assume that there are at least this many targets available. |
| Performance | Frame Budget | slider | 70% | 20% to 90%, step 5 | This setting determines how much time can be used to calculate recommendations. |
| Performance | Forecast window (s) | slider | 15 | 5 to 30, step 1 | How far ahead the recommendations look for the next affordable action. |

n/a: no fixed default (a keybind not set, or a value that follows the game or another option), no range, or no description.
<!-- /GENERATED -->

## Class settings

<!-- GENERATED:spec-settings -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Class | Specializations | Setting | Type | Default | Description |
|---|---|---|---|---|---|
| Warrior | Arms, Fury | Recklessness (wowsims.com) | toggle | Off | The wowsims.com priority's Recklessness ON/OFF switch (its default in wowsims's own APL). |
| Warrior | Arms | Stance Dance (wowsims.com) | toggle | Off | The wowsims.com priority's Stance Dance ON/OFF switch (its default in wowsims's own APL). |
| Warrior | Arms | Maintain Thunder Clap | toggle | Off | Keep Thunder Clap's slow on the target, recasting it only when it is missing (that includes the levels before Mortal Strike). |
| Warrior | Fury | Rend Weave (wowsims.com) | toggle | On | The wowsims.com priority's Rend Weave ON/OFF switch (its default in wowsims's own APL). |
| Warrior | Protection | Maintain Demoralizing Shout | toggle | Off | Keep Demoralizing Shout on the target, as a raid tank does. |
| Druid | Balance, Feral, Guardian | Always Behind | toggle | Off | Hekili assumes you are always behind the target. |
| Druid | Feral, Guardian | Maintain Demoralizing Roar | toggle | Off | Keep Demoralizing Roar on the target, as a raid tank does, and recast it only when it is missing (that includes the levels before Lacerate). |
| Priest | Shadow | Prefer Starshards | toggle | Off | Shadow only, and only when you know Starshards (the Night Elf racial). |
| Warlock | Affliction, Demonology, Destruction | Assigned Curse | choice | Curse of the Elements | The curse the wowsims.com priority keeps on the target (wowsims's Curses option). |

n/a: no description.
<!-- /GENERATED -->

## See also

- [Setting up target counting](Setting-Up-Target-Counting)
- [Pack settings](Pack-Settings)
