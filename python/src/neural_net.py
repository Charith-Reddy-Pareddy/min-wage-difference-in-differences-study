"""A single-hidden-layer feedforward network (PyTorch), the Python-side
counterpart to R/28_neural_network.R's nnet() model.

Same reasoning as the R version: ~1,000-2,000 training rows and a
handful of predictors isn't enough data to justify a deep network, and
inputs/target are standardized on TRAIN-set statistics only (fitting the
scaler on test data too would leak test-set information into training).
"""

from __future__ import annotations

import numpy as np
import torch
from torch import nn


class FeedForwardNet(nn.Module):
    def __init__(self, input_dim: int, hidden_dim: int = 8):
        super().__init__()
        self.hidden = nn.Linear(input_dim, hidden_dim)
        self.activation = nn.ReLU()
        self.output = nn.Linear(hidden_dim, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.output(self.activation(self.hidden(x))).squeeze(-1)


class Standardizer:
    """Fits mean/std on one array, applies (and inverts) that same
    transform on any other array -- used to scale train and test
    consistently from train-only statistics."""

    def __init__(self) -> None:
        self.mean_ = None
        self.std_ = None

    def fit(self, x: np.ndarray) -> "Standardizer":
        self.mean_ = x.mean(axis=0)
        std = x.std(axis=0)
        self.std_ = np.where(std == 0, 1.0, std)
        return self

    def transform(self, x: np.ndarray) -> np.ndarray:
        return (x - self.mean_) / self.std_

    def inverse_transform_target(self, z: np.ndarray, target_mean: float, target_std: float) -> np.ndarray:
        return z * target_std + target_mean


def train_neural_network(
    X_train: np.ndarray,
    y_train: np.ndarray,
    X_test: np.ndarray,
    hidden_dim: int = 8,
    epochs: int = 300,
    lr: float = 0.01,
    seed: int = 1,
) -> tuple[np.ndarray, list[float]]:
    """Trains FeedForwardNet on (X_train, y_train), returns predictions
    on X_test (rescaled to y_train's original units) plus the per-epoch
    training loss history."""
    torch.manual_seed(seed)

    x_scaler = Standardizer().fit(np.asarray(X_train, dtype=float))
    y_mean, y_std = float(y_train.mean()), float(y_train.std() or 1.0)

    X_train_t = torch.tensor(x_scaler.transform(np.asarray(X_train, dtype=float)), dtype=torch.float32)
    y_train_t = torch.tensor((np.asarray(y_train, dtype=float) - y_mean) / y_std, dtype=torch.float32)
    X_test_t = torch.tensor(x_scaler.transform(np.asarray(X_test, dtype=float)), dtype=torch.float32)

    model = FeedForwardNet(input_dim=X_train_t.shape[1], hidden_dim=hidden_dim)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.MSELoss()

    loss_history = []
    model.train()
    for _ in range(epochs):
        optimizer.zero_grad()
        predictions = model(X_train_t)
        loss = loss_fn(predictions, y_train_t)
        loss.backward()
        optimizer.step()
        loss_history.append(float(loss.item()))

    model.eval()
    with torch.no_grad():
        pred_z = model(X_test_t).numpy()
    predictions = pred_z * y_std + y_mean

    return predictions, loss_history
