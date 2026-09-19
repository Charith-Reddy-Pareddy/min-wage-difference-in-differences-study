"""Load the feature panel exported by R/27_ml_prediction.R.

The panel itself (data/processed/ml_panel.csv) is built once, in R, from
the same build_panel() the study's causal Model A/C use -- this module
only reads that CSV and one-hot encodes region, rather than re-deriving
panel-construction logic in a second language. Two implementations of
"how to build the panel" would drift out of sync; one implementation
(R) with a shared export, read here, doesn't.
"""

from pathlib import Path

import pandas as pd

DEFAULT_PANEL_PATH = Path(__file__).resolve().parents[2] / "data" / "processed" / "ml_panel.csv"

FEATURE_COLUMNS = ["treated_post", "gdp_growth", "pop_growth", "exposure"]
TARGET_COLUMN = "employment_growth"
GROUP_COLUMN = "state"


def load_ml_panel(path: Path = DEFAULT_PANEL_PATH) -> pd.DataFrame:
    """Read the shared ML panel CSV written by R/27_ml_prediction.R."""
    return pd.read_csv(path, parse_dates=["quarter"])


def one_hot_region(df: pd.DataFrame) -> pd.DataFrame:
    """Add 0/1 region dummy columns, dropping one level to avoid the
    dummy-variable trap (perfect collinearity with an intercept) in the
    linear baseline."""
    dummies = pd.get_dummies(df["region"], prefix="region", drop_first=True, dtype=float)
    return pd.concat([df.reset_index(drop=True), dummies.reset_index(drop=True)], axis=1)


def feature_matrix(df: pd.DataFrame) -> pd.DataFrame:
    """The numeric feature columns used by every model here: the fixed
    predictors plus whichever region dummy columns one_hot_region added."""
    region_cols = [c for c in df.columns if c.startswith("region_")]
    return df[FEATURE_COLUMNS + region_cols]
