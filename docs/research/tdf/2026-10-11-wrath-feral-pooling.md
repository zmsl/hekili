<!-- Ported from TacoDogForever docs/research/2026-10-11-wrath-feral-pooling.md (credit: TacoDogForever), copied here because that repo is being retired. -->
# Wrath Feral pooling logic (Zachary Samsel) -> Taco Dog Forever

Sources (read-only): `origin/wrath_release` (tip 02581b0a, 2023-10-26) and `origin/wrath` (Nov 2023 follow-ups).
Unless noted, `L###` = `git show origin/wrath_release:Wrath/Druid.lua` line numbers;
`simc:L##` = `origin/wrath_release:Wrath/APLs/DruidFeral.simc`. All of the Feral cat logic below is his
(`git log -S` attributes `excess_e`, `floating_energy`, the old per-refresh APL guards, `rip_now`'s CC branch,
`should_rake`, the trinket pooling and the settings to "Zachary Samsel").

## 0. Timeline (two generations of pooling)

| commit | date | what |
|---|---|---|
| 2b6fa9e2 | 2023-07-09 | Gen 1: per-refresh affordability guards written inline in APL conditions |
| ba5c98e9 | 2023-07-18 | Gen 2: replaced them with `excess_e` "to align energy pooling logic with the sim"; Shred gated on `excess_e>=action.shred.spend` |
| 3a187722 | 2023-07-20 | trinket-proc pooling, "pooling when refreshes are due and player is at 5cp" |
| 0dc73bc4 | 2023-07-23 | no Roar reservation at 0 CP / Roar outlasting the fight |
| 1c7e8010 | 2023-09-07 | "toggle on/off optimizations": settings `optimize_rake`, `optimize_trinkets` |
| 700d1747 | 2023-10-26 | fixed broken sort of `pending_actions` ("poor energy pooling recommendations"), AoE pooling, TF refactor, "removed unproven finisher pooling" |
| 2b92e1ca | 2023-10-26 | reverted TF carry-over model to simple "-60 on first refresh after TF"; re-added 5-CP finisher hold |
| 2117d8fe | 2023-10-26 | "Druid energy pooling work: simulation implementation for rip pooling" (removed debug `print("Holding for rip")`) |
| 8456070b | 2023-11-15 (wrath) | "Optimize rake now baseline logic": `should_rake` DPE test always on, setting removed |
| 704a3a8e..e8805f9c | 2023-11-15/18 (wrath) | trinket pooling handles multi-aura trinkets |

## 1. Mechanisms (Q1)

### 1a. Gen 1: inline per-refresh guards (2b6fa9e2; quoted from `ba5c98e9^:Wrath/APLs/DruidFeral.simc` L28-33)
Every filler/builder carried one guard per pending refresh:
```
shred,if=((combo_points.current<5|10+energy.current-action.shred.spend+debuff.rip.remains*10>=action.rip.spend)
  &(combo_points.current=0|10+energy.current-action.shred.spend+buff.savage_roar.remains*10>=action.savage_roar.spend)
  &(!debuff.mangle_cat.up|10+energy.current-action.shred.spend+debuff.mangle_cat.remains*10>=action.mangle_cat.spend)
  &(ttd<10|!should_rake|10+energy.current-action.shred.spend+debuff.rake.remains*10>=action.rake.spend))&!wait_for_ff
shred,if=energy.current=100
```
Formula per reservation R: `E_now - cost_filler + 10*R.remains + 10 >= cost_R`, i.e. energy at (R falls off + 1 s)
covers R. The `+10` is one second (= one cat GCD) of slack: Rip may be late by up to ~1 GCD. Gated on
whether R is actually castable then (Rip only at `cp=5`, Roar only at `cp>0`, Rake only if `should_rake`
and fight lasts). Weaknesses that motivated Gen 2: each guard is independent, so two refreshes due close
together are each "affordable" alone but not together; no cap handling except the separate `energy=100` line.

