"""R-learner treatment-effect heterogeneity (Nie & Wager, 2017), built
directly on the residuals `partialling_out_dml` already computes --
no separate cross-fitting pass needed.

Once Y and D are residualized against X (`y_resid`, `d_resid`), the
individual treatment effect tau(X) at each row can be estimated by
regressing the pseudo-outcome `y_resid / d_resid` on X, weighted by
`d_resid ** 2`. That weight is what makes this a real second-stage
regression rather than an ad hoc ratio: rows where the nuisance model
left almost no residual treatment variation (`d_resid` near zero) get
almost no say, since dividing by a tiny d_resid would otherwise blow up
the pseudo-outcome into noise.

`tau(X)` here is linear-in-X by construction (weighted least squares) --
a first cut at heterogeneity, not a full causal forest. It answers "does
the treatment effect vary with exposure/growth controls" with an
interpretable slope, which is what R/07's Model C already asks for
`exposure` specifically (`treated_post * exposure`); this is the same
question asked with the DML residuals instead of TWFE.
"""

from __future__ import annotations

import numpy as np


def fit_r_learner_cate(X: np.ndarray, y_resid: np.ndarray, d_resid: np.ndarray) -> np.ndarray:
    """Weighted least squares for tau(X) = coef[0] + coef[1:] @ X, fit on
    the DML pseudo-outcome y_resid/d_resid with weights d_resid**2."""
    X = np.asarray(X, dtype=float)
    y_resid = np.asarray(y_resid, dtype=float)
    d_resid = np.asarray(d_resid, dtype=float)

    # A near-zero d_resid means the nuisance model already explains almost
    # all of this row's treatment variation -- dividing by it would blow
    # a tiny denominator into an enormous, meaningless pseudo-outcome.
    keep = np.abs(d_resid) > 1e-8
    pseudo_outcome = y_resid[keep] / d_resid[keep]
    weights = d_resid[keep] ** 2

    design = np.column_stack([np.ones(keep.sum()), X[keep]])
    sqrt_w = np.sqrt(weights)
    coef, *_ = np.linalg.lstsq(design * sqrt_w[:, None], pseudo_outcome * sqrt_w, rcond=None)
    return coef


def predict_cate(coef: np.ndarray, X: np.ndarray) -> np.ndarray:
    """tau_hat(X) for new rows, from the coefficients `fit_r_learner_cate` returned."""
    X = np.asarray(X, dtype=float)
    design = np.column_stack([np.ones(len(X)), X])
    return design @ coef
