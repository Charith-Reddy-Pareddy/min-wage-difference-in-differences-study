# Day 5: Model A (binary DiD) and Model C (exposure interaction), Section
# 6.2. This is the study's actual identification strategy -- unlike the
# SLR/MLR (Day 4), which were simple cross-sectional coursework pieces.
#
# Y(i,t) = b3[Treated(i)xPost(t)] + X(i,t)'g + a(i) + g(t) + e(i,t)   (A)
# Y(i,t) = b4[Treated(i)xPost(t)xExposure(i)] + b3[Treated(i)xPost(t)]
#          + Exposure(i) + X(i,t)'g + a(i) + g(t) + e(i,t)            (C)
#
# State and quarter two-way fixed effects, state-clustered SEs. "Exposure"
# is a state-industry constant (Day 3), so it and any main effect built
# from it get absorbed by the state fixed effect -- only its interaction
# with treated_post survives as an independently estimable term, which is
# exactly b4, the primary scientific hypothesis (Section 2).
#
# Sample: treated + control states only, matching the Day-4 correction --
# the "excluded" (later-2021-changer) group isn't a clean comparison group
# for a binary treated indicator. Uses the full computable panel
# (2016Q1-2022Q4; growth covariates need a 4-quarter lag, so 2015 is
# consumed establishing them) rather than the narrower 2019-2022 window
# from Day 4's simple pre/post comparison -- state/quarter fixed effects
# make the extra pre-period quarters useful rather than a liability, and
# whether parallel trends actually hold over that window is exactly what
# the Day 7 event study checks; this script doesn't assume the answer.

library(dplyr)
library(fixest)

#' Year-over-year log growth: log(value) at quarter q minus log(value) at
#' the same quarter one year earlier, matched by actual calendar date (not
#' a positional 4-row lag, which would silently misalign if the series had
#' a gap). NA wherever the prior-year quarter isn't in the data.
yoy_log_growth <- function(value, quarter) {
  log_by_quarter <- setNames(log(value), as.character(quarter))
  prior_year_quarter <- as.character(
    as.Date(paste0(as.integer(format(quarter, "%Y")) - 1, "-", format(quarter, "%m-%d")))
  )
  unname(log_by_quarter[as.character(quarter)] - log_by_quarter[prior_year_quarter])
}

#' State-quarter panel with growth covariates, treatment/post indicators,
#' and (for Model C) the state-industry exposure share. One row per
#' state-quarter; `outcome_col` picks which industry's employment series
#' becomes `log_employment`. `exposure_band_col` picks which exposure
#' bandwidth column to use (exposure_share_10/125/15) -- defaults to the
#' primary 12.5% band; R/17's bandwidth sensitivity check is the only
#' caller that overrides it.
build_panel <- function(fred_panel, treatment_table, exposure_table, industry, outcome_col,
                         treatment_effective = as.Date("2021-01-01"),
                         exposure_band_col = "exposure_share_125") {
  exposure_col <- exposure_table %>%
    filter(industry == !!industry) %>%
    select(state, exposure = all_of(exposure_band_col))

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
    inner_join(exposure_col, by = "state") %>%
    mutate(
      log_employment = log(.data[[outcome_col]]),
      treated = as.integer(group == "treated"),
      post = as.integer(quarter >= treatment_effective),
      treated_post = treated * post
    )
}

fit_model_a <- function(panel) {
  feols(log_employment ~ treated_post + gdp_growth + pop_growth | state + quarter,
        cluster = ~state, data = panel)
}

fit_model_c <- function(panel) {
  feols(log_employment ~ treated_post * exposure + gdp_growth + pop_growth | state + quarter,
        cluster = ~state, data = panel)
}

#' lm() + sandwich::vcovCL() cross-check for Model A -- same specification,
#' fixed effects as dummies instead of fixest's demeaning, clustered SEs
#' from a different implementation. Coefficients should match fixest
#' closely; this exists to catch a fixest-specific bug, not to replace it.
fit_model_a_lm_crosscheck <- function(panel) {
  lm(log_employment ~ treated_post + gdp_growth + pop_growth + factor(state) + factor(quarter),
     data = panel)
}