### 1b. Gen 2: `excess_e` floating-energy model (L413-566; Shred gate simc:L30)
`pending_actions` table (L413-430) holds `{refresh_time, refresh_cost}` for mangle_cat, rake, rip, savage_roar.
Single-target population (L436-475):
```lua
if debuff.rip.up and combo_points.current == 5 then
    pending_actions.rip.refresh_time = query_time + debuff.rip.remains
    pending_actions.rip.refresh_cost = (30 - (set_bonus.tier10feral_2pc == 1 and 10 or 0)) * (berserk_expected_at(query_time, query_time + debuff.rip.remains) and 0.5 or 1)
...
if debuff.rake.up and debuff.rake.remains < ttd - 9 and should_rake then   -- rake only if it will tick out
```
Roar only when `combo_points.current > 0` (added 0dc73bc4; wrath L480). On `origin/wrath` (L487-496) Rip and Roar
are mutually exclusive reservations (only the earlier one is reserved, since both need the same CPs).
Core accumulation (L500-525):
```lua
table.sort(sorted_actions, function(a,b) return pending_actions[a].refresh_time < pending_actions[b].refresh_time end)
local floating_energy, previous_time, tf_pending = 0, query_time, false
for i = 1, #sorted_actions do
  local entry = sorted_actions[i]
  if pending_actions[entry].refresh_time > 0 then
    local delta_t = pending_actions[entry].refresh_time - previous_time
    if not tf_pending then
      tf_pending = tf_expected_before(query_time, pending_actions[entry].refresh_time)
      if tf_pending then pending_actions[entry].refresh_cost = pending_actions[entry].refresh_cost - 60 end
    end
    if delta_t < pending_actions[entry].refresh_cost / 10 then
      floating_energy = floating_energy + pending_actions[entry].refresh_cost - 10 * delta_t
      previous_time = pending_actions[entry].refresh_time
    else
      previous_time = previous_time + pending_actions[entry].refresh_cost / 10
    end
  end
end
...
return energy.current - floating_energy        -- L565
```
Semantics: walk refreshes in time order; regen from `previous_time` funds the next refresh first. If the
window `delta_t` regenerates less than its cost, the shortfall `cost - 10*delta_t` must already be banked now
("floating"); else the refresh consumes `cost/10` seconds of future regen and later refreshes only get regen
after that. `excess_e = energy - floating` = energy you may spend now without delaying any known refresh.
Note the `sorted_actions` sort bug fixed in 700d1747 — ordering is load-bearing.

Shred gate (simc:L30):
```
shred,if=!wait_for_ff&(excess_e>=action.shred.spend|buff.clearcasting.up|buff.berserk.up|(cooldown.faerie_fire_feral.remains<=1&energy.current>77|energy.current=100))
```
Escape hatches: free (CC), cheap (Berserk halves costs), about to gain energy/OoC chance (FF), or capped.

### 1c. Energy-credit for a cooldown that grants energy (Tiger's Fury) (L361-369, L510-516)
`tf_expected_before(now, t)` = TF cooldown (or Berserk, which blocks TF) ends before t. The FIRST refresh
after TF becomes available gets `cost -= 60` (TF = +60 energy). Can go negative: then the `else` branch moves
`previous_time` backwards, i.e. surplus credit carries to later refreshes. A more exact carry model (`tf_carry`,
min(carry, cost) per refresh) was tried and reverted in 2b92e1ca. TF itself is used `if=energy.current<30-(CC&15)`
(simc:L16), so credit assumes TF is pressed when it comes up.

### 1d. Cost scaling by future buffs (L378-393)
`berserk_expected_at(now, t)` -> reservation cost halved if Berserk (-50% cost) will be up at refresh time.

### 1e. "Hold everything for the finisher" at 5 CP (L557-563; re-added 2b92e1ca)
```lua
if combo_points.current == 5 and not (bite_before_rip or bite_at_end)
    and (not trinket_active) and buff.savage_roar.up and buff.savage_roar.remains < ttd
    and rip_refresh_pending
    and min(buff.savage_roar.remains, debuff.rip.remains) < time_to_cap - query_time then
        floating_energy = max(floating_energy, 100)
```
`time_to_cap = query_time + (100 - energy.current)/10` (L527); `rip_refresh_pending = rip.up & cp=5 &
rip.remains < ttd - end_thresh` (L568-570, end_thresh=10 L286). At 5 CP a builder's CP is wasted, so if the next
finisher lands before energy would cap, reserve the full bar: Shred then only fires via `energy.current=100`.
Pooling here is free (energy is only lost at cap) and maximises post-finisher energy.

