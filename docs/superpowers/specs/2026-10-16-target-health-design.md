# Target health from health-gated usability (design note, 2026-10-16)

Status: DRAFT, awaiting the user's checkpoint results (§7, lines 2 and 4 decide §2.3b and §2.3a). Base: 605b6dcb.
Paths are under `src/Hekili/` unless they start with `tests/`, `tools/` or `docs/`.

Corrections to the audit (docs/research/2026-10-15-api-events-audit.md): Execute IS recommended when the client says it is
usable: `usable` and `execute_phase` read `IsSpellUsable` live through `reactive()` (Forever/Classes/Warrior.lua:102-109,
997-999, 1555-1557) and the packs gate the execute list on it (tools/packs/warrior.lua:15, 30, 55). What is missing is a
moving `target.health.pct` and a real `time_to_die`. The `ttd` belief (Player.lua:52-54, 95-97, default 30) has no
callers: Hekili's `time_to_die` comes from Targets.lua's own tracker (`GetTTD` :1257, default 300 `FOREVER` :1163).

## 1. Facts
- Target health is a constant: `health other` is fixed at 1 (Virtual/State/Families/Player.lua:47-49); `VS.Health` returns
  it for every unit but the player (:77); `VS.HealthMax` is 100 (:81-86); the facade answers `UnitHealth("target")` as
  est*100 and `UnitHealthMax` as 100 (Virtual/API/Facade.lua:264-279). UnitHealth is secret always ([W PR14],
  docs/forever-facade-notes.md:167-168; the Forever API data marks UnitHealth/UnitHealthPercent `secretReturns`).
  UnitHealthMax is NOT marked: it is governed by `C_Secrets.ShouldUnitHealthMaxBeSecret(unit)` → unverified (§7 line 2).
- `target.health.pct` = 100*current/max (State.lua:2862-2871): it moves if the facade's answer moves. `time_to_die`,
  `real_ttd`, `time_to_pct_N` (State.lua:2799-2811) go through `Hekili:GetTTD`/`GetTimeToPct` (Targets.lua:1257-1314):
  a 0.5 s regression over UnitHealth/UnitHealthMax (UpdateTTDs :1540-1575, ticker :1605; rate = mean of up to 10 drops
  :1196-1212); dummies answer 180 (:1258).
- Usability observations exist only for spenders: `C_Spell.IsSpellUsable` is asked for abilities with a spend slot
  (Sources/Power.lua:23-24), logged as `Obs.Usable` with b=1 usable, c=1 short of power (:32-43), on change (:58-64) and
  every poll-2 answer (:128-130). Execute spends rage, so it is asked. Range is NOT part of IsSpellUsable.
- Pattern to mirror: the cost ladder (Families/Resources.lua:402-440), the flip pin (:384-397, 456-466), NOT answers give
  no rung (:449); basis = newest of observed/pinned/modelled by t, else default (VirtualState.lua:130-144).
- The ability table reaches the belief unchanged: buildDef keeps Hekili's table (Adapter.lua:162-172), Casts stores it as
  `I.ab.obj[a]` (Families/Casts.lua:69); RegisterAbility stores non-function fields raw (Engine/Spec.lua:780-788). No
  Adapter change for a new declarative field.
- Target identity: `UnitGUID("target")` → a memory slot (16, LRU) then `Obs.TargetSwap` (a = slot) (Sources/Target.lua:22-55);
  death from plain `UnitIsDead` → `TargetGone` (:69-78); Auras keep `I.curSlot` (Families/Auras.lua:183-198).
- Damage taken by the target: `UNIT_COMBAT` on `target` is plain with WOUND amounts (O-O1: 374 firings, 0 secret;
  docs/research/tdf/2026-10-14-virtual-combat-log-events.md:91, 215). Rows.lua pairs it only with our own swings/casts and
  drops the rest (Events/Rows.lua:140-155, 168-170): the family reads the raw event. Victim-side events include other
  players' damage, which is right for ttd.

