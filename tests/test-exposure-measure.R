library(testthat)
source("../R/04_exposure_measure.R")

test_that("hourly-paid workers use HOURWAGE directly", {
  wage <- derive_hourly_wage(hourwage = 15.5, paidhour = 2, earnweek = 999.99, uhrsworkorg = 999)
  expect_equal(wage, 15.5)
})

test_that("salaried workers get weekly earnings divided by hours", {
  wage <- derive_hourly_wage(hourwage = 999.99, paidhour = 1, earnweek = 800, uhrsworkorg = 40)
  expect_equal(wage, 20)
})

test_that("missing hourly wage falls back to weekly/hours even when PAIDHOUR says hourly", {
  # PAIDHOUR = 2 but HOURWAGE is NIU -- shouldn't happen often, but the
  # derivation should still recover a wage from weekly earnings instead
  # of silently returning NA.
  wage <- derive_hourly_wage(hourwage = 999.99, paidhour = 2, earnweek = 600, uhrsworkorg = 30)
  expect_equal(wage, 20)
})

test_that("NA when neither hourly nor weekly/hours data is usable", {
  wage <- derive_hourly_wage(hourwage = 999.99, paidhour = 1, earnweek = 9999.99, uhrsworkorg = 999)
  expect_true(is.na(wage))
})

test_that("vectorized derivation handles a mix of cases in one call", {
  wage <- derive_hourly_wage(
    hourwage    = c(15.5, 999.99, 999.99),
    paidhour    = c(2, 1, 1),
    earnweek    = c(999.99, 800, 9999.99),
    uhrsworkorg = c(999, 40, 999)
  )
  expect_equal(wage, c(15.5, 20, NA_real_))
})

test_that("eating and drinking places (641) classify as food_service", {
  expect_equal(classify_industry(641), "food_service")
})

test_that("retail codes classify as retail, and 641 is excluded from that set", {
  expect_equal(classify_industry(601), "retail")   # grocery stores
  expect_equal(classify_industry(612), "retail")   # motor vehicle dealers
  expect_false(641 %in% RETAIL_IND1990)
})

test_that("wholesale trade and unrelated industries are neither", {
  expect_true(is.na(classify_industry(500)))  # wholesale, motor vehicles
  expect_true(is.na(classify_industry(10)))   # agriculture
})

test_that("month_to_quarter buckets correctly, including boundaries", {
  expect_equal(month_to_quarter(c(1, 3, 4, 6, 7, 10, 12)), c(1, 1, 2, 2, 3, 4, 4))
})

test_that("weighted_exposure_share weights by EARNWT, not raw headcount", {
  # One low-weight worker outside the band shouldn't swamp two
  # high-weight workers inside it.
  wage <- c(10, 10, 50)
  earnwt <- c(100, 100, 1)
  share <- weighted_exposure_share(wage, earnwt, min_wage = 10, band_pct = 0.10)
  expect_equal(share, 200 / 201, tolerance = 1e-6)
})

test_that("weighted_exposure_share drops NA wages before computing the share", {
  wage <- c(10, NA, 10)
  earnwt <- c(50, 999, 50)
  share <- weighted_exposure_share(wage, earnwt, min_wage = 10, band_pct = 0.10)
  expect_equal(share, 1)
})

test_that("weighted_exposure_share returns NA for an empty cell instead of erroring", {
  expect_true(is.na(weighted_exposure_share(numeric(0), numeric(0), min_wage = 10, band_pct = 0.10)))
})

test_that("build_exposure_table flags cells under the n=30 threshold", {
  cps_org <- tibble::tibble(
    state = rep("Alaska", 10),
    industry = rep("food_service", 10),
    wage = rep(10.19, 10),
    earnwt = rep(1000, 10)
  )
  treatment_table <- tibble::tibble(state = "Alaska", wage_2020 = 10.19)
  result <- build_exposure_table(cps_org, treatment_table)
  expect_true(result$below_cell_size_threshold)
  expect_equal(result$n_obs, 10)
})