### 1f. Trinket pooling (`optimize_trinkets`, L529-555; multi-aura in wrath e8805f9c)
Earliest internal-cooldown proc = `buff.last_application + action.cooldown`; if no trinket buff active, proc
comes before `time_to_cap`, and proc buff ends before fight end -> `floating = max(floating,100)` (pool to cap
so the burst window is spent under the proc). Gated on `debuff.rip.up`.

### 1g. Rip timing / Clearcasting / clipping
- `rip_now` (L315-327): `!debuff.rip.up & cp=5 & ttd>=end_thresh`; but if CC is up, Rip only if
  `rip_cast_time = max(1.0, (rip.spend - energy)/10 + latency) >= buff.savage_roar.remains` — i.e. spend the
  free CC on Shred first and Rip one GCD later, unless that would cost Roar. Rip never clips (needs `!up`).
- Rake: `rake,if=!up&!buff.clearcasting.up&(should_rake|!debuff.bleed.up)&ttd>9&!wait_for_ff` (simc:L26);
  CC Rake only if no bleed (L25). Never clips; skipped if target dies before 9 s of ticks.
- Mangle debuff: `!debuff.mangle.up&ttd>1` (L24). `clip_mangle` (L339-343) end-of-fight count math, unused in APL.
- Roar vs Rip desync: `rip_maxremains` (Shred-glyph extension, L234-240), `sr_new_duration` (L242-247), APL L21
  clips Roar only if it would expire before Rip+`rip_leeway` and the new Roar outlasts Rip by `min_roar_offset`.
- Bite: `bite_at_end` (5 CP and fight ends <10 s or Rip covers to end, L290-293), `bite_before_rip`
  (Rip/Roar remains above settings, L295-298), energy<67 & no CC (simc:L23).

### 1h. "Optimizations" toggle / Rake baseline
`should_rake` (L265-272) = T9-2pc/T10-4pc or `rake_dpe >= shred_dpe` from `calc_rake_dpe` (L349-359: armor,
ArP, AP, crit formulas) `or not settings.optimize_rake` (L2968). 8456070b made the DPE test unconditional.
`optimize_trinkets` (L2980) gates 1f.

### 1i. Other end-of-fight / weave guards (same pattern: "do X only if no refresh lands inside X's window")
`can_spend_ff` (L395-400), `wait_for_ff` (L402-411: wait for FF if `energy + 10*(ff.remains+latency) < 87`, no CC,
Rip not due within 1 s), `should_flowerweave`/`should_bearweave` (L572-608: require
`!rip_refresh_pending | rip.remains >= weave_end`, no TF/FF expected in window, enough fight left to dump energy).

## 2. The math (Q2)

Energy model: Wrath energy is continuous; `spec:RegisterResource( Enum.PowerType.Energy )` (L663) has no tick
model, and his code hard-codes **10 energy/s** and **cap 100** everywhere (`/10`, `*10`). He never uses
`energy.regen` or `energy.time_to_X`, though Hekili State provides them (`state:TimeToResource`:
`max(0, pad + (amount - current)/regen)`, wrath_release State.lua L3447-3448; `time_to_<n>` / `time_to_max`
L3509-3520; `pad` is 0.1 s tick alignment only when `lastTick` exists — not for Druid energy).

- Energy at T (implicit, no cap): `E(T) = E0 + 10*(T - now)`.
- Gen 1 single reservation: filler OK iff `E0 - c_f + 10*(T_R - now) + 10 >= c_R`.
- Gen 2 multi-reservation: `excess = E0 - sum_i max(0, c_i - 10*(T_i - p_i))` with `p_1 = now`,
  `p_{i+1} = T_i` if shortfall else `p_i + c_i/10`. Filler OK iff `excess >= c_f`.
- Credits: `c_i -= 60` for first refresh after TF; `c_i *= 0.5` if Berserk up at `T_i`.
- Cap: `time_to_cap = now + (100 - E0)/10`; used only to decide "pool to 100" (1e, 1f). Inside the main formula
  cap is ignored; the `energy.current=100` Shred clause is the anti-waste valve.
- GCD: not modelled in `excess_e` (Wrath cat GCD = 1.0 s = 10 energy; the Gen 1 `+10` is that slack).
  `rip_now` uses `max(1.0, deficit/10 + latency)` as "time until Rip can go".
