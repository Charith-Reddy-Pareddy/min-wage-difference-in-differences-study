library(testthat)
source("../R/23_specification_curve.R")

make_spec_curve_inputs <- function() {
  quarters <- seq(as.Date("2019-01-01"), as.Date("2022-10-01"), by = "quarter")
  # 3 treated states (increases split across the >=$0.50 subsample cut) and
  # 2 controls -- the subsample keeps 2 of the 3 treated states, still
  # enough for treated_post:exposure to stay identified in every derived
  # sample (see test-exposure-bandwidth-sensitivity.R's note on why 1
  # treated state isn't enough).
  states <- c("California", "NewYork", "Texas", "Ohio", "Florida")
  fred_panel <- tidyr::expand_grid(state = states, quarter = quarters) %>%
    dplyr::arrange(state, quarter) %>%
    dplyr::mutate(
      gdp = 1000 * 1.005^as.integer(factor(quarter)),
      population = 5000 * 1.001^as.integer(factor(quarter))
    )
  quarter_trend <- as.integer(factor(fred_panel$quarter)) * 0.01
  set.seed(101)
  fred_panel$employment_food_service <- 100 * exp(quarter_trend + rnorm(nrow(fred_panel), sd = 0.01))
  set.seed(202)
  fred_panel$employment_retail <- 150 * exp(quarter_trend + rnorm(nrow(fred_panel), sd = 0.01))

  treatment_table <- tibble::tibble(
    state = states,
    group = c("treated", "treated", "treated", "control", "control"),
    increase = c(0.3, 0.6, 0.9, 0, 0)
  )
  exposure_table <- tibble::tibble(
    state = states,
    industry = "food_service",
    exposure_share_10 = c(0.1, 0.2, 0.3, 0.4, 0.5),
    exposure_share_125 = c(0.15, 0.25, 0.35, 0.45, 0.55),
    exposure_share_15 = c(0.2, 0.3, 0.4, 0.5, 0.6)
  ) %>%
    dplyr::bind_rows(tibble::tibble(
      state = states,
      industry = "retail",
      exposure_share_10 = c(0.05, 0.15, 0.25, 0.35, 0.45),
      exposure_share_125 = c(0.1, 0.2, 0.3, 0.4, 0.5),
      exposure_share_15 = c(0.15, 0.25, 0.35, 0.45, 0.55)
    ))

  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

test_that("run_specification_curve covers every bandwidth x sample x industry combination", {
  inputs <- make_spec_curve_inputs()
  result <- run_specification_curve(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table)

  expect_equal(nrow(result), 12)
  expect_setequal(result$bandwidth, c("10%", "12.5%", "15%"))
  expect_setequal(result$sample, c("full 20-state sample", ">=$0.50 subsample"))
  expect_setequal(result$industry, c("food_service", "retail"))
  expect_equal(nrow(dplyr::distinct(result, bandwidth, sample, industry)), 12)
})

test_that("run_specification_curve ranks estimates and flags significance consistently", {
  inputs <- make_spec_curve_inputs()
  result <- run_specification_curve(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table)

  expect_equal(result$rank, order(result$beta4))
  expect_true(all(result$ci_low < result$ci_high))
  expect_equal(result$significant, result$p_value < 0.05)
})

test_that(">=$0.50 subsample actually drops the lowest-increase treated state", {
  inputs <- make_spec_curve_inputs()
  result <- run_specification_curve(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table)

  # California's 0.3 increase is below the 0.50 cut, so its exposure value
  # (0.15 at the 12.5% band) should be absent from the subsample fit but
  # present in the full-sample fit -- checked indirectly via the two
  # samples producing different beta4 estimates for the same
  # bandwidth/industry cell (identical estimates would mean the filter
  # silently did nothing).
  full <- result %>% dplyr::filter(sample == "full 20-state sample", bandwidth == "12.5%", industry == "food_service")
  sub <- result %>% dplyr::filter(sample == ">=$0.50 subsample", bandwidth == "12.5%", industry == "food_service")
  expect_false(isTRUE(all.equal(full$beta4, sub$beta4)))
})
