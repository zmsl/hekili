The **Accuracy** page reports, for each specialization and priority, how closely Hekili Forever's recommendations follow the rotations from [wowsims.com](https://wowsims.com), and how much the values the game hides cost. All numbers come from test simulations run outside the game. None was measured in live play.

<!-- GENERATED:accuracy-meta -->
<!-- /GENERATED -->

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
