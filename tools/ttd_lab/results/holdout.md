## Held-out seeds (set B)

Score = weighted mean of (term / median of the main lineup's term); weights: unknown 1, relMed 0.5, relP90 0.5, wrongMean 1, flipSum 1. Lower is better. scale=1

### Ranking on set B

| # | algorithm | score | unknown | rel med | rel p90 | abs med s | wrong (mean of 4) | excess flips/min | first answer med/p90 s | never |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Tuned + K=0 + window 30 | 0.848 | 2.2% | 0.18 | 0.50 | 3.9 | 6.9% | 11.60 | 0.90 / 1.44 | 0.1% |
| 2 | Tuned + K=0 | 0.854 | 2.2% | 0.18 | 0.50 | 3.9 | 7.0% | 11.73 | 0.90 / 1.44 | 0.1% |
| 3 | Tuned + K=0 + deadband 2s/0.2 | 0.858 | 2.2% | 0.19 | 0.52 | 4.0 | 7.2% | 11.18 | 0.90 / 1.44 | 0.1% |
| 4 | Tuned + K=0.5 | 0.859 | 2.2% | 0.18 | 0.50 | 3.7 | 6.9% | 12.16 | 0.90 / 1.44 | 0.1% |
| 5 | Tuned + K=0.5 + deadband 2s/0.2 | 0.861 | 2.2% | 0.19 | 0.52 | 3.8 | 7.2% | 11.46 | 0.90 / 1.44 | 0.1% |
| 6 | Tuned + deadband 3s/0.3 | 0.863 | 2.2% | 0.19 | 0.54 | 3.4 | 7.3% | 11.26 | 0.90 / 1.44 | 0.1% |
| 7 | Tuned (censor 0, anchorBelow, priorEmpty) | 0.864 | 2.2% | 0.18 | 0.50 | 3.3 | 6.9% | 12.41 | 0.90 / 1.44 | 0.1% |
| 8 | Midpoints (TimeToDie default) | 0.923 | 2.4% | 0.22 | 0.61 | 5.7 | 7.6% | 11.13 | 0.92 / 1.46 | 0.3% |
| 9 | Rec, no censoring | 0.926 | 3.1% | 0.18 | 0.50 | 3.3 | 7.1% | 11.74 | 1.08 / 1.80 | 0.3% |
| 10 | LeastSquares (TimeToDie) | 1.036 | 2.4% | 0.27 | 0.93 | 6.3 | 9.0% | 9.92 | 0.92 / 1.46 | 0.3% |
| 11 | Cumulative + deadband | 1.183 | 6.1% | 0.23 | 0.63 | 5.9 | 8.5% | 8.33 | 1.64 / 2.18 | 1.6% |
| 12 | SimC-style cumulative | 1.197 | 6.1% | 0.22 | 0.60 | 5.6 | 8.3% | 9.85 | 1.64 / 2.18 | 1.6% |
| 13 | WeightedLS halving (TimeToDie) | 1.317 | 3.2% | 0.20 | 0.56 | 4.4 | 7.9% | 26.42 | 0.92 / 1.46 | 0.3% |
| 14 | HeroLib-style OLS 10.4 s | 1.425 | 10.1% | 0.17 | 0.51 | 3.8 | 7.7% | 9.12 | 2.16 / 3.29 | 0.9% |
| 15 | HeroLib + deadband | 1.444 | 10.1% | 0.19 | 0.54 | 3.8 | 7.8% | 9.21 | 2.16 / 3.29 | 0.9% |
| 16 | Ring8 (old plan) | 1.458 | 6.9% | 0.18 | 0.49 | 4.0 | 8.2% | 20.76 | 2.16 / 3.29 | 0.9% |
| 17 | Hekili-retail mean of rates | 1.734 | 6.0% | 0.36 | 0.67 | 7.0 | 16.3% | 18.77 | 2.16 / 3.29 | 0.9% |
| 18 | Recommended (research defaults) | 2.933 | 3.1% | 0.23 | 1.62 | 4.6 | 9.8% | 85.54 | 1.08 / 1.80 | 0.3% |
| 19 | Rec, no deadband | 2.979 | 3.1% | 0.23 | 1.66 | 4.4 | 9.7% | 87.43 | 1.08 / 1.80 | 0.3% |
| 20 | Rec, no full anchor | 3.034 | 4.8% | 0.23 | 1.61 | 4.4 | 9.8% | 84.42 | 2.03 / 2.91 | 0.3% |
| 21 | Rec, no carried prior | 3.039 | 4.5% | 0.23 | 1.64 | 4.6 | 10.1% | 84.87 | 1.11 / 1.83 | 0.6% |
| 22 | Unknown floor (constant once a band is known) | 3.602 | 0.7% | 1.47 | 7.75 | 24.1 | 35.5% | 0.00 | 0.30 / 0.41 | 0.1% |

### Overall detail (class means)

| algorithm | rel med early | rel p90 early | rel med late | rel p90 late | abs med early s | abs med late s | common rel med | common rel p90 | common abs med s |
|---|---|---|---|---|---|---|---|---|---|
| Tuned + K=0 + window 30 | 0.28 | 0.62 | 0.19 | 0.45 | 14.5 | 1.1 | 0.18 | 0.46 | 3.4 |
| Tuned + K=0 | 0.28 | 0.62 | 0.19 | 0.45 | 14.2 | 1.0 | 0.18 | 0.47 | 3.6 |
| Tuned + K=0 + deadband 2s/0.2 | 0.29 | 0.64 | 0.20 | 0.49 | 14.6 | 1.1 | 0.18 | 0.49 | 3.6 |
| Tuned + K=0.5 | 0.28 | 0.62 | 0.19 | 0.44 | 14.2 | 1.0 | 0.17 | 0.46 | 3.4 |
| Tuned + K=0.5 + deadband 2s/0.2 | 0.29 | 0.63 | 0.20 | 0.48 | 14.3 | 1.1 | 0.18 | 0.49 | 3.4 |
| Tuned + deadband 3s/0.3 | 0.30 | 0.65 | 0.20 | 0.49 | 14.6 | 1.1 | 0.18 | 0.50 | 3.1 |
| Tuned (censor 0, anchorBelow, priorEmpty) | 0.29 | 0.62 | 0.19 | 0.44 | 14.3 | 1.1 | 0.17 | 0.47 | 3.1 |
| Midpoints (TimeToDie default) | 0.31 | 0.64 | 0.23 | 0.49 | 15.8 | 1.5 | 0.21 | 0.55 | 5.6 |
| Rec, no censoring | 0.29 | 0.60 | 0.19 | 0.44 | 14.2 | 1.1 | 0.17 | 0.47 | 3.1 |
| LeastSquares (TimeToDie) | 0.30 | 0.64 | 0.52 | 1.28 | 15.6 | 3.9 | 0.29 | 0.90 | 6.2 |
| Cumulative + deadband | 0.29 | 0.56 | 0.25 | 0.54 | 15.7 | 1.6 | 0.22 | 0.58 | 5.7 |
| SimC-style cumulative | 0.29 | 0.55 | 0.23 | 0.48 | 15.3 | 1.5 | 0.21 | 0.54 | 5.5 |
| WeightedLS halving (TimeToDie) | 0.28 | 0.66 | 0.17 | 0.51 | 13.3 | 1.0 | 0.19 | 0.51 | 4.0 |
| HeroLib-style OLS 10.4 s | 0.27 | 0.51 | 0.18 | 0.48 | 13.6 | 1.0 | 0.17 | 0.51 | 3.7 |
| HeroLib + deadband | 0.28 | 0.52 | 0.20 | 0.54 | 14.2 | 1.1 | 0.18 | 0.54 | 3.8 |
| Ring8 (old plan) | 0.26 | 0.52 | 0.17 | 0.46 | 12.9 | 1.0 | 0.18 | 0.49 | 3.8 |
| Hekili-retail mean of rates | 0.42 | 0.74 | 0.30 | 0.63 | 20.7 | 1.7 | 0.36 | 0.67 | 6.7 |
| Recommended (research defaults) | 0.32 | 1.12 | 0.23 | 1.04 | 14.9 | 1.3 | 0.22 | 1.56 | 4.2 |
| Rec, no deadband | 0.32 | 1.12 | 0.21 | 1.04 | 15.0 | 1.2 | 0.22 | 1.59 | 4.1 |
| Rec, no full anchor | 0.30 | 1.02 | 0.23 | 1.04 | 14.0 | 1.3 | 0.23 | 1.56 | 4.2 |
| Rec, no carried prior | 0.32 | 1.12 | 0.23 | 1.04 | 15.0 | 1.3 | 0.23 | 1.57 | 4.2 |
| Unknown floor (constant once a band is known) | 0.66 | 1.51 | 6.63 | 13.42 | 37.9 | 23.9 | 1.58 | 8.10 | 23.1 |

### Decisions (wrong side % / excess flips per min)

| algorithm | ttd<4 | ttd<8 | ttd<15 | fight_remains<20 |
|---|---|---|---|---|
| Tuned + K=0 + window 30 | 4.0% / 2.61 | 6.6% / 3.55 | 7.6% / 2.94 | 9.4% / 2.51 |
| Tuned + K=0 | 4.0% / 2.62 | 6.7% / 3.56 | 7.7% / 3.00 | 9.5% / 2.56 |
| Tuned + K=0 + deadband 2s/0.2 | 4.5% / 2.49 | 7.0% / 3.32 | 7.8% / 2.86 | 9.6% / 2.51 |
| Tuned + K=0.5 | 4.0% / 2.73 | 6.6% / 3.72 | 7.6% / 3.09 | 9.4% / 2.61 |
| Tuned + K=0.5 + deadband 2s/0.2 | 4.4% / 2.58 | 7.0% / 3.45 | 7.7% / 2.91 | 9.5% / 2.54 |
| Tuned + deadband 3s/0.3 | 4.7% / 2.62 | 7.0% / 3.40 | 7.8% / 2.74 | 9.5% / 2.50 |
| Tuned (censor 0, anchorBelow, priorEmpty) | 4.1% / 2.84 | 6.6% / 3.82 | 7.6% / 3.11 | 9.4% / 2.64 |
| Midpoints (TimeToDie default) | 4.2% / 2.67 | 7.1% / 3.18 | 8.5% / 2.81 | 10.4% / 2.48 |
| Rec, no censoring | 4.1% / 2.74 | 6.7% / 3.53 | 7.9% / 2.98 | 9.7% / 2.49 |
| LeastSquares (TimeToDie) | 6.1% / 2.19 | 8.5% / 2.81 | 9.8% / 2.60 | 11.6% / 2.32 |
| Cumulative + deadband | 4.6% / 1.85 | 7.6% / 2.32 | 9.8% / 2.26 | 12.0% / 1.89 |
| SimC-style cumulative | 4.3% / 2.19 | 7.3% / 2.75 | 9.7% / 2.62 | 11.8% / 2.29 |
| WeightedLS halving (TimeToDie) | 4.2% / 5.25 | 7.4% / 7.33 | 9.2% / 7.28 | 11.0% / 6.56 |
| HeroLib-style OLS 10.4 s | 4.1% / 1.76 | 6.7% / 2.30 | 9.0% / 2.48 | 11.0% / 2.59 |
| HeroLib + deadband | 4.3% / 1.83 | 6.9% / 2.47 | 9.1% / 2.42 | 11.0% / 2.49 |
| Ring8 (old plan) | 4.3% / 4.27 | 7.3% / 6.00 | 9.6% / 5.37 | 11.4% / 5.12 |
| Hekili-retail mean of rates | 11.7% / 5.14 | 16.8% / 5.11 | 17.8% / 4.54 | 19.0% / 3.98 |
| Recommended (research defaults) | 4.9% / 11.43 | 8.6% / 21.97 | 12.0% / 26.86 | 13.5% / 25.28 |
| Rec, no deadband | 4.8% / 11.98 | 8.6% / 22.26 | 11.9% / 27.31 | 13.5% / 25.88 |
| Rec, no full anchor | 4.9% / 11.45 | 8.6% / 21.87 | 12.0% / 26.40 | 13.6% / 24.70 |
| Rec, no carried prior | 5.1% / 11.39 | 8.9% / 21.78 | 12.5% / 26.57 | 14.1% / 25.13 |
| Unknown floor (constant once a band is known) | 14.8% / 0.00 | 27.9% / 0.00 | 46.1% / 0.00 | 53.3% / 0.00 |

### Weight robustness, set B (each weight x 2^U(-1,1), 2000 draws)

| algorithm | mean rank | ranked 1st | in top 5 |
|---|---|---|---|
| Tuned + K=0 + window 30 | 1.04 | 95.9% | 100.0% |
| Tuned + K=0 | 2.50 | 0.0% | 100.0% |
| Tuned + K=0 + deadband 2s/0.2 | 3.67 | 4.1% | 86.2% |
| Tuned + K=0.5 | 4.12 | 0.0% | 66.6% |
| Tuned + K=0.5 + deadband 2s/0.2 | 5.10 | 0.0% | 71.4% |
| Tuned (censor 0, anchorBelow, priorEmpty) | 5.77 | 0.0% | 40.2% |
| Tuned + deadband 3s/0.3 | 5.79 | 0.0% | 35.6% |
| Midpoints (TimeToDie default) | 8.49 | 0.0% | 0.0% |
| Rec, no censoring | 8.52 | 0.0% | 0.0% |
| LeastSquares (TimeToDie) | 10.11 | 0.0% | 0.0% |
| Cumulative + deadband | 11.33 | 0.0% | 0.0% |
| SimC-style cumulative | 12.05 | 0.0% | 0.0% |
