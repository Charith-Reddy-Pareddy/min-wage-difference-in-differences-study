library(testthat)
source("../R/22_multiple_testing_correction.R")

make_fake_mac <- function() {
  tibble::tibble(
    sample = c("full 20-state treated sample", "full 20-state treated sample",
               ">=$0.50-increase subsample", ">=$0.50-increase subsample"),
    industry = c("food_service", "retail", "food_service", "retail"),
    model_a_p = c(0.02, 0.40, 0.99, 0.99),
    model_c_beta4_p = c(0.03, 0.90, 0.99, 0.99)
  )
}

test_that("holm_adjust_confirmatory only uses the headline specification", {
  mac <- make_fake_mac()
  result <- holm_adjust_confirmatory(mac)
  expect_equal(nrow(result), 4) # 2 coefficients x 2 industries, headline spec only
  expect_false(any(result$p_raw == 0.99)) # subsample rows excluded
})

test_that("Holm-adjusted p-values are never smaller than the raw p-values", {
  mac <- make_fake_mac()
  result <- holm_adjust_confirmatory(mac)
  expect_true(all(result$p_holm >= result$p_raw))
})

test_that("Holm correction matches base R's p.adjust directly on the same 4 p-values", {
  mac <- make_fake_mac()
  result <- holm_adjust_confirmatory(mac)
  expected <- p.adjust(c(0.02, 0.40, 0.03, 0.90), method = "holm")
  expect_equal(sort(result$p_holm), sort(expected))
})