#' Proposal Section 4.2: the increase-type tag (legislated vs.
#' automatic/CPI-indexed) is carried as a labeled column through the
#' results tables, not just used as a filter. Counts treated states by
#' mechanism in a given (possibly already-filtered) treatment table.
count_treated_by_type <- function(treatment_table) {
  treated <- treatment_table %>% filter(group == "treated")
  list(
    n_legislated = sum(treated$increase_type == "legislation"),
    n_inflation_adjusted = sum(treated$increase_type %in% c("inflation_adj", "inflation_adj_paused"))
  )
}

if (sys.nframe() == 0) {
  source("R/01_treatment_classification.R")
  treatment_table <- load_treatment_table()
  fred_panel <- readr::read_csv("data/processed/fred_state_quarter.csv", show_col_types = FALSE)
  exposure_table <- readr::read_csv("data/processed/exposure_state_industry.csv", show_col_types = FALSE)

  results <- list()

  for (spec in list(
    list(label = "full 20-state treated sample", treatment_table = treatment_table),
    list(label = ">=$0.50-increase subsample", treatment_table = treatment_table %>%
           filter(group != "treated" | increase >= 0.50))
  )) {
    # In this data the >=$0.50 cut and the legislated-vs-automatic cut
    # turn out to be identical: the 10 states with >=$0.50 increases are
    # exactly the 10 "legislation"-type states (n_legislated ==
    # n_treated_states in that row below), so a separate legislated-only
    # model spec would just reproduce it -- the composition counts are
    # what makes the by-mechanism split visible instead.
    type_counts <- count_treated_by_type(spec$treatment_table)

    for (ind in list(
      list(industry = "food_service", col = "employment_food_service"),
      list(industry = "retail", col = "employment_retail")
    )) {
      panel <- build_panel(fred_panel, spec$treatment_table, exposure_table, ind$industry, ind$col)

      cat("\n============================================================\n")
      cat(spec$label, "--", ind$industry, "\n")
      cat("treated states:", n_distinct(panel$state[panel$treated == 1]),
          " control states:", n_distinct(panel$state[panel$treated == 0]), "\n")

      cat("\n--- Model A (fixest) ---\n")
      model_a <- fit_model_a(panel)
      print(summary(model_a))

      cat("\n--- Model A (lm + sandwich cross-check) ---\n")
      lm_a <- fit_model_a_lm_crosscheck(panel)
      vcov_cl <- sandwich::vcovCL(lm_a, cluster = panel$state)
      lm_a_se <- sqrt(vcov_cl["treated_post", "treated_post"])
      cat("treated_post: coef =", round(coef(lm_a)["treated_post"], 5),
          " clustered SE =", round(lm_a_se, 5), "\n")

      cat("\n--- Model C (fixest) ---\n")
      model_c <- fit_model_c(panel)
      print(summary(model_c))

      ct_a <- summary(model_a)$coeftable
      ct_c <- summary(model_c)$coeftable
      results[[paste(spec$label, ind$industry)]] <- tibble::tibble(
        sample = spec$label,
        industry = ind$industry,
        n_treated_states = n_distinct(panel$state[panel$treated == 1]),
        n_control_states = n_distinct(panel$state[panel$treated == 0]),
        n_legislated_treated = type_counts$n_legislated,
        n_inflation_adjusted_treated = type_counts$n_inflation_adjusted,
        model_a_treated_post = ct_a["treated_post", "Estimate"],
        model_a_se = ct_a["treated_post", "Std. Error"],
        model_a_p = ct_a["treated_post", "Pr(>|t|)"],
        model_a_lm_crosscheck_se = lm_a_se,
        model_c_beta4_treated_post_x_exposure = ct_c["treated_post:exposure", "Estimate"],
        model_c_beta4_se = ct_c["treated_post:exposure", "Std. Error"],
        model_c_beta4_p = ct_c["treated_post:exposure", "Pr(>|t|)"]
      )
    }
  }

  results_table <- dplyr::bind_rows(results)
  readr::write_csv(results_table, "data/processed/model_a_c_results.csv")
  cat("\n\n=== Summary across all 4 specifications ===\n")
  print(results_table, width = Inf)
}
