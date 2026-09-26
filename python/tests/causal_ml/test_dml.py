import numpy as np

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
