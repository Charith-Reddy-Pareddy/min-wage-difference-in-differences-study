library(testthat)
source("../R/25_exposure_covid_correlation.R")

make_correlation_inputs <- function(n_states = 20, designed_r_sign = -1) {
  states <- paste0("S", seq_len(n_states))
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")

  # Exposure runs 0.05 to 0.95 in even steps; covid_severity is built as a
  # deterministic linear function of exposure (sign controlled by
  # designed_r_sign) plus a small amount of noise, so the correlation's
  # sign is known and its magnitude is close to (not exactly) 1 -- a
  # clean way to check the function recovers the right sign without
  # requiring the noiseless r == 1 edge case.
  exposure_by_state <- stats::setNames(seq(0.05, 0.95, length.out = n_states), states)
  set.seed(42)
  noise <- rnorm(n_states, sd = 0.01)
  covid_severity_by_state <- stats::setNames(
    designed_r_sign * exposure_by_state * 0.5 + noise, states
  )

  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::mutate(
      employment_food_service = ifelse(
        quarter == as.Date("2020-04-01"),
        100 * exp(covid_severity_by_state[state]),
        100
      )
    )
  # compute_covid_severity() only reads the pre-COVID and trough quarters,
  # so every other quarter's value is irrelevant to this test -- fixed at
  # 100 (pre-COVID reference level) is enough for it to compute the exact
  # designed severity.

  treatment_table <- tibble::tibble(
    state = states,
    group = rep(c("treated", "control"), length.out = n_states),
    increase = ifelse(rep(c("treated", "control"), length.out = n_states) == "treated", 1, 0)
  )
  exposure_table <- tidyr::expand_grid(state = states, industry = "food_service") %>%
    dplyr::mutate(exposure_share_125 = exposure_by_state[state])

  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("exposure_covid_correlation recovers a designed negative correlation", {
  inputs <- make_correlation_inputs(designed_r_sign = -1)
  result <- exposure_covid_correlation(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                        "food_service", "employment_food_service")

  expect_true(result$correlation < -0.9)
  expect_true(result$p_value < 0.001)
  expect_equal(result$n, 20)
})

test_that("exposure_covid_correlation recovers a designed positive correlation", {
  inputs <- make_correlation_inputs(designed_r_sign = 1)
  result <- exposure_covid_correlation(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                        "food_service", "employment_food_service")

  expect_true(result$correlation > 0.9)
  expect_true(result$p_value < 0.001)
})

test_that("exposure_covid_correlation excludes the excluded group", {
  inputs <- make_correlation_inputs(n_states = 10)
  inputs$treatment_table$group[1] <- "excluded"
  result <- exposure_covid_correlation(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                        "food_service", "employment_food_service")

  expect_equal(result$n, 9)
  expect_false("S1" %in% result$data$state)
})

test_that("exposure_covid_correlation returns the joined data used for the fit", {
  inputs <- make_correlation_inputs(n_states = 15)
  result <- exposure_covid_correlation(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                        "food_service", "employment_food_service")

  expect_true(all(c("state", "exposure", "covid_severity") %in% names(result$data)))
  expect_equal(nrow(result$data), 15)
})
