# State Minimum Wage Increases and Low-Wage Employment

[![CI](https://github.com/Charith-Reddy-Pareddy/min-wage-difference-in-differences-study/actions/workflows/ci.yml/badge.svg)](https://github.com/Charith-Reddy-Pareddy/min-wage-difference-in-differences-study/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Live site](https://img.shields.io/badge/live%20site-charith--reddy--pareddy.github.io-9a3324)](https://charith-reddy-pareddy.github.io/min-wage-difference-in-differences-study/)

**Question.** Does the employment response to the 2021 round of state
minimum-wage increases vary with each state-industry's pre-policy
exposure to the new wage floor?

**Method.** A difference-in-differences design: 20 states that raised
their minimum wage in 2021 Q1 vs. 25 states with no change that year,
quarterly food-service and retail employment, 2015-2022, state and
quarter fixed effects, state-clustered inference — extended with an
interaction term letting the effect scale with a state-industry's
pre-policy exposure share.

**Finding.** The baseline average effect is negative but not credible as
a causal effect, and the exposure-gradient extension is underpowered and
confounded. See [Results at a Glance](#results-at-a-glance) below.

**Why the finding is uncertain.** Parallel pre-trends — the assumption
this design's causal claim actually rests on — are directly tested
(Section 4.1 of the [full report](#final-report)) and found to be
**violated for food service**. That is this study's real identification
problem, checked directly rather than assumed, and it's why every result
below is reported with that caveat attached rather than as a clean
causal estimate.

<img src="reports/figures/event_study_food_service.png" width="70%">

**Reproduce:** `Rscript -e 'renv::restore()' && make all` — see
[How to Reproduce](#how-to-reproduce) for the full command list.

---

**Primary contribution — causal inference / econometrics:** a
Card-Krueger-style state minimum-wage DiD design, extended to ask how
the effect scales with pre-policy exposure and stress-tested with every
credibility check the data will support (event study, placebo test,
COVID-sensitivity spec, wild cluster bootstrap, permutation test,
specification curve, power analysis). This is the project's actual
research contribution and the rest of this README is organized around
it first.

**Secondary — predictive modeling comparison:** an ML/neural-network
predictive-accuracy comparison (R and Python) and two exploratory checks
(treatment predictability, state clustering) are included as
**extensions**, not co-equal findings — see
[Extensions](#extensions) below. They inform
the causal analysis's credibility checks; they don't replace them.

## Research Questions

**Primary:** How does the employment response to state minimum-wage
increases vary with pre-policy minimum-wage exposure across low-wage
industries?

**Secondary:**
1. Does minimum-wage treatment affect employment in food service and retail?
2. Is the effect larger where exposure is greater?
3. Does the effect differ across Census regions?
4. How sensitive are these conclusions to alternative treatment definitions
   and inference procedures?
5. Did the increases actually raise earnings in low-wage industries, and
   by how much relative to the size of the mandate (pass-through)?
6. Is treatment status itself predictable from pre-period state
   characteristics, and do states form natural economic clusters that
   track treatment status? (Exploratory; see
   [Extensions](#extensions) — this does not
   itself bear on whether the DiD design is valid, since DiD doesn't
   require random assignment.)

### Confirmatory vs. Exploratory

Which analyses were specified before results were seen, and which were
added afterward, matters for how much weight a p-value can carry.

| | Analyses | Status |
|---|---|---|
| **Confirmatory** (pre-specified in the original proposal) | Model A (β₃), Model C (β₄, pre-registered as likely underpowered), event study, COVID-sensitivity spec, placebo test, wild cluster bootstrap, permutation test, power analysis | Reported regardless of significance |
| **Exploratory** (added after the original build, motivated by what the confirmatory results showed) | Bandwidth sensitivity, marginal effects, treatment intensity, leave-one-out, multiple-testing correction, specification curve, exposure–COVID correlation, COVID-controlled placebo, wage pass-through, treatment predictability, state clustering, ML/NN comparison | Informs interpretation; not held to the same inferential standard as the confirmatory family |

## Key Metrics

| | |
|---|---|
| **Sample** | 50 states, quarterly 2015-2022 (1,260 obs in the estimation panel) — 20 treated, 25 control, 5 excluded |
| **Model A, β₃** (avg. effect) | -0.025 food service (p=0.12), -0.010 retail (p=0.39); significant only in the ≥$0.50 subsample |
| **Model C, β₄** (exposure gradient) | 0.167 food service (p=0.34), -0.005 retail (p=0.95) — noisy and inconsistent in sign |
| **Robustness on β₄** | 4/4 independent checks (placebo, permutation, event study, spec curve) flag it as confounded |
| **Inference** | State-clustered SEs, wild cluster bootstrap, 10,000-rep permutation test, Monte Carlo power analysis |
| **Wage pass-through** | 13% (food service proxy, p=0.65) / 63% (retail proxy, p=0.22) of the mandated increase — neither significant |
| **Treatment predictability** | Logistic regression on pre-period growth + exposure: 87% accuracy, AUC 0.97 — highly predictable |
| **State clustering** | k-means (k=3) on the same features: 2 of 3 clusters are essentially pure treated/control (χ²p<0.0001) |
| **Engineering** | 31 R scripts + a Python ML subproject, 163 R test blocks (all passing), CI on every push, `make all` for full reproduction |

## Results at a Glance

| Question | Result | Interpretation |
|---|---|---|
| Average employment effect | Negative but not robust | Weak causal evidence |
| Parallel trends | Violated (food service) | Major identification concern |
| COVID sensitivity | Large change once controlled for | Confounding likely |
| Exposure gradient (β₄) | Inconclusive and confounded | Underpowered, not "no effect" |
| Placebo / permutation / event study / spec curve (β₄) | All 4 flag a pre-existing exposure-outcome link | Convergent evidence, not one fluke |
| Exposure vs. COVID severity | Significant negative correlation | A candidate mechanism — but controlling for it barely moves the placebo effect |
| Multiple-testing correction | None of the 4 confirmatory tests survive Holm | Consistent with "not robust," now formal |
| Leave-one-state-out | Estimate stable across all 20 drops | No single state drives Model A |
| Wage pass-through | 13%/63% of the mandated increase, neither significant | Consistent with underpowered, not "no pass-through" |
| Is treatment predictable from pre-period data? | Yes — 87% accuracy, AUC 0.97 | Doesn't invalidate DiD, but motivates checking trends directly |
| Do states cluster by treatment status? | Yes — 2/3 k-means clusters are nearly pure | Same caveat — see event study (Section 4.1) for the actual test |

## Key Figures

<table>
<tr>
<td width="50%">

**Which states were treated, and by how much**
<img src="reports/figures/treatment_control_overview.png" width="100%">

</td>
<td width="50%">

**Event study: pre-trends don't hold for food service**
<img src="reports/figures/event_study_food_service.png" width="100%">

</td>
</tr>
<tr>
<td width="50%">

**Baseline vs. COVID-adjusted estimate**
<img src="reports/figures/covid_adjustment_comparison.png" width="100%">

</td>
<td width="50%">

**Pre-2021 exposure distribution by industry**
<img src="reports/figures/exposure_distribution.png" width="100%">

</td>
</tr>
</table>

**Does the treatment effect scale with exposure?**
<img src="reports/figures/marginal_effects.png" width="100%">

**All four confirmatory estimates at a glance**
<img src="reports/figures/coefficient_forest_plot.png" width="100%">

**Every reasonable band × sample × industry choice, ranked**
<img src="reports/figures/specification_curve.png" width="100%">

**Exposure predicts COVID severity — a candidate mechanism for the confound**
<img src="reports/figures/exposure_covid_correlation_retail.png" width="70%">

More figures — model diagnostics, permutation-test null distributions,
power-analysis curves, the beta4 event study and forest plot — are in
`reports/figures/` and embedded in the
[full report](reports/final_report.Rmd).

## Limitations

- **Parallel trends violated** for food service (event study + two-sample t-test) — this study's central, load-bearing identification problem.
- **COVID-era differential recovery confounds the treatment window** — a
  real share of the baseline estimate, not the policy.
- **Both β₃ and β₄ are underpowered** at the observed effect sizes
  (`R/16_power_analysis.R`), not just assumed underpowered.
- **β₄ is also confounded**, not just underpowered — 4 independent
  checks find high/low-exposure states already differed before 2021. A
  candidate mechanism (exposure correlates with COVID severity) was
  tested directly by controlling for it in the placebo spec
  (`R/25`-`R/26`) — the effect barely shrank. See report Section 8.1.
- **The ≥$0.50 subsample and the legislated-only subsample are the exact
  same 10 states** — the two cuts can't be disentangled in this data.
- **Small cluster count** (20 treated, 45 total) — addressed via
  clustered SEs and a wild bootstrap, but always some caution.
- **Wage pass-through uses broader supersector proxies**, not the exact
  food-service/retail industries — BLS/FRED don't publish earnings at
  that resolution by state (see [Extensions](#extensions)).
- **Exposure-measure construction, spillovers, anticipation effects, and
  external validity** are documented but not fully resolved.
- Results are **DiD estimates under this specification**, not definitive
  causal effects — see the full report's Limitations section for detail.

**Identification structure.** Not a generic textbook DAG — the red path
below is this study's own confounding structure, established
empirically (exposure predicts treatment status: `R/30`; exposure
correlates with COVID severity: `R/25`-`R/26`), not assumed:

<img src="reports/figures/identification_dag.png" width="85%">

## Final Report

**[Read the rendered report (HTML)](https://github.com/Charith-Reddy-Pareddy/min-wage-difference-in-differences-study/releases/tag/v1.0-report)**
or **[download the PDF](https://github.com/Charith-Reddy-Pareddy/min-wage-difference-in-differences-study/releases/download/v1.0-report/final_report.pdf)**
— no cloning required. Or render
[reports/final_report.Rmd](reports/final_report.Rmd) directly:

```
Rscript -e 'rmarkdown::render("reports/final_report.Rmd")'   # HTML
make report-pdf                                               # + PDF, via headless Chrome
```

(needs [pandoc](https://pandoc.org) — `brew install pandoc` on macOS — for
the HTML, and Chrome/Chromium installed locally for the PDF; see
`scripts/render_report_pdf.R` for why it's a headless-Chrome print
rather than a LaTeX pipeline).

## Extensions

Everything below is secondary to the causal analysis above, not
co-equal with it: a second research question (wage pass-through), two
exploratory checks on treatment assignment, and a predictive-modeling
comparison. None of them revise the causal estimates or their
limitations; they're included because they add real information, not
to pad the project's scope.

### Wage Pass-Through

A new research question, not a re-analysis of the one above: did the
2021 increases actually raise **earnings** in low-wage industries, and
by how much relative to the dollar size of the mandate (pass-through)?
Everything above asks whether employment fell; this asks whether the
policy did the thing it was actually meant to do.

**Data limitation, found by direct request** (`R/29_wage_passthrough.R`):
BLS/FRED do not publish state-level average hourly earnings at the
detailed NAICS-722 (food service) or 44-45 (retail trade) level the
employment analysis uses — every candidate series ID at that resolution
404s. The finest available state-level breakdown is the CES
**supersector**: "Leisure and Hospitality" (nests food service, but also
accommodation and arts/entertainment/recreation) as the closest proxy for
food service, and "Trade, Transportation, and Utilities" (nests retail,
but also wholesale trade, transportation, and utilities) as the closest
proxy for retail. Both are broader than the industries used elsewhere in
this study, so **this answers a related but not identical question** —
not "did retail workers' wages rise" but "did wages in retail's broader
supersector rise."

| Proxy industry | treated_post (log pts) | p | Mandated $/hr | Estimated $/hr | Pass-through |
|---|---|---|---|---|---|
| Leisure & Hospitality (food service proxy) | 0.0044 | 0.647 | $0.54 | $0.07 | 13% |
| Trade, Transportation & Utilities (retail proxy) | 0.0144 | 0.217 | $0.54 | $0.34 | 63% |

<img src="reports/figures/wage_passthrough.png" width="80%">

Neither estimate is statistically significant, and the food-service
proxy's confidence interval crosses zero on both sides — consistent
with this study's broader theme that these designs are underpowered at
the observed effect sizes, not evidence that pass-through is genuinely
13%/63% versus some other number. The likeliest reason both estimates
sit well under 100%: the supersector proxies include large numbers of
workers (hotel managers, arts/entertainment/recreation staff, wholesale
and utilities employees) who were never near the minimum wage to begin
with, diluting any real effect on the low-wage workers actually
targeted.

### Treatment Assignment: Predictability & Clustering

Exploratory analyses investigating systematic differences in
pre-treatment economic structure between treated and comparison states,
using techniques not used elsewhere in this study (a chi-square test of
independence, logistic regression as a classifier, k-means, PCA).

**Is treatment status independent of Census region?**
(`R/30_treatment_predictability.R`) A chi-square test of independence
says no (χ²=8.0, df=3, p=0.046) — the South is heavily under-represented
among treated states (2 of 20) relative to control (12 of 25).

**Is treatment status predictable from pre-period state
characteristics?** A logistic regression on pre-period (2019-2020) GDP
growth, population growth, and food-service exposure — the same
variables used elsewhere in this study, not new ones picked for this
check — classifies treated vs. control states with **87% accuracy and
an AUC of 0.97** at n=45. Exposure alone is the strongest, most
significant predictor (p=0.013).

<img src="reports/figures/treatment_predictability.png" width="60%">

**Do states form natural economic clusters, and do those clusters track
treatment status?** Unsupervised this time — no label is given to the
algorithm. A hand-rolled k-means (with k-means++ initialization; see
`R/31_state_clustering.R`) on the same pre-period features, k=3 chosen
from a gradual (not sharply-elbowed) WCSS curve, finds that **2 of the 3
clusters are almost pure treated or pure control** (χ²=28.0, p<0.0001):

<img src="reports/figures/state_clustering_pca.png" width="75%">

**On interpretation — this does not, by itself, invalidate the causal
design.** DiD does not require random treatment assignment. States
choosing to raise their minimum wage for identifiable political or
economic reasons is entirely compatible with valid causal identification,
*provided* the relevant conditional parallel-trends assumption holds.
Treatment being this predictable doesn't do the identification work
itself — what it does is raise the prior that treated and control states
might follow different *counterfactual* trends, which is exactly what
Section 4.1's event study tests directly rather than assumes. For food
service, that direct test finds pre-trends **are** violated (Section
4.1) — that is the actual identification problem this report leads with,
not the predictability result. The predictability and clustering
findings here are a reason to take the event study's verdict seriously,
not a second, independent verdict of their own.

### Machine Learning Extension

A predictive-accuracy comparison, separate from the causal claims
above: how well can flexible ML methods predict quarterly employment
*growth* for a state they never saw during training, versus a plain
linear specification? Evaluated by holding out entire states (not
rows) from training, since a row-level split would leak within-state
structure the causal models' clustered SEs already treat as
non-independent.

- **R** (`R/27_ml_prediction.R`, `R/28_neural_network.R`): a linear
  baseline, a hand-rolled bagged-trees ensemble (bootstrap-aggregated
  `rpart` trees, one fixed random feature subset per tree), a real
  random forest (the `randomForest` package — re-samples features at
  every split, not once per tree), gradient boosting (the `gbm`
  package, cross-validated to pick the number of trees), and a
  single-hidden-layer neural network (`nnet`).
- **Python** (`python/`): an independent replication in a separate
  ecosystem — numpy/pandas for data handling, a from-scratch regression
  tree with a bagging ensemble, a true random forest (per-split feature
  re-sampling), and gradient boosting (sequential trees fit to
  residuals) all hand-rolled since no ML library is usable here, plus a
  PyTorch feedforward network — reading the same panel the R side
  exports. See [python/README.md](python/README.md) for why it doesn't
  use scikit-learn.

On the held-out states, gradient boosting is the strongest predictor in
both languages (R: R²=0.64; Python: R²=0.49), ahead of the neural
network and both other tree ensembles — a sensible result, not a
foregone one, since boosting's sequential residual-fitting is a
genuinely different strategy from bagging/forests' independent,
averaged trees.

This is a methods comparison, not a substitute for Model A/C's
identification strategy — a model that predicts employment well isn't
thereby estimating the policy's causal effect on it.

## What I Learned

A significant DiD estimate isn't sufficient evidence of a causal effect.
The event study and COVID-sensitivity spec caught exactly the failure
modes they were built to catch. Extending the same rigor to the exposure
gradient afterward — power analysis, four robustness checks, then a
direct test of the candidate confounding mechanism — reinforced it from
another angle: a fragile result isn't evidence of "no effect," and
proposing a mechanism isn't the same as confirming one.

## Data

### Sources

| Source | Role |
|---|---|
| FRED (public API) | State-quarter employment, GDP, population, 2015-2022 |
| U.S. DOL minimum wage history | Treatment classification |
| QCEW Open Data API | Fallback employment (2 states); validation check |
| CPS-ORG via IPUMS-CPS | Exposure construction (2019-2020 earnings only) |
| FRED CES average hourly earnings (supersector) | Wage pass-through analysis (`R/29`) |

### Variables

| Variable | Source | Frequency | Transformation | Role in identification |
|---|---|---|---|---|
| `log_employment` (food service / retail) | FRED CES; QCEW fallback for 2 states | Monthly → quarterly mean | Natural log | Outcome |
| `treated_post` | U.S. DOL minimum wage history | Static per state × time-invariant cutoff | Binary (treated × post-2021Q1) | Treatment indicator (Model A/C) |
| `exposure` (12.5% band) | CPS-ORG via IPUMS-CPS, 2019-2020 pooled | Static per state-industry | Weighted share of workers within band of pre-2021 minimum wage | Moderator — the exposure-gradient hypothesis itself (Model C) |
| `gdp_growth` | FRED (state GDP) | Quarterly | Year-over-year log growth | Control |
| `pop_growth` | FRED (state population) | Annual, repeated across quarters | Year-over-year log growth | Control |
| `region` | Census Bureau region classification | Static | Categorical (4 levels) | Heterogeneity / robustness (ANOVA, chi-square) |
| `covid_severity` | Derived from FRED employment (own construction) | Static per state | log(2020 Q2 employment) − log(2019 Q4 employment) | COVID-sensitivity covariate (Section 4.3) |
| `wage_food_service_proxy`, `wage_retail_proxy` | FRED CES average hourly earnings, supersector | Monthly → quarterly mean | Natural log | Outcome, wage pass-through (`R/29`) only |

## How to Reproduce

```
Rscript -e 'renv::restore()'   # pinned package versions (renv.lock, R 4.5.1)
make all                       # R/01-R/31, tests, figures, report end to end
make test                      # just the R test suite
make report                    # just render reports/final_report.Rmd (HTML)
make report-pdf                # + reports/final_report.pdf (headless Chrome)

make python-setup               # one-time: creates python/.venv, installs the minwage package
make python-test                # Python ML/NN test suite (python/)
```

`make all` needs `IPUMS_API_KEY` in `.env` (see `.env.example`) for
`R/03`, and takes several minutes (CPS-ORG pull, wild bootstrap,
permutation test, power simulation are the slow steps). Rendering the
HTML report needs [pandoc](https://pandoc.org), separate from
`renv.lock`; `make report-pdf` additionally needs Chrome/Chromium
installed locally (no LaTeX distribution required).
`make python-test` needs `make python-setup` to have been run once
first; see [python/README.md](python/README.md) for why it's a
separate virtual environment rather than a renv-tracked dependency.

Repo layout: `R/` (31 numbered scripts, run in order), `tests/` (one
file per script), `reports/` (`final_report.Rmd`, rendered HTML and PDF,
figures), `data/processed/` (all results, gitignored, reproducible),
`python/` (independent ML/NN replication — see
[python/README.md](python/README.md)). CI (`.github/workflows/ci.yml`)
parse-checks `R/`, verifies every script is wired into the Makefile and
has a matching test file (`scripts/check_pipeline_sync.R` — also
runnable locally as `make check-sync`), and runs both the R and Python
test suites, on every push.

## Roadmap

Not yet done, in rough priority order:

- **A heterogeneity-robust DiD comparison.** Model A has a single common
  treatment date, so the staggered-timing critique (Goodman-Bacon 2021;
  de Chaisemartin and D'Haultfœuille 2020) doesn't mechanically bind it —
  but Model C's continuous exposure treatment is a more natural fit for
  the newer continuous/dose-treatment DiD literature than for
  Callaway-Sant'Anna (2021) or Sun-Abraham (2021) specifically, which
  target staggered *binary* adoption. Planned: fit whichever estimator
  actually matches Model C's design, report it alongside TWFE and the
  wild-cluster-bootstrap inference already in place, and let
  disagreement (if any) be informative rather than resolved by picking
  a side.
- **A reproducibility summary table** (R version, Python version, exact
  data source vintages, seed policy, test counts, expected runtime per
  `make` target) — most of this is scattered across the README already;
  consolidating it into one table is the remaining work.
- **A Zenodo-archived release** once the above are in, for a citable DOI.

## Status

Complete. The original 10-day build covered treatment classification through the final report;
11 new scripts (`R/16`-`R/26`) and 4 extended ones (`R/08`, `R/10`,
`R/11`, `R/15`) were added afterward for the power analyses, robustness
checks, and mechanism investigation summarized above; `R/27`-`R/28` and
`python/` add the ML/neural-network predictive comparison described
above, `R/29` adds the wage pass-through research question, and
`R/30`-`R/31` add the treatment-predictability and state-clustering
angles.

## License

[MIT](LICENSE) — the code. Underlying data remains subject to each
source's own terms (see [Data Sources](#data-sources) above); this
license covers the analysis code, not the data itself.
