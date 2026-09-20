import numpy as np

from minwage.ml.evaluation import r_squared, rmse


def test_rmse_matches_hand_computed_example():
    actual = np.array([1, 2, 3, 4])
    predicted = np.array([1, 2, 3, 6])
    assert rmse(actual, predicted) == np.sqrt(np.mean([0, 0, 0, 4]))


def test_r_squared_is_one_for_a_perfect_prediction():
    actual = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    assert r_squared(actual, actual) == 1.0


def test_r_squared_is_zero_for_predicting_the_mean():
    actual = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    predicted = np.full_like(actual, actual.mean())
    assert r_squared(actual, predicted) == 0.0
