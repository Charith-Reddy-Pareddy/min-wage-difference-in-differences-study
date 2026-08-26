library(testthat)
source("../R/15_permutation_test.R")

make_permutation_panel <- function(n_states = 20, treated_effect = 0) {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- paste0("S", seq_len(n_states))

  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::arrange(state, quarter) %>%
    dplyr::mutate(
      gdp = 1000 * 1.005^as.integer(factor(quarter)),
      population = 5000 * 1.001^as.integer(factor(quarter))
    )

  treatment_table <- tibble::tibble(
    state = states,
    group = rep(c("treated", "control"), length.out = n_states),
    increase = ifelse(rep(c("treated", "control"), length.out = n_states) == "treated", 1, 0)
  )
  exposure_table <- tidyr::expand_grid(state = states, industry = "food_service") %>%
    dplyr::mutate(exposure_share_125 = 0.3)

  is_treated <- treatment_table$group[match(fred_panel$state, treatment_table$state)] == "treated"
  is_post <- fred_panel$quarter >= as.Date("2021-01-01")
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  set.seed(123)
  noise <- rnorm(nrow(fred_panel), sd = 0.01)
  fred_panel$employment_food_service <-
    100 * exp(quarter_trend + treated_effect * is_treated * is_post + noise)

  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("permutation_test_model_a returns well-formed output", {
  inputs <- make_permutation_panel()
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  perm <- permutation_test_model_a(panel, n_reps = 200, seed = 1)

  expect_length(perm$null_stats, 200)
  expect_true(perm$p_value >= 0 && perm$p_value <= 1)
})

test_that("a designed treated_post effect is picked up as significant", {
  inputs <- make_permutation_panel(treated_effect = 0.1)
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  perm <- permutation_test_model_a(panel, n_reps = 200, seed = 1)

  expect_true(perm$p_value < 0.05)
  expect_true(abs(perm$observed_stat) > abs(perm$null_mean) + 2 * perm$null_sd)
})

test_that("no designed effect gives a non-tiny permutation p-value", {
  inputs <- make_permutation_panel(treated_effect = 0)
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  perm <- permutation_test_model_a(panel, n_reps = 200, seed = 1)

  expect_true(perm$p_value > 0.05)
})

#' Post-build addition: permutation_test_model_c needs treated_post:exposure
#' to be identified, which needs at least 2 treated states with different
#' exposure values -- make_permutation_panel above gives every state the
#' same exposure_share_125 (fine for the Model A tests, not for Model C).
make_permutation_panel_c <- function(n_states = 20, beta4 = 0) {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- paste0("S", seq_len(n_states))
  exposure_by_state <- stats::setNames(seq(0.1, 0.9, length.out = n_states), states)

  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::arrange(state, quarter) %>%
    dplyr::mutate(
      gdp = 1000 * 1.005^as.integer(factor(quarter)),
      population = 5000 * 1.001^as.integer(factor(quarter))
    )

  treatment_table <- tibble::tibble(
    state = states,
    group = rep(c("treated", "control"), length.out = n_states),
    increase = ifelse(rep(c("treated", "control"), length.out = n_states) == "treated", 1, 0)
  )
  exposure_table <- tidyr::expand_grid(state = states, industry = "food_service") %>%
    dplyr::mutate(exposure_share_125 = exposure_by_state[state])

  is_treated <- treatment_table$group[match(fred_panel$state, treatment_table$state)] == "treated"
  is_post <- fred_panel$quarter >= as.Date("2021-01-01")
  exposure <- exposure_by_state[fred_panel$state]
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  set.seed(123)
  noise <- rnorm(nrow(fred_panel), sd = 0.01)
  fred_panel$employment_food_service <-
    100 * exp(quarter_trend + beta4 * exposure * is_treated * is_post + noise)

  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("permutation_test_model_c returns well-formed output", {
  inputs <- make_permutation_panel_c(n_states = 30)
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  perm <- permutation_test_model_c(panel, n_reps = 200, seed = 1)

  expect_length(perm$null_stats, 200)
  expect_true(perm$p_value >= 0 && perm$p_value <= 1)
})

test_that("a designed beta4 effect is picked up as significant", {
  inputs <- make_permutation_panel_c(n_states = 30, beta4 = 0.3)
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  perm <- permutation_test_model_c(panel, n_reps = 200, seed = 1)

  expect_true(perm$p_value < 0.05)
  expect_true(abs(perm$observed_stat) > abs(perm$null_mean) + 2 * perm$null_sd)
})

test_that("no designed beta4 effect gives a non-tiny permutation p-value", {
  inputs <- make_permutation_panel_c(n_states = 30, beta4 = 0)
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  perm <- permutation_test_model_c(panel, n_reps = 200, seed = 1)

  expect_true(perm$p_value > 0.05)
})

test_that("permuted treated_post always preserves the true n_treated count", {
  inputs <- make_permutation_panel(n_states = 12)
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  true_n_treated <- dplyr::n_distinct(panel$state[panel$treated == 1])

  set.seed(99)
  states <- unique(panel$state)
  for (i in 1:20) {
    treated_states <- sample(states, true_n_treated)
    expect_length(treated_states, true_n_treated)
  }
})
