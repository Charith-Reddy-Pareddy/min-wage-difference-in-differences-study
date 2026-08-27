library(testthat)
source("../R/26_covid_controlled_placebo.R")

make_synthetic_inputs <- function(n_states = 5) {
  quarters <- seq(as.Date("2015-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- paste0("S", seq_len(n_states))
  exposure_by_state <- stats::setNames(seq(0.15, 0.55, length.out = n_states), states)

  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::arrange(state, quarter) %>%
    dplyr::mutate(
      gdp = 1000 * 1.005^as.integer(factor(quarter)),
      population = 5000 * 1.001^as.integer(factor(quarter))
    )
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  set.seed(505)
  noise <- rnorm(nrow(fred_panel), sd = 0.01)
  # A real COVID dip at 2020 Q2 (needed for compute_covid_severity to find
  # a nonzero, non-NA severity per state) plus the ordinary trend/noise.
  is_covid_trough <- fred_panel$quarter == as.Date("2020-04-01")
  fred_panel$employment_food_service <- 100 * exp(quarter_trend + noise - 0.1 * is_covid_trough)

  treatment_table <- tibble::tibble(
    state = states,
    group = c("treated", "treated", "treated", "control", "control"),
    increase = c(1, 1, 1, 0, 0)
  )
  exposure_table <- tibble::tibble(
    state = states,
    industry = "food_service",
    exposure_share_125 = exposure_by_state[state]
  )
  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("fit_placebo_model_c_covid_controlled returns both terms in the coefficient table", {
  inputs <- make_synthetic_inputs()
  panel <- build_placebo_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                "food_service", "employment_food_service")
  covid_severity <- compute_covid_severity(inputs$fred_panel, "employment_food_service")
  panel_covid <- add_covid_covariate(panel, covid_severity)

  model <- fit_placebo_model_c_covid_controlled(panel_covid)
  ct <- fixest::coeftable(model)

  expect_true("placebo_treated_post:exposure" %in% rownames(ct))
  expect_true("covid_severity_x_post" %in% rownames(ct))
})

test_that("covid_severity_x_post is built from the placebo panel's own post indicator", {
  inputs <- make_synthetic_inputs()
  panel <- build_placebo_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                "food_service", "employment_food_service")
  covid_severity <- compute_covid_severity(inputs$fred_panel, "employment_food_service")
  panel_covid <- add_covid_covariate(panel, covid_severity)

  # Where post == 0 (pre false-2018-date), the interaction must be exactly
  # zero regardless of the state's covid_severity value.
  pre_period <- panel_covid[panel_covid$post == 0, ]
  expect_true(all(pre_period$covid_severity_x_post == 0))

  post_period <- panel_covid[panel_covid$post == 1, ]
  expected <- post_period$covid_severity * post_period$post
  expect_equal(post_period$covid_severity_x_post, expected)
})

test_that("adding the covid control doesn't change the baseline model's sample size", {
  inputs <- make_synthetic_inputs()
  panel <- build_placebo_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                "food_service", "employment_food_service")
  covid_severity <- compute_covid_severity(inputs$fred_panel, "employment_food_service")
  panel_covid <- add_covid_covariate(panel, covid_severity)

  baseline <- fit_placebo_model_c(panel)
  controlled <- fit_placebo_model_c_covid_controlled(panel_covid)

  expect_equal(nobs(baseline), nobs(controlled))
})
