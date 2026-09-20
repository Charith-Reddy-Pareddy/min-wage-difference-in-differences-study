"""New in this restructuring: loaders.py had no dedicated test file
before (only exercised indirectly via train.py against real data).
one_hot_region and feature_matrix are pure DataFrame transforms and
easy to test directly; load_ml_panel is a thin CSV read wrapped around
pandas and isn't worth a synthetic-fixture test on its own."""

import pandas as pd

from minwage.data.loaders import feature_matrix, one_hot_region


def test_one_hot_region_drops_one_level_to_avoid_the_dummy_trap():
    df = pd.DataFrame({"state": ["A", "B", "C"], "region": ["West", "South", "West"]})
    result = one_hot_region(df)

    region_cols = [c for c in result.columns if c.startswith("region_")]
    # 2 distinct regions -> 1 dummy column, not 2.
    assert len(region_cols) == 1
    assert result[region_cols[0]].tolist() == [1.0, 0.0, 1.0] or result[region_cols[0]].tolist() == [
        0.0,
        1.0,
        0.0,
    ]


def test_one_hot_region_preserves_row_count_and_original_columns():
    df = pd.DataFrame({"state": ["A", "B"], "region": ["West", "South"], "exposure": [0.3, 0.4]})
    result = one_hot_region(df)

    assert len(result) == 2
    assert "exposure" in result.columns
    assert "state" in result.columns


def test_feature_matrix_selects_fixed_columns_plus_region_dummies():
    df = pd.DataFrame(
        {
            "treated_post": [1, 0],
            "gdp_growth": [0.01, -0.01],
            "pop_growth": [0.001, 0.002],
            "exposure": [0.3, 0.4],
            "region_South": [1.0, 0.0],
            "region_West": [0.0, 1.0],
            "unrelated_column": ["x", "y"],
        }
    )
    result = feature_matrix(df)

    assert "unrelated_column" not in result.columns
    assert set(result.columns) == {
        "treated_post",
        "gdp_growth",
        "pop_growth",
        "exposure",
        "region_South",
        "region_West",
    }
