# Core leakage audit (2026-10-16, forever 887214a2)

Question: has class-specific knowledge leaked into the core engine (`src/Hekili/Virtual/**`, `src/Hekili/Engine/**`,
the fork's edits to stock files), and how is each leak handed back to the class content as a declared field while
core keeps the generic rule? Audit by an opus reviewer, read-only, against every ability/aura/talent key (209) and
numeric ID (607) in `Forever/**`.

## Verdict

Very little leaked. Core contains no class, race, spell, aura, talent, form or item name or spell ID in any branch;
the only hits are generic words (`charge`, `form`, `potion`, `spells`) and the client's GCD spell 29515. No declared
class constant appears in core (no 1.25/1.22 decay, no 3.46/4.5/1.73 swing rate, no 105 Gnome cap). Every class
word in core is in a comment explaining a generic rule. The real leaks are three generic-looking rules shaped after
one class plus one core test that loads real race files; the rest is cosmetic. Reverse direction: the class files
use only declared API (`ns.Facade`, `VS.KnownRank`, `VS.SwingBase`, `VS.Track`), never `ns.VirtualStateInternal`.

Counts: 4 structural, 6 cosmetic (one reverse-direction).

## Structural

| id | where | leak | class-side declaration | generic rule core keeps |
|---|---|---|---|---|
| S1 | `Virtual/API/Facade.lua:241` | `floor(powerType == 1 and b.est or b.lo)`: rage answers est, others lo (decision G4) | none needed; the belief knows which resources are swing-paid | a swing-paid resource answers its estimate, others answer `lo` (`I.res.swing[I.res.slotOf[pt]] > 0`); fallback meta field `read = "est"`; update `tests/Virtual/API/facade_spec.lua:137` |
| S2 | `Families/Resources.lua:280-296` (`decayFrom`), `Adapter.lua:95-101` | every player regen aura pauses OOC decay: Bloodrage's behaviour applied to all (Druid `enrage` at `Druid.lua:188` gets it unverified) | `pausesDecay = true` on Warrior's `bloodrage` regen entry (`Warrior.lua:209`); Druid Enrage only if checkpoint Q9 shows it | an entry flagged `pausesDecay` stops decay while its aura is up, beats restart at its expiry (`G.pause[g]` at build, tested in both places) |
| S3 | `Families/Casts.lua:159`, `Families/Now.lua:307`, `Casts.lua:42-45` (`I.gcdLearned`) | one global GCD length (1.5/haste or last learned); ignores `gcd = "totem"` (1.0 s cat abilities); Druid form shifts mispredict the first GCD by up to 0.5 s, corrected by the client's GCD edge | none new: `gcd` and stock `gcdTime` already exist | `gcdTime` if declared, else `totem` = 1.0 fixed, `spell` = 1.5/haste, one learned length per GCD kind; lets stock `State.lua:3180-3212` Druid-in-energy branch go |
| S4 | `tests/Virtual/State/races_spec.lua:8-33` | loads real `Forever/Races/*.lua` via the TOC and asserts their keys | n/a | test `Engine/Schema/Races.lua` with a fake race in the test; move real-file checks to `tests/Forever/races_spec.lua` |

## Cosmetic

| id | where | leak | fix |
|---|---|---|---|
| C1 | `Adapter.lua:122-131` | `POINTS` list of resource names a max modifier must not scale | resource meta `points = true`, or `ns.ResourceIsPoints(key)` beside stock `passive_regen` in `Constants.lua` |
| C2 | `Constants.lua:247-259` | pseudo-spec rows `[1491]` Warrior, `[1499]` Druid; `DRUID_SPEC = 1499` duplicated in `Druid.lua:35` | optional: pass identity from the class file in `NewSpecialization(...)`; wait for a third class |
| C3 | `Options/Options.lua:5034, :5051` | forecast help says "a rage class ... an energy class" | "a resource paid by swings" vs "a resource that regenerates steadily" |
| C4 | `Hekili.lua:62` | "only a load-only Warrior stub" | drop or make generic |
| C5 | `tests/Virtual/State/helpers/fake_spec.lua:8-9, 61-96`, `adapter_spec.lua:101-196`, `modifiers_spec.lua:41-113`, `alloc_spec.lua:61`, `fake_api.lua:34` | fixtures hand-copy Warrior facts (772, 6546, 78, 6673, heroic_strike, rend, battle_shout, bloodrage 29131, 1.25, Eureka, 105, WARRIOR) | neutral fixtures (`spender_a`, IDs from 1001) |
| C6 (reverse) | `Druid.lua:596` `ns.DruidNotBehindErrors`, read by `tests/Forever/druid_spec.lua:677` | class-named test hook on the shared `ns` | hang it on the spec object |

Inherited from stock Hekili (not counted, pre-fork by blame): `State.lua:3180-3212` Rogue 1 s GCD table and
Druid-in-energy branch, Adrenaline Rush, Voidform; `Events.lua:2334-2406` Druid/Rogue blocks; Death Knight branches
in `Core.lua` and `State.lua:1192`.

## Already correct (checked)

Swing-paid resources (`swing`, `value`, `aura` incl. the Druid's `bear_form` gate; rates only in class files;
`GetPowerRegenForPowerType` answers by capability); decay (`decay`, `decayInterval` from the class; sim entry
generated); aura/periodic regen read by field; maxima and modifiers (`max` number-or-function, plain read wins;
Gnome +5% via `RegisterResourceMod`; `RegisterCostMod` one list for belief and sim); ability fields (`spend`,
`spendType`, `cooldown`, `charges`, `recharge`, `gcd`, `cast`, `onNextSwing`, `now`, `healthGate`, `known` via
`VS.KnownRank`); forms mapped by the client's form spell ID to whatever aura the class registered; two-cost
abilities from the client's second cost; GCD spell 29515 one constant; `Engine/*` fork edits generic; fork edits
to stock files (E3, E5, E7-E9) class-neutral.

## Recommended order

1. S1 (~15 min). 2. S2 (~1 h). 3. S4 (~45 min). 4. A boundary test like TDF's `tests/boundary_spec.lua`: extract
keys and IDs from `Forever/**`, fail on any hit in `Virtual/**` or `Engine/**` outside comments, allow-list 29515
and the resource vocabulary (~1-1.5 h). 5. S3 (~2-3 h with the stock GCD edit and an in-game check). 6. C1.
7. C3, C4, C6. 8. C5. 9. C2 when a third class arrives.

Not checked: the suite was not run; stock-file edits before the a414b73c layout move were read as one combined diff.
