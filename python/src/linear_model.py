"""OLS via the normal equations, implemented directly on numpy (no scipy
or sklearn) -- this environment's scipy wheel doesn't load on this
machine (see python/README.md), and a closed-form least-squares fit is
a handful of lines anyway."""

import numpy as np


class LinearRegression:
    def __init__(self) -> None:
        self.coef_: np.ndarray | None = None

    def fit(self, X: np.ndarray, y: np.ndarray) -> "LinearRegression":
        X = np.asarray(X, dtype=float)
        y = np.asarray(y, dtype=float)
        design = np.column_stack([np.ones(len(X)), X])
        # lstsq rather than a literal (X'X)^-1 X'y: numerically stable
        # even when columns are near-collinear.
        coef, *_ = np.linalg.lstsq(design, y, rcond=None)
        self.coef_ = coef
        return self

    def predict(self, X: np.ndarray) -> np.ndarray:
        if self.coef_ is None:
            raise RuntimeError("call fit() before predict()")
        X = np.asarray(X, dtype=float)
        design = np.column_stack([np.ones(len(X)), X])
        return design @ self.coef_
