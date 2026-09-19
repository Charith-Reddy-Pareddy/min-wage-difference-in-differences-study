"""Predictive comparison, Python side: linear baseline, hand-rolled
bagged trees, hand-rolled random forest, and a PyTorch feedforward net,
all predicting employment_growth on the same held-out states -- an
independent replication (different ecosystem, different
implementations) of R/27_ml_prediction.R and R/28_neural_network.R's
comparison. Not a causal claim; see those files' headers for why.

Run from the python/ directory, after the R pipeline has produced
data/processed/ml_panel.csv (`make pipeline` or at least
`Rscript ../R/27_ml_prediction.R`):

    .venv/bin/python train.py
"""

from pathlib import Path

import pandas as pd

from src.data import feature_matrix, load_ml_panel, one_hot_region
from src.linear_model import LinearRegression
from src.metrics import r_squared, rmse
from src.neural_net import train_neural_network
from src.split import group_train_test_split
from src.tree import BaggedTrees, RandomForest

RESULTS_DIR = Path(__file__).resolve().parent / "results"


def main() -> pd.DataFrame:
    panel = one_hot_region(load_ml_panel())
    train_df, test_df = group_train_test_split(panel, test_frac=0.2, seed=1)

    X_train = feature_matrix(train_df).to_numpy(dtype=float)
    X_test = feature_matrix(test_df).to_numpy(dtype=float)
    y_train = train_df["employment_growth"].to_numpy(dtype=float)
    y_test = test_df["employment_growth"].to_numpy(dtype=float)

    linear = LinearRegression().fit(X_train, y_train)
    linear_pred = linear.predict(X_test)

    bagged = BaggedTrees(n_trees=25, max_depth=4, min_samples_leaf=5, mtry=3, seed=1).fit(X_train, y_train)
    bagged_pred = bagged.predict(X_test)

    forest = RandomForest(n_trees=100, max_depth=4, min_samples_leaf=5, seed=1).fit(X_train, y_train)
    forest_pred = forest.predict(X_test)

    nn_pred, _ = train_neural_network(X_train, y_train, X_test, hidden_dim=8, epochs=300, lr=0.01, seed=1)

    results = pd.DataFrame(
        {
            "model": ["linear_baseline", "bagged_trees", "random_forest", "neural_network"],
            "rmse": [
                rmse(y_test, linear_pred), rmse(y_test, bagged_pred), rmse(y_test, forest_pred), rmse(y_test, nn_pred)
            ],
            "r_squared": [
                r_squared(y_test, linear_pred),
                r_squared(y_test, bagged_pred),
                r_squared(y_test, forest_pred),
                r_squared(y_test, nn_pred),
            ],
        }
    )

    RESULTS_DIR.mkdir(exist_ok=True)
    results.to_csv(RESULTS_DIR / "comparison.csv", index=False)
    print(f"Train states: {train_df['state'].nunique()} | Test states: {test_df['state'].nunique()}")
    print(results.to_string(index=False))
    return results


if __name__ == "__main__":
    main()