## 2. Design
2.1 Field: `healthGate = 0.2` on `execute` (Warrior.lua:981); later Hammer of Wrath. At build the family reads
`rawget(I.ab.obj[a], "healthGate")` and resolves the ability's `buff`/`nobuff` (Execute: `nobuff = "defensive_stance"`,
Warrior.lua:994) to a player aura index like `swingAura` (Resources.lua:179-188): 0 none, -1 named but untracked. No class
names in the engine.

2.2 Family `Virtual/State/Families/TargetHealth.lua`, current target only, health as a fraction 0..1. Scalars: est0/lo0/hi0;
`dmg` (WOUND total since the swap), `dmgT0` (first WOUND); `M` (damage per full health, 0 unknown); `fresh` (an anchor at
1.0 is valid: the slot was never targeted before); `prev[a]` (last usability per gated ability). Per memory slot `maxBy[s]`
so a swap back keeps M. Records `health target` and `ttd target` from `I.NewBelief`.

2.3 Observations:
(a) `Obs.Usable` for gated ability a with `I.curSlot > 0`: usable (b=1) — or short (c=1) if §7 line 4 shows short implies
at or below the gate — means health ≤ g. From NOT with `lag <= I.PIN_EXACT`: a flip → pin [g - slack, g] (slack = damage
since the last NOT answer / M, 0 if M unknown), `pinned` sample; if `fresh` and dmg > 0 and M unknown, learn
M = dmg / (1 - g). Otherwise a ladder rung: hi0 = min(hi0, g), est snapped (`pinned` only when est moved).
NOT (b=0, c=0): health > g only under every guard of §5: lo0 = max(lo0, g + EPS), est raised if below.
(b) Plain max (only if §7 line 2 shows UnitHealthMax("target") plain): read at the swap and in poll 1 as Read/ReadOf.Max
(a = 0), sets M `observed`; an observed max wins over a learned one (`maxRead`, as Resources.lua:486-490).
(c) New `Obs.TargetDamage = 35` (b = amount), staged from `S.On("UNIT_COMBAT","target")` WOUND in Sources/Target.lua: add to
dmg; if M > 0 move est0/lo0/hi0 down by amount/M, floor 0.02 while alive (Targets.lua:1552 drops an enemy at ≤ 1), write
`modelled`; if M unknown nothing moves.
(d) Resets: TargetSwap → store maxBy[old] = M, load the new slot's M, default 1/[0,1], dmg = 0, `fresh` = slot was empty
(Target.lua:28-38 gains a first-use flag). TargetGone for curSlot → 0, `observed`. CombatEnd → default (an evade heals).
Basis as I.Basis: a flip pin is `pinned`; later WOUNDs are newer `modelled` samples from that anchor (as swings after a pin,
Resources.lua:462 vs :513); death `observed`; before any, `default`.

## 3. What reads answer
- `VS.Health("target")` returns the family's record (Player.lua:77 dispatches unit == "target"; other units keep otherHealth).
- Facade unchanged: `UnitHealth("target")` = est*100, `UnitHealthMax` = 100 (Facade.lua:267-268, 277-279) → `target.health.pct`
  = est*100; `execute_phase` stays on the client's answer (already exact).
- ttd: `VS.TTD("target", now)` = est*M / dps, dps = dmg / (now - dmgT0), basis `modelled` when M > 0 and dps > 0; else the
  default record. Add `VS.TimeToPct(p, now)` = (est - p)*M / dps.
