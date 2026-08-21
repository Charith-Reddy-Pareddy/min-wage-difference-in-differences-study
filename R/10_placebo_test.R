# Day 8: placebo test using a false pre-treatment date (Section 6.4).
#
# Restricts the panel to 2016Q1-2019Q4 -- pre-COVID and well before the
# real 2021Q1 treatment -- and pretends treatment happened on 2018-01-01
# instead. If the design is sound, there's no real policy change at that
# fake date, so the placebo treated_post estimate should come back small
# and statistically indistinguishable from zero.
#
# The window deliberately excludes 2020: Day 7 already found a real,
# COVID-driven anomaly at 2020 Q2, so a placebo window that included it
# would be testing "does this design pick up a shock we already know
# about" rather than "does this design manufacture effects from nothing."
# Reuses build_panel() from R/07 (it already accepts a configurable
# treatment_effective date) rather than a second implementation.

library(dplyr)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../R/07_model_a_c.R")
}

PLACEBO_DATE <- as.Date("2018-01-01")
PLACEBO_WINDOW_START <- as.Date("2016-01-01")
PLACEBO_WINDOW_END <- as.Date("2019-10-01")

#' Same panel Model A/C use, but with a false treatment date and
#' restricted to a pre-COVID, pre-real-treatment window.
build_placebo_panel <- function(fred_panel, treatment_table, exposure_table, industry, outcome_col) {
  build_panel(fred_panel, treatment_table, exposure_table, industry, outcome_col,
              treatment_effective = PLACEBO_DATE) %>%
    filter(quarter >= PLACEBO_WINDOW_START, quarter <= PLACEBO_WINDOW_END) %>%
    rename(placebo_treated_post = treated_post)
}

fit_placebo_model <- function(panel) {
  feols(log_employment ~ placebo_treated_post + gdp_growth + pop_growth | state + quarter,
        cluster = ~state, data = panel)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  results <- list()

  for (ind in list(
    list(industry = "food_service", col = "employment_food_service"),
    list(industry = "retail", col = "employment_retail")
  )) {
    cat("\n============================================================\n")
    cat("Placebo test --", ind$industry, "(false treatment date:", format(PLACEBO_DATE), ")\n")

    panel <- build_placebo_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    cat("Panel window:", format(min(panel$quarter)), "to", format(max(panel$quarter)),
        " (", n_distinct(panel$quarter), "quarters )\n")

    model <- fit_placebo_model(panel)
    print(summary(model))

    ct <- summary(model)$coeftable
    results[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      placebo_date = PLACEBO_DATE,
      placebo_treated_post = ct["placebo_treated_post", "Estimate"],
      placebo_se = ct["placebo_treated_post", "Std. Error"],
      placebo_p = ct["placebo_treated_post", "Pr(>|t|)"]
    )
  }

  results_table <- dplyr::bind_rows(results)
  readr::write_csv(results_table, "data/processed/placebo_test_results.csv")
  cat("\n\n=== Placebo test summary ===\n")
  print(results_table, width = Inf)
}
