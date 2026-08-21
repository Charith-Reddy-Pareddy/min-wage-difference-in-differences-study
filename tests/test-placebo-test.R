library(testthat)
source("../R/10_placebo_test.R")

make_synthetic_inputs <- function() {
  quarters <- seq(as.Date("2015-01-01"), as.Date("2022-10-01"), by = "quarter")
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas"), each = length(quarters)),
    quarter = rep(quarters, times = 2),
    employment_food_service = rep(100, 2 * length(quarters)),
    employment_retail = rep(200, 2 * length(quarters)),
    gdp = rep(1000 * 1.005^seq_along(quarters), times = 2),
    population = rep(5000 * 1.001^seq_along(quarters), times = 2)
  )
  treatment_table <- tibble::tibble(state = c("California", "Texas"), group = c("treated", "control"), increase = c(1, 0))
  exposure_table <- tibble::tibble(
    state = rep(c("California", "Texas"), each = 2),
    industry = rep(c("food_service", "retail"), times = 2),
    exposure_share_125 = c(0.4, 0.3, 0.2, 0.15)
  )
  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("build_placebo_panel restricts to the pre-COVID placebo window", {
  inputs <- make_synthetic_inputs()
  panel <- build_placebo_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                "food_service", "employment_food_service")
  expect_true(all(panel$quarter >= PLACEBO_WINDOW_START))
  expect_true(all(panel$quarter <= PLACEBO_WINDOW_END))
  expect_true(max(panel$quarter) < as.Date("2020-01-01")) # excludes COVID entirely
  expect_true(max(panel$quarter) < as.Date("2021-01-01")) # excludes real treatment entirely
})

test_that("build_placebo_panel assigns placebo_treated_post around the false date, not the real one", {
  inputs <- make_synthetic_inputs()
  panel <- build_placebo_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                "retail", "employment_retail")

  ca_before_false_date <- panel %>% filter(state == "California", quarter < PLACEBO_DATE)
  ca_after_false_date <- panel %>% filter(state == "California", quarter >= PLACEBO_DATE)
  tx_after_false_date <- panel %>% filter(state == "Texas", quarter >= PLACEBO_DATE)

  expect_true(all(ca_before_false_date$placebo_treated_post == 0))
  expect_true(all(ca_after_false_date$placebo_treated_post == 1))
  expect_true(all(tx_after_false_date$placebo_treated_post == 0)) # control, never "treated"
})

test_that("fit_placebo_model finds no effect when none was built into the synthetic data", {
  inputs <- make_synthetic_inputs()
  # Give both states an identical trend and nothing special at the false
  # date -- the placebo coefficient should come back at (numerically) zero.
  quarters <- unique(inputs$fred_panel$quarter)
  quarter_index <- as.integer(factor(inputs$fred_panel$quarter, levels = quarters))
  inputs$fred_panel$employment_food_service <- 100 * 1.01^quarter_index

  panel <- build_placebo_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                "food_service", "employment_food_service")
  model <- fit_placebo_model(panel)
  expect_equal(unname(coef(model)["placebo_treated_post"]), 0, tolerance = 1e-8)
})
