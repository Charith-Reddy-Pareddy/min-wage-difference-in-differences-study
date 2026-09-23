import numpy as np

from minwage.ml.baselines import LinearRegression
from minwage.ml.experiment import (
    bootstrap_metric_ci,
    cross_validate,
    grid_search_cv,
    group_k_fold,
    permutation_importance,
)


def make_groups(n_states: int = 10, rows_per_state: int = 4) -> np.ndarray:
    return np.array([f"State{i}" for i in range(n_states) for _ in range(rows_per_state)])


class ConstantPredictor:
    """A model whose only "training" is remembering a fixed constant --
    used to give grid_search_cv a deterministically correct answer to
    find, without needing a real estimator's randomness."""

    def __init__(self, value: float = 0.0) -> None:
        self.value = value

    def fit(self, X, y):
        return self

    def predict(self, X):
        return np.full(len(X), self.value)


def test_group_k_fold_never_splits_a_state_across_train_and_test():
    groups = make_groups(10, 4)
    for train_idx, test_idx in group_k_fold(groups, n_splits=5, seed=0):
        train_states = set(groups[train_idx])
        test_states = set(groups[test_idx])
        assert train_states.isdisjoint(test_states)


def test_group_k_fold_covers_every_row_exactly_once_across_folds():
    groups = make_groups(10, 4)
    seen = []
    for _, test_idx in group_k_fold(groups, n_splits=5, seed=0):
        seen.extend(test_idx.tolist())

    assert sorted(seen) == list(range(len(groups)))


def test_cross_validate_returns_one_score_per_fold():
    rng = np.random.default_rng(0)
    groups = make_groups(10, 4)
    X = rng.normal(size=(len(groups), 2))
    y = X[:, 0] + rng.normal(scale=0.01, size=len(groups))

    result = cross_validate(LinearRegression, X, y, groups, n_splits=5, seed=0)

    assert len(result["rmse_folds"]) == 5
    assert result["rmse_mean"] < 0.5


def test_grid_search_cv_finds_the_exact_best_constant():
    groups = make_groups(10, 4)
    y = np.full(len(groups), 7.0)
    X = np.zeros((len(groups), 1))

    best_params, results = grid_search_cv(
        ConstantPredictor, {"value": [0.0, 3.0, 7.0, 10.0]}, X, y, groups, n_splits=5, seed=0
    )

    assert best_params["value"] == 7.0
    assert results.loc[results["value"] == 7.0, "rmse_mean"].iloc[0] == 0.0


def test_bootstrap_metric_ci_is_exact_when_predictions_are_perfect():
    groups = make_groups(10, 4)
    actual = np.arange(len(groups), dtype=float)
    predicted = actual.copy()

    ci = bootstrap_metric_ci(actual, predicted, groups, n_boot=200, seed=0)

    assert ci["point_estimate"] == 0.0
    assert ci["lower"] == 0.0
    assert ci["upper"] == 0.0


def test_bootstrap_metric_ci_bracket_widens_around_the_point_estimate():
    rng = np.random.default_rng(0)
    groups = make_groups(20, 4)
    actual = rng.normal(size=len(groups))
    predicted = actual + rng.normal(scale=0.5, size=len(groups))

    ci = bootstrap_metric_ci(actual, predicted, groups, n_boot=500, seed=0)

    assert ci["lower"] <= ci["point_estimate"] <= ci["upper"]


def test_permutation_importance_ranks_the_informative_feature_first():
    rng = np.random.default_rng(0)
    groups = make_groups(20, 4)
    n = len(groups)
    signal = rng.normal(size=n)
    noise = rng.normal(size=n)
    X = np.column_stack([signal, noise])
    y = 3 * signal

    model = LinearRegression().fit(X, y)
    importances = permutation_importance(model, X, y, ["signal", "noise"], n_repeats=15, seed=0)

    assert importances.iloc[0]["feature"] == "signal"
    assert importances.iloc[0]["importance_mean"] > importances.iloc[1]["importance_mean"]
