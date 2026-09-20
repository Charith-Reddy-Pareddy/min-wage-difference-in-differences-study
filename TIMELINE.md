# Build timeline: a 10-day compressed implementation of an 8-week design

The proposal (`docs/` — original PDF, not committed) scopes this as an 8-week
project. This repo compresses the same confirmatory family into a 10-day
schedule: each day below is one focused commit, reviewed before moving to
the next.

| Day | Milestone | Proposal ref |
|---|---|---|
| 1 | Research questions, analysis plan, treatment classification table (**done**) | Week 1 |
| 2 | Pull real FRED/QCEW data; source-check treatment table against DOL/NCSL; scaffold the CPS-ORG pull (**done**) | Week 2 |
| 3 | Exposure measure from CPS-ORG; QCEW correlation validation check; exposure-distribution check (**done**) | Week 2-3 |
| 4 | Simple linear regression (§7) and multiple regression (§6.1) (**done**) | Week 4 |
| 5 | Model A (binary DiD) and Model C (exposure interaction), both industries (**done**) | Week 5 |
| 7 | Event study / parallel-trends check; COVID-sensitivity covariate spec (**done**) | Week 6-7 |
| 8 | Placebo test; cluster bootstrap for β₄; model diagnostics (**done**) | Week 7 |
| 9 | Two-sample t-test; descriptive statistics; one-way regional ANOVA; Monte Carlo permutation (**done**) | Week 8 |
| 10 | Final R Markdown report, README pass, reproducibility check (**done**) | Week 8 |

**Resolved:** the Day 2/3 IPUMS blocker is cleared — a real `IPUMS_API_KEY`
was set locally and the CPS-ORG pull ran for real (Day 3).

**Environment note:** the project moved from `~/Desktop` to `~/Projects`
partway through Day 3 after `~/Desktop`'s iCloud sync (full quota) started
corrupting `.git` objects mid-session. Recovered by re-cloning from GitHub
(which was current through the Day-2 commits) and re-copying the
not-yet-committed Day-3 files over individually with checksum verification.
No history or data was lost, but this is why the repo now lives outside
any iCloud-synced folder.

**Power analysis note:** Section 4.4 of the proposal pre-registers this
design as likely underpowered for the exposure-gradient question (β₄) —
that's expected, not a bug to chase. **Correction, written at the end of
Day 10:** earlier entries in this file said the formal Monte Carlo power
simulation (Section 4.4's `sim_power`, estimating the minimum detectable
effect) was "folded into a later day." It wasn't -- there was no later
day it got folded into, and it was never built. What actually happened is
the *qualitative* pre-registered expectation (design likely underpowered
for β₄) got carried through the write-up and was borne out by the
results (noisy, sign-inconsistent β₄ across every specification), but the
quantitative MDE calculation itself was never run. That's a real gap in
this build, not a rounding error, and it's flagged as such in the final
report's Limitations section rather than left to look like it happened
somewhere it didn't.

**Post-build addition (not one of the 10 days above):** the quantitative
power simulation flagged as missing above was built afterward, in
`R/16_power_analysis.R` — a residual-based Monte Carlo simulation on the
real panel (same method `R/11_cluster_bootstrap.R` already uses). The
proposal's Section 4.4 actually specifies two separate power analyses,
and both are now built:

- **β₃ (Model A, average effect)**, at the proposal's own assumed grid
  of 0.5%/1%/2%/3%: MDE at 80% power isn't reached anywhere in that
  range for either industry. See `reports/figures/power_analysis_beta3.png`
  and `data/processed/power_analysis_beta3_results.csv`.
- **β₄ (Model C, exposure gradient)**: MDE at 80% power is β₄≈0.50 for
  food service and β₄≈0.22 for retail — both well above the actual
  observed estimates (0.167 and -0.005). See `reports/figures/power_analysis.png`
  and `data/processed/power_analysis_results.csv`.

Both confirm the design's qualitative "likely underpowered" expectation
with a number, for both parameters the proposal named.

**Post-build additions, continued (`R/17`-`R/26`):** ten more scripts,
added across several later passes once `R/16` established the pattern of
closing gaps the compressed 10-day build didn't get to.

- **`R/17_exposure_bandwidth_sensitivity.R`**: refits Model C's β₄ at
  10%/12.5%/15% exposure bands (all three were already computed in
  `R/04`, but only 12.5% was ever used downstream). Result: sign and
  significance pattern is consistent across all three bands for both
  industries — not an artifact of the band-width choice.
- **`R/18_marginal_effects.R`**: plots `β₃ + β₄ × exposure` with a
  delta-method confidence band, the direct visual answer to the
  primary research question ("does the effect scale with exposure?").
- **`R/19_treatment_intensity.R`**: an exploratory model using the
  continuous dollar size of each state's increase instead of a binary
  treated indicator. Food service comes back negative and marginally
  significant (p=0.043), retail negative but not significant (p=0.169)
  — directionally consistent with Model A, but explicitly labeled
  non-confirmatory since increase size wasn't randomly assigned.
