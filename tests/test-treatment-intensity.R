library(testthat)
source("../R/19_treatment_intensity.R")

make_intensity_inputs <- function(beta1 = 0) {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- c("California", "NewYork", "Texas", "Ohio")
  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::arrange(state, quarter) %>%
    dplyr::mutate(
      gdp = 1000 * 1.005^as.integer(factor(quarter)),
      population = 5000 * 1.001^as.integer(factor(quarter))
    )
  treatment_table <- tibble::tibble(
    state = states,
    group = c("treated", "treated", "control", "control"),
    increase = c(1.00, 0.50, 0, 0)
  )
  is_post <- fred_panel$quarter >= as.Date("2021-01-01")
  wage_increase <- treatment_table$increase[match(fred_panel$state, treatment_table$state)]
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  effect <- beta1 * wage_increase * is_post
  set.seed(654)
  noise <- rnorm(nrow(fred_panel), sd = 0.005)
  fred_panel$employment_food_service <- 100 * exp(quarter_trend + effect + noise)
  list(fred_panel = fred_panel, treatment_table = treatment_table)
}

test_that("build_intensity_panel keeps the continuous increase amount, not a binary flag", {
  inputs <- make_intensity_inputs()
  panel <- build_intensity_panel(inputs$fred_panel, inputs$treatment_table, "employment_food_service")

  expect_equal(unique(panel$increase[panel$state == "California"]), 1.00)
  expect_equal(unique(panel$increase[panel$state == "NewYork"]), 0.50)
  post_rows <- panel$state == "California" & panel$quarter >= as.Date("2021-01-01")
  expect_true(all(panel$wage_increase_post[post_rows] == 1.00))
})

test_that("build_intensity_panel drops excluded states, same as build_panel", {
  inputs <- make_intensity_inputs()
  inputs$treatment_table <- rbind(inputs$treatment_table,
                                   tibble::tibble(state = "Florida", group = "excluded", increase = 1.44))
  inputs$fred_panel <- rbind(
    inputs$fred_panel,
    inputs$fred_panel %>% dplyr::filter(state == "Texas") %>% dplyr::mutate(state = "Florida")
  )
  panel <- build_intensity_panel(inputs$fred_panel, inputs$treatment_table, "employment_food_service")
  expect_false("Florida" %in% panel$state)
})

test_that("fit_treatment_intensity recovers a known beta1 built into synthetic data", {
  inputs <- make_intensity_inputs(beta1 = 0.03)
  panel <- build_intensity_panel(inputs$fred_panel, inputs$treatment_table, "employment_food_service")
  model <- fit_treatment_intensity(panel)
  expect_true("wage_increase_post" %in% names(coef(model)))
  expect_equal(unname(coef(model)["wage_increase_post"]), 0.03, tolerance = 0.01)
})
