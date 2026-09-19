"""A CART-style regression tree and a bootstrap-aggregated ("bagged")
ensemble of them, built from scratch on top of numpy only.

This is the Python-side counterpart to R/27_ml_prediction.R's
fit_bagged_trees() (there, `rpart` supplies the single-tree fit; here
there's no tree-fitting library available at all in this environment
-- see python/README.md -- so the split-search and recursion are
implemented directly). Same ensembling idea in both: bootstrap-resample
rows and take a random feature subset per tree, then average
predictions across trees.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass
class _Node:
    is_leaf: bool
    value: float = 0.0
    feature_index: int = -1
    threshold: float = 0.0
    left: "_Node | None" = None
    right: "_Node | None" = None


def _sse(y: np.ndarray) -> float:
    if len(y) == 0:
        return 0.0
    return float(np.sum((y - y.mean()) ** 2))


def _best_split(X: np.ndarray, y: np.ndarray, feature_indices: list[int], min_samples_leaf: int):
    """Greedy search over the given features and every midpoint between
    consecutive sorted values, minimizing the total SSE of the two
    resulting halves. Returns (feature_index, threshold) or None if no
    split satisfies min_samples_leaf."""
    best = None
    best_sse = _sse(y)

    for feat in feature_indices:
        values = X[:, feat]
        order = np.argsort(values)
        sorted_values = values[order]
        sorted_y = y[order]

        # Candidate thresholds: midpoints between distinct consecutive
        # values only (a split between two equal values can't separate
        # anything).
        candidate_positions = np.where(np.diff(sorted_values) > 0)[0]
        for pos in candidate_positions:
            left_n = pos + 1
            right_n = len(y) - left_n
            if left_n < min_samples_leaf or right_n < min_samples_leaf:
                continue
            left_sse = _sse(sorted_y[:left_n])
            right_sse = _sse(sorted_y[left_n:])
            total = left_sse + right_sse
            if total < best_sse:
                best_sse = total
                threshold = (sorted_values[pos] + sorted_values[pos + 1]) / 2
                best = (feat, threshold)

    return best


def _build(X: np.ndarray, y: np.ndarray, feature_indices: list[int], depth: int, max_depth: int, min_samples_leaf: int) -> _Node:
    if depth >= max_depth or len(y) < 2 * min_samples_leaf:
        return _Node(is_leaf=True, value=float(y.mean()))

    split = _best_split(X, y, feature_indices, min_samples_leaf)
    if split is None:
        return _Node(is_leaf=True, value=float(y.mean()))

    feat, threshold = split
    left_mask = X[:, feat] <= threshold
    left = _build(X[left_mask], y[left_mask], feature_indices, depth + 1, max_depth, min_samples_leaf)
    right = _build(X[~left_mask], y[~left_mask], feature_indices, depth + 1, max_depth, min_samples_leaf)
    return _Node(is_leaf=False, feature_index=feat, threshold=threshold, left=left, right=right)


def _predict_one(node: _Node, row: np.ndarray) -> float:
    while not node.is_leaf:
        node = node.left if row[node.feature_index] <= node.threshold else node.right
    return node.value


class RegressionTree:
    def __init__(self, max_depth: int = 5, min_samples_leaf: int = 5, feature_indices: list[int] | None = None):
        self.max_depth = max_depth
        self.min_samples_leaf = min_samples_leaf
        self.feature_indices = feature_indices
        self.root: _Node | None = None

    def fit(self, X: np.ndarray, y: np.ndarray) -> "RegressionTree":
        X = np.asarray(X, dtype=float)
        y = np.asarray(y, dtype=float)
        feature_indices = self.feature_indices if self.feature_indices is not None else list(range(X.shape[1]))
        self.root = _build(X, y, feature_indices, depth=0, max_depth=self.max_depth, min_samples_leaf=self.min_samples_leaf)
        return self

    def predict(self, X: np.ndarray) -> np.ndarray:
        X = np.asarray(X, dtype=float)
        return np.array([_predict_one(self.root, row) for row in X])


class BaggedTrees:
    """Bootstrap-aggregated regression trees, each grown on a bootstrap
    resample of the rows and a random subset (`mtry`) of the features --
    plain bagging when mtry is None (all features), a random forest when
    mtry < number of features."""

    def __init__(self, n_trees: int = 25, max_depth: int = 5, min_samples_leaf: int = 5, mtry: int | None = None, seed: int = 1):
        self.n_trees = n_trees
        self.max_depth = max_depth
        self.min_samples_leaf = min_samples_leaf
        self.mtry = mtry
        self.seed = seed
        self.trees: list[RegressionTree] = []

    def fit(self, X: np.ndarray, y: np.ndarray) -> "BaggedTrees":
        X = np.asarray(X, dtype=float)
        y = np.asarray(y, dtype=float)
        n, n_features = X.shape
        rng = np.random.default_rng(self.seed)

        self.trees = []
        for _ in range(self.n_trees):
            boot_idx = rng.integers(0, n, size=n)
            mtry = self.mtry if self.mtry is not None else n_features
            feature_indices = sorted(rng.choice(n_features, size=mtry, replace=False).tolist())
            tree = RegressionTree(
                max_depth=self.max_depth, min_samples_leaf=self.min_samples_leaf, feature_indices=feature_indices
            )
            tree.fit(X[boot_idx], y[boot_idx])
            self.trees.append(tree)
        return self

    def predict(self, X: np.ndarray) -> np.ndarray:
        X = np.asarray(X, dtype=float)
        predictions = np.column_stack([tree.predict(X) for tree in self.trees])
        return predictions.mean(axis=1)
