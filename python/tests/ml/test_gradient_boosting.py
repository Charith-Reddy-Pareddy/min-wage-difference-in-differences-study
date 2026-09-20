import numpy as np

from minwage.ml.gradient_boosting import GradientBoostedTrees


def test_gradient_boosted_trees_recovers_a_clean_step_function():
    rng = np.random.default_rng(2)
    n = 300
    x = rng.uniform(-1, 1, size=(n, 1))
    y = np.where(x[:, 0] > 0, 10.0, -10.0) + rng.normal(scale=0.1, size=n)

    model = GradientBoostedTrees(n_estimators=100, learning_rate=0.1, max_depth=2, min_samples_leaf=5)
    model.fit(x, y)
    predictions = model.predict(np.array([[-0.9], [-0.5], [0.5], [0.9]]))

    assert len(predictions) == 4
    assert all(p < 0 for p in predictions[:2])
    assert all(p > 0 for p in predictions[2:])


def test_gradient_boosted_trees_training_error_shrinks_as_estimators_are_added():
    # The defining behavior of boosting: each additional tree is fit to
    # the residuals of everything before it, so training error should
    # fall (not necessarily monotonically per-tree, but clearly overall)
    # as more estimators are added.
    rng = np.random.default_rng(11)
    n = 200
    x = rng.uniform(-1, 1, size=(n, 2))
    y = 3 * x[:, 0] - 2 * x[:, 1] + rng.normal(scale=0.1, size=n)

    few = GradientBoostedTrees(n_estimators=3, learning_rate=0.1, max_depth=2, min_samples_leaf=5).fit(x, y)
    many = GradientBoostedTrees(n_estimators=100, learning_rate=0.1, max_depth=2, min_samples_leaf=5).fit(x, y)

    error_few = np.mean((y - few.predict(x)) ** 2)
    error_many = np.mean((y - many.predict(x)) ** 2)
    assert error_many < error_few


def test_gradient_boosted_trees_predict_matches_fit_incrementally():
    # predict() re-derives the running total from init_value + each
    # tree's contribution -- confirm that matches what fit() actually
    # converged to, not a separately-drifted implementation.
    rng = np.random.default_rng(12)
    x = rng.uniform(-1, 1, size=(100, 1))
    y = 2 * x[:, 0] + rng.normal(scale=0.05, size=100)

    model = GradientBoostedTrees(n_estimators=20, learning_rate=0.1, max_depth=2, min_samples_leaf=5).fit(x, y)

    manual = np.full(len(x), model.init_value)
    for tree in model.trees:
        manual = manual + model.learning_rate * tree.predict(x)

    assert np.allclose(model.predict(x), manual)
