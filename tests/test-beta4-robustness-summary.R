library(testthat)
source("../R/24_beta4_robustness_summary.R")

make_synthetic_inputs <- function() {
  placebo_beta4 <- tibble::tibble(
    industry = c("food_service", "retail"),
    placebo_date = as.Date("2018-01-01"),
    placebo_beta4 = c(0.11, 0.06),
    placebo_beta4_se = c(0.026, 0.026),
    placebo_beta4_p = c(0.00008, 0.0164234)
  )
  permutation_beta4 <- tibble::tibble(
    industry = c("food_service", "retail"),
    observed_beta4 = c(0.167, -0.005),
    null_mean = c(-0.087, -0.077),
    null_sd = c(0.062, 0.059),
    permutation_p_value = c(0.10, 0.97)
  )
  spec_curve <- tibble::tribble(
    ~industry,      ~beta4,   ~significant,
    "food_service",  0.11,     FALSE,
    "food_service",  0.17,     FALSE,
    "food_service",  0.18,     FALSE,
    "food_service",  0.21,     FALSE,
    "food_service",  0.39,     FALSE,
    "food_service",  0.42,     FALSE,
    "retail",       -0.30,     TRUE,
    "retail",       -0.19,     TRUE,
    "retail",       -0.16,     FALSE,
    "retail",       -0.02,     FALSE,
    "retail",       -0.01,     FALSE,
    "retail",       -0.005,    FALSE
  )
  pretrend_beta4 <- tibble::tibble(
    industry = c("food_service", "retail"),
    pretrend_f_stat = c(4.44, 6.76),
    pretrend_p_value = c(0.0000224, 0.0000000918)
  )
  list(placebo_beta4 = placebo_beta4, permutation_beta4 = permutation_beta4,
       spec_curve = spec_curve, pretrend_beta4 = pretrend_beta4)
}

test_that("beta4_robustness_summary returns one row per check and one column per industry", {
  inputs <- make_synthetic_inputs()
  result <- beta4_robustness_summary(inputs$placebo_beta4, inputs$permutation_beta4,
                                      inputs$spec_curve, inputs$pretrend_beta4)

  expect_equal(nrow(result), 4)
  expect_setequal(names(result), c("check", "food_service", "retail"))
  expect_equal(result$check, c(
    "Placebo test (false 2018 date)",
    "Permutation test (label reassignment)",
    "Specification curve (12 specs)",
    "Event study (pre-trend joint test)"
  ))
})

test_that("very small p-values are reported as < 0.0001 rather than rounding to zero", {
  inputs <- make_synthetic_inputs()
  result <- beta4_robustness_summary(inputs$placebo_beta4, inputs$permutation_beta4,
                                      inputs$spec_curve, inputs$pretrend_beta4)

  placebo_row <- result[result$check == "Placebo test (false 2018 date)", ]
  expect_equal(placebo_row$food_service, "p < 0.0001")
  expect_true(grepl("^p = 0\\.0164", placebo_row$retail))
})

test_that("permutation row flags an off-center null distribution", {
  inputs <- make_synthetic_inputs()
  result <- beta4_robustness_summary(inputs$placebo_beta4, inputs$permutation_beta4,
                                      inputs$spec_curve, inputs$pretrend_beta4)

  perm_row <- result[result$check == "Permutation test (label reassignment)", ]
  expect_true(grepl("null not centered at zero", perm_row$food_service))
  expect_true(grepl("null not centered at zero", perm_row$retail))
})

test_that("specification-curve row summarizes sign consistency and significance count correctly", {
  inputs <- make_synthetic_inputs()
  result <- beta4_robustness_summary(inputs$placebo_beta4, inputs$permutation_beta4,
                                      inputs$spec_curve, inputs$pretrend_beta4)

  spec_row <- result[result$check == "Specification curve (12 specs)", ]
  expect_equal(spec_row$food_service, "0 of 6 significant, positive in 6 of 6")
  expect_equal(spec_row$retail, "2 of 6 significant, negative in 6 of 6")
})

test_that("a well-centered permutation null is not flagged as off-center", {
  inputs <- make_synthetic_inputs()
  inputs$permutation_beta4$null_mean <- c(0.001, -0.002)
  result <- beta4_robustness_summary(inputs$placebo_beta4, inputs$permutation_beta4,
                                      inputs$spec_curve, inputs$pretrend_beta4)

  perm_row <- result[result$check == "Permutation test (label reassignment)", ]
  expect_false(grepl("null not centered at zero", perm_row$food_service))
  expect_false(grepl("null not centered at zero", perm_row$retail))
})
