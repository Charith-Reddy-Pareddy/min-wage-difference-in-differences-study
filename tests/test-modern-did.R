library(testthat)
source("../R/01_treatment_classification.R")
source("../R/07_model_a_c.R")
source("../R/32_modern_did.R")

make_tercile_test_panel <- function(n_per_state = 20) {
  # 9 states, 3 per exposure tercile (a genuinely even split, so the
  # sample quantile cutpoints fall cleanly between groups rather than on
  # a boundary value -- an uneven 3/4/4 split with n=11 turned out to
  # place the low/mid cutpoint's quantile interpolation ABOVE the lowest
  # mid-tercile value, silently pulling a treated state into "low").
  # Low is all control (0 treated); mid and high each have 2 treated,
  # 1 control -- enough states per bin for fixest to actually separate
  # state FE from the treated_post/tercile terms (a single treated state
  # per bin was too thin: fixest flagged everything collinear rather
  # than just the expected "low" contrast). Zero treated states in "low"
  # reproduces the real coverage gap found in the actual panel (see
  # add_exposure_tercile's docstring).
  states <- tibble::tibble(
    state = paste0("S", 1:9),
    exposure_share_125 = c(0.10, 0.11, 0.12, 0.50, 0.51, 0.52, 0.90, 0.91, 0.92),
    group = c("control", "control", "control", "treated", "treated", "control",
              "treated", "treated", "control"),
    increase = c(0, 0, 0, 1, 1, 0, 1, 1, 0)
  )
  quarters <- seq(as.Date("2019-01-01"), by = "quarter", length.out = n_per_state)
  quarter_index <- seq_along(quarters)
  # build_panel's default; matters here because build_panel drops the
  # first 4 quarters entirely (gdp_growth/pop_growth need a 4-quarter
  # lag -- see R/07's yoy_log_growth). With only 20 quarters and
  # treatment at index 9 (2021 Q1), the surviving post-trim panel still
  # has a real pre-period (indices 5-8) as well as post (9-20) -- an
  # earlier version of this fixture set treatment_effective right at the
  # trim boundary, leaving zero surviving pre-period rows, which made
  # `post` -- and therefore treated_post -- perfectly collinear with the
  # state fixed effect. fixest's collinearity message didn't say why;
  # this comment is the why.
  treatment_effective <- as.Date("2021-01-01")

  # A shared quarter_index trend alone would be fully absorbed by the
  # quarter fixed effect, leaving zero residual variation for state+quarter
  # FE to explain -- the exact degenerate-regression failure mode already
  # documented in tests/test-model-a-c.R's restricted-model test. Per-state
  # noise (seeded, so the fixture is still deterministic) gives state+
  # quarter FE real variation to work with, and a fixed +5% treated_post
  # jump (common across bins) gives fit_binned_dose_response's "high vs
  # mid" contrast a known answer (~0) to check against.
  set.seed(32)
  fred_panel <- states %>%
    tidyr::crossing(quarter = quarters) %>%
    dplyr::group_by(state) %>%
    dplyr::mutate(
      is_treated_post = group == "treated" & quarter >= treatment_effective,
      employment_food_service = 100 * 1.01^quarter_index * ifelse(is_treated_post, 1.05, 1) *
        exp(rnorm(dplyr::n(), sd = 0.02)),
      employment_retail = 200 * 1.01^quarter_index * ifelse(is_treated_post, 1.05, 1) *
        exp(rnorm(dplyr::n(), sd = 0.02)),
      gdp = 1000 * 1.005^quarter_index * exp(rnorm(dplyr::n(), sd = 0.01)),
      population = 5000 * 1.001^quarter_index * exp(rnorm(dplyr::n(), sd = 0.01))
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(state, quarter, employment_food_service, employment_retail, gdp, population)

  treatment_table <- states %>% dplyr::select(state, group, increase)
  exposure_table <- tidyr::crossing(
    states %>% dplyr::select(state, exposure_share_125),
    industry = c("food_service", "retail")
  )

  list(fred_panel = fred_panel, treatment_table = treatment_table, exposure_table = exposure_table)
}

make_test_panel <- function() {
  inputs <- make_tercile_test_panel()
  build_panel(inputs$fred_panel, inputs$treatment_table, inputs$exposure_table,
              "food_service", "employment_food_service") # default treatment_effective: 2021-01-01
}

test_that("add_exposure_tercile bins into three groups and makes mid the reference level", {
  panel <- make_test_panel()
  tercile_panel <- add_exposure_tercile(panel)

  expect_setequal(levels(tercile_panel$exposure_tercile), c("low", "mid", "high"))
  expect_equal(levels(tercile_panel$exposure_tercile)[1], "mid") # relevel() puts ref first
})

test_that("count_treated_states_per_tercile counts distinct states, not state-quarters", {
  panel <- make_test_panel()
  counts <- count_treated_states_per_tercile(panel)

  # 11 states in the fixture, regardless of how many quarters each
  # contributes to the panel.
  expect_equal(sum(counts$n_states), 9)
  expect_equal(counts$n_states[counts$treated == 1 & counts$exposure_tercile == "low"], integer(0))
})

test_that("coef_or_na returns the estimate when the term is present", {
  fake_coeftable <- matrix(c(1.5, 0.2), nrow = 1, dimnames = list("treated_post", c("Estimate", "Std. Error")))
  expect_equal(coef_or_na(fake_coeftable, "treated_post"), 1.5)
})

test_that("coef_or_na returns NA instead of erroring when the term was dropped", {
  fake_coeftable <- matrix(c(1.5, 0.2), nrow = 1, dimnames = list("treated_post", c("Estimate", "Std. Error")))
  expect_true(is.na(coef_or_na(fake_coeftable, "treated_post:exposure_tercilelow")))
})

test_that("fit_binned_dose_response runs without erroring when a tercile has zero treated states", {
  # This is the actual bug: with zero treated states in "low", fixest
  # drops the low-tercile interaction for collinearity, and the runner
  # script used to crash trying to index that dropped row directly.
  # This test would fail with the same "subscript out of bounds" error
  # the real run hit, if coef_or_na's guard were removed.
  panel <- make_test_panel()
  model <- fit_binned_dose_response(panel)
  ct <- summary(model)$coeftable

  expect_true("treated_post" %in% rownames(ct))
  expect_true("treated_post:exposure_tercilehigh" %in% rownames(ct))
  expect_false("treated_post:exposure_tercilelow" %in% rownames(ct))
  expect_true(is.na(coef_or_na(ct, "treated_post:exposure_tercilelow")))
  # The fixture builds in the same +5% treated_post jump for every
  # treated state regardless of tercile, so the mid-tercile baseline
  # should recover ~log(1.05) and the high-vs-mid contrast should be ~0.
  expect_equal(unname(coef_or_na(ct, "treated_post")), log(1.05), tolerance = 0.05)
  expect_equal(unname(coef_or_na(ct, "treated_post:exposure_tercilehigh")), 0, tolerance = 0.05)
})

test_that("fit_high_vs_low drops the middle tercile", {
  panel <- make_test_panel()
  model <- fit_high_vs_low(panel)

  # The 4 mid-tercile states (exposure 0.5) should contribute no rows.
  n_states_in_model <- length(fixest::fixef(model)$state)
  expect_equal(n_states_in_model, 6) # 3 low + 3 high
})