- Property worth knowing: inside a pooling window, `excess(t)` is constant
  (`E0 + 10(t-now) - (c - 10(T - t))` = `E0 - c + 10(T-now)`), outside it grows at regen. So `excess(t)` is
  piecewise linear -> flip times are analytic.
- State exprs/functions he added (all `spec:RegisterStateExpr/Function`): `excess_e`, `rip_refresh_pending`,
  `rip_now`, `should_rake`, `calc_rake_dpe`, `tf_expected_before`, `ff_expected_before`, `berserk_expected_at`,
  `can_spend_ff`, `wait_for_ff`, `ff_during_berserk`, `bite_at_end`, `bite_before_rip`, `bite_during_berserk`,
  `wait_for_tf`, `ttd` (training-dummy override), `end_thresh`, `rip_canextend`, `rip_maxremains`,
  `sr_new_duration`, `mangle_refresh_now/pending`, `clip_mangle`, `should_flowerweave/bearweave/cat`.
  No `pool_resource` anywhere; Hekili's APL had no reservation primitive, hence the expression approach.

## 3. Reusability for Taco Dog Forever (Q3)

(a) idea/formula -> Pick reservation or engine-computed registry expression
- Floating-energy chain (1b) — the core. Directly answers "Rip and Rake both coming due" which a single
  `for_next=1` reservation misses. Port with `s.regen`, `s.energyMax` instead of 10/100.
- Energy-credit cooldown (1c) -> **Shifting Power** (+40, 16 s cd, used at <50 energy): credit 40 to the first
  reservation after `cdReady[shifting_power]`, only if SP will actually be used (energy <50 then is likely when
  pooling, so usually yes). Keep his simple non-carry version (carry model was reverted).
- 5-CP hold-to-cap (1e): at cp=5 with Rip pending before time-to-cap, Shred only at cap. In Forever (no Bite)
  Shred at 5 CP wastes CP gain; pooling costs nothing unless capped. Reusable as idea; see 4 for the rule.
- Fallback valve "Shred at cap" (1b gate): mandatory in any variant.
- Sort-by-time + ordering correctness (700d1747 bug).
- Inside-window constant excess -> analytic flip times for our `cond` rechecks.

(b) APL conditions with new registry expressions
- Gen 1 guard, generalised:
  `shred,if=cp<5|debuff.rip.up&energy-action.shred.cost+energy.regen*(debuff.rip.remains)>=action.rip.cost`
  and same for Rake (no cp gate). New exprs: `action.X.cost`, `energy.regen`, optionally
  `energy.time_to_max` (anti-cap: `|energy.time_to_max<=gcd.max`), `gcd.max`.
- `energy.excess` (or `excess_e`) as an engine-computed expression over declared reservations
  (rip if cp=5, rake) with Shifting Power credit; then `shred,if=energy.excess>=action.shred.cost|energy.time_to_max<=gcd.max|buff.clearcasting.up`.
- Fight-end guards: `rake,if=...&target.time_to_die>9`, Rip `ttd>=10` — need a `target.time_to_die` expr
  (we only have `targetHealthPct`; optional).
- CC-first-then-Rip (1g): `rip,if=!debuff.rip.up&cp=5&!buff.clearcasting.up` with Shred taking CC first;
  needs `buff.clearcasting.*` (we have `clearcastable`). Costs one GCD of Rip delay — make it a `settings.X`
  since the theorycrafter says minimise delay.

(c) not applicable
- Savage Roar (Roar reservation, rip/roar desync, `rip_leeway`, `min_roar_offset`, `sr_new_duration`,
  Rip/Roar mutual exclusion), Berserk cost halving, Tiger's Fury (replaced by SP analogue), Mangle debuff
  upkeep, Faerie Fire/OoC glyph waits (`wait_for_ff`, `can_spend_ff`), Shred-glyph Rip extension
  (`rip_maxremains`), Ferocious Bite logic (not in priority), `calc_rake_dpe` (Wrath ArP/armor formulas; the
  rotation always Rakes), trinket ICD pooling, tier sets/idols, bear/flower weaving, AoE (Swipe/idol) branch,
  Hekili recheck hacks (`debuff.x.up!=debuff.x.up`, Gen 2 era) — our flip times replace them. Energy ticks: Wrath
  code already assumes continuous regen, so nothing to unlearn there; no bleed snapshot logic existed.

## 4. Recommendation (Q4)

