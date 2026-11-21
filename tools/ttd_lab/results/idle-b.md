## LibTimeToDie review I-3: a target idle at full, stale anchors, clamped ranges (seed set B)

Score = weighted mean of (term / median of the main lineup's term); weights: unknown 1, relMed 0.5, relP90 0.5, wrongMean 1, flipSum 1. Lower is better. scale=1

### Scores (each class set against its own main-lineup medians)

| algorithm | old score | old flips | run 2 score | idle score | idle unknown | idle rel med/p90 | idle first 10 s of damage rel med/p90 | idle wrong | idle flips |
|---|---|---|---|---|---|---|---|---|---|
| Midpoints (TimeToDie default) | 0.922 | 11.31 | 0.972 | 1.413 | 26.0% | 0.76 / 3.70 | 2.72 / 10.20 | 6.4% | 0.60 |
| LeastSquares (TimeToDie) | 1.030 | 10.12 | 1.053 | 1.448 | 26.0% | 0.78 / 4.86 | 3.26 / 12.07 | 6.2% | 0.34 |
| WeightedLS halving (TimeToDie) | 1.298 | 26.51 | 1.445 | 1.513 | 26.0% | 0.13 / 1.97 | 1.02 / 9.68 | 3.7% | 6.08 |
| HeroLib-style OLS 10.4 s | 1.405 | 9.03 | 1.950 | 0.887 | 41.2% | 0.08 / 0.21 | 0.09 / 0.25 | 3.3% | 1.78 |
| Hekili-retail mean of rates | 1.741 | 18.76 | 1.799 | 1.575 | 28.0% | 0.19 / 0.40 | 0.26 / 0.51 | 6.3% | 5.78 |
| SimC-style cumulative | 1.205 | 9.80 | 1.263 | 1.346 | 26.2% | 0.73 / 3.18 | 2.38 / 8.77 | 6.3% | 0.55 |
| Ring8 (old plan) | 1.448 | 20.66 | 1.675 | 1.347 | 28.0% | 0.09 / 0.23 | 0.10 / 0.27 | 3.1% | 5.92 |
| Research recommendation (as written) | 2.816 | 84.31 | 2.841 | 3.614 | 26.0% | 0.23 / 2.22 | 1.14 / 8.80 | 4.6% | 20.08 |
| Run 1 winner (pinned) | 0.844 | 11.68 | 0.913 | 0.686 | 26.0% | 0.08 / 1.62 | 0.71 / 8.75 | 2.9% | 0.87 |
| Run 2 default (staleAnchor 0, clampRange off) | 0.835 | 11.69 | 0.903 | 0.691 | 26.0% | 0.08 / 1.62 | 0.71 / 8.75 | 2.9% | 0.90 |
| staleAnchor 3 | 0.838 | 11.69 | 0.915 | 0.690 | 27.2% | 0.07 / 0.20 | 0.10 / 0.29 | 2.6% | 1.64 |
| staleAnchor 5 | 0.835 | 11.69 | 0.903 | 0.689 | 27.1% | 0.07 / 0.20 | 0.10 / 0.29 | 2.6% | 1.64 |
| staleAnchor 8 | 0.835 | 11.69 | 0.903 | 0.673 | 27.0% | 0.07 / 0.20 | 0.10 / 0.31 | 2.6% | 1.52 |
| staleAnchor 12 | 0.835 | 11.69 | 0.903 | 0.664 | 26.8% | 0.07 / 0.21 | 0.12 / 0.66 | 2.6% | 1.46 |
| clampRange | 0.835 | 11.69 | 0.903 | 0.691 | 26.0% | 0.08 / 1.62 | 0.71 / 8.75 | 2.9% | 0.90 |
| staleAnchor 5 + clampRange | 0.835 | 11.69 | 0.903 | 0.689 | 27.1% | 0.07 / 0.20 | 0.10 / 0.29 | 2.6% | 1.64 |
| Run 3 default (staleAnchor 8 + clampRange) | 0.835 | 11.69 | 0.903 | 0.673 | 27.0% | 0.07 / 0.20 | 0.10 / 0.31 | 2.6% | 1.52 |

### Idle classes: rel median, first 10 s of damage, per class

| algorithm | idle trash | idle elite | idle boss | idle solo elite | idle ooc elite | idle ooc boss |
|---|---|---|---|---|---|---|
| Midpoints (TimeToDie default) | 3.79 | 4.09 | 4.09 | 4.19 | 0.10 | 0.06 |
| LeastSquares (TimeToDie) | 5.00 | 4.94 | 4.30 | 5.16 | 0.10 | 0.06 |
| WeightedLS halving (TimeToDie) | 0.32 | 0.56 | 3.72 | 1.31 | 0.14 | 0.06 |
| HeroLib-style OLS 10.4 s | 0.12 | 0.09 | 0.08 | 0.12 | 0.09 | 0.05 |
| Hekili-retail mean of rates | 0.39 | 0.29 | 0.34 | 0.15 | 0.32 | 0.08 |
| SimC-style cumulative | 3.52 | 3.58 | 3.47 | 3.54 | 0.09 | 0.06 |
| Ring8 (old plan) | 0.15 | 0.11 | 0.05 | 0.14 | 0.12 | 0.05 |
| Research recommendation (as written) | 1.08 | 0.89 | 3.47 | 1.20 | 0.12 | 0.06 |
| Run 1 winner (pinned) | 0.21 | 0.17 | 3.47 | 0.24 | 0.11 | 0.06 |
| Run 2 default (staleAnchor 0, clampRange off) | 0.21 | 0.17 | 3.47 | 0.24 | 0.11 | 0.06 |
| staleAnchor 3 | 0.12 | 0.10 | 0.07 | 0.15 | 0.11 | 0.08 |
| staleAnchor 5 | 0.12 | 0.10 | 0.07 | 0.15 | 0.11 | 0.06 |
| staleAnchor 8 | 0.12 | 0.10 | 0.07 | 0.15 | 0.11 | 0.06 |
| staleAnchor 12 | 0.12 | 0.10 | 0.15 | 0.16 | 0.11 | 0.06 |
| clampRange | 0.21 | 0.17 | 3.47 | 0.24 | 0.11 | 0.06 |
| staleAnchor 5 + clampRange | 0.12 | 0.10 | 0.07 | 0.15 | 0.11 | 0.06 |
| Run 3 default (staleAnchor 8 + clampRange) | 0.12 | 0.10 | 0.07 | 0.15 | 0.11 | 0.06 |

### Idle classes: rel median per class

| algorithm | idle trash | idle elite | idle boss | idle solo elite | idle ooc elite | idle ooc boss |
|---|---|---|---|---|---|---|
| Midpoints (TimeToDie default) | 2.72 | 0.82 | 0.14 | 0.84 | 0.06 | 0.02 |
| LeastSquares (TimeToDie) | 3.52 | 0.44 | 0.05 | 0.58 | 0.07 | 0.02 |
| WeightedLS halving (TimeToDie) | 0.25 | 0.13 | 0.04 | 0.19 | 0.12 | 0.03 |
| HeroLib-style OLS 10.4 s | 0.11 | 0.06 | 0.04 | 0.12 | 0.08 | 0.04 |
| Hekili-retail mean of rates | 0.38 | 0.28 | 0.03 | 0.16 | 0.28 | 0.03 |
| SimC-style cumulative | 2.57 | 0.79 | 0.14 | 0.80 | 0.06 | 0.02 |
| Ring8 (old plan) | 0.15 | 0.10 | 0.03 | 0.14 | 0.11 | 0.03 |
| Research recommendation (as written) | 0.69 | 0.18 | 0.08 | 0.32 | 0.09 | 0.03 |
| Run 1 winner (pinned) | 0.16 | 0.07 | 0.03 | 0.11 | 0.08 | 0.03 |
| Run 2 default (staleAnchor 0, clampRange off) | 0.16 | 0.07 | 0.03 | 0.11 | 0.08 | 0.03 |
| staleAnchor 3 | 0.12 | 0.06 | 0.03 | 0.11 | 0.08 | 0.03 |
| staleAnchor 5 | 0.12 | 0.06 | 0.03 | 0.11 | 0.08 | 0.03 |
| staleAnchor 8 | 0.12 | 0.06 | 0.03 | 0.11 | 0.08 | 0.03 |
| staleAnchor 12 | 0.12 | 0.06 | 0.03 | 0.11 | 0.08 | 0.03 |
| clampRange | 0.16 | 0.07 | 0.03 | 0.11 | 0.08 | 0.03 |
| staleAnchor 5 + clampRange | 0.12 | 0.06 | 0.03 | 0.11 | 0.08 | 0.03 |
| Run 3 default (staleAnchor 8 + clampRange) | 0.12 | 0.06 | 0.03 | 0.11 | 0.08 | 0.03 |

### Ranges (spread on): truth inside [lo, hi] / zero-width misses / median hi:lo / inside, 10 s after a change

| params | old | run 2 | idle |
|---|---|---|---|
| Run 2 default (staleAnchor 0, clampRange off) | 18.7% / 7.6% / 1.04 / 10.4% | 14.4% / 3.7% / 1.04 / 16.0% | 25.3% / 4.4% / 1.03 / 20.0% |
| staleAnchor 3 | 18.7% / 7.6% / 1.04 / 10.4% | 14.2% / 3.7% / 1.04 / 15.9% | 26.4% / 3.4% / 1.03 / 31.0% |
| staleAnchor 5 | 18.7% / 7.6% / 1.04 / 10.4% | 14.4% / 3.7% / 1.04 / 16.0% | 26.6% / 3.4% / 1.03 / 32.9% |
| staleAnchor 8 | 18.7% / 7.6% / 1.04 / 10.4% | 14.4% / 3.7% / 1.04 / 16.0% | 26.5% / 3.4% / 1.03 / 31.9% |
| staleAnchor 12 | 18.7% / 7.6% / 1.04 / 10.4% | 14.4% / 3.7% / 1.04 / 16.0% | 26.4% / 3.4% / 1.03 / 30.0% |
| clampRange | 18.7% / 7.6% / 1.04 / 10.4% | 14.4% / 3.7% / 1.04 / 16.0% | 26.0% / 3.2% / 1.03 / 27.5% |
| staleAnchor 5 + clampRange | 18.7% / 7.6% / 1.04 / 10.4% | 14.4% / 3.7% / 1.04 / 16.0% | 26.6% / 3.4% / 1.03 / 32.9% |
| Run 3 default (staleAnchor 8 + clampRange) | 18.7% / 7.6% / 1.04 / 10.4% | 14.4% / 3.7% / 1.04 / 16.0% | 26.5% / 3.4% / 1.03 / 31.9% |
