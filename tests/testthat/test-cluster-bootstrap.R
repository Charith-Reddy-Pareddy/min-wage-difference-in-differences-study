library(testthat)
source("../../R/11_cluster_bootstrap.R")

make_bootstrap_panel <- function(n_states = 10, beta4 = 0) {
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
  effect <- beta4 * exposure * is_treated * is_post
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  # A little state-quarter noise: without it the series is a perfectly
  # deterministic function of state/quarter, the model fits it exactly,
  # residual variance is ~0, and the bootstrap-t statistics become
  # numerically degenerate (huge, unstable) rather than a well-behaved
  # sampling distribution -- real data always has noise, so the test
  # fixture needs some too.
  set.seed(123)
  noise <- rnorm(nrow(fred_panel), sd = 0.01)
  fred_panel$employment_food_service <- 100 * exp(quarter_trend + effect + noise)

  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("wild_cluster_bootstrap_beta4 returns well-formed output", {
  inputs <- make_bootstrap_panel()
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  boot <- wild_cluster_bootstrap_beta4(panel, B = 199, seed = 42)

  expect_length(boot$boot_t, 199)
  expect_true(boot$p_value >= 0 && boot$p_value <= 1)
  expect_true(boot$ci_low < boot$ci_high)
})

test_that("a designed beta4 effect is picked up as significant", {
  # beta4 = 0.3, with exposure 0.1-0.9, gives individual treated-state
  # effects of 3%-27% log points -- large and clearly detectable, but
  # still within the range of what Day 5-8's real beta4 estimates looked
  # like (0.06-0.4). A much bigger beta4 (e.g. 2, tried initially) badly
  # misspecifies the *restricted* model used to build the bootstrap
  # residuals -- it assumes one flat treated_post effect, so an
  # unrealistically large exposure-scaled effect leaves huge structured
  # residuals that destabilize the whole bootstrap, not just this test.
  #
  # 30 states (15 treated), not the 10-state default: with only 5
  # treated states identifying beta4, the wild bootstrap's weight draws
  # are too coarse (2^5 = 32 combinations) for the reference distribution
  # to behave -- confirmed by testing 10 vs. 30 states directly, where 10
  # gave a wildly unstable bootstrap-t distribution (matching known
  # wild-bootstrap behavior at very low cluster counts) and 30 didn't.
  # Real Day 5-8 data has 20 treated states, comfortably in the stable
  # range.
  inputs <- make_bootstrap_panel(n_states = 30, beta4 = 0.3)
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  boot <- wild_cluster_bootstrap_beta4(panel, B = 199, seed = 42)

  expect_true(boot$p_value < 0.05)
  expect_true(boot$ci_low > 0) # CI should exclude zero given the designed positive effect
})

test_that("no designed effect gives a non-tiny bootstrap p-value", {
  inputs <- make_bootstrap_panel(n_states = 30, beta4 = 0)
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  boot <- wild_cluster_bootstrap_beta4(panel, B = 199, seed = 42)

  expect_true(boot$p_value > 0.05)
})
