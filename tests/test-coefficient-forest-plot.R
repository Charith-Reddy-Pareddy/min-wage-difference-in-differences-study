library(testthat)
source("../R/21_coefficient_forest_plot.R")

make_fake_mac <- function() {
  tibble::tibble(
    sample = c("full 20-state treated sample", "full 20-state treated sample",
               ">=$0.50-increase subsample", ">=$0.50-increase subsample"),
    industry = c("food_service", "retail", "food_service", "retail"),
    model_a_treated_post = c(-0.025, -0.010, -0.048, -0.027),
    model_a_se = c(0.016, 0.011, 0.019, 0.013),
    model_c_beta4_treated_post_x_exposure = c(0.167, -0.005, 0.419, -0.297),
    model_c_beta4_se = c(0.172, 0.080, 0.226, 0.121)
  )
}

test_that("build_forest_data produces 2 rows (beta3, beta4) per model_a_c_results row", {
  mac <- make_fake_mac()
  forest <- build_forest_data(mac)
  expect_equal(nrow(forest), nrow(mac) * 2)
  expect_setequal(forest$coefficient, c("beta3 (Model A)", "beta4 (Model C)"))
})

test_that("build_forest_data's CI is centered on its own estimate with the right width", {
  mac <- make_fake_mac()
  forest <- build_forest_data(mac)
  expect_equal(forest$ci_low, forest$estimate - 1.96 * forest$se, tolerance = 1e-9)
  expect_equal(forest$ci_high, forest$estimate + 1.96 * forest$se, tolerance = 1e-9)
})

test_that("build_forest_data pulls the correct estimate for each coefficient", {
  mac <- make_fake_mac()
  forest <- build_forest_data(mac)
  beta3_row <- forest %>% dplyr::filter(coefficient == "beta3 (Model A)", industry == "food_service",
                                         sample == "full 20-state treated sample")
  beta4_row <- forest %>% dplyr::filter(coefficient == "beta4 (Model C)", industry == "food_service",
                                         sample == "full 20-state treated sample")
  expect_equal(beta3_row$estimate, -0.025)
  expect_equal(beta4_row$estimate, 0.167)
})
