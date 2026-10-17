# Forever Protection Warrior: rage from damage taken, threat and the priority (design, 2026-10-16)

Status: revised 2026-10-16 with the user's decisions (§6): no current-health model, no defensives in the priority,
Shield Block kept up unconditionally, the rotation driven by the rage model. Base: forever 939a64cc. Paths under `src/Hekili/` unless they start with `tests/`,
`tools/` or `docs/`. Inputs: the research brief `tmp/prot/research.md` ("R", corrected 2026-10-16: every DB2 number
re-queried with `wowdb` at build 1.60.1.70338; its §0 lists the corrections), the live-client export of 2026-10-15
("EXP", `tmp/warrior/export/`, reconciled in `tmp/warrior/reconcile.md`), magey/forever-warrior issue 3 (re-read
2026-10-16), the event-facade spec (§2.4, decision 6), the core leakage audit (the boundary rule) and the max-health
research (UnitHealthMax("player") plain always, UnitHealth secret always, stats and armor plain out of combat only).
Already decided, not reopened: the white-crit rage bonus, `pausesDecay`, UnitPower answering `lo`, UnitHealthMax
player plain. Layering: Events may stage State observations (reviewer ruling, 2026-10-16).

**The boundary, binding for every section.** Core (`Virtual/**`, `Engine/**`, fork edits to stock files) gets generic
rules read from declared fields, with no class, spell, aura, talent name, spell ID or Warrior constant. Everything
Warrior-specific is a field or function on `Forever/Classes/Warrior.lua`'s declarations. Each section ends with
"Owns", the split by file.

## 1. Rage from damage taken

### 1.1 Facts
- magey #3 (level 8-9, Zephras Isle): rage (bar points) = pre-armor damage x 10 / max health; a blocked hit gives the
  rage of its unblocked amount; attacker level made no difference (L5 vs L6); below about 130-170 armor the rate is
  exactly double (unresolved, "possibly a bug"). Defensive Stance is a level-10 spell (DB2 71), so those logs were not
  in it: whether the stance's -10% (7376 aura 87) comes before the rage is untested.
- `UNIT_COMBAT` on `player` is plain (TDF N27: 165 firings, 0 secret): WOUND, BLOCK, DODGE, PARRY, MISS, HEAL; flags
  CRITICAL, GLANCING, CRUSHING, BLOCK, BLOCK_REDUCED. The amount is post-armor and post-block; the blocked part is not
  given (TDF :180). It has no source: `Events/Attackers.lua` attributes only when the clocks or a lone hostile name one.
- Armor: `UnitArmor` returns `base, effective, real, bonus` (DOC); plain out of combat only. The stat cache keeps all
  returns; the armor is the **second** (the 2026-10-16 probe's "0" was `base`). Block value: `GetShieldBlock()`,
  `SecretWhenUnitStatsRestricted` (DOC) like the armor, not cached today.
- Talents: Shield Specialization (12298, rank-1 row): "a $m2% chance to generate 5 Rage when you Block", m2 = 100,
  energize 1310318 = 50. Master of Defense (1310316): "a $m1% chance to generate 5 Rage when you Dodge or Parry while a
  shield is equipped", m1 = 0 in the row (chance unknown; wow.gg says 50% a rank), energize 23602 = 50 today (the
  2026-10-15 reconcile read 20). Both are procs on avoidance outcomes the same event reports.

### 1.2 The generic rule (core)
1. **Observation.** New `Obs.PlayerHit = 36` (VirtualState.lua): `a` the kind, `b` the amount (0 when none), `c` the
   attacker level. Kinds (`I.HitKind`): 1 WOUND, 2 BLOCKED (a WOUND flagged BLOCK or BLOCK_REDUCED), 3 BLOCK (a full
   block), 4 DODGE, 5 PARRY, 6 MISS, 7 HEAL. Staged by `Sources/Player.lua` from `S.On("UNIT_COMBAT", nil, ...)` when
   `unit == "player"` (registered for every unit, as `Sources/Target.lua` explains: a "player" registration would
   narrow the client's and starve Rows/Attackers). Every hit counts, **attributed or not** (an unattributed hit is
   still damage we took): the stage happens before and independent of `Attackers.lua`'s attribution. Level: the plain
   `UnitLevel("target")` when the plain `UnitIsUnit("targettarget", "player")` is true and the level is above 0, else
   the plain `UnitLevel("player")` (both through `Plain`; a secret answer falls to the next). Secret amount: never
   seen (N27), still guarded: `Plain` or the hit is dropped with a `Note`.
