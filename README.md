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
  growth, population growth, and Census region.

Scatter/fitted-line/CI-band and residuals-vs-fitted plots for both SLR
models are in `reports/figures/`. These are the STAT 240/340
coursework-closure pieces (Section 9), not the study's identification
strategy — that's Model A/C (Day 5) and the event study (Day 7).

**Correction (found while starting Day 5):** the proposal names the 20
treated and 5 excluded/secondary states explicitly (Section 4.2) but never
lists the actual control group ("states with no 2021 change") its own
design depends on. The original Day 4 MLR ran on the only 25 states
classified at the time (20 treated + the 5 later-2021-changer "excluded"
states), which isn't a real treated-vs-control comparison — those 5 states
raised wages too, just not on 1/1/2021. Added a real control group: the
other 25 states, each source-checked against DOL snapshots from Dec 2020,
Feb 2021, and Dec 2021, confirming zero minimum-wage movement across all
of 2021 (see the note in `R/01_treatment_classification.R`). The MLR now
runs on treated + control (45 states), with the "excluded" group correctly
left out of the primary specification. Result changed in a meaningful way:
the treated coefficient is now null for both industries (food service
p=0.65, retail p=0.26) rather than marginally significant for food
service — the earlier result was likely an artifact of the contaminated
comparison group, not a real signal.

**Day 5:** `R/07_model_a_c.R` is the study's actual identification
strategy (Section 6.2) — everything before this was coursework-closure or
setup. Two-way fixed-effects (state + quarter), state-clustered SEs, on
the treated + control panel (2016Q1-2022Q4; the growth covariates need a
4-quarter lag, which consumes 2015). Run for both industries and both the
full 20-treated-state sample and the ≥$0.50-increase subsample:

- **Model A** (β₃, the average effect): negative in all 4 specifications,
  but only significant in the ≥$0.50 subsample (food service p=0.016,
  retail p=0.049) — the full sample includes states with increases as
  small as $0.00-0.19, which dilutes the average effect toward zero,
  same story the proposal's own sensitivity threshold is designed to
  surface.
- **Model C** (β₄, the primary hypothesis): noisy and inconsistent in
  sign across specifications — positive for food service, negative for
  retail, significant only in the ≥$0.50 subsample. This is close to
  what Section 4.4 pre-registers as the expected outcome: a design that
  may not reliably distinguish "no gradient" from "real gradient" given
  the sample size. The formal power simulation (later day) will state
  that limit quantitatively rather than just qualitatively.
- Every `fixest` Model A estimate was cross-checked against an
  independent `lm()` + `sandwich::vcovCL()` fit — coefficients and
  clustered SEs matched to 4+ decimal places in all 4 specifications.

Full regression output and the 4-specification summary table are in
`data/processed/model_a_c_results.csv` (gitignored, reproducible).

