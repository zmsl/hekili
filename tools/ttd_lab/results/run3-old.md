## Run 3 strategies on the run 1 and run 2 classes (seed set A)

Score = weighted mean of (term / median of the main lineup's term); weights: unknown 1, relMed 0.5, relP90 0.5, wrongMean 1, flipSum 1. Lower is better. scale=1

### Old and new classes

| algorithm | old score | old rel med/p90 | old wrong | old flips | new score | new unknown | new rel med/p90 | new post-change rel med/p90 | new post-change wrong | new wrong | new flips |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Run 2 recommendation, learned w=0.25 | 0.824 | 0.15 / 0.47 | 6.7% | 10.99 | 0.754 | 1.6% | 0.15 / 0.38 | 0.22 / 0.53 | 5.5% | 4.9% | 5.40 |
| Run 2 recommendation: 20% learned, one session | 0.824 | 0.15 / 0.47 | 6.7% | 10.90 | 0.762 | 1.6% | 0.15 / 0.39 | 0.23 / 0.54 | 5.7% | 5.0% | 5.46 |
| c. all lines, prior wrong share (1/8 each: too low), learned | 0.871 | 0.17 / 0.49 | 7.4% | 11.27 | 0.880 | 1.6% | 0.21 / 0.54 | 0.36 / 0.79 | 8.6% | 6.8% | 5.43 |
| a. no execute hint (default) | 0.843 | 0.16 / 0.49 | 6.9% | 11.01 | 0.916 | 1.6% | 0.24 / 0.61 | 0.42 / 0.91 | 9.9% | 7.5% | 5.29 |
| b. own line, learned w=0.25 | 0.845 | 0.16 / 0.49 | 6.9% | 11.01 | 0.915 | 1.6% | 0.24 / 0.61 | 0.42 / 0.91 | 9.9% | 7.4% | 5.27 |
| b. own line, learned | 0.847 | 0.16 / 0.49 | 7.0% | 11.01 | 0.915 | 1.6% | 0.24 / 0.61 | 0.42 / 0.91 | 9.9% | 7.4% | 5.27 |
| Run 1 winner (pinned) | 0.852 | 0.16 / 0.49 | 7.1% | 10.97 | 0.923 | 1.6% | 0.24 / 0.62 | 0.51 / 0.93 | 10.8% | 7.6% | 5.23 |
| c. own line, prior x2 equal share, learned | 0.971 | 0.21 / 0.53 | 9.2% | 11.58 | 0.857 | 1.6% | 0.19 / 0.49 | 0.29 / 0.69 | 7.1% | 6.5% | 5.65 |
| d. all lines, prior x2 equal share, fixed | 0.973 | 0.21 / 0.53 | 9.2% | 11.59 | 0.858 | 1.6% | 0.19 / 0.49 | 0.29 / 0.69 | 7.1% | 6.5% | 5.65 |
| Midpoints (TimeToDie default) | 0.933 | 0.20 / 0.57 | 7.6% | 10.71 | 0.960 | 1.8% | 0.25 / 0.64 | 0.58 / 0.97 | 11.7% | 7.9% | 5.22 |
| d. all lines, prior wrong mult (x3: too high), fixed | 1.079 | 0.26 / 0.58 | 11.1% | 11.78 | 0.863 | 1.6% | 0.19 / 0.48 | 0.29 / 0.66 | 6.7% | 6.6% | 5.77 |
| d. all lines, x2 whatever the group, fixed | 1.121 | 0.29 / 0.59 | 11.6% | 12.22 | 0.868 | 1.6% | 0.18 / 0.46 | 0.28 / 0.58 | 6.6% | 6.4% | 6.13 |
| LeastSquares (TimeToDie) | 1.036 | 0.23 / 0.89 | 9.0% | 9.29 | 1.057 | 1.8% | 0.28 / 0.98 | 1.02 / 1.78 | 18.6% | 9.5% | 4.50 |
| SimC-style cumulative | 1.199 | 0.20 / 0.55 | 8.2% | 9.45 | 1.244 | 4.6% | 0.25 / 0.62 | 0.57 / 0.95 | 11.7% | 8.3% | 4.11 |
| WeightedLS halving (TimeToDie) | 1.328 | 0.19 / 0.54 | 7.9% | 25.99 | 1.431 | 1.8% | 0.24 / 0.61 | 0.22 / 0.69 | 6.9% | 7.6% | 15.55 |
| Ring8 (old plan) | 1.452 | 0.17 / 0.47 | 8.1% | 19.90 | 1.601 | 4.9% | 0.22 / 0.57 | 0.24 / 0.70 | 7.2% | 7.3% | 11.67 |
| HeroLib-style OLS 10.4 s | 1.408 | 0.16 / 0.48 | 7.6% | 8.31 | 1.923 | 10.3% | 0.25 / 0.66 | 0.57 / 1.00 | 11.7% | 8.2% | 3.63 |
| Hekili-retail mean of rates | 1.799 | 0.36 / 0.66 | 16.5% | 19.11 | 1.801 | 4.9% | 0.24 / 0.57 | 0.32 / 0.71 | 8.5% | 10.5% | 13.68 |
| Research recommendation (as written) | 2.867 | 0.21 / 1.52 | 9.6% | 81.17 | 2.920 | 2.1% | 0.32 / 1.07 | 0.59 / 1.39 | 13.5% | 9.9% | 41.69 |
