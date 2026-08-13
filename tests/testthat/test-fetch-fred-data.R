library(testthat)
source("../../R/01_treatment_classification.R")
source("../../R/02_fetch_fred_data.R")

test_that("employment series IDs match confirmed-working FRED IDs", {
  # These exact IDs were verified against live FRED data before being
  # hardcoded here as a regression check.
  expect_equal(fred_employment_id("California", "70722"), "SMU06000007072200001")
  expect_equal(fred_employment_id("California", "42000"), "SMU06000004200000001")
  expect_equal(fred_employment_id("New York", "70722"), "SMU36000007072200001")
})

test_that("GDP and population series IDs use the state abbreviation", {
  expect_equal(fred_gdp_id("New York"), "NYNQGSP")
  expect_equal(fred_population_id("New York"), "NYPOP")
})

test_that("unknown states are rejected rather than silently producing a bad ID", {
  expect_error(fred_employment_id("Nowhere", "70722"), "Unknown state")
  expect_error(fred_gdp_id("Nowhere"), "Unknown state")
})

test_that("every state in the treatment table has a FIPS code and abbreviation", {
  treated <- load_treatment_table("../../data/treatment_classification.csv")
  missing_fips <- setdiff(treated$state, names(STATE_FIPS))
  missing_abbr <- setdiff(treated$state, names(STATE_ABBR))
  expect_length(missing_fips, 0)
  expect_length(missing_abbr, 0)
})

test_that("annual population values are repeated across all 4 quarters of the year", {
  df <- data.frame(date = as.Date("2021-01-01"), value = 5000)
  result <- annual_to_quarterly(df)
  expect_equal(nrow(result), 4)
  expect_equal(sort(result$quarter), as.Date(c("2021-01-01", "2021-04-01", "2021-07-01", "2021-10-01")))
  expect_true(all(result$value == 5000))
})

test_that("QCEW headcounts are converted to thousands to match FRED's units", {
  # QCEW's own reported values, not made up: NM food service Q1 2021,
  # month1/2/3 employment levels for the private-sector row.
  expect_equal(qcew_monthly_to_thousands(52746, 56550, 60354), 56.55, tolerance = 1e-6)
})

test_that("to_quarterly averages monthly values within each quarter", {
  df <- data.frame(
    date = as.Date(c("2021-01-01", "2021-02-01", "2021-03-01", "2021-04-01")),
    value = c(10, 20, 30, 40)
  )
  result <- to_quarterly(df)
  expect_equal(result$value[result$quarter == as.Date("2021-01-01")], 20)
  expect_equal(result$value[result$quarter == as.Date("2021-04-01")], 40)
})
