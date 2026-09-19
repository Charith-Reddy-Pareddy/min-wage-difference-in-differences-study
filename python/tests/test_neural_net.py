import numpy as np
import pytest

from src.neural_net import Standardizer, train_neural_network


def test_standardizer_round_trips_and_normalizes():
    x = np.array([[10.0], [20.0], [30.0], [40.0]])
    scaler = Standardizer().fit(x)
    z = scaler.transform(x)

    assert z.mean() == pytest.approx(0.0, abs=1e-8)
    recovered = scaler.inverse_transform_target(z[:, 0], target_mean=x.mean(), target_std=x.std())
    assert recovered == pytest.approx(x[:, 0], abs=1e-6)


def test_train_neural_network_returns_one_prediction_per_test_row_and_finite_loss():
    rng = np.random.default_rng(4)
    n = 200
    X = rng.uniform(-1, 1, size=(n, 2))
    y = 0.5 * X[:, 0] - 0.3 * X[:, 1] + rng.normal(scale=0.05, size=n)
    X_test = rng.uniform(-1, 1, size=(20, 2))

    predictions, loss_history = train_neural_network(X, y, X_test, hidden_dim=4, epochs=100, seed=1)

    assert predictions.shape == (20,)
    assert np.all(np.isfinite(predictions))
    assert all(np.isfinite(loss) for loss in loss_history)


def test_train_neural_network_loss_decreases_over_training():
    rng = np.random.default_rng(5)
    n = 200
    X = rng.uniform(-1, 1, size=(n, 2))
    y = 0.5 * X[:, 0] - 0.3 * X[:, 1] + rng.normal(scale=0.05, size=n)
    X_test = rng.uniform(-1, 1, size=(5, 2))

    _, loss_history = train_neural_network(X, y, X_test, hidden_dim=4, epochs=200, seed=1)

    # Not monotonic epoch-to-epoch (Adam), but the back half should
    # clearly beat the front half if training is actually working.
    first_quarter = np.mean(loss_history[: len(loss_history) // 4])
    last_quarter = np.mean(loss_history[-len(loss_history) // 4 :])
    assert last_quarter < first_quarter
