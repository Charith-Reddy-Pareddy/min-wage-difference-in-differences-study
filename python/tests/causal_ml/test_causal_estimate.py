"""Check that the runnable analysis exports the inference it reports."""

import importlib.util
from pathlib import Path

import numpy as np
import pandas as pd

from minwage.ml.baselines import LinearRegression


def test_analysis_exports_clustered_and_row_uncertainty(tmp_path, monkeypatch):
    path = Path(__file__).resolve().parents[2] / "causal_estimate.py"
    spec = importlib.util.spec_from_file_location("causal_estimate", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    rng = np.random.default_rng(10)
    n = 60
    panel = pd.DataFrame(
        {
            "state": np.repeat(np.arange(10), 6),
            "gdp_growth": rng.normal(size=n),
            "pop_growth": rng.normal(size=n),
            "exposure": rng.uniform(size=n),
            "employment_growth": rng.normal(size=n),
            "treated_post": rng.integers(0, 2, size=n),
        }
    )
    monkeypatch.setattr(module, "load_ml_panel", lambda: panel)
    monkeypatch.setattr(module, "one_hot_region", lambda frame: frame)
    monkeypatch.setattr(module, "RandomForest", lambda **kwargs: LinearRegression())
    monkeypatch.setattr(module, "RESULTS_DIR", tmp_path)
    result = module.main()
    saved = pd.read_csv(tmp_path / "dml_estimate.csv")
    pd.testing.assert_frame_equal(saved, result)
    assert saved["n_clusters"].tolist() == [10, 10]
    assert saved["n"].tolist() == [n, n]
    assert (saved["se_row"] > 0).all()
    np.testing.assert_allclose(saved["ci_upper"] - saved["theta"], 1.96 * saved["se"])
    assert (tmp_path / "dml_exposure_heterogeneity.csv").exists()
