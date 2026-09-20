import numpy as np

from minwage.ml.random_forest import BaggedTrees, RandomForest, RegressionTree


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


def test_random_forest_recovers_the_step_function_and_returns_one_prediction_per_row():
    rng = np.random.default_rng(2)
    n = 300
    x = rng.uniform(-1, 1, size=(n, 1))
    y = np.where(x[:, 0] > 0, 10.0, -10.0) + rng.normal(scale=0.1, size=n)

    model = RandomForest(n_trees=10, max_depth=3, min_samples_leaf=5, seed=1).fit(x, y)
    test_x = np.array([[-0.9], [-0.5], [0.5], [0.9]])
    predictions = model.predict(test_x)

    assert len(predictions) == 4
    assert all(p < 0 for p in predictions[:2])
    assert all(p > 0 for p in predictions[2:])


def test_random_forest_mtry_resamples_features_at_every_split_not_once_per_tree():
    # Two useless columns and one useful one; forcing mtry=1 means most
    # individual splits won't even see the useful column, but with a
    # FRESH draw at every node (not once per tree, unlike BaggedTrees),
    # a deep-enough tree still has many chances to find it somewhere in
    # its structure -- the ensemble should still recover the pattern.
    rng = np.random.default_rng(6)
    n = 400
    x = rng.uniform(-1, 1, size=(n, 3))
    y = np.where(x[:, 0] > 0, 5.0, -5.0) + rng.normal(scale=0.1, size=n)

    model = RandomForest(n_trees=50, max_depth=4, min_samples_leaf=5, mtry=1, seed=1).fit(x, y)
    predictions = model.predict(np.array([[-0.8, 0.0, 0.0], [0.8, 0.0, 0.0]]))

    assert predictions[0] < 0
    assert predictions[1] > 0


def test_random_forest_runs_with_default_mtry_on_many_features():
    # Smoke test for the default-mtry path (max(1, n_features // 3)):
    # with 9 features and no mtry passed, this should neither error out
    # nor treat mtry as 0 (which would leave _best_split nothing to
    # search and every row would fall into a single leaf).
    rng = np.random.default_rng(9)
    x = rng.uniform(-1, 1, size=(50, 9))
    y = rng.normal(size=50)

    model = RandomForest(n_trees=5, seed=1).fit(x, y)
    predictions = model.predict(x)

    assert predictions.shape == (50,)
    assert np.all(np.isfinite(predictions))
