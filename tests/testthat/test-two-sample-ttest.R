library(testthat)
source("../../R/13_two_sample_ttest.R")

test_that("compute_pre_period_trend is log(2020Q4) - log(2019Q1), per state", {
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas"), each = 2),
    quarter = rep(c(as.Date("2019-01-01"), as.Date("2020-10-01")), times = 2),
    employment_food_service = c(100, 110, 100, 95)
  )
  result <- compute_pre_period_trend(fred_panel, "employment_food_service")
  expect_equal(result$pre_trend[result$state == "California"], log(110) - log(100), tolerance = 1e-9)
  expect_equal(result$pre_trend[result$state == "Texas"], log(95) - log(100), tolerance = 1e-9)
})

test_that("compute_pre_period_trend returns NA rather than erroring on a missing quarter", {
  fred_panel <- tibble::tibble(
    state = "California",
    quarter = as.Date("2019-01-01"),
    employment_food_service = 100
  )
  result <- compute_pre_period_trend(fred_panel, "employment_food_service")
  expect_true(is.na(result$pre_trend))
})

test_that("two_sample_trend_ttest excludes the 'excluded' group", {
  trend <- tibble::tibble(
    state = c("A", "B", "C", "D", "E", "F"),
    # E is an "excluded"-group outlier huge enough to shift the test
    # statistic noticeably if it leaked into either group.
    pre_trend = c(0.01, 0.02, 0.015, -0.01, 5, -0.005)
  )
  treatment_table <- tibble::tibble(
    state = c("A", "B", "C", "D", "E", "F"),
    group = c("treated", "treated", "treated", "control", "excluded", "control")
  )
  test <- two_sample_trend_ttest(trend, treatment_table)

  # Same test run directly on the pre-filtered subset should match exactly.
  filtered <- trend %>%
    dplyr::inner_join(treatment_table, by = "state") %>%
    dplyr::filter(group %in% c("treated", "control"))
  expected <- stats::t.test(pre_trend ~ group, data = filtered)
  expect_equal(unname(test$statistic), unname(expected$statistic))
})

test_that("two_sample_trend_ttest finds a clear difference when one is built into the data", {
  # A little noise, not just a repeated constant -- t.test() errors
  # outright ("data are essentially constant") on zero-variance groups.
  set.seed(1)
  trend <- tibble::tibble(
    state = paste0("S", 1:10),
    pre_trend = c(0.05 + rnorm(5, sd = 0.001), -0.05 + rnorm(5, sd = 0.001))
  )
  treatment_table <- tibble::tibble(
    state = paste0("S", 1:10),
    group = rep(c("treated", "control"), each = 5)
  )
  test <- two_sample_trend_ttest(trend, treatment_table)
  expect_true(test$p.value < 0.001)
})

test_that("descriptive_statistics_table groups by treatment group, industry, and increase type", {
  trend_by_industry <- tibble::tibble(
    state = rep(c("A", "B"), each = 2),
    industry = rep(c("food_service", "retail"), times = 2),
    pre_trend = c(0.01, 0.02, 0.03, 0.04)
  )
  treatment_table <- tibble::tibble(
    state = c("A", "B"),
    group = c("treated", "control"),
    increase_type = c("legislation", "no_change")
  )
  result <- descriptive_statistics_table(trend_by_industry, treatment_table)
  expect_true(all(c("group", "industry", "increase_type", "n", "mean_pre_trend", "sd_pre_trend") %in% names(result)))
  expect_equal(nrow(result), 4) # 2 states x 2 industries
})
