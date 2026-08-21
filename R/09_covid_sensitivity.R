# Day 7: COVID-sensitivity covariate spec (Section 6.5's "supporting
# check: a single sensitivity specification adding 2020 employment
# decline as a covariate to Model A and Model C").
#
# The proposal doesn't spell out the functional form, and it matters:
# "2020 employment decline" is a state-industry constant (like exposure
# in Model C), so added as a bare main effect it would be fully absorbed
# by the state fixed effect already in Model A/C and have literally zero
# effect on any other coefficient -- the same collinearity R/07 already
# hit with exposure's own main effect. The meaningful version has to let
# COVID severity have a *time-varying* effect, so it's added the same way
# exposure enters Model C: interacted with post. covid_severity x post is
# a state-industry-specific post-2021 level shift proportional to how
# hard COVID hit that state-industry -- exactly the kind of confound
# Section 6.5 is worried about (states recovering differently from COVID
# for reasons unrelated to minimum wage, coinciding with the 2021
# treatment window).
#
# covid_severity is defined the same way the event study identified the
# shock: log(employment at 2020 Q2, the trough) - log(employment at
# 2019 Q4, the last pre-COVID quarter). More negative = harder hit.

library(dplyr)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../R/07_model_a_c.R")
}

PRE_COVID_QUARTER <- as.Date("2019-10-01")
COVID_TROUGH_QUARTER <- as.Date("2020-04-01")

#' log(employment at the COVID trough) - log(employment at the last
#' pre-COVID quarter), per state. Uses two filtered lookups joined by
#' state rather than pivot_wider, so a state (or an entire quarter)
#' missing from the data comes back as NA instead of an error -- with
#' pivot_wider, a quarter absent for every state means that column never
#' gets created at all, and the lookup below would fail outright.
compute_covid_severity <- function(fred_panel, outcome_col) {
  pre <- fred_panel %>%
    filter(quarter == PRE_COVID_QUARTER) %>%
    select(state, pre_value = all_of(outcome_col))
  trough <- fred_panel %>%
    filter(quarter == COVID_TROUGH_QUARTER) %>%
    select(state, trough_value = all_of(outcome_col))

  full_join(pre, trough, by = "state") %>%
    transmute(state, covid_severity = log(trough_value) - log(pre_value))
}

#' Adds covid_severity x post to an existing Model A/C panel.
add_covid_covariate <- function(panel, covid_severity) {
  panel %>%
    inner_join(covid_severity, by = "state") %>%
    mutate(covid_severity_x_post = covid_severity * post)
}

fit_model_a_covid <- function(panel) {
  fixest::feols(
    log_employment ~ treated_post + gdp_growth + pop_growth + covid_severity_x_post | state + quarter,
    cluster = ~state, data = panel
  )
}

fit_model_c_covid <- function(panel) {
  fixest::feols(
    log_employment ~ treated_post * exposure + gdp_growth + pop_growth + covid_severity_x_post | state + quarter,
    cluster = ~state, data = panel
  )
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
    cat("COVID-sensitivity spec --", ind$industry, "(full 20-state treated sample)\n")

    panel <- build_panel(fred_panel, treatment_table, exposure_table, ind$industry, ind$col)
    covid_severity <- compute_covid_severity(fred_panel, ind$col)
    panel_covid <- add_covid_covariate(panel, covid_severity)

    cat("\ncovid_severity range:", round(range(covid_severity$covid_severity), 3), "\n")

    cat("\n--- Model A, without COVID covariate (Day 5 baseline) ---\n")
    model_a <- fit_model_a(panel)
    print(fixest::coeftable(model_a)["treated_post", ])

    cat("\n--- Model A, with covid_severity x post ---\n")
    model_a_covid <- fit_model_a_covid(panel_covid)
    print(fixest::coeftable(model_a_covid)[c("treated_post", "covid_severity_x_post"), ])

    cat("\n--- Model C, without COVID covariate (Day 5 baseline) ---\n")
    model_c <- fit_model_c(panel)
    print(fixest::coeftable(model_c)["treated_post:exposure", ])

    cat("\n--- Model C, with covid_severity x post ---\n")
    model_c_covid <- fit_model_c_covid(panel_covid)
    print(fixest::coeftable(model_c_covid)[c("treated_post:exposure", "covid_severity_x_post"), ])

    results[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      model_a_treated_post_baseline = coef(model_a)["treated_post"],
      model_a_treated_post_covid_spec = coef(model_a_covid)["treated_post"],
      model_c_beta4_baseline = coef(model_c)["treated_post:exposure"],
      model_c_beta4_covid_spec = coef(model_c_covid)["treated_post:exposure"]
    )
  }

  results_table <- dplyr::bind_rows(results)
  readr::write_csv(results_table, "data/processed/covid_sensitivity_results.csv")
  cat("\n\n=== Baseline vs. COVID-sensitivity spec, treated_post and beta4 ===\n")
  print(results_table, width = Inf)
}