**Day 7:** `R/08_event_study.R` (Sections 5, 6.4, 6.5) and
`R/09_covid_sensitivity.R` (Section 6.5's supporting check).

The event study is a real, meaningful finding — not a clean pass. The
joint test that all pre-period leads equal zero **rejects** flat
pre-trends for both industries (food service F=4.77, p<0.0001; retail
F=3.09, p=0.001). The shape isn't a gradual pre-trend drift so much as a
roughly stable, non-zero gap between treated and control states across
most of the sample (both pre- and post-period), plus one sharp anomalous
dip at quarter -3 relative to treatment — which is **2020 Q2, the COVID
employment trough** — most visible in retail. Plots:
`reports/figures/event_study_food_service.png` and `_retail.png`.

The COVID-sensitivity spec confirms why: adding `covid_severity x post`
(log employment change from 2019 Q4 to the 2020 Q2 trough, interacted
with the post indicator — a bare state-constant term would be fully
absorbed by the state fixed effect, the same collinearity `exposure` hit
in Model C, so it has to enter interacted) is highly significant in every
specification (p < 10⁻⁸). Once included, Model A's `treated_post`
shrinks toward zero (food service: -0.025 → -0.002; retail: -0.010 →
+0.006) and Model C's β₄ shifts substantially, even flipping sign for
retail (-0.005 → +0.102). Differential COVID recovery, not the minimum
wage policy, explains a real share of what Day 5's baseline specification
picked up.

Per Section 6.5, this is reported as a direct limit on how much weight
the Day-5 headline numbers can carry, not something to patch over — the
event study and this sensitivity check are exactly the tools the proposal
specifies for catching it, and they did.

**Day 8:** `R/10_placebo_test.R`, `R/11_cluster_bootstrap.R`,
`R/12_model_diagnostics.R` (Sections 6.4, 8, 11).

**Placebo test**: a false treatment date (2018-01-01), restricted to a
pre-COVID, pre-real-treatment window (2016-2019) so it isn't just
re-detecting the confound Day 7 already found. Clean result: small,
non-significant estimates for both industries (food service p=0.29,
retail p=0.43) — the design doesn't manufacture effects from nothing when
there's no real policy change to detect.

**Wild cluster bootstrap for β₄** (Cameron-Gelbach-Miller): `fwildclusterboot`,
the standard package for this, was pulled from CRAN in 2024 and doesn't
install on current R, so the procedure is implemented directly (999
Rademacher-weight replications, restricted-model residuals — see the
header comment in `R/11_cluster_bootstrap.R`, including a note on where
the proposal's own wording is internally inconsistent about which
bootstrap variant it means). On the real 20-treated-state panel, bootstrap
p-values track the asymptotic ones closely (food service: 0.367 vs. 0.338
asymptotic; retail: 0.953 vs. 0.953) — both 95% CIs include zero,
confirming Day 5's asymptotic β₄ result rather than overturning it.

Building the test suite for this surfaced a real property of the method
worth knowing, not a bug: with very few treated clusters (~5, tried
first) and a treatment effect large enough to badly misspecify the
restricted null model, the wild bootstrap's reference distribution
becomes numerically unstable. Confirmed by testing 10 vs. 30 synthetic
states directly. Real Day 5-8 data (20 treated states) is comfortably
outside that regime.

**Model diagnostics** (Section 11) for Model A, both industries — 4-panel
plots in `reports/figures/model_a_diagnostics_{food_service,retail}.png`.
Residuals are non-normal by a Shapiro-Wilk test (p≈0 both industries,
though with 1,260 observations that test is hypersensitive to small
deviations). More informative: the specific highest-leverage points in
both industries are 2020 Q2-Q3 observations — Vermont and New York (Q2
2020), Hawaii (Q3 2020, heavily tourism-dependent) — the same COVID window
Day 7 already flagged as the central identification threat, not a new or
separate data problem. No single observation is extreme by Cook's
distance (max 0.046, food service), so results aren't being driven by one
outlier state.

**Day 9:** `R/13_two_sample_ttest.R`, `R/14_regional_anova.R`,
`R/15_permutation_test.R` (Section 10, STAT 240/340 coursework closure).

**Two-sample t-test** on pre-period (2019 Q1 → 2020 Q4) employment
trends, treated vs. control: **food service shows a real, significant
difference** (treated -0.197 vs. control -0.118, t=3.03, p=0.0043) —
treated states' food-service employment was already declining faster
than control states' *before* treatment started. This independently
corroborates Day 7's event-study pre-trend violation using a completely
different, simpler method — not a new problem, the same one confirmed a
second way. Retail shows no such difference (p=0.30), consistent with
its weaker pre-trend violation in Day 7.

**Descriptive statistics** (mean/SD of the pre-period trend, by group ×
industry × increase type) in `data/processed/descriptive_statistics.csv`.

**One-way regional ANOVA** (exploratory, Section 6.3): regions differ
significantly in log employment change for both industries (food service
F=5.10, p=0.0039; retail F=5.64, p=0.0022) — West notably higher than
Midwest/South. Real geographic heterogeneity, unrelated to treatment;
doesn't override Model C, which remains the formal heterogeneity test.
Boxplots (by region and group) in
`reports/figures/regional_boxplot_{food_service,retail}.png`.

**Monte Carlo permutation test**, Model A only, 10,000 relabelings of
which states are "treated" (state-level, not row-level, holding n_treated
fixed at the real design's count): permutation p-values track the
asymptotic Day-5 ones closely (food service: 0.09 vs. 0.118 asymptotic;
retail: 0.377 vs. 0.385 asymptotic) — another confirmation, not a
reversal. Null-distribution histograms in
`reports/figures/permutation_test_{food_service,retail}.png`.
