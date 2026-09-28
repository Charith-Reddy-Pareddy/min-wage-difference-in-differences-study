"""A small read-only FastAPI service over this project's precomputed
results CSVs (train.py's model comparison, causal_estimate.py's DML
estimate and exposure-heterogeneity slope).

It does not run or retrain any model itself -- every endpoint reads
whatever train.py/causal_estimate.py last wrote to results/, and
returns 404 rather than crashing if that file doesn't exist yet, since
results/ is gitignored and only populated locally after running those
scripts. This is a results-serving layer, not a prediction endpoint --
the DiD study's actual causal estimate belongs in the R report and
README, not behind an API a browser could hit and misread as a live
model.

Run (needs the [api] extra, and at least one script under python/ to
have been run first so results/ has something to serve):

    .venv/bin/pip install -e ".[api]"
    .venv/bin/uvicorn minwage.api.app:app --reload
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
from fastapi import FastAPI, HTTPException

RESULTS_DIR = Path(__file__).resolve().parents[3] / "results"

app = FastAPI(
    title="minwage results API",
    description="Read-only access to this project's precomputed ML comparison and causal ML results.",
)


def _read_results_csv(filename: str) -> list[dict]:
    path = RESULTS_DIR / filename
    if not path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"{filename} not found in results/ -- run the script that produces it first.",
        )
    return pd.read_csv(path).to_dict(orient="records")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/ml/comparison")
def ml_comparison() -> list[dict]:
    """Predictive-accuracy comparison across models (train.py)."""
    return _read_results_csv("comparison.csv")


@app.get("/ml/random-forest/grid-search")
def random_forest_grid_search() -> list[dict]:
    """Every max_depth/min_samples_leaf combination tried and its grouped-CV RMSE."""
    return _read_results_csv("random_forest_grid_search.csv")


@app.get("/ml/random-forest/bootstrap-ci")
def random_forest_bootstrap_ci() -> list[dict]:
    """95% cluster bootstrap CI for the tuned random forest's test RMSE and R²."""
    return _read_results_csv("random_forest_bootstrap_ci.csv")


@app.get("/ml/random-forest/permutation-importance")
def random_forest_permutation_importance() -> list[dict]:
    """RMSE increase when each feature is independently shuffled."""
    return _read_results_csv("random_forest_permutation_importance.csv")


@app.get("/causal/dml")
def causal_dml() -> list[dict]:
    """Double ML estimate of treated_post's effect on employment_growth (causal_estimate.py)."""
    return _read_results_csv("dml_estimate.csv")


@app.get("/causal/heterogeneity")
def causal_heterogeneity() -> list[dict]:
    """R-learner heterogeneity slope for the treatment effect by exposure."""
    return _read_results_csv("dml_exposure_heterogeneity.csv")
