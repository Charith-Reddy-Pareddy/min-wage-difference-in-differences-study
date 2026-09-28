import pandas as pd
import pytest
from fastapi.testclient import TestClient

from minwage.api import app as app_module

client = TestClient(app_module.app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.parametrize(
    "endpoint,filename",
    [
        ("/ml/comparison", "comparison.csv"),
        ("/ml/random-forest/grid-search", "random_forest_grid_search.csv"),
        ("/ml/random-forest/bootstrap-ci", "random_forest_bootstrap_ci.csv"),
        ("/ml/random-forest/permutation-importance", "random_forest_permutation_importance.csv"),
        ("/causal/dml", "dml_estimate.csv"),
        ("/causal/heterogeneity", "dml_exposure_heterogeneity.csv"),
    ],
)
def test_returns_404_when_the_results_file_does_not_exist_yet(tmp_path, monkeypatch, endpoint, filename):
    monkeypatch.setattr(app_module, "RESULTS_DIR", tmp_path)

    response = client.get(endpoint)

    assert response.status_code == 404
    assert filename in response.json()["detail"]


def test_returns_the_csv_contents_as_json_when_the_file_exists(tmp_path, monkeypatch):
    monkeypatch.setattr(app_module, "RESULTS_DIR", tmp_path)
    pd.DataFrame({"model": ["linear_baseline", "random_forest"], "rmse": [0.08, 0.07]}).to_csv(
        tmp_path / "comparison.csv", index=False
    )

    response = client.get("/ml/comparison")

    assert response.status_code == 200
    assert response.json() == [
        {"model": "linear_baseline", "rmse": 0.08},
        {"model": "random_forest", "rmse": 0.07},
    ]
