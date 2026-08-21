library(testthat)
source("../R/16_power_analysis.R") # transitively sources R/07 for build_panel

make_power_panel <- function(n_states = 30, beta4 = 0, beta3 = 0) {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- paste0("S", seq_len(n_states))
  exposure_by_state <- stats::setNames(seq(0.1, 0.9, length.out = n_states), states)

  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::arrange(state, quarter)
  # gdp/population need genuine state-by-quarter variation, not just a
  # quarter trend or a per-state constant growth rate -- either one alone
  # leaves gdp_growth/pop_growth fully collinear with one of the two
  # fixed effects in fit_model_a_restricted() (no treated_post left to
  # soak it up), which real data never runs into since GDP genuinely
  # varies both ways. Small state*quarter noise breaks that degeneracy.
  set.seed(456)
  state_quarter_noise_gdp <- rnorm(nrow(fred_panel), sd = 0.01)
  state_quarter_noise_pop <- rnorm(nrow(fred_panel), sd = 0.01)
  fred_panel <- fred_panel %>%
    dplyr::mutate(
      gdp = 1000 * 1.005^as.integer(factor(quarter)) * exp(state_quarter_noise_gdp),
      population = 5000 * 1.001^as.integer(factor(quarter)) * exp(state_quarter_noise_pop)
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
  effect <- beta4 * exposure * is_treated * is_post + beta3 * is_treated * is_post
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  set.seed(123)
  noise <- rnorm(nrow(fred_panel), sd = 0.01)
  fred_panel$employment_food_service <- 100 * exp(quarter_trend + effect + noise)

  build_panel(fred_panel, treatment_table, exposure_table, "food_service", "employment_food_service")
}

test_that("select_mde picks the smallest grid value clearing the threshold", {
  expect_equal(select_mde(c(0.1, 0.2, 0.3), c(0.4, 0.7, 0.9), threshold = 0.80), 0.3)
  expect_equal(select_mde(c(0.1, 0.2, 0.3), c(0.85, 0.9, 0.95), threshold = 0.80), 0.1)
})

test_that("select_mde returns NA when no grid point reaches the threshold", {
  expect_true(is.na(select_mde(c(0.1, 0.2, 0.3), c(0.1, 0.3, 0.5), threshold = 0.80)))
})

test_that("simulate_power_at_effect returns a valid proportion", {
  panel <- make_power_panel(beta4 = 0.3)
  power <- simulate_power_at_effect(panel, true_beta4 = 0.3, reps = 50, seed = 1)
  expect_true(power >= 0 && power <= 1)
})

test_that("a larger true effect gives higher power than a near-zero one, same design", {
  panel <- make_power_panel()
  power_small <- simulate_power_at_effect(panel, true_beta4 = 0.01, reps = 100, seed = 1)
  power_large <- simulate_power_at_effect(panel, true_beta4 = 0.5, reps = 100, seed = 1)
  expect_true(power_large > power_small)
})

test_that("power_curve returns one row per grid point and a consistent mde_80", {
  panel <- make_power_panel()
  effect_grid <- c(0.01, 0.3, 0.6)
  curve <- power_curve(panel, effect_grid, reps = 100, seed = 1)

  expect_equal(nrow(curve$table), length(effect_grid))
  expect_equal(curve$table$effect_size, effect_grid)
  expect_equal(curve$mde_80, select_mde(curve$table$effect_size, curve$table$power, 0.80))
})

test_that("simulate_power_at_effect_a returns a valid proportion", {
  panel <- make_power_panel(beta3 = 0.05)
  power <- simulate_power_at_effect_a(panel, true_beta3 = 0.05, reps = 50, seed = 1)
  expect_true(power >= 0 && power <= 1)
})

test_that("a larger true beta3 gives higher power than a near-zero one, same design", {
  panel <- make_power_panel()
  power_small <- simulate_power_at_effect_a(panel, true_beta3 = 0.001, reps = 100, seed = 1)
  power_large <- simulate_power_at_effect_a(panel, true_beta3 = 0.1, reps = 100, seed = 1)
  expect_true(power_large > power_small)
})

test_that("power_curve_a returns one row per grid point and a consistent mde_80", {
  panel <- make_power_panel()
  effect_grid <- c(0.005, 0.01, 0.1)
  curve <- power_curve_a(panel, effect_grid, reps = 100, seed = 1)

  expect_equal(nrow(curve$table), length(effect_grid))
  expect_equal(curve$table$effect_size, effect_grid)
  expect_equal(curve$mde_80, select_mde(curve$table$effect_size, curve$table$power, 0.80))
})
