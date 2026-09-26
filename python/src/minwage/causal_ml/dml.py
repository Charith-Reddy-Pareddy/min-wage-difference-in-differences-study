"""Double/debiased machine learning (Chernozhukov et al., 2018) for the
partially linear model

    Y = theta * D + g(X) + U
    D = m(X) + V

instead of assuming g and m are linear -- TWFE's implicit functional-
form assumption in R/07_model_a_c.R's Model A -- g and m are each fit
with any ML estimator that exposes .fit()/.predict() (this project's
hand-rolled RandomForest or GradientBoostedTrees, or LinearRegression
as a sanity check). theta is recovered from the residualized
regression: partial X's predictable part out of both Y and D, then
regress what's left of Y on what's left of D.

theta has the same interpretation as Model A's DiD coefficient -- this
is a functional-form robustness check on that estimate, not a
different identification strategy. It still requires no unobserved
confounder of treatment and outcome given X, the same assumption
Model A's parallel-trends argument makes; ML nuisance functions relax
how g and m are allowed to look, not what has to be true about U and V.

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

from typing import Callable

import numpy as np

from minwage.ml.experiment import group_k_fold


def _cross_fitted_residuals(
    X: np.ndarray, target: np.ndarray, groups: np.ndarray,
    model_factory: Callable[[], object], n_folds: int = 5, seed: int = 0,
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
    X: np.ndarray, Y: np.ndarray, D: np.ndarray, groups: np.ndarray,
    y_model_factory: Callable[[], object], d_model_factory: Callable[[], object],
    n_folds: int = 5, seed: int = 0,
) -> dict:
    """Estimate theta in Y = theta*D + g(X) + U by cross-fitted
    partialling-out. `y_model_factory`/`d_model_factory` are zero-arg
    callables returning a fresh, unfit model for Y~X and D~X
    respectively (they can be the same estimator or different ones --
    Y and D need not be equally hard to predict from X).

    Returns theta_hat, its asymptotic standard error and a 95% CI
    (Chernozhukov et al. 2018's Neyman-orthogonal score, which is what
    makes the CI valid despite theta_hat being built from ML first-stage
    predictions), plus both sets of residuals for diagnostics."""
    Y = np.asarray(Y, dtype=float)
    D = np.asarray(D, dtype=float)
    n = len(Y)

    y_resid, y_fitted = _cross_fitted_residuals(X, Y, groups, y_model_factory, n_folds, seed)
    d_resid, d_fitted = _cross_fitted_residuals(X, D, groups, d_model_factory, n_folds, seed)

    theta_hat = float(np.sum(d_resid * y_resid) / np.sum(d_resid**2))

    # Chernozhukov et al. (2018), eq. 4.1: the sandwich variance of the
    # Neyman-orthogonal moment psi(theta) = (Y_resid - theta*D_resid) * D_resid.
    psi = (y_resid - theta_hat * d_resid) * d_resid
    j0 = np.mean(d_resid**2)
    se = float(np.sqrt(np.mean(psi**2) / j0**2 / n))

    return {
        "theta": theta_hat,
        "se": se,
        "ci_lower": theta_hat - 1.96 * se,
        "ci_upper": theta_hat + 1.96 * se,
        "n": n,
        "y_resid": y_resid,
        "d_resid": d_resid,
        "y_fitted": y_fitted,
        "d_fitted": d_fitted,
    }
