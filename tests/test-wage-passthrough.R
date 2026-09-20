library(testthat)
source("../R/29_wage_passthrough.R")

test_that("wage series IDs match confirmed-working FRED IDs", {
  # These exact IDs were verified against live FRED data (a 200 response
  # with real observations) before being hardcoded here as a regression
  # check -- matching R/02's own practice for the employment series IDs.
  expect_equal(fred_ahe_id("California", AHE_SUPERSECTOR[["food_service_proxy"]]), "SMU06000007000000003")
  expect_equal(fred_ahe_id("California", AHE_SUPERSECTOR[["retail_proxy"]]), "SMU06000004000000003")
  expect_equal(fred_ahe_id("Alabama", AHE_SUPERSECTOR[["food_service_proxy"]]), "SMU01000007000000003")
})

test_that("unknown states are rejected rather than silently producing a bad ID", {
  expect_error(fred_ahe_id("Nowhere", AHE_SUPERSECTOR[["food_service_proxy"]]), "Unknown state")
})

test_that("build_wage_input joins wage series onto the existing fred panel by state and quarter", {
  fred_panel <- tibble::tibble(
    state = c("California", "California", "Texas"),
    quarter = as.Date(c("2020-01-01", "2020-04-01", "2020-01-01")),
    gdp = c(1000, 1010, 900),
    population = c(5000, 5000, 4000)
  )
  wage_data <- tibble::tibble(
    state = c("California", "California", "Texas"),
    quarter = as.Date(c("2020-01-01", "2020-04-01", "2020-01-01")),
    wage_food_service_proxy = c(15, 15.5, 14),
    wage_retail_proxy = c(16, 16.2, 15)
  )
  result <- build_wage_input(fred_panel, wage_data)

  expect_equal(nrow(result), 3)
  expect_true(all(c("gdp", "population", "wage_food_service_proxy", "wage_retail_proxy") %in% names(result)))
  expect_equal(result$wage_food_service_proxy[result$state == "Texas"], 14)
})

test_that("build_wage_input drops rows with no matching quarter in either source", {
  fred_panel <- tibble::tibble(state = "California", quarter = as.Date("2020-01-01"), gdp = 1000, population = 5000)
  wage_data <- tibble::tibble(state = "California", quarter = as.Date("2020-04-01"), wage_food_service_proxy = 15, wage_retail_proxy = 16)
  result <- build_wage_input(fred_panel, wage_data)
  expect_equal(nrow(result), 0)
})

test_that("wage_passthrough_ratio recovers a known example exactly", {
  treatment_table <- tibble::tibble(
    state = c("A", "B", "C"),
    group = c("treated", "treated", "control"),
    increase = c(1.00, 0.50, 0)
  )
  # log-point coefficient of log(1.05) means a 5% wage increase; on a
  # $20 baseline wage that's exactly $1.00.
  result <- wage_passthrough_ratio(log(1.05), baseline_wage = 20, treatment_table)

  expect_equal(result$implied_dollar_increase, 1.00, tolerance = 1e-9)
  expect_equal(result$mandated_dollar_increase, 0.75) # mean(1.00, 0.50), control excluded
  expect_equal(result$pass_through_ratio, 1.00 / 0.75, tolerance = 1e-9)
})

test_that("wage_passthrough_ratio is 0 when the estimated wage effect is exactly 0", {
  treatment_table <- tibble::tibble(state = "A", group = "treated", increase = 1.00)
  result <- wage_passthrough_ratio(0, baseline_wage = 20, treatment_table)
  expect_equal(result$implied_dollar_increase, 0)
  expect_equal(result$pass_through_ratio, 0)
})

test_that("build_panel + fit_model_a work on a wage outcome exactly as they do on employment", {
  # Reuses the same synthetic-panel pattern as test-model-a-c.R, but
  # with a wage-shaped outcome column standing in for employment --
  # confirms the reuse (build_wage_input's output plugged straight into
  # R/07's build_panel/fit_model_a) doesn't secretly depend on the
  # column being named an employment-specific way.
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  quarter_index <- as.integer(factor(quarters))
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas"), each = length(quarters)),
    quarter = rep(quarters, times = 2),
    gdp = rep(1000 * 1.005^seq_along(quarters), times = 2),
    population = rep(5000 * 1.001^seq_along(quarters), times = 2)
  )
  wage_data <- tibble::tibble(
    state = rep(c("California", "Texas"), each = length(quarters)),
    quarter = rep(quarters, times = 2),
    wage_food_service_proxy = c(
      15 * 1.01^quarter_index * ifelse(quarters >= as.Date("2021-01-01"), 1.05, 1),
      15 * 1.01^quarter_index
    )
  )
  treatment_table <- tibble::tibble(state = c("California", "Texas"), group = c("treated", "control"), increase = c(1.00, 0))
  exposure_table <- tibble::tibble(
    state = rep(c("California", "Texas"), each = 2),
    industry = rep(c("food_service", "retail"), times = 2),
    exposure_share_125 = c(0.4, 0.3, 0.2, 0.15)
  )

  wage_input <- build_wage_input(fred_panel, wage_data)
  panel <- build_panel(wage_input, treatment_table, exposure_table, "food_service", "wage_food_service_proxy")
  model <- fit_model_a(panel)

  expect_equal(unname(coef(model)["treated_post"]), log(1.05), tolerance = 1e-6)
})
