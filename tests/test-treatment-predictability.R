library(testthat)
source("../R/30_treatment_predictability.R")

test_that("region_treatment_chisq excludes the 'excluded' group and cross-tabs region x group", {
  treatment_table <- tibble::tibble(
    state = c("California", "Texas", "New York", "Florida", "Vermont"),
    group = c("treated", "control", "treated", "control", "excluded")
  )
  result <- region_treatment_chisq(treatment_table)

  expect_equal(sum(result$table), 4) # Vermont (excluded) dropped
  expect_true(is.list(result$test))
  expect_true("p.value" %in% names(result$test))
})

test_that("pre_period_growth averages yoy growth over 2019-2020 only, per state", {
  quarters <- seq(as.Date("2018-01-01"), as.Date("2021-10-01"), by = "quarter")
  quarter_index <- as.integer(factor(quarters))
  fred_panel <- tibble::tibble(
    state = "California",
    quarter = quarters,
    gdp = 1000 * 1.01^quarter_index,
    population = 5000 * 1.001^quarter_index
  )
  result <- pre_period_growth(fred_panel)

  expect_equal(nrow(result), 1)
  expect_true(result$avg_gdp_growth > 0) # steady growth -> positive yoy growth throughout
  expect_equal(result$state, "California")
})

test_that("build_predictability_data joins growth and exposure onto treated/control states only", {
  quarters <- seq(as.Date("2018-01-01"), as.Date("2021-10-01"), by = "quarter")
  quarter_index <- as.integer(factor(quarters))
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas", "Vermont"), each = length(quarters)),
    quarter = rep(quarters, times = 3),
    gdp = rep(1000 * 1.01^quarter_index, times = 3),
    population = rep(5000 * 1.001^quarter_index, times = 3)
  )
  treatment_table <- tibble::tibble(
    state = c("California", "Texas", "Vermont"),
    group = c("treated", "control", "excluded")
  )
  exposure_table <- tibble::tibble(
    state = c("California", "Texas", "Vermont"),
    industry = "food_service",
    exposure_share_125 = c(0.4, 0.2, 0.3)
  )

  result <- build_predictability_data(fred_panel, treatment_table, exposure_table)

  expect_equal(nrow(result), 2) # Vermont (excluded) dropped
  expect_true(all(c("avg_gdp_growth", "avg_pop_growth", "exposure", "treated") %in% names(result)))
  expect_equal(result$treated[result$state == "California"], 1)
  expect_equal(result$treated[result$state == "Texas"], 0)
})

test_that("classification_accuracy computes a known confusion matrix and accuracy", {
  actual <- c(0, 0, 1, 1)
  predicted_prob <- c(0.2, 0.6, 0.7, 0.3) # predictions: 0, 1, 1, 0 at threshold 0.5
  result <- classification_accuracy(actual, predicted_prob, threshold = 0.5)

  expect_equal(result$accuracy, 0.5)
  expect_equal(unname(result$confusion["0", "0"]), 1)
  expect_equal(unname(result$confusion["1", "1"]), 1)
})

test_that("auc_mann_whitney is 1 for perfect separation and 0 for perfectly reversed predictions", {
  actual <- c(0, 0, 1, 1)
  expect_equal(auc_mann_whitney(actual, c(0.1, 0.2, 0.8, 0.9)), 1)
  expect_equal(auc_mann_whitney(actual, c(0.9, 0.8, 0.2, 0.1)), 0)
})

test_that("auc_mann_whitney is 0.5 when predictions carry no information", {
  actual <- c(0, 1, 0, 1)
  predicted_prob <- c(0.5, 0.5, 0.5, 0.5) # ties throughout -> no separating power
  expect_equal(auc_mann_whitney(actual, predicted_prob), 0.5)
})

test_that("fit_treatment_classifier fits a binomial GLM that converges given realistic overlap", {
  # Enough overlap between the two groups' predictor distributions that
  # the classes aren't perfectly separable -- a classic near-perfect-
  # separation setup (e.g. two non-overlapping predictor ranges) makes
  # glm() fail to converge, which is real statistical behavior, not a
  # bug in fit_treatment_classifier -- exactly why this fixture avoids it.
  set.seed(1)
  n <- 60
  data <- tibble::tibble(
    avg_gdp_growth = c(rnorm(n / 2, 0.01, 0.03), rnorm(n / 2, -0.01, 0.03)),
    avg_pop_growth = rnorm(n, 0, 0.01),
    exposure = rnorm(n, 0.3, 0.05),
    treated = rep(c(1, 0), each = n / 2)
  )
  model <- fit_treatment_classifier(data)

  expect_s3_class(model, "glm")
  expect_true(model$converged)
  expect_true("avg_gdp_growth" %in% names(coef(model)))
})
