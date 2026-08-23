# Exploratory treatment-intensity analysis (added post-build). This is
# "Model B" from the original 8-week proposal, cut from scope to fit the
# 10-day compressed build (see TIMELINE.md and the proposal's Section 14).
#
# Question: does a LARGER minimum-wage increase correspond to a larger
# employment response, rather than just binary treated-vs-not?
#
#   Y(i,t) = beta1[wage_increase(i) x post(t)] + alpha(i) + gamma(t) + e(i,t)
#
# Labeled exploratory, not confirmatory: the dollar size of a state's
# increase is not randomly assigned -- states that raise wages by $1.00
# vs. $0.08 may differ systematically in ways unrelated to the policy
# itself (political composition, cost of living, existing wage levels).
# Model A/C's binary treated/control comparison at least has a cleaner
# "did anything change" comparison; this one asks a more informative but
# less identified question. Not part of the confirmatory family
# (Section 12 of the proposal / this report).

library(dplyr)
library(fixest)

if (file.exists("R/07_model_a_c.R")) {
  source("R/07_model_a_c.R")
} else {
  source("../R/07_model_a_c.R")
}

#' Same panel-building logic as build_panel(), but keeps the continuous
#' dollar `increase` amount (post-interacted) instead of collapsing to a
#' binary treated indicator. Excluded states dropped, same as Model A/C.
build_intensity_panel <- function(fred_panel, treatment_table, outcome_col,
                                   treatment_effective = as.Date("2021-01-01")) {
  fred_panel %>%
    group_by(state) %>%
    arrange(quarter, .by_group = TRUE) %>%
    mutate(
      gdp_growth = yoy_log_growth(gdp, quarter),
      pop_growth = yoy_log_growth(population, quarter)
    ) %>%
    ungroup() %>%
    filter(!is.na(gdp_growth)) %>%
    inner_join(treatment_table %>% select(state, group, increase), by = "state") %>%
    filter(group != "excluded") %>%
    mutate(
      log_employment = log(.data[[outcome_col]]),
      post = as.integer(quarter >= treatment_effective),
      wage_increase_post = increase * post
    )
}

fit_treatment_intensity <- function(panel) {
  feols(log_employment ~ wage_increase_post + gdp_growth + pop_growth | state + quarter,
        cluster = ~state, data = panel)
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)

  results <- list()
  for (ind in list(
    list(industry = "food_service", col = "employment_food_service"),
    list(industry = "retail", col = "employment_retail")
  )) {
    cat("\n============================================================\n")
    cat("Exploratory treatment-intensity model --", ind$industry, "\n")

    panel <- build_intensity_panel(fred_panel, treatment_table, ind$col)
    model <- fit_treatment_intensity(panel)
    print(summary(model))

    ct <- fixest::coeftable(model)
    results[[ind$industry]] <- tibble::tibble(
      industry = ind$industry,
      beta1_wage_increase_post = ct["wage_increase_post", "Estimate"],
      beta1_se = ct["wage_increase_post", "Std. Error"],
      beta1_p = ct["wage_increase_post", "Pr(>|t|)"]
    )
  }

  results_table <- dplyr::bind_rows(results)
  readr::write_csv(results_table, "data/processed/treatment_intensity_results.csv")
  cat("\n\n=== Exploratory treatment-intensity summary (NOT part of the confirmatory family) ===\n")
  print(results_table, width = Inf)
}
