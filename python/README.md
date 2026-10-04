# ML/NN extension (Python)

An independent, Python-side replication of the predictive comparison in
[`R/27_ml_prediction.R`](../R/27_ml_prediction.R) and
[`R/28_neural_network.R`](../R/28_neural_network.R): a linear baseline,
a bagged-trees ensemble, a random forest, gradient boosting, and a
feedforward neural network, all predicting `employment_growth` on
states held out entirely from training (see those two files' headers
for why the split is by state and why the target is growth, not
employment level).

`minwage.ml` has `random_forest.BaggedTrees`, `random_forest.RandomForest`,
and `gradient_boosting.GradientBoostedTrees` as three genuinely different
combination strategies, not the same ensemble under different names:
`BaggedTrees` picks one random feature subset per tree (the "random
subspace" method); `RandomForest` re-picks a fresh random subset at
*every* split node in every tree (the actual Breiman algorithm); and
`GradientBoostedTrees` doesn't bootstrap-resample at all — it fits
trees sequentially, each one to the current residuals of the trees
before it. See `random_forest.py`'s module docstring for the full
distinction.

**`train.py`'s comparison above is predictive-accuracy only, not a
causal claim.** The study's actual identification strategy is Model
A/C in `R/07`, with the robustness checks in `R/08`-`R/26`.
`causal_ml/` (below) is the one place on the Python side that does
make a causal estimate, and it says exactly what that estimate does
and doesn't establish.

## Why numpy/pandas/torch only, no scikit-learn

This environment's prebuilt `scipy` wheel (a hard dependency of
scikit-learn) fails to load on this machine — a Mach-O loader error
un­related to this project's code, reproducible with a bare
`python -c "import scipy"` in a fresh virtualenv. Rather than depend on
a library that doesn't import here, the classical models
(`ml/baselines.py`, `ml/random_forest.py`, `ml/gradient_boosting.py`)
are implemented directly on numpy: closed-form OLS via
`numpy.linalg.lstsq`, and a CART-style regression tree with hand-rolled
bagging, random-forest, and gradient-boosting ensembles on top of it.
If scikit-learn works in your environment, swapping in
`sklearn.ensemble.RandomForestRegressor` or `GradientBoostingRegressor`
for `RandomForest` / `GradientBoostedTrees` is a drop-in replacement —
the splitting/evaluation/data modules don't care which one produced the
predictions.

PyTorch (`ml/neural_network.py`) has no such issue and installs/imports
cleanly.

## Setup

`minwage` is a proper installable package (`pyproject.toml`, `src/`
layout), not a flat script collection:

```
python3 -m venv .venv
.venv/bin/pip install -e ".[dev,api]"
```

(`-e` is an editable install — code changes under `src/minwage/` take
effect immediately, no reinstall needed. `[dev]` pulls in
pytest/ruff/mypy/coverage; `[api]` pulls in FastAPI/uvicorn. `[api]`
is only needed to run the results service below, but `[dev]`'s test
suite exercises it, so CI installs both.)

## Run the comparison

Needs `data/processed/ml_panel.csv`, written by `R/27_ml_prediction.R`
(run `Rscript ../R/27_ml_prediction.R` from the repo root first, or
`make pipeline`).

```
.venv/bin/python train.py
```

Writes `results/comparison.csv` (gitignored, like the R side's
`data/processed/`), plus three more files describing the random
forest specifically: `random_forest_grid_search.csv` (every
max_depth/min_samples_leaf combination tried and its grouped-CV RMSE),
`random_forest_bootstrap_ci.csv` (a 95% cluster bootstrap interval,
resampled by state, for test RMSE and R²), and
`random_forest_permutation_importance.csv` (RMSE increase when each
feature is independently shuffled on the test set).

## Model selection and uncertainty

`minwage.ml.experiment` is the model-selection layer every estimator in
`minwage.ml` can use, not something specific to the random forest:

- `group_k_fold` / `cross_validate` — k-fold CV that splits on states,
  not rows, so no state's quarters leak across a fold boundary.
- `grid_search_cv` — tries every combination in a hyperparameter grid
  under grouped CV and returns the lowest-mean-RMSE combination.