- **`R/20_leave_one_out.R`**: refits Model A dropping each treated state
  once. `treated_post` stays in a narrow band across all 20 drops (food
  service -0.031 to -0.021, retail -0.014 to -0.007) — no single state
  is driving the result.
- **`R/21_coefficient_forest_plot.R`**: one dot-and-whisker plot of all
  four confirmatory estimates (β₃/β₄ × both industries) side by side,
  replacing four separate reads of `model_a_c_results.csv`.
- **`R/22_multiple_testing_correction.R`**: Holm-adjusted p-values
  across the 4 headline-specification tests. None survive correction
  (smallest raw p=0.118 for β₃ food service becomes 0.472 adjusted) —
  the same "not robust" conclusion the individual tests already reached,
  now stated as one formal joint test instead of four separate ones
  that happen to agree.
- **`R/23_specification_curve.R`**: the first genuinely new analysis
  after the symmetry-completion pattern above — a 12-specification
  multiverse (3 exposure bands × 2 samples × 2 industries) for β₄, all
  ranked on one plot. Only 2 of 12 are significant, both retail in the
  ≥$0.50 subsample, and food service's estimate is positive in all 6 of
  its specifications while retail's is negative in all 6 — the two
  industries don't even agree on sign.
- **`R/24_beta4_robustness_summary.R`**: by this point four independent
  checks (the placebo test and permutation test extended to β₄ earlier,
  the event study extended to β₄, and the specification curve above)
  each separately flagged β₄ as fragile. This script pulls all four into
  one table rather than leaving a reader to piece it together across
  four report sections — and prompted a pass fixing a stale claim in the
  report's Section 8 that still described the permutation test as
  purely corroborating Model A, no longer true once it covered β₄ too.
- **`R/25_exposure_covid_correlation.R`**: asks *why* β₄ looks
  confounded. Tests the obvious candidate directly: does a state's
  pre-2021 exposure share correlate with its own COVID severity?
  Significant negative correlation for both industries (food service
  r=-0.35, p=0.018; retail r=-0.54, p=0.0001) — higher-exposure states
  were hit harder by COVID, a real candidate mechanism.
- **`R/26_covid_controlled_placebo.R`**: tests that candidate mechanism
  directly rather than leaving it as a proposed-but-unverified
  explanation — adds `covid_severity x post` to the placebo-date Model C
  specification and checks whether the spurious placebo β₄ shrinks
  toward zero. It largely doesn't (8% shrinkage for food service,
  retail's effect actually grows). Both the README and report Section
  4.3 were revised after this result to say so plainly: COVID severity
  is a real, correlated factor, not the full explanation for why β₄'s
  identification is confounded.

Each of these ten scripts followed the same process as the original
build: implement, test on synthetic fixtures with known ground truth,
run against the real panel, verify the full suite still passes, wire
into the report and README, then commit. Two recurring test-fixture bugs
surfaced along the way and were fixed as genuine defects, not staged
ones — a synthetic panel with `gdp`/`population` varying only by quarter
becomes exactly collinear with the quarter fixed effect once a
*restricted* model has no `treated_post` term left to absorb it (hit
independently in three different test files), and a design needs at
least 2 treated states with *different* exposure values or
`treated_post:exposure` is exactly collinear with `treated_post` alone.

