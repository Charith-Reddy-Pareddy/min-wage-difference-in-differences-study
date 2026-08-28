library(testthat)
source("../R/07_model_a_c.R")

test_that("count_treated_by_type counts legislated and inflation-adjusted separately", {
  treatment_table <- tibble::tibble(
    state = c("A", "B", "C", "D", "E"),
    group = c("treated", "treated", "treated", "treated", "control"),
    increase_type = c("legislation", "legislation", "inflation_adj", "inflation_adj_paused", "no_change")
  )
  counts <- count_treated_by_type(treatment_table)
  expect_equal(counts$n_legislated, 2)
  expect_equal(counts$n_inflation_adjusted, 2) # inflation_adj + inflation_adj_paused
})

test_that("count_treated_by_type ignores non-treated rows entirely", {
  treatment_table <- tibble::tibble(
    state = c("A", "B"),
    group = c("excluded", "control"),
    increase_type = c("ballot_measure", "no_change")
  )
  counts <- count_treated_by_type(treatment_table)
  expect_equal(counts$n_legislated, 0)
  expect_equal(counts$n_inflation_adjusted, 0)
})

test_that("yoy_log_growth is NA for the first 4 quarters and correct afterward", {
  quarter <- seq(as.Date("2019-01-01"), as.Date("2020-10-01"), by = "quarter")
  value <- 100 * 1.01^(0:7) # steady growth
  growth <- yoy_log_growth(value, quarter)
  expect_true(all(is.na(growth[1:4])))
  expect_equal(growth[5], log(value[5]) - log(value[1]), tolerance = 1e-9)
  expect_equal(growth[8], log(value[8]) - log(value[4]), tolerance = 1e-9)
})

test_that("yoy_log_growth doesn't assume the input is pre-sorted", {
  quarter <- as.Date(c("2020-04-01", "2019-01-01", "2020-01-01", "2019-04-01"))
  value <- c(110, 100, 105, 102)
  growth <- yoy_log_growth(value, quarter)
  # 2020-01-01 (value 105) vs 2019-01-01 (value 100), regardless of input order
  expect_equal(growth[quarter == as.Date("2020-01-01")], log(105) - log(100), tolerance = 1e-9)
})

make_synthetic_panel_inputs <- function() {
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
    state = c("California", "Texas"),
    group = c("treated", "control"),
    increase = c(1.00, 0)
  )
  exposure_table <- tibble::tibble(
    state = rep(c("California", "Texas"), each = 2),
    industry = rep(c("food_service", "retail"), times = 2),
    exposure_share_125 = c(0.4, 0.3, 0.2, 0.15)
  )
  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("build_panel drops the first 4 (lag-establishing) quarters and excludes 'excluded' states", {
  inputs <- make_synthetic_panel_inputs()
  inputs$treatment_table <- rbind(inputs$treatment_table,
                                   tibble::tibble(state = "Florida", group = "excluded", increase = 1.44))
  inputs$fred_panel <- rbind(
    inputs$fred_panel,
    inputs$fred_panel %>% dplyr::filter(state == "Texas") %>% dplyr::mutate(state = "Florida")
  )
  inputs$exposure_table <- rbind(
    inputs$exposure_table,
    tibble::tibble(state = "Florida", industry = c("food_service", "retail"),
                   exposure_share_125 = c(0.1, 0.1))
  )

  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")

  expect_false("Florida" %in% panel$state)
  n_quarters_per_state <- panel %>% dplyr::count(state) %>% dplyr::pull(n)
  expect_true(all(n_quarters_per_state == 12)) # 16 quarters - 4 dropped for the lag
})

test_that("build_panel sets treated_post correctly", {
  inputs <- make_synthetic_panel_inputs()
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "retail", "employment_retail")

  ca_pre <- panel %>% dplyr::filter(state == "California", quarter < as.Date("2021-01-01"))
  ca_post <- panel %>% dplyr::filter(state == "California", quarter >= as.Date("2021-01-01"))
  tx_post <- panel %>% dplyr::filter(state == "Texas", quarter >= as.Date("2021-01-01"))

  expect_true(all(ca_pre$treated_post == 0))
  expect_true(all(ca_post$treated_post == 1))
  expect_true(all(tx_post$treated_post == 0)) # control state, never treated
})

test_that("build_panel attaches the right industry's exposure share", {
  inputs <- make_synthetic_panel_inputs()
  panel_food <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                             "food_service", "employment_food_service")
  panel_retail <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                               "retail", "employment_retail")

  expect_true(all(panel_food$exposure[panel_food$state == "California"] == 0.4))
  expect_true(all(panel_retail$exposure[panel_retail$state == "California"] == 0.3))
})

test_that("fit_model_a recovers a known treated_post effect built into the synthetic data", {
  inputs <- make_synthetic_panel_inputs()
  # Give both states a common quarter trend (so quarter FE has something to
  # absorb) plus a fixed +5% jump for the treated state in the post period
  # -- state/quarter FE should net that back out as the treated_post coef.
  n <- nrow(inputs$fred_panel)
  quarter_index <- as.integer(factor(inputs$fred_panel$quarter))
  is_treated_post <- inputs$fred_panel$state == "California" &
    inputs$fred_panel$quarter >= as.Date("2021-01-01")
  inputs$fred_panel$employment_food_service <- 100 * 1.01^quarter_index * ifelse(is_treated_post, 1.05, 1)

  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  model <- fit_model_a(panel)
  expect_true("treated_post" %in% names(coef(model)))
  expect_equal(unname(coef(model)["treated_post"]), log(1.05), tolerance = 1e-6)
})

test_that("fit_model_a_restricted omits treated_post entirely", {
  # Consolidated here from R/11 and R/16, which previously each defined
  # this identically -- shared now since both source this file already.
  # make_synthetic_panel_inputs()'s default flat employment=100 is fine
  # for tests that build their own panel then discard the fitted model's
  # actual coefficients, but here the model is fit and inspected
  # directly, so it needs real quarter variation for state+quarter FE
  # not to demean the outcome to an exact constant (same collinearity
  # noted throughout tests/test-power-analysis.R and others).
  inputs <- make_synthetic_panel_inputs()
  # gdp/population in the shared fixture vary only by quarter, not by
  # state, which is fine for tests that keep treated_post in the model
  # (it soaks up the remaining variation) but leaves the restricted
  # model here nothing to estimate once quarter FE absorbs a
  # quarter-only series -- same fix as test-power-analysis.R and
  # test-cluster-bootstrap.R: add real state-by-quarter noise.
  quarter_index <- as.integer(factor(inputs$fred_panel$quarter))
  set.seed(11)
  noise_gdp <- rnorm(nrow(inputs$fred_panel), sd = 0.01)
  noise_pop <- rnorm(nrow(inputs$fred_panel), sd = 0.01)
  inputs$fred_panel$gdp <- inputs$fred_panel$gdp * exp(noise_gdp)
  inputs$fred_panel$population <- inputs$fred_panel$population * exp(noise_pop)
  inputs$fred_panel$employment_food_service <- 100 * 1.01^quarter_index

  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  model <- fit_model_a_restricted(panel)
  expect_false("treated_post" %in% names(coef(model)))
  expect_true(all(c("gdp_growth", "pop_growth") %in% names(coef(model))))
})
