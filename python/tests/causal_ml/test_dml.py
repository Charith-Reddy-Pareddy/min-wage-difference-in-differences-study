import numpy as np
import pytest

from minwage.causal_ml.dml import partialling_out_dml
from minwage.ml.baselines import LinearRegression
from minwage.ml.random_forest import RandomForest


def make_groups(n_states: int = 40, rows_per_state: int = 10) -> np.ndarray:
    return np.array([f"State{i}" for i in range(n_states) for _ in range(rows_per_state)])


def test_recovers_a_known_effect_with_linear_nuisance_functions():
    rng = np.random.default_rng(0)
    groups = make_groups(40, 10)
    n = len(groups)
    true_theta = 2.5

    X = rng.normal(size=(n, 2))
    D = 0.5 * X[:, 0] - 0.3 * X[:, 1] + rng.normal(scale=0.3, size=n)
    Y = true_theta * D + 1.5 * X[:, 0] + 0.8 * X[:, 1] + rng.normal(scale=0.1, size=n)

    result = partialling_out_dml(X, Y, D, groups, LinearRegression, LinearRegression, n_folds=5, seed=0)

    assert abs(result["theta"] - true_theta) < 0.1
    assert result["ci_lower"] < true_theta < result["ci_upper"]


def test_recovers_a_known_effect_with_nonlinear_nuisance_functions():
    rng = np.random.default_rng(1)
    groups = make_groups(40, 10)
    n = len(groups)
    true_theta = -1.0

    X = rng.normal(size=(n, 2))
    # g(X) and m(X) are both nonlinear -- a linear nuisance model would
    # leave confounding in the residuals and bias theta_hat.
    D = np.sin(X[:, 0]) + 0.4 * X[:, 1] ** 2 + rng.normal(scale=0.2, size=n)
    Y = true_theta * D + np.cos(X[:, 1]) + 0.3 * X[:, 0] ** 2 + rng.normal(scale=0.1, size=n)

    def forest_factory():
        return RandomForest(n_trees=50, max_depth=4, min_samples_leaf=5, seed=1)

    result = partialling_out_dml(X, Y, D, groups, forest_factory, forest_factory, n_folds=5, seed=0)

    assert abs(result["theta"] - true_theta) < 0.3


def test_theta_is_near_zero_when_d_has_no_effect_on_y():
    rng = np.random.default_rng(2)
    groups = make_groups(40, 10)
    n = len(groups)

    X = rng.normal(size=(n, 2))
    D = 0.5 * X[:, 0] + rng.normal(scale=0.3, size=n)
    Y = 1.5 * X[:, 0] + 0.8 * X[:, 1] + rng.normal(scale=0.1, size=n)  # no D term at all

    result = partialling_out_dml(X, Y, D, groups, LinearRegression, LinearRegression, n_folds=5, seed=0)

    assert abs(result["theta"]) < 0.1
    assert result["ci_lower"] < 0 < result["ci_upper"]


class ZeroPredictor:
    def fit(self, X, y):
        return self

    def predict(self, X):
        return np.zeros(len(X))


def clustered_example(repeats=1):
    # Unequal, interleaved clusters with positively correlated scores.
    groups = np.array(["a", "b", "a", "c", "b", "c", "c"])
    D = np.ones(7)
    Y = np.array([1.0, 3.0, 1.0, 5.0, 3.0, 5.0, 5.0])
    return partialling_out_dml(
        np.zeros((7 * repeats, 1)),
        np.tile(Y, repeats),
        np.tile(D, repeats),
        np.tile(groups, repeats),
        ZeroPredictor,
        ZeroPredictor,
        n_folds=3,
    )


def test_cluster_sandwich_matches_hand_calculation():
    result = clustered_example()
    theta = 23 / 7
    scores = np.array([2 * (1 - theta), 2 * (3 - theta), 3 * (5 - theta)])
    expected = np.sqrt(3 / 2 * np.sum(scores**2)) / 7
    assert result["theta"] == pytest.approx(theta)
    assert result["se"] == pytest.approx(expected)
    assert result["n_clusters"] == 3
    assert result["se"] > result["se_row"]
    assert result["ci_lower"] == pytest.approx(theta - 1.96 * expected)
    assert result["ci_upper"] == pytest.approx(theta + 1.96 * expected)


def test_duplicate_rows_within_states_do_not_create_precision():
    original, duplicated = clustered_example(), clustered_example(repeats=4)
    assert duplicated["theta"] == pytest.approx(original["theta"])
    assert duplicated["se"] == pytest.approx(original["se"])
    assert duplicated["se_row"] == pytest.approx(original["se_row"] / 2)


def test_singleton_clusters_match_hc1():
    result = partialling_out_dml(
        np.zeros((4, 1)),
        np.array([1.0, 2.0, 4.0, 8.0]),
        np.ones(4),
        np.arange(4),
        ZeroPredictor,
        ZeroPredictor,
        n_folds=2,
    )
    assert result["se"] == pytest.approx(result["se_row"] * np.sqrt(4 / 3))


def test_zero_residual_treatment_is_rejected():
    with pytest.raises(ValueError, match="treatment"):
        partialling_out_dml(
            np.zeros((4, 1)),
            np.arange(4.0),
            np.zeros(4),
            np.arange(4),
            ZeroPredictor,
            ZeroPredictor,
            n_folds=2,
        )


@pytest.mark.parametrize("case", ["shape", "nan", "missing_group", "one_cluster", "folds"])
def test_invalid_panel_inputs_are_rejected(case):
    X, Y, D, groups = np.zeros((4, 1)), np.arange(4.0), np.ones(4), np.arange(4.0)
    folds = 2
    if case == "shape":
        D = D[:-1]
    elif case == "nan":
        Y[0] = np.nan
    elif case == "missing_group":
        groups[0] = np.nan
    elif case == "one_cluster":
        groups[:] = 0
    else:
        folds = 5
    with pytest.raises(ValueError):
        partialling_out_dml(X, Y, D, groups, ZeroPredictor, ZeroPredictor, n_folds=folds)
