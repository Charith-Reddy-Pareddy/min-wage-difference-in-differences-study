library(testthat)
source("../R/27_ml_prediction.R")

test_that("rmse matches a hand-computed example", {
  actual <- c(1, 2, 3, 4)
  predicted <- c(1, 2, 3, 6)
  expect_equal(rmse(actual, predicted), sqrt(mean(c(0, 0, 0, 4))))
})

test_that("r_squared is 1 for a perfect prediction and 0 for predicting the mean", {
  actual <- c(1, 2, 3, 4, 5)
  expect_equal(r_squared(actual, actual), 1)
  expect_equal(r_squared(actual, rep(mean(actual), length(actual))), 0)
})

make_multi_state_panel <- function(n_states = 10) {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- paste0("State", seq_len(n_states))
  panel <- tibble::tibble(
    state = rep(states, each = length(quarters)),
    quarter = rep(quarters, times = n_states)
  )
  panel
}

test_that("split_by_state keeps every quarter for a given state on one side of the split", {
  panel <- make_multi_state_panel(10)
  split <- split_by_state(panel, test_frac = 0.3, seed = 1)

  expect_equal(length(intersect(split$train$state, split$test$state)), 0)
  expect_equal(nrow(split$train) + nrow(split$test), nrow(panel))
})

test_that("split_by_state produces roughly the requested fraction of states", {
  panel <- make_multi_state_panel(10)
  split <- split_by_state(panel, test_frac = 0.3, seed = 1)

  expect_equal(length(unique(split$test$state)), 3)
  expect_equal(length(unique(split$train$state)), 7)
})

test_that("fit_bagged_trees recovers a clear nonlinear split better than a coin flip", {
  # y is a step function of x -- a single-split decision boundary, not a
  # subtle pattern -- so a working bagged-tree ensemble should recover it
  # cleanly on held-out data, while getting the sign backwards everywhere
  # would indicate the ensembling/prediction logic is broken.
  set.seed(42)
  n <- 400
  train <- tibble::tibble(
    x = runif(n, -1, 1),
    noise = rnorm(n, sd = 0.5),
    y = ifelse(x > 0, 10, -10) + noise
  )
  test <- tibble::tibble(x = c(-0.8, -0.5, 0.5, 0.8))

  model <- fit_bagged_trees(train, predictors = "x", response = "y", n_trees = 15, seed = 1)
  preds <- predict(model, test)

  expect_length(preds, 4)
  expect_true(all(preds[1:2] < 0))
  expect_true(all(preds[3:4] > 0))
})

test_that("fit_random_forest recovers a clear nonlinear split on held-out data", {
  # Same synthetic step-function setup as the bagged-trees test above --
  # a working random forest should recover it too, and this also
  # exercises the actual randomForest-package call path (formula
  # construction, mtry passthrough) rather than just the hand-rolled
  # ensemble.
  set.seed(42)
  n <- 400
  train <- tibble::tibble(
    x = runif(n, -1, 1),
    noise = rnorm(n, sd = 0.5),
    y = ifelse(x > 0, 10, -10) + noise
  )
  test <- tibble::tibble(x = c(-0.8, -0.5, 0.5, 0.8))

  model <- fit_random_forest(train, predictors = "x", response = "y", n_trees = 50, seed = 1)
  preds <- predict(model, newdata = test)

  expect_length(preds, 4)
  expect_true(all(preds[1:2] < 0))
  expect_true(all(preds[3:4] > 0))
})

test_that("fit_random_forest returns an actual randomForest object, not the hand-rolled ensemble", {
  # Not a claim that predictions differ from fit_bagged_trees by any
  # particular amount -- just that fit_random_forest genuinely calls into
  # the randomForest package rather than silently reusing bagged_trees.
  set.seed(1)
  train <- tibble::tibble(
    x1 = rnorm(50), x2 = rnorm(50),
    y = 2 * rnorm(50)
  )
  rf <- fit_random_forest(train, c("x1", "x2"), "y", n_trees = 10, seed = 1)
  expect_s3_class(rf, "randomForest")
})

test_that("build_ml_panel stacks food_service and retail with an industry column and region attached", {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas"), each = length(quarters)),
    quarter = rep(quarters, times = 2),
    employment_food_service = rep(100, 2 * length(quarters)),
    employment_retail = rep(200, 2 * length(quarters)),
    gdp = rep(1000 * 1.005^seq_along(quarters), times = 2),
    population = rep(5000 * 1.001^seq_along(quarters), times = 2)
  )
  treatment_table <- tibble::tibble(
    state = c("California", "Texas"), group = c("treated", "control"), increase = c(1.00, 0)
  )
  exposure_table <- tibble::tibble(
    state = rep(c("California", "Texas"), each = 2),
    industry = rep(c("food_service", "retail"), times = 2),
    exposure_share_125 = c(0.4, 0.3, 0.2, 0.15)
  )

  panel <- build_ml_panel(fred_panel, treatment_table, exposure_table)

  expect_setequal(unique(panel$industry), c("food_service", "retail"))
  expect_equal(unique(panel$region[panel$state == "California"]), "West")
  expect_equal(unique(panel$region[panel$state == "Texas"]), "South")
  # Flat employment in the fixture -> zero growth everywhere, not NA.
  expect_true("employment_growth" %in% names(panel))
  expect_true(all(panel$employment_growth == 0))
})

test_that("build_ml_panel's employment_growth tracks the outcome column, not log_employment's level", {
  # A state whose employment level is much larger throughout should not
  # get a larger growth value just from its level -- growth here is
  # identical for both states (5% per data point) despite very different
  # levels, which is exactly why growth (not level) is the right target
  # for predicting an unseen state (see file header).
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  quarter_index <- as.integer(factor(quarters))
  fred_panel <- tibble::tibble(
    state = rep(c("Wyoming", "California"), each = length(quarters)),
    quarter = rep(quarters, times = 2),
    employment_food_service = c(10 * 1.05^quarter_index, 10000 * 1.05^quarter_index),
    employment_retail = c(20 * 1.05^quarter_index, 20000 * 1.05^quarter_index),
    gdp = rep(1000 * 1.005^seq_along(quarters), times = 2),
    population = rep(5000 * 1.001^seq_along(quarters), times = 2)
  )
  treatment_table <- tibble::tibble(
    state = c("Wyoming", "California"), group = c("treated", "control"), increase = c(1.00, 0)
  )
  exposure_table <- tibble::tibble(
    state = rep(c("Wyoming", "California"), each = 2),
    industry = rep(c("food_service", "retail"), times = 2),
    exposure_share_125 = c(0.4, 0.3, 0.2, 0.15)
  )

  panel <- build_ml_panel(fred_panel, treatment_table, exposure_table)
  expect_equal(
    panel$employment_growth[panel$state == "Wyoming"],
    panel$employment_growth[panel$state == "California"],
    tolerance = 1e-9
  )
})
