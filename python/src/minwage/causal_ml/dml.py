"""Double/debiased machine learning (Chernozhukov et al., 2018) for the
partially linear model

    Y = theta * D + g(X) + U
    D = m(X) + V

The nuisance functions g and m can use any estimator exposing fit/predict.
Theta is recovered by regressing residualized Y on residualized D.
A causal interpretation requires conditional unconfoundedness and suitable
nuisance estimation rates and treatment variation. This is not equivalent
to DiD parallel trends or a reproduction of the TWFE specification.

Cross-fitting (Y and D are each predicted out-of-fold, never using a
row's own fold to predict that row) is required so that overfitting in
g_hat/m_hat doesn't bias theta_hat toward zero -- a flexible enough
model can otherwise fit part of U or V and steal it into the residual.
Folds are grouped by state (minwage.ml.experiment.group_k_fold), same
as the rest of this package's cross-validation, so a state's quarters
are never split between the fold a nuisance model trains on and the
fold its prediction is evaluated on.
"""

from __future__ import annotations

from collections.abc import Callable

import numpy as np
import pandas as pd

from minwage.ml.experiment import group_k_fold
from minwage.ml.protocols import Estimator


def _cross_fitted_residuals(
    X: np.ndarray,
    target: np.ndarray,
    groups: np.ndarray,
    model_factory: Callable[[], Estimator],
    n_folds: int = 5,
    seed: int = 0,
) -> tuple[np.ndarray, np.ndarray]:
    """Out-of-fold predictions for `target` from `X`, and the resulting
    residuals, using a fresh model per fold so no row is ever predicted
    by a model that saw it (or its state) during fitting."""
    X = np.asarray(X, dtype=float)
    target = np.asarray(target, dtype=float)
    fitted = np.empty(len(target))

    for train_idx, test_idx in group_k_fold(groups, n_splits=n_folds, seed=seed):
        model = model_factory()
        model.fit(X[train_idx], target[train_idx])
        fitted[test_idx] = model.predict(X[test_idx])

    return target - fitted, fitted


def partialling_out_dml(
    X: np.ndarray,
    Y: np.ndarray,
    D: np.ndarray,
    groups: np.ndarray,
    y_model_factory: Callable[[], Estimator],
    d_model_factory: Callable[[], Estimator],
    n_folds: int = 5,
    seed: int = 0,
) -> dict:
    """Estimate theta in Y = theta*D + g(X) + U by cross-fitted
    partialling-out. `y_model_factory`/`d_model_factory` are zero-arg
    callables returning a fresh, unfit model for Y~X and D~X
    respectively (they can be the same estimator or different ones --
    Y and D need not be equally hard to predict from X).

    Returns a state-clustered sandwich SE with G/(G-1) correction and
    normal-approximation 95% CI. Clusters must be independent; inference
    is asymptotic in the number of clusters. `se_row` retains the old
    uncorrected row-independent SE for comparison only. `groups` defines
    both cross-fitting folds and variance clusters.
    """
    X = np.asarray(X, dtype=float)
    Y = np.asarray(Y, dtype=float)
    D = np.asarray(D, dtype=float)
    groups = np.asarray(groups)
    if Y.ndim != 1 or D.shape != Y.shape or groups.shape != Y.shape or X.ndim != 2 or len(X) != len(Y):
        raise ValueError("X, Y, D and groups must have aligned rows; Y, D and groups must be one-dimensional")
    if not all(np.isfinite(v).all() for v in (X, Y, D)) or pd.isna(groups).any():
        raise ValueError("Inputs must be finite and groups must not be missing")
    labels, cluster_ids = np.unique(groups, return_inverse=True)
    n_clusters = len(labels)
    if not isinstance(n_folds, int) or not 2 <= n_folds <= n_clusters:
        raise ValueError("n_folds must be between 2 and the number of clusters")
    n = len(Y)

    y_resid, y_fitted = _cross_fitted_residuals(X, Y, groups, y_model_factory, n_folds, seed)
    d_resid, d_fitted = _cross_fitted_residuals(X, D, groups, d_model_factory, n_folds, seed)

    denominator = float(np.sum(d_resid**2))
    if not np.isfinite(denominator) or denominator <= 0:
        raise ValueError("Residualized treatment must have positive finite variation")
    theta_hat = float(np.sum(d_resid * y_resid) / denominator)
    psi = (y_resid - theta_hat * d_resid) * d_resid
    if not np.isfinite(psi).all():
        raise ValueError("Nuisance predictions must produce finite scores")
    # Sum scores within each state before squaring to retain within-state covariance.
    cluster_scores = np.bincount(cluster_ids, weights=psi, minlength=n_clusters)
    se = float(np.sqrt(n_clusters / (n_clusters - 1) * np.sum(cluster_scores**2)) / denominator)
    se_row = float(np.sqrt(np.sum(psi**2)) / denominator)

    return {
        "theta": theta_hat,
        "se": se,
        "se_row": se_row,
        "n_clusters": n_clusters,
        "ci_lower": theta_hat - 1.96 * se,
        "ci_upper": theta_hat + 1.96 * se,
        "n": n,
        "y_resid": y_resid,
        "d_resid": d_resid,
        "y_fitted": y_fitted,
        "d_fitted": d_fitted,
    }
