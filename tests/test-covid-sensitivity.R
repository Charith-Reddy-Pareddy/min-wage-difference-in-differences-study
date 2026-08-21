library(testthat)
source("../R/09_covid_sensitivity.R")

test_that("compute_covid_severity is log(trough) - log(pre-COVID), per state", {
  fred_panel <- tibble::tibble(
    state = rep(c("California", "Texas"), each = 2),
    quarter = rep(c(as.Date("2019-10-01"), as.Date("2020-04-01")), times = 2),
    employment_food_service = c(100, 80, 100, 95) # CA hit harder than TX
  )
  result <- compute_covid_severity(fred_panel, "employment_food_service")
  expect_equal(result$covid_severity[result$state == "California"], log(80) - log(100), tolerance = 1e-9)
  expect_equal(result$covid_severity[result$state == "Texas"], log(95) - log(100), tolerance = 1e-9)
  expect_true(result$covid_severity[result$state == "California"] < result$covid_severity[result$state == "Texas"])
})

test_that("add_covid_covariate is zero pre-treatment and covid_severity in post", {
  panel <- tibble::tibble(
    state = c("California", "California"),
    post = c(0, 1)
  )
  covid_severity <- tibble::tibble(state = "California", covid_severity = -0.2)
  result <- add_covid_covariate(panel, covid_severity)
  expect_equal(result$covid_severity_x_post, c(0, -0.2))
})

test_that("compute_covid_severity errors clearly if a state is missing one of the two quarters", {
  fred_panel <- tibble::tibble(
    state = "California",
    quarter = as.Date("2019-10-01"), # missing the 2020-04-01 trough quarter
    employment_food_service = 100
  )
  result <- compute_covid_severity(fred_panel, "employment_food_service")
  expect_true(is.na(result$covid_severity))
})