- `bootstrap_metric_ci` — a cluster bootstrap (resampling whole states,
  with replacement) for a confidence interval on a fixed model's
  held-out RMSE or R², rather than reporting a single number as if it
  had no sampling variability.
- `permutation_importance` — shuffles one feature at a time and reports
  how much worse predictions get, as a model-agnostic measure of which
  features the fitted model actually relies on.

`train.py` currently applies all four to the random forest only (the
one estimator whose depth/leaf-size are worth tuning); the other
models keep the fixed hyperparameters chosen in earlier work.

## Causal ML: double ML as a functional-form robustness check

```
.venv/bin/python causal_estimate.py
```

`causal_ml/dml.py` implements cross-fitted double/debiased ML
(Chernozhukov et al., 2018) for the partially linear model
`Y = theta*D + g(X) + U`, `D = m(X) + V`: `g` and `m` are fit with any
ML estimator instead of assumed linear, then `theta` -- the effect of
`D` (`treated_post`) on `Y` (`employment_growth`) -- is recovered from
the residualized regression, cross-fitted by state so no fold's
nuisance model ever sees the rows it predicts.

This compares linear and forest nuisance models on the Python panel. A causal
interpretation requires conditional unconfoundedness, which differs from
DiD parallel trends. The outcome is employment growth with region controls;
Model A uses log employment with state and quarter fixed effects. Their
coefficients are not directly comparable.

