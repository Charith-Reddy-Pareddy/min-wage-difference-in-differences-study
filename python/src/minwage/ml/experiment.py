"""Model-selection and uncertainty tooling shared across `minwage.ml`
estimators: grouped k-fold cross-validation, a grid search built on top
of it, a cluster bootstrap for confidence intervals on a held-out
metric, and permutation feature importance.

Every function here takes `groups` (state labels) alongside X/y and
respects them the same way `splitting.group_train_test_split` does --
a state's quarters never get split across train/validation, and the
bootstrap resamples whole states rather than individual rows, since
rows from the same state aren't independent observations.
"""

from __future__ import annotations

import itertools
from typing import Callable

import numpy as np
import pandas as pd

from minwage.ml.evaluation import r_squared, rmse


def group_k_fold(groups: np.ndarray, n_splits: int = 5, seed: int = 0):
    """Yield (train_idx, test_idx) row-index arrays for `n_splits` folds,
    splitting on unique groups (states) rather than rows -- every row for
    a given state lands in exactly one fold's test set."""
    groups = np.asarray(groups)
    unique_groups = np.sort(pd.unique(groups))
    rng = np.random.default_rng(seed)
    shuffled = rng.permutation(unique_groups)
    fold_groups = np.array_split(shuffled, n_splits)

    for test_groups in fold_groups:
        test_mask = np.isin(groups, test_groups)
        yield np.where(~test_mask)[0], np.where(test_mask)[0]


def cross_validate(
    model_fn: Callable[[], object], X: np.ndarray, y: np.ndarray, groups: np.ndarray,
    n_splits: int = 5, seed: int = 0,
) -> dict:
    """Fit a fresh model per fold via `model_fn()` and score it on that
    fold's held-out states. Returns per-fold scores plus their mean/std."""
    X = np.asarray(X, dtype=float)
    y = np.asarray(y, dtype=float)

    rmse_folds = []
    r_squared_folds = []
    for train_idx, test_idx in group_k_fold(groups, n_splits=n_splits, seed=seed):
        model = model_fn()
        model.fit(X[train_idx], y[train_idx])
        pred = model.predict(X[test_idx])
        rmse_folds.append(rmse(y[test_idx], pred))
        r_squared_folds.append(r_squared(y[test_idx], pred))

    return {
        "rmse_mean": float(np.mean(rmse_folds)),
        "rmse_std": float(np.std(rmse_folds)),
        "r_squared_mean": float(np.mean(r_squared_folds)),
        "r_squared_std": float(np.std(r_squared_folds)),
        "rmse_folds": rmse_folds,
        "r_squared_folds": r_squared_folds,
    }


def grid_search_cv(
    model_cls: type, param_grid: dict, X: np.ndarray, y: np.ndarray, groups: np.ndarray,
    n_splits: int = 5, seed: int = 0,
) -> tuple[dict, pd.DataFrame]:
    """Try every combination of `param_grid` (dict of param name -> list
    of values), score each with `cross_validate`, and return the
    lowest-mean-RMSE combination plus the full results table."""
    keys = list(param_grid.keys())
    rows = []
    for combo in itertools.product(*param_grid.values()):
        params = dict(zip(keys, combo))

        def model_fn(params=params):
            return model_cls(**params)

        cv_result = cross_validate(model_fn, X, y, groups, n_splits=n_splits, seed=seed)
        rows.append({**params, "rmse_mean": cv_result["rmse_mean"], "rmse_std": cv_result["rmse_std"]})

    results = pd.DataFrame(rows)
    best_row = results.loc[results["rmse_mean"].idxmin()]
    best_params = {k: best_row[k] for k in keys}
    return best_params, results


def bootstrap_metric_ci(
    actual: np.ndarray, predicted: np.ndarray, groups: np.ndarray,
    metric_fn: Callable[[np.ndarray, np.ndarray], float] = rmse,
    n_boot: int = 1000, seed: int = 0, alpha: float = 0.05,
) -> dict:
    """Cluster-bootstrap confidence interval for a fixed model's
    held-out metric: resample whole states with replacement (not rows),
    since a state's quarters aren't independent observations, and
    recompute the metric on each resample. No refitting -- this is a
    CI on the test-set metric itself, not on model performance under
    resampled training data."""
    actual = np.asarray(actual, dtype=float)
    predicted = np.asarray(predicted, dtype=float)
    groups = np.asarray(groups)
    unique_groups = np.sort(pd.unique(groups))
    rng = np.random.default_rng(seed)

    boot_stats = []
    for _ in range(n_boot):
        sampled_groups = rng.choice(unique_groups, size=len(unique_groups), replace=True)
        idx = np.concatenate([np.where(groups == g)[0] for g in sampled_groups])
        boot_stats.append(metric_fn(actual[idx], predicted[idx]))

    boot_stats = np.array(boot_stats)
    return {
        "point_estimate": float(metric_fn(actual, predicted)),
        "lower": float(np.percentile(boot_stats, 100 * alpha / 2)),
        "upper": float(np.percentile(boot_stats, 100 * (1 - alpha / 2))),
        "boot_stats": boot_stats.tolist(),
    }


def permutation_importance(
    model, X: np.ndarray, y: np.ndarray, feature_names: list[str], n_repeats: int = 20, seed: int = 0,
) -> pd.DataFrame:
    """For each feature, shuffle its column `n_repeats` times and measure
    how much RMSE increases relative to the unpermuted baseline -- a
    feature the model actually relies on should get much worse
    predictions once its values are decoupled from the target; a feature
    it ignores shouldn't move the score at all."""
    X = np.asarray(X, dtype=float)
    y = np.asarray(y, dtype=float)
    baseline_rmse = rmse(y, model.predict(X))
    rng = np.random.default_rng(seed)

    rows = []
    for j, name in enumerate(feature_names):
        increases = []
        for _ in range(n_repeats):
            X_permuted = X.copy()
            X_permuted[:, j] = rng.permutation(X_permuted[:, j])
            increases.append(rmse(y, model.predict(X_permuted)) - baseline_rmse)
        rows.append({
            "feature": name,
            "importance_mean": float(np.mean(increases)),
            "importance_std": float(np.std(increases)),
        })

    return pd.DataFrame(rows).sort_values("importance_mean", ascending=False).reset_index(drop=True)
