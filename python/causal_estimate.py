"""Cross-fitted double ML estimate of the minimum-wage effect on
employment_growth, using minwage.causal_ml.dml on the same feature
panel and target as train.py's predictive comparison.

This is NOT a reproduction of R/07_model_a_c.R's Model A: Model A fits
log_employment with full state and quarter fixed effects via TWFE;
this script fits employment_growth (the scale-invariant target
train.py already uses -- see R/27_ml_prediction.R's header for why)
with only region dummies as controls, matching the feature set the
Python ML panel has always used. The point is a functional-form
robustness check within that panel -- does relaxing the linear-in-X
assumption change the treated_post coefficient -- not a second,
independent estimate of Model A's causal parameter. Both estimates
still rest on the same identifying assumption: no unobserved
confounder of treatment and outcome given the controls.

Also reports how that effect varies with exposure specifically
(minwage.causal_ml.heterogeneity's R-learner on the random forest's
residuals) -- the same question R/07's Model C asks with a
treated_post*exposure interaction term, asked here without assuming
the interaction is linear in Model A's TWFE sense.

Run after `python train.py` has been used at least once (needs the
same data/processed/ml_panel.csv):

    python causal_estimate.py
"""

from pathlib import Path

import pandas as pd

from minwage.causal_ml.dml import partialling_out_dml
from minwage.causal_ml.heterogeneity import fit_r_learner_cate
from minwage.data.loaders import load_ml_panel, one_hot_region
from minwage.ml.baselines import LinearRegression
from minwage.ml.random_forest import RandomForest

RESULTS_DIR = Path(__file__).resolve().parent / "results"
CONTROL_COLUMNS = ["gdp_growth", "pop_growth", "exposure"]


def main() -> pd.DataFrame:
    panel = one_hot_region(load_ml_panel())
    region_cols = [c for c in panel.columns if c.startswith("region_")]
    X = panel[CONTROL_COLUMNS + region_cols].to_numpy(dtype=float)
    Y = panel["employment_growth"].to_numpy(dtype=float)
    D = panel["treated_post"].to_numpy(dtype=float)
    groups = panel["state"].to_numpy()

    linear_result = partialling_out_dml(X, Y, D, groups, LinearRegression, LinearRegression, n_folds=5, seed=1)

    def forest_factory():
        return RandomForest(n_trees=100, max_depth=4, min_samples_leaf=5, seed=1)

    forest_result = partialling_out_dml(X, Y, D, groups, forest_factory, forest_factory, n_folds=5, seed=1)

    results = pd.DataFrame(
        [
            {"nuisance_model": "linear", **{k: v for k, v in linear_result.items() if k in ("theta", "se", "ci_lower", "ci_upper", "n")}},
            {"nuisance_model": "random_forest", **{k: v for k, v in forest_result.items() if k in ("theta", "se", "ci_lower", "ci_upper", "n")}},
        ]
    )

    # Heterogeneity by exposure specifically -- the R-learner's pseudo-
    # outcome regression, taking exposure alone as the heterogeneity axis
    # (not the full control set), mirroring what R/07's Model C already
    # asks with a treated_post*exposure interaction, but built on the
    # forest-nuisance DML residuals above rather than TWFE.
    exposure = panel["exposure"].to_numpy(dtype=float).reshape(-1, 1)
    cate_coef = fit_r_learner_cate(exposure, forest_result["y_resid"], forest_result["d_resid"])
    heterogeneity = pd.DataFrame([{"intercept": cate_coef[0], "exposure_slope": cate_coef[1]}])

    RESULTS_DIR.mkdir(exist_ok=True)
    results.to_csv(RESULTS_DIR / "dml_estimate.csv", index=False)
    heterogeneity.to_csv(RESULTS_DIR / "dml_exposure_heterogeneity.csv", index=False)
    print("Double ML estimate of treated_post's effect on employment_growth:")
    print(results.to_string(index=False))
    print("\nTreatment-effect heterogeneity by exposure (R-learner, forest-nuisance residuals):")
    print(heterogeneity.to_string(index=False))
    return results


if __name__ == "__main__":
    main()
