import numpy as np

from minwage.causal_ml.heterogeneity import fit_r_learner_cate, predict_cate


def test_recovers_a_known_linear_heterogeneity_slope():
    rng = np.random.default_rng(0)
    n = 4000
    X = rng.normal(size=(n, 1))
    true_intercept, true_slope = 1.0, 2.0
    tau = true_intercept + true_slope * X[:, 0]

    # y_resid = tau(X) * d_resid + noise, exactly the R-learner's assumed
    # relationship after partialling out X from Y and D.
    d_resid = rng.normal(scale=1.0, size=n)
    y_resid = tau * d_resid + rng.normal(scale=0.05, size=n)

    coef = fit_r_learner_cate(X, y_resid, d_resid)

    assert abs(coef[0] - true_intercept) < 0.1
    assert abs(coef[1] - true_slope) < 0.1


def test_predict_cate_matches_the_fitted_coefficients():
    coef = np.array([1.0, 2.0, -0.5])
    X = np.array([[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]])

    predicted = predict_cate(coef, X)

    assert np.allclose(predicted, [1.0, 3.0, 0.5])


def test_rows_with_near_zero_d_resid_do_not_dominate_the_fit():
    rng = np.random.default_rng(1)
    n = 2000
    X = rng.normal(size=(n, 1))
    true_intercept, true_slope = 0.5, -1.0
    tau = true_intercept + true_slope * X[:, 0]

    d_resid = rng.normal(scale=1.0, size=n)
    y_resid = tau * d_resid + rng.normal(scale=0.05, size=n)

    # A handful of rows with a near-zero d_resid but wild y_resid --
    # should barely move the fit since their weight is tiny.
    d_resid[:5] = 1e-10
    y_resid[:5] = 1e6

    coef = fit_r_learner_cate(X, y_resid, d_resid)

    assert abs(coef[0] - true_intercept) < 0.1
    assert abs(coef[1] - true_slope) < 0.1
