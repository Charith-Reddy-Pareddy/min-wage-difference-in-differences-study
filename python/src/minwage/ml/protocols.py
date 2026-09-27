"""The `.fit(X, y)` / `.predict(X)` shape every estimator in this
project follows (LinearRegression, RandomForest, GradientBoostedTrees,
...), typed once so `minwage.ml.experiment` and `minwage.causal_ml.dml`
can say "any estimator" instead of the untyped `object` a bare
`Callable[[], object]` gives mypy nothing to check against."""

from __future__ import annotations

from typing import Protocol

import numpy as np


class Estimator(Protocol):
    def fit(self, X: np.ndarray, y: np.ndarray) -> Estimator: ...

    def predict(self, X: np.ndarray) -> np.ndarray: ...
