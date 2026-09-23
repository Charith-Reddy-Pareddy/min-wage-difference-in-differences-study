"""Predictive comparison, Python side: linear baseline, hand-rolled
bagged trees, hand-rolled random forest, hand-rolled gradient boosting,
and a PyTorch feedforward net, all predicting employment_growth on the
same held-out states -- an independent replication (different
ecosystem, different implementations) of R/27_ml_prediction.R and
R/28_neural_network.R's comparison. Not a causal claim; see those
files' headers for why.

The random forest's hyperparameters are chosen by grouped cross-
validation on the training states (minwage.ml.experiment), not fixed
by hand, and its test-set performance is reported with a cluster
bootstrap confidence interval and a permutation importance breakdown
rather than a single point estimate -- see that module's docstring for
why each resampling scheme is grouped/clustered by state.

Run from the python/ directory, after the R pipeline has produced
data/processed/ml_panel.csv (`make pipeline` or at least
`Rscript ../R/27_ml_prediction.R`), with the package installed
(`pip install -e ".[dev]"` -- see python/README.md):

    python train.py
"""

from pathlib import Path

import pandas as pd

from minwage.data.loaders import feature_matrix, load_ml_panel, one_hot_region
from minwage.ml.baselines import LinearRegression
from minwage.ml.evaluation import r_squared, rmse
from minwage.ml.experiment import bootstrap_metric_ci, grid_search_cv, permutation_importance
from minwage.ml.gradient_boosting import GradientBoostedTrees
from minwage.ml.neural_network import train_neural_network
from minwage.ml.random_forest import BaggedTrees, RandomForest
from minwage.ml.splitting import group_train_test_split

RESULTS_DIR = Path(__file__).resolve().parent / "results"

# Kept small on purpose: grid_search_cv refits a model per combination per
# fold, and RandomForest is the slowest estimator here. n_trees is fixed
# low during the search and raised for the final refit below -- tree
# count barely affects which max_depth/min_samples_leaf wins, so there's
# no need to pay full cost while searching.
RANDOM_FOREST_SEARCH_GRID = {
    "n_trees": [50],
    "max_depth": [3, 4, 5],
    "min_samples_leaf": [5, 10],
}
FINAL_N_TREES = 200


def main() -> pd.DataFrame:
    panel = one_hot_region(load_ml_panel())
    train_df, test_df = group_train_test_split(panel, test_frac=0.2, seed=1)

    feature_names = list(feature_matrix(train_df).columns)
    X_train = feature_matrix(train_df).to_numpy(dtype=float)
    X_test = feature_matrix(test_df).to_numpy(dtype=float)
    y_train = train_df["employment_growth"].to_numpy(dtype=float)
    y_test = test_df["employment_growth"].to_numpy(dtype=float)
    groups_train = train_df["state"].to_numpy()
    groups_test = test_df["state"].to_numpy()

    linear = LinearRegression().fit(X_train, y_train)
    linear_pred = linear.predict(X_test)

    bagged = BaggedTrees(n_trees=25, max_depth=4, min_samples_leaf=5, mtry=3, seed=1).fit(X_train, y_train)
    bagged_pred = bagged.predict(X_test)

    # Random forest's max_depth/min_samples_leaf are chosen by grouped
    # cross-validation on the training states, not fixed by hand -- the
    # test states stay untouched until the final evaluation below.
    best_params, search_results = grid_search_cv(
        RandomForest, RANDOM_FOREST_SEARCH_GRID, X_train, y_train, groups_train, n_splits=5, seed=1
    )
    forest = RandomForest(
        n_trees=FINAL_N_TREES,
        max_depth=int(best_params["max_depth"]),
        min_samples_leaf=int(best_params["min_samples_leaf"]),
        seed=1,
    ).fit(X_train, y_train)
    forest_pred = forest.predict(X_test)

    boosted = GradientBoostedTrees(n_estimators=150, learning_rate=0.05, max_depth=2, min_samples_leaf=5)
    boosted.fit(X_train, y_train)
    boosted_pred = boosted.predict(X_test)

    nn_pred, _ = train_neural_network(X_train, y_train, X_test, hidden_dim=8, epochs=300, lr=0.01, seed=1)

    predictions = {
        "linear_baseline": linear_pred,
        "bagged_trees": bagged_pred,
        "random_forest": forest_pred,
        "gradient_boosting": boosted_pred,
        "neural_network": nn_pred,
    }
    results = pd.DataFrame(
        {
            "model": list(predictions.keys()),
            "rmse": [rmse(y_test, pred) for pred in predictions.values()],
            "r_squared": [r_squared(y_test, pred) for pred in predictions.values()],
        }
    )

    # Uncertainty and interpretation for the tuned random forest only --
    # it's the estimator the grid search above actually selected
    # hyperparameters for, so it's the one worth a confidence interval
    # and a feature-importance breakdown.
    rmse_ci = bootstrap_metric_ci(y_test, forest_pred, groups_test, metric_fn=rmse, n_boot=1000, seed=1)
    r_squared_ci = bootstrap_metric_ci(y_test, forest_pred, groups_test, metric_fn=r_squared, n_boot=1000, seed=1)
    importance = permutation_importance(forest, X_test, y_test, feature_names, n_repeats=30, seed=1)

    RESULTS_DIR.mkdir(exist_ok=True)
    results.to_csv(RESULTS_DIR / "comparison.csv", index=False)
    search_results.to_csv(RESULTS_DIR / "random_forest_grid_search.csv", index=False)
    importance.to_csv(RESULTS_DIR / "random_forest_permutation_importance.csv", index=False)
    pd.DataFrame(
        [
            {"metric": "rmse", **{k: v for k, v in rmse_ci.items() if k != "boot_stats"}},
            {"metric": "r_squared", **{k: v for k, v in r_squared_ci.items() if k != "boot_stats"}},
        ]
    ).to_csv(RESULTS_DIR / "random_forest_bootstrap_ci.csv", index=False)

    print(f"Train states: {train_df['state'].nunique()} | Test states: {test_df['state'].nunique()}")
    print(results.to_string(index=False))
    print(f"\nRandom forest selected by grouped CV: {best_params}")
    print(
        f"Random forest test RMSE: {rmse_ci['point_estimate']:.4f} "
        f"[{rmse_ci['lower']:.4f}, {rmse_ci['upper']:.4f}] (95% cluster bootstrap CI)"
    )
    print(
        f"Random forest test R^2: {r_squared_ci['point_estimate']:.4f} "
        f"[{r_squared_ci['lower']:.4f}, {r_squared_ci['upper']:.4f}] (95% cluster bootstrap CI)"
    )
    print("\nPermutation importance (RMSE increase when a feature is shuffled):")
    print(importance.to_string(index=False))
    return results


if __name__ == "__main__":
    main()