Standard errors aggregate the orthogonal scores within states before
squaring: `SE = sqrt(G/(G-1) * sum_g(sum_i psi_i)^2) / sum_i d_resid_i^2`,
where `psi_i = d_resid_i * (y_resid_i - theta*d_resid_i)` and `G` is the
number of states. The same states define cross-fitting folds and variance
clusters. This follows the [cluster-robust DML approach](https://docs.doubleml.org/stable/examples/py_double_ml_multiway_cluster.html).
The output uses `se` for clustered uncertainty, `se_row` for the previous
row-independent calculation, and `n_clusters` for the state count.

Rerunning `.venv/bin/python causal_estimate.py` on the local processed panel
(seed 1, five folds, 2,520 rows, 45 states) gives:

| Nuisance model | Estimate | Row SE | State-clustered SE | Clustered 95% CI |
|---|---:|---:|---:|---:|
| Linear | 0.005812 | 0.006673 | 0.010740 | [-0.015239, 0.026863] |
| Random forest | -0.000771 | 0.008432 | 0.009478 | [-0.019347, 0.017806] |

Point estimates and nuisance fits are unchanged by the variance correction.
The clustered SE is about 61% larger for linear nuisances and 12% larger for
the forest. Both intervals include zero. Results are in employment-growth
units; a different data vintage can change them.

The 95% intervals use `theta +/- 1.96*se`: they are asymptotic in the number
of independent states, not exact small-sample intervals. Clustering allows
within-state dependence but does not address cross-state shocks, weak
residual treatment variation, poor nuisance estimation or unobserved
confounding. The R-learner output remains a descriptive linear exposure
slope without its own uncertainty estimate.

`causal_ml/heterogeneity.py` adds an R-learner (Nie & Wager, 2017) on
top of the DML residuals: instead of one effect for every row, it
regresses the pseudo-outcome `y_resid/d_resid` on exposure (weighted
by `d_resid**2`) to get a slope for how the effect varies with
exposure specifically, with a linear exposure slope. This uses a different
outcome and control set from Model C's `treated_post*exposure` interaction.
No separate cross-fitting pass;
it reuses the residuals `partialling_out_dml` already computed.

## Tests

```
.venv/bin/python -m pytest --cov=minwage --cov-report=term-missing
```

CI fails the build under 90% coverage (`[tool.coverage.report]` in
`pyproject.toml`); it's at ~99% currently.

## Lint, formatting, and type checking

```
.venv/bin/ruff check .
.venv/bin/ruff format .
.venv/bin/mypy
```

`ruff` covers both linting and formatting (no separate black
dependency); `mypy` runs with `disallow_untyped_defs`, and every
estimator in `minwage.ml`/`minwage.causal_ml` is typed against the
shared `ml.protocols.Estimator` protocol rather than a bare `object`,
so a model factory that doesn't actually implement `.fit()`/`.predict()`
is a type error, not a runtime surprise. All three run in CI
(`.github/workflows/ci.yml`) alongside the test suite and a package
build check (`python -m build`).

## Results API

```
.venv/bin/pip install -e ".[api]"
.venv/bin/uvicorn minwage.api.app:app --reload
```

A small read-only FastAPI service over whatever `train.py` and
`causal_estimate.py` have already written to `results/` -- it does not
train or refit anything itself, it just serves the CSVs as JSON:

| Endpoint | Source file |
|---|---|
| `GET /health` | -- |
| `GET /ml/comparison` | `comparison.csv` |
| `GET /ml/random-forest/grid-search` | `random_forest_grid_search.csv` |
| `GET /ml/random-forest/bootstrap-ci` | `random_forest_bootstrap_ci.csv` |
| `GET /ml/random-forest/permutation-importance` | `random_forest_permutation_importance.csv` |
| `GET /causal/dml` | `dml_estimate.csv` |
| `GET /causal/heterogeneity` | `dml_exposure_heterogeneity.csv` |

Each endpoint returns 404 (not a crash) if its source file doesn't
exist yet, since `results/` is gitignored and only populated after
running the script that writes it. There's deliberately no endpoint
that takes new covariates and returns a prediction -- this is a
results-serving layer for what's already been computed and reviewed,
not a live model a caller could feed arbitrary input and misread as
the study's causal estimate.

## Docker

From the `python/` directory:

```sh
docker build -t minwage -f Dockerfile .
docker run --rm --network none minwage
```

The image installs the package and runs its tests with synthetic fixtures.
It includes `causal_estimate.py` because an integration test imports that
script, but does not run the real-data analysis. Both analysis scripts need
`data/processed/ml_panel.csv` from the R pipeline, which is not included.
The build context is restricted to package metadata, source, tests and the
integration-test script; local environments and generated results are excluded.

**Verification status:** the image has not been built or run locally because
the Docker daemon is unavailable. The image's copied-file layout was checked
with the host Python environment, which reproduced and verified the fix for
a missing `causal_estimate.py`. That check does not validate the Linux base
image or dependency installation. CI now builds the image and runs the full
Python suite inside it with the 90% coverage gate; consult the `docker-tests`
job for the actual container result. Building requires network access to
fetch the base image and packages; the test container runs without networking.

## Layout

```
python/
├── pyproject.toml          # package metadata, dependencies, pytest/coverage/ruff/mypy config
├── Dockerfile              # runs the test suite in a clean environment
├── src/minwage/
│   ├── config.py           # shared constants (panel path, column names)
│   ├── data/
│   │   └── loaders.py      # reads the shared panel CSV, one-hot encodes region
│   └── ml/
│       ├── splitting.py    # grouped (by-state) train/test split
│       ├── baselines.py    # OLS via the normal equations
│       ├── protocols.py    # the Estimator protocol (fit/predict) every model here follows
│       ├── random_forest.py    # regression tree + bagging + random forest, from scratch
│       ├── gradient_boosting.py # sequential residual-fitting ensemble, from scratch
│       ├── neural_network.py    # PyTorch feedforward net, train-only standardization
│       ├── evaluation.py   # RMSE / R², matching R/27's definitions exactly
│       └── experiment.py   # grouped CV, grid search, bootstrap CI, permutation importance
│   ├── causal_ml/
│   │   ├── dml.py           # cross-fitted double ML for the partially linear treatment model
│   │   └── heterogeneity.py # R-learner treatment-effect heterogeneity on the DML residuals
│   └── api/
│       └── app.py          # read-only FastAPI service over results/
├── train.py                # ties minwage.ml together, prints and saves the comparison
├── causal_estimate.py      # runs double ML against the real panel
└── tests/                  # pytest, mirrors the src/minwage/ layout
```

There is no `data/fred.py` / `qcew.py` / `minimum_wage.py` for raw data
ingestion here, even though a `data/` subpackage might suggest there
should be — all raw acquisition (FRED, QCEW, CPS-ORG, DOL) happens in R
(`R/02`-`R/04`), which stays this project's single source of truth for
how the panel is built. See `loaders.py`'s module docstring.

A heterogeneous-treatment-effects estimator (causal forest) on top of
`causal_ml/` doesn't exist yet -- a planned extension, not scaffolding
for its own sake.
