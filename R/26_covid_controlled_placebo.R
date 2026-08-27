# Post-build addition: R/25 found that pre-2021 exposure correlates
# significantly with COVID severity for both industries -- a candidate
# mechanism for why the beta4 placebo test (R/10), permutation test
# (R/15), and event study (R/08) all detect a pre-existing
# exposure-outcome association. This closes the loop directly: does
# adding covid_severity x post (R/09's own COVID-sensitivity covariate)
# to the placebo-date Model C specification make the spurious placebo
# beta4 shrink toward zero? If the COVID mechanism really explains the
# pre-existing association, controlling for it should absorb most of the
# placebo effect. If it doesn't, something else is also going on.
#
# covid_severity itself is computed from 2020 Q2/2019 Q4 FRED data --
# outside the 2016-2019 placebo window -- but that's fine here: it's used
# purely as a fixed state-level characteristic (how hard this state was
# eventually hit), the same way exposure itself is a fixed
# state-industry characteristic. The placebo window restriction still
# applies to which *quarters* enter the regression; only covid_severity's
# definition reaches outside it.

library(dplyr)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
  source("R/09_covid_sensitivity.R")
  source("R/10_placebo_test.R")
} else {
  source("../R/07_model_a_c.R")
  source("../R/09_covid_sensitivity.R")
  source("../R/10_placebo_test.R")
}

#' Placebo Model C (beta4) with covid_severity x post added -- same
#' add_covid_covariate() helper R/09 uses, since the placebo panel's own
#' `post` column (relative to the fake 2018 date) is exactly what should
#' interact with covid_severity here.
fit_placebo_model_c_covid_controlled <- function(panel) {
  feols(log_employment ~ placebo_treated_post * exposure + gdp_growth + pop_growth + covid_severity_x_post
        | state + quarter, cluster = ~state, data = panel)
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
    cat("COVID-controlled placebo, Model C (beta4) --", ind$industry, "\n")

    panel <- build_placebo_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    covid_severity <- compute_covid_severity(fred_panel, ind$col)
    panel_covid <- add_covid_covariate(panel, covid_severity)

    cat("\n--- Without covid_severity x post (R/10 baseline) ---\n")
    model_baseline <- fit_placebo_model_c(panel)
    ct_baseline <- fixest::coeftable(model_baseline)
    print(ct_baseline["placebo_treated_post:exposure", ])

    cat("\n--- With covid_severity x post ---\n")
    model_controlled <- fit_placebo_model_c_covid_controlled(panel_covid)
    ct_controlled <- fixest::coeftable(model_controlled)
    print(ct_controlled[c("placebo_treated_post:exposure", "covid_severity_x_post"), ])

    results[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      baseline_beta4 = ct_baseline["placebo_treated_post:exposure", "Estimate"],
      baseline_beta4_p = ct_baseline["placebo_treated_post:exposure", "Pr(>|t|)"],
      covid_controlled_beta4 = ct_controlled["placebo_treated_post:exposure", "Estimate"],
      covid_controlled_beta4_p = ct_controlled["placebo_treated_post:exposure", "Pr(>|t|)"]
    )
  }

  results_table <- dplyr::bind_rows(results) %>%
    mutate(pct_shrinkage = 100 * (1 - abs(covid_controlled_beta4) / abs(baseline_beta4)))
  readr::write_csv(results_table, "data/processed/covid_controlled_placebo_results.csv")
  cat("\n\n=== COVID-controlled placebo summary (beta4) ===\n")
  print(results_table, width = Inf)
}