- Named core edit, Targets.lua:1257 `GetTTD` and :1288 `GetTimeToPct`: after the dummy check, for unit == "target" return the
  VS answer (ceil, n = 3) when its basis is not `default` (otherwise the jump at a pin poisons Hekili's 10-sample mean ~5 s).

## 4. Allocation
Records, per-ability arrays (prev, guard aura index) and maxBy[1..TARGET_CAP] allocated at build/load; appliers and accessors
do scalar arithmetic; UNIT_COMBAT stages numbers (S.Stage, Sources.lua:36-46).

## 5. Guards on the "above the gate" pin (a NOT answer)
1. known (`I.ab.known[a] ~= false`); 2. power believed sufficient: `I.res.lo0[slot] >= I.CostOf(a)`; 3. `nobuff` aura believed
down / `buff` believed up (index -1 → no NOT pins at all); 4. `I.curSlot > 0` and not dead; 5. target attackable
(TargetSwap c = 1 from plain `UnitCanAttack("player","target")` at the swap). Range is not part of IsSpellUsable; Execute has
no cooldown.

## 6. Tests (tests/Virtual/State/target_health_spec.lua; fake api and a fake spec with a gated spender)
1 flip pin → est 0.2, hi 0.2, `pinned`; fresh dmg 800 → M 1000. 2 no pin when power short (`{false,true}` with lo < cost); a
NOT with low rage changes nothing. 3 no pin when the stance guard fails. 4 slope: WOUNDs 50+50 at M 1000 → est 0.1,
`modelled`; TTD = est*M/dps. 5 floor 0.02 alive; TargetGone → 0 `observed`. 6 swap reset default 1.0, dmg 0; swap back keeps
M. 7 facade: UnitHealth("target") = est*100, UnitHealthMax 100; GetTTD("target") returns the VS answer once basis ≠ default.
8 alloc_spec: target UNIT_COMBAT, gated flips, VS.TTD/VS.Health("target").

## 7. Checkpoint lines (open-world mob; dummies answer a fixed 180 and may never drop below 20%)
1. Execute flips vs health (in combat, watch the bar; the frame prints each change):
`/run local f=CreateFrame("Frame")f:SetScript("OnUpdate",function()local u,n=C_Spell.IsSpellUsable(5308)if u~=f.u or n~=f.n then f.u,f.n=u,n VSCopy(format("%.2f",GetTime()),u,n)end end)`
2. Max readability, out of combat then in combat:
`/run local m=UnitHealthMax("target")VSCopy(InCombatLockdown(),issecretvalue(m),not issecretvalue(m) and m,C_Secrets and C_Secrets.ShouldUnitHealthMaxBeSecret and C_Secrets.ShouldUnitHealthMaxBeSecret("target"))`
3. Damage amounts summed to the kill (compare with the mob's max):
`/run local s=0 local f=CreateFrame("Frame")f:RegisterUnitEvent("UNIT_COMBAT","target")f:RegisterEvent("PLAYER_TARGET_CHANGED")f:SetScript("OnEvent",function(_,e,u,a,_,n)if e=="UNIT_COMBAT"then if a=="WOUND"then s=s+n end else VSCopy("sum",s)s=0 end end)`
4. Short vs health: with under 15 rage, line 1 on a mob above 20% and below 20%; repeat in Defensive Stance (does short mean
at or below the gate; does a wrong stance give false,false).

## 8. Open questions and risks
- IsSpellUsable false for non-health reasons: wrong stance, not known, no/friendly/dead target, short of power, possibly
  crowd control on the player (unmeasured, no guard; §7 line 4 extended).
- A pre-damaged target (group, or a mob already fighting) overestimates M; the next pin or death corrects est, not M.
  shortcut: one anchor per target; upgrade with a per-npcid max learned at kills.
- Not covered: ttd above the gate, or classes with no gated ability (Druid), unless the max is plain (§7 line 2).
  `fight_remains`/`GetGreatestTTD` (State.lua:1811-1828) keep Hekili's tracker.
- A future proc making Execute usable at any health would pin wrongly: needs a `buff` guard like the stance one.
- Unchecked: that VirtualState sees stance auras through UNIT_AURA (guard 3); Hammer of Wrath (no Paladin file).

## 9. Placement
VirtualState.lua `Obs.TargetDamage = 35`; new Families/TargetHealth.lua (TOC after Families\TargetCast.lua); Player.lua
VS.Health/VS.TTD dispatch for "target"; Sources/Target.lua UNIT_COMBAT handler and TargetSwap c; Warrior.lua `healthGate`;
Targets.lua GetTTD/GetTimeToPct edit; tests as §6.
