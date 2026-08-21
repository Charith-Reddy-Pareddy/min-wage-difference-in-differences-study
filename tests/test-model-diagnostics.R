library(testthat)
source("../R/12_model_diagnostics.R")

test_that("save_model_a_diagnostics returns well-formed summary stats and writes a plot file", {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas"), each = length(quarters)),
    quarter = rep(quarters, times = 2),
    employment_food_service = 100 * 1.01^rep(seq_along(quarters), times = 2) *
      exp(rnorm(2 * length(quarters), sd = 0.01)),
    employment_retail = 200,
    gdp = rep(1000 * 1.005^seq_along(quarters), times = 2),
    population = rep(5000 * 1.001^seq_along(quarters), times = 2)
  )
  treatment_table <- tibble::tibble(state = c("California", "Texas"), group = c("treated", "control"), increase = c(1, 0))
  exposure_table <- tibble::tibble(
    state = rep(c("California", "Texas"), each = 2),
    industry = rep(c("food_service", "retail"), times = 2),
    exposure_share_125 = c(0.4, 0.3, 0.2, 0.15)
  )
  panel <- build_panel(fred_panel, treatment_table, exposure_table, "food_service", "employment_food_service")

  out_dir <- withr::local_tempdir()
  result <- save_model_a_diagnostics(panel, "food_service", out_dir)

  expect_equal(result$n_obs, nrow(panel))
  expect_equal(result$influential_threshold, 4 / nrow(panel))
  expect_true(result$max_cooks_distance >= 0)
  expect_true(file.exists(file.path(out_dir, "model_a_diagnostics_food_service.png")))
})
