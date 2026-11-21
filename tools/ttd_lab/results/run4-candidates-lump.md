## Run 4: real traces, lumpy damage, opener timing (seed set A, LHV band contract)

Score = weighted mean of (term / median of the main lineup's term); weights: unknown 1, relMed 0.5, relP90 0.5, wrongMean 1, flipSum 1. Lower is better. scale=1

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
| Library (lab defaults, staleAnchor 12) | 0.31 / 0.58 | 0.34 / 0.77 | 19.5% | 1.11 / 6.00 | 13.3% | 10.2% | 5.9% | 3.4 | 0.0% | 0.9% | 0.40 0.32 0.15 0.33 0.37 | 11 22 15 25 27 |
| lumpWeight | 0.28 / 0.54 | 0.32 / 0.70 | 19.5% | 1.09 / 6.00 | 12.6% | 11.3% | 5.9% | 3.4 | 0.0% | 1.0% | 0.41 0.25 0.18 0.26 0.39 | 10 28 15 21 27 |
| lumpWeight + newAnchor 0.1 | 0.28 / 0.54 | 0.32 / 0.70 | 19.5% | 1.09 / 6.00 | 12.6% | 11.3% | 5.9% | 3.4 | 0.0% | 1.0% | 0.41 0.25 0.18 0.26 0.39 | 10 28 15 21 27 |
| lumpWeight + halfLife 10 | 0.27 / 0.53 | 0.30 / 0.69 | 22.0% | 1.10 / 6.00 | 12.3% | 11.3% | 5.9% | 4.5 | 0.0% | 0.9% | 0.41 0.22 0.18 0.23 0.39 | 10 28 15 25 39 |

### Set: lumpy (3 classes; score against the main lineup's medians)

| candidate | score | unknown | rel med / p90 | wrong (mean of 4) | excess flips/min | first answer med s | truth in [lo, hi] | hi:lo med / p90 | under 1/4 | read dead |
|---|---|---|---|---|---|---|---|---|---|---|
| Library (lab defaults, staleAnchor 12) | 1.062 | 9.0% | 0.32 / 0.79 | 17.3% | 18.06 | 1.76 | 13.3% | 1.10 / 6.00 | 3.0% | 2.7% |
| lumpWeight | 1.069 | 9.0% | 0.33 / 0.77 | 18.1% | 17.69 | 1.76 | 13.1% | 1.11 / 6.00 | 3.7% | 3.0% |
| lumpWeight + newAnchor 0.1 | 1.032 | 9.8% | 0.32 / 0.76 | 17.6% | 14.86 | 1.99 | 13.4% | 1.11 / 6.00 | 3.0% | 2.6% |
| lumpWeight + halfLife 10 | 1.078 | 9.0% | 0.33 / 0.76 | 18.2% | 18.11 | 1.76 | 13.3% | 1.11 / 6.00 | 3.7% | 2.9% |

### lumpy: rel median per class

| algorithm | lumpy solo | lumpy instant | lumpy pair |
|---|---|---|---|
| Library (lab defaults, staleAnchor 12) | 0.32 | 0.35 | 0.29 |
| lumpWeight | 0.31 | 0.37 | 0.31 |
| lumpWeight + newAnchor 0.1 | 0.31 | 0.35 | 0.31 |
| lumpWeight + halfLife 10 | 0.31 | 0.37 | 0.31 |

### lumpy: wrong side per class

| algorithm | lumpy solo | lumpy instant | lumpy pair |
|---|---|---|---|
| Library (lab defaults, staleAnchor 12) | 15.2% | 16.6% | 20.0% |
| lumpWeight | 15.7% | 18.0% | 20.7% |
| lumpWeight + newAnchor 0.1 | 15.6% | 16.5% | 20.7% |
| lumpWeight + halfLife 10 | 15.8% | 18.2% | 20.7% |

### lumpy: unknown per class

| algorithm | lumpy solo | lumpy instant | lumpy pair |
|---|---|---|---|
| Library (lab defaults, staleAnchor 12) | 13.0% | 6.0% | 7.9% |
| lumpWeight | 13.0% | 6.0% | 7.9% |
| lumpWeight + newAnchor 0.1 | 13.1% | 8.5% | 7.9% |
| lumpWeight + halfLife 10 | 13.0% | 6.0% | 7.9% |

### Set: old (13 classes; score against the main lineup's medians)

| candidate | score | unknown | rel med / p90 | wrong (mean of 4) | excess flips/min | first answer med s | truth in [lo, hi] | hi:lo med / p90 | under 1/4 | read dead |
|---|---|---|---|---|---|---|---|---|---|---|
| Library (lab defaults, staleAnchor 12) | 0.837 | 2.2% | 0.16 / 0.49 | 6.9% | 10.96 | 0.85 | 17.2% | 1.05 / 1.61 | 0.8% | 0.4% |
| lumpWeight | 0.834 | 2.2% | 0.16 / 0.48 | 6.9% | 10.84 | 0.85 | 17.4% | 1.05 / 1.65 | 0.9% | 0.4% |
| lumpWeight + newAnchor 0.1 | 0.832 | 2.3% | 0.16 / 0.48 | 6.8% | 10.28 | 0.89 | 17.4% | 1.05 / 1.62 | 0.9% | 0.4% |
| lumpWeight + halfLife 10 | 0.834 | 2.2% | 0.16 / 0.49 | 6.9% | 10.77 | 0.85 | 17.6% | 1.06 / 1.64 | 0.9% | 0.4% |

### Set: run 2 (20 classes; score against the main lineup's medians)

| candidate | score | unknown | rel med / p90 | wrong (mean of 4) | excess flips/min | first answer med s | truth in [lo, hi] | hi:lo med / p90 | under 1/4 | read dead |
|---|---|---|---|---|---|---|---|---|---|---|
| Library (lab defaults, staleAnchor 12) | 0.908 | 1.6% | 0.23 / 0.61 | 7.4% | 5.28 | 1.03 | 14.3% | 1.04 / 1.13 | 0.1% | 0.1% |
| lumpWeight | 0.892 | 1.6% | 0.23 / 0.60 | 7.5% | 4.99 | 1.03 | 14.3% | 1.04 / 1.12 | 0.1% | 0.1% |
| lumpWeight + newAnchor 0.1 | 0.883 | 1.8% | 0.23 / 0.60 | 7.4% | 4.39 | 1.08 | 14.3% | 1.04 / 1.12 | 0.0% | 0.1% |
| lumpWeight + halfLife 10 | 0.895 | 1.6% | 0.23 / 0.60 | 7.5% | 4.99 | 1.03 | 15.2% | 1.04 / 1.13 | 0.1% | 0.1% |

### Set: idle (6 classes; score against the main lineup's medians)

| candidate | score | unknown | rel med / p90 | wrong (mean of 4) | excess flips/min | first answer med s | truth in [lo, hi] | hi:lo med / p90 | under 1/4 | read dead |
|---|---|---|---|---|---|---|---|---|---|---|
| Library (lab defaults, staleAnchor 12) | 0.676 | 26.8% | 0.07 / 0.22 | 2.7% | 1.49 | 14.89 | 26.1% | 1.03 / 1.08 | 0.0% | 0.1% |
| lumpWeight | 0.688 | 26.8% | 0.08 / 0.22 | 2.7% | 1.55 | 14.89 | 25.9% | 1.03 / 1.08 | 0.0% | 0.1% |
| lumpWeight + newAnchor 0.1 | 0.684 | 26.8% | 0.08 / 0.22 | 2.7% | 1.53 | 14.89 | 25.9% | 1.03 / 1.08 | 0.0% | 0.1% |
| lumpWeight + halfLife 10 | 0.695 | 26.8% | 0.07 / 0.21 | 2.7% | 1.61 | 14.89 | 28.5% | 1.03 / 1.09 | 0.0% | 0.1% |
