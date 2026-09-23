"""Shared evaluation metrics, kept identical to R/27's rmse()/r_squared()
so the two ecosystems' results are directly comparable."""

from __future__ import annotations

import numpy as np


def rmse(actual: np.ndarray, predicted: np.ndarray) -> float:
    return float(np.sqrt(np.mean((actual - predicted) ** 2)))


def r_squared(actual: np.ndarray, predicted: np.ndarray) -> float:
    actual = np.asarray(actual)
    predicted = np.asarray(predicted)
    ss_res = np.sum((actual - predicted) ** 2)
    ss_tot = np.sum((actual - np.mean(actual)) ** 2)
    if ss_tot == 0:
        # actual has zero variance -- "fraction of variance explained" is
        # undefined, not a divide-by-zero. Perfect predictions still get
        # credit; anything else gets none, matching sklearn's convention.
        return 1.0 if ss_res == 0 else 0.0
    return float(1 - ss_res / ss_tot)
