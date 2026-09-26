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
.venv/bin/pip install -e ".[dev]"
```

(`-e` is an editable install — code changes under `src/minwage/` take
effect immediately, no reinstall needed. `[dev]` pulls in `pytest`.)

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

**What this is:** a check on whether Model A's linear-in-controls
functional form (`R/07_model_a_c.R`) matters, run on the same
`employment_growth` target and control set `train.py` already uses.
**What this isn't:** a second, independent identification strategy.
Both the linear and ML-nuisance versions still require no unobserved
confounder of treatment and outcome given the controls -- exactly
Model A's parallel-trends assumption, not something double ML relaxes.
`causal_estimate.py`'s module docstring spells out why its point
estimate isn't numerically comparable to Model A's coefficient (different
target, different control set -- region dummies here, full state and
quarter fixed effects there).

`causal_ml/heterogeneity.py` adds an R-learner (Nie & Wager, 2017) on
top of the DML residuals: instead of one effect for every row, it
regresses the pseudo-outcome `y_resid/d_resid` on exposure (weighted
by `d_resid**2`) to get a slope for how the effect varies with
exposure specifically -- the same question Model C's
`treated_post*exposure` interaction asks, without assuming that
interaction is linear in TWFE's sense. No separate cross-fitting pass;
it reuses the residuals `partialling_out_dml` already computed.

## Tests

```
.venv/bin/python -m pytest
```

## Layout

```
python/
├── pyproject.toml          # package metadata, dependencies, pytest config
├── src/minwage/
│   ├── config.py           # shared constants (panel path, column names)
│   ├── data/
│   │   └── loaders.py      # reads the shared panel CSV, one-hot encodes region
│   └── ml/
│       ├── splitting.py    # grouped (by-state) train/test split
│       ├── baselines.py    # OLS via the normal equations
│       ├── random_forest.py    # regression tree + bagging + random forest, from scratch
│       ├── gradient_boosting.py # sequential residual-fitting ensemble, from scratch
│       ├── neural_network.py    # PyTorch feedforward net, train-only standardization
│       ├── evaluation.py   # RMSE / R², matching R/27's definitions exactly
│       └── experiment.py   # grouped CV, grid search, bootstrap CI, permutation importance
│   └── causal_ml/
│       └── dml.py          # cross-fitted double ML for the partially linear treatment model
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
`causal_ml/` and a small FastAPI results service (`api/`) don't exist
yet -- planned extensions, not scaffolding for their own sake.
