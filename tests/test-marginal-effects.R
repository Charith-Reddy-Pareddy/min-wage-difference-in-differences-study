library(testthat)
source("../R/18_marginal_effects.R")

test_that("marginal_effect_curve recovers a known beta3 + beta4 combination exactly", {
  # Build a fake fixest-like object isn't practical (coef()/vcov() need a
  # real fitted model), so this checks the delta-method arithmetic
  # directly against known coefficients and a diagonal (zero-covariance)
  # vcov -- the simplest case where the closed-form answer is obvious.
  # coef()/vcov() are S3 generics dispatched via UseMethod(), which looks
  # up "coef.fake_fit"/"vcov.fake_fit" starting from marginal_effect_curve()'s
  # own calling environment -- methods assigned as plain local variables
  # inside this test_that() block live in the wrong environment for that
  # lookup to find them, so they must be registered in .GlobalEnv instead
  # (and removed again after, via on.exit, so this doesn't leak into
  # other tests).
  assign("coef.fake_fit", function(object, ...) c(treated_post = -0.02, `treated_post:exposure` = 0.5),
         envir = .GlobalEnv)
  assign("vcov.fake_fit", function(object, ...) {
    m <- diag(c(0.0001, 0.01))
    dimnames(m) <- list(c("treated_post", "treated_post:exposure"), c("treated_post", "treated_post:exposure"))
    m
  }, envir = .GlobalEnv)
  on.exit(rm(list = c("coef.fake_fit", "vcov.fake_fit"), envir = .GlobalEnv), add = TRUE)

  fake_model <- structure(list(), class = "fake_fit")
  curve <- marginal_effect_curve(fake_model, exposure_grid = c(0, 0.5, 1))

  # effect(exposure) = -0.02 + 0.5 * exposure
  expect_equal(curve$effect, c(-0.02, 0.23, 0.48), tolerance = 1e-9)
  # se(0) = sqrt(var(beta3)) = sqrt(0.0001) = 0.01 (zero covariance, exposure = 0)
  expect_equal(curve$se[1], 0.01, tolerance = 1e-9)
  # se(1) = sqrt(var(beta3) + var(beta4)) = sqrt(0.0001 + 0.01)
  expect_equal(curve$se[3], sqrt(0.0001 + 0.01), tolerance = 1e-9)
  expect_true(all(curve$ci_low < curve$effect & curve$effect < curve$ci_high))
})

test_that("marginal_effect_curve on a real fitted Model C matches the coefficient table directly", {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- c("California", "NewYork", "Texas", "Ohio")
  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::arrange(state, quarter) %>%
    dplyr::mutate(
      gdp = 1000 * 1.005^as.integer(factor(quarter)),
      population = 5000 * 1.001^as.integer(factor(quarter))
    )
  set.seed(321)
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  noise <- rnorm(nrow(fred_panel), sd = 0.01)
  fred_panel$employment_food_service <- 100 * exp(quarter_trend + noise)

  treatment_table <- tibble::tibble(
    state = states, group = c("treated", "treated", "control", "control"), increase = c(1, 1, 0, 0)
  )
  exposure_table <- tibble::tibble(
    state = states, industry = "food_service",
    exposure_share_125 = c(0.2, 0.4, 0.3, 0.5)
  )

  panel <- build_panel(fred_panel, treatment_table, exposure_table, "food_service", "employment_food_service")
  model <- fit_model_c(panel)

  curve <- marginal_effect_curve(model, exposure_grid = c(0, 1))
  b <- coef(model)
  expect_equal(curve$effect[1], unname(b[["treated_post"]]), tolerance = 1e-9)
  expect_equal(curve$effect[2], unname(b[["treated_post"]] + b[["treated_post:exposure"]]), tolerance = 1e-9)
})
