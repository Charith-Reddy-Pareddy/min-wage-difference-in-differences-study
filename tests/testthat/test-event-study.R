library(testthat)
source("../../R/08_event_study.R")

test_that("relative_quarter is 0 at the treatment quarter and correct on either side", {
  expect_equal(relative_quarter(as.Date("2021-01-01")), 0L)
  expect_equal(relative_quarter(as.Date("2020-10-01")), -1L)
  expect_equal(relative_quarter(as.Date("2021-04-01")), 1L)
  expect_equal(relative_quarter(as.Date("2019-01-01")), -8L)
  expect_equal(relative_quarter(as.Date("2022-10-01")), 7L)
})

test_that("build_event_study_panel attaches rel_q consistent with build_panel's own quarters", {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas"), each = length(quarters)),
    quarter = rep(quarters, times = 2),
    employment_food_service = rep(100, 2 * length(quarters)),
    employment_retail = rep(200, 2 * length(quarters)),
    gdp = rep(1000 * 1.005^seq_along(quarters), times = 2),
    population = rep(5000 * 1.001^seq_along(quarters), times = 2)
  )
  treatment_table <- tibble::tibble(state = c("California", "Texas"), group = c("treated", "control"), increase = c(1, 0))
  exposure_table <- tibble::tibble(
    state = rep(c("California", "Texas"), each = 2),
    industry = rep(c("food_service", "retail"), times = 2),
    exposure_share_125 = c(0.4, 0.3, 0.2, 0.15)
  )

  panel <- build_event_study_panel(fred_panel, treatment_table, exposure_table, "food_service", "employment_food_service")
  expect_true("rel_q" %in% names(panel))
  expect_equal(panel$rel_q[panel$quarter == as.Date("2021-01-01") & panel$state == "California"], 0L)
})

test_that("fit_event_study recovers a known dynamic treatment effect", {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas"), each = length(quarters)),
    quarter = rep(quarters, times = 2),
    gdp = rep(1000 * 1.005^seq_along(quarters), times = 2),
    population = rep(5000 * 1.001^seq_along(quarters), times = 2)
  )
  # California gets a step-function jump of +10% starting exactly at
  # 2021 Q1 (rel_q == 0) and flat pre-trends before that -- a textbook
  # "clean" event study: all pre-period leads should come back at zero,
  # all post-period effects at a constant +10%.
  quarter_index <- as.integer(factor(fred_panel$quarter))
  is_treated_post <- fred_panel$state == "California" & fred_panel$quarter >= as.Date("2021-01-01")
  fred_panel$employment_food_service <- 100 * 1.01^quarter_index * ifelse(is_treated_post, 1.10, 1)
  fred_panel$employment_retail <- fred_panel$employment_food_service

  treatment_table <- tibble::tibble(state = c("California", "Texas"), group = c("treated", "control"), increase = c(1, 0))
  exposure_table <- tibble::tibble(
    state = rep(c("California", "Texas"), each = 2),
    industry = rep(c("food_service", "retail"), times = 2),
    exposure_share_125 = c(0.4, 0.3, 0.2, 0.15)
  )

  panel <- build_event_study_panel(fred_panel, treatment_table, exposure_table, "food_service", "employment_food_service")
  model <- fit_event_study(panel)
  coefs <- event_study_coefficients(model)

  pre <- coefs %>% dplyr::filter(rel_q < -1)
  post <- coefs %>% dplyr::filter(rel_q >= 0)
  expect_true(all(abs(pre$estimate) < 1e-6))
  expect_true(all(abs(post$estimate - log(1.10)) < 1e-6))
})

test_that("event_study_coefficients adds the omitted reference quarter back in at zero", {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas"), each = length(quarters)),
    quarter = rep(quarters, times = 2),
    employment_food_service = rep(100 * 1.01^rep(seq_along(quarters), times = 2), 1),
    gdp = rep(1000 * 1.005^seq_along(quarters), times = 2),
    population = rep(5000 * 1.001^seq_along(quarters), times = 2)
  )
  treatment_table <- tibble::tibble(state = c("California", "Texas"), group = c("treated", "control"), increase = c(1, 0))
  exposure_table <- tibble::tibble(
    state = c("California", "Texas"),
    industry = "food_service",
    exposure_share_125 = c(0.4, 0.2)
  )
  panel <- build_event_study_panel(fred_panel, treatment_table, exposure_table, "food_service", "employment_food_service")
  model <- fit_event_study(panel)
  coefs <- event_study_coefficients(model)

  ref_row <- coefs %>% dplyr::filter(rel_q == -1)
  expect_equal(nrow(ref_row), 1)
  expect_equal(ref_row$estimate, 0)
  expect_equal(ref_row$ci_low, 0)
  expect_equal(ref_row$ci_high, 0)
})