Do it in **Pick as a reservation**, but implement it as his chained `excess_e` (multi-reservation) rather than
a single `for_next=1`, and expose the same number as a registry expression for APL authors/debugging. Concretely:

1. APL marks reservation targets, e.g. `rip,reserve=1,if=!debuff.rip.up&combo_points=5` and
   `rake,reserve=1,if=!debuff.rake.up` (or `pool_resource,for_next=1` before each — same compiled flag).
2. In Pick, for each reserve entry r with flip time `T_r` (when its cond becomes true, not when affordable)
   and cost `c_r`, build the time-sorted list and compute floating energy exactly as L504-525, with
   `regen = s.regen`, credits for energy-granting cooldowns (Shifting Power +40, flagged in ability data
   `grantsEnergy=40`) applied to the first reservation after its `cdReady`.
3. A non-reserve entry f ready at `t0 < T_r` is taken only if
   (i) `E(t0) - c_f >= floating(t0)` (equivalently: the reserved entries are not delayed), and
   (ii) `t0 + gcd <= T_first` (GCD alignment; his code never had this — with 1.0 s GCD and 10/s regen it is
   worth 10 energy, which is why Gen 1 had `+10` slack. Add a tolerance setting, default ~0.1-0.2 s), OR
   (iii) cap valve: `E(t0) + regen*(T_first - t0) > energyMax` and spending f doesn't push r later —
   wasting energy at cap is strictly worse than shredding,
   OR f is free (Clearcasting).
   Better single criterion (handles cap, current shortfall and GCD at once): compute
   `t_r_with = max(T_r, t0+gcd, t0 + (c_r - (E(t0)-c_f))/regen)` vs
   `t_r_without = max(T_r, now_gcd_end, t0 + (c_r - E(t0))/regen)` and allow f iff `t_r_with <= t_r_without + tol`.
4. Only reserve when the reserved entry will actually be castable at `T_r`: Rip only if cp=5 now (his
   `combo_points.current == 5` gate) — a Shred at 4 CP is what *enables* Rip, so do not reserve against it;
   Rake always (rotation never skips it); drop a reservation if `T_r` is past fight end if ttd exists.
5. Also publish `energy.excess` (same computation at sim time t) + `energy.regen`, `energy.time_to_max`,
   `action.X.cost`, `gcd.max` so the APL can override/tune and tests can assert numbers.

Why not APL-only: Gen 1 guards (one per reservation per filler) were exactly what he abandoned — they don't
chain, don't see cooldown credits, duplicate across every filler, and need constant-time rechecks; our `cond`
flip-time machinery would have to solve each guard anyway. Why not plain `for_next=1`: SimC semantics only pool
for the immediately next entry *when its condition is already true*; it does nothing while Rip is still up but
about to fall off, which is the whole problem.

Pitfalls his work handled that a naive version misses:
- **Multiple refreshes close together** (Rip+Rake ~5 s apart, each 30-40 energy, Shred 48-60): independent
  checks each pass, the sum fails -> late Rake. Chain them (1b).
- **Ordering**: the chain is only valid when sorted by time (700d1747 bug fix).
- **Cap waste**: pooling past 100 throws energy away; always keep a "Shred at/near cap" valve
  (`energy.current=100`; better `energy.time_to_max <= gcd`).
- **Energy-granting cooldown**: ignoring TF (here Shifting Power, +40) over-pools by up to 40 energy (~4 s of
  Shreds lost). Credit only the first reservation after it is ready; don't over-engineer carry (reverted).
- **CP gating**: reserving for Rip below 5 CP blocks the very builder that enables it.
- **5 CP and nothing to spend CP on**: hold to cap (1e) — fillers then only waste CP; pooling is free.
- **Clearcasting**: a free Shred never violates a reservation; and Rip-with-CC wastes the proc (1g).
- **Early vs late**: he never refreshed early (`!up` everywhere, Rip/Rake never clipped); slack was tolerated
  late (Gen 1 `+10` = 1 GCD; `wait_for_ff` `max_ff_delay` 0.1 s). Keep "never clip", add an explicit late
  tolerance rather than implicit fudge.
- **End of fight**: don't reserve for (or cast) a bleed that won't tick out (`rake.remains < ttd-9`,
  `ttd>=end_thresh`) — only if we add a TTD expression.
- **Latency**: `rip_cast_time` adds `latency`; our sim times should include a small reaction pad too.
