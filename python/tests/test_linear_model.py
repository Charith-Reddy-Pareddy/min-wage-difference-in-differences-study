import numpy as np
import pytest

from src.linear_model import LinearRegression


def test_recovers_an_exact_linear_relationship_with_no_noise():
    rng = np.random.default_rng(0)
    X = rng.uniform(-5, 5, size=(200, 2))
    true_intercept, true_coefs = 3.0, np.array([2.0, -1.5])
    y = true_intercept + X @ true_coefs

    model = LinearRegression().fit(X, y)

    assert model.coef_[0] == pytest.approx(true_intercept, abs=1e-8)
    assert model.coef_[1:] == pytest.approx(true_coefs, abs=1e-8)


def test_predict_matches_fit_data_when_relationship_is_exact():
    X = np.array([[0.0], [1.0], [2.0], [3.0]])
    y = np.array([1.0, 3.0, 5.0, 7.0])  # y = 1 + 2x

    model = LinearRegression().fit(X, y)
    predictions = model.predict(np.array([[4.0], [5.0]]))

    assert predictions == pytest.approx(np.array([9.0, 11.0]), abs=1e-8)
