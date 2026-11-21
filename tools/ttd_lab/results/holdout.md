## Held-out seeds (set B)

Score = weighted mean of (term / median of the main lineup's term); weights: unknown 1, relMed 0.5, relP90 0.5, wrongMean 1, flipSum 1. Lower is better. scale=1

### Ranking on set B

| # | algorithm | score | unknown | rel med | rel p90 | abs med s | wrong (mean of 4) | excess flips/min | first answer med/p90 s | never |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Run 2 default + execute learned (true threshold) | 0.796 | 2.1% | 0.14 | 0.44 | 2.7 | 6.5% | 11.79 | 0.86 / 1.38 | 0.2% |
| 2 | Run 2 default + rate hint + execute learned 20% (one session) | 0.815 | 2.1% | 0.16 | 0.47 | 2.7 | 6.9% | 11.50 | 0.86 / 1.38 | 0.2% |
| 3 | Run 2 default + execute learned, 20% always (one session) | 0.816 | 2.1% | 0.16 | 0.47 | 3.0 | 6.9% | 11.50 | 0.86 / 1.38 | 0.2% |
| 4 | Run 2 default + rate hint (perfect) | 0.834 | 2.1% | 0.16 | 0.49 | 3.5 | 7.1% | 11.69 | 0.86 / 1.38 | 0.2% |
| 5 | Run 2 default (estimator defaults) | 0.835 | 2.1% | 0.16 | 0.49 | 3.6 | 7.1% | 11.69 | 0.86 / 1.38 | 0.2% |
| 6 | Winner, no deadband | 0.837 | 2.2% | 0.16 | 0.47 | 3.5 | 7.0% | 12.14 | 0.86 / 1.38 | 0.2% |
| 7 | Tuned + K=0 + window 30 + holdStall | 0.844 | 2.2% | 0.17 | 0.49 | 3.6 | 7.2% | 11.68 | 0.86 / 1.38 | 0.2% |
| 8 | Run 1 winner (pinned) | 0.844 | 2.2% | 0.17 | 0.49 | 3.6 | 7.2% | 11.68 | 0.86 / 1.38 | 0.2% |
| 9 | Tuned + K=0 + window 30 | 0.847 | 2.2% | 0.17 | 0.49 | 3.7 | 7.2% | 11.76 | 0.86 / 1.38 | 0.2% |
| 10 | Winner, no stall hold | 0.847 | 2.2% | 0.17 | 0.49 | 3.7 | 7.2% | 11.76 | 0.86 / 1.38 | 0.2% |
| 11 | Tuned + K=0 | 0.854 | 2.2% | 0.17 | 0.50 | 3.7 | 7.3% | 11.88 | 0.86 / 1.38 | 0.2% |
| 12 | Winner, K=2 (research shrink) | 0.854 | 2.2% | 0.17 | 0.49 | 3.2 | 7.1% | 12.53 | 0.86 / 1.38 | 0.2% |
| 13 | Tuned + K=0.5 | 0.855 | 2.2% | 0.17 | 0.49 | 3.5 | 7.1% | 12.32 | 0.86 / 1.38 | 0.2% |
| 14 | Tuned + K=0.5 + deadband 2s/0.2 | 0.857 | 2.2% | 0.18 | 0.51 | 3.6 | 7.4% | 11.65 | 0.86 / 1.38 | 0.2% |
| 15 | Winner, seedWeight 1 (own anchor mixed with a carried slope) | 0.858 | 2.2% | 0.17 | 0.49 | 3.7 | 7.1% | 12.46 | 0.86 / 1.38 | 0.2% |
| 16 | Tuned + K=0 + deadband 2s/0.2 | 0.858 | 2.2% | 0.18 | 0.51 | 3.8 | 7.5% | 11.36 | 0.86 / 1.38 | 0.2% |
| 17 | Tuned + deadband 3s/0.3 | 0.859 | 2.2% | 0.18 | 0.52 | 3.3 | 7.5% | 11.49 | 0.86 / 1.38 | 0.2% |
| 18 | Tuned (censor 0, anchorBelow, priorEmpty) | 0.860 | 2.2% | 0.17 | 0.49 | 3.2 | 7.1% | 12.63 | 0.86 / 1.38 | 0.2% |
| 19 | Winner, seedWeight 2 | 0.875 | 2.2% | 0.17 | 0.49 | 3.7 | 7.2% | 13.10 | 0.86 / 1.38 | 0.2% |
| 20 | Winner, seedWeight 4 | 0.875 | 2.2% | 0.17 | 0.49 | 3.7 | 7.2% | 13.10 | 0.86 / 1.38 | 0.2% |
| 21 | Winner, carried prior only after a crossing | 0.875 | 2.5% | 0.17 | 0.49 | 3.6 | 7.3% | 11.71 | 0.89 / 1.41 | 0.6% |
| 22 | Winner, no below-full anchor | 0.890 | 2.8% | 0.17 | 0.49 | 3.6 | 7.3% | 11.43 | 1.01 / 1.70 | 0.2% |
| 23 | Run 2 default + rate hint (wrong, phantom) | 0.906 | 2.1% | 0.20 | 0.52 | 4.2 | 7.9% | 12.60 | 0.86 / 1.38 | 0.2% |
| 24 | Midpoints (TimeToDie default) | 0.922 | 2.5% | 0.21 | 0.59 | 5.4 | 7.7% | 11.31 | 0.89 / 1.41 | 0.6% |
| 25 | Winner, no full anchor | 0.943 | 3.8% | 0.17 | 0.47 | 3.5 | 7.2% | 10.89 | 1.72 / 2.61 | 0.3% |
| 26 | Winner, no carried prior | 0.966 | 3.4% | 0.17 | 0.49 | 3.7 | 7.4% | 12.65 | 0.89 / 1.41 | 0.6% |
| 27 | LeastSquares (TimeToDie) | 1.030 | 2.5% | 0.25 | 0.89 | 5.9 | 9.1% | 10.12 | 0.89 / 1.41 | 0.6% |
| 28 | Cumulative + deadband | 1.192 | 6.4% | 0.22 | 0.60 | 5.6 | 8.6% | 8.28 | 1.63 / 2.16 | 2.2% |
| 29 | SimC-style cumulative | 1.205 | 6.4% | 0.20 | 0.57 | 5.3 | 8.3% | 9.80 | 1.63 / 2.16 | 2.2% |
| 30 | WeightedLS halving (TimeToDie) | 1.298 | 3.2% | 0.19 | 0.54 | 4.2 | 8.2% | 26.51 | 0.89 / 1.41 | 0.6% |
| 31 | HeroLib-style OLS 10.4 s | 1.405 | 10.0% | 0.17 | 0.49 | 3.6 | 7.8% | 9.03 | 2.09 / 3.21 | 1.6% |
| 32 | HeroLib + deadband | 1.425 | 10.0% | 0.18 | 0.52 | 3.6 | 8.0% | 9.10 | 2.09 / 3.21 | 1.6% |
| 33 | Ring8 (old plan) | 1.448 | 7.1% | 0.18 | 0.48 | 3.8 | 8.3% | 20.66 | 2.09 / 3.21 | 1.6% |
| 34 | Hekili-retail mean of rates | 1.741 | 6.3% | 0.35 | 0.67 | 6.7 | 16.5% | 18.76 | 2.09 / 3.21 | 1.6% |
| 35 | Winner + censoring (research rule) | 2.752 | 2.2% | 0.23 | 1.56 | 4.7 | 9.7% | 84.84 | 0.86 / 1.38 | 0.2% |
| 36 | Research recommendation (as written) | 2.816 | 3.2% | 0.22 | 1.55 | 4.3 | 9.8% | 84.31 | 1.04 / 1.73 | 0.6% |
| 37 | Unknown floor (constant once a band is known) | 3.692 | 0.7% | 1.41 | 7.86 | 23.6 | 35.0% | 0.00 | 0.30 / 0.41 | 0.2% |

### Overall detail (class means)

| algorithm | rel med early | rel p90 early | rel med late | rel p90 late | abs med early s | abs med late s | common rel med | common rel p90 | common abs med s |
|---|---|---|---|---|---|---|---|---|---|
| Run 2 default + execute learned (true threshold) | 0.26 | 0.62 | 0.12 | 0.33 | 13.3 | 0.7 | 0.14 | 0.40 | 2.5 |
| Run 2 default + rate hint + execute learned 20% (one session) | 0.26 | 0.63 | 0.15 | 0.40 | 12.7 | 0.8 | 0.15 | 0.42 | 2.5 |
| Run 2 default + execute learned, 20% always (one session) | 0.27 | 0.63 | 0.15 | 0.40 | 13.1 | 0.8 | 0.15 | 0.42 | 2.8 |
| Run 2 default + rate hint (perfect) | 0.27 | 0.63 | 0.17 | 0.43 | 13.2 | 1.0 | 0.16 | 0.44 | 3.1 |
| Run 2 default (estimator defaults) | 0.27 | 0.63 | 0.17 | 0.43 | 13.1 | 1.0 | 0.16 | 0.44 | 3.2 |
| Winner, no deadband | 0.27 | 0.62 | 0.16 | 0.39 | 13.4 | 0.9 | 0.15 | 0.42 | 3.2 |
| Tuned + K=0 + window 30 + holdStall | 0.27 | 0.63 | 0.18 | 0.44 | 13.7 | 1.0 | 0.17 | 0.45 | 3.2 |
| Run 1 winner (pinned) | 0.27 | 0.63 | 0.18 | 0.44 | 13.7 | 1.0 | 0.17 | 0.45 | 3.2 |
| Tuned + K=0 + window 30 | 0.27 | 0.63 | 0.18 | 0.44 | 13.7 | 1.0 | 0.17 | 0.45 | 3.3 |
| Winner, no stall hold | 0.27 | 0.63 | 0.18 | 0.44 | 13.7 | 1.0 | 0.17 | 0.45 | 3.3 |
| Tuned + K=0 | 0.27 | 0.63 | 0.18 | 0.44 | 13.4 | 1.0 | 0.17 | 0.45 | 3.4 |
| Winner, K=2 (research shrink) | 0.28 | 0.62 | 0.18 | 0.43 | 13.9 | 1.0 | 0.16 | 0.44 | 3.0 |
| Tuned + K=0.5 | 0.27 | 0.61 | 0.18 | 0.43 | 13.4 | 1.0 | 0.17 | 0.45 | 3.2 |
| Tuned + K=0.5 + deadband 2s/0.2 | 0.28 | 0.63 | 0.19 | 0.47 | 13.5 | 1.0 | 0.17 | 0.47 | 3.2 |
| Winner, seedWeight 1 (own anchor mixed with a carried slope) | 0.27 | 0.62 | 0.18 | 0.44 | 13.7 | 1.0 | 0.17 | 0.45 | 3.3 |
| Tuned + K=0 + deadband 2s/0.2 | 0.27 | 0.65 | 0.20 | 0.47 | 13.8 | 1.1 | 0.18 | 0.47 | 3.4 |
| Tuned + deadband 3s/0.3 | 0.28 | 0.64 | 0.20 | 0.47 | 13.8 | 1.1 | 0.17 | 0.48 | 3.0 |
| Tuned (censor 0, anchorBelow, priorEmpty) | 0.27 | 0.61 | 0.18 | 0.43 | 13.4 | 1.0 | 0.16 | 0.45 | 2.9 |
| Winner, seedWeight 2 | 0.27 | 0.63 | 0.18 | 0.44 | 13.7 | 1.0 | 0.17 | 0.45 | 3.3 |
| Winner, seedWeight 4 | 0.27 | 0.63 | 0.18 | 0.44 | 13.7 | 1.0 | 0.17 | 0.45 | 3.3 |
| Winner, carried prior only after a crossing | 0.27 | 0.63 | 0.18 | 0.44 | 13.7 | 1.0 | 0.17 | 0.45 | 3.2 |
| Winner, no below-full anchor | 0.27 | 0.61 | 0.18 | 0.44 | 13.6 | 1.0 | 0.17 | 0.45 | 3.3 |
| Run 2 default + rate hint (wrong, phantom) | 0.29 | 0.65 | 0.20 | 0.48 | 13.8 | 1.1 | 0.19 | 0.48 | 3.7 |
| Midpoints (TimeToDie default) | 0.29 | 0.63 | 0.22 | 0.46 | 14.8 | 1.4 | 0.20 | 0.53 | 5.2 |
| Winner, no full anchor | 0.26 | 0.55 | 0.18 | 0.44 | 12.8 | 1.0 | 0.17 | 0.45 | 3.3 |
| Winner, no carried prior | 0.27 | 0.63 | 0.18 | 0.45 | 13.7 | 1.0 | 0.17 | 0.45 | 3.3 |
| LeastSquares (TimeToDie) | 0.29 | 0.63 | 0.48 | 1.20 | 14.7 | 3.6 | 0.28 | 0.85 | 5.8 |
| Cumulative + deadband | 0.28 | 0.54 | 0.24 | 0.52 | 14.8 | 1.5 | 0.21 | 0.55 | 5.4 |
| SimC-style cumulative | 0.27 | 0.54 | 0.21 | 0.46 | 14.3 | 1.4 | 0.20 | 0.52 | 5.2 |
| WeightedLS halving (TimeToDie) | 0.27 | 0.65 | 0.16 | 0.49 | 12.6 | 0.9 | 0.18 | 0.49 | 3.8 |
| HeroLib-style OLS 10.4 s | 0.26 | 0.49 | 0.18 | 0.47 | 12.8 | 1.0 | 0.17 | 0.49 | 3.5 |
| HeroLib + deadband | 0.26 | 0.51 | 0.20 | 0.52 | 13.3 | 1.0 | 0.18 | 0.52 | 3.6 |
| Ring8 (old plan) | 0.25 | 0.50 | 0.16 | 0.45 | 12.2 | 0.9 | 0.17 | 0.47 | 3.6 |
| Hekili-retail mean of rates | 0.41 | 0.73 | 0.30 | 0.63 | 19.7 | 1.7 | 0.35 | 0.67 | 6.5 |
| Winner + censoring (research rule) | 0.31 | 1.14 | 0.22 | 1.00 | 14.4 | 1.3 | 0.22 | 1.48 | 4.2 |
| Research recommendation (as written) | 0.30 | 1.09 | 0.22 | 0.99 | 14.1 | 1.2 | 0.21 | 1.48 | 4.0 |
| Unknown floor (constant once a band is known) | 0.65 | 1.54 | 6.57 | 13.52 | 36.3 | 24.0 | 1.52 | 8.19 | 22.7 |

### Decisions (wrong side % / excess flips per min)

| algorithm | ttd<4 | ttd<8 | ttd<15 | fight_remains<20 |
|---|---|---|---|---|
| Run 2 default + execute learned (true threshold) | 3.4% / 2.39 | 5.6% / 3.51 | 7.0% / 3.16 | 10.2% / 2.72 |
| Run 2 default + rate hint + execute learned 20% (one session) | 3.5% / 2.21 | 6.0% / 3.46 | 7.3% / 3.13 | 10.6% / 2.71 |
| Run 2 default + execute learned, 20% always (one session) | 3.5% / 2.21 | 6.0% / 3.46 | 7.3% / 3.13 | 10.6% / 2.71 |
| Run 2 default + rate hint (perfect) | 3.5% / 2.36 | 6.1% / 3.50 | 7.8% / 3.13 | 10.9% / 2.70 |
| Run 2 default (estimator defaults) | 3.5% / 2.36 | 6.1% / 3.50 | 7.8% / 3.13 | 10.9% / 2.70 |
| Winner, no deadband | 3.6% / 2.47 | 6.2% / 3.53 | 7.6% / 3.29 | 10.8% / 2.84 |
| Tuned + K=0 + window 30 + holdStall | 3.8% / 2.47 | 6.4% / 3.44 | 7.7% / 3.08 | 10.9% / 2.69 |
| Run 1 winner (pinned) | 3.8% / 2.47 | 6.4% / 3.44 | 7.7% / 3.08 | 10.9% / 2.69 |
| Tuned + K=0 + window 30 | 3.9% / 2.50 | 6.4% / 3.47 | 7.7% / 3.09 | 11.0% / 2.69 |
| Winner, no stall hold | 3.9% / 2.50 | 6.4% / 3.47 | 7.7% / 3.09 | 11.0% / 2.69 |
| Tuned + K=0 | 3.9% / 2.51 | 6.5% / 3.47 | 7.8% / 3.15 | 11.0% / 2.74 |
| Winner, K=2 (research shrink) | 3.9% / 2.71 | 6.3% / 3.73 | 7.4% / 3.24 | 10.7% / 2.85 |
| Tuned + K=0.5 | 3.9% / 2.62 | 6.4% / 3.63 | 7.6% / 3.25 | 10.7% / 2.83 |
| Tuned + K=0.5 + deadband 2s/0.2 | 4.3% / 2.48 | 6.7% / 3.35 | 7.6% / 3.06 | 10.9% / 2.76 |
| Winner, seedWeight 1 (own anchor mixed with a carried slope) | 3.8% / 2.70 | 6.4% / 3.71 | 7.5% / 3.25 | 10.7% / 2.81 |
| Tuned + K=0 + deadband 2s/0.2 | 4.3% / 2.40 | 6.8% / 3.25 | 7.9% / 3.02 | 11.2% / 2.70 |
| Tuned + deadband 3s/0.3 | 4.5% / 2.52 | 6.8% / 3.37 | 7.7% / 2.91 | 10.8% / 2.69 |
| Tuned (censor 0, anchorBelow, priorEmpty) | 3.9% / 2.76 | 6.4% / 3.76 | 7.5% / 3.27 | 10.7% / 2.85 |
| Winner, seedWeight 2 | 4.0% / 2.91 | 6.5% / 3.89 | 7.5% / 3.33 | 10.7% / 2.97 |
| Winner, seedWeight 4 | 4.0% / 2.91 | 6.5% / 3.89 | 7.5% / 3.33 | 10.7% / 2.97 |
| Winner, carried prior only after a crossing | 3.9% / 2.48 | 6.6% / 3.44 | 7.9% / 3.09 | 11.0% / 2.70 |
| Winner, no below-full anchor | 3.8% / 2.47 | 6.3% / 3.32 | 7.8% / 3.02 | 11.1% / 2.63 |
| Run 2 default + rate hint (wrong, phantom) | 4.4% / 2.63 | 6.9% / 3.87 | 8.4% / 3.27 | 11.8% / 2.83 |
| Midpoints (TimeToDie default) | 4.1% / 2.63 | 6.9% / 3.18 | 8.3% / 2.90 | 11.6% / 2.59 |
| Winner, no full anchor | 3.7% / 2.35 | 6.4% / 3.20 | 7.6% / 2.81 | 11.0% / 2.53 |
| Winner, no carried prior | 4.0% / 2.74 | 6.7% / 3.65 | 7.9% / 3.23 | 11.1% / 3.03 |
| LeastSquares (TimeToDie) | 5.9% / 2.19 | 8.2% / 2.80 | 9.5% / 2.69 | 12.7% / 2.44 |
| Cumulative + deadband | 4.5% / 1.77 | 7.4% / 2.27 | 9.7% / 2.27 | 12.7% / 1.98 |
| SimC-style cumulative | 4.2% / 2.10 | 7.2% / 2.69 | 9.5% / 2.64 | 12.5% / 2.37 |
| WeightedLS halving (TimeToDie) | 4.1% / 5.20 | 7.2% / 7.32 | 9.1% / 7.34 | 12.2% / 6.66 |
| HeroLib-style OLS 10.4 s | 4.0% / 1.70 | 6.6% / 2.24 | 8.8% / 2.48 | 11.9% / 2.61 |
| HeroLib + deadband | 4.2% / 1.77 | 6.8% / 2.40 | 8.9% / 2.42 | 12.0% / 2.51 |
| Ring8 (old plan) | 4.2% / 4.21 | 7.2% / 5.93 | 9.4% / 5.34 | 12.4% / 5.17 |
| Hekili-retail mean of rates | 11.7% / 5.10 | 16.7% / 5.11 | 17.6% / 4.52 | 20.1% / 4.04 |
| Winner + censoring (research rule) | 4.7% / 10.91 | 8.2% / 21.33 | 11.6% / 26.99 | 14.2% / 25.61 |
| Research recommendation (as written) | 4.8% / 11.08 | 8.4% / 21.42 | 11.8% / 26.67 | 14.4% / 25.14 |
| Unknown floor (constant once a band is known) | 14.7% / 0.00 | 27.8% / 0.00 | 46.1% / 0.00 | 51.5% / 0.00 |

### Weight robustness, set B (each weight x 2^U(-1,1), 2000 draws)

| algorithm | mean rank | ranked 1st | in top 5 |
|---|---|---|---|
| Run 2 default + execute learned (true threshold) | 1.00 | 100.0% | 100.0% |
| Run 2 default + rate hint + execute learned 20% (one session) | 2.00 | 0.0% | 100.0% |
| Run 2 default + execute learned, 20% always (one session) | 3.00 | 0.0% | 100.0% |
| Run 2 default + rate hint (perfect) | 4.26 | 0.0% | 100.0% |
| Run 2 default (estimator defaults) | 5.33 | 0.0% | 66.5% |
| Winner, no deadband | 5.66 | 0.0% | 33.5% |
| Tuned + K=0 + window 30 + holdStall | 7.08 | 0.0% | 0.0% |
| Run 1 winner (pinned) | 7.81 | 0.0% | 0.0% |
| Tuned + K=0 + window 30 | 9.16 | 0.0% | 0.0% |
| Winner, no stall hold | 10.16 | 0.0% | 0.0% |
| Winner, K=2 (research shrink) | 12.76 | 0.0% | 0.0% |
| Tuned + K=0 | 12.82 | 0.0% | 0.0% |
