library(testthat)
source("../R/28_neural_network.R")

test_that("standardize_by / unstandardize_by round-trip exactly", {
  x <- c(10, 20, 30, 40)
  z <- standardize_by(x, mean = 25, sd = 5)
  expect_equal(unstandardize_by(z, mean = 25, sd = 5), x)
})

test_that("standardize_by produces mean 0 / sd 1 on the data it was fit from", {
  set.seed(1)
  x <- rnorm(50, mean = 7, sd = 3)
  z <- standardize_by(x, mean = mean(x), sd = stats::sd(x))
  expect_equal(mean(z), 0, tolerance = 1e-9)
  expect_equal(stats::sd(z), 1, tolerance = 1e-9)
})

make_nn_fixture <- function(n_states = 12) {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- paste0("State", seq_len(n_states))
  set.seed(7)
  panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::mutate(
      treated_post = as.integer(state %in% states[1:(n_states / 2)] & quarter >= as.Date("2021-01-01")),
      gdp_growth = rnorm(dplyr::n(), sd = 0.01),
      pop_growth = rnorm(dplyr::n(), sd = 0.01),
      exposure = rep(seq(0.1, 0.4, length.out = n_states), each = length(quarters)),
      region = rep(rep(c("South", "West"), each = n_states / 2), each = length(quarters)),
      # A real (if simple) signal: employment_growth rises with
      # treated_post and with exposure, plus a little noise -- something
      # a network with a handful of epochs should be able to pick up on
      # partially.
      employment_growth = 0.02 + 0.05 * treated_post + 0.1 * exposure + rnorm(dplyr::n(), sd = 0.02)
    )
  panel
}

test_that("fit_neural_network returns one finite prediction per test row", {
  panel <- make_nn_fixture()
  split <- split_by_state(panel, test_frac = 0.3, seed = 1)

  nn <- fit_neural_network(split$train, split$test, size = 3, seed = 1, maxit = 100)

  expect_length(nn$predictions, nrow(split$test))
  expect_true(all(is.finite(nn$predictions)))
  # Predictions should land in the same ballpark as employment_growth
  # (roughly 0.02-0.09), not blow up from an unstandardized fit gone wrong.
  expect_true(all(nn$predictions > -0.5 & nn$predictions < 0.5))
})

test_that("build_comparison_table appends the neural network row to R/27's results", {
  prior <- tibble::tibble(
    model = c("linear_baseline", "bagged_trees"),
    rmse = c(0.05, 0.03),
    r_squared = c(0.4, 0.6)
  )
  combined <- build_comparison_table(prior, nn_rmse = 0.02, nn_r_squared = 0.7)

  expect_equal(nrow(combined), 3)
  expect_equal(combined$model, c("linear_baseline", "bagged_trees", "neural_network"))
  expect_equal(combined$rmse[combined$model == "neural_network"], 0.02)
  expect_equal(combined$r_squared[combined$model == "neural_network"], 0.7)
})
