## Run 4: real traces, lumpy damage, opener timing (seed set A, LHV band contract)

Score = weighted mean of (term / median of the main lineup's term); weights: unknown 1, relMed 0.5, relP90 0.5, wrongMean 1, flipSum 1. Lower is better. scale=0.3

Replay oracle: 56 of 65 logged sink lines reproduced within 0.05 (worst inf).
- miss: F3 t=9.16 logged 14.37 replay off by 0.07
- miss: F3 t=11.11 logged 45.35 replay off by 0.07
- miss: F3 t=15.88 logged 16.47 replay off by 1.09
- miss: F3 t=17.59 logged 17.27 replay none
- miss: F3 t=22.25 logged 13.81 replay none
- miss: F3 t=26.66 logged 8.20 replay off by 0.25
- miss: F3 t=30.01 logged 2.38 replay none
- miss: F3 t=33.02 logged 0.06 replay none
- miss: F4 t=15.78 logged 24.89 replay off by 0.06

| fight | logged lines: n, rel med / p90 (/ true), wrong 5 s | replayed sink lines: same, truth in [lo, hi] |
|---|---|---|
| F1 | 17, 0.364 / 1.012, 5.9% | 17, 0.364 / 1.011, 5.9%, 17.6% |
| F2 | 12, 0.311 / 0.822, 8.3% | 14, 0.310 / 0.819, 7.1%, 28.6% |
| F3 | 14, 0.244 / 0.571, 7.1% | 16, 0.250 / 1.053, 6.2%, 25.0% |
| F4 | 12, 0.296 / 0.585, 8.3% | 12, 0.297 / 0.586, 8.3%, 16.7% |
| F6 | 9, 0.333 / 0.797, 22.2% | 10, 0.330 / 0.796, 20.0%, 20.0% |

### Real traces (owner, 2026-11-21a: 5 kills, one melee spec solo; reads every 0.1 s, scored from combat or the first band to the death)

| candidate | rel med / p90 | probe rel med / p90 | truth in [lo, hi] | hi:lo med / p90 | wrong 5 s | wrong 8 s | unknown | excess flips/min | under 1/4 | read dead | rel med per fight F1 F2 F3 F4 F6 | in [lo, hi] per fight |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| newAnchor 0.1 | 0.31 / 0.58 | 0.34 / 0.77 | 19.5% | 1.11 / 6.00 | 13.3% | 10.2% | 5.9% | 3.4 | 0.0% | 0.9% | 0.40 0.32 0.15 0.33 0.37 | 11 22 15 25 27 |
| newAnchor 0.1 + rangeZ 1.15 | 0.31 / 0.58 | 0.34 / 0.77 | 85.2% | 3.17 / 9.00 | 13.3% | 10.2% | 5.9% | 3.4 | 0.0% | 0.9% | 0.40 0.32 0.15 0.33 0.37 | 60 90 92 89 94 |
| newAnchor 0.1 + rangeZ 1.15, rangeMax 2 | 0.31 / 0.58 | 0.34 / 0.77 | 82.4% | 3.17 / 6.00 | 13.3% | 10.2% | 5.9% | 3.4 | 0.0% | 0.9% | 0.40 0.32 0.15 0.33 0.37 | 52 88 92 88 90 |
| newAnchor 0.1 + rangeZ 1, rangeOwn | 0.31 / 0.58 | 0.34 / 0.77 | 75.8% | 3.28 / 6.00 | 13.3% | 10.2% | 5.9% | 3.4 | 0.0% | 0.9% | 0.40 0.32 0.15 0.33 0.37 | 60 61 93 75 85 |
| newAnchor 0.1 + rangeZ 1.3, rangeOwn | 0.31 / 0.58 | 0.34 / 0.77 | 85.0% | 4.69 / 8.13 | 13.3% | 10.2% | 5.9% | 3.4 | 0.0% | 0.9% | 0.40 0.32 0.15 0.33 0.37 | 83 74 93 81 94 |

### Set: lumpy (3 classes; score against the main lineup's medians)

| candidate | score | unknown | rel med / p90 | wrong (mean of 4) | excess flips/min | first answer med s | truth in [lo, hi] | hi:lo med / p90 | under 1/4 | read dead |
|---|---|---|---|---|---|---|---|---|---|---|
| newAnchor 0.1 | 1.027 | 9.4% | 0.33 / 0.80 | 16.8% | 15.61 | 1.87 | 13.4% | 1.10 / 6.00 | 2.8% | 2.4% |
| newAnchor 0.1 + rangeZ 1.15 | 1.027 | 9.4% | 0.33 / 0.80 | 16.8% | 15.61 | 1.87 | 70.9% | 3.27 / 9.00 | 2.8% | 2.4% |
| newAnchor 0.1 + rangeZ 1.15, rangeMax 2 | 1.027 | 9.4% | 0.33 / 0.80 | 16.8% | 15.61 | 1.87 | 66.5% | 3.27 / 6.00 | 2.8% | 2.4% |
| newAnchor 0.1 + rangeZ 1, rangeOwn | 1.027 | 9.4% | 0.33 / 0.80 | 16.8% | 15.61 | 1.87 | 57.9% | 2.34 / 6.00 | 2.8% | 2.4% |
| newAnchor 0.1 + rangeZ 1.3, rangeOwn | 1.027 | 9.4% | 0.33 / 0.80 | 16.8% | 15.61 | 1.87 | 67.9% | 3.02 / 6.52 | 2.8% | 2.4% |

### lumpy: rel median per class

| algorithm | lumpy solo | lumpy instant | lumpy pair |
|---|---|---|---|
| newAnchor 0.1 | 0.33 | 0.37 | 0.28 |
| newAnchor 0.1 + rangeZ 1.15 | 0.33 | 0.37 | 0.28 |
| newAnchor 0.1 + rangeZ 1.15, rangeMax 2 | 0.33 | 0.37 | 0.28 |
| newAnchor 0.1 + rangeZ 1, rangeOwn | 0.33 | 0.37 | 0.28 |
| newAnchor 0.1 + rangeZ 1.3, rangeOwn | 0.33 | 0.37 | 0.28 |

### lumpy: wrong side per class

| algorithm | lumpy solo | lumpy instant | lumpy pair |
|---|---|---|---|
| newAnchor 0.1 | 14.7% | 15.5% | 20.2% |
| newAnchor 0.1 + rangeZ 1.15 | 14.7% | 15.5% | 20.2% |
| newAnchor 0.1 + rangeZ 1.15, rangeMax 2 | 14.7% | 15.5% | 20.2% |
| newAnchor 0.1 + rangeZ 1, rangeOwn | 14.7% | 15.5% | 20.2% |
| newAnchor 0.1 + rangeZ 1.3, rangeOwn | 14.7% | 15.5% | 20.2% |

### lumpy: unknown per class

| algorithm | lumpy solo | lumpy instant | lumpy pair |
|---|---|---|---|
| newAnchor 0.1 | 11.7% | 8.8% | 7.6% |
| newAnchor 0.1 + rangeZ 1.15 | 11.7% | 8.8% | 7.6% |
| newAnchor 0.1 + rangeZ 1.15, rangeMax 2 | 11.7% | 8.8% | 7.6% |
| newAnchor 0.1 + rangeZ 1, rangeOwn | 11.7% | 8.8% | 7.6% |
| newAnchor 0.1 + rangeZ 1.3, rangeOwn | 11.7% | 8.8% | 7.6% |
ttd lab run4 done in 80.9 s

### Set: old (13 classes; score against the main lineup's medians)

| candidate | score | unknown | rel med / p90 | wrong (mean of 4) | excess flips/min | first answer med s | truth in [lo, hi] | hi:lo med / p90 | under 1/4 | read dead |
|---|---|---|---|---|---|---|---|---|---|---|
| newAnchor 0.1 | 0.854 | 2.5% | 0.16 / 0.47 | 6.8% | 10.22 | 0.91 | 17.3% | 1.05 / 1.53 | 0.7% | 0.4% |
| newAnchor 0.1 + rangeZ 1.15 | 0.854 | 2.5% | 0.16 / 0.47 | 6.8% | 10.22 | 0.91 | 71.7% | 1.82 / 6.00 | 0.7% | 0.4% |
| newAnchor 0.1 + rangeZ 1.15, rangeMax 2 | 0.854 | 2.5% | 0.16 / 0.47 | 6.8% | 10.22 | 0.91 | 71.2% | 1.82 / 4.00 | 0.7% | 0.4% |
| newAnchor 0.1 + rangeZ 1, rangeOwn | 0.854 | 2.5% | 0.16 / 0.47 | 6.8% | 10.22 | 0.91 | 73.7% | 1.77 / 4.74 | 0.7% | 0.4% |
| newAnchor 0.1 + rangeZ 1.3, rangeOwn | 0.854 | 2.5% | 0.16 / 0.47 | 6.8% | 10.22 | 0.91 | 80.3% | 2.10 / 6.00 | 0.7% | 0.4% |

### Set: run 2 (20 classes; score against the main lineup's medians)

| candidate | score | unknown | rel med / p90 | wrong (mean of 4) | excess flips/min | first answer med s | truth in [lo, hi] | hi:lo med / p90 | under 1/4 | read dead |
|---|---|---|---|---|---|---|---|---|---|---|
| newAnchor 0.1 | 0.875 | 1.8% | 0.23 / 0.61 | 7.3% | 4.69 | 1.05 | 13.7% | 1.04 / 1.12 | 0.0% | 0.0% |
| newAnchor 0.1 + rangeZ 1.15 | 0.875 | 1.8% | 0.23 / 0.61 | 7.3% | 4.69 | 1.05 | 59.7% | 1.31 / 2.45 | 0.0% | 0.0% |
| newAnchor 0.1 + rangeZ 1.15, rangeMax 2 | 0.875 | 1.8% | 0.23 / 0.61 | 7.3% | 4.69 | 1.05 | 59.6% | 1.31 / 2.45 | 0.0% | 0.0% |
| newAnchor 0.1 + rangeZ 1, rangeOwn | 0.875 | 1.8% | 0.23 / 0.61 | 7.3% | 4.69 | 1.05 | 67.8% | 1.69 / 2.25 | 0.0% | 0.0% |
| newAnchor 0.1 + rangeZ 1.3, rangeOwn | 0.875 | 1.8% | 0.23 / 0.61 | 7.3% | 4.69 | 1.05 | 76.9% | 1.99 / 2.87 | 0.0% | 0.0% |

### Set: idle (6 classes; score against the main lineup's medians)

| candidate | score | unknown | rel med / p90 | wrong (mean of 4) | excess flips/min | first answer med s | truth in [lo, hi] | hi:lo med / p90 | under 1/4 | read dead |
|---|---|---|---|---|---|---|---|---|---|---|
| newAnchor 0.1 | 0.648 | 27.2% | 0.07 / 0.21 | 2.5% | 1.12 | 15.57 | 26.6% | 1.03 / 1.08 | 0.0% | 0.1% |
| newAnchor 0.1 + rangeZ 1.15 | 0.648 | 27.2% | 0.07 / 0.21 | 2.5% | 1.12 | 15.57 | 94.8% | 1.22 / 1.96 | 0.0% | 0.1% |
| newAnchor 0.1 + rangeZ 1.15, rangeMax 2 | 0.648 | 27.2% | 0.07 / 0.21 | 2.5% | 1.12 | 15.57 | 94.7% | 1.22 / 1.96 | 0.0% | 0.1% |
| newAnchor 0.1 + rangeZ 1, rangeOwn | 0.648 | 27.2% | 0.07 / 0.21 | 2.5% | 1.12 | 15.57 | 96.7% | 1.84 / 2.30 | 0.0% | 0.1% |
| newAnchor 0.1 + rangeZ 1.3, rangeOwn | 0.648 | 27.2% | 0.07 / 0.21 | 2.5% | 1.12 | 15.57 | 98.2% | 2.22 / 2.96 | 0.0% | 0.1% |
