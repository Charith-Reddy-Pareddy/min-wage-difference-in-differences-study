"""A CART-style regression tree, plus three ensembles built on top of
it, all from scratch on numpy only (no tree-fitting library is usable
in this environment -- see python/README.md).

- BaggedTrees: bootstrap-resample rows; if `mtry` is set, each tree also
  gets one fixed random feature subset for its entire fit. That's the
  "random subspace" method (Ho 1998), the direct counterpart to R/27's
  fit_bagged_trees() -- NOT Breiman's random forest, despite the
  superficial resemblance.
- RandomForest: the actual algorithm. Every split, in every tree,
  re-samples which `mtry` features are even candidates for that split --
  different splits within the same tree can draw on different features.
  Counterpart to R/27's fit_random_forest() (there, the real
  `randomForest` package; here, hand-rolled, since no such package is
  usable in this environment either).
- GradientBoostedTrees: a different combination strategy entirely --
  bagging and random forests fit trees INDEPENDENTLY in parallel on
  resampled data and average them; boosting fits trees SEQUENTIALLY,
  each one to the residual errors the ensemble so far still has. No
  bootstrap resampling here at all. Counterpart to R/27's
  fit_gradient_boosting() (there, the `gbm` package).
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


def _build(
    X: np.ndarray,
    y: np.ndarray,
    depth: int,
    max_depth: int,
    min_samples_leaf: int,
    feature_indices: list[int] | None = None,
    mtry: int | None = None,
    rng: np.random.Generator | None = None,
) -> _Node:
    """Recursive CART builder. Pass a fixed `feature_indices` for a plain
    tree or a per-tree-fixed subset (RegressionTree, BaggedTrees).
    Pass `mtry` + `rng` instead for a fresh random feature subset drawn
    at THIS node -- the call to build the two child nodes below draws
    its own subset again, independently (RandomForest)."""
    if depth >= max_depth or len(y) < 2 * min_samples_leaf:
        return _Node(is_leaf=True, value=float(y.mean()))

    if mtry is not None:
        n_features = X.shape[1]
        candidate_features = sorted(rng.choice(n_features, size=min(mtry, n_features), replace=False).tolist())
    else:
        candidate_features = feature_indices

    split = _best_split(X, y, candidate_features, min_samples_leaf)
    if split is None:
        return _Node(is_leaf=True, value=float(y.mean()))

    feat, threshold = split
    left_mask = X[:, feat] <= threshold
    left = _build(X[left_mask], y[left_mask], depth + 1, max_depth, min_samples_leaf, feature_indices, mtry, rng)
    right = _build(X[~left_mask], y[~left_mask], depth + 1, max_depth, min_samples_leaf, feature_indices, mtry, rng)
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
        self.root = _build(
            X, y, depth=0, max_depth=self.max_depth, min_samples_leaf=self.min_samples_leaf,
            feature_indices=feature_indices,
        )
        return self

    def predict(self, X: np.ndarray) -> np.ndarray:
        X = np.asarray(X, dtype=float)
        return np.array([_predict_one(self.root, row) for row in X])


class BaggedTrees:
    """Bootstrap-aggregated regression trees. Plain bagging when mtry is
    None (every tree considers all features). When mtry is set, each
    tree gets ONE fixed random feature subset for its entire fit -- the
    random subspace method (Ho 1998), not Breiman's random forest (see
    RandomForest below for that distinction and the real algorithm)."""

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


class RandomForest:
    """Breiman's random forest: bagged trees where every split, in every
    tree, re-samples which `mtry` features are candidates for that split
    (see module docstring for how this differs from BaggedTrees'
    mtry). `mtry` defaults to max(1, n_features // 3), the common
    regression-forest rule of thumb (scikit-learn and R's randomForest
    both default to this for regression)."""

    def __init__(self, n_trees: int = 25, max_depth: int = 5, min_samples_leaf: int = 5, mtry: int | None = None, seed: int = 1):
        self.n_trees = n_trees
        self.max_depth = max_depth
        self.min_samples_leaf = min_samples_leaf
        self.mtry = mtry
        self.seed = seed
        self.roots: list[_Node] = []

    def fit(self, X: np.ndarray, y: np.ndarray) -> "RandomForest":
        X = np.asarray(X, dtype=float)
        y = np.asarray(y, dtype=float)
        n, n_features = X.shape
        mtry = self.mtry if self.mtry is not None else max(1, n_features // 3)
        rng = np.random.default_rng(self.seed)

        self.roots = []
        for _ in range(self.n_trees):
            boot_idx = rng.integers(0, n, size=n)
            root = _build(
                X[boot_idx], y[boot_idx], depth=0, max_depth=self.max_depth,
                min_samples_leaf=self.min_samples_leaf, mtry=mtry, rng=rng,
            )
            self.roots.append(root)
        return self

    def predict(self, X: np.ndarray) -> np.ndarray:
        X = np.asarray(X, dtype=float)
        predictions = np.column_stack(
            [[_predict_one(root, row) for row in X] for root in self.roots]
        )
        return predictions.mean(axis=1)


class GradientBoostedTrees:
    """Gradient boosting for squared-error regression: start from the
    training mean, then repeatedly fit a shallow RegressionTree to the
    CURRENT residuals (y minus the ensemble's predictions so far) and add
    `learning_rate` times that tree's predictions to the running total.
    For squared-error loss, the residual IS the negative gradient, which
    is what makes this "gradient" boosting rather than just "fit trees to
    leftover error" -- for a different loss function the target at each
    step would be that loss's own negative gradient instead.

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
    ):
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
