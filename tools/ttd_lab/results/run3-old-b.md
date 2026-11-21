## Run 3 strategies on the run 1 and run 2 classes (seed set B)

Score = weighted mean of (term / median of the main lineup's term); weights: unknown 1, relMed 0.5, relP90 0.5, wrongMean 1, flipSum 1. Lower is better. scale=1

### Old and new classes

| algorithm | old score | old rel med/p90 | old wrong | old flips | new score | new unknown | new rel med/p90 | new post-change rel med/p90 | new post-change wrong | new wrong | new flips |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Run 2 recommendation, learned w=0.25 | 0.813 | 0.15 / 0.46 | 6.8% | 11.61 | 0.753 | 1.6% | 0.15 / 0.37 | 0.22 / 0.51 | 5.2% | 4.8% | 5.04 |
| Run 2 recommendation: 20% learned, one session | 0.816 | 0.16 / 0.47 | 6.9% | 11.50 | 0.757 | 1.6% | 0.15 / 0.38 | 0.22 / 0.53 | 5.3% | 4.8% | 5.03 |
| c. all lines, prior wrong share (1/8 each: too low), learned | 0.862 | 0.18 / 0.49 | 7.6% | 11.93 | 0.872 | 1.6% | 0.22 / 0.53 | 0.36 / 0.80 | 8.2% | 6.8% | 4.85 |
| a. no execute hint (default) | 0.835 | 0.16 / 0.49 | 7.1% | 11.69 | 0.903 | 1.6% | 0.24 / 0.60 | 0.41 / 0.92 | 9.5% | 7.4% | 4.63 |
| b. own line, learned w=0.25 | 0.836 | 0.16 / 0.49 | 7.1% | 11.68 | 0.903 | 1.6% | 0.24 / 0.60 | 0.41 / 0.92 | 9.6% | 7.4% | 4.63 |
| b. own line, learned | 0.837 | 0.17 / 0.49 | 7.1% | 11.68 | 0.903 | 1.6% | 0.24 / 0.60 | 0.41 / 0.92 | 9.6% | 7.4% | 4.61 |
| Run 1 winner (pinned) | 0.844 | 0.17 / 0.49 | 7.2% | 11.68 | 0.913 | 1.6% | 0.25 / 0.61 | 0.50 / 0.94 | 10.5% | 7.5% | 4.62 |
| c. own line, prior x2 equal share, learned | 0.960 | 0.22 / 0.52 | 9.4% | 12.20 | 0.863 | 1.6% | 0.19 / 0.48 | 0.29 / 0.70 | 6.7% | 6.4% | 5.38 |
| d. all lines, prior x2 equal share, fixed | 0.963 | 0.23 / 0.52 | 9.5% | 12.15 | 0.863 | 1.6% | 0.19 / 0.48 | 0.29 / 0.70 | 6.7% | 6.4% | 5.37 |
| Midpoints (TimeToDie default) | 0.922 | 0.21 / 0.59 | 7.7% | 11.31 | 0.972 | 1.8% | 0.25 / 0.63 | 0.57 / 0.97 | 11.3% | 7.9% | 4.95 |
| d. all lines, prior wrong mult (x3: too high), fixed | 1.063 | 0.27 / 0.58 | 11.3% | 12.51 | 0.866 | 1.6% | 0.19 / 0.48 | 0.29 / 0.66 | 6.6% | 6.6% | 5.38 |
| d. all lines, x2 whatever the group, fixed | 1.096 | 0.29 / 0.59 | 11.7% | 12.76 | 0.866 | 1.6% | 0.18 / 0.45 | 0.28 / 0.58 | 6.4% | 6.4% | 5.63 |
| LeastSquares (TimeToDie) | 1.030 | 0.25 / 0.89 | 9.1% | 10.12 | 1.053 | 1.8% | 0.28 / 0.96 | 1.03 / 1.79 | 18.5% | 9.5% | 3.99 |
| SimC-style cumulative | 1.205 | 0.20 / 0.57 | 8.3% | 9.80 | 1.263 | 4.4% | 0.25 / 0.62 | 0.56 / 0.94 | 11.3% | 8.2% | 4.05 |
| WeightedLS halving (TimeToDie) | 1.298 | 0.19 / 0.54 | 8.2% | 26.51 | 1.445 | 1.8% | 0.24 / 0.60 | 0.23 / 0.68 | 6.6% | 7.5% | 14.80 |
| Ring8 (old plan) | 1.448 | 0.18 / 0.48 | 8.3% | 20.66 | 1.675 | 4.9% | 0.22 / 0.57 | 0.25 / 0.70 | 6.9% | 7.4% | 11.94 |
| HeroLib-style OLS 10.4 s | 1.405 | 0.17 / 0.49 | 7.8% | 9.03 | 1.950 | 10.1% | 0.25 / 0.65 | 0.56 / 1.00 | 11.3% | 8.1% | 3.27 |
| Hekili-retail mean of rates | 1.741 | 0.35 / 0.67 | 16.5% | 18.76 | 1.799 | 4.9% | 0.24 / 0.56 | 0.33 / 0.70 | 8.4% | 10.0% | 12.74 |
| Research recommendation (as written) | 2.816 | 0.22 / 1.55 | 9.8% | 84.31 | 2.841 | 2.0% | 0.31 / 1.03 | 0.58 / 1.38 | 13.2% | 9.6% | 38.26 |
