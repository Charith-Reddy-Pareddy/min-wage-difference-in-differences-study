library(testthat)
source("../R/20_leave_one_out.R")

make_loo_inputs <- function() {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- c("California", "NewYork", "Texas", "Ohio")
  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::arrange(state, quarter) %>%
    dplyr::mutate(
      gdp = 1000 * 1.005^as.integer(factor(quarter)),
      population = 5000 * 1.001^as.integer(factor(quarter))
    )
  set.seed(111)
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  is_treated <- fred_panel$state %in% c("California", "NewYork")
  is_post <- fred_panel$quarter >= as.Date("2021-01-01")
  noise <- rnorm(nrow(fred_panel), sd = 0.01)
  fred_panel$employment_food_service <- 100 * exp(quarter_trend - 0.03 * is_treated * is_post + noise)

  treatment_table <- tibble::tibble(
    state = states, group = c("treated", "treated", "control", "control"), increase = c(1, 1, 0, 0)
  )
  exposure_table <- tibble::tibble(state = states, industry = "food_service", exposure_share_125 = c(0.2, 0.4, 0.3, 0.5))
  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("leave_one_out returns one row per treated state, not per all states", {
  inputs <- make_loo_inputs()
  result <- leave_one_out(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                           "food_service", "employment_food_service")
  expect_equal(nrow(result), 2) # 2 treated states: California, NewYork
  expect_setequal(result$dropped_state, c("California", "NewYork"))
})

test_that("dropping a treated state actually removes it from that refit's panel", {
  inputs <- make_loo_inputs()
  reduced_table <- inputs$treatment_table %>% dplyr::filter(state != "California")
  reduced_fred <- inputs$fred_panel %>% dplyr::filter(state != "California")
  panel <- build_panel(reduced_fred, reduced_table, inputs$exposure_table, "food_service", "employment_food_service")
  expect_false("California" %in% panel$state)
  expect_true("NewYork" %in% panel$state)
})

test_that("leave_one_out's CI is centered on its own point estimate", {
  inputs <- make_loo_inputs()
  result <- leave_one_out(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                           "food_service", "employment_food_service")
  expect_equal(result$ci_low, result$treated_post - 1.96 * result$se, tolerance = 1e-9)
  expect_equal(result$ci_high, result$treated_post + 1.96 * result$se, tolerance = 1e-9)
})
