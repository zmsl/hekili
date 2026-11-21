## Held-out seeds (set C)

Score = weighted mean of (term / median of the main lineup's term); weights: unknown 1, relMed 0.5, relP90 0.5, wrongMean 1, flipSum 1. Lower is better. scale=1

### Ranking on set C

| # | algorithm | score | unknown | rel med | rel p90 | abs med s | wrong (mean of 4) | excess flips/min | first answer med/p90 s | never |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Winner, no deadband | 0.839 | 2.1% | 0.16 | 0.48 | 3.5 | 7.1% | 11.51 | 0.85 / 1.35 | 0.3% |
| 2 | Winner (estimator defaults) | 0.846 | 2.1% | 0.17 | 0.51 | 3.6 | 7.3% | 11.10 | 0.85 / 1.35 | 0.3% |
| 3 | Tuned + K=0 + window 30 + holdStall | 0.846 | 2.1% | 0.17 | 0.51 | 3.6 | 7.3% | 11.10 | 0.85 / 1.35 | 0.3% |
| 4 | Winner, no stall hold | 0.849 | 2.1% | 0.17 | 0.51 | 3.6 | 7.3% | 11.15 | 0.85 / 1.35 | 0.3% |
| 5 | Tuned + K=0 + window 30 | 0.849 | 2.1% | 0.17 | 0.51 | 3.6 | 7.3% | 11.15 | 0.85 / 1.35 | 0.3% |
| 6 | Tuned + K=0.5 | 0.853 | 2.1% | 0.17 | 0.50 | 3.3 | 7.2% | 11.56 | 0.85 / 1.35 | 0.3% |
| 7 | Tuned + K=0.5 + deadband 2s/0.2 | 0.853 | 2.1% | 0.18 | 0.52 | 3.5 | 7.3% | 10.96 | 0.85 / 1.35 | 0.3% |
| 8 | Winner, seedWeight 1 (own anchor mixed with a carried slope) | 0.854 | 2.1% | 0.17 | 0.50 | 3.6 | 7.1% | 11.66 | 0.85 / 1.35 | 0.3% |
| 9 | Tuned + K=0 | 0.855 | 2.1% | 0.17 | 0.51 | 3.7 | 7.3% | 11.31 | 0.85 / 1.35 | 0.3% |
| 10 | Winner, K=2 (research shrink) | 0.856 | 2.1% | 0.17 | 0.50 | 3.1 | 7.1% | 11.82 | 0.85 / 1.35 | 0.3% |
| 11 | Tuned + K=0 + deadband 2s/0.2 | 0.856 | 2.1% | 0.18 | 0.53 | 3.7 | 7.5% | 10.74 | 0.85 / 1.35 | 0.3% |
| 12 | Tuned + deadband 3s/0.3 | 0.858 | 2.1% | 0.18 | 0.54 | 3.2 | 7.4% | 10.88 | 0.85 / 1.35 | 0.3% |
| 13 | Tuned (censor 0, anchorBelow, priorEmpty) | 0.860 | 2.1% | 0.17 | 0.50 | 3.1 | 7.2% | 11.92 | 0.85 / 1.35 | 0.3% |
| 14 | Winner, seedWeight 2 | 0.877 | 2.1% | 0.17 | 0.51 | 3.6 | 7.2% | 12.45 | 0.85 / 1.35 | 0.3% |
| 15 | Winner, seedWeight 4 | 0.877 | 2.1% | 0.17 | 0.51 | 3.6 | 7.2% | 12.45 | 0.85 / 1.35 | 0.3% |
| 16 | Winner, carried prior only after a crossing | 0.878 | 2.5% | 0.17 | 0.50 | 3.6 | 7.4% | 11.17 | 0.88 / 1.39 | 0.7% |
| 17 | Winner, no below-full anchor | 0.895 | 2.8% | 0.17 | 0.50 | 3.6 | 7.3% | 10.97 | 1.00 / 1.73 | 0.3% |
| 18 | Midpoints (TimeToDie default) | 0.932 | 2.5% | 0.22 | 0.60 | 5.3 | 7.8% | 10.96 | 0.88 / 1.39 | 0.7% |
| 19 | Winner, no full anchor | 0.959 | 3.8% | 0.17 | 0.49 | 3.5 | 7.3% | 10.82 | 1.68 / 2.63 | 0.3% |
| 20 | Winner, no carried prior | 0.966 | 3.3% | 0.17 | 0.51 | 3.7 | 7.4% | 12.30 | 0.88 / 1.39 | 0.7% |
| 21 | LeastSquares (TimeToDie) | 1.037 | 2.5% | 0.25 | 0.91 | 6.0 | 9.2% | 9.73 | 0.88 / 1.39 | 0.7% |
| 22 | Cumulative + deadband | 1.201 | 6.4% | 0.22 | 0.61 | 5.5 | 8.5% | 8.38 | 1.63 / 2.16 | 1.8% |
| 23 | SimC-style cumulative | 1.216 | 6.4% | 0.21 | 0.57 | 5.2 | 8.4% | 9.90 | 1.63 / 2.16 | 1.8% |
| 24 | WeightedLS halving (TimeToDie) | 1.313 | 3.3% | 0.19 | 0.55 | 4.2 | 8.0% | 26.04 | 0.88 / 1.39 | 0.7% |
| 25 | HeroLib-style OLS 10.4 s | 1.427 | 10.2% | 0.17 | 0.50 | 3.6 | 7.9% | 8.71 | 2.12 / 3.25 | 1.6% |
| 26 | HeroLib + deadband | 1.449 | 10.2% | 0.18 | 0.53 | 3.7 | 8.1% | 8.84 | 2.12 / 3.25 | 1.6% |
| 27 | Ring8 (old plan) | 1.462 | 7.1% | 0.18 | 0.49 | 3.8 | 8.3% | 20.31 | 2.12 / 3.25 | 1.6% |
| 28 | Hekili-retail mean of rates | 1.776 | 6.4% | 0.36 | 0.68 | 6.7 | 16.7% | 18.72 | 2.12 / 3.25 | 1.6% |
| 29 | Winner + censoring (research rule) | 2.850 | 2.1% | 0.23 | 1.57 | 4.8 | 9.8% | 84.72 | 0.85 / 1.35 | 0.3% |
| 30 | Research recommendation (as written) | 2.913 | 3.2% | 0.23 | 1.56 | 4.3 | 9.9% | 84.14 | 1.04 / 1.76 | 0.7% |
| 31 | Unknown floor (constant once a band is known) | 3.682 | 0.7% | 1.42 | 7.88 | 23.5 | 35.3% | 0.00 | 0.31 / 0.40 | 0.3% |

### Overall detail (class means)

| algorithm | rel med early | rel p90 early | rel med late | rel p90 late | abs med early s | abs med late s | common rel med | common rel p90 | common abs med s |
|---|---|---|---|---|---|---|---|---|---|
| Winner, no deadband | 0.27 | 0.63 | 0.16 | 0.39 | 14.5 | 0.9 | 0.16 | 0.44 | 3.1 |
| Winner (estimator defaults) | 0.28 | 0.63 | 0.17 | 0.44 | 14.6 | 1.0 | 0.17 | 0.46 | 3.2 |
| Tuned + K=0 + window 30 + holdStall | 0.28 | 0.63 | 0.17 | 0.44 | 14.6 | 1.0 | 0.17 | 0.46 | 3.2 |
| Winner, no stall hold | 0.28 | 0.63 | 0.17 | 0.44 | 14.6 | 1.0 | 0.17 | 0.46 | 3.2 |
| Tuned + K=0 + window 30 | 0.28 | 0.63 | 0.17 | 0.44 | 14.6 | 1.0 | 0.17 | 0.46 | 3.2 |
| Tuned + K=0.5 | 0.28 | 0.62 | 0.17 | 0.43 | 14.2 | 1.0 | 0.17 | 0.46 | 3.1 |
| Tuned + K=0.5 + deadband 2s/0.2 | 0.28 | 0.63 | 0.19 | 0.46 | 14.3 | 1.0 | 0.18 | 0.48 | 3.2 |
| Winner, seedWeight 1 (own anchor mixed with a carried slope) | 0.28 | 0.63 | 0.17 | 0.44 | 14.6 | 1.0 | 0.17 | 0.46 | 3.2 |
| Tuned + K=0 | 0.28 | 0.63 | 0.17 | 0.44 | 14.1 | 0.9 | 0.17 | 0.46 | 3.2 |
| Winner, K=2 (research shrink) | 0.28 | 0.63 | 0.18 | 0.43 | 14.8 | 1.0 | 0.17 | 0.46 | 2.9 |
| Tuned + K=0 + deadband 2s/0.2 | 0.28 | 0.64 | 0.19 | 0.47 | 14.2 | 1.0 | 0.18 | 0.48 | 3.3 |
| Tuned + deadband 3s/0.3 | 0.30 | 0.65 | 0.19 | 0.48 | 14.8 | 1.1 | 0.17 | 0.50 | 3.0 |
| Tuned (censor 0, anchorBelow, priorEmpty) | 0.28 | 0.63 | 0.17 | 0.43 | 14.5 | 1.0 | 0.17 | 0.46 | 2.9 |
| Winner, seedWeight 2 | 0.28 | 0.65 | 0.17 | 0.44 | 14.6 | 1.0 | 0.17 | 0.46 | 3.2 |
| Winner, seedWeight 4 | 0.28 | 0.65 | 0.17 | 0.44 | 14.6 | 1.0 | 0.17 | 0.46 | 3.2 |
| Winner, carried prior only after a crossing | 0.28 | 0.63 | 0.17 | 0.44 | 14.6 | 1.0 | 0.17 | 0.46 | 3.2 |
| Winner, no below-full anchor | 0.28 | 0.62 | 0.17 | 0.44 | 14.4 | 1.0 | 0.17 | 0.46 | 3.2 |
| Midpoints (TimeToDie default) | 0.30 | 0.64 | 0.22 | 0.47 | 15.7 | 1.4 | 0.21 | 0.54 | 5.1 |
| Winner, no full anchor | 0.27 | 0.58 | 0.17 | 0.44 | 13.8 | 1.0 | 0.17 | 0.46 | 3.2 |
| Winner, no carried prior | 0.28 | 0.64 | 0.17 | 0.44 | 14.6 | 1.0 | 0.17 | 0.46 | 3.2 |
| LeastSquares (TimeToDie) | 0.30 | 0.64 | 0.48 | 1.20 | 15.7 | 3.3 | 0.26 | 0.87 | 5.9 |
| Cumulative + deadband | 0.28 | 0.54 | 0.24 | 0.53 | 15.6 | 1.5 | 0.22 | 0.56 | 5.2 |
| SimC-style cumulative | 0.28 | 0.54 | 0.22 | 0.47 | 15.2 | 1.4 | 0.21 | 0.53 | 5.0 |
| WeightedLS halving (TimeToDie) | 0.28 | 0.67 | 0.16 | 0.48 | 13.4 | 0.9 | 0.18 | 0.50 | 3.8 |
| HeroLib-style OLS 10.4 s | 0.26 | 0.51 | 0.18 | 0.47 | 13.4 | 1.0 | 0.17 | 0.50 | 3.5 |
| HeroLib + deadband | 0.27 | 0.51 | 0.21 | 0.52 | 13.6 | 1.0 | 0.18 | 0.53 | 3.6 |
| Ring8 (old plan) | 0.26 | 0.54 | 0.17 | 0.44 | 13.0 | 0.9 | 0.18 | 0.48 | 3.6 |
| Hekili-retail mean of rates | 0.43 | 0.74 | 0.32 | 0.66 | 20.9 | 1.7 | 0.36 | 0.68 | 6.5 |
| Winner + censoring (research rule) | 0.32 | 1.18 | 0.21 | 1.00 | 15.4 | 1.3 | 0.22 | 1.48 | 4.3 |
| Research recommendation (as written) | 0.32 | 1.12 | 0.21 | 0.98 | 15.1 | 1.2 | 0.22 | 1.47 | 4.0 |
| Unknown floor (constant once a band is known) | 0.64 | 1.48 | 6.62 | 13.56 | 36.0 | 24.1 | 1.56 | 8.23 | 22.6 |

### Decisions (wrong side % / excess flips per min)

| algorithm | ttd<4 | ttd<8 | ttd<15 | fight_remains<20 |
|---|---|---|---|---|
| Winner, no deadband | 3.9% / 2.48 | 6.3% / 3.12 | 7.2% / 3.01 | 10.8% / 2.90 |
| Winner (estimator defaults) | 4.1% / 2.29 | 6.5% / 3.04 | 7.4% / 2.93 | 11.0% / 2.84 |
| Tuned + K=0 + window 30 + holdStall | 4.1% / 2.29 | 6.5% / 3.04 | 7.4% / 2.93 | 11.0% / 2.84 |
| Winner, no stall hold | 4.2% / 2.31 | 6.6% / 3.08 | 7.4% / 2.93 | 11.0% / 2.83 |
| Tuned + K=0 + window 30 | 4.2% / 2.31 | 6.6% / 3.08 | 7.4% / 2.93 | 11.0% / 2.83 |
| Tuned + K=0.5 | 4.2% / 2.39 | 6.5% / 3.15 | 7.2% / 3.06 | 10.8% / 2.97 |
| Tuned + K=0.5 + deadband 2s/0.2 | 4.6% / 2.29 | 6.6% / 2.93 | 7.2% / 2.91 | 10.8% / 2.83 |
| Winner, seedWeight 1 (own anchor mixed with a carried slope) | 4.2% / 2.42 | 6.4% / 3.19 | 7.2% / 3.08 | 10.7% / 2.96 |
| Tuned + K=0 | 4.2% / 2.33 | 6.6% / 3.09 | 7.4% / 2.99 | 11.0% / 2.91 |
| Winner, K=2 (research shrink) | 4.2% / 2.49 | 6.4% / 3.26 | 7.2% / 3.12 | 10.7% / 2.95 |
| Tuned + K=0 + deadband 2s/0.2 | 4.6% / 2.25 | 6.7% / 2.89 | 7.4% / 2.84 | 11.1% / 2.76 |
| Tuned + deadband 3s/0.3 | 4.7% / 2.32 | 6.9% / 2.87 | 7.3% / 2.88 | 10.9% / 2.80 |
| Tuned (censor 0, anchorBelow, priorEmpty) | 4.2% / 2.50 | 6.5% / 3.30 | 7.2% / 3.15 | 10.7% / 2.98 |
| Winner, seedWeight 2 | 4.3% / 2.69 | 6.5% / 3.37 | 7.3% / 3.28 | 10.8% / 3.11 |
| Winner, seedWeight 4 | 4.3% / 2.69 | 6.5% / 3.37 | 7.3% / 3.28 | 10.8% / 3.11 |
| Winner, carried prior only after a crossing | 4.2% / 2.30 | 6.6% / 3.04 | 7.5% / 2.96 | 11.0% / 2.87 |
| Winner, no below-full anchor | 4.2% / 2.44 | 6.5% / 2.99 | 7.5% / 2.81 | 11.2% / 2.72 |
| Midpoints (TimeToDie default) | 4.4% / 2.71 | 6.8% / 2.82 | 8.2% / 2.86 | 11.6% / 2.57 |
| Winner, no full anchor | 4.2% / 2.39 | 6.4% / 2.97 | 7.4% / 2.78 | 11.1% / 2.69 |
| Winner, no carried prior | 4.4% / 2.63 | 6.7% / 3.29 | 7.6% / 3.20 | 11.0% / 3.18 |
| LeastSquares (TimeToDie) | 6.3% / 2.19 | 8.3% / 2.56 | 9.4% / 2.59 | 12.7% / 2.40 |
| Cumulative + deadband | 4.6% / 1.89 | 7.3% / 2.20 | 9.5% / 2.17 | 12.8% / 2.12 |
| SimC-style cumulative | 4.4% / 2.28 | 7.1% / 2.47 | 9.3% / 2.60 | 12.6% / 2.55 |
| WeightedLS halving (TimeToDie) | 4.3% / 5.26 | 6.9% / 7.21 | 8.7% / 6.95 | 12.1% / 6.62 |
| HeroLib-style OLS 10.4 s | 4.3% / 1.74 | 6.7% / 2.11 | 8.5% / 2.36 | 12.0% / 2.50 |
| HeroLib + deadband | 4.7% / 1.81 | 6.9% / 2.07 | 8.6% / 2.43 | 12.1% / 2.53 |
| Ring8 (old plan) | 4.2% / 4.37 | 7.1% / 5.30 | 9.1% / 5.29 | 12.6% / 5.35 |
| Hekili-retail mean of rates | 12.9% / 5.40 | 16.8% / 4.82 | 16.9% / 4.24 | 20.1% / 4.26 |
| Winner + censoring (research rule) | 4.8% / 11.43 | 8.4% / 20.64 | 11.5% / 26.88 | 14.5% / 25.78 |
| Research recommendation (as written) | 4.9% / 11.68 | 8.5% / 20.66 | 11.7% / 26.43 | 14.6% / 25.38 |
| Unknown floor (constant once a band is known) | 14.8% / 0.00 | 27.9% / 0.00 | 46.5% / 0.00 | 52.0% / 0.00 |

### Weight robustness, set C (each weight x 2^U(-1,1), 2000 draws)

| algorithm | mean rank | ranked 1st | in top 5 |
|---|---|---|---|
| Winner, no deadband | 1.31 | 91.6% | 97.5% |
| Winner (estimator defaults) | 2.43 | 0.0% | 97.5% |
| Tuned + K=0 + window 30 + holdStall | 2.66 | 5.8% | 100.0% |
| Winner, no stall hold | 5.07 | 0.0% | 76.7% |
| Tuned + K=0 + window 30 | 5.12 | 0.0% | 77.5% |
| Tuned + K=0.5 | 7.06 | 0.0% | 14.6% |
| Tuned + K=0.5 + deadband 2s/0.2 | 8.20 | 0.0% | 5.5% |
| Winner, seedWeight 1 (own anchor mixed with a carried slope) | 8.43 | 0.0% | 9.0% |
| Tuned + K=0 | 9.17 | 0.0% | 0.0% |
| Winner, K=2 (research shrink) | 9.36 | 0.0% | 11.8% |
| Tuned + K=0 + deadband 2s/0.2 | 9.46 | 2.6% | 9.3% |
| Tuned + deadband 3s/0.3 | 11.43 | 0.0% | 0.7% |