**Controlled debugging exercise (`R/04`, `R/07`, `R/13`):** three
defects were deliberately planted, one at a time, to practice the
debug workflow itself rather than to demonstrate a real incident — an
off-by-one on the treatment date (`quarter > treatment_effective`
instead of `>=` in `build_panel()`, which also silently broke
`R/10`'s placebo test since it reuses that function), a swapped-operand
sign flip in `compute_pre_period_trend()`, and a magic-number typo
(`n_obs < 3` instead of `< 30`) in the exposure cell-size check. Running
the suite surfaced 6 failures across 4 test files; all three were fixed
and three new regression tests added that pin the exact failure mode
(a boundary quarter, an explicit sign check, the exact threshold value)
rather than relying on the same test that happened to catch it this
time. Both the planting commit and the fix commit say so directly in
their messages — this did not happen during ordinary development.

**Post-build addition: ML/neural-network extension (`R/27`-`R/28`,
`python/`):** a predictive-accuracy comparison, explicitly kept separate
from the causal claims above — how well can flexible ML methods predict
quarterly employment growth for a state held out entirely from training,
versus a plain linear specification. The first working version predicted
`log_employment`'s *level* and came back with a negative R² for every
model; the actual bug was the target variable, not the models — a
held-out state's employment level is dominated by its population size
(California vs. Wyoming), which nothing in the feature set could recover.
Switching the target to year-over-year employment *growth* (scale-invariant
across states) fixed it: R² went from negative to a sensible ~0.39-0.58
across methods. `R/27` also established the state-level train/test split
(never a row-level one, for the same reason the causal models' SEs are
state-clustered) and a hand-rolled bagged-trees ensemble; `R/28` added a
single-hidden-layer neural network (`nnet`, train-only standardization);
`python/` is an independent replication in numpy/pandas/PyTorch, built
because this development machine's `scipy` wheel doesn't load (a
Mach-O loader error, unrelated to this project's code — see
`python/README.md`), so the classical models are hand-rolled there too
rather than via scikit-learn.

**Post-build addition: real random forest (`R/27`, `python/`):** the
original bagged-trees ensemble's docstring claimed a random feature
subset per tree "turns plain bagging into a random forest" — that's
wrong. It's the random subspace method (Ho 1998): one fixed subset per
tree. Breiman's actual algorithm re-samples the feature subset at
*every split node*, not once per tree. Added `fit_random_forest()` via
the real `randomForest` package in R, and a hand-rolled `RandomForest`
class in Python with genuine per-node resampling (a different code path
from `BaggedTrees`, not the same ensemble renamed) — and corrected the
original comment rather than leaving it. Random forest outperformed the
random-subspace bagging in both languages, as expected from the
stronger decorrelation.

**Post-build addition: gradient boosting (`R/27`, `python/`):** the
`gbm` package in R (5-fold cross-validated tree count, rather than
naively using every tree fit), and a hand-rolled `GradientBoostedTrees`
in Python (sequential shallow trees fit to residuals — no bootstrap
resampling at all, a genuinely different combination strategy from the
two ensembles above). First real-data run crashed: `gbm`'s
cross-validation workers don't auto-coerce a character `region` column
to a factor the way `lm()`/`rpart()`/`randomForest()` silently do via
`model.frame()` — fixed by making `region` an explicit factor in
`build_ml_panel()`. Gradient boosting came out the strongest predictor
of all five methods in both languages (R: R²=0.64; Python: R²=0.49), a
sensible result rather than a foregone one.

**Post-build addition: wage pass-through, a new research question
(`R/29`):** everything through `R/28` asks whether employment fell;
this asks whether the policy raised earnings at all, and by how much
relative to the mandated dollar increase. The obvious approach —
state-level average hourly earnings at the same NAICS-722/44-45
resolution the employment analysis uses — doesn't exist: every
candidate FRED series ID at that resolution 404s (confirmed by direct
`curl` requests against `fredgraph.csv`, the same verification standard
`R/02` already holds itself to, not assumed from documentation). Traced
the actual available resolution by working backward from a known-good
employment series ID on FRED's own site to its sibling earnings
series: state-level average hourly earnings is only published at the
CES **supersector** level. Landed on "Leisure and Hospitality" (SMU
industry code `70000`, data type `00003`) as the food-service proxy and
"Trade, Transportation, and Utilities" (`40000`) as the retail proxy —
both broader than the employment analysis's industries, a real
limitation stated prominently in the script header, the README, and the
report rather than glossed over. Unlike the detailed employment series
(which 404s for New Mexico and South Dakota, needing a QCEW fallback in
`R/02`), both supersector series returned real data for all 50 states on
the first attempt — checked directly for several small states (South
Dakota, Wyoming, Vermont, Alaska, Hawaii) before running the full pull.
Reused `build_panel()` and `fit_model_a()` from `R/07` completely
unchanged, by joining the new wage series onto the existing
`fred_state_quarter.csv` panel and passing it in as `outcome_col` — no
new DiD machinery needed. Result: neither proxy shows a statistically
significant wage effect (food service p=0.65, retail p=0.22), with
point estimates implying 13% and 63% pass-through of the mandated
increase respectively — read as "underpowered to detect pass-through at
this resolution," consistent with this project's recurring theme, not
as evidence pass-through is genuinely that low.

**Post-build addition: treatment predictability (`R/30`):** picked
specifically to cover the two STAT 240/340 techniques this project
hadn't used yet -- a chi-square test of independence and logistic
regression as a classifier -- but the result turned out to matter well
beyond coursework coverage. The chi-square test (treatment status x
Census region) rejects independence (p=0.046). The logistic regression
(treated ~ pre-period GDP growth + population growth + food-service
exposure, n=45) classifies treated vs. control states at 87% accuracy
and AUC=0.97, with exposure the single strongest predictor (p=0.013).
That the primary scientific-hypothesis variable (exposure) also
strongly predicts treatment assignment itself is an independent
confirmation of the confounding R/25-R/26 already found by a completely
different route (correlating exposure with COVID severity directly) --
not a coincidence worth burying in a coursework-completion footnote.

**Post-build addition: state clustering (`R/31`):** the second half of
the same idea, unsupervised this time. Hand-rolled k-means (with
k-means++ initialization -- Arthur & Vassilvitskii 2007 -- rather than
uniform-random initial centroids, for the same "make the ensembling
mechanics visible" reason R/27's fit_bagged_trees() is hand-rolled
instead of calling a library) on the same pre-period features,
standardized. The elbow curve was honestly gradual rather than sharply
bent at any one k; k=3 was picked as a judgment call, documented as
such in the script rather than overstated as an obvious elbow. Result:
2 of the 3 resulting clusters are almost entirely pure treated or pure
control (χ²=28.0, p<0.0001) -- unsupervised, states weren't told their
treatment status, and it emerged from the clustering anyway. Three
independent methods (β₄'s original robustness battery, R/30's
predictability check, and this clustering result) now converge on the
same conclusion from three unrelated angles: treated and control states
were not comparable on pre-existing characteristics.
