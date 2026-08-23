library(testthat)
source("../R/17_exposure_bandwidth_sensitivity.R")

make_bandwidth_inputs <- function() {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  states <- c("California", "NewYork", "Texas", "Ohio")
  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::arrange(state, quarter) %>%
    dplyr::mutate(
      gdp = 1000 * 1.005^as.integer(factor(quarter)),
      population = 5000 * 1.001^as.integer(factor(quarter))
    )
  # A flat constant employment series is degenerate: after state+quarter
  # FE demeaning it's exactly zero everywhere and fixest can't estimate
  # anything ("dependent variable is a constant"). Needs real state and
  # quarter variation, same as the fixtures in test-model-a-c.R and
  # test-power-analysis.R.
  set.seed(789)
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  noise <- rnorm(nrow(fred_panel), sd = 0.01)
  fred_panel$employment_food_service <- 100 * exp(quarter_trend + noise)
  # At least 2 treated states with *different* exposure values are
  # needed: with only 1 treated state, treated_post:exposure is exactly
  # proportional to treated_post (no within-treated exposure variation),
  # so fixest drops it as collinear and the term never appears in the
  # coefficient table.
  treatment_table <- tibble::tibble(
    state = states,
    group = c("treated", "treated", "control", "control"),
    increase = c(1, 1, 0, 0)
  )
  exposure_table <- tibble::tibble(
    state = states,
    industry = "food_service",
    exposure_share_10 = c(0.1, 0.2, 0.3, 0.4),
    exposure_share_125 = c(0.15, 0.25, 0.35, 0.45),
    exposure_share_15 = c(0.2, 0.3, 0.4, 0.5)
  )
  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("bandwidth_sensitivity returns one row per bandwidth", {
  inputs <- make_bandwidth_inputs()
  result <- bandwidth_sensitivity(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                                   "food_service", "employment_food_service")
  expect_equal(nrow(result), 3)
  expect_setequal(result$bandwidth, c("10%", "12.5%", "15%"))
  expect_true(all(c("beta4", "beta4_se", "beta4_p") %in% names(result)))
})

test_that("build_panel's exposure_band_col actually switches which column is used", {
  inputs <- make_bandwidth_inputs()
  panel_10 <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                           "food_service", "employment_food_service", exposure_band_col = "exposure_share_10")
  panel_15 <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                           "food_service", "employment_food_service", exposure_band_col = "exposure_share_15")
  expect_equal(panel_10$exposure[panel_10$state == "California"][1], 0.1)
  expect_equal(panel_15$exposure[panel_15$state == "California"][1], 0.2)
})

test_that("build_panel still defaults to the 12.5% band when exposure_band_col is omitted", {
  inputs <- make_bandwidth_inputs()
  panel <- build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
                        "food_service", "employment_food_service")
  expect_equal(panel$exposure[panel$state == "California"][1], 0.15)
})
