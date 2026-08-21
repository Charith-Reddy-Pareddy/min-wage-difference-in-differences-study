library(testthat)
source("../R/06_slr_mlr.R")

test_that("census_region covers every state in the treatment table and errors on an unknown one", {
  source("../R/01_treatment_classification.R")
  treatment_table <- load_treatment_table("../data/treatment_classification.csv")
  expect_length(census_region(treatment_table$state), nrow(treatment_table))
  expect_error(census_region("Nowhere"), "No Census region")
})

test_that("period_log_change computes mean(log(post)) - mean(log(pre))", {
  quarter <- as.Date(c("2019-01-01", "2019-04-01", "2021-01-01", "2021-04-01"))
  value <- c(100, 100, 110, 110)
  result <- period_log_change(
    value, quarter,
    pre_start = as.Date("2019-01-01"), pre_end = as.Date("2020-10-01"),
    post_start = as.Date("2021-01-01"), post_end = as.Date("2022-10-01")
  )
  expect_equal(result, log(110) - log(100), tolerance = 1e-9)
})

test_that("period_log_change errors on an empty window instead of returning NaN silently", {
  quarter <- as.Date(c("2021-01-01", "2021-04-01"))
  value <- c(110, 110)
  expect_error(
    period_log_change(
      value, quarter,
      pre_start = as.Date("2019-01-01"), pre_end = as.Date("2020-10-01"),
      post_start = as.Date("2021-01-01"), post_end = as.Date("2022-10-01")
    ),
    "Empty pre or post window"
  )
})

test_that("build_state_level_data joins treatment status and region onto the computed changes", {
  quarters <- rep(seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter"), times = 2)
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Florida"), each = 16),
    quarter = quarters,
    employment_food_service = 100 * exp(as.numeric(quarter - min(quarter)) / 3650),
    employment_retail = 200 * exp(as.numeric(quarter - min(quarter)) / 3650),
    gdp = 1000 * exp(as.numeric(quarter - min(quarter)) / 3650),
    population = 5000 * exp(as.numeric(quarter - min(quarter)) / 3650)
  )
  treatment_table <- tibble::tibble(
    state = c("California", "Florida"),
    group = c("treated", "excluded"),
    increase = c(1.00, 1.44)
  )

  result <- build_state_level_data(fred_panel, treatment_table)
  expect_equal(nrow(result), 2)
  expect_equal(result$treated[result$state == "California"], 1)
  expect_equal(result$treated[result$state == "Florida"], 0)
  expect_equal(result$region[result$state == "California"], "West")
  expect_equal(result$region[result$state == "Florida"], "South")
  expect_true(all(result$log_change_food_service > 0)) # employment trends up in this synthetic series
})

test_that("fit_slr uses only treated states", {
  state_level <- tibble::tibble(
    state = c("A", "B", "C"),
    treated = c(1, 1, 0),
    increase = c(0.5, 1.0, 2.0),
    log_change_food_service = c(0.01, 0.02, 0.5) # state C is an outlier that should be excluded
  )
  model <- fit_slr(state_level, "log_change_food_service")
  expect_equal(nrow(model$model), 2)
})

test_that("fit_mlr drops the 'excluded' group and keeps treated + control", {
  state_level <- tibble::tibble(
    state = c("A", "B", "C", "D"),
    group = c("treated", "control", "control", "excluded"),
    treated = c(1, 0, 0, 1),
    gdp_growth = c(0.01, 0.01, 0.02, 0.5), # state D is an outlier that should be excluded
    pop_growth = c(0.01, 0.01, 0.02, 0.5),
    region = c("West", "South", "South", "Northeast"),
    log_change_food_service = c(0.01, 0.02, 0.015, 0.9)
  )
  model <- fit_mlr(state_level, "log_change_food_service")
  expect_equal(nrow(model$model), 3)
  expect_false("D" %in% rownames(model$model))
})
