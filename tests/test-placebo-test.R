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

#' Post-build addition: fit_placebo_model_c needs treated_post:exposure to
#' be identified, which (same as test-exposure-bandwidth-sensitivity.R and
#' test-specification-curve.R) needs at least 2 treated states with
#' different exposure values -- make_synthetic_inputs above only has 1.
make_placebo_c_inputs <- function() {
  quarters <- seq(as.Date("2015-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- c("California", "NewYork", "Texas", "Ohio", "Florida")
  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::arrange(state, quarter) %>%
    dplyr::mutate(
      gdp = 1000 * 1.005^as.integer(factor(quarter)),
      population = 5000 * 1.001^as.integer(factor(quarter))
    )
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  set.seed(303)
  noise <- rnorm(nrow(fred_panel), sd = 0.01)
  fred_panel$employment_food_service <- 100 * exp(quarter_trend + noise)

  treatment_table <- tibble::tibble(
    state = states,
    group = c("treated", "treated", "treated", "control", "control"),
    increase = c(1, 1, 1, 0, 0)
  )
  exposure_table <- tibble::tibble(
    state = states,
    industry = "food_service",
    exposure_share_125 = c(0.15, 0.25, 0.35, 0.45, 0.55)
  )
  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("fit_placebo_model_c returns a well-formed exposure-interaction coefficient", {
  inputs <- make_placebo_c_inputs()
  panel <- build_placebo_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                "food_service", "employment_food_service")
  model_c <- fit_placebo_model_c(panel)
  ct <- summary(model_c)$coeftable
  expect_true("placebo_treated_post:exposure" %in% rownames(ct))
})

test_that("fit_placebo_model_c finds no spurious exposure gradient in well-behaved synthetic data", {
  inputs <- make_placebo_c_inputs()
  # Deterministic, noise-free trend identical across states -- no real or
  # fake heterogeneous effect exists, so the placebo beta4 should come
  # back at exactly zero, same as fit_placebo_model's null test above.
  # (Real data has noise and, per the report, genuinely fails this check
  # -- this test only establishes that the estimator itself is correct.)
  quarter_index <- as.integer(factor(inputs$fred_panel$quarter))
  inputs$fred_panel$employment_food_service <- 100 * 1.01^quarter_index

  panel <- build_placebo_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                "food_service", "employment_food_service")
  model_c <- fit_placebo_model_c(panel)
  expect_equal(unname(coef(model_c)["placebo_treated_post:exposure"]), 0, tolerance = 1e-8)
})

test_that("fit_placebo_model_c picks up a designed exposure-scaled effect at the false date", {
  inputs <- make_placebo_c_inputs()
  is_treated <- inputs$treatment_table$group[match(inputs$fred_panel$state, inputs$treatment_table$state)] == "treated"
  is_post <- inputs$fred_panel$quarter >= PLACEBO_DATE
  exposure_by_state <- stats::setNames(inputs$exposure_table$exposure_share_125, inputs$exposure_table$state)
  exposure <- exposure_by_state[inputs$fred_panel$state]
  quarter_trend <- as.integer(factor(inputs$fred_panel$quarter)) * 0.01
  set.seed(303)
  noise <- rnorm(nrow(inputs$fred_panel), sd = 0.01)
  inputs$fred_panel$employment_food_service <- 100 * exp(
    quarter_trend + 0.3 * exposure * is_treated * is_post + noise
  )

  panel <- build_placebo_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                "food_service", "employment_food_service")
  model_c <- fit_placebo_model_c(panel)
  ct <- summary(model_c)$coeftable
  expect_true(ct["placebo_treated_post:exposure", "Pr(>|t|)"] < 0.05)
})
