# State Minimum Wage Increases and Low-Wage Employment

A difference-in-differences study of the 2021 round of state minimum-wage
increases, extended beyond a single average treatment effect to ask how
the employment response varies with pre-policy wage exposure.

**Finding:** the baseline DiD estimate is negative but not credible as a
causal estimate — pre-trends are violated for food service, and the
estimate is highly sensitive to differential COVID recovery. The
exposure-gradient hypothesis is underpowered *and*, per four independent
checks, confounded by a pre-existing association between exposure and
employment trends unrelated to the 2021 policy. See
[Results at a Glance](#results-at-a-glance).

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

This builds on a standard Card-Krueger-style state minimum-wage DiD
design. The contribution isn't a new question but a specific empirical
angle: moving from one average treatment effect to modeling how that
effect scales with exposure — and then stress-testing that model with
every credibility check the data will support.

## 30-Second Version

| | |
|---|---|
| **Data** | 50 states, quarterly 2015-2022 — FRED/QCEW employment + CPS-ORG (IPUMS) exposure |
| **Method** | Two-way fixed-effects DiD, event study, placebo test, state-clustered and wild-bootstrap inference, permutation test, Monte Carlo power analysis |
| **Baseline estimate** | Small negative average effect, significant only in the ≥$0.50-increase subsample |
| **Main finding** | Not robust: pre-trends fail for food service, and a COVID-recovery confound explains a real share of it |
| **Main limitation** | The exposure gradient (β₄) is underpowered *and* confounded — 4 independent checks find high/low-exposure states already differed pre-2021 |

Jump to the [full report](reports/final_report.Rmd) or
[Limitations](#limitations).

## Results at a Glance

| Question | Result | Interpretation |
|---|---|---|
| Average employment effect | Negative but not robust | Weak causal evidence |
| Parallel trends | Violated (food service) | Major identification concern |
| COVID sensitivity | Large change once controlled for | Confounding likely |
| Exposure gradient (β₄) | Inconclusive and confounded | Underpowered, not "no effect" |
| Exposure bandwidth (10%/12.5%/15%) | Consistent across all three | Not an artifact of band choice |
| Placebo test (β₃, average effect) | Null | Helpful credibility check |
| Placebo test (β₄, exposure gradient) | Significant at the fake date | Threatens the exposure gradient specifically |
| Permutation test (β₄) | Null isn't centered at zero for food service | Second independent sign of a pre-existing association |
| Event study (β₄) | Pre-trend joint test rejects for both industries | Third independent sign, visible quarter by quarter |
| Specification curve (12 specs) | Only 2 of 12 significant; sign flips by industry | Fourth independent sign of fragility |
| Exposure vs. COVID severity | Significant negative correlation, both industries | A candidate mechanism for the confound |
| Controlling for COVID severity | Placebo effect barely moves | Real factor, but not the full explanation |
| Multiple-testing correction | None of the 4 confirmatory tests survive Holm | Consistent with "not robust," now formal |
| Leave-one-state-out | Estimate stable across all 20 drops | No single state drives Model A |
| Treatment-intensity (exploratory) | Directionally consistent | Not confirmatory — increase size isn't randomly assigned |

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

More figures — model diagnostics, permutation-test null distributions,
power-analysis curves, exposure-bandwidth sensitivity, the exposure/COVID
correlation — are in `reports/figures/` and embedded in the
[full report](reports/final_report.Rmd).

## Final Report

**[Read the rendered report](https://github.com/Charith-Reddy-Pareddy/min-wage-difference-in-differences-study/releases/tag/v1.0-report)**
— no cloning required.

[reports/final_report.Rmd](reports/final_report.Rmd) is the complete
write-up. It reads pre-computed results from `data/processed/` and
figures from `reports/figures/`, so render it directly:

```
Rscript -e 'rmarkdown::render("reports/final_report.Rmd")'
```

(needs [pandoc](https://pandoc.org) — `brew install pandoc` on macOS).
Regenerating those inputs from scratch is the
[How to Reproduce](#how-to-reproduce) section below.

## Limitations

- **Parallel trends are violated** for food service, confirmed by both
  the event study's joint pre-trend test and an independent two-sample
  t-test.
- **COVID-era differential recovery confounds the treatment window**: a
  real share of the baseline estimate is attributable to differential
  COVID recovery across states, not minimum-wage policy.
- **Both β₃ and β₄ are underpowered** at the effect sizes actually
  observed — quantified by a Monte Carlo power simulation
  (`R/16_power_analysis.R`), not just assumed. β₃'s minimum detectable
  effect isn't reached anywhere in the proposal's own 0.5%–3% assumed
  range, which is why Model A is only significant in the ≥$0.50
  subsample.
- **The exposure gradient (β₄) is also confounded**, not just
  underpowered — four independent checks (placebo test, permutation
  test, event study, specification curve) all find that high- and
  low-exposure states already differed on employment trends before 2021.
  A candidate mechanism (exposure correlates with COVID severity,
  `R/25_exposure_covid_correlation.R`) was tested directly by controlling
  for it in the placebo specification (`R/26_covid_controlled_placebo.R`)
  — the spurious effect barely shrank, so COVID severity is a real,
  correlated factor but not the full explanation. See Section 8.1 of the
  [full report](reports/final_report.Rmd) for the consolidated evidence.
- **The ≥$0.50-increase subsample and the legislated-only subsample are
  the exact same 10 states** — the dollar-threshold cut and the
  legislated-vs-automatic mechanism cut can't be disentangled in this
  data.
- **A relatively small number of clusters** (20 treated states, 45
  total) — addressed via state-clustered SEs and a wild cluster
  bootstrap for both β₃ and β₄, but inference this few clusters always
  carries some caution.
- **Exposure-measure construction is a documented choice**, not the only
  defensible one (band width, cell-pooling rules) — tested for
  sensitivity across three bandwidths with consistent results.
- **Spillovers, anticipation effects, and external validity** (this
  window is COVID-era by construction) are not modeled or corrected for.
- **The permutation test is a reference distribution, not evidence of a
  randomized experiment** — states chose whether and when to raise
  wages.
- Results should be read as **DiD estimates under this specification**,
  not as definitive causal effects — see the full report's Limitations
  section for complete detail.

## What I Learned

A statistically significant DiD estimate isn't sufficient evidence of a
causal effect on its own. The event study revealed a parallel-trends
violation, and the COVID-sensitivity spec showed that differential
recovery across states explained a substantial share of the baseline
estimate — exactly the failure modes the design's credibility checks
were built to catch. Extending the same rigor to the exposure gradient
after the original build — a power analysis, then four independent
robustness checks, then a direct test of the candidate confounding
mechanism — reinforced the same lesson from a different angle: a noisy
or fragile result isn't itself evidence of "no effect," and proposing a
mechanism isn't the same as confirming one. I treat the causal
interpretation here as limited throughout, not the coefficients as
definitive.

## Data Sources

| Source | Role |
|---|---|
| FRED (public API) | State-quarter employment (food service, retail), GDP, population, 2015-2022 |
| U.S. DOL minimum wage history (Wayback Machine snapshots) | Treatment classification |
| QCEW Open Data API | Fallback employment series for 2 states FRED doesn't publish; wage-ratio validation check |
| CPS-ORG via IPUMS-CPS | Exposure measure construction (2019-2020 earnings only) |

## Analysis Pipeline

<img src="reports/figures/pipeline_diagram.png" width="60%">

26 scripts run in order, each reading the previous ones' output from
`data/processed/` and writing its own back. See
[How to Reproduce](#how-to-reproduce) for the exact commands.

## Repo Layout

```
data/raw/        source pulls, not committed (see .gitignore)
data/processed/  cleaned panel data + all analysis results, not committed
R/               numbered scripts, 01 through 26, run in order
scripts/         presentation-only figure generation (not part of the analysis pipeline)
reports/         final_report.Rmd, rendered HTML, and all figures
tests/           unit tests, one file per R/ script
.github/workflows/ CI: parse-checks R/ and runs the test suite on every push
renv.lock        pinned package versions (see Environment below)
```

## Environment

Package versions are pinned via [renv](https://rstudio.github.io/renv/)
in `renv.lock` (R 4.5.1):

```
Rscript -e 'renv::restore()'
```

Key packages: `fixest`, `dplyr`, `readr`, `sandwich`, `testthat`,
`rmarkdown`, `knitr`, `ggplot2`. Rendering the report additionally needs
[pandoc](https://pandoc.org) (`brew install pandoc` on macOS), which
isn't an R package and isn't in `renv.lock`.

## How to Reproduce

**One command**, from the repo root, after `renv::restore()`:

```
make all      # runs R/01 through R/26, the test suite, the summary figures, then the report
make test     # just the test suite
make figures  # just the README's summary figures (scripts/generate_readme_figures.R)
make report   # just renders reports/final_report.Rmd against existing data/processed/
```

`make all` needs `IPUMS_API_KEY` set in `.env` (see `.env.example`) for
`R/03`, and takes several minutes end to end — the CPS-ORG pull, the
wild cluster bootstrap, the permutation test, and the power simulation
are each the slowest part of their respective scripts.

Equivalently, run the numbered scripts in `R/` directly in order from
the repo root (each reads the previous scripts' outputs from
`data/processed/`, so order matters). See the `Rscript R/NN_*.R` list in
`Makefile`'s `PIPELINE` variable for the exact sequence and per-script
notes.

Then `testthat::test_dir("tests")` should show every test passing, and
`reports/final_report.Rmd` should render cleanly against the outputs
those scripts just produced. CI (`.github/workflows/ci.yml`) runs the
parse-check and test suite on every push — it doesn't run the full
pipeline or render the report, since those need live API credentials and
several minutes.

## Status

Complete. See [TIMELINE.md](TIMELINE.md) for the day-by-day build log,
including every defect found and corrected along the way — a missing
control group, a treatment-date error traced to a skipped statutory
adjustment, and a stale duplicated lookup table that only broke once a
later script's data grew past what it was written for, among others.

The original 10-day build covered treatment classification through the
final written report (Sections 2–15 of the project proposal). Afterward:
11 new scripts (`R/16`–`R/26`) added the β₃ and β₄ power analyses the
proposal specified but the compressed build never got to, an
exposure-bandwidth sensitivity check, a marginal-effects curve, an
exploratory treatment-intensity model, a leave-one-state-out check, a
coefficient forest plot, a Holm multiple-testing correction, a
12-specification robustness curve, a consolidated summary of four checks
that all flag the exposure gradient as fragile, and a mechanism
investigation (does exposure predict COVID severity, and does
controlling for it explain the fragility away — it doesn't, fully). Four
existing scripts (`R/08`, `R/10`, `R/11`, `R/15`) were also extended so
the event study, placebo test, wild cluster bootstrap, and permutation
test each cover both β₃ and β₄, wherever only one had been checked
before.
