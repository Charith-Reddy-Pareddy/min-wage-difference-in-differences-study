"""Package-wide constants: the panel's default location and the fixed
feature/target/group column names every module in `minwage.ml` agrees on.
Centralized here rather than duplicated per-module, and rather than left
implicit as string literals scattered across `data`, `ml`, and `train.py`.
"""

from pathlib import Path

# python/src/minwage/config.py -> parents[3] is the repo root
# (config.py -> minwage -> src -> python -> repo root).
REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PANEL_PATH = REPO_ROOT / "data" / "processed" / "ml_panel.csv"

FEATURE_COLUMNS = ["treated_post", "gdp_growth", "pop_growth", "exposure"]
TARGET_COLUMN = "employment_growth"
GROUP_COLUMN = "state"
