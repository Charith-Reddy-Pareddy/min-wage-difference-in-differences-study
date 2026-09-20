"""Gradient boosting for squared-error regression -- a different
combination strategy entirely from `minwage.ml.random_forest`'s two
ensembles: bagging and random forests fit trees INDEPENDENTLY in
parallel on resampled data and average them; boosting fits trees
SEQUENTIALLY, each one to the residual errors the ensemble so far still
has. No bootstrap resampling here at all. Counterpart to R/27's
fit_gradient_boosting() (there, the `gbm` package).
"""

from __future__ import annotations

import numpy as np

from minwage.ml.random_forest import RegressionTree


class GradientBoostedTrees:
    """Start from the training mean, then repeatedly fit a shallow
    RegressionTree to the CURRENT residuals (y minus the ensemble's
    predictions so far) and add `learning_rate` times that tree's
    predictions to the running total. For squared-error loss, the
    residual IS the negative gradient, which is what makes this
    "gradient" boosting rather than just "fit trees to leftover error"
    -- for a different loss function the target at each step would be
    that loss's own negative gradient instead.

    Deliberately shallow trees (`max_depth` small) and a small
    `learning_rate`: many weak learners added slowly, rather than a few
    strong ones, is what keeps gradient boosting from overfitting almost
    immediately."""

    def __init__(
        self,
        n_estimators: int = 100,
        learning_rate: float = 0.1,
        max_depth: int = 2,
        min_samples_leaf: int = 5,
    ) -> None:
        self.n_estimators = n_estimators
        self.learning_rate = learning_rate
        self.max_depth = max_depth
        self.min_samples_leaf = min_samples_leaf
        self.init_value: float = 0.0
        self.trees: list[RegressionTree] = []

    def fit(self, X: np.ndarray, y: np.ndarray) -> "GradientBoostedTrees":
        X = np.asarray(X, dtype=float)
        y = np.asarray(y, dtype=float)
        self.init_value = float(y.mean())
        predictions = np.full(len(y), self.init_value)

        self.trees = []
        for _ in range(self.n_estimators):
            residuals = y - predictions
            tree = RegressionTree(max_depth=self.max_depth, min_samples_leaf=self.min_samples_leaf)
            tree.fit(X, residuals)
            predictions = predictions + self.learning_rate * tree.predict(X)
            self.trees.append(tree)
        return self

    def predict(self, X: np.ndarray) -> np.ndarray:
        X = np.asarray(X, dtype=float)
        predictions = np.full(X.shape[0], self.init_value)
        for tree in self.trees:
            predictions = predictions + self.learning_rate * tree.predict(X)
        return predictions
