The **Accuracy** page reports, for each specialization and priority, how closely Hekili Forever's recommendations follow the rotations from [wowsims.com](https://wowsims.com), and how much the values the game hides cost. All numbers come from test simulations run outside the game. None was measured in live play.

| Accuracy measurements | |
|---|---|
| Measured on | Hekili Forever v0.8.0 |
| Priorities | Built from wowsims.com as of 2026-11-07 |
| Specializations and priorities | 27 |
| Scale | 0 to 1; higher is better |
| Produced by | `make accuracy` in the repository |

## Reading the table

Each cell holds two numbers, **full information / live-like**.

- **Full information**: the test lets Hekili Forever see the player's own buffs and debuffs, as the original Hekili could. Resources stay hidden.
- **Live-like**: the player's own buffs and debuffs are also hidden in combat, as on the live client, and the game's Cooldown Manager shows none of them. This is the lower bound. In real play the result lies between the two numbers, depending on what the Cooldown Manager shows.

The three measures are:

- **Matches wowsims**: wowsims.com's own log of a 180-second fight is played back to Hekili Forever, with the hidden values kept hidden. The number is the share of decisions where Hekili Forever's first icon was the ability wowsims cast next.
- **Hidden values, solo**: twenty simulated fights, each played twice: once with only the values the game shows, and once with the true values. The number is the share of moments where both runs showed the same first icon, taking the worst of three sets of fights. 1.000 means the hidden values cost a player fighting alone nothing.
- **Hidden values, crowded target**: the same test with 39 other simulated players attacking the target. It is reported only; no check fails when it drops.

## Results

<!-- GENERATED:accuracy -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Class | Specialization or priority | Matches wowsims | Hidden values, solo | Hidden values, crowded target |
|---|---|---|---|---|
| Druid | Balance | 0.975 / 0.835 | 0.993 / 0.919 | 0.968 / 0.928 |
| Druid | Feral | 0.965 / 0.929 | 0.947 / 0.956 | 0.952 / 0.938 |
| Druid | Guardian | 0.632 / 0.607 | 0.876 / 0.865 | 0.894 / 0.888 |
| Hunter | Beast Mastery | 0.958 / 0.958 | 0.994 / 0.994 | 0.997 / 0.997 |
| Hunter | Marksmanship | 0.989 / 0.989 | 1.000 / 1.000 | 0.999 / 0.999 |
| Hunter | Survival | 0.946 / 0.946 | 0.955 / 0.700 | 0.966 / 0.721 |
| Mage | Arcane | 0.955 / 0.848 | 0.987 / 0.581 | 0.982 / 0.606 |
| Mage | Fire | 0.963 / 0.815 | 0.994 / 0.780 | 0.992 / 0.803 |
| Mage | Frostfire | 0.965 / 0.860 | 0.935 / 0.830 | 0.956 / 0.813 |
| Paladin | Protection | 0.958 / 0.958 | 1.000 / 1.000 | 1.000 / 1.000 |
| Paladin | Retribution | 0.933 / 0.822 | 0.995 / 0.977 | 0.996 / 0.950 |
| Priest | Shadow | 1.000 / 1.000 | 0.997 / 0.996 | 0.996 / 0.994 |
| Priest | Smite | 0.932 / 0.932 | 0.945 / 0.945 | 0.950 / 0.950 |
| Rogue | Assassination | 0.978 / 0.978 | 0.990 / 0.990 | 0.992 / 0.993 |
| Rogue | Combat | 0.991 / 0.991 | 0.989 / 0.987 | 0.988 / 0.989 |
| Rogue | Subtlety | 0.990 / 0.990 | 0.983 / 0.984 | 0.985 / 0.980 |
| Shaman | Elemental | 0.896 / 0.896 | 0.994 / 0.971 | 0.995 / 0.974 |
| Shaman | Enhancement | 0.969 / 0.763 | 0.953 / 0.175 | 0.948 / 0.177 |
| Warlock | Affliction | 0.833 / 0.750 | 0.988 / 0.844 | 0.987 / 0.833 |
| Warlock | Demonology | 0.872 / 0.829 | 0.949 / 0.949 | 0.945 / 0.945 |
| Warlock | Destruction | 0.908 / 0.908 | 0.985 / 0.985 | 0.985 / 0.985 |
| Warlock | SM Ruin | 0.798 / 0.787 | 0.981 / 0.963 | 0.972 / 0.951 |
| Warlock | Shadow Brand | 0.718 / 0.718 | 0.984 / 0.984 | 0.967 / 0.967 |
| Warrior | Arms | 0.886 / 0.886 | 0.958 / 0.958 | 0.862 / 0.859 |
| Warrior | Fury | 0.869 / 0.869 | 0.922 / 0.922 | 0.835 / 0.845 |
| Warrior | Fury (level 24) | n/a | 0.924 / 0.926 | 0.853 / 0.850 |
| Warrior | Protection | 0.920 / 0.920 | 0.893 / 0.841 | 0.873 / 0.870 |

n/a: wowsims has no fight log for this case.
<!-- /GENERATED -->

## Lowest values

- **Guardian, matches wowsims (0.632):** the game hides the rage gained from hits the player takes, and Hekili Forever does not estimate it. Lacerate, Maul and Primal Bite therefore appear only once the game reports enough rage to use them.
- **Live-like, solo:** the largest drops are for priorities that depend on the player's own buffs: Enhancement (0.175), Arcane (0.581), Survival (0.700) and Fire (0.780). Priorities that test none of their own buffs do not change.

## What the numbers do not show

- Live play. The tests have no boss mechanics, no movement and a single target.
- Damage. The numbers count matching decisions, not damage done.
- Priorities that are not in the table. They were not measured.

## See also

- [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)
- [wowsims priorities explained](APL-wowsims-Packs-Explained)
