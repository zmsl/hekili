## LibTimeToDie review I-3: a target idle at full, stale anchors, clamped ranges (seed set A)

Score = weighted mean of (term / median of the main lineup's term); weights: unknown 1, relMed 0.5, relP90 0.5, wrongMean 1, flipSum 1. Lower is better. scale=1

### Scores (each class set against its own main-lineup medians)

| algorithm | old score | old flips | run 2 score | idle score | idle unknown | idle rel med/p90 | idle first 10 s of damage rel med/p90 | idle wrong | idle flips |
|---|---|---|---|---|---|---|---|---|---|
| Midpoints (TimeToDie default) | 0.933 | 10.71 | 0.960 | 1.354 | 25.9% | 0.71 / 3.66 | 2.67 / 10.11 | 6.4% | 0.52 |
| LeastSquares (TimeToDie) | 1.036 | 9.29 | 1.057 | 1.354 | 25.9% | 0.68 / 4.75 | 3.23 / 12.12 | 6.1% | 0.33 |
| WeightedLS halving (TimeToDie) | 1.328 | 25.99 | 1.431 | 1.590 | 25.9% | 0.13 / 2.11 | 1.06 / 9.22 | 3.6% | 6.06 |
| HeroLib-style OLS 10.4 s | 1.408 | 8.31 | 1.923 | 0.898 | 41.9% | 0.08 / 0.23 | 0.09 / 0.25 | 3.3% | 1.62 |
| Hekili-retail mean of rates | 1.799 | 19.11 | 1.801 | 1.644 | 28.0% | 0.19 / 0.40 | 0.26 / 0.52 | 6.3% | 5.74 |
| SimC-style cumulative | 1.199 | 9.45 | 1.244 | 1.314 | 26.2% | 0.68 / 3.16 | 2.34 / 8.46 | 6.3% | 0.59 |
| Ring8 (old plan) | 1.452 | 19.90 | 1.601 | 1.422 | 28.0% | 0.09 / 0.24 | 0.10 / 0.26 | 3.0% | 5.92 |
| Research recommendation (as written) | 2.867 | 81.17 | 2.920 | 3.727 | 26.0% | 0.24 / 2.18 | 1.14 / 8.40 | 4.6% | 19.08 |
| Run 1 winner (pinned) | 0.852 | 10.97 | 0.923 | 0.691 | 25.9% | 0.08 / 1.70 | 0.73 / 8.36 | 2.9% | 0.84 |
| Run 2 default (staleAnchor 0, clampRange off) | 0.843 | 11.01 | 0.916 | 0.693 | 25.9% | 0.08 / 1.71 | 0.73 / 8.36 | 2.9% | 0.85 |
| staleAnchor 3 | 0.847 | 11.01 | 0.927 | 0.728 | 27.1% | 0.07 / 0.20 | 0.10 / 0.28 | 2.6% | 1.73 |
| staleAnchor 5 | 0.844 | 11.01 | 0.916 | 0.727 | 27.0% | 0.07 / 0.20 | 0.10 / 0.28 | 2.6% | 1.73 |
| staleAnchor 8 | 0.844 | 11.01 | 0.916 | 0.718 | 26.9% | 0.07 / 0.21 | 0.10 / 0.29 | 2.6% | 1.66 |
| staleAnchor 12 | 0.843 | 11.01 | 0.916 | 0.698 | 26.8% | 0.07 / 0.22 | 0.11 / 0.90 | 2.7% | 1.53 |
| clampRange | 0.843 | 11.01 | 0.916 | 0.693 | 25.9% | 0.08 / 1.71 | 0.73 / 8.36 | 2.9% | 0.85 |
| staleAnchor 5 + clampRange | 0.844 | 11.01 | 0.916 | 0.727 | 27.0% | 0.07 / 0.20 | 0.10 / 0.28 | 2.6% | 1.73 |
| Run 3 default (staleAnchor 8 + clampRange) | 0.844 | 11.01 | 0.916 | 0.718 | 26.9% | 0.07 / 0.21 | 0.10 / 0.29 | 2.6% | 1.66 |

### Idle classes: rel median, first 10 s of damage, per class

| algorithm | idle trash | idle elite | idle boss | idle solo elite | idle ooc elite | idle ooc boss |
|---|---|---|---|---|---|---|
| Midpoints (TimeToDie default) | 3.70 | 3.87 | 4.17 | 4.14 | 0.10 | 0.06 |
| LeastSquares (TimeToDie) | 5.31 | 4.54 | 4.27 | 5.10 | 0.09 | 0.07 |
| WeightedLS halving (TimeToDie) | 0.33 | 0.55 | 3.84 | 1.47 | 0.12 | 0.07 |
| HeroLib-style OLS 10.4 s | 0.10 | 0.10 | 0.06 | 0.14 | 0.08 | 0.05 |
| Hekili-retail mean of rates | 0.39 | 0.26 | 0.35 | 0.15 | 0.35 | 0.08 |
| SimC-style cumulative | 3.38 | 3.43 | 3.58 | 3.52 | 0.09 | 0.07 |
| Ring8 (old plan) | 0.15 | 0.12 | 0.04 | 0.14 | 0.11 | 0.05 |
| Research recommendation (as written) | 1.04 | 0.87 | 3.58 | 1.14 | 0.11 | 0.07 |
| Run 1 winner (pinned) | 0.19 | 0.19 | 3.58 | 0.23 | 0.10 | 0.07 |
| Run 2 default (staleAnchor 0, clampRange off) | 0.19 | 0.19 | 3.58 | 0.23 | 0.10 | 0.07 |
| staleAnchor 3 | 0.12 | 0.11 | 0.04 | 0.14 | 0.10 | 0.08 |
| staleAnchor 5 | 0.12 | 0.11 | 0.04 | 0.14 | 0.10 | 0.07 |
| staleAnchor 8 | 0.12 | 0.11 | 0.04 | 0.15 | 0.10 | 0.07 |
| staleAnchor 12 | 0.12 | 0.12 | 0.11 | 0.15 | 0.10 | 0.07 |
| clampRange | 0.19 | 0.19 | 3.58 | 0.23 | 0.10 | 0.07 |
| staleAnchor 5 + clampRange | 0.12 | 0.11 | 0.04 | 0.14 | 0.10 | 0.07 |
| Run 3 default (staleAnchor 8 + clampRange) | 0.12 | 0.11 | 0.04 | 0.15 | 0.10 | 0.07 |

### Idle classes: rel median per class

| algorithm | idle trash | idle elite | idle boss | idle solo elite | idle ooc elite | idle ooc boss |
|---|---|---|---|---|---|---|
| Midpoints (TimeToDie default) | 2.43 | 0.76 | 0.15 | 0.85 | 0.07 | 0.02 |
| LeastSquares (TimeToDie) | 2.93 | 0.40 | 0.05 | 0.61 | 0.08 | 0.02 |
| WeightedLS halving (TimeToDie) | 0.26 | 0.14 | 0.04 | 0.18 | 0.12 | 0.03 |
| HeroLib-style OLS 10.4 s | 0.11 | 0.08 | 0.05 | 0.12 | 0.08 | 0.04 |
| Hekili-retail mean of rates | 0.38 | 0.29 | 0.03 | 0.15 | 0.28 | 0.03 |
| SimC-style cumulative | 2.33 | 0.74 | 0.14 | 0.81 | 0.07 | 0.02 |
| Ring8 (old plan) | 0.15 | 0.11 | 0.03 | 0.14 | 0.10 | 0.03 |
| Research recommendation (as written) | 0.71 | 0.19 | 0.08 | 0.33 | 0.10 | 0.03 |
| Run 1 winner (pinned) | 0.16 | 0.08 | 0.03 | 0.11 | 0.08 | 0.03 |
| Run 2 default (staleAnchor 0, clampRange off) | 0.16 | 0.08 | 0.03 | 0.11 | 0.08 | 0.03 |
| staleAnchor 3 | 0.12 | 0.08 | 0.03 | 0.11 | 0.08 | 0.03 |
| staleAnchor 5 | 0.12 | 0.08 | 0.03 | 0.11 | 0.08 | 0.03 |
| staleAnchor 8 | 0.12 | 0.08 | 0.03 | 0.11 | 0.08 | 0.03 |
| staleAnchor 12 | 0.12 | 0.08 | 0.03 | 0.11 | 0.08 | 0.03 |
| clampRange | 0.16 | 0.08 | 0.03 | 0.11 | 0.08 | 0.03 |
| staleAnchor 5 + clampRange | 0.12 | 0.08 | 0.03 | 0.11 | 0.08 | 0.03 |
| Run 3 default (staleAnchor 8 + clampRange) | 0.12 | 0.08 | 0.03 | 0.11 | 0.08 | 0.03 |

### Ranges (spread on): truth inside [lo, hi] / zero-width misses / median hi:lo / inside, 10 s after a change

| params | old | run 2 | idle |
|---|---|---|---|
| Run 2 default (staleAnchor 0, clampRange off) | 18.3% / 7.6% / 1.04 / 7.9% | 14.3% / 3.5% / 1.04 / 16.0% | 24.8% / 4.1% / 1.03 / 19.0% |
| staleAnchor 3 | 18.3% / 7.6% / 1.04 / 7.9% | 14.1% / 3.5% / 1.04 / 15.9% | 26.2% / 3.1% / 1.03 / 30.0% |
| staleAnchor 5 | 18.3% / 7.6% / 1.04 / 7.9% | 14.3% / 3.5% / 1.04 / 16.0% | 26.4% / 3.0% / 1.03 / 31.8% |
| staleAnchor 8 | 18.3% / 7.6% / 1.04 / 7.9% | 14.3% / 3.5% / 1.04 / 16.0% | 26.4% / 3.1% / 1.03 / 30.8% |
| staleAnchor 12 | 18.3% / 7.6% / 1.04 / 7.9% | 14.3% / 3.5% / 1.04 / 16.0% | 26.0% / 3.1% / 1.03 / 28.8% |
| clampRange | 18.3% / 7.6% / 1.04 / 7.9% | 14.3% / 3.5% / 1.04 / 16.0% | 25.4% / 3.0% / 1.03 / 25.5% |
| staleAnchor 5 + clampRange | 18.3% / 7.6% / 1.04 / 7.9% | 14.3% / 3.5% / 1.04 / 16.0% | 26.4% / 3.0% / 1.03 / 31.8% |
| Run 3 default (staleAnchor 8 + clampRange) | 18.3% / 7.6% / 1.04 / 7.9% | 14.3% / 3.5% / 1.04 / 16.0% | 26.4% / 3.1% / 1.03 / 30.8% |