2. **Declaration.** A swing-paid resource's paying entry (the `swing = "mainhand"` regen entry, where `crit` lives)
   may declare `taken = function(kind, amount, level) return gain, width end`: `kind` the kind's name ("WOUND",
   "BLOCKED", "BLOCK", "DODGE", "PARRY", "MISS", "HEAL", constant strings), `gain` the expected units, `width` the
   half-width of its uncertainty (default 0). `Adapter.lua` forwards it as `d.taken`. The function is bound at
   SpecChanged to the `now` context (`Families/Now.lua`'s `ctx`, exposed as `I.NowContext`), so `buff`, `talent` and
   the resources read the belief, as a `now` handler's do; upvalues (VS accessors, `state.equipped`) stay usable.
3. **Belief (`Families/Resources.lua`).** On `PlayerHit` of kinds 1-6, for each slot with a `taken`: `est += gain`,
   `lo += max(0, gain - width)`, `hi += gain + width`, each clamped to [0, max]; `R.gain[r] += gain` (a flip after it
   is explained, as `I.ResourceShift` does, so the swing calibration no longer absorbs damage-taken rage as a larger
   swing scale); one `modelled` sample at the hit's time (`Obs.PlayerHit`). A `gain` that is not a positive number is
   ignored. Zero allocation: no closures, the kind names a constant table.
4. **Learned incoming rate.** Per slot with a `taken`, ten one-second bins of the gains (`R.takenBin[r][1..10]` and their
   second stamps, preallocated at build); `VS.TakenRate(powerType, now)` = the sum of the bins stamped within the last
   `I.TAKEN_WINDOW = 10` s / 10, in combat only (0 out of combat; the bins clear at `CombatEnd`).
5. **Sim (`Adapter.lua`).** For a resource whose paying entry has `taken`, a generated regen entry `__taken` (reserved,
   like `__decay`, and skipped by the `auraRegen` walk): `{ resource = k, interval = 1, value = function() return
   VS.TakenRate(pt, state.now) end, last = function() return state.now + state.offset end, stop = function() return
   state.time == 0 end }`, built once per regen model. Hekili's forecast then steps the learned rate every second of
   the fight (`rage.time_to_x`, `TimeToResource`); out of combat it is removed (`stop`). The belief never reads it:
   real hits are observed.

### 1.3 Warrior (`Warrior.lua`, the `mainhand` entry)
`taken`, beside `crit`:
- WOUND, BLOCKED: `armor = select(2, VS.Stat("UnitArmor"))`; `dr = armor / (armor + 400 + 85 x level)`; `post = amount +
  (BLOCKED and VS.Stat("GetShieldBlock") or 0)` (the unblocked amount, magey #3); `pre = post / (1 - dr)`; divided by
  `TAKEN_SCALE` (below); `gain = pre x 10 / VS.HealthMax("player")`, `width = 0.15 x gain` (the fit's scatter, 9.6-11
  around 10, plus a stale cached armor). A local EMA of the unblocked post-armor amounts (weight 0.2) feeds BLOCK.
- BLOCK (full): the unblocked amount is at most the block value: `u = min(blockValue, ema)`, `gain` from `u` as above,
  `width = gain`.
- Shield Specialization on BLOCK and BLOCKED, rank >= 1: `+ p x 5` with `p = 1` (the rank-1 row's 100%), width
  `max(p, 1 - p) x 5`. Master of Defense on DODGE and PARRY with `state.equipped.shield`: `p = 0.5 x rank`, `gain = p x
  5`, width as above. They are the same rule's siblings: one `taken` function, kinds as its argument (my call: one field
  on one entry keeps the core rule one loop, and a class with several procs adds branches, not declarations).
- MISS, HEAL: 0.
- `TAKEN_SCALE`: `buff.defensive_stance.up` gives 0.9 and `buff.shield_wall.up` 0.4 (product), applied only when the file
  constant `RAGE_BEFORE_REDUCTION = true` (assumption: the server computes rage from the damage before every
  percentage reduction, as it does before armor; checkpoint Q5 settles it, D1). `false` divides by nothing.
- Not modelled: the sub-170-armor doubling (a comment with `shortcut:` naming checkpoint Q6 and D2); Berserker Rage's
  extra rage taken (not a Protection tool; unread).
- The stat cache gains `{ "GetShieldBlock" }` (`Families/Player.lua` `I.STATS`, `Sources/Player.lua` `statCall`): a
  generic client stat, same out-of-combat rule.

Owns: `VirtualState.lua` (Obs, HitKind), `Sources/Player.lua` (the stage, the stat call), `Families/Player.lua`
(I.STATS row), `Families/Now.lua` (`I.NowContext`), `Families/Resources.lua` (taken, bins, `VS.TakenRate`),
`Adapter.lua` (forward, `__taken`); `Warrior.lua` (`taken`, `RAGE_BEFORE_REDUCTION`).

## 2. Threat expressions
- **Pass through already:** `aggro` (State.lua:1842, `UnitThreatSituation("player") > 1`, highest over every mob;
  `UnitThreatSituation` is a plain passthrough row, Facade.lua:853 "plain in combat [W PR14]"); `state.UnitIsUnit`
  (State.lua:471-474, passthrough row :844). `tanking` (State.lua:1870) is `role.tank and aggro`, and `role.tank` is
  set only from `GetSpecializationInfo`'s role (Engine/Schema/Spec.lua:1974-1980); the pseudo-spec 1491's role is unread
  (checkpoint Q10). Priorities do not use `tanking`.
- **New, generic** (`Engine/Schema/Spec.lua`, an engine state table on `all` beside `casting`/`movement`, no State.lua edit;
  computed on read, no caching, no allocation): `threat.situation` = `UnitThreatSituation("player", "target") or 0`;
  `threat.on_me` = `UnitIsUnit("targettarget", "player")`; `threat.lost` = `UnitExists("targettarget") and not
  threat.on_me` (the target attacks someone else: Taunt's own condition, "no effect if the target is already attacking
  you"); `threat.loose` = `VS.LooseEnemies()`. Each read goes through the facade's existing plain rows; a secret answer
  reads as 0/false (`issecretvalue` first).
- **`VS.LooseEnemies()`** (`Events/Attackers.lua`): the hostile tokens (target, focus, nameplates) whose `"<token>target"`
  exists and is not the player, deduped by GUID, from the per-token state `recheck` already keeps (one plain
  `UnitExists(TT[i])` read added there). No facade row: a VS accessor. Whether a nameplate's target-of read is plain
  is recorded by the existing `Note("UnitIsUnit target-of", ...)`; checkpoint Q8 reads it.

Owns: `Engine/Schema/Spec.lua` (`threat`), `Events/Attackers.lua` (`LooseEnemies`). No Warrior code.

## 3. Kit corrections (`Warrior.lua`)
- **Improved Shield Block, Improved Taunt, Toughness: not registered.** The brief asked for them; the live tree has no
  node for any of the three (EXP: the 52 nodes; reconcile.md:126's "GONE" list), ruling A1 deleted their readers, and
  `TALENTS` pins the 52. The DB2 rows (12945/12307/12944: +1 block, +0.5/1/2 s; 12302/12765: -1/-2 s) describe a tree
  Forever does not ship. Shield Block stays 7 s, Taunt 8 s.
- **Defiance stays `{ 0, 12792, 3 }`.** The DB2 lists 5 rank IDs (talent 144) but the client's node is max 3 (EXP);
  the client wins (file header rule). Nothing reads it (threat is not simulated).
- **Shield Block's blocks are aura charges, not spell charges.** DB2: `SpellAuraOptions.ProcCharges = 2`, no
  `SpellCategories` row (no charge category), so the ability gets **no** `charges` field (Hekili would read it as two
  cooldown charges) and `C_Spell.GetSpellCharges` is not used (nothing to report; `SecretWhenCooldownsRestricted`).
  The aura becomes `max_stack = 2`; `now` and `handler` apply it with 2 stacks. Generic aura field (core,
  `Families/Auras.lua` + Adapter forward): `consumedBy = { BLOCK = true, BLOCKED = true }` removes one stack per
  `PlayerHit` of a listed kind while the aura is believed up, and the aura at 0. In combat the aura walk is secret, so
  the belief is the only source; out of combat a plain read overrides (checkpoint Q1 says which field shows 2).
  `buff.shield_block.stack` is the blocks left.
- **Shield Specialization and Master of Defense:** modelled by §1.3; their `-- unmodelled` comments go.
- **Devastate and Commanding Shout:** registered only if checkpoint Q3 shows them known (`IsPlayerSpell`); then
  Devastate `{ id = 403196 }` as a Sunder modifier needs no ability (it rides Sunder's cast) and Commanding Shout
  (403215: no cost, 1.5 s GCD, 5 min party stamina) an ability with `now = applyBuff("commanding_shout")` and its aura.
  Until then nothing.
- **`now`:** Shield Block's changes (2 stacks); nothing else new (Victory Rush's heal and Last Stand's health touch
  only the player's current health, which stays secret and unmodelled).
- **Unchanged and confirmed by the DB2:** Concussion Blow off the GCD (StartRecovery 0), Shield Wall and Shield Bash on
  it (1500), Taunt off it, Revenge 5 s category cooldown, Shield Slam 6 s.

Owns: `Warrior.lua` (aura, `now`, comments), `Families/Auras.lua` + `Adapter.lua` (`consumedBy`).

## 4. The Protection priority (`tools/packs/warrior.lua`)
Settings (Warrior.lua, `RegisterSetting`): `prot_heroic_strike_rage` 50 (0-100), `prot_cleave_rage` 40 (0-100),
`challenging_shout_loose` 3 (1-10). The priority recommends no defensives: Last Stand, Shield Wall and the Healthstone
stay out of it, and Bloodrage has no health gate; the player decides those.
```
actions.precombat=battle_shout,if=!buff.battle_shout.up
actions.precombat+=/charge,use_off_gcd=1
actions.precombat+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up
actions=shield_bash
actions+=/mocking_blow,if=threat.lost
actions+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up
actions+=/taunt,use_off_gcd=1,if=threat.lost&!debuff.mocking_blow.up
actions+=/challenging_shout,if=threat.loose>=settings.challenging_shout_loose
actions+=/shield_block,use_off_gcd=1,if=buff.shield_block.stack<2
actions+=/victory_rush
actions+=/bloodrage,use_off_gcd=1,if=rage.current<20
actions+=/battle_shout,if=!buff.battle_shout.up
actions+=/run_action_list,name=aoe,if=active_enemies>=3
actions+=/run_action_list,name=single
actions.single=revenge
actions.single+=/shield_slam
actions.single+=/sunder_armor,if=debuff.sunder_armor.stack<5|debuff.sunder_armor.remains<3
actions.single+=/thunder_clap,if=!debuff.thunder_clap.up
actions.single+=/demoralizing_shout,if=settings.debuff_demoshout_enabled&!debuff.demoralizing_shout.up
actions.single+=/concussion_blow,use_off_gcd=1
actions.single+=/heroic_strike,use_off_gcd=1,if=rage.current>=settings.prot_heroic_strike_rage
actions.single+=/sunder_armor
actions.aoe=thunder_clap,if=!debuff.thunder_clap.up|active_dot.thunder_clap<active_enemies
actions.aoe+=/demoralizing_shout,if=!debuff.demoralizing_shout.up
actions.aoe+=/revenge
actions.aoe+=/shield_slam
actions.aoe+=/cleave,use_off_gcd=1,if=rage.current>=settings.prot_cleave_rage
actions.aoe+=/sunder_armor
```
Notes. Shield Block is kept up unconditionally: whenever a charge is missing (`buff.shield_block.stack<2`, which
includes the aura being down) and it is off cooldown (the ability's own 5 s cooldown gates it), right after the
interrupt and the threat entries; the stance line stays above it because Shield Block requires Defensive Stance. The
rotation is driven by the rage model: §1's damage-taken rage and its learned rate reach the forecast, so the Heroic
Strike and Cleave thresholds and `rage.time_to_x` see incoming rage. The toggles come from the abilities (Challenging
Shout: `defensives`; Mocking Blow: `cooldowns`; Shield Bash: `interrupts`), so the list does not repeat them. Mocking
Blow is Battle Stance only (`buff = "battle_stance"`): in Defensive Stance it never shows; no stance dance is
recommended (D4). It sits above the stance swap so that in Battle Stance with the target lost it comes first; Taunt
(Defensive Stance only) follows the swap and waits while the sim's Mocking Blow debuff is up, so the queue does not
predict a second taunt after Mocking Blow. Revenge is gated by `revenge_usable` (the attributed rows or the plain usability read); Shield Slam
waits for level 40 and its talent. Sunder stacks to 5 then refreshes under 3 s, and fills last. Every name exists
after §2-§3 (`threat.*`, `buff.shield_block.stack`, the three settings); no `health.*` token, so the "only registered
names" test's secret-token check stays as it is. The description drops "(provisional)". The pack is regenerated
(`lua5.1 tools/make_pack.lua`) into Warrior.lua's `RegisterPack("Protection", ...)`.

## 5. Tests and the in-game checkpoint

### 5.1 Tests (busted, headless; the existing files)
- §1 `tests/Virtual/State/resources_spec.lua`: a `taken` slot gains `gain` on WOUND, BLOCKED, BLOCK, DODGE, PARRY,
  clamped to max, `lo`/`hi` by the width; a slot without `taken` unchanged; an unattributed hit (no hostile on us)
  still counts; `R.gain` explains a later flip (the scale stays 1); `VS.TakenRate`: three gains of 2 in 10 s give 0.6,
  0 after 10 quiet seconds and after `CombatEnd`. `adapter_spec.lua`: `__taken` generated with interval 1, value =
  the rate, `stop` with `time == 0`, absent from `auraRegen`; `taken` forwarded. `player_spec.lua` (sources):
  `UNIT_COMBAT` player maps to the seven kinds, flag BLOCK/BLOCK_REDUCED to BLOCKED; level from the target only when
  its target is the player. `alloc_spec.lua`: 100 hits and rate reads, 0 bytes. `tests/Forever/warrior_spec.lua`:
  magey's log 01 (armor 593, level-5 attacker, max 203, 110 pre-armor over 20 hits) gives 5.4 rage within the width;
  BLOCKED adds the cached block value; Defensive Stance divides by 0.9 only with `RAGE_BEFORE_REDUCTION`; Shield
  Specialization +5 on a block at rank 1; Master of Defense 2.5 on a dodge at rank 1 with a shield, 0 without.
- §2 `tests/Forever/engine_load_spec.lua` (the engine keys on `all`): `threat.situation`, `on_me`, `lost`, `loose`
  from a fake client, a secret answer reads 0/false. `tests/Virtual/Events/event_facade_spec.lua`: `LooseEnemies`
  counts plates whose target exists and is not us, deduped by GUID.
- §3 `auras_spec.lua`: `consumedBy` takes one stack per listed kind, removes at 0, ignores other kinds.
  `warrior_spec.lua`: Shield Block applies 2 stacks, has no `charges`; the 52-node pin unchanged.
- §4 `warrior_spec.lua`: the pack matches `make_pack.lua`; the "only registered names" test passes with the three
  settings and `threat`, its secret-token check unchanged (no `health.*`); no Last Stand, Shield Wall or Healthstone
  entry in the Protection lists; Shield Block's entry sits right after the threat entries; `packs_spec.lua` unchanged.
Every task ends with busted, luacheck, StyLua, LuaLS and the API-read check.

### 5.2 Checkpoint (user, in game)
A Protection-specced Warrior with a shield, ForeverProbe loaded (`VSCopy`, `/vscopy` reopens it; S = secret), open-
world mobs (no dummies). Possible at 22-30: Shield Block (16), Revenge (14), Taunt (10), Mocking Blow (16), Disarm
(18), Victory Rush (20), Challenging Shout (26), Concussion Blow (30, with 20 Protection points), Shield Specialization, Master of Defense. Waits for 40: Shield Slam (level 40, 30
points). Every line is under 255 characters.

| # | Question | Line | Answer -> action |
|---|---|---|---|
| Q0 | the build loads, the rate line exists | `/run local V,t=Hekili.VirtualState,GetTime() VSCopy(V.TakenRate(1,t),V.Power(1,t).est)` | numbers -> none; an error -> stop and report |
| Q1 | which Shield Block field counts blocks | out of combat, after Shield Block: `/run local a=C_UnitAuras.GetPlayerAuraBySpellID(2565) VSCopy(a and a.applications,a and a.charges,a and a.maxCharges,a and a.duration)` | `2` in one field -> the aura read maps it to stacks; 0/nil everywhere -> the belief alone (as designed) |
| Q2 | every hit reaches the belief | in a fight: `/run local f=CreateFrame("Frame")f:RegisterEvent("UNIT_COMBAT")f:SetScript("OnEvent",function(_,_,u,e,fl,a)if u=="player"then VSCopy(format("%.2f",GetTime()),e,fl,a)end end)` | after each hit `/run local r=Hekili.VirtualState.Power(1,GetTime()) VSCopy(format("%.1f %.1f %.1f",r.lo,r.est,r.hi),UnitPower("player",1))`: the estimate moves on every WOUND -> none |
| Q3 | Devastate / Commanding Shout known | `/run VSCopy(IsPlayerSpell(403196),IsPlayerSpell(403195),IsPlayerSpell(403215),IsPlayerSpell(29787),C_Engraving~=nil)` | all false -> nothing registered; true -> §3's registrations |
| Q4 | the rage factor at this level, Battle Stance | 20 hits in Battle Stance: the Q2 line plus `/run VSCopy(UnitPower("player",1),select(2,UnitArmor("player")),UnitHealthMax("player"),UnitLevel("target"))` before and after, out of combat | rage ~ sum(pre) x 10 / max -> none; another factor -> `RAGE_TAKEN_FACTOR` (data) |
| Q5 | Defensive Stance's 10% before the rage | Q4 again in Defensive Stance, same mob type | per post-armor point x 1/0.9 of Q4 -> `RAGE_BEFORE_REDUCTION = true`; equal -> `false` (D1) |
| Q6 | the armor step | Q4 with armor under 130 (remove pieces) | double -> D2 |
| Q7 | block value and the full block's amount | `/run VSCopy(select(2,UnitArmor("player")),GetShieldBlock(),InCombatLockdown())` in and out of combat; Q2 lines for `BLOCK` | plain out, S in -> the cache; a BLOCK amount above 0 -> use it in place of the EMA |
| Q8 | threat reads | in a fight: `/run VSCopy(UnitThreatSituation("player","target"),UnitThreatSituation("player"),UnitIsUnit("targettarget","player"),UnitExists("targettarget"),UnitIsUnit("nameplate1target","player"))` | plain -> none; S for the plate -> `threat.loose` counts the target and focus only (documented) |
| Q9 | Shield Specialization and Master of Defense numbers | `/run for _,i in ipairs({12298,1310316,12792,29787}) do VSCopy(i,C_Spell.GetSpellDescription(i)) end` at the current ranks | the chance and rage -> the `taken` constants |
| Q10 | the pseudo-spec's role | `/run local i=GetSpecialization() VSCopy(i,i and select(5,GetSpecializationInfo(i)),Hekili.State.role.tank)` | recorded (`tanking` is not used) |
| Q11 | the priority | a pull of one, then three | Taunt only when the mob turns away; Shield Block pressed whenever a block is spent and it is ready; Revenge after blocks; HS above the threshold as rage arrives from hits; Thunder Clap and Demoralizing first at 3+; never Last Stand, Shield Wall or a Healthstone |

## 6. Decisions (accepted 2026-10-16)
The user's rulings: no current-health model (the player's current health stays secret and unmodelled; the existing
`AplWarnings.lua` player-health rows stay), no defensives in the priority, Shield Block kept up unconditionally, the
rotation driven by the rage model. The remaining choices, each at its default, accepted:
- D1 **Stance and Shield Wall reduction before the rage:** assumed before (`RAGE_BEFORE_REDUCTION = true`, consistent
  with "pre-armor"); checkpoint Q5 decides. Accepted.
- D2 **The low-armor doubling:** not modelled (a tank wears more than 170 armor by level 10; a `shortcut:` comment);
  modelled only if Q6 reproduces it at the tank's level. Accepted.
- D3 **Rage thresholds:** Heroic Strike at 50 rage, Cleave at 40, Challenging Shout at 3 loose enemies (settings).
  Accepted.
- D4 **Mocking Blow:** only when already in Battle Stance; no stance swap for it (rage loss, Tactical Mastery keeps 10).
  Accepted.
- D5 **Shield Specialization's chance by rank:** 100% at every rank from the rank-1 row until Q9; Master of Defense 50%
  a rank and 5 rage (wow.gg and today's DB2; the 2026-10-15 reconcile read 2 rage). Accepted.
- D6 **Improved Shield Block / Improved Taunt / Defiance 5:** not registered / kept at 3 (the live tree lacks them);
  reopen only if a fresh export shows the nodes. Accepted.

## 7. Out of scope
Group attribution (hits on a party member, heals from others named, threat on other tanks) and the aura walk's cost in
groups: both go to a later "group fidelity" pass. The priority recommends no defensives (Last Stand, Shield Wall, Healthstone, a health gate on Bloodrage): the player
decides those. The player's current health is not modelled: it stays secret, `UnitHealth("player")` keeps its virtual
default and `AplWarnings.lua` keeps warning on `health.*` reads. Also out: simulating threat amounts (no per-ability values on
Forever beyond Sunder's 34), Improved Revenge's stun proc, Improved Shield Wall (its DB2 -11 min is implausible,
unread), Improved Bloodrage's DB2 +50% against the file's +25% tooltip reading (unchanged), per-target Sunder stacks in
AoE (one target's debuff is modelled), the sub-170-armor doubling (D2), Devastate and Commanding Shout until Q3,
Berserker Rage's extra rage from damage.
