"""Grouped train/test split.

Mirrors split_by_state() in R/27_ml_prediction.R: a row-level random
split would put the same state's quarters on both sides, leaking
within-state structure the model could exploit. Every row for a given
group (state) must land entirely in train or entirely in test.
"""

import numpy as np
import pandas as pd


def group_train_test_split(
    df: pd.DataFrame, group_col: str = "state", test_frac: float = 0.2, seed: int = 1
) -> tuple[pd.DataFrame, pd.DataFrame]:
    groups = np.sort(df[group_col].unique())
    rng = np.random.default_rng(seed)
    n_test = max(1, round(len(groups) * test_frac))
    test_groups = set(rng.choice(groups, size=n_test, replace=False))

    is_test = df[group_col].isin(test_groups)
    return df.loc[~is_test].reset_index(drop=True), df.loc[is_test].reset_index(drop=True)
