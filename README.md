# State Minimum Wage Increases and Low-Wage Employment: A Difference-in-Differences Study with Power, Heterogeneity, and Robustness Analysis

A difference-in-differences study of the 2021 round of state minimum wage
increases, extended beyond a single average treatment effect to ask how the
employment response varies with pre-policy wage exposure.

## Research questions

**Primary:** How does the employment response to state minimum-wage
increases vary with pre-policy minimum-wage exposure across low-wage
industries?

**Secondary:**
1. Does minimum-wage treatment affect employment in food service and retail?
2. Is the effect larger where exposure is greater?
3. Does the effect differ across Census regions?
4. How sensitive are these conclusions to alternative treatment definitions
   and inference procedures?

This builds on a standard Card-Krueger-style state minimum wage DiD design.
The contribution isn't a new question but a specific empirical angle: moving
from one average treatment effect to modeling how that effect scales with
exposure.

## Data sources

| Source | Role |
|---|---|
| FRED | State-quarter employment (food service, retail), GDP, population |
| U.S. DOL (cross-checked against NCSL) | Treatment classification (wage change dates/amounts) |
| QCEW wage-band tables / CPS ORG (IPUMS-CPS) | Exposure measure construction |
| CPS (IPUMS-CPS) | Teen employment (16-19), secondary outcome |

## Repo layout

```
data/raw/        source pulls, not committed (see .gitignore)
data/processed/  cleaned panel data, not committed
R/               data prep and analysis scripts
reports/         R Markdown report and figures
```

## Status

See [TIMELINE.md](TIMELINE.md) for the day-by-day build schedule.

**Day 1:** Treatment classification table drafted, validated by
`R/01_treatment_classification.R`.

**Day 2:** Treatment table source-checked against DOL's historical minimum
wage tables (two Wayback Machine snapshots, straddling the Jan 1, 2021
changes). 24 of 25 states matched the draft exactly; Michigan's 2021
increase turned out not to have happened at all (see the note at the top of
`R/01_treatment_classification.R`) and has been corrected. That also
resolves the earlier "10 vs. 9 states below $0.50" open item: the correct
count is 10, and the proposal text's "9" looks like a minor error in the
proposal narrative rather than a data problem.

`R/02_fetch_fred_data.R` pulls real state-quarter employment (food service,
retail), GDP, and population for all 25 states from FRED's public endpoint
(2015-2022). FRED doesn't publish the food-service employment series for
New Mexico or South Dakota (confirmed 404, not assumed); those two states
fall back to QCEW's Open Data API instead, converted to the same thousands
scale FRED uses.

**Day 3:** `R/03_fetch_cps_org.R` pulled real CPS-ORG microdata (all 24
monthly 2019-2020 Basic samples, ORG respondents only — a hardcoded
"January of each year" guess turned out to be wrong on the first attempt;
see the comment above `resolve_cps_org_samples()`).

`R/04_exposure_measure.R` builds the exposure share (workers within 10%,
12.5%, and 15% of the pre-2021 state minimum wage) per state-industry cell,
weighted by `EARNWT`. All 50 state-industry cells clear the proposal's
n=30 threshold on the full 2019-2020 pool, so no pooling-across-quarters
fallback was needed in practice.

`R/05_exposure_validation.R` runs both Day 3 validation checks:
- **QCEW correlation check** (Section 3): QCEW's average wage (hourly
  proxy) over the state minimum wage, correlated against the CPS-ORG
  exposure share. Both industries show the expected negative relationship
  (food service: -0.76, retail: -0.33) — neither flagged.
- **Exposure-distribution check** (Section 5): food service exposure is
  higher than retail in 24 of 25 states (mean 0.415 vs. 0.294, Wilcoxon
  signed-rank p < 0.0001), confirming the two industries genuinely differ
  in exposure before that difference is used in Model C.

Processed outputs land in `data/processed/` (gitignored, reproducible by
re-running the scripts in order).

**Day 4:** `R/06_slr_mlr.R` builds the derived per-state outcome from
Section 4.1 — each state's average log employment change, pre-period
(2019-2020) to post-period (2021-2022) — separately for food service and
retail, and fits:
- **SLR** (Section 7): log employment change on the dollar size of the
  wage increase, treated states only. Not significant for either industry
  (food service p=0.46, retail p=0.62) — consistent with the proposal's
  own pre-registered expectation (Section 15) of a small, possibly
  inconclusive effect, not a modeling problem.
- **MLR** (Section 6.1): log employment change on treatment status, GDP
  growth, population growth, and Census region, all 25 states. GDP growth
  is a significant positive predictor in both industries; the treated
  coefficient itself is only marginal for food service (p=0.059) and
  essentially zero for retail (p=0.996).

Scatter/fitted-line/CI-band and residuals-vs-fitted plots for both SLR
models are in `reports/figures/`. These are the STAT 240/340
coursework-closure pieces (Section 9), not the study's identification
strategy — that's Model A/C (Day 5) and the event study (Day 7).
