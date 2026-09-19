import numpy as np

from src.tree import BaggedTrees, RegressionTree


def test_regression_tree_recovers_a_clean_step_function():
    rng = np.random.default_rng(1)
    n = 300
    x = rng.uniform(-1, 1, size=(n, 1))
    y = np.where(x[:, 0] > 0, 10.0, -10.0) + rng.normal(scale=0.1, size=n)

    tree = RegressionTree(max_depth=3, min_samples_leaf=5).fit(x, y)
    predictions = tree.predict(np.array([[-0.8], [-0.2], [0.2], [0.8]]))

    assert predictions[0] < 0 and predictions[1] < 0
    assert predictions[2] > 0 and predictions[3] > 0


def test_regression_tree_leaf_value_is_the_mean_of_its_training_rows():
    x = np.array([[1.0], [1.0], [1.0]])
    y = np.array([2.0, 4.0, 6.0])

    tree = RegressionTree(max_depth=3, min_samples_leaf=1).fit(x, y)
    # A single distinct x value -> no split is possible -> one leaf, the mean.
    assert tree.predict(np.array([[1.0]]))[0] == 4.0


def test_bagged_trees_recovers_the_step_function_and_returns_one_prediction_per_row():
    rng = np.random.default_rng(2)
    n = 300
    x = rng.uniform(-1, 1, size=(n, 1))
    y = np.where(x[:, 0] > 0, 10.0, -10.0) + rng.normal(scale=0.1, size=n)

    model = BaggedTrees(n_trees=10, max_depth=3, min_samples_leaf=5, seed=1).fit(x, y)
    test_x = np.array([[-0.9], [-0.5], [0.5], [0.9]])
    predictions = model.predict(test_x)

    assert len(predictions) == 4
    assert all(p < 0 for p in predictions[:2])
    assert all(p > 0 for p in predictions[2:])


def test_bagged_trees_mtry_uses_only_a_subset_of_features_per_tree():
    rng = np.random.default_rng(3)
    n = 200
    # Only column 0 carries signal; mtry=1 forces each tree to pick
    # either the useful or the useless column at random -- the ensemble
    # average should still recover the pattern.
    x = rng.uniform(-1, 1, size=(n, 2))
    y = np.where(x[:, 0] > 0, 5.0, -5.0) + rng.normal(scale=0.1, size=n)

    model = BaggedTrees(n_trees=30, max_depth=3, min_samples_leaf=5, mtry=1, seed=1).fit(x, y)
    predictions = model.predict(np.array([[-0.8, 0.0], [0.8, 0.0]]))

    assert predictions[0] < 0
    assert predictions[1] > 0
