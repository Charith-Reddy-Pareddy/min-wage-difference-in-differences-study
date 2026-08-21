library(testthat)
source("../R/05_exposure_validation.R")

test_that("qcew_wage_ratio converts weekly wage to an hourly proxy over minimum wage", {
  # $800/week -> $20/hour proxy; min wage $10 -> ratio 2.0
  expect_equal(qcew_wage_ratio(800, 10), 2.0)
})

test_that("qcew_correlation_check finds the expected negative relationship", {
  # Construct a clean case: as exposure share rises, the wage ratio
  # falls -- the relationship the check is designed to detect.
  exposure <- tibble::tibble(
    state = rep(c("A", "B", "C", "D"), each = 1),
    industry = "food_service",
    exposure_share_15 = c(0.1, 0.3, 0.5, 0.7)
  )
  qcew_wages <- tibble::tibble(
    state = c("A", "B", "C", "D"),
    industry = "food_service",
    qcew_wage_ratio = c(2.0, 1.6, 1.2, 0.8)
  )
  result <- qcew_correlation_check(exposure, qcew_wages)
  expect_equal(result$correlation, -1, tolerance = 1e-6)
  expect_false(result$flagged)
})

test_that("qcew_correlation_check flags a weak or wrong-signed relationship", {
  exposure <- tibble::tibble(
    state = c("A", "B", "C", "D"),
    industry = "retail",
    exposure_share_15 = c(0.1, 0.3, 0.5, 0.7)
  )
  qcew_wages <- tibble::tibble(
    state = c("A", "B", "C", "D"),
    industry = "retail",
    qcew_wage_ratio = c(1.0, 1.0, 1.0, 1.0001) # essentially no relationship
  )
  result <- qcew_correlation_check(exposure, qcew_wages, flag_threshold = -0.3)
  expect_true(result$flagged)
})

test_that("exposure_distribution_check reports food service consistently higher when it is", {
  exposure <- tibble::tibble(
    state = rep(c("A", "B", "C"), each = 2),
    industry = rep(c("food_service", "retail"), 3),
    exposure_share_15 = c(0.5, 0.2, 0.6, 0.3, 0.55, 0.25)
  )
  result <- exposure_distribution_check(exposure)
  expect_equal(result$n_states, 3)
  expect_equal(result$n_food_higher, 3)
  expect_gt(result$mean_food_service, result$mean_retail)
})
