# ML/NN extension (Python)

An independent, Python-side replication of the predictive comparison in
[`R/27_ml_prediction.R`](../R/27_ml_prediction.R) and
[`R/28_neural_network.R`](../R/28_neural_network.R): a linear baseline,
a bagged-trees ensemble, and a feedforward neural network, all
predicting `employment_growth` on states held out entirely from
training (see those two files' headers for why the split is by state
and why the target is growth, not employment level).

**This is a predictive-accuracy comparison, not a causal claim.** The
study's actual identification strategy is Model A/C in `R/07`, with the
robustness checks in `R/08`-`R/26`.

## Why numpy/pandas/torch only, no scikit-learn

This environment's prebuilt `scipy` wheel (a hard dependency of
scikit-learn) fails to load on this machine — a Mach-O loader error
un­related to this project's code, reproducible with a bare
`python -c "import scipy"` in a fresh virtualenv. Rather than depend on
a library that doesn't import here, the classical models
(`src/linear_model.py`, `src/tree.py`) are implemented directly on
numpy: closed-form OLS via `numpy.linalg.lstsq`, and a CART-style
regression tree with a hand-rolled bootstrap-aggregation ensemble. If
scikit-learn works in your environment, swapping in
`sklearn.ensemble.RandomForestRegressor` for `src/tree.BaggedTrees` is a
drop-in replacement — the split/metrics/data modules don't care which
one produced the predictions.

PyTorch (`src/neural_net.py`) has no such issue and installs/imports
cleanly.

## Setup

```
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Run the comparison

Needs `data/processed/ml_panel.csv`, written by `R/27_ml_prediction.R`
(run `Rscript ../R/27_ml_prediction.R` from the repo root first, or
`make pipeline`).

```
.venv/bin/python train.py
```

Writes `results/comparison.csv` (gitignored, like the R side's
`data/processed/`).

## Tests

```
.venv/bin/python -m pytest
```

## Layout

- `src/data.py` — reads the shared panel CSV, one-hot encodes region
- `src/split.py` — grouped (by-state) train/test split
- `src/linear_model.py` — OLS via the normal equations
- `src/tree.py` — regression tree + bagged-trees ensemble, from scratch
- `src/neural_net.py` — PyTorch feedforward net, train-only standardization
- `src/metrics.py` — RMSE / R², matching R/27's definitions exactly
- `train.py` — ties the above together, prints and saves the comparison
- `tests/` — pytest, one file per `src/` module
